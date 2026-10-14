-- Standalone regression checks for chunk-aware WAV duration parsing and its cache.
package.path = 'addons/trigger/?.lua;' .. package.path
package.loaded.shared = { events = {} }
addon = { path = '' }
local realOpen = io.open
local function le(value, bytes)
    local out = {}
    for i = 1, bytes do out[i] = string.char(value % 256); value = math.floor(value / 256) end
    return table.concat(out)
end
local function chunk(kind, data)
    return kind .. le(#data, 4) .. data .. (#data % 2 == 1 and '\0' or '')
end
local function riff(chunks)
    local data = 'WAVE' .. chunks
    return 'RIFF' .. le(#data, 4) .. data
end
local format = chunk('fmt ', le(1, 2) .. le(1, 2) .. le(500, 4) .. le(1000, 4) .. le(2, 2) .. le(16, 2))
local samples = chunk('data', ('\0'):rep(1000)) -- one second at 1000 bytes/second
local cases = {
    { 'standard', riff(format .. samples), 1 },
    { 'large odd metadata with false chunk names', riff(chunk('JUNK', 'fmt data' .. ('x'):rep(4993)) .. format .. samples), 1 },
    { 'data before format', riff(samples .. format), 1 },
    { 'invalid header', 'not a wave file', 0.5 },
    { 'truncated data', riff(format .. samples):sub(1, -2), 0.5 },
    { 'zero byte rate', riff(chunk('fmt ', ('\0'):rep(16)) .. samples), 0.5 },
}
for _, case in ipairs(cases) do
    local now, plays, opens, bytesRead = 0, 0, 0, 0
    os.clock = function() return now end
    ashita = { fs = { exists = function() return true end }, misc = { play_sound = function() plays = plays + 1 end } }
    io.open = function(path, mode)
        assert(path == 'sounds\\fixture.wav' and mode == 'rb')
        opens = opens + 1
        local file = assert(io.tmpfile())
        file:write(case[2]); file:seek('set', 0)
        return {
            read = function(_, count)
                local data = file:read(count)
                bytesRead = bytesRead + (data and #data or 0)
                return data
            end,
            seek = function(_, ...) return file:seek(...) end,
            close = function() return file:close() end,
        }
    end
    package.loaded.playing = nil
    local playing = require('playing')
    playing.Ask('fixture.wav', {})
    playing.Ask('fixture.wav', {})
    now = case[3] - 0.01; playing.PlayWaiting(now)
    assert(plays == 1, case[1] .. ': queue played too early')
    now = case[3]; playing.PlayWaiting(now)
    assert(plays == 2, case[1] .. ': queue did not play at the expected duration')
    assert(opens == 1, case[1] .. ': duration must be cached')
    assert(bytesRead <= 80, case[1] .. ': metadata/sample payloads must be skipped, not loaded')
end
io.open = realOpen
print('Trigger WAV durations: all assertions passed')
