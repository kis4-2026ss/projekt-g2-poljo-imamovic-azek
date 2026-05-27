--!strict
--[[
    TagController
    Listens for left-mouse clicks and fires AttemptTag for whichever player the
    crosshair is on. Server validates distance + holder state. Plays a 3D-spatial
    steal sound on the new holder when ownership transfers between two players
    (skips initial neutral pickups).

    The click target is resolved via CrosshairController:GetAimTarget(), not via
    raw Mouse.Target. That keeps the click hitbox aligned with the green/bold
    crosshair lock-on indicator and gives a slightly larger effective hitbox
    than pixel-precise Mouse.Target.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Constants
local TAG_SOUND_ID = "rbxassetid://9120386436"
local TAG_SOUND_VOLUME = 2.5
local TAG_SOUND_MAX_DISTANCE = 250

--// Module
local TagController = Knit.CreateController({
    Name = "TagController",

    _previousHolder = 0,
})

--// Forward declarations
local TagService
local CrosshairController

--// Private helpers

function TagController:_onClick()
    local target = CrosshairController:GetAimTarget()
    if not target then
        return
    end
    -- Server still validates range/holder, so we don't gate locally on range.
    -- Even a slightly out-of-range click is worth attempting; the server cost
    -- is tiny and the user got the timing right.
    TagService.AttemptTag:Fire(target.UserId)
end

function TagController:_playTagSound(newHolderUserId: number)
    local tagger = Players:GetPlayerByUserId(newHolderUserId)
    local character = tagger and tagger.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")

    local sound = Instance.new("Sound")
    sound.Name = "TagStealSound"
    sound.SoundId = TAG_SOUND_ID
    sound.Volume = TAG_SOUND_VOLUME
    sound.RollOffMaxDistance = TAG_SOUND_MAX_DISTANCE
    sound.RollOffMode = Enum.RollOffMode.InverseTapered
    sound.Parent = root or workspace
    sound:Play()
    sound.Ended:Once(function()
        sound:Destroy()
    end)
end

--// Lifecycle

function TagController:KnitInit() end

function TagController:KnitStart()
    TagService = Knit.GetService("TagService")
    CrosshairController = Knit.GetController("CrosshairController")

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:_onClick()
        end
    end)

    TagService.CurrentHolder:Observe(function(value)
        local userId = tonumber(value) or 0
        if userId ~= 0 and self._previousHolder ~= 0 and self._previousHolder ~= userId then
            self:_playTagSound(userId)
        end
        self._previousHolder = userId
    end)
end

return TagController
