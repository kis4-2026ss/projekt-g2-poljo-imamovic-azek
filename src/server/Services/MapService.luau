--!strict
--[[
    MapService
    Builds the placeholder arena at server start. Low-poly cubes, closed map.

    Layout under Workspace.Map:
        Floor                 — 120x120 slab
        Boundaries/           — 4 tall side walls so nobody falls off
        Platforms/            — central stepped pyramid + 4 corner towers
        Ramps/                — tilted parts connecting floor to corner decks
        Obstacles/            — vault-height cubes + mantle walls scattered
        Pillars/              — tall thin cover columns
        SpawnPoints/
            Player1 / Player2 — 1v1 spawns at opposite corners
            Object            — center anchor (over the pyramid top)
            Powerups/         — Parts marking powerup spawn anchors
]]

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)

--// Constants
local MAP_NAME = "Map"
local FLOOR_SIZE = Vector3.new(120, 2, 120)
local FLOOR_COLOR = Color3.fromRGB(95, 100, 110)
local WALL_HEIGHT = 36
local WALL_THICKNESS = 2
local WALL_COLOR = Color3.fromRGB(60, 65, 75)

local PYRAMID_COLOR = Color3.fromRGB(150, 155, 175)
local PLATFORM_COLOR = Color3.fromRGB(130, 135, 145)
local OBSTACLE_COLOR = Color3.fromRGB(190, 135, 100)
local MANTLE_WALL_COLOR = Color3.fromRGB(170, 90, 90)
local PILLAR_COLOR = Color3.fromRGB(70, 80, 105)
local RAMP_COLOR = Color3.fromRGB(200, 185, 100)
local SPAWN_COLOR = Color3.fromRGB(100, 180, 140)
local OBJECT_ANCHOR_COLOR = Color3.fromRGB(240, 200, 60)
local POWERUP_ANCHOR_COLOR = Color3.fromRGB(120, 200, 240)

type PartDef = {
    name: string?,
    position: Vector3,
    size: Vector3,
    color: Color3?,
}

type RampDef = {
    cframe: CFrame,
    size: Vector3,
}

--// Module
local MapService = Knit.CreateService({
    Name = "MapService",
    Client = {},

    _mapFolder = nil :: Folder?,
})

--// Private helpers

local function makeAnchoredPart(props: {
    name: string,
    size: Vector3,
    cframe: CFrame?,
    position: Vector3?,
    color: Color3,
    material: Enum.Material?,
    canCollide: boolean?,
    transparency: number?,
    parent: Instance,
}): Part
    local part = Instance.new("Part")
    part.Name = props.name
    part.Size = props.size
    part.Color = props.color
    part.Material = props.material or Enum.Material.SmoothPlastic
    part.Anchored = true
    part.CanCollide = if props.canCollide == nil then true else props.canCollide
    part.Transparency = props.transparency or 0
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    if props.cframe then
        part.CFrame = props.cframe
    elseif props.position then
        part.Position = props.position
    end
    part.Parent = props.parent
    return part
end

function MapService:_clearDefaults()
    for _, child in ipairs(Workspace:GetChildren()) do
        if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
            child:Destroy()
        end
    end
    local existing = Workspace:FindFirstChild(MAP_NAME)
    if existing then
        existing:Destroy()
    end
end

function MapService:_buildFloor(parent: Instance)
    makeAnchoredPart({
        name = "Floor",
        size = FLOOR_SIZE,
        position = Vector3.new(0, -FLOOR_SIZE.Y / 2, 0),
        color = FLOOR_COLOR,
        parent = parent,
    })
end

function MapService:_buildBoundaries(parent: Instance)
    local boundaries = Instance.new("Folder")
    boundaries.Name = "Boundaries"
    boundaries.Parent = parent

    local halfX = FLOOR_SIZE.X / 2
    local halfZ = FLOOR_SIZE.Z / 2
    local yCenter = WALL_HEIGHT / 2

    local walls = {
        {
            name = "WallNorth",
            size = Vector3.new(FLOOR_SIZE.X + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS),
            position = Vector3.new(0, yCenter, -halfZ - WALL_THICKNESS / 2),
        },
        {
            name = "WallSouth",
            size = Vector3.new(FLOOR_SIZE.X + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS),
            position = Vector3.new(0, yCenter, halfZ + WALL_THICKNESS / 2),
        },
        {
            name = "WallEast",
            size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, FLOOR_SIZE.Z),
            position = Vector3.new(halfX + WALL_THICKNESS / 2, yCenter, 0),
        },
        {
            name = "WallWest",
            size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, FLOOR_SIZE.Z),
            position = Vector3.new(-halfX - WALL_THICKNESS / 2, yCenter, 0),
        },
    }

    for _, def in ipairs(walls) do
        makeAnchoredPart({
            name = def.name,
            size = def.size,
            position = def.position,
            color = WALL_COLOR,
            parent = boundaries,
        })
    end
end

