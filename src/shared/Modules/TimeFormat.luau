--!strict
--[[
    TimeFormat
    Helpers for displaying durations in MM:SS and MM:SS.mmm formats.
]]

local TimeFormat = {}

function TimeFormat.secondsToMMSSmmm(seconds: number): string
    local clamped = if seconds < 0 then 0 else seconds
    local totalMs = math.floor(clamped * 1000)
    local minutes = math.floor(totalMs / 60000)
    local secs = math.floor(totalMs / 1000) % 60
    local ms = totalMs % 1000
    return string.format("%02d:%02d.%03d", minutes, secs, ms)
end

function TimeFormat.secondsToMMSS(seconds: number): string
    local clamped = if seconds < 0 then 0 else seconds
    local minutes = math.floor(clamped / 60)
    local secs = math.floor(clamped) % 60
    return string.format("%d:%02d", minutes, secs)
end

return TimeFormat
