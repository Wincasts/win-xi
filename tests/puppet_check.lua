-- puppet: loads, and lists what an automaton will do next, the spell and the weapon skill named, from
-- its maneuvers, its attachments and its target
local debuffs = require('winxi.debuffs')
local imgui = require('imgui')
local o = H.options()
H.print('Always Show starts on', o.alwaysShow[1], '| the priority list on', o.showPriority[1], '| debug information off', o.showDebug[1] == false)
o.alwaysShow[1] = false; o.showBurden[1] = false -- each is looked at by itself further down
H.print('settings: visible', o.isVisible[1])

-- what the window says: every line of text drawn in a frame, and the colour of each coloured one
local said, colored = {}, {}
imgui.Text = function(text) said[#said + 1] = text end
imgui.TextDisabled = function(text) said[#said + 1] = '(' .. text .. ')' end
imgui.TextColored = function(color, text) said[#said + 1] = text; colored[#colored + 1] = { text, { color[1], color[2], color[3], color[4] } } end -- the colour copied: the addon reuses its tables
-- the colour a word was last written in
local function colorOf(word)
    for i = #colored, 1, -1 do
        if colored[i][1]:find(word, 1, true) then return colored[i][2] end
    end
    return nil
end
local function same(a, b) return a ~= nil and b ~= nil and math.abs(a[1] - b[1]) < 0.01 and math.abs(a[2] - b[2]) < 0.01 and math.abs(a[3] - b[3]) < 0.01 and math.abs(a[4] - b[4]) < 0.01 end
local fire, ice, thunder, dark = { 1.00, 0.54, 0.48, 1 }, { 0.65, 0.89, 1.00, 1 }, { 0.85, 0.65, 1.00, 1 }, { 0.60, 0.56, 0.72, 1 }
local function shown()
    H.frames(10) -- time enough to have faded in, or out
    for i = #said, 1, -1 do said[i] = nil end
    for i = #colored, 1, -1 do colored[i] = nil end
    H.frames(1)
    return table.concat(said, ' ')
end
-- the same without the wait: what is there the frame after a change
local function atOnce()
    for i = #said, 1, -1 do said[i] = nil end
    for i = #colored, 1, -1 do colored[i] = nil end
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
-- the server's account of the automaton: the job at 0x04, head at 0x08, frame at 0x09, the attachments
-- fitted from 0x0A, and its melee, ranged and magic skill at 0x70, 0x74 and 0x78 (all three the same here)
local function describe(head, frame, skill, job, attachments)
    local bytes = {}
    for i = 0, 0x9B do bytes[i] = 0 end
    bytes[0x04], bytes[0x08], bytes[0x09] = job or 18, head, frame
    for slot, attachment in ipairs(attachments or {}) do bytes[0x0A + slot - 1] = attachment end
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
H.print('Bio II in dark', same(colorOf('Bio II'), dark), '| Slapstick in thunder', same(colorOf('Slapstick'), thunder))
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
describe(2, 0x20, 120); game.buffs = {}; H.print('Valoredge head on a Harlequin frame, nobody to heal: Magic names nothing', shown())
game.buffs = { 306 }; H.print('with Light, the master whole: still nothing, not Heal', shown())
pet.HPPercent = 45; H.print('the automaton at 45%: Heal', shown()); pet.HPPercent = 100
game.hp = 38; H.print('the master at 38% under one Light: Heal', shown()); game.buffs = {}; H.print('and without the Light, at 38%: nothing', shown()); game.hp = 100
describe(2, 0x20, 120, nil, { 195 }); game.hp = 60; H.print('a Damage Gauge, the master at 60%, no Light: nothing (it heals at 50)', shown())
game.hp = 48; H.print('at 48%: Heal', shown()); game.hp = 60; game.buffs = { 306 }; H.print('at 60% under one Light: Heal (75)', shown()); game.buffs = {}; game.hp = 100
describe(3, 0x22, 200); game.buffs = { 302 }; H.print('Sharpshot frame, Wind:', shown())
describe(1, 0x20, 120, 4); H.print('another job\'s packet is not read', shown():find('Daze') ~= nil)
-- the attachments that act on their own: a row each while fitted, in the maneuver's colour
describe(2, 0x21, 200, nil, { 1, 194, 97, 71, 6 }); game.buffs = {}
H.print('Valoredge with Strobe, Flashbulb, Shock Absorber, Replicator and Reactive Shield, no maneuvers:', shown())
game.buffs = { 300 }; H.print('Fire: Provoke and Blaze Spikes ready', shown(), '| Provoke in fire', same(colorOf('Provoke'), fire))
game.buffs = { 302 }; H.print('Wind, the automaton whole: Blink waits on its HP', shown())
pet.HPPercent = 40; H.print('at 40%:', shown()); pet.HPPercent = 100
describe(2, 0x21, 200, nil, { 230, 226, 197, 232 }); game.buffs = { 307 }
H.print('Economizer, Mana Converter, Eraser and Disruptor on a frame with no MP, Dark up: the two MP ones never, Disruptor ready but not next', shown())
describe(1, 0x20, 120, nil, { 230, 226 }); game.petMpp = 35; H.print('on a Harlequin at 35% MP, one Dark: Economizer at 40, Mana Converter at 40', shown()); game.petMpp = 100
describe(1, 0x20, 120); game.buffs = {}

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
-- a spell's start packet says which magic begins in a four-letter code: white "cawh", black "cabk"; one broken off "spwh"
local white, black, whiteBroken = 0x68776163, 0x6B626163, 0x68777073
local function list() return shown() end
entities[1].PetTargetIndex = 2; H.frames(2); fight(900); now = now + 400
describe(1, 0x20, 120); H.print('Harlequin, fresh:', list())
did(8, black, 231); cast(231, 900); H.print('it casts Bio II (black magic):', list())
H.frames(400); H.print('twelve seconds on:', list())
game.hp = 25; H.print('the master at 25%: the heal timer shown now it is wanted, as before:', list())
did(8, white, 1); game.hp = 100; H.print('a cure cast (white magic) and the master whole: Heal still shows its timer', list()); H.frames(1100); game.hp = 25
H.frames(700); H.print('the timers run out:', list()); game.hp = 100
game.buffs = { 306 }; game.hp = 35; H.print('Light, the master at 35%: heal comes first:', list(), '| Heal in light', same(colorOf('Heal'), { 1, 1, 1, 1 })); game.buffs = {}; game.hp = 100
game.petTp = 1200; H.print('TP ready, a spell ready too: the spell comes first:', list(), '| Slapstick in thunder', same(colorOf('Slapstick'), thunder))
did(8, white, 220); H.print('the spell just cast: the weapon skill is next:', list()); game.petTp = 300
-- the weapon skill against the spells' timers, at the rate the automaton gains TP, which the addon
-- samples from the game every frame (a frame is 0.03 s here)
local tpRate = require('tp')
tpRate.Clear(); game.petTp = 300; H.frames(1); game.petTp = 450; H.frames(170); game.petTp = 600; H.frames(170)
H.print('TP 300 to 600 in five seconds: the weapon skill in ~7s, before the spell:', list())
tpRate.Clear(); game.petTp = 300; H.frames(1); game.petTp = 310; H.frames(170); game.petTp = 320; H.frames(170)
H.print('a trickle: the spell comes first:', list())
game.petTp = 200; H.frames(2); H.print('a fall in TP starts the rate again: no rate, the spell waiting: the spell:', list())
tpRate.Clear()
did(8, whiteBroken, 0); did(8, white, 1); tracker.Action({ actor_id = 77, category = 8, param = white, targets = { { id = 900, actions = { { param = 23 } } } } }, 2)
H.print('a casting broken off, and someone else\'s, change nothing; a cure starts the heal timer:', list())
tracker.Clear(); describe(3, 0x22, 200); H.print('Sharpshot frame:', list()); did(11, 1949); H.print('it shoots:', list())
describe(2, 0x21, 200); H.print('Valoredge frame:', list()); did(11, 1944); H.print('it bashes:', list())
describe(2, 0x21, 200, nil, { 1, 97 }); game.buffs = { 300, 303 }; H.print('Strobe and Shock Absorber, Fire and Earth up:', list())
did(11, 1945); did(11, 1946); H.print('it provokes and puts up stoneskin:', list()); H.frames(1100); H.print('33 seconds on:', list()); game.buffs = {}
describe(4, 0x23, 120); game.buffs = { 301 }; tracker.Clear(); H.print('Stormwaker, Ice:', list()); game.buffs = {}
describe(5, 0x23, 120); H.print('Soulsoother:', list())
describe(6, 0x23, 120); H.print('Spiritreaver, no Dark:', list())
describe(1, 0x20, 120); o.showPriority[1] = false; entities[1].PetTargetIndex = 0; fight(0); tracker.Clear(); shown()
o.showBurden[1] = true
-- the burden of each element: 35 of each to start, one off every three seconds, and what a maneuver adds
-- how fast the automaton gains TP, from its TP frame by frame
tpRate.Clear(); H.print('TP rate: nothing seen', tpRate.Until(1000, 0) == nil)
tpRate.Sample(100, 0); tpRate.Sample(100, 1); tpRate.Sample(160, 6); H.print('100 then 160 six seconds on: 10 a second', tpRate.Rate(6), '| 84 seconds to 1000', tpRate.Until(1000, 6))
tpRate.Sample(1000, 90); H.print('with 1000: 0', tpRate.Until(1000, 90))
tpRate.Sample(0, 91); H.print('a weapon skill, TP falls: no rate again', tpRate.Rate(91) == nil, '| nor a time', tpRate.Until(1000, 91) == nil)
tpRate.Sample(50, 92); H.print('too soon to say', tpRate.Rate(92) == nil); tpRate.Sample(80, 95); H.print('three seconds on: 20 a second', tpRate.Rate(95))
tpRate.Sample(80, 200); H.print('the old samples go, but a rate stays while the TP sits', tpRate.Rate(200) ~= nil); tpRate.Clear()
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
-- from what the master does (the priority list is off here: the figures are all that is coloured)
local figures = colored
local function drawn()
    for i = #said, 1, -1 do said[i] = nil end
    for i = #figures, 1, -1 do figures[i] = nil end
    H.frames(1)
    local out = {}
    for _, figure in ipairs(figures) do out[#out + 1] = figure[1] end
    return table.concat(out, ' ')
end
local faint = { 1, 1, 1, 0.5 }
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
H.print('dummy data, no automaton out:', shown(), '| Provoke in fire', same(colorOf('Provoke'), fire), '| and the figures', drawn())
setDummy(false); H.print('switched off: gone', shown() == ''); o.showPriority[1] = false
-- transparent: nothing of the window's own, and every word outlined over the game instead of imgui's text
o.transparent[1] = true; o.alwaysShow[1] = true; entities[1].PetTargetIndex = 2; fight(900)
local before = H.calls['draw.AddText'] or 0
local words = shown()
H.print('Transparent: nothing through imgui\'s text', words == '', '| written outlined on the draw list', (H.calls['draw.AddText'] or 0) > before)
o.transparent[1] = false; before = H.calls['draw.AddText'] or 0; H.print('off again: imgui\'s text', shown() ~= '', '| nothing more outlined', (H.calls['draw.AddText'] or 0) == before)
entities[1].PetTargetIndex = 0; o.alwaysShow[1] = false; fight(0); shown()
H.print('/puppet config kept from the game', H.command('/puppet config')); H.frames(1)
H.command('/puppet'); H.print('/puppet hides it', o.isVisible[1] == false, '| and says so:', H.printed[#H.printed])
H.command('/puppet'); H.print('and shows it again:', H.printed[#H.printed])
H.unload(); H.print('unload ran; saves', H.saves() > 0)
