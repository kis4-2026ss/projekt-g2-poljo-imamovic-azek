--!strict
--[[
    PowerupController
    Plain centered text at the bottom of the screen showing the current held
    powerup name. Active-type powerups get a "(Q)" hint appended. Server holds
    the authoritative attribute; this controller forwards Q and reflects state.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Shared
local Powerups = require(ReplicatedStorage.Shared.Modules.Powerups)

--// Constants
local ACTIVE_POWERUP_ATTRIBUTE = "ActivePowerup"
local SPEED_BOOST_ATTRIBUTE = "SpeedBoostMult"
local DOUBLE_JUMP_ATTRIBUTE = "HasDoubleJump"

--// Module
local PowerupController = Knit.CreateController({
    Name = "PowerupController",

    _label = nil :: TextLabel?,
    _activeConn = nil :: RBXScriptConnection?,
    _speedConn = nil :: RBXScriptConnection?,
    _doubleJumpConn = nil :: RBXScriptConnection?,
    _characterConn = nil :: RBXScriptConnection?,
})

--// Forward declarations
local PowerupService

--// Private helpers

local function buildLabel(): TextLabel
    local localPlayer = Players.LocalPlayer
    local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "PowerupHUD"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    local label = Instance.new("TextLabel")
    label.Name = "PowerupText"
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Position = UDim2.new(0.5, 0, 1, -28)
    label.Size = UDim2.fromOffset(400, 28)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(240, 240, 255)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 18
    label.TextStrokeTransparency = 0.3
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.Text = ""
    label.Visible = false
    label.Parent = screenGui

    return label
end

function PowerupController:_updateLabel(humanoid: Humanoid)
    local label = self._label
    if not label then
        return
    end

    local activeName = humanoid:GetAttribute(ACTIVE_POWERUP_ATTRIBUTE)
    if typeof(activeName) == "string" and activeName ~= "" then
        local def = Powerups.Get(activeName)
        if def then
            label.Text = string.format("%s (Q)", def.displayName)
            label.TextColor3 = def.color
            label.Visible = true
            return
        end
    end

    if humanoid:GetAttribute(DOUBLE_JUMP_ATTRIBUTE) == true then
        local def = Powerups.Get("DoubleJump")
        label.Text = if def then def.displayName else "Double Jump"
        label.TextColor3 = if def then def.color else Color3.fromRGB(180, 255, 140)
        label.Visible = true
        return
    end

    local speedMult = humanoid:GetAttribute(SPEED_BOOST_ATTRIBUTE)
    if typeof(speedMult) == "number" and speedMult > 1 then
        local def = Powerups.Get("SpeedBoost")
        label.Text = if def then def.displayName else "Speed Boost"
        label.TextColor3 = if def then def.color else Color3.fromRGB(120, 220, 255)
        label.Visible = true
        return
    end

    label.Visible = false
end

function PowerupController:_bindCharacter(character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid

    for _, conn in { self._activeConn, self._speedConn, self._doubleJumpConn } do
        if conn then
            conn:Disconnect()
        end
    end

    self:_updateLabel(humanoid)
    self._activeConn = humanoid
        :GetAttributeChangedSignal(ACTIVE_POWERUP_ATTRIBUTE)
        :Connect(function()
            self:_updateLabel(humanoid)
        end)
    self._speedConn = humanoid:GetAttributeChangedSignal(SPEED_BOOST_ATTRIBUTE):Connect(function()
        self:_updateLabel(humanoid)
    end)
    self._doubleJumpConn = humanoid
        :GetAttributeChangedSignal(DOUBLE_JUMP_ATTRIBUTE)
        :Connect(function()
            self:_updateLabel(humanoid)
        end)
end

--// Lifecycle

function PowerupController:KnitInit() end

function PowerupController:KnitStart()
    PowerupService = Knit.GetService("PowerupService")

    self._label = buildLabel()

    local localPlayer = Players.LocalPlayer

    if localPlayer.Character then
        self:_bindCharacter(localPlayer.Character)
    end
    self._characterConn = localPlayer.CharacterAdded:Connect(function(character)
        self:_bindCharacter(character)
    end)

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        if input.KeyCode == Enum.KeyCode.Q then
            PowerupService.ActivateActive:Fire()
        end
    end)
end

return PowerupController