function MapService:_buildCentralPyramid(parent: Instance)
    -- 2-stud steps per level so you can walk up the pyramid like a staircase.
    local levels: { PartDef } = {
        { position = Vector3.new(0, 1, 0), size = Vector3.new(22, 2, 22) },
        { position = Vector3.new(0, 3, 0), size = Vector3.new(16, 2, 16) },
        { position = Vector3.new(0, 5, 0), size = Vector3.new(10, 2, 10) },
        { position = Vector3.new(0, 7, 0), size = Vector3.new(5, 2, 5) },
    }
    for i, def in ipairs(levels) do
        makeAnchoredPart({
            name = string.format("PyramidLevel%d", i),
            size = def.size,
            position = def.position,
            color = PYRAMID_COLOR,
            parent = parent,
        })
    end
end

function MapService:_buildCornerTowers(parent: Instance)
    -- 2-stud step from floor to lower deck, 2-stud step from lower to upper.
    local corners = { { 40, 40 }, { -40, 40 }, { 40, -40 }, { -40, -40 } }
    for index, corner in ipairs(corners) do
        local x = corner[1]
        local z = corner[2]
        makeAnchoredPart({
            name = string.format("Corner%d_Lower", index),
            size = Vector3.new(14, 2, 14),
            position = Vector3.new(x, 1, z),
            color = PLATFORM_COLOR,
            parent = parent,
        })
        makeAnchoredPart({
            name = string.format("Corner%d_Upper", index),
            size = Vector3.new(7, 2, 7),
            position = Vector3.new(x, 3, z),
            color = PLATFORM_COLOR,
            parent = parent,
        })
    end
end

function MapService:_buildObstacles(parent: Instance)
    local obstacles = Instance.new("Folder")
    obstacles.Name = "Obstacles"
    obstacles.Parent = parent

    local vaults: { PartDef } = {
        { position = Vector3.new(18, 1.25, 0), size = Vector3.new(4, 2.5, 10) },
        { position = Vector3.new(-18, 1.25, 0), size = Vector3.new(4, 2.5, 10) },
        { position = Vector3.new(0, 1.25, 18), size = Vector3.new(10, 2.5, 4) },
        { position = Vector3.new(0, 1.25, -18), size = Vector3.new(10, 2.5, 4) },
        { position = Vector3.new(24, 1.25, 24), size = Vector3.new(6, 2.5, 3) },
        { position = Vector3.new(-24, 1.25, 24), size = Vector3.new(6, 2.5, 3) },
        { position = Vector3.new(24, 1.25, -24), size = Vector3.new(6, 2.5, 3) },
        { position = Vector3.new(-24, 1.25, -24), size = Vector3.new(6, 2.5, 3) },
    }
    for i, def in ipairs(vaults) do
        makeAnchoredPart({
            name = string.format("Vault%d", i),
            size = def.size,
            position = def.position,
            color = OBSTACLE_COLOR,
            parent = obstacles,
        })
    end

    local mantles: { PartDef } = {
        { position = Vector3.new(30, 2.5, 10), size = Vector3.new(2, 5, 10) },
        { position = Vector3.new(-30, 2.5, -10), size = Vector3.new(2, 5, 10) },
        { position = Vector3.new(10, 2.5, 30), size = Vector3.new(10, 5, 2) },
        { position = Vector3.new(-10, 2.5, -30), size = Vector3.new(10, 5, 2) },
    }
    for i, def in ipairs(mantles) do
        makeAnchoredPart({
            name = string.format("MantleWall%d", i),
            size = def.size,
            position = def.position,
            color = MANTLE_WALL_COLOR,
            parent = obstacles,
        })
    end
end

function MapService:_buildPillars(parent: Instance)
    local pillars = Instance.new("Folder")
    pillars.Name = "Pillars"
    pillars.Parent = parent

    local positions = {
        Vector3.new(26, 9, 0),
        Vector3.new(-26, 9, 0),
        Vector3.new(0, 9, 26),
        Vector3.new(0, 9, -26),
        Vector3.new(18, 9, 18),
        Vector3.new(-18, 9, -18),
    }
    for i, pos in ipairs(positions) do
        makeAnchoredPart({
            name = string.format("Pillar%d", i),
            size = Vector3.new(2.5, 18, 2.5),
            position = pos,
            color = PILLAR_COLOR,
            parent = pillars,
        })
    end
end

function MapService:_buildRamps(parent: Instance)
    local ramps = Instance.new("Folder")
    ramps.Name = "Ramps"
    ramps.Parent = parent

    local defs: { RampDef } = {
        {
            cframe = CFrame.new(40, 1, 25) * CFrame.Angles(math.rad(-7), 0, 0),
            size = Vector3.new(6, 1, 16),
        },
        {
            cframe = CFrame.new(-40, 1, 25) * CFrame.Angles(math.rad(-7), 0, 0),
            size = Vector3.new(6, 1, 16),
        },
        {
            cframe = CFrame.new(40, 1, -25) * CFrame.Angles(math.rad(7), 0, 0),
            size = Vector3.new(6, 1, 16),
        },
        {
            cframe = CFrame.new(-40, 1, -25) * CFrame.Angles(math.rad(7), 0, 0),
            size = Vector3.new(6, 1, 16),
        },
    }
    for i, def in ipairs(defs) do
        makeAnchoredPart({
            name = string.format("Ramp%d", i),
            size = def.size,
            cframe = def.cframe,
            color = RAMP_COLOR,
            parent = ramps,
        })
    end
