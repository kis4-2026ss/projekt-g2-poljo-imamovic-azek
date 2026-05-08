--!strict
--[[
    TagController
    Listens for left-mouse clicks, resolves target Player via Mouse.Target,
    and fires AttemptTag to the server. Server validates distance + holder state.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Module
local TagController = Knit.CreateController({
    Name = "TagController",
})

--// Forward declarations
local TagService

--// Private helpers

local function resolveTargetPlayer(target: Instance?): Player?
    if not target then
        return nil
    end
    local character = target:FindFirstAncestorOfClass("Model")
    if not character then
        return nil
    end
    local player = Players:GetPlayerFromCharacter(character)
    if not player then
        return nil
    end
    return player
end

function TagController:_onClick()
    local localPlayer = Players.LocalPlayer
    local mouse = localPlayer:GetMouse()
    local target = resolveTargetPlayer(mouse.Target)
    if not target or target == localPlayer then
        return
    end
    TagService.AttemptTag:Fire(target.UserId)
end

--// Lifecycle

function TagController:KnitInit() end

function TagController:KnitStart()
    TagService = Knit.GetService("TagService")

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:_onClick()
        end
    end)
end

return TagController
