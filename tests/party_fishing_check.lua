-- Fishing: a hooked fish's stamina gauge is drawn with the game's own party list, so for the fight
-- party gives that list back (uihook stops replacing it) and hides its own, not to show the party twice.
H.load()
local options = H.options()
local fishing = require('fishing')
local partyWanted, targetWanted
package.loaded.hook = {
    Begin = function(party, target) partyWanted, targetWanted = party, target; return party or target end,
    Stop = function() end, Uses = function() return false end, Disable = function() end,
    Capture = function() return false end, Status = function() return 'test plugin' end,
}
options.nativeHook[1], options.nativeTarget[1], options.target.enabled[1] = true, true, true
options.nativeParty[1], options.party.enabled[1] = true, true
options.pets.enabled[1], options.showConfig[1] = false, false
options.fade.Enabled = false
require('winxi.game').IsHidden = function() return false end
-- the target windows are drawn when party asks whom they are for, the party's when it asks how many
local targetDrawn, partyDrawn
require('target').Indexes = function() targetDrawn = true; return 0, 0, 0 end
require('roster').Counts = function() partyDrawn = true; return 0, 0, 0, false end
local function Frame() targetDrawn, partyDrawn = false, false; H.frames(2) end

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
assert(partyWanted == true and targetWanted == true and not fishing.Hooked(), 'no fish: the party list and target window replaced')
assert(partyDrawn and targetDrawn, 'no fish: party\'s own windows drawn')
Fish(60)
Frame()
assert(fishing.Hooked() and partyWanted == false, 'a fish on: the game\'s party list given back')
assert(targetWanted == true and targetDrawn, 'a fish on: the target window still replaced, party\'s drawn')
assert(not partyDrawn, 'a fish on: party\'s own party windows out of the way')
Action(0x110, 5) -- "you don't know how much longer you can keep this one": the fight goes on
Frame()
assert(fishing.Hooked() and partyWanted == false, 'the time warning does not end the fight')
Action(0x110, 3)
Frame()
assert(not fishing.Hooked() and partyWanted == true and partyDrawn, 'the mini-game ended: the party list replaced again')

Fish(60); Action(0x066, 4)
assert(not fishing.Hooked(), 'the older packet\'s release ends it too')
Fish(60); H.packet(0x00B)
assert(not fishing.Hooked(), 'a change of area ends it')
Fish(20); H.wait(49)
assert(fishing.Hooked(), 'within the time limit and grace, still on')
H.wait(2)
assert(not fishing.Hooked(), 'past the time limit and grace, over')
H.print('fishing: the game\'s party list given back from the bite to the end, party\'s own out of the way', true)
