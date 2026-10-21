-- puppet: loads, and names the spells and the weapon skill an automaton will use next, from its
-- maneuvers and its target
local debuffs = require('winxi.debuffs')
local imgui = require('imgui')
local o = H.options()
H.print('Always Show starts on', o.alwaysShow[1], '| the priority list on', o.showPriority[1], '| debug information off', o.showDebug[1] == false)
o.alwaysShow[1] = false; o.showPriority[1] = false -- each is looked at by itself further down
H.print('settings: visible', o.isVisible[1])

-- what the window says: every line of text drawn in a frame
local said = {}
imgui.Text = function(text) said[#said + 1] = text end
imgui.TextDisabled = function(text) said[#said + 1] = '(' .. text .. ')' end
local function shown()
    H.frames(10) -- time enough to have faded in, or out
    for i = #said, 1, -1 do said[i] = nil end
    H.frames(1)
    return table.concat(said, ' ')
end
-- the same without the wait: what is there the frame after a change
local function atOnce()
    for i = #said, 1, -1 do said[i] = nil end
    H.frames(1)
    return table.concat(said, ' ')
end

-- the game: a puppetmaster (entity 1) with an automaton (2), and two enemies (7 and 8)
local game = { job = 18, buffs = {}, petMpp = 100, petTp = 0, hp = 100 }
local entities = {
    [1] = { ServerId = 1, PetTargetIndex = 2, SpawnFlags = 0x01 },
    [2] = { ServerId = 2, TargetedIndex = 0, HPPercent = 100, SpawnFlags = 0x100 },
    [7] = { ServerId = 900, Name = 'Troll Machinist', SpawnFlags = 0x10 },
    [8] = { ServerId = 901, Name = 'Wamoura', SpawnFlags = 0x10 },
}
function GetEntity(index) return entities[index] end
local memory = {
    GetPlayer = function() return { GetMainJob = function() return game.job end, GetLoginStatus = function() return 2 end,
        GetBuffs = function() return game.buffs end, GetPetMPPercent = function() return game.petMpp end, GetPetTP = function() return game.petTp end } end,
    GetParty = function() return { GetMemberTargetIndex = function() return 1 end, GetMemberName = function() return 'Tester' end, GetMemberServerId = function() return 1 end,
        GetMemberHPPercent = function() return game.hp end } end,
}
local core = AshitaCore
AshitaCore = setmetatable({ GetMemoryManager = function() return memory end }, { __index = core })

-- the bytes of a packet, read as the game packs them
struct.unpack = function(format, data, at)
    local value = 0
    for i = ({ B = 1, H = 2, I = 4 })[format] - 1, 0, -1 do value = value * 256 + (data:byte(at + i) or 0) end
    return value
end
-- the packet that keeps a pet and its master in step: the master at 0x08, and at 0x14 what the pet is
-- attacking, or nothing
local function number(value) return string.char(value % 256, math.floor(value / 256) % 256, math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256) end
local function fight(enemy, master)
    H.packetData(0x068, ('\0'):rep(8) .. number(master or 1) .. ('\0'):rep(8) .. number(enemy) .. ('\0'):rep(20))
end
-- the server's account of the automaton: the job at 0x04, head at 0x08, frame at 0x09, and its melee,
-- ranged and magic skill at 0x70, 0x74 and 0x78 (all three the same here)
local function describe(head, frame, skill, job)
    local bytes = {}
    for i = 0, 0x9B do bytes[i] = 0 end
    bytes[0x04], bytes[0x08], bytes[0x09] = job or 18, head, frame
    for _, at in ipairs({ 0x70, 0x74, 0x78 }) do bytes[at], bytes[at + 1] = skill % 256, math.floor(skill / 256) end
    local out = {}
    for i = 0, 0x9B do out[#out + 1] = string.char(bytes[i]) end
    H.packetData(0x044, table.concat(out))
end
local function cast(spell, target, message) debuffs.Action({ actor_id = 2, category = 4, param = spell, targets = { { id = target, actions = { { message = message or 2 } } } } }) end
local now = 1000
os.time = function() return now end

local pet = entities[2]
H.play(true); H.frames(3)
describe(1, 0x20, 120)
H.print('the automaton fighting nothing: nothing drawn', shown() == '')
fight(900, 55); H.print('nor when it is someone else\'s pet that fights', shown() == '')
fight(900)
H.print('Harlequin, no maneuvers:', shown())
game.buffs = { 306 }; H.print('Light:', shown())
game.buffs = { 306, 307 }; H.print('Light and Dark:', shown())
game.buffs = { 305, 301, 255, 255 }; H.print('Water and Ice:', shown())
game.buffs = {}; cast(230, 900); H.print('Bio is on it:', shown())
cast(56, 900, 236); cast(220, 900, 236); H.print('and Slow and Poison:', shown())
now = now + 400; H.print('all worn off:', shown())
fight(901); cast(23, 901); H.print('it fights another, with Dia on it:', shown())
fight(900)
describe(1, 0x20, 30); H.print('skill 30:', shown())
describe(1, 0x20, 200); H.print('skill 200:', shown())
game.buffs = { 304 }; H.print('Thunder:', shown())
describe(5, 0x23, 120); game.buffs = { 303 }; H.print('Soulsoother, Earth:', shown())
describe(6, 0x23, 120); game.buffs = {}; H.print('Spiritreaver, no Dark: no spells named', shown())
game.petMpp = 50; H.print('Spiritreaver, low on MP:', shown())
game.petMpp = 100; game.buffs = { 307, 301, 301 }; H.print('Spiritreaver, Dark and two Ice:', shown())
describe(2, 0x21, 200); game.buffs = {}; H.print('Valoredge frame: no spells named', shown())
game.buffs = { 300 }; H.print('Fire:', shown())
game.buffs = { 300, 304, 304 }; H.print('Fire and two Thunder:', shown())
describe(2, 0x20, 120); game.buffs = {}; H.print('Valoredge head on a Harlequin frame: no spells named', shown())
describe(3, 0x22, 200); game.buffs = { 302 }; H.print('Sharpshot frame, Wind:', shown())
describe(1, 0x20, 120, 4); H.print('another job\'s packet is not read', shown():find('Daze') ~= nil)

describe(1, 0x20, 120); game.buffs = {}; shown()
fight(0); H.print('the fight is over: still there the frame after, as it was', atOnce())
H.print('and gone once faded', shown() == '')
fight(900); H.print('back with the next fight', shown() ~= '')
entities[900] = { ServerId = 900, HPPercent = 0 }; H.print('the enemy has no HP left: gone', shown() == ''); entities[900] = nil
fight(900); H.packet(0x00A); H.print('a change of area: gone', shown() == ''); fight(900); shown()
entities[1].PetTargetIndex = 0; H.print('no automaton out: nothing drawn', shown() == '')
entities[1].PetTargetIndex = 2; game.job = 4; fight(900); H.print('another job: nothing drawn', shown() == '')
game.job = 18
H.print('the automaton is kept in the settings: head', o.automaton.head, '| frame', o.automaton.frame, '| magic', o.automaton.magic)
o.alwaysShow[1] = true; entities[1].PetTargetIndex = 0; fight(0); H.print('Always Show, with nothing going on: what it last showed:', shown())
o.showDebug[1] = true; H.print('with the debug information:', shown()); o.showDebug[1] = false
entities[1].PetTargetIndex = 2; cast(230, 900); game.buffs = { 306 }; H.print('the automaton out and idle: what it would open with, whatever was on the last enemy:', shown()); game.buffs = {}; entities[1].PetTargetIndex = 0
o.isVisible[1] = false; H.print('Always Show, but not Visible: nothing drawn', shown() == ''); o.isVisible[1] = true; o.alwaysShow[1] = false
-- the priority list: what the automaton might do, in its order, and how each stands
local tracker = require('tracker')
local function did(category, param, spell) tracker.Action({ actor_id = 2, category = category, param = param, targets = { { id = 900, actions = { { param = spell or 0 } } } } }, 2) end
local function list() return (shown():gsub('%(Enfeeble%).-%(WS%) %a+ ?%a* ?', '', 1)) end
o.showPriority[1] = true; entities[1].PetTargetIndex = 2; H.frames(2); fight(900); now = now + 400
describe(1, 0x20, 120); H.print('Harlequin, fresh:', list())
did(8, 24931, 231); cast(231, 900); H.print('it casts Bio II:', list())
H.frames(400); H.print('twelve seconds on:', list())
game.hp = 25; H.print('the master at 25%:', list())
H.frames(700); H.print('the timers run out:', list()); game.hp = 100
game.buffs = { 306 }; game.hp = 35; H.print('Light, the master at 35%: heal comes first:', list()); game.buffs = {}; game.hp = 100
game.petTp = 1200; H.print('TP ready: no row for it, the spell comes next:', list())
did(8, 24931, 220); H.print('the spell just cast: nothing next while it waits:', list()); game.petTp = 300
did(8, 28787, 0); did(8, 24931, 1); tracker.Action({ actor_id = 77, category = 8, param = 24931, targets = { { id = 900, actions = { { param = 23 } } } } }, 2)
H.print('a casting broken off, and someone else\'s, change nothing; a cure starts the heal timer:', list())
tracker.Clear(); describe(3, 0x22, 200); H.print('Sharpshot frame:', list()); did(11, 1949); H.print('it shoots:', list())
describe(2, 0x21, 200); H.print('Valoredge frame:', list()); did(11, 1944); H.print('it bashes:', list())
describe(4, 0x23, 120); game.buffs = { 301 }; tracker.Clear(); H.print('Stormwaker, Ice:', list()); game.buffs = {}
describe(5, 0x23, 120); H.print('Soulsoother:', list())
describe(6, 0x23, 120); H.print('Spiritreaver, no Dark:', list())
describe(1, 0x20, 120); o.showPriority[1] = false; entities[1].PetTargetIndex = 0; fight(0); tracker.Clear(); shown()
-- the burden of each element: 35 of each to start, one off every three seconds, and what a maneuver adds
local burden = require('burden')
local harlequin, valoredge, heatsink = { frame = 0x20 }, { frame = 0x21 }, { frame = 0x20, attachments = { [162] = true } }
local function maneuver(element, chance, state, at) burden.Action({ actor_id = 1, category = 6, param = 140 + element, targets = { { id = 1, actions = { { param = chance } } } } }, state or harlequin, at) end
local function at(element, when, state) local value = burden.Get(element, state or harlequin, when) return value and math.floor(value + 0.5) or '?' end
burden.Clear(); H.print('burden, the automaton out before the addon: not known', at(1, 0) == '?', '| and no chance said of it', burden.Chance(1, harlequin, 0) == 0)
maneuver(1, 0, harlequin, 0); H.print('a maneuver with no chance of overloading: 25 at the most', at(1, 0))
maneuver(2, 21, harlequin, 0); H.print('one with a chance of 21: 46', at(2, 0))
burden.Action({ actor_id = 1, category = 6, param = 136, targets = {} }, harlequin, 0)
H.print('Activate: 35 of each', at(1, 0), at(8, 0), '| half a minute on', at(1, 30), '| with a Heatsink', at(1, 30, heatsink), '| never below nothing', at(1, 600))
H.print('one more maneuver, fresh: taken to add 20, a chance of', burden.Chance(1, harlequin, 0), '| once it is down to 10: none', burden.Chance(1, harlequin, 75) == 0, '| in Overdrive: none', burden.Chance(1, { frame = 0x20, overdrive = true }, 0) == 0)
maneuver(1, 26, harlequin, 0); H.print('a Fire maneuver, the server says 26: the burden is 51', at(1, 0), '| so a maneuver adds 16: the next has a chance of', burden.Chance(1, harlequin, 0))
maneuver(1, 0, harlequin, 150); H.print('once it is down to 1, another, with no chance said: 17', at(1, 150))
maneuver(3, 0, harlequin, 60); H.print('Wind, never seen, from 15 with no chance said: 25 and not 35', at(3, 60))
H.print('Dark adds 14, a chance of', burden.Chance(8, harlequin, 0), '| and 8 on a Valoredge frame', burden.Chance(8, valoredge, 0))
maneuver(8, 0, { frame = 0x20, overdrive = true }, 0); H.print('a Dark maneuver in Overdrive, no chance said: 49 all the same', at(8, 0))
burden.Action({ actor_id = 1, category = 6, param = 309, targets = {} }, harlequin, 0); H.print('Cooldown halves it', at(8, 0), at(2, 0))
burden.Action({ actor_id = 1, category = 4, param = 141, targets = {} }, harlequin, 0); H.print('a spell with a maneuver\'s number changes nothing', at(8, 0))
-- and in the addon: the figures are drawn with the automaton out, one for each element in its colour,
-- from what the master does
local figures = {} -- what was drawn in a frame: the figure and the colour it was in
imgui.TextColored = function(color, text) figures[#figures + 1] = { text, color } end
local function drawn()
    for i = #figures, 1, -1 do figures[i] = nil end
    H.frames(1)
    local out = {}
    for _, figure in ipairs(figures) do out[#out + 1] = figure[1] end
    return table.concat(out, ' ')
end
local ice = { 0.65, 0.89, 1.00, 1 }
local fire, faint = { 1.00, 0.54, 0.48, 1 }, { 1, 1, 1, 0.5 }
local function same(a, b) return a ~= nil and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4] end
burden.Clear(); entities[1].PetTargetIndex = 2; o.alwaysShow[1] = true; shown()
H.print('the figures are drawn with the automaton out, none known yet:', drawn(), '| faint', same(figures[1] and figures[1][2], faint))
burden.Action({ actor_id = 1, category = 6, param = 136, targets = {} }, harlequin); burden.Action({ actor_id = 1, category = 6, param = 141, targets = { { id = 1, actions = { { param = 26 } } } } }, harlequin)
burden.Action({ actor_id = 1, category = 6, param = 145, targets = { { id = 1, actions = { { param = 8 } } } } }, harlequin)
H.print('Activate, a Fire maneuver at 26 and a Thunder at 8:', drawn())
H.print('each in its element\'s colour, whatever the chance: Fire', same(figures[1] and figures[1][2], fire), '| Ice', same(figures[2] and figures[2][2], ice))
o.showBurden[1] = false; H.print('not with Show Burden off', drawn() == ''); o.showBurden[1] = true
entities[1].PetTargetIndex = 0; H.print('nor with no automaton', drawn() == '')
H.packet(0x00A); entities[1].PetTargetIndex = 2; entities[2].ServerId = 3; H.frames(1)
H.print('an automaton brought into another area starts afresh', at(4, os.clock()))
entities[2].ServerId = 2; entities[1].PetTargetIndex = 0; o.alwaysShow[1] = false; shown()
-- the dummy data: every part filled, with no automaton out, and gone again when switched off
local realCheckbox = imgui.Checkbox
local function setDummy(on) imgui.Checkbox = function(id, value) if id == '##puppet.showDummy' then value[1] = on end return false end; H.command('/puppet config'); H.frames(1); H.command('/puppet config'); imgui.Checkbox = realCheckbox end
o.showPriority[1] = true; setDummy(true)
H.print('dummy data, no automaton out:', shown(), '| and the figures', drawn())
setDummy(false); H.print('switched off: gone', shown() == ''); o.showPriority[1] = false
H.print('/puppet config kept from the game', H.command('/puppet config')); H.frames(1)
H.command('/puppet'); H.print('/puppet hides it', o.isVisible[1] == false, '| and says so:', H.printed[#H.printed])
H.command('/puppet'); H.print('and shows it again:', H.printed[#H.printed])
H.unload(); H.print('unload ran; saves', H.saves() > 0)
