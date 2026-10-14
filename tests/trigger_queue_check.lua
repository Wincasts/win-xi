-- Standalone regression checks for Trigger's sound queue; run from the repository root.
package.path = 'addons/trigger/?.lua;' .. package.path
package.loaded.shared = { events = {} }
addon = { path = '' }
local now, heard = 0, {}
os.clock = function() return now end
ashita = {
    fs = { exists = function(path) return not path:find('missing', 1, true) end },
    misc = { play_sound = function(path) heard[#heard + 1] = path end },
}
local playing = require('playing')
local function tick(time)
    now = time
    playing.PlayWaiting(now)
end
local function lastIs(file)
    assert(heard[#heard] == 'sounds\\' .. file, 'expected last sound: ' .. file)
end
playing.Ask('a.wav', 'a')
playing.Ask('b.wav', 'b')
playing.Ask('c.wav', 'c')
assert(#heard == 1, 'queued sounds must not interrupt')
tick(0.49)
assert(#heard == 1, 'sound must finish before the next starts')
tick(0.5); tick(1)
assert(table.concat(heard, ',') == 'sounds\\a.wav,sounds\\b.wav,sounds\\c.wav', 'FIFO order')
tick(1.5)
playing.Ask('d.wav', 'd')
playing.Ask('missing.wav', 'missing')
playing.Ask('e.wav', 'e')
tick(2)
lastIs('e.wav')
assert(#heard == 5, 'a missing queued file must not block the next sound')
playing.Ask('stale.wav', 'stale')
tick(6)
assert(#heard == 5, 'expired queued sound must be discarded')
playing.Ask('fresh.wav', 'fresh')
lastIs('fresh.wav')
playing.Ask('fresh.wav', 'fresh')
assert(#heard == 6, 'same-key cooldown')
for i = 1, 200 do playing.Ask('burst.wav', {}) end
tick(6.5)
assert(#heard == 7, 'only one burst sound starts while playback is active')
tick(10)
assert(#heard == 7, 'remaining burst entries expire')
playing.Ask('after.wav', 'after')
lastIs('after.wav')
assert(#heard == 8, 'queue can be reused after draining')
print('Trigger queue: all assertions passed')
