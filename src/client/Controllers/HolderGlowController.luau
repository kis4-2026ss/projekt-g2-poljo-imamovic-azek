--!strict
--[[
    HolderGlowController
    Renders a Highlight + BillboardGui on whichever character currently holds the game object.
    The Highlight uses DepthMode = AlwaysOnTop so it is visible through walls.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Constants
local OUTLINE_COLOR = Color3.fromRGB(255, 170, 60)
local FILL_COLOR = Color3.fromRGB(255, 200, 120)
local FILL_TRANSPARENCY = 0.7
local OUTLINE_TRANSPARENCY = 0

--// Module
local HolderGlowController = Knit.CreateController({
    Name = "HolderGlowController",

    _activeHighlight = nil :: Highlight?,
    _activeBillboard = nil :: BillboardGui?,
    _currentHolderUserId = 0,
    _characterAddedConn = nil :: RBXScriptConnection?,
})

--// Forward declarations
local TagService

--// Private helpers

local function buildHighlight(): Highlight
    local highlight = Instance.new("Highlight")
    highlight.Name = "HolderHighlight"
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.OutlineColor = OUTLINE_COLOR
    highlight.FillColor = FILL_COLOR
    highlight.FillTransparency = FILL_TRANSPARENCY
    highlight.OutlineTransparency = OUTLINE_TRANSPARENCY
    return highlight
end

local function buildBillboard(playerName: string): BillboardGui
    local gui = Instance.new("BillboardGui")
    gui.Name = "HolderLabel"
    gui.Size = UDim2.fromOffset(180, 40)
    gui.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
    gui.AlwaysOnTop = true

    local label = Instance.new("TextLabel")
    label.Name = "Name"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = playerName
    label.TextColor3 = OUTLINE_COLOR
    label.TextStrokeTransparency = 0.2
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.Parent = gui

    return gui
end

function HolderGlowController:_clearHighlight()
    local highlight = self._activeHighlight
    if highlight then
        highlight:Destroy()
        self._activeHighlight = nil
    end
    local billboard = self._activeBillboard
    if billboard then
        billboard:Destroy()
        self._activeBillboard = nil
    end
    local conn = self._characterAddedConn
    if conn then
        conn:Disconnect()
        self._characterAddedConn = nil
    end
end

function HolderGlowController:_applyToCharacter(player: Player, character: Model)
    self:_clearHighlight()
    local highlight = buildHighlight()
    highlight.Adornee = character
    highlight.Parent = character
    self._activeHighlight = highlight

    local head = character:FindFirstChild("Head")
    if head and head:IsA("BasePart") then
        local billboard = buildBillboard(player.DisplayName)
        billboard.Parent = head
        self._activeBillboard = billboard
    end
end

function HolderGlowController:_applyToPlayer(player: Player)
    local character = player.Character
    if character then
        self:_applyToCharacter(player, character)
    end
    self._characterAddedConn = player.CharacterAdded:Connect(function(newCharacter)
        if self._currentHolderUserId == player.UserId then
            self:_applyToCharacter(player, newCharacter)
        end
    end)
end

function HolderGlowController:_onHolderChanged(userId: number)
    self._currentHolderUserId = userId
    self:_clearHighlight()
    if userId == 0 then
        return
    end
    local player = Players:GetPlayerByUserId(userId)
    if not player then
        return
    end
    self:_applyToPlayer(player)
end

--// Lifecycle

function HolderGlowController:KnitInit() end

function HolderGlowController:KnitStart()
    TagService = Knit.GetService("TagService")

    TagService.CurrentHolder:Observe(function(userId)
        self:_onHolderChanged(userId or 0)
    end)
end

return HolderGlowController
