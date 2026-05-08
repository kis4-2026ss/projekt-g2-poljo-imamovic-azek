--!strict
--[[
    StunController
    Watches the local player's Humanoid 'Stunned' attribute.
    While stunned: apply a BlurEffect to Lighting and rotate the stars BillboardGui.
]]

--// Services
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Constants
local STUN_ATTRIBUTE = "Stunned"
local BLUR_SIZE = 10
local BLUR_NAME = "StunBlur"
local STARS_GUI_NAME = "StunStars"
local STARS_ROTATION_SPEED = 180

--// Module
local StunController = Knit.CreateController({
    Name = "StunController",

    _blur = nil :: BlurEffect?,
    _stunnedActive = false,
    _characterConn = nil :: RBXScriptConnection?,
    _attributeConn = nil :: RBXScriptConnection?,
    _heartbeatConn = nil :: RBXScriptConnection?,
})

--// Private helpers

function StunController:_ensureBlur(): BlurEffect
    local blur = self._blur
    if blur and blur.Parent then
        return blur
    end
    blur = Instance.new("BlurEffect")
    blur.Name = BLUR_NAME
    blur.Size = 0
    blur.Parent = Lighting
    self._blur = blur
    return blur
end

function StunController:_setBlur(active: boolean)
    local blur = self:_ensureBlur()
    blur.Size = if active then BLUR_SIZE else 0
end

function StunController:_onAttributeChanged(humanoid: Humanoid)
    local stunned = humanoid:GetAttribute(STUN_ATTRIBUTE) == true
    if stunned == self._stunnedActive then
        return
    end
    self._stunnedActive = stunned
    self:_setBlur(stunned)
end

function StunController:_bindCharacter(character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid

    local prevAttrConn = self._attributeConn
    if prevAttrConn then
        prevAttrConn:Disconnect()
    end

    self._stunnedActive = humanoid:GetAttribute(STUN_ATTRIBUTE) == true
    self:_setBlur(self._stunnedActive)

    self._attributeConn = humanoid:GetAttributeChangedSignal(STUN_ATTRIBUTE):Connect(function()
        self:_onAttributeChanged(humanoid)
    end)
end

function StunController:_rotateStars(deltaTime: number)
    local step = STARS_ROTATION_SPEED * deltaTime
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if not character then
            continue
        end
        local head = character:FindFirstChild("Head")
        if not head then
            continue
        end
        local gui = head:FindFirstChild(STARS_GUI_NAME)
        if not gui or not gui:IsA("BillboardGui") then
            continue
        end
        local rotator = gui:FindFirstChild("Rotator")
        if rotator and rotator:IsA("Frame") then
            rotator.Rotation = (rotator.Rotation + step) % 360
        end
    end
end

--// Lifecycle

function StunController:KnitInit() end

function StunController:KnitStart()
    local localPlayer = Players.LocalPlayer

    if localPlayer.Character then
        self:_bindCharacter(localPlayer.Character)
    end
    self._characterConn = localPlayer.CharacterAdded:Connect(function(character)
        self:_bindCharacter(character)
    end)

    self._heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        self:_rotateStars(dt)
    end)
end

return StunController
