-- Standalone regression checks: every playback entry point uses the global volume.
package.path = 'addons/trigger/?.lua;' .. package.path
local options = { volume = 'Medium', events = { tell = { enabled = { true }, sound = 'tell.wav' } } }
local said = {}
package.loaded.shared = { events = {}, app = { options = options,
    Say = function(_, text) said[#said + 1] = text end } }
addon = { path = '' }
local now, heard, existenceChecks = 0, {}, 0
os.clock = function() return now end
local available = {
    ['sounds\\tell.wav'] = true,
    ['sounds\\high\\tell.wav'] = true,
    ['sounds\\low\\tell.wav'] = true,
    ['sounds\\custom.wav'] = true,
}
ashita = {
    fs = { exists = function(path)
        existenceChecks = existenceChecks + 1
        return available[path] or false
    end },
    misc = { play_sound = function(path) heard[#heard + 1] = path end },
}
local p = require('playing')
local function lastIs(path)
    assert(heard[#heard] == 'sounds\\' .. path, 'expected: ' .. path)
end
assert(p.PlayFile('tell.wav')); lastIs('tell.wav')
options.volume = 'High'
existenceChecks = 0
assert(p.PlayFile('tell.wav')); lastIs('high\\tell.wav')
assert(existenceChecks == 1, 'a volume copy should only be checked once')
options.volume = 'Low'
p.Try('tell.wav'); lastIs('low\\tell.wav')
now = 1
p.Sound('tell'); lastIs('low\\tell.wav')
p.Ask('tell.wav', {}) -- a trigger, queued behind the event
local count = #heard
options.volume = 'High'; now = 1.5; p.PlayWaiting(now)
lastIs('high\\tell.wav')
assert(#heard == count + 1, 'queued trigger uses current volume')
assert(p.PlayFile('custom.wav')); lastIs('custom.wav')
available['sounds\\high\\tell.wav'] = nil
existenceChecks = 0
assert(p.PlayFile('tell.wav')); lastIs('tell.wav')
assert(existenceChecks == 2, 'fallback checks the variant and then the original')
assert(not p.PlayFile('missing.wav'))
p.Try('missing.wav'); assert(#said == 1, 'missing-file test reports the error')
options.volume = nil
assert(p.PlayFile('tell.wav')); lastIs('tell.wav')
print('Trigger volume: all assertions passed')