end

function MapService:_buildSpawnPoints(parent: Instance)
    local spawnPoints = Instance.new("Folder")
    spawnPoints.Name = "SpawnPoints"
    spawnPoints.Parent = parent

    local spawn1 = Instance.new("SpawnLocation")
    spawn1.Name = "Player1"
    spawn1.Size = Vector3.new(6, 1, 6)
    spawn1.Position = Vector3.new(52, 0.5, 52)
    spawn1.Color = SPAWN_COLOR
    spawn1.Material = Enum.Material.Neon
    spawn1.Anchored = true
    spawn1.CanCollide = true
    spawn1.Neutral = true
    spawn1.AllowTeamChangeOnTouch = false
    spawn1.TopSurface = Enum.SurfaceType.Smooth
    spawn1.BottomSurface = Enum.SurfaceType.Smooth
    spawn1.Parent = spawnPoints

    local spawn2 = spawn1:Clone()
    spawn2.Name = "Player2"
    spawn2.Position = Vector3.new(-52, 0.5, -52)
    spawn2.Parent = spawnPoints

    makeAnchoredPart({
        name = "Object",
        size = Vector3.new(2, 2, 2),
        position = Vector3.new(0, 11, 0),
        color = OBJECT_ANCHOR_COLOR,
        material = Enum.Material.Neon,
        canCollide = false,
        transparency = 1,
        parent = spawnPoints,
    })

    local powerupFolder = Instance.new("Folder")
    powerupFolder.Name = "Powerups"
    powerupFolder.Parent = spawnPoints

    -- All spawn spots sit ON top of an actual walkable surface (2-stud step max
    -- between levels so the character walks up like stairs, no jumping needed).
    local powerupSpots = {
        -- Pyramid Level 1 top (Y=2 surface, 22x22 footprint)
        Vector3.new(9, 3, 9),
        Vector3.new(-9, 3, 9),
        Vector3.new(9, 3, -9),
        Vector3.new(-9, 3, -9),
        -- Pyramid Level 2 top (Y=4 surface, 16x16)
        Vector3.new(6, 5, 0),
        Vector3.new(-6, 5, 0),
        -- Pyramid Level 3 top (Y=6 surface, 10x10)
        Vector3.new(0, 7, 0),
        -- Pyramid Level 4 top (Y=8 surface, 5x5) - top-tier prize
        Vector3.new(0, 9, 0),
        -- Corner tower upper decks (Y=4 surface, 7x7)
        Vector3.new(40, 5, 40),
        Vector3.new(-40, 5, -40),
        Vector3.new(40, 5, -40),
        Vector3.new(-40, 5, 40),
    }

    for i, spot in ipairs(powerupSpots) do
        makeAnchoredPart({
            name = string.format("Spot%d", i),
            size = Vector3.new(1, 1, 1),
            position = spot,
            color = POWERUP_ANCHOR_COLOR,
            material = Enum.Material.Neon,
            canCollide = false,
            transparency = 1,
            parent = powerupFolder,
        })
    end
end

function MapService:_buildMap()
    self:_clearDefaults()

    local mapFolder = Instance.new("Folder")
    mapFolder.Name = MAP_NAME
    mapFolder.Parent = Workspace
    self._mapFolder = mapFolder

    local platforms = Instance.new("Folder")
    platforms.Name = "Platforms"
    platforms.Parent = mapFolder

    self:_buildFloor(mapFolder)
    self:_buildBoundaries(mapFolder)
    self:_buildCentralPyramid(platforms)
    self:_buildCornerTowers(platforms)
    self:_buildObstacles(mapFolder)
    self:_buildPillars(mapFolder)
    self:_buildRamps(mapFolder)
    self:_buildSpawnPoints(mapFolder)
end

--// Public API

function MapService:GetMapFolder(): Folder?
    return self._mapFolder
end

function MapService:GetSpawnPoint(name: string): BasePart?
    local mapFolder = self._mapFolder
    if not mapFolder then
        return nil
    end
    local spawns = mapFolder:FindFirstChild("SpawnPoints")
    if not spawns then
        return nil
    end
    local target = spawns:FindFirstChild(name)
    if target and target:IsA("BasePart") then
        return target
    end
    return nil
end

function MapService:GetPowerupSpots(): { BasePart }
    local result: { BasePart } = {}
    local mapFolder = self._mapFolder
    if not mapFolder then
        return result
    end
    local spawns = mapFolder:FindFirstChild("SpawnPoints")
    if not spawns then
        return result
    end
    local powerups = spawns:FindFirstChild("Powerups")
    if not powerups then
        return result
    end
    for _, child in ipairs(powerups:GetChildren()) do
        if child:IsA("BasePart") then
            table.insert(result, child)
        end
    end
    return result
end

--// Lifecycle

function MapService:KnitInit()
    self:_buildMap()
end

function MapService:KnitStart() end

return MapService
