--!strict
--[[
    TagService
    Server-authoritative tracking of the game object and its holder.
    Validates client tag attempts, swaps the holder, fires internal + remote signals.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

--// Constants
-- Tag-grab radius around the holder. Roughly 3 character heights — close
-- enough that you have to be aware of nearby threats, far enough that you
-- don't have to clip into the holder's hitbox to steal. Must stay in sync
-- with CrosshairController.TAG_RANGE_STUDS (client lock-on visual gate).
local TAG_MAX_DISTANCE = 18
local PICKUP_DISTANCE = 5
local STUN_DURATION_AFTER_STEAL = 2.5
local OBJECT_NAME = "GameObject"
local OBJECT_SIZE = Vector3.new(2.5, 2.5, 2.5)
local OBJECT_COLOR = Color3.fromRGB(255, 180, 40)
local OBJECT_HEAD_OFFSET = Vector3.new(0, 4, 0)
local OBJECT_UNHELD_BOB_SPEED = 1.5
local OBJECT_UNHELD_BOB_HEIGHT = 0.5

--// Module
local TagService = Knit.CreateService({
    Name = "TagService",

    Client = {
        AttemptTag = Knit.CreateSignal(),
        CurrentHolder = Knit.CreateProperty(0),
    },

    _currentHolder = nil :: Player?,
    _object = nil :: BasePart?,
    _objectSpawnPosition = nil :: Vector3?,
    _heartbeatConn = nil :: RBXScriptConnection?,
    _holderDiedConn = nil :: RBXScriptConnection?,

    TagOccurred = Signal.new(),
    HolderChanged = Signal.new(),
})

--// Forward declarations via dependencies
local MapService
local StunService

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

function TagService:_disconnectHolder()
    local conn = self._holderDiedConn
    if conn then
        conn:Disconnect()
        self._holderDiedConn = nil
    end
end

function TagService:_ensureObject()
    if self._object and self._object.Parent then
        return
    end
    local object = Instance.new("Part")
    object.Name = OBJECT_NAME
    object.Size = OBJECT_SIZE
    object.Color = OBJECT_COLOR
    object.Material = Enum.Material.Neon
    object.Anchored = true
    object.CanCollide = false
    object.CanQuery = true
    object.TopSurface = Enum.SurfaceType.Smooth
    object.BottomSurface = Enum.SurfaceType.Smooth
    object.Shape = Enum.PartType.Ball

    if self._objectSpawnPosition then
        object.Position = self._objectSpawnPosition
    end
    object.Parent = Workspace

    self._object = object
end

function TagService:_setHolder(player: Player?)
    local oldHolder = self._currentHolder
    if oldHolder == player then
        return
    end
    self._currentHolder = player
    self:_disconnectHolder()

    if player then
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            self._holderDiedConn = humanoid.Died:Connect(function()
                if self._currentHolder == player then
                    self:_setHolder(nil)
                end
            end)
        end
    end

    local newHolderUserId = if player then player.UserId else 0
    self.Client.CurrentHolder:Set(newHolderUserId)
    self.HolderChanged:Fire(player)
    self.TagOccurred:Fire(oldHolder, player)
end

function TagService:_validateTag(tagger: Player, target: Player): boolean
    if tagger == target then
        return false
    end
    if self._currentHolder ~= target then
        return false
    end
    if StunService and StunService:IsStunned(tagger) then
        return false
    end
    local taggerRoot = getCharacterRoot(tagger)
    local targetRoot = getCharacterRoot(target)
    if not taggerRoot or not targetRoot then
        return false
    end
    local distance = (taggerRoot.Position - targetRoot.Position).Magnitude
    if distance > TAG_MAX_DISTANCE then
        return false
    end
    return true
end

function TagService:_performTag(previous: Player, tagger: Player)
    self:_setHolder(tagger)
    if StunService then
        StunService:ApplyStun(previous, STUN_DURATION_AFTER_STEAL)
    end
end

function TagService:_tryAutoPickup()
    if self._currentHolder then
        return
    end
    local object = self._object
    if not object then
        return
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if StunService and StunService:IsStunned(player) then
            continue
        end
        local root = getCharacterRoot(player)
        if not root then
            continue
        end
        if (root.Position - object.Position).Magnitude <= PICKUP_DISTANCE then
            self:_setHolder(player)
            return
        end
    end
end

function TagService:_updateObjectPosition()
    local object = self._object
    if not object or not object.Parent then
        return
    end

    if not self._currentHolder then
        self:_tryAutoPickup()
    end

    local holder = self._currentHolder
    if holder then
        local character = holder.Character
        if not character then
            return
        end
        local head = character:FindFirstChild("Head")
        if head and head:IsA("BasePart") then
            object.Position = head.Position + OBJECT_HEAD_OFFSET
        end
    else
        local spawnPos = self._objectSpawnPosition
        if spawnPos then
            local bob = math.sin(os.clock() * OBJECT_UNHELD_BOB_SPEED) * OBJECT_UNHELD_BOB_HEIGHT
            object.Position = spawnPos + Vector3.new(0, bob, 0)
            object.CFrame = CFrame.new(object.Position) * CFrame.Angles(0, os.clock(), 0)
        end
    end
end

function TagService:_onAttemptTag(tagger: Player, targetUserId: number)
    if typeof(targetUserId) ~= "number" then
        return
    end
    local target = Players:GetPlayerByUserId(targetUserId)
    if not target then
        return
    end
    if not self:_validateTag(tagger, target) then
        return
    end
    self:_performTag(target, tagger)
end

--// Public API (server-to-server)

function TagService:GetCurrentHolder(): Player?
    return self._currentHolder
end

function TagService:TryTag(tagger: Player, target: Player): boolean
    if not self:_validateTag(tagger, target) then
        return false
    end
    self:_performTag(target, tagger)
    return true
end

function TagService:SpawnObject()
    self:_ensureObject()
end

function TagService:DestroyObject()
    self:_setHolder(nil)
    local object = self._object
    if object then
        object:Destroy()
    end
    self._object = nil
end

function TagService:AssignToPlayer(player: Player)
    self:_ensureObject()
    self:_setHolder(player)
end

function TagService:ReleaseHolder()
    self:_setHolder(nil)
end

--// Lifecycle

function TagService:KnitInit() end

function TagService:KnitStart()
    MapService = Knit.GetService("MapService")
    StunService = Knit.GetService("StunService")

    local spawnAnchor = MapService:GetSpawnPoint("Object")
    if spawnAnchor then
        self._objectSpawnPosition = spawnAnchor.Position
    else
        self._objectSpawnPosition = Vector3.new(0, 14, 0)
    end

    self:_ensureObject()

    self.Client.AttemptTag:Connect(function(tagger: Player, targetUserId: number)
        self:_onAttemptTag(tagger, targetUserId)
    end)

    Players.PlayerRemoving:Connect(function(player)
        if self._currentHolder == player then
            self:_setHolder(nil)
        end
    end)

    self._heartbeatConn = RunService.Heartbeat:Connect(function()
        self:_updateObjectPosition()
    end)
end

return TagService
