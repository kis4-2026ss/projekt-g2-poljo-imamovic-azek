--!strict
--[[
    CrosshairController
    Center-screen crosshair plus aim resolver.

    Aim model:
        Cast a forward ray from the camera and pick the player whose HumanoidRootPart
        sits within an angular tolerance of that ray (perpendicular distance from
        the ray <= player half-width + padding). This gives the click hitbox a
        slightly larger effective size than the model itself — pixel-precise
        Mouse.Target was unforgiving for fast targets.

    Lock-on visual:
        The crosshair turns green and goes thicker (bold) when the resolved target
        is tag-eligible RIGHT NOW:
            - a target was resolved by the aim ray
            - target is within tag range from the local player
            - target IS the current object holder
            - local player is NOT the current holder
            - local player is NOT stunned

    Public API:
        GetAimTarget()        -> Player? (last cone-resolved target, may be out of range)
        GetAimTargetInRange() -> Player? (only returns when within TAG_RANGE_STUDS)

    TagController consumes GetAimTarget() so the click resolves to the same player
    the crosshair highlighted (UI + click stay consistent).
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Constants
local STUN_ATTRIBUTE = "Stunned"

-- Effective player hitbox: humanoid is ~2 studs wide, half-width = 1.
-- Add a small padding so the aim hitbox is "minimally larger than the enemy",
-- matching the spec.
local PLAYER_HALF_WIDTH = 1
local AIM_PADDING_STUDS = 1.25
local AIM_RADIUS = PLAYER_HALF_WIDTH + AIM_PADDING_STUDS

-- Must match TagService.TAG_MAX_DISTANCE so the visual lock-on agrees with the
-- server's distance gate. If you ever bump that on the server, bump this too.
local TAG_RANGE_STUDS = 18

-- Crosshair visual sizing
local ARM_LENGTH = 10
local ARM_GAP = 4
local THICKNESS_DEFAULT = 2
local THICKNESS_LOCKED = 4
local COLOR_DEFAULT = Color3.fromRGB(245, 245, 250)
local COLOR_LOCKED = Color3.fromRGB(80, 255, 120)

--// Module
local CrosshairController = Knit.CreateController({
    Name = "CrosshairController",

    _gui = nil :: ScreenGui?,
    _arms = {} :: { [string]: Frame },
    _currentHolderUserId = 0,
    _wasLocked = false,
    _cachedTarget = nil :: Player?,
    _cachedTargetInRange = false,
})

--// Forward declarations
local TagService

--// Private helpers

local function getCharacterRoot(player: Player): BasePart?
    local character = player.Character
    if not character then
        return nil
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        return root
    end
    return nil
end

local function buildGui(): (ScreenGui, { [string]: Frame })
    local localPlayer = Players.LocalPlayer
    local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "Crosshair"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui

    local function makeArm(name: string): Frame
        local frame = Instance.new("Frame")
        frame.Name = name
        frame.BorderSizePixel = 0
        frame.BackgroundColor3 = COLOR_DEFAULT
        frame.AnchorPoint = Vector2.new(0.5, 0.5)
        frame.Parent = screenGui
        return frame
    end

    local arms = {
        Top = makeArm("Top"),
        Bottom = makeArm("Bottom"),
        Left = makeArm("Left"),
        Right = makeArm("Right"),
    }

    return screenGui, arms
end

function CrosshairController:_layoutArms(locked: boolean)
    local thickness = if locked then THICKNESS_LOCKED else THICKNESS_DEFAULT
    local color = if locked then COLOR_LOCKED else COLOR_DEFAULT
    local offset = ARM_GAP + ARM_LENGTH / 2

    local arms = self._arms
    if arms.Top then
        arms.Top.Position = UDim2.new(0.5, 0, 0.5, -offset)
        arms.Top.Size = UDim2.fromOffset(thickness, ARM_LENGTH)
        arms.Top.BackgroundColor3 = color
    end
    if arms.Bottom then
        arms.Bottom.Position = UDim2.new(0.5, 0, 0.5, offset)
        arms.Bottom.Size = UDim2.fromOffset(thickness, ARM_LENGTH)
        arms.Bottom.BackgroundColor3 = color
    end
    if arms.Left then
        arms.Left.Position = UDim2.new(0.5, -offset, 0.5, 0)
        arms.Left.Size = UDim2.fromOffset(ARM_LENGTH, thickness)
        arms.Left.BackgroundColor3 = color
    end
    if arms.Right then
        arms.Right.Position = UDim2.new(0.5, offset, 0.5, 0)
        arms.Right.Size = UDim2.fromOffset(ARM_LENGTH, thickness)
        arms.Right.BackgroundColor3 = color
    end
end

function CrosshairController:_isLocalStunned(): boolean
    local localPlayer = Players.LocalPlayer
    local character = localPlayer.Character
    if not character then
        return false
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end
    return humanoid:GetAttribute(STUN_ATTRIBUTE) == true
end

-- Resolves the player our crosshair is on, plus whether they are in tag range.
-- Returns nil + false if no candidate is in the cone.
function CrosshairController:_resolveAim(): (Player?, boolean)
    local camera = Workspace.CurrentCamera
    if not camera then
        return nil, false
    end
    local localPlayer = Players.LocalPlayer
    local localRoot = getCharacterRoot(localPlayer)
    if not localRoot then
        return nil, false
    end

    local rayOrigin = camera.CFrame.Position
    local rayDir = camera.CFrame.LookVector
    if rayDir.Magnitude < 1e-4 then
        return nil, false
    end

    local bestPlayer: Player? = nil
    local bestForward = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player == localPlayer then
            continue
        end
        local root = getCharacterRoot(player)
        if not root then
            continue
        end

        local toPlayer = root.Position - rayOrigin
        local forwardDist = toPlayer:Dot(rayDir)
        if forwardDist <= 0 then
            continue -- candidate is behind the camera
        end

        local projected = rayOrigin + rayDir * forwardDist
        local perpDist = (root.Position - projected).Magnitude
        if perpDist > AIM_RADIUS then
            continue
        end

        if forwardDist < bestForward then
            bestForward = forwardDist
            bestPlayer = player
        end
    end

    if not bestPlayer then
        return nil, false
    end

    local targetRoot = getCharacterRoot(bestPlayer)
    if not targetRoot then
        return bestPlayer, false
    end
    local distance = (localRoot.Position - targetRoot.Position).Magnitude
    return bestPlayer, distance <= TAG_RANGE_STUDS
end

function CrosshairController:_isTagEligible(target: Player?, inRange: boolean): boolean
    if not target or not inRange then
        return false
    end
    local localPlayer = Players.LocalPlayer
    if self._currentHolderUserId == 0 then
        return false -- nobody is the holder yet (object floats until first auto-pickup)
    end
    if self._currentHolderUserId == localPlayer.UserId then
        return false -- I'm the holder, can't tag myself
    end
    if self._currentHolderUserId ~= target.UserId then
        return false -- target doesn't hold the object
    end
    if self:_isLocalStunned() then
        return false
    end
    return true
end

function CrosshairController:_update()
    local target, inRange = self:_resolveAim()
    self._cachedTarget = target
    self._cachedTargetInRange = inRange

    local locked = self:_isTagEligible(target, inRange)
    if locked ~= self._wasLocked then
        self:_layoutArms(locked)
        self._wasLocked = locked
    end
end

--// Public API

function CrosshairController:GetAimTarget(): Player?
    return self._cachedTarget
end

function CrosshairController:GetAimTargetInRange(): Player?
    if self._cachedTargetInRange then
        return self._cachedTarget
    end
    return nil
end

--// Lifecycle

function CrosshairController:KnitInit() end

function CrosshairController:KnitStart()
    TagService = Knit.GetService("TagService")

    local gui, arms = buildGui()
    self._gui = gui
    self._arms = arms
    self:_layoutArms(false)

    TagService.CurrentHolder:Observe(function(value)
        self._currentHolderUserId = tonumber(value) or 0
    end)

    RunService.Heartbeat:Connect(function()
        self:_update()
    end)
end

return CrosshairController
