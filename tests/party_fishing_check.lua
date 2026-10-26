-- Fishing: a hooked fish's stamina is drawn in the game's own target window, so for the fight party
-- gives that window back (uihook stops replacing it) and keeps its own target windows out of the way.
H.load()
local options = H.options()
local fishing = require('fishing')
local targetWanted
package.loaded.hook = {
    Begin = function(party, target) targetWanted = target; return party or target end,
    Stop = function() end, Uses = function() return false end, Disable = function() end,
    Capture = function() return false end, Status = function() return 'test plugin' end,
}
options.nativeHook[1], options.nativeTarget[1], options.target.enabled[1] = true, true, true
options.party.enabled[1], options.pets.enabled[1], options.showConfig[1] = false, false, false
options.fade.Enabled = false
require('winxi.game').IsHidden = function() return false end
-- the target windows are drawn when party asks whom they are for
local targetDrawn
require('target').Indexes = function() targetDrawn = true; return 0, 0, 0 end
local function Frame() targetDrawn = false; H.frames(2) end

-- The fish packet: its stamina at 0x04 and the seconds it may be fought for at 0x10
local function Fish(seconds)
    local bytes = { }
    for i = 1, 0x18 do bytes[i] = 0 end
    bytes[0x04 + 1], bytes[0x05 + 1] = 0x10, 0x27
    bytes[0x10 + 1] = seconds
    H.packetData(0x115, string.char(unpack(bytes)))
end
-- The client's fishing packet with a mode at 0x0E
local function Action(id, mode)
    local bytes = { }
    for i = 1, 0x14 do bytes[i] = 0 end
    bytes[0x0E + 1] = mode
    H.packetOutData(id, string.char(unpack(bytes)))
end

Frame()
assert(targetWanted == true and not fishing.Hooked() and targetDrawn, 'no fish: the target window replaced, party\'s drawn')
Fish(60)
Frame()
assert(fishing.Hooked() and targetWanted == false, 'a fish on: the game\'s target window given back')
assert(not targetDrawn, 'a fish on: party\'s own target windows out of the way')
Action(0x110, 5) -- "you don't know how much longer you can keep this one": the fight goes on
Frame()
assert(fishing.Hooked() and targetWanted == false, 'the time warning does not end the fight')
Action(0x110, 3)
Frame()
assert(not fishing.Hooked() and targetWanted == true, 'the mini-game ended: the target window replaced again')

Fish(60); Action(0x066, 4)
assert(not fishing.Hooked(), 'the older packet\'s release ends it too')
Fish(60); H.packet(0x00B)
assert(not fishing.Hooked(), 'a change of area ends it')
Fish(20); H.wait(49)
assert(fishing.Hooked(), 'within the time limit and grace, still on')
H.wait(2)
assert(not fishing.Hooked(), 'past the time limit and grace, over')
H.print('fishing: the game\'s target window given back from the bite to the end, party\'s own out of the way', true)
