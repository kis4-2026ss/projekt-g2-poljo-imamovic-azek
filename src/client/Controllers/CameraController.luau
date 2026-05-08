--!strict
--[[
    CameraController
    Forces first-person at spawn and locks the mouse to screen center so the
    camera always rotates with mouse movement (no right-click required).
    Player can still scroll out up to MAX_ZOOM_DISTANCE studs; scrolling back
    in returns to first-person at zoom distance 0.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Constants
local MIN_ZOOM_DISTANCE = 0
local MAX_ZOOM_DISTANCE = 20

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
    localPlayer.CameraMinZoomDistance = MIN_ZOOM_DISTANCE
    localPlayer.CameraMaxZoomDistance = 0
    task.delay(0.1, function()
        localPlayer.CameraMaxZoomDistance = MAX_ZOOM_DISTANCE
    end)
end

--// Lifecycle

function CameraController:KnitInit() end

function CameraController:KnitStart()
    local localPlayer = Players.LocalPlayer

    self:_forceFirstPerson()
    self:_lockMouse()

    localPlayer.CharacterAdded:Connect(function()
        self:_forceFirstPerson()
        task.wait(0.15)
        self:_lockMouse()
    end)

    UserInputService.WindowFocused:Connect(function()
        self:_lockMouse()
    end)
end

return CameraController
