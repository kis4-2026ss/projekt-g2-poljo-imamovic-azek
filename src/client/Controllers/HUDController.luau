--!strict
--[[
    HUDController
    Top-of-screen round timer + live hold-time leaderboard.
    Reacts to RoundService.TimeRemaining and RoundService.HoldTimes properties.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Shared
local TimeFormat = require(ReplicatedStorage.Shared.Modules.TimeFormat)

--// Module
local HUDController = Knit.CreateController({
    Name = "HUDController",

    _timerLabel = nil :: TextLabel?,
    _scoresFrame = nil :: Frame?,
    _latestHoldTimes = {} :: { [number]: number },
})

--// Forward declarations
local RoundService

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

    local scoresFrame = Instance.new("Frame")
    scoresFrame.Name = "ScoresFrame"
    scoresFrame.AnchorPoint = Vector2.new(0.5, 0)
    scoresFrame.Position = UDim2.new(0.5, 0, 0, 46)
    scoresFrame.Size = UDim2.fromOffset(260, 20)
    scoresFrame.AutomaticSize = Enum.AutomaticSize.Y
    scoresFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    scoresFrame.BackgroundTransparency = 0.35
    scoresFrame.Parent = screenGui

    local scoresCorner = Instance.new("UICorner")
    scoresCorner.CornerRadius = UDim.new(0, 4)
    scoresCorner.Parent = scoresFrame

    local scoresPadding = Instance.new("UIPadding")
    scoresPadding.PaddingTop = UDim.new(0, 3)
    scoresPadding.PaddingBottom = UDim.new(0, 3)
    scoresPadding.PaddingLeft = UDim.new(0, 6)
    scoresPadding.PaddingRight = UDim.new(0, 6)
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

function HUDController:_updateScores(holdTimes: { [number]: number })
    self._latestHoldTimes = holdTimes
    local scoresFrame = self._scoresFrame
    if not scoresFrame then
        return
    end

    for _, child in ipairs(scoresFrame:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    local entries: { { userId: number, time: number } } = {}
    for userId, time in pairs(holdTimes) do
        table.insert(entries, { userId = userId, time = time })
    end
    table.sort(entries, function(a, b)
        return a.time > b.time
    end)

    for i, entry in ipairs(entries) do
        local player = Players:GetPlayerByUserId(entry.userId)
        local name = if player then player.DisplayName else tostring(entry.userId)

        local row = Instance.new("TextLabel")
        row.Name = string.format("Row_%d", entry.userId)
        row.LayoutOrder = i
        row.Size = UDim2.new(1, 0, 0, 14)
        row.BackgroundTransparency = 1
        row.TextColor3 = Color3.fromRGB(220, 220, 225)
        row.Font = Enum.Font.GothamMedium
        row.TextSize = 12
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.Text = string.format("%s — %s", name, TimeFormat.secondsToMMSSmmm(entry.time))
        row.Parent = scoresFrame
    end
end

--// Lifecycle

function HUDController:KnitInit() end

function HUDController:KnitStart()
    RoundService = Knit.GetService("RoundService")

    local gui = buildGui()
    local timerFrame = gui:FindFirstChild("TimerFrame") :: Frame
    local scoresFrame = gui:FindFirstChild("ScoresFrame") :: Frame
    self._timerLabel = timerFrame:FindFirstChild("TimerLabel") :: TextLabel
    self._scoresFrame = scoresFrame

    RoundService.TimeRemaining:Observe(function(value)
        self:_updateTimer(tonumber(value) or 0)
    end)

    RoundService.HoldTimes:Observe(function(value)
        local safe: { [number]: number } = {}
        if typeof(value) == "table" then
            for k, v in pairs(value) do
                if typeof(k) == "number" and typeof(v) == "number" then
                    safe[k] = v
                end
            end
        end
        self:_updateScores(safe)
    end)
end

return HUDController
