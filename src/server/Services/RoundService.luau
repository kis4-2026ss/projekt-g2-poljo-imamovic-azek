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

function RoundService:_teleportPlayerToPosition(player: Player, position: Vector3)
    local character = player.Character
    if not character then
        return
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        root.CFrame = CFrame.new(position + Vector3.new(0, 5, 0))
    end
end

function RoundService:_assignSpawns()
    local spawnPoints = MapService:GetPlayerSpawnPoints()
    if #spawnPoints == 0 then
        return
    end

    -- Fisher-Yates shuffle the player list so spawn assignment isn't deterministic
    -- across rounds (otherwise the first-joined player always lands on Spawn1).
    local players = Players:GetPlayers()
    for i = #players, 2, -1 do
        local j = math.random(1, i)
        players[i], players[j] = players[j], players[i]
    end

    -- Round-robin through the spawn list. With 10 spawns and up to 10 players,
    -- every player gets a unique spot; if MaxPlayers is ever raised, the modulo
    -- wraps so we never index out of bounds.
    for i, player in ipairs(players) do
        local spawnPart = spawnPoints[((i - 1) % #spawnPoints) + 1]
        self:_teleportPlayerToPosition(player, spawnPart.Position)
    end
end

-- Writes the elapsed-since-start time onto `holderToFlush` and clears the
-- tick-start timestamp. Pass the player whose run is ending — do NOT ask
-- TagService for the current holder here, because by the time we get a
-- holder-change notification, TagService._currentHolder is already the new
-- holder. Asking would credit the wrong player. See TagOccurred signal,
-- which carries (previous, new) explicitly.
--
-- The `self._holdTimes[holderToFlush] ~= nil` guard skips flushing players
-- who have already been removed from the table (e.g. via PlayerRemoving's
-- cleanup running before our flush). Without it, a leaving holder could
-- ressurrect themselves into _holdTimes as a zombie entry that _determineWinner
-- would treat as a valid scorer.
function RoundService:_flushHolder(holderToFlush: Player?)
    if not self._currentHolderSince then
        return
    end
    if holderToFlush and self._holdTimes[holderToFlush] ~= nil then
        local elapsed = os.clock() - self._currentHolderSince
        self._holdTimes[holderToFlush] = self._holdTimes[holderToFlush] + elapsed
    end
    self._currentHolderSince = nil
end

function RoundService:_onTagOccurred(previousHolder: Player?, newHolder: Player?)
    if not self._isActive then
        return
    end
    -- 1. Flush the previous holder's elapsed run BEFORE we start the new one.
    --    Using TagOccurred's explicit `previous` arg means we always credit the
    --    right player, even if multiple holder changes happen quickly or if
    --    the previous holder died/left.
    self:_flushHolder(previousHolder)
    -- 2. Start the next run, only if there's a new holder. A nil newHolder
    --    (object went neutral via death/leave/release) leaves the tick-start
    --    timestamp cleared so the next auto-pickup will set it fresh.
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
    -- Final flush of whoever is currently holding the object so their last
    -- "run" gets counted. Safe to use TagService here because no holder
    -- transition is in flight — EndRound runs from the round-timer expiring,
    -- not from a holder-change handler.
    self:_flushHolder(TagService:GetCurrentHolder())

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

function RoundService:_onPlayerJoinedMidRound(player: Player)
    -- Seed hold time so the scoreboard immediately picks the player up. Without
    -- this the new joiner stays invisible on the right-side score list until
    -- the next round starts and StartRound() re-seeds the table.
    if self._holdTimes[player] == nil then
        self._holdTimes[player] = 0
    end

    -- Teleport them onto a spawn anchor near the arena so they don't drop in
    -- on top of the pyramid or outside the map. Wait for the character on the
    -- first CharacterAdded so the teleport actually has a root to move.
    local function placeOnSpawn()
        local spawnPoints = MapService:GetPlayerSpawnPoints()
        if #spawnPoints == 0 then
            return
        end
        local spawnPart = spawnPoints[math.random(1, #spawnPoints)]
        self:_teleportPlayerToPosition(player, spawnPart.Position)
    end

    if player.Character then
        placeOnSpawn()
        return
    end

    -- Once-only listener: we only want to override the FIRST spawn after the
    -- mid-round join. Subsequent respawns (death, next round) are handled by
    -- Roblox's default SpawnLocation flow or by _assignSpawns at round start.
    local conn: RBXScriptConnection?
    conn = player.CharacterAdded:Connect(function()
        if conn then
            conn:Disconnect()
            conn = nil
        end
        -- task.defer so the body/root parts have a chance to assemble before
        -- we CFrame the root. Without it the teleport occasionally no-ops on
        -- the very first character spawn.
        task.defer(placeOnSpawn)
    end)
end

function RoundService:KnitStart()
    MapService = Knit.GetService("MapService")
    TagService = Knit.GetService("TagService")

    -- TagOccurred carries (previousHolder, newHolder). HolderChanged only
    -- carries the new holder, which is not enough to credit the right player
    -- when the run ends (TagService._currentHolder has already been swapped
    -- to the new holder by the time the signal fires). Always use TagOccurred
    -- for time-tracking.
    TagService.TagOccurred:Connect(function(previousHolder: Player?, newHolder: Player?)
        self:_onTagOccurred(previousHolder, newHolder)
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

    Players.PlayerAdded:Connect(function(player)
        -- Hot-join: register the joiner in hold times so the scoreboard shows
        -- them, and put them on a spawn anchor if a round is already running.
        if self._isActive then
            self:_onPlayerJoinedMidRound(player)
        end
        scheduleStartIfReady()
    end)
    Players.PlayerRemoving:Connect(function(player)
        -- Race-handling: TagService also listens to PlayerRemoving and calls
        -- _setHolder(nil) on a leaving holder, which fires TagOccurred and
        -- normally flushes their elapsed time. But the relative listener
        -- order is not guaranteed — if WE run first, we'd clear _holdTimes
        -- before TagService's flush could land. Explicitly flush here when
        -- the leaving player is the current holder so the final run is
        -- credited regardless of listener order. The _flushHolder guard
        -- against re-adding a cleared entry handles the inverse order.
        if TagService:GetCurrentHolder() == player then
            self:_flushHolder(player)
        end
        self._holdTimes[player] = nil
    end)
    scheduleStartIfReady()

    self._heartbeatConn = RunService.Heartbeat:Connect(function()
        self:_update()
    end)
end

return RoundService
