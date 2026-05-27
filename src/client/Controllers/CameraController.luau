--!strict
--[[
    CameraController
    Locks the camera to first-person and the mouse to screen center.
    Both zoom distances pinned to 0 so the player cannot scroll out to
    third-person.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Module
local CameraController = Knit.CreateController({
    Name = "CameraController",
})

--// Private helpers

function CameraController:_lockMouse()
    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    UserInputService.MouseIconEnabled = false
end

function CameraController:_forceFirstPerson()
    local localPlayer = Players.LocalPlayer
    localPlayer.CameraMinZoomDistance = 0
    localPlayer.CameraMaxZoomDistance = 0
end

--// Lifecycle

function CameraController:KnitInit() end

function CameraController:KnitStart()
    local localPlayer = Players.LocalPlayer

    self:_forceFirstPerson()
    self:_lockMouse()

    localPlayer.CharacterAdded:Connect(function()
        self:_forceFirstPerson()
        self:_lockMouse()
    end)

    UserInputService.WindowFocused:Connect(function()
        self:_lockMouse()
    end)
end

return CameraController
