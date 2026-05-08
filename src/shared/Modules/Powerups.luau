--!strict
--[[
    Powerups
    Data-driven powerup definitions. Server (PowerupService) applies effects;
    client (PowerupController) only consults this for visuals + UI labels.
]]

export type PowerupKind = "instant" | "next-trigger" | "active"

export type PowerupDef = {
    name: string,
    displayName: string,
    kind: PowerupKind,
    color: Color3,
    duration: number?,
    walkSpeedMult: number?,
    nextTriggerExpires: number?,
    activeKey: Enum.KeyCode?,
    wallDuration: number?,
    wallSize: Vector3?,
}

local Powerups: { [string]: PowerupDef } = {
    SpeedBoost = {
        name = "SpeedBoost",
        displayName = "Speed Boost",
        kind = "instant",
        color = Color3.fromRGB(120, 220, 255),
        duration = 5,
        walkSpeedMult = 1.5,
    },
    DoubleJump = {
        name = "DoubleJump",
        displayName = "Double Jump",
        kind = "next-trigger",
        color = Color3.fromRGB(180, 255, 140),
        nextTriggerExpires = 30,
    },
    WallSpawn = {
        name = "WallSpawn",
        displayName = "Wall Spawn",
        kind = "active",
        color = Color3.fromRGB(255, 140, 200),
        activeKey = Enum.KeyCode.Q,
        wallDuration = 5,
        wallSize = Vector3.new(8, 8, 1),
    },
}

local module = {}
module.All = Powerups

function module.Get(name: string): PowerupDef?
    return Powerups[name]
end

function module.RandomName(): string
    local names = {}
    for name in pairs(Powerups) do
        table.insert(names, name)
    end
    return names[math.random(1, #names)]
end

return module
