--!strict
--[[
    WinScreenController
    Shows the end-of-round panel with winner + hold times.
    Dismisses on next RoundStarted or after intermission window expires.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Shared
local TimeFormat = require(ReplicatedStorage.Shared.Modules.TimeFormat)

--// Constants
local AUTO_DISMISS_SECONDS = 5.5

--// Types
type RoundResult = {
    winnerUserId: number,
    isDraw: boolean,
    holdTimes: { [number]: number },
    duration: number,
}

--// Module
local WinScreenController = Knit.CreateController({
    Name = "WinScreenController",

    _activeGui = nil :: ScreenGui?,
})

--// Forward declarations
local RoundService

--// Private helpers

local function getTitleText(result: RoundResult): (string, Color3)
    if result.isDraw or result.winnerUserId == 0 then
        return "UNENTSCHIEDEN", Color3.fromRGB(190, 195, 215)
    end
    local winner = Players:GetPlayerByUserId(result.winnerUserId)
    local name = if winner then winner.DisplayName else "???"
    return string.format("%s gewinnt!", name), Color3.fromRGB(255, 215, 90)
end

local function buildScreen(result: RoundResult): ScreenGui
    local localPlayer = Players.LocalPlayer
    local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "WinScreen"
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    local backdrop = Instance.new("Frame")
    backdrop.Name = "Backdrop"
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    backdrop.BackgroundTransparency = 0.35
    backdrop.Parent = screenGui

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.Size = UDim2.fromOffset(520, 360)
    card.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
    card.Parent = backdrop

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 16)
    cardCorner.Parent = card

    local titleText, titleColor = getTitleText(result)
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.AnchorPoint = Vector2.new(0.5, 0)
    title.Position = UDim2.new(0.5, 0, 0, 24)
    title.Size = UDim2.fromOffset(480, 60)
    title.BackgroundTransparency = 1
    title.TextColor3 = titleColor
    title.Font = Enum.Font.GothamBlack
    title.TextScaled = true
    title.Text = titleText
    title.Parent = card

    local scoresFrame = Instance.new("Frame")
    scoresFrame.Name = "Scores"
    scoresFrame.AnchorPoint = Vector2.new(0.5, 0)
    scoresFrame.Position = UDim2.new(0.5, 0, 0, 100)
    scoresFrame.Size = UDim2.fromOffset(440, 200)
    scoresFrame.BackgroundTransparency = 1
    scoresFrame.Parent = card

    local scoresLayout = Instance.new("UIListLayout")
    scoresLayout.Padding = UDim.new(0, 8)
    scoresLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    scoresLayout.Parent = scoresFrame

    local entries: { { userId: number, time: number } } = {}
    for userId, time in pairs(result.holdTimes) do
        table.insert(entries, { userId = userId, time = time })
    end
    table.sort(entries, function(a, b)
        return a.time > b.time
    end)

    for i, entry in ipairs(entries) do
        local player = Players:GetPlayerByUserId(entry.userId)
        local name = if player then player.DisplayName else tostring(entry.userId)

        local row = Instance.new("TextLabel")
        row.Name = string.format("Row%d", i)
        row.LayoutOrder = i
        row.Size = UDim2.new(1, 0, 0, 32)
        row.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        row.TextColor3 = Color3.fromRGB(225, 225, 230)
        row.Font = Enum.Font.GothamMedium
        row.TextSize = 18
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.Text =
            string.format("  %d.  %s  —  %s", i, name, TimeFormat.secondsToMMSSmmm(entry.time))
        row.Parent = scoresFrame

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 6)
        rowCorner.Parent = row

        local rowPadding = Instance.new("UIPadding")
        rowPadding.PaddingLeft = UDim.new(0, 8)
        rowPadding.PaddingRight = UDim.new(0, 8)
        rowPadding.Parent = row
    end

    local footer = Instance.new("TextLabel")
    footer.Name = "Footer"
    footer.AnchorPoint = Vector2.new(0.5, 1)
    footer.Position = UDim2.new(0.5, 0, 1, -16)
    footer.Size = UDim2.fromOffset(440, 28)
    footer.BackgroundTransparency = 1
    footer.TextColor3 = Color3.fromRGB(160, 160, 180)
    footer.Font = Enum.Font.Gotham
    footer.TextSize = 14
    footer.Text = "Naechste Runde startet automatisch..."
    footer.Parent = card

    return screenGui
end

function WinScreenController:_dismiss()
    local gui = self._activeGui
    if gui then
        gui:Destroy()
        self._activeGui = nil
    end
end

function WinScreenController:_showResult(result: RoundResult)
    self:_dismiss()
    local gui = buildScreen(result)
    self._activeGui = gui

    task.delay(AUTO_DISMISS_SECONDS, function()
        if self._activeGui == gui then
            self:_dismiss()
        end
    end)
end

--// Lifecycle

function WinScreenController:KnitInit() end

function WinScreenController:KnitStart()
    RoundService = Knit.GetService("RoundService")

    RoundService.RoundEnded:Connect(function(result: RoundResult)
        self:_showResult(result)
    end)

    RoundService.RoundStarted:Connect(function()
        self:_dismiss()
    end)
end

return WinScreenController
