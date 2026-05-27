--!strict
--[[
    MovementController (parkour rewrite)
    Mirror's Edge / Parkour-inspired movement.

    State machine:
        Grounded    - default, constant sprint baseline, auto-vault detection
        Sliding     - momentum-based slide with friction decay (works in air too)
        Airborne    - after jump or walking off ledge, wallrun + mantle detection
        WallRunning - locked to a vertical surface, forward velocity along wall
        Vaulting    - ballistic arc over a knee-high obstacle
        Mantling    - ballistic climb onto a ledge from air

    Jump handling:
        Humanoid.JumpPower = 0 so we own the jump. Space enters jump manually:
            Grounded / within coyote time    -> velocity jump (+ momentum boost from slide)
            WallRunning                      -> walljump away + up + forward
            Airborne with DoubleJump powerup -> powerup consumed
        Space pressed shortly before landing is buffered and fires on touchdown.

    State changes are broadcast via self.StateChanged so MovementCameraController
    can drive FOV / roll / offset effects in sync.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

--// Shared
local Config = require(ReplicatedStorage.Shared.Modules.MovementConfig)

--// Constants
local SPEED_BOOST_ATTRIBUTE = "SpeedBoostMult"
local DOUBLE_JUMP_ATTRIBUTE = "HasDoubleJump"
-- DoubleJumpExpiresAt also lives on the humanoid but is consulted only by the
-- server (its os.clock() is consistent with the apply-time). The client used to
-- read it too and reject the jump if expired, but os.clock() is per-process
-- uptime — server and client clocks don't share an origin — so a client whose
-- process had been running longer than the server's would silently see every
-- pickup as already-expired. Server-side task.delay handles the timeout now.

--// Types
export type State = "Grounded" | "Sliding" | "Airborne" | "WallRunning" | "Vaulting" | "Mantling"

export type WallSide = "Left" | "Right"

type WallProbe = {
    instance: BasePart,
    normal: Vector3,
    side: WallSide,
    position: Vector3,
}

--// Module
local MovementController = Knit.CreateController({
    Name = "MovementController",

    _state = "Grounded" :: State,
    _character = nil :: Model?,
    _humanoid = nil :: Humanoid?,
    _rootPart = nil :: BasePart?,

    -- Slide
    _slideSpeed = 0,
    _slideEndTime = 0,

    -- Jump timing
    _lastGroundedTime = 0,
    _jumpBufferedUntil = 0,

    -- Vault / Mantle
    _vaultEndTime = 0,
    _vaultCooldownUntil = 0,
    _mantleEndTime = 0,
    _mantleCooldownUntil = 0,

    -- Wallrun
    _wallSide = "Left" :: WallSide,
    _wallNormal = Vector3.zero,
    _wallrunEndTime = 0,
    _wallrunCooldownUntil = 0,
    _wallrunSpeed = 0,

    -- Bunny chain (slide-jump-slide momentum stack)
    _chainBonus = 0,
    _chainExpireTime = 0,

    -- Peak horizontal speed since last grounded; survives wall collisions
    -- so wallrun/walljump can recover the pre-collision momentum.
    _peakAirSpeed = 0,

    StateChanged = Signal.new(),
})

--// Forward declarations
local PowerupService

--// Private helpers

local function horizontalize(vec: Vector3): Vector3
    local flat = Vector3.new(vec.X, 0, vec.Z)
    if flat.Magnitude < 1e-4 then
        return Vector3.zero
    end
    return flat.Unit
end

function MovementController:_raycastParams(): RaycastParams
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { self._character }
    params.IgnoreWater = true
    return params
end

function MovementController:_speedMultiplier(): number
    local humanoid = self._humanoid
    if not humanoid then
        return 1
    end
    local mult = humanoid:GetAttribute(SPEED_BOOST_ATTRIBUTE)
    if typeof(mult) == "number" and mult > 0 then
        return mult
    end
    return 1
end

function MovementController:_isStunned(): boolean
    local humanoid = self._humanoid
    if not humanoid then
        return false
    end
    return humanoid:GetAttribute("Stunned") == true
end

function MovementController:_isGroundedHumanoidState(): boolean
    local humanoid = self._humanoid
    if not humanoid then
        return false
    end
    local state = humanoid:GetState()
    return state == Enum.HumanoidStateType.Running
        or state == Enum.HumanoidStateType.Landed
        or state == Enum.HumanoidStateType.RunningNoPhysics
end

function MovementController:_setState(newState: State)
    if newState == self._state then
        return
    end
    local oldState = self._state
    self._state = newState
    if newState == "Grounded" then
        self._peakAirSpeed = 0
    end
    self.StateChanged:Fire(newState, oldState)
end

function MovementController:GetState(): State
    return self._state
end

function MovementController:GetWallSide(): WallSide
    return self._wallSide
end

--// Slide

function MovementController:_startSlide()
    local humanoid = self._humanoid
    local rootPart = self._rootPart
    if not humanoid or not rootPart then
        return
    end

    local lookVec = rootPart.CFrame.LookVector
    local horizontal = horizontalize(lookVec)
    local currentHorizontalSpeed = horizontalize(rootPart.AssemblyLinearVelocity).Magnitude

    local now = os.clock()
    if now <= self._chainExpireTime then
        self._chainBonus =
            math.min(self._chainBonus + Config.BunnyChain.BonusPerLink, Config.BunnyChain.MaxBonus)
    else
        self._chainBonus = 0
    end

    local baseSpeed = math.max(Config.Slide.InitialSpeed, currentHorizontalSpeed + 6)
    self._slideSpeed = baseSpeed + self._chainBonus
    self._slideEndTime = now + Config.Slide.MaxDuration

    humanoid.WalkSpeed = 0
    humanoid.HipHeight = humanoid.HipHeight - Config.Slide.HipHeightDrop

    local vy = rootPart.AssemblyLinearVelocity.Y
    rootPart.AssemblyLinearVelocity =
        Vector3.new(horizontal.X * self._slideSpeed, vy, horizontal.Z * self._slideSpeed)

    self:_setState("Sliding")
end

function MovementController:_endSlide(goAirborne: boolean?)
    if self._state ~= "Sliding" then
        return
    end
    local humanoid = self._humanoid
    if humanoid then
        humanoid.HipHeight = humanoid.HipHeight + Config.Slide.HipHeightDrop
        humanoid.WalkSpeed = Config.Run.Speed * self:_speedMultiplier()
    end
    self._slideSpeed = 0

    if goAirborne or not self:_isGroundedHumanoidState() then
        self:_setState("Airborne")
    else
        self:_setState("Grounded")
    end
end

function MovementController:_updateSlide(dt: number)
    if self._state ~= "Sliding" then
        return
    end
    local rootPart = self._rootPart
    if not rootPart then
        return
    end

    self._slideSpeed = math.max(0, self._slideSpeed - Config.Slide.Friction * dt)

    local horizontal = horizontalize(rootPart.CFrame.LookVector)
    local vy = rootPart.AssemblyLinearVelocity.Y
    rootPart.AssemblyLinearVelocity =
        Vector3.new(horizontal.X * self._slideSpeed, vy, horizontal.Z * self._slideSpeed)

    if self._slideSpeed < Config.Slide.ExitSpeed or os.clock() > self._slideEndTime then
        self:_endSlide()
    end
end

--// Jump / Coyote / Buffer

function MovementController:_executeJump(isBuffered: boolean?)
    local humanoid = self._humanoid
    local rootPart = self._rootPart
    if not humanoid or not rootPart then
        return
    end

    local wasSliding = self._state == "Sliding"
    if wasSliding then
        self:_endSlide(true)
        self._chainExpireTime = os.clock() + Config.BunnyChain.Window
    end

    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

    local v = rootPart.AssemblyLinearVelocity
    local forwardBoost = if wasSliding then Config.Momentum.SlideJumpForwardBoost else 0
    local forward = horizontalize(rootPart.CFrame.LookVector)
    rootPart.AssemblyLinearVelocity = Vector3.new(
        v.X + forward.X * forwardBoost,
        Config.Jump.Velocity,
        v.Z + forward.Z * forwardBoost
    )

    self._lastGroundedTime = 0
    self._jumpBufferedUntil = 0
    self:_setState("Airborne")
    local _ = isBuffered -- unused for now, future sound/animation hook
end

function MovementController:_tryJump()
    if self._state == "Vaulting" or self._state == "Mantling" then
        return
    end

    if self._state == "WallRunning" then
        self:_walljump()
        return
    end

    self._jumpBufferedUntil = os.clock() + Config.Jump.BufferTime

    local grounded = self:_isGroundedHumanoidState()
    local withinCoyote = (os.clock() - self._lastGroundedTime) <= Config.Jump.CoyoteTime

    if grounded or withinCoyote then
        self:_executeJump(false)
        return
    end

    self:_tryDoubleJump()
end

function MovementController:_tryDoubleJump()
    local humanoid = self._humanoid
    local rootPart = self._rootPart
    if not humanoid or not rootPart or not PowerupService then
        return
    end
    if humanoid:GetAttribute(DOUBLE_JUMP_ATTRIBUTE) ~= true then
        return
    end
    -- No client-side expiry check: see the constants block. Server's
    -- task.delay clears the attribute when the powerup window ends, and
    -- ConsumeDoubleJump validates again before granting the jump.

    -- Preserve peak air horizontal speed; Roblox's humanoid air-control
    -- bleeds momentum down toward WalkSpeed while flying, so we restore
    -- the pre-deceleration magnitude in the player's current direction.
    local v = rootPart.AssemblyLinearVelocity
    local horiz = Vector3.new(v.X, 0, v.Z)
    local mag = horiz.Magnitude
    if mag > 0.01 and self._peakAirSpeed > mag then
        horiz = horiz.Unit * self._peakAirSpeed
    end

    rootPart.AssemblyLinearVelocity = Vector3.new(horiz.X, Config.DoubleJump.Velocity, horiz.Z)
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    PowerupService.UseDoubleJump:Fire()
end

--// Vault

function MovementController:_tryVault()
    if self._state ~= "Grounded" then
        return
    end
    if os.clock() < self._vaultCooldownUntil then
        return
    end
    local rootPart = self._rootPart
    if not rootPart then
        return
    end

    local origin = rootPart.Position
    local lookVector = rootPart.CFrame.LookVector
    local params = self:_raycastParams()

    local lowHit = Workspace:Raycast(
        origin + Vector3.new(0, Config.Vault.LowRayHeight, 0),
        lookVector * Config.Vault.CheckDistance,
        params
    )
    if not lowHit then
        return
    end

    local highHit = Workspace:Raycast(
        origin + Vector3.new(0, Config.Vault.HighRayHeight, 0),
        lookVector * Config.Vault.CheckDistance,
        params
    )
    if highHit then
        return
    end

    local horizontal = horizontalize(lookVector)
    if horizontal.Magnitude < 0.1 then
        return
    end

    rootPart.AssemblyLinearVelocity = Vector3.new(
        horizontal.X * Config.Vault.ForwardSpeed,
        Config.Vault.UpwardSpeed,
        horizontal.Z * Config.Vault.ForwardSpeed
    )
    self._vaultEndTime = os.clock() + Config.Vault.Duration
    self._vaultCooldownUntil = os.clock() + Config.Vault.Cooldown
    self:_setState("Vaulting")
end

function MovementController:_updateVault()
    if self._state ~= "Vaulting" then
        return
    end
    if os.clock() > self._vaultEndTime then
        self:_setState("Airborne")
    end
end

--// Mantle

function MovementController:_tryMantle()
    if self._state ~= "Airborne" then
        return
    end
    if os.clock() < self._mantleCooldownUntil then
        return
    end
    local rootPart = self._rootPart
    if not rootPart then
        return
    end

    local origin = rootPart.Position
    local lookVector = rootPart.CFrame.LookVector
    local params = self:_raycastParams()

    local wallHit = Workspace:Raycast(origin, lookVector * Config.Mantle.CheckDistance, params)
    if not wallHit then
        return
    end

    local upperHit = Workspace:Raycast(
        origin + Vector3.new(0, Config.Mantle.UpperRayHeight, 0),
        lookVector * Config.Mantle.CheckDistance,
        params
    )
    if upperHit then
        return
    end

    local horizontal = horizontalize(lookVector)
    if horizontal.Magnitude < 0.1 then
        return
    end

    rootPart.AssemblyLinearVelocity = Vector3.new(
        horizontal.X * Config.Mantle.ForwardSpeed,
        Config.Mantle.UpwardSpeed,
        horizontal.Z * Config.Mantle.ForwardSpeed
    )
    self._mantleEndTime = os.clock() + Config.Mantle.Duration
    self._mantleCooldownUntil = os.clock() + Config.Mantle.Cooldown
    self:_setState("Mantling")
end

function MovementController:_updateMantle()
    if self._state ~= "Mantling" then
        return
    end
    if os.clock() > self._mantleEndTime then
        self:_setState("Airborne")
    end
end

--// Wallrun

function MovementController:_probeWalls(): WallProbe?
    local rootPart = self._rootPart
    if not rootPart then
        return nil
    end
    local params = self:_raycastParams()
    local pos = rootPart.Position
    local rightVec = rootPart.CFrame.RightVector

    local rightHit = Workspace:Raycast(pos, rightVec * Config.Wallrun.CheckDistance, params)
    if rightHit and math.abs(rightHit.Normal.Y) < Config.Wallrun.MaxWallNormalY then
        return {
            instance = rightHit.Instance,
            normal = rightHit.Normal,
            side = "Right",
            position = rightHit.Position,
        }
    end

    local leftHit = Workspace:Raycast(pos, -rightVec * Config.Wallrun.CheckDistance, params)
    if leftHit and math.abs(leftHit.Normal.Y) < Config.Wallrun.MaxWallNormalY then
        return {
            instance = leftHit.Instance,
            normal = leftHit.Normal,
            side = "Left",
            position = leftHit.Position,
        }
    end

    return nil
end

function MovementController:_alongWallDirection(normal: Vector3): Vector3
    local rootPart = self._rootPart
    if not rootPart then
        return Vector3.zero
    end
    -- Two candidates: perpendicular to normal in the horizontal plane
    local candidate = Vector3.new(-normal.Z, 0, normal.X)
    local lookHorizontal = horizontalize(rootPart.CFrame.LookVector)
    if candidate:Dot(lookHorizontal) < 0 then
        candidate = -candidate
    end
    if candidate.Magnitude < 1e-4 then
        return Vector3.zero
    end
    return candidate.Unit
end

function MovementController:_tryStartWallrun()
    if self._state ~= "Airborne" then
        return
    end
    if os.clock() < self._wallrunCooldownUntil then
        return
    end
    local humanoid = self._humanoid
    local rootPart = self._rootPart
    if not humanoid or not rootPart then
        return
    end

    local v = rootPart.AssemblyLinearVelocity
    local horizontalSpeed = Vector3.new(v.X, 0, v.Z).Magnitude
    if horizontalSpeed < Config.Wallrun.MinEntrySpeed then
        return
    end
    if v.Y > Config.Wallrun.MaxEntryRiseSpeed then
        return
    end

    local probe = self:_probeWalls()
    if not probe then
        return
    end

    self._wallNormal = probe.normal
    self._wallSide = probe.side
    self._wallrunEndTime = os.clock() + Config.Wallrun.MaxDuration
    self._wallrunSpeed = math.max(horizontalSpeed, self._peakAirSpeed, Config.Wallrun.Speed)

    humanoid.WalkSpeed = 0
    humanoid.AutoRotate = true

    self:_setState("WallRunning")
end

function MovementController:_updateWallrun(_dt: number)
    if self._state ~= "WallRunning" then
        return
    end
    local humanoid = self._humanoid
    local rootPart = self._rootPart
    if not humanoid or not rootPart then
        return
    end

    local probe = self:_probeWalls()
    if not probe or probe.side ~= self._wallSide then
        self:_endWallrun()
        return
    end

    self._wallNormal = probe.normal
    local alongDir = self:_alongWallDirection(probe.normal)
    if alongDir.Magnitude < 1e-4 then
        self:_endWallrun()
        return
    end

    rootPart.AssemblyLinearVelocity = Vector3.new(
        alongDir.X * self._wallrunSpeed - probe.normal.X * Config.Wallrun.StickForce,
        Config.Wallrun.VerticalHoldVelocity,
        alongDir.Z * self._wallrunSpeed - probe.normal.Z * Config.Wallrun.StickForce
    )

    if os.clock() > self._wallrunEndTime then
        self:_endWallrun()
    end
end

function MovementController:_endWallrun()
    if self._state ~= "WallRunning" then
        return
    end
    local humanoid = self._humanoid
    if humanoid then
        humanoid.WalkSpeed = Config.Run.Speed * self:_speedMultiplier()
        humanoid.AutoRotate = true
    end
    self._wallrunCooldownUntil = os.clock() + Config.Wallrun.Cooldown
    self:_setState("Airborne")
end

function MovementController:_walljump()
    if self._state ~= "WallRunning" then
        return
    end
    local humanoid = self._humanoid
    local rootPart = self._rootPart
    if not humanoid or not rootPart then
        return
    end

    local awayDir = self._wallNormal
    local forward = horizontalize(rootPart.CFrame.LookVector)
    if forward.Magnitude < 0.1 then
        forward = awayDir
    end

    -- Preserve incoming horizontal velocity and ADD walljump impulse on top.
    -- Faster wallrun -> faster walljump -> farther jump. Aim where you want
    -- to go to compound the away+forward push with your existing momentum.
    local v = rootPart.AssemblyLinearVelocity
    local awayBoost = awayDir * Config.Walljump.AwaySpeed
    local forwardBoost = forward * Config.Walljump.ForwardSpeed

    rootPart.AssemblyLinearVelocity = Vector3.new(
        v.X + awayBoost.X + forwardBoost.X,
        Config.Walljump.UpSpeed,
        v.Z + awayBoost.Z + forwardBoost.Z
    )

    humanoid.WalkSpeed = Config.Run.Speed * self:_speedMultiplier()
    humanoid.AutoRotate = true
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

    self._wallrunCooldownUntil = os.clock() + Config.Walljump.Cooldown
    self._lastGroundedTime = 0
    self:_setState("Airborne")
end

--// Transition logic based on Humanoid grounding

function MovementController:_updateGroundedness()
    if not self._humanoid then
        return
    end

    local grounded = self:_isGroundedHumanoidState()
    if grounded then
        self._lastGroundedTime = os.clock()
    end

    if self._state == "Airborne" and grounded then
        self:_setState("Grounded")
        if os.clock() < self._jumpBufferedUntil then
            self:_executeJump(true)
        end
        return
    end

    if self._state == "Grounded" and not grounded then
        self:_setState("Airborne")
        return
    end
end

--// Input

function MovementController:_onInputBegan(input: InputObject)
    if self:_isStunned() then
        return
    end

    if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.C then
        if self._state == "Grounded" or self._state == "Airborne" then
            self:_startSlide()
        end
    elseif input.KeyCode == Enum.KeyCode.Space then
        self:_tryJump()
    end
end

--// Update

function MovementController:_update(dt: number)
    local humanoid = self._humanoid
    if not humanoid then
        return
    end

    if self:_isStunned() then
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
        return
    end
    humanoid.JumpPower = 0

    if self._state == "Grounded" or self._state == "Airborne" then
        humanoid.WalkSpeed = Config.Run.Speed * self:_speedMultiplier()
    end

    self:_updateGroundedness()

    if self._state ~= "Grounded" and self._rootPart then
        local v = self._rootPart.AssemblyLinearVelocity
        local horizontalSpeed = Vector3.new(v.X, 0, v.Z).Magnitude
        if horizontalSpeed > self._peakAirSpeed then
            self._peakAirSpeed = horizontalSpeed
        end
    end

    if self._state == "Sliding" then
        self:_updateSlide(dt)
    elseif self._state == "WallRunning" then
        self:_updateWallrun(dt)
    elseif self._state == "Vaulting" then
        self:_updateVault()
    elseif self._state == "Mantling" then
        self:_updateMantle()
    elseif self._state == "Airborne" then
        self:_tryStartWallrun()
        if self._state == "Airborne" then
            self:_tryMantle()
        end
    end
end

--// Lifecycle

function MovementController:_bindCharacter(character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

    self._character = character
    self._humanoid = humanoid
    self._rootPart = rootPart
    humanoid.WalkSpeed = Config.Run.Speed
    humanoid.JumpPower = 0
    humanoid.AutoRotate = true

    self._state = "Grounded"
    self._slideSpeed = 0
    self._slideEndTime = 0
    self._lastGroundedTime = os.clock()
    self._jumpBufferedUntil = 0
    self._vaultEndTime = 0
    self._vaultCooldownUntil = 0
    self._mantleEndTime = 0
    self._mantleCooldownUntil = 0
    self._wallrunEndTime = 0
    self._wallrunCooldownUntil = 0
    self._wallrunSpeed = 0
    self._chainBonus = 0
    self._chainExpireTime = 0
    self._peakAirSpeed = 0

    humanoid.Died:Connect(function()
        self._character = nil
        self._humanoid = nil
        self._rootPart = nil
        self._state = "Grounded"
    end)
end

function MovementController:KnitInit() end

function MovementController:KnitStart()
    PowerupService = Knit.GetService("PowerupService")

    local localPlayer = Players.LocalPlayer

    if localPlayer.Character then
        self:_bindCharacter(localPlayer.Character)
    end
    localPlayer.CharacterAdded:Connect(function(character)
        self:_bindCharacter(character)
    end)

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        self:_onInputBegan(input)
    end)

    RunService.Heartbeat:Connect(function(dt)
        self:_update(dt)
    end)
end

return MovementController
