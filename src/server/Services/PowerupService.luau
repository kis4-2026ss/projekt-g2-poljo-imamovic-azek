--!strict
--[[
    PowerupService
    Spawns powerups at map anchors, handles pickup, and applies effects.
    Three powerup kinds:
        instant      → applied immediately (e.g. SpeedBoost adds a speed mult attribute)
        next-trigger → sets an attribute consumed by the next relevant action (DoubleJump)
        active       → stored in 'ActivePowerup' attribute, consumed on hotkey/Activate request
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Shared
local Powerups = require(ReplicatedStorage.Shared.Modules.Powerups)

--// Constants
local MAX_ACTIVE_PICKUPS = 3
local SPAWN_INTERVAL_MIN = 10
local SPAWN_INTERVAL_MAX = 15
local INITIAL_SPAWN_DELAY = 4
local PICKUP_TOUCH_FOLDER = "ActivePowerups"
local POWERUP_PART_NAME_PREFIX = "Powerup_"

local SPEED_BOOST_ATTRIBUTE = "SpeedBoostMult"
local DOUBLE_JUMP_ATTRIBUTE = "HasDoubleJump"
local DOUBLE_JUMP_EXPIRE_ATTRIBUTE = "DoubleJumpExpiresAt"
local ACTIVE_POWERUP_ATTRIBUTE = "ActivePowerup"

--// Module
local PowerupService = Knit.CreateService({
    Name = "PowerupService",

    Client = {
        ActivateActive = Knit.CreateSignal(),
        UseDoubleJump = Knit.CreateSignal(),
    },

    _activePickups = {} :: { [BasePart]: string },
    _occupiedSpots = {} :: { [BasePart]: BasePart },
    _spawnContainer = nil :: Folder?,
    _spawnLoopThread = nil :: thread?,
})

--// Forward declarations
local MapService
local StunService

--// Private helpers

local function findHumanoid(player: Player): Humanoid?
    local character = player.Character
    if not character then
        return nil
    end
    return character:FindFirstChildOfClass("Humanoid")
end

function PowerupService:_ensureContainer(): Folder
    local existing = self._spawnContainer
    if existing and existing.Parent then
        return existing
    end
    local container = Instance.new("Folder")
    container.Name = PICKUP_TOUCH_FOLDER
    container.Parent = Workspace
    self._spawnContainer = container
    return container
end

function PowerupService:_buildPickupPart(spot: BasePart, def: Powerups.PowerupDef): BasePart
    local container = self:_ensureContainer()

    local part = Instance.new("Part")
    part.Name = POWERUP_PART_NAME_PREFIX .. def.name
    part.Size = Vector3.new(2, 2, 2)
    part.Color = def.color
    part.Material = Enum.Material.Neon
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = true
    part.Position = spot.Position
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = container

    local label = Instance.new("BillboardGui")
    label.Size = UDim2.fromOffset(120, 28)
    label.StudsOffsetWorldSpace = Vector3.new(0, 1.8, 0)
    label.AlwaysOnTop = true
    label.Parent = part

    local text = Instance.new("TextLabel")
    text.Size = UDim2.fromScale(1, 1)
    text.BackgroundTransparency = 1
    text.Font = Enum.Font.GothamBold
    text.TextScaled = true
    text.Text = def.displayName
    text.TextColor3 = def.color
    text.TextStrokeTransparency = 0.2
    text.Parent = label

    return part
end

function PowerupService:_pickRandomFreeSpot(): BasePart?
    local spots = MapService:GetPowerupSpots()
    local free: { BasePart } = {}
    for _, spot in ipairs(spots) do
        if not self._occupiedSpots[spot] then
            table.insert(free, spot)
        end
    end
    if #free == 0 then
        return nil
    end
    return free[math.random(1, #free)]
end

function PowerupService:_countActive(): number
    local n = 0
    for _ in pairs(self._activePickups) do
        n += 1
    end
    return n
end

function PowerupService:_removePickup(part: BasePart)
    local powerupName = self._activePickups[part]
    if not powerupName then
        return
    end
    self._activePickups[part] = nil
    for spot, occupiedBy in pairs(self._occupiedSpots) do
        if occupiedBy == part then
            self._occupiedSpots[spot] = nil
        end
    end
    part:Destroy()
end

function PowerupService:_applyInstant(player: Player, def: Powerups.PowerupDef)
    local humanoid = findHumanoid(player)
    if not humanoid then
        return
    end
    if def.name == "SpeedBoost" and def.duration and def.walkSpeedMult then
        local mult = def.walkSpeedMult
        local duration = def.duration
        humanoid:SetAttribute(SPEED_BOOST_ATTRIBUTE, mult)
        local endsAt = os.clock() + duration
        humanoid:SetAttribute(SPEED_BOOST_ATTRIBUTE .. "EndsAt", endsAt)
        task.delay(duration, function()
            local stillActive = humanoid:GetAttribute(SPEED_BOOST_ATTRIBUTE .. "EndsAt")
            if stillActive == endsAt then
                humanoid:SetAttribute(SPEED_BOOST_ATTRIBUTE, 1)
                humanoid:SetAttribute(SPEED_BOOST_ATTRIBUTE .. "EndsAt", 0)
            end
        end)
    end
end

function PowerupService:_applyNextTrigger(player: Player, def: Powerups.PowerupDef)
    local humanoid = findHumanoid(player)
    if not humanoid then
        return
    end
    if def.name == "DoubleJump" then
        local duration = def.nextTriggerExpires or 30
        local expires = os.clock() + duration
        humanoid:SetAttribute(DOUBLE_JUMP_ATTRIBUTE, true)
        humanoid:SetAttribute(DOUBLE_JUMP_EXPIRE_ATTRIBUTE, expires)
        -- Auto-clear the attribute after the window. Server's os.clock() is
        -- consistent with the apply-time, so the expires-stamp comparison is
        -- safe here (unlike on the client). Skip the clear if a fresher pickup
        -- bumped the expires-stamp in the meantime.
        task.delay(duration, function()
            if
                humanoid.Parent
                and humanoid:GetAttribute(DOUBLE_JUMP_EXPIRE_ATTRIBUTE) == expires
            then
                humanoid:SetAttribute(DOUBLE_JUMP_ATTRIBUTE, false)
                humanoid:SetAttribute(DOUBLE_JUMP_EXPIRE_ATTRIBUTE, 0)
            end
        end)
    end
end

function PowerupService:_storeActive(player: Player, def: Powerups.PowerupDef)
    local humanoid = findHumanoid(player)
    if not humanoid then
        return
    end
    humanoid:SetAttribute(ACTIVE_POWERUP_ATTRIBUTE, def.name)
end

function PowerupService:_spawnWall(player: Player, def: Powerups.PowerupDef)
    local character = player.Character
    if not character then
        return
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root or not root:IsA("BasePart") then
        return
    end
    local size = def.wallSize or Vector3.new(8, 8, 1)
    local lookVector = root.CFrame.LookVector
    -- Center wall on player so it extends symmetrically above and below,
    -- covering the full vertical regardless of placement height.
    local wallCFrame = root.CFrame * CFrame.new(0, 0, 2)
    wallCFrame = CFrame.new(wallCFrame.Position, wallCFrame.Position + lookVector)

    local wall = Instance.new("Part")
    wall.Name = "PlayerWall"
    wall.Size = size
    wall.CFrame = wallCFrame
    wall.Color = def.color
    wall.Material = Enum.Material.ForceField
    wall.Transparency = 0.3
    wall.Anchored = true
    wall.CanCollide = true
    wall.CanQuery = true
    wall.TopSurface = Enum.SurfaceType.Smooth
    wall.BottomSurface = Enum.SurfaceType.Smooth
    wall.Parent = Workspace

    task.delay(def.wallDuration or 5, function()
        if wall.Parent then
            wall:Destroy()
        end
    end)
end

function PowerupService:_handlePickup(player: Player, part: BasePart)
    local powerupName = self._activePickups[part]
    if not powerupName then
        return
    end
    if StunService and StunService:IsStunned(player) then
        return
    end
    local def = Powerups.Get(powerupName)
    if not def then
        return
    end
    self:_removePickup(part)

    if def.kind == "instant" then
        self:_applyInstant(player, def)
    elseif def.kind == "next-trigger" then
        self:_applyNextTrigger(player, def)
    elseif def.kind == "active" then
        self:_storeActive(player, def)
    end
end

function PowerupService:_attachPickup(part: BasePart)
    part.Touched:Connect(function(hit)
        local character = hit:FindFirstAncestorOfClass("Model")
        if not character then
            return
        end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then
            return
        end
        self:_handlePickup(player, part)
    end)
end

function PowerupService:_spawnOne()
    if self:_countActive() >= MAX_ACTIVE_PICKUPS then
        return
    end
    local spot = self:_pickRandomFreeSpot()
    if not spot then
        return
    end
    local powerupName = Powerups.RandomName()
    local def = Powerups.Get(powerupName)
    if not def then
        return
    end
    local part = self:_buildPickupPart(spot, def)
    self._activePickups[part] = powerupName
    self._occupiedSpots[spot] = part
    self:_attachPickup(part)
end

function PowerupService:_spawnLoop()
    task.wait(INITIAL_SPAWN_DELAY)
    while true do
        self:_spawnOne()
        task.wait(math.random(SPAWN_INTERVAL_MIN * 10, SPAWN_INTERVAL_MAX * 10) / 10)
    end
end

function PowerupService:_handleActivate(player: Player)
    local humanoid = findHumanoid(player)
    if not humanoid then
        return
    end
    local activeName = humanoid:GetAttribute(ACTIVE_POWERUP_ATTRIBUTE)
    if typeof(activeName) ~= "string" or activeName == "" then
        return
    end
    local def = Powerups.Get(activeName)
    if not def or def.kind ~= "active" then
        return
    end
    if StunService and StunService:IsStunned(player) then
        return
    end

    if def.name == "WallSpawn" then
        self:_spawnWall(player, def)
    end
    humanoid:SetAttribute(ACTIVE_POWERUP_ATTRIBUTE, "")
end

--// Public API

function PowerupService:ConsumeDoubleJump(player: Player): boolean
    local humanoid = findHumanoid(player)
    if not humanoid then
        return false
    end
    if humanoid:GetAttribute(DOUBLE_JUMP_ATTRIBUTE) ~= true then
        return false
    end
    local expires = humanoid:GetAttribute(DOUBLE_JUMP_EXPIRE_ATTRIBUTE)
    if typeof(expires) == "number" and os.clock() > expires then
        humanoid:SetAttribute(DOUBLE_JUMP_ATTRIBUTE, false)
        humanoid:SetAttribute(DOUBLE_JUMP_EXPIRE_ATTRIBUTE, 0)
        return false
    end
    humanoid:SetAttribute(DOUBLE_JUMP_ATTRIBUTE, false)
    humanoid:SetAttribute(DOUBLE_JUMP_EXPIRE_ATTRIBUTE, 0)
    return true
end

function PowerupService:ClearAllForPlayer(player: Player)
    local humanoid = findHumanoid(player)
    if not humanoid then
        return
    end
    humanoid:SetAttribute(SPEED_BOOST_ATTRIBUTE, 1)
    humanoid:SetAttribute(SPEED_BOOST_ATTRIBUTE .. "EndsAt", 0)
    humanoid:SetAttribute(DOUBLE_JUMP_ATTRIBUTE, false)
    humanoid:SetAttribute(DOUBLE_JUMP_EXPIRE_ATTRIBUTE, 0)
    humanoid:SetAttribute(ACTIVE_POWERUP_ATTRIBUTE, "")
end

function PowerupService:ClearAllPickups()
    for part in pairs(self._activePickups) do
        part:Destroy()
    end
    self._activePickups = {}
    self._occupiedSpots = {}
end

--// Lifecycle

function PowerupService:KnitInit() end

function PowerupService:KnitStart()
    MapService = Knit.GetService("MapService")
    StunService = Knit.GetService("StunService")

    self:_ensureContainer()

    self.Client.ActivateActive:Connect(function(player: Player)
        self:_handleActivate(player)
    end)

    self.Client.UseDoubleJump:Connect(function(player: Player)
        self:ConsumeDoubleJump(player)
    end)

    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function()
            self:ClearAllForPlayer(player)
        end)
    end)

    self._spawnLoopThread = task.spawn(function()
        self:_spawnLoop()
    end)
end

return PowerupService
