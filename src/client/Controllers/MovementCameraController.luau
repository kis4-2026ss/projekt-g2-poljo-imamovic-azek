--!strict
--[[
    MovementCameraController
    Drives camera feel based on MovementController state changes:
        - Tweens FieldOfView (70 normal -> 86 slide / 82 wallrun)
        - Tilts camera roll (post-camera CFrame rotation around Z)
        - Shifts Humanoid.CameraOffset for dip (slide) and lean (wallrun)
    All interpolation is exponential damping so changes feel punchy but smooth.
    Binds to RenderStep AFTER Roblox's default camera step so we overlay without
    fighting the default camera's positioning.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Shared
local Config = require(ReplicatedStorage.Shared.Modules.MovementConfig)

--// Types
type State = "Grounded" | "Sliding" | "Airborne" | "WallRunning" | "Vaulting" | "Mantling"

--// Module
local MovementCameraController = Knit.CreateController({
    Name = "MovementCameraController",

    _targetFOV = Config.Camera.NormalFOV,
    _currentFOV = Config.Camera.NormalFOV,
    _targetRoll = 0,
    _currentRoll = 0,
    _targetOffset = Vector3.zero,
    _currentOffset = Vector3.zero,
})

--// Forward declarations
local MovementController

--// Helpers

local function dampNumber(
    current: number,
    target: number,
    responsiveness: number,
    dt: number
): number
    local alpha = 1 - math.exp(-responsiveness * dt)
    return current + (target - current) * alpha
end

local function dampVector(
    current: Vector3,
    target: Vector3,
    responsiveness: number,
    dt: number
): Vector3
    local alpha = 1 - math.exp(-responsiveness * dt)
    return current + (target - current) * alpha
end

function MovementCameraController:_setTargetsForState(state: State)
    local conf = Config.Camera

    if state == "Sliding" then
        self._targetFOV = conf.SlideFOV
        self._targetRoll = conf.TiltSlide
        self._targetOffset = conf.OffsetSlide
    elseif state == "WallRunning" then
        self._targetFOV = conf.WallrunFOV
        local side = MovementController:GetWallSide()
        if side == "Left" then
            self._targetRoll = conf.TiltWallrunLeft
            self._targetOffset = conf.OffsetWallrunLeft
        else
            self._targetRoll = conf.TiltWallrunRight
            self._targetOffset = conf.OffsetWallrunRight
        end
    elseif state == "Vaulting" then
        self._targetFOV = conf.VaultFOV
        self._targetRoll = conf.TiltNone
        self._targetOffset = conf.OffsetNone
    elseif state == "Mantling" then
        self._targetFOV = conf.MantleFOV
        self._targetRoll = conf.TiltNone
        self._targetOffset = conf.OffsetNone
    else
        self._targetFOV = conf.NormalFOV
        self._targetRoll = conf.TiltNone
        self._targetOffset = conf.OffsetNone
    end
end

local function firstPersonIntensity(camera: Camera, conf): number
    local zoom = (camera.CFrame.Position - camera.Focus.Position).Magnitude
    if zoom <= conf.FirstPersonMaxDistance then
        return 1
    end
    if zoom >= conf.ThirdPersonMinDistance then
        return 0
    end
    local range = conf.ThirdPersonMinDistance - conf.FirstPersonMaxDistance
    return 1 - (zoom - conf.FirstPersonMaxDistance) / range
end

function MovementCameraController:_updateCamera(dt: number)
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    local conf = Config.Camera
    self._currentFOV = dampNumber(self._currentFOV, self._targetFOV, conf.FOVResponsiveness, dt)
    self._currentRoll = dampNumber(self._currentRoll, self._targetRoll, conf.TiltResponsiveness, dt)
    self._currentOffset =
        dampVector(self._currentOffset, self._targetOffset, conf.OffsetResponsiveness, dt)

    local fpsAlpha = firstPersonIntensity(camera, conf)
    local rollScale = conf.ThirdPersonRollFloor + (1 - conf.ThirdPersonRollFloor) * fpsAlpha
    local offsetScale = conf.ThirdPersonOffsetFloor + (1 - conf.ThirdPersonOffsetFloor) * fpsAlpha

    camera.FieldOfView = self._currentFOV

    local effectiveRoll = self._currentRoll * rollScale
    if math.abs(effectiveRoll) > 1e-4 then
        camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, effectiveRoll)
    end

    local localPlayer = Players.LocalPlayer
    local character = localPlayer.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.CameraOffset = self._currentOffset * offsetScale
        end
    end
end

--// Lifecycle

function MovementCameraController:KnitInit() end

function MovementCameraController:KnitStart()
    MovementController = Knit.GetController("MovementController")

    self:_setTargetsForState(MovementController:GetState())
    self._currentFOV = self._targetFOV
    self._currentRoll = self._targetRoll
    self._currentOffset = self._targetOffset

    MovementController.StateChanged:Connect(function(newState: State)
        self:_setTargetsForState(newState)
    end)

    RunService:BindToRenderStep(
        "MovementCameraFX",
        Enum.RenderPriority.Camera.Value + 1,
        function(dt)
            self:_updateCamera(dt)
        end
    )
end

return MovementCameraController
