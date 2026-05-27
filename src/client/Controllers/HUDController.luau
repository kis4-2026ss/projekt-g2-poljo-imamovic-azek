--!strict
--[[
    HUDController
    Top-of-screen round timer + live hold-time scoreboard.
    Marks the current holder with a star + gold tint, shows a "DU HAELTST DAS
    OBJEKT" badge when the local player is the holder, and smoothes the
    holder's counter to render per-frame between the 0.1s server updates.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Shared
local TimeFormat = require(ReplicatedStorage.Shared.Modules.TimeFormat)

--// Constants
local HOLDER_COLOR = Color3.fromRGB(255, 180, 60)
local LOCAL_COLOR = Color3.fromRGB(140, 220, 255)
local NORMAL_COLOR = Color3.fromRGB(220, 220, 225)

--// Module
local HUDController = Knit.CreateController({
    Name = "HUDController",

    _timerLabel = nil :: TextLabel?,
    _scoresFrame = nil :: Frame?,
    _holderBadge = nil :: Frame?,
    _rows = {} :: { [number]: TextLabel },

    _latestHoldTimes = {} :: { [number]: number },
    _currentHolderUserId = 0,
    _holderBaseTime = 0,
    _holderBaseLocalTime = 0,
})

--// Forward declarations
local RoundService
local TagService

--// Private helpers

local function buildGui(): ScreenGui
    local localPlayer = Players.LocalPlayer
    local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "HUD"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui

    local timerFrame = Instance.new("Frame")
    timerFrame.Name = "TimerFrame"
    timerFrame.AnchorPoint = Vector2.new(0.5, 0)
    timerFrame.Position = UDim2.new(0.5, 0, 0, 8)
    timerFrame.Size = UDim2.fromOffset(120, 32)
    timerFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    timerFrame.BackgroundTransparency = 0.25
    timerFrame.Parent = screenGui

    local timerCorner = Instance.new("UICorner")
    timerCorner.CornerRadius = UDim.new(0, 6)
    timerCorner.Parent = timerFrame

    local timerLabel = Instance.new("TextLabel")
    timerLabel.Name = "TimerLabel"
    timerLabel.Size = UDim2.fromScale(1, 1)
    timerLabel.BackgroundTransparency = 1
    timerLabel.TextColor3 = Color3.fromRGB(255, 230, 120)
    timerLabel.Font = Enum.Font.GothamBold
    timerLabel.TextSize = 20
    timerLabel.Text = "0:00"
    timerLabel.Parent = timerFrame

    local holderBadge = Instance.new("Frame")
    holderBadge.Name = "HolderBadge"
    holderBadge.AnchorPoint = Vector2.new(0.5, 0)
    holderBadge.Position = UDim2.new(0.5, 0, 0, 46)
    holderBadge.Size = UDim2.fromOffset(200, 22)
    holderBadge.BackgroundColor3 = HOLDER_COLOR
    holderBadge.BackgroundTransparency = 0.15
    holderBadge.Visible = false
    holderBadge.Parent = screenGui

    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(0, 4)
    badgeCorner.Parent = holderBadge

    local badgeLabel = Instance.new("TextLabel")
    badgeLabel.Name = "Label"
    badgeLabel.Size = UDim2.fromScale(1, 1)
    badgeLabel.BackgroundTransparency = 1
    badgeLabel.TextColor3 = Color3.fromRGB(35, 25, 10)
    badgeLabel.Font = Enum.Font.GothamBold
    badgeLabel.TextSize = 13
    badgeLabel.Text = "★ DU HAELTST DAS OBJEKT ★"
    badgeLabel.Parent = holderBadge

    local scoresFrame = Instance.new("Frame")
    scoresFrame.Name = "ScoresFrame"
    scoresFrame.AnchorPoint = Vector2.new(1, 0)
    scoresFrame.Position = UDim2.new(1, -12, 0.5, 2)
    scoresFrame.Size = UDim2.fromOffset(280, 20)
    scoresFrame.AutomaticSize = Enum.AutomaticSize.Y
    scoresFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    scoresFrame.BackgroundTransparency = 0.35
    scoresFrame.Parent = screenGui

    local scoresCorner = Instance.new("UICorner")
    scoresCorner.CornerRadius = UDim.new(0, 4)
    scoresCorner.Parent = scoresFrame

    local scoresPadding = Instance.new("UIPadding")
    scoresPadding.PaddingTop = UDim.new(0, 4)
    scoresPadding.PaddingBottom = UDim.new(0, 4)
    scoresPadding.PaddingLeft = UDim.new(0, 8)
    scoresPadding.PaddingRight = UDim.new(0, 8)
    scoresPadding.Parent = scoresFrame

    local scoresLayout = Instance.new("UIListLayout")
    scoresLayout.FillDirection = Enum.FillDirection.Vertical
    scoresLayout.Padding = UDim.new(0, 2)
    scoresLayout.SortOrder = Enum.SortOrder.LayoutOrder
    scoresLayout.Parent = scoresFrame

    return screenGui
end

function HUDController:_updateTimer(remaining: number)
    local label = self._timerLabel
    if label then
        label.Text = TimeFormat.secondsToMMSS(remaining)
    end
end

function HUDController:_holderTimeNow(): number
    if self._currentHolderUserId == 0 then
        return 0
    end
    return self._holderBaseTime + (os.clock() - self._holderBaseLocalTime)
end

function HUDController:_renderScores()
    local scoresFrame = self._scoresFrame
    if not scoresFrame then
        return
    end

    local localId = Players.LocalPlayer.UserId
    local holderId = self._currentHolderUserId

    -- Iterate over the currently connected players, not the synced hold-times
    -- map. Two reasons:
    --   1. The scoreboard should show everyone on the server (even if the
    --      server's HoldTimes table hiccups, didn't include them yet, or the
    --      round is in intermission), with a 0 score as fallback.
    --   2. The HoldTimes property has occasionally come back with stale or
    --      key-shifted entries due to Roblox's table-replication quirks; the
    --      authoritative "who is here right now" list is Players:GetPlayers().
    -- The synced map is consulted only as a time lookup.
    local entries: { { userId: number, time: number } } = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local displayTime: number
        if player.UserId == holderId and holderId > 0 then
            displayTime = self:_holderTimeNow()
        else
            displayTime = self._latestHoldTimes[player.UserId] or 0
        end
        table.insert(entries, { userId = player.UserId, time = displayTime })
    end

    -- Sort by descending hold-time; ties fall back to userId for deterministic
    -- ordering (avoids rows flickering positions when two players have score 0).
    table.sort(entries, function(a, b)
        if a.time == b.time then
            return a.userId < b.userId
        end
        return a.time > b.time
    end)

    local activeIds: { [number]: boolean } = {}
    for i, entry in ipairs(entries) do
        local row = self._rows[entry.userId]
        if not row then
            row = Instance.new("TextLabel")
            row.Name = string.format("Row_%d", entry.userId)
            row.Size = UDim2.new(1, 0, 0, 16)
            row.BackgroundTransparency = 1
            row.TextSize = 13
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.Parent = scoresFrame
            self._rows[entry.userId] = row
        end
        row.LayoutOrder = i

        local player = Players:GetPlayerByUserId(entry.userId)
        local name = if player then player.DisplayName else tostring(entry.userId)
        local isHolder = entry.userId == holderId
        local isLocal = entry.userId == localId
        local marker = if isHolder then "★ " else "   "

        if isHolder then
            row.TextColor3 = HOLDER_COLOR
            row.Font = Enum.Font.GothamBold
        elseif isLocal then
            row.TextColor3 = LOCAL_COLOR
            row.Font = Enum.Font.GothamBold
        else
            row.TextColor3 = NORMAL_COLOR
            row.Font = Enum.Font.GothamMedium
        end
        row.Text =
            string.format("%s%s — %s", marker, name, TimeFormat.secondsToMMSSmmm(entry.time))
        activeIds[entry.userId] = true
    end

    for userId, row in pairs(self._rows) do
        if not activeIds[userId] then
            row:Destroy()
            self._rows[userId] = nil
        end
    end

    local badge = self._holderBadge
    if badge then
        badge.Visible = holderId > 0 and holderId == localId
    end
end

function HUDController:_onHoldTimesUpdate(holdTimes: { [number]: number })
    self._latestHoldTimes = holdTimes
    if self._currentHolderUserId > 0 then
        local serverTime = holdTimes[self._currentHolderUserId]
        if serverTime then
            self._holderBaseTime = serverTime
            self._holderBaseLocalTime = os.clock()
        end
    end
end

function HUDController:_onHolderChanged(userId: number)
    self._currentHolderUserId = userId
    self._holderBaseTime = if userId > 0 then (self._latestHoldTimes[userId] or 0) else 0
    self._holderBaseLocalTime = os.clock()
end

--// Lifecycle

function HUDController:KnitInit() end

function HUDController:KnitStart()
    RoundService = Knit.GetService("RoundService")
    TagService = Knit.GetService("TagService")

    local gui = buildGui()
    local timerFrame = gui:FindFirstChild("TimerFrame") :: Frame
    self._timerLabel = timerFrame:FindFirstChild("TimerLabel") :: TextLabel
    self._scoresFrame = gui:FindFirstChild("ScoresFrame") :: Frame
    self._holderBadge = gui:FindFirstChild("HolderBadge") :: Frame

    RoundService.TimeRemaining:Observe(function(value)
        self:_updateTimer(tonumber(value) or 0)
    end)

    RoundService.HoldTimes:Observe(function(value)
        -- Robust key parsing: Roblox replicates non-dense number-keyed tables
        -- as JSON-ish dictionaries, which means our { [userId] = time } map
        -- arrives on the client with STRING keys (e.g. "12345678") rather
        -- than the original number keys. Studio Local Server doesn't hit
        -- this because test-user-ids are small and dense (1, 2, ...), so
        -- the table replicates as an array. Live servers DO hit it and the
        -- scoreboard goes empty. tonumber() the keys defensively.
        local safe: { [number]: number } = {}
        if typeof(value) == "table" then
            for k, v in pairs(value) do
                local userId = if typeof(k) == "number" then k else tonumber(k)
                if userId and typeof(v) == "number" then
                    safe[userId] = v
                end
            end
        end
        self:_onHoldTimesUpdate(safe)
    end)

    TagService.CurrentHolder:Observe(function(value)
        self:_onHolderChanged(tonumber(value) or 0)
    end)

    RunService.Heartbeat:Connect(function()
        self:_renderScores()
    end)
end

return HUDController
