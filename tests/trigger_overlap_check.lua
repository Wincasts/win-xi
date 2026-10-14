-- Native calls mocked; actual FFI structs and WAV parsing exercised on Linux too.
package.path = 'addons/trigger/?.lua;' .. package.path
local real = require('ffi')
local headers, opened, closed, reset = {}, 0, 0, 0
local failWrite = false
local native = {
    waveOutOpen = function(out) opened = opened + 1; out[0] = real.cast('void *', opened); return 0 end,
    waveOutPrepareHeader = function(_, h) headers[#headers + 1] = h; return 0 end,
    waveOutWrite = function() return failWrite and 1 or 0 end,
    waveOutUnprepareHeader = function() return 0 end,
    waveOutReset = function() reset = reset + 1; return 0 end,
    waveOutClose = function() closed = closed + 1; return 0 end,
}
package.loaded.ffi = setmetatable({ os = 'Windows', load = function() return native end }, { __index = real })
local overlap = require('overlap')
assert(overlap.Available())
local path = 'addons/trigger/sounds/voicef-tell.wav'
for i = 1, 8 do assert(overlap.Play(path)) end
assert(opened == 8 and closed == 0, 'eight independent voices')
assert(not overlap.Play(path), 'voice cap')
headers[1][0].flags = 1
collectgarbage('collect')
overlap.Poll()
assert(closed == 1, 'completed voice released')
assert(overlap.Play(path), 'completed slot reused')
overlap.Stop()
assert(closed == 9 and reset == 8, 'all active voices stopped')
failWrite = true
assert(not overlap.Play(path))
assert(closed == 10, 'write failure cleaned up')
assert(not overlap.Play('missing.wav'))

-- Playback routing, volume variants, repeat protection and switching modes.
package.loaded.shared = { events = {}, app = { options = { overlapSounds = { true }, volume = 'Low' }, Say = function() end } }
local played, polls, stops, legacy = {}, 0, 0, 0
package.loaded.overlap = {
    Available = function() return true end,
    Play = function(p) played[#played + 1] = p; return true end,
    Poll = function() polls = polls + 1 end,
    Stop = function() stops = stops + 1 end,
}
addon = { path = '' }
ashita = { fs = { exists = function() return true end }, misc = { play_sound = function() legacy = legacy + 1 end } }
local now = 0
os.clock = function() return now end
local playing = require('playing')
playing.Ask('a.wav', 'a'); playing.Ask('b.wav', 'b')
assert(#played == 2 and legacy == 0, 'overlap starts immediately')
assert(played[1] == 'sounds\\low\\a.wav', 'volume copies used')
playing.Ask('a.wav', 'a'); assert(#played == 2, 'repeat cooldown')
playing.Try('preview.wav'); assert(#played == 3, 'preview uses overlap')
playing.PlayWaiting(now); assert(polls == 1)
package.loaded.shared.app.options.overlapSounds[1] = false
playing.Ask('c.wav', 'c'); playing.Ask('d.wav', 'd')
assert(legacy == 1 and stops == 2, 'switch back stops voices and queues')
now = 0.5; playing.PlayWaiting(now); assert(legacy == 2)
print('Trigger overlap: all assertions passed (native calls mocked)')
