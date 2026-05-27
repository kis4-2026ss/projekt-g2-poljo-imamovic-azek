--!strict
--[[
    MovementConfig
    Central tuning values for the parkour movement system. Kept in shared so
    both MovementController (logic) and MovementCameraController (visuals) pull
    from the same numbers.
]]

local MovementConfig = {
    Run = {
        Speed = 24,
        Jump = 50,
    },

    Slide = {
        InitialSpeed = 44,
        Friction = 22,
        ExitSpeed = 16,
        MaxDuration = 1.4,
        HipHeightDrop = 0,
        MinEntrySpeed = 0,
    },

    Jump = {
        Velocity = 48,
        CoyoteTime = 0.14,
        BufferTime = 0.16,
    },

    DoubleJump = {
        Velocity = 117,
    },

    Vault = {
        CheckDistance = 4,
        LowRayHeight = -1.4,
        HighRayHeight = 3.2,
        Duration = 0.42,
        ForwardSpeed = 30,
        UpwardSpeed = 32,
        Cooldown = 0.5,
    },

    Mantle = {
        CheckDistance = 3.2,
        UpperRayHeight = 4.6,
        Duration = 0.42,
        ForwardSpeed = 22,
        UpwardSpeed = 46,
        Cooldown = 0.45,
    },

    Wallrun = {
        CheckDistance = 3.4,
        MaxWallNormalY = 0.35,
        Speed = 28,
        VerticalHoldVelocity = 2,
        MaxDuration = 1.8,
        MinEntrySpeed = 10,
        MaxEntryRiseSpeed = 18,
        StickForce = 6,
        Cooldown = 0.28,
    },

    Walljump = {
        AwaySpeed = 34,
        UpSpeed = 50,
        ForwardSpeed = 24,
        Cooldown = 0.14,
    },

    Momentum = {
        -- Extra forward speed given when jumping while sliding (rewards chaining)
        SlideJumpForwardBoost = 6,
    },

    BunnyChain = {
        -- Surf-style chain: slide -> jump -> slide within Window grants a chain link.
        -- Each link adds BonusPerLink to the next slide's speed, capped at MaxBonus.
        -- Chain breaks if grounded too long without a slide entry.
        Window = 0.4,
        BonusPerLink = 10,
        MaxBonus = 50,
    },

    Camera = {
        NormalFOV = 70,
        SlideFOV = 86,
        WallrunFOV = 82,
        VaultFOV = 80,
        MantleFOV = 78,
        FOVResponsiveness = 9,

        -- Roll-radians applied as post-camera rotation around Z (roll axis)
        TiltNone = 0,
        TiltSlide = math.rad(6),
        TiltWallrunLeft = -math.rad(22),
        TiltWallrunRight = math.rad(22),
        TiltResponsiveness = 10,

        -- Humanoid.CameraOffset values (vertical/sideways body-relative shift)
        OffsetNone = Vector3.zero,
        OffsetSlide = Vector3.new(0, -1.1, 0),
        OffsetWallrunLeft = Vector3.new(-0.5, 0, 0),
        OffsetWallrunRight = Vector3.new(0.5, 0, 0),
        OffsetResponsiveness = 12,

        -- 3rd-person scaling (most camera effects only make sense in first-person).
        -- Camera-distance = |Camera.CFrame.Position - Camera.Focus.Position|:
        --   <= FirstPersonMaxDistance    -> full intensity (1x)
        --   >= ThirdPersonMinDistance    -> floor intensities applied (below)
        --   in between                    -> linear fade
        FirstPersonMaxDistance = 1.5,
        ThirdPersonMinDistance = 5.5,
        ThirdPersonRollFloor = 0.35,
        ThirdPersonOffsetFloor = 0,
    },
}

return MovementConfig
