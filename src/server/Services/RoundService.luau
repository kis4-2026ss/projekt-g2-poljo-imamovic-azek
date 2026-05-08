--!strict
--[[
    RoundService
    Owns the round lifecycle: start → track holds → end with winner.
    Hold times are accumulated in seconds with fractional precision (via os.clock()),
    which exposes millisecond granularity to the UI.
]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--// Packages
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

--// Constants
local ROUND_DURATION = 90
local MIN_PLAYERS_TO_START = 1
local INTERMISSION_DURATION = 6
local CLIENT_SYNC_INTERVAL = 0.1
local ROUND_START_DELAY = 3

--// Types
export type RoundResult = {
    winnerUserId: number,
    isDraw: boolean,
    holdTimes: { [number]: number },
    duration: number,
}

--// Module
local RoundService = Knit.CreateService({
    Name = "RoundService",

    Client = {
        RoundStarted = Knit.CreateSignal(),
        RoundEnded = Knit.CreateSignal(),
        TimeRemaining = Knit.CreateProperty(0),
        HoldTimes = Knit.CreateProperty({} :: { [number]: number }),
    },

    _isActive = false,
    _roundStartTime = 0,
    _roundDuration = ROUND_DURATION,
    _holdTimes = {} :: { [Player]: number },
    _currentHolderSince = nil :: number?,
    _lastClientUpdate = 0,
    _heartbeatConn = nil :: RBXScriptConnection?,

    RoundStarted = Signal.new(),
    RoundEnded = Signal.new(),
})

--// Forward declarations
local MapService
local TagService

--// Private helpers

local function makeHoldTimesByUserId(holdTimes: { [Player]: number }): { [number]: number }
    local result: { [number]: number } = {}
    for player, time in pairs(holdTimes) do
        result[player.UserId] = time
    end
    return result
end

function RoundService:_teleportPlayerToSpawn(player: Player, spawnName: string)
    local spawnPart = MapService:GetSpawnPoint(spawnName)
    if not spawnPart then
        return
    end
    local character = player.Character
    if not character then
        return
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        root.CFrame = CFrame.new(spawnPart.Position + Vector3.new(0, 5, 0))
    end
end

function RoundService:_assignSpawns()
    local spawnNames = { "Player1", "Player2" }
    for i, player in ipairs(Players:GetPlayers()) do
        local spawnName = spawnNames[i]
        if not spawnName then
            break
        end
        self:_teleportPlayerToSpawn(player, spawnName)
    end
end

function RoundService:_flushCurrentHolder()
    if not self._currentHolderSince then
        return
    end
    local currentHolder = TagService:GetCurrentHolder()
    if currentHolder then
        local elapsed = os.clock() - self._currentHolderSince
        self._holdTimes[currentHolder] = (self._holdTimes[currentHolder] or 0) + elapsed
    end
    self._currentHolderSince = nil
end

function RoundService:_onHolderChanged(newHolder: Player?)
    if not self._isActive then
        return
    end
    self:_flushCurrentHolder()
    if newHolder then
        self._currentHolderSince = os.clock()
    end
end

function RoundService:_buildLiveHoldTimes(): { [number]: number }
    local times = makeHoldTimesByUserId(self._holdTimes)
    local currentHolder = TagService:GetCurrentHolder()
    if currentHolder and self._currentHolderSince then
        local live = (times[currentHolder.UserId] or 0) + (os.clock() - self._currentHolderSince)
        times[currentHolder.UserId] = live
    end
    return times
end

function RoundService:_pushClientState(remaining: number)
    self.Client.TimeRemaining:Set(math.max(0, remaining))
    self.Client.HoldTimes:Set(self:_buildLiveHoldTimes())
end

function RoundService:_update()
    if not self._isActive then
        return
    end
    local now = os.clock()
    local elapsed = now - self._roundStartTime
    local remaining = self._roundDuration - elapsed

    if remaining <= 0 then
        self:EndRound()
        return
    end

    if now - self._lastClientUpdate >= CLIENT_SYNC_INTERVAL then
        self._lastClientUpdate = now
        self:_pushClientState(remaining)
    end
end

function RoundService:_determineWinner(): (Player?, boolean)
    local winner: Player? = nil
    local maxTime = -1
    local draw = false
    for player, time in pairs(self._holdTimes) do
        if time > maxTime then
            winner = player
            maxTime = time
            draw = false
        elseif time == maxTime and player ~= winner then
            draw = true
        end
    end
    if maxTime <= 0 then
        winner = nil
        draw = true
    end
    return winner, draw
end

--// Public API

function RoundService:IsActive(): boolean
    return self._isActive
end

function RoundService:GetCurrentHoldTime(player: Player): number
    local accumulated = self._holdTimes[player] or 0
    local currentHolder = TagService:GetCurrentHolder()
    if currentHolder == player and self._currentHolderSince then
        accumulated = accumulated + (os.clock() - self._currentHolderSince)
    end
    return accumulated
end

function RoundService:StartRound()
    if self._isActive then
        return
    end
    self._isActive = true
    self._roundStartTime = os.clock()
    self._holdTimes = {}
    self._currentHolderSince = nil
    self._lastClientUpdate = 0

    for _, player in ipairs(Players:GetPlayers()) do
        self._holdTimes[player] = 0
    end

    TagService:ReleaseHolder()
    TagService:SpawnObject()
    self:_assignSpawns()

    self.Client.TimeRemaining:Set(self._roundDuration)
    self.Client.HoldTimes:Set(makeHoldTimesByUserId(self._holdTimes))
    self.Client.RoundStarted:FireAll(self._roundDuration)
    self.RoundStarted:Fire(self._roundDuration)
end

function RoundService:EndRound()
    if not self._isActive then
        return
    end
    self._isActive = false
    self:_flushCurrentHolder()

    local winner, isDraw = self:_determineWinner()
    local result: RoundResult = {
        winnerUserId = if winner then winner.UserId else 0,
        isDraw = isDraw,
        holdTimes = makeHoldTimesByUserId(self._holdTimes),
        duration = self._roundDuration,
    }

    self.Client.TimeRemaining:Set(0)
    self.Client.HoldTimes:Set(result.holdTimes)
    self.Client.RoundEnded:FireAll(result)
    self.RoundEnded:Fire(result)

    task.delay(INTERMISSION_DURATION, function()
        if not self._isActive and #Players:GetPlayers() >= MIN_PLAYERS_TO_START then
            self:StartRound()
        end
    end)
end

--// Lifecycle

function RoundService:KnitInit() end

function RoundService:KnitStart()
    MapService = Knit.GetService("MapService")
    TagService = Knit.GetService("TagService")

    TagService.HolderChanged:Connect(function(newHolder: Player?)
        self:_onHolderChanged(newHolder)
    end)

    local function scheduleStartIfReady()
        if self._isActive then
            return
        end
        if #Players:GetPlayers() < MIN_PLAYERS_TO_START then
            return
        end
        task.delay(ROUND_START_DELAY, function()
            if not self._isActive and #Players:GetPlayers() >= MIN_PLAYERS_TO_START then
                self:StartRound()
            end
        end)
    end

    Players.PlayerAdded:Connect(scheduleStartIfReady)
    scheduleStartIfReady()

    self._heartbeatConn = RunService.Heartbeat:Connect(function()
        self:_update()
    end)
end

return RoundService
