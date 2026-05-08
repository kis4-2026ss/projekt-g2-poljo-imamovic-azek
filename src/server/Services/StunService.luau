--!strict
--[[
    StunService
    Applies temporary stuns to players: attribute-driven so MovementController and
    TagService both respect it. Spawns visual stars BillboardGui over the stunned head.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

--// Constants
local STUN_ATTRIBUTE = "Stunned"
local STUN_END_ATTRIBUTE = "StunEndsAt"
local STARS_GUI_NAME = "StunStars"
local STARS_TEXT = "✦ ✦ ✦"
local STARS_COLOR = Color3.fromRGB(255, 230, 60)

--// Module
local StunService = Knit.CreateService({
    Name = "StunService",

    Client = {},

    _activeStuns = {} :: { [Player]: number },

    StunStarted = Signal.new(),
    StunEnded = Signal.new(),
})

--// Private helpers

local function findHumanoid(player: Player): Humanoid?
    local character = player.Character
    if not character then
        return nil
    end
    return character:FindFirstChildOfClass("Humanoid")
end

local function findHead(player: Player): BasePart?
    local character = player.Character
    if not character then
        return nil
    end
    local head = character:FindFirstChild("Head")
    if head and head:IsA("BasePart") then
        return head
    end
    return nil
end

local function buildStarsGui(): BillboardGui
    local gui = Instance.new("BillboardGui")
    gui.Name = STARS_GUI_NAME
    gui.Size = UDim2.fromOffset(140, 60)
    gui.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
    gui.AlwaysOnTop = true

    local frame = Instance.new("Frame")
    frame.Name = "Rotator"
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundTransparency = 1
    frame.Parent = gui

    local label = Instance.new("TextLabel")
    label.Name = "Stars"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = STARS_TEXT
    label.TextColor3 = STARS_COLOR
    label.TextStrokeTransparency = 0.3
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.Parent = frame

    return gui
end

function StunService:_clearStarsForPlayer(player: Player)
    local head = findHead(player)
    if not head then
        return
    end
    local gui = head:FindFirstChild(STARS_GUI_NAME)
    if gui then
        gui:Destroy()
    end
end

function StunService:_applyStarsToPlayer(player: Player)
    local head = findHead(player)
    if not head then
        return
    end
    if head:FindFirstChild(STARS_GUI_NAME) then
        return
    end
    local gui = buildStarsGui()
    gui.Parent = head
end

function StunService:_endStun(player: Player)
    if not self._activeStuns[player] then
        return
    end
    self._activeStuns[player] = nil

    local humanoid = findHumanoid(player)
    if humanoid then
        humanoid:SetAttribute(STUN_ATTRIBUTE, false)
        humanoid:SetAttribute(STUN_END_ATTRIBUTE, 0)
    end
    self:_clearStarsForPlayer(player)
    self.StunEnded:Fire(player)
end

--// Public API

function StunService:IsStunned(player: Player): boolean
    local endsAt = self._activeStuns[player]
    if not endsAt then
        return false
    end
    if os.clock() >= endsAt then
        self:_endStun(player)
        return false
    end
    return true
end

function StunService:ApplyStun(player: Player, duration: number)
    if duration <= 0 then
        return
    end
    local humanoid = findHumanoid(player)
    if not humanoid then
        return
    end
    local endsAt = os.clock() + duration
    self._activeStuns[player] = endsAt

    humanoid:SetAttribute(STUN_ATTRIBUTE, true)
    humanoid:SetAttribute(STUN_END_ATTRIBUTE, endsAt)
    self:_applyStarsToPlayer(player)
    self.StunStarted:Fire(player, duration)

    task.delay(duration, function()
        if self._activeStuns[player] == endsAt then
            self:_endStun(player)
        end
    end)
end

function StunService:ClearStun(player: Player)
    self:_endStun(player)
end

--// Lifecycle

function StunService:KnitInit() end

function StunService:KnitStart()
    Players.PlayerRemoving:Connect(function(player)
        self._activeStuns[player] = nil
    end)
end

return StunService
