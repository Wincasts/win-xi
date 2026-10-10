-- puppet: loads, and names the spells and the weapon skill an automaton will use next, from its
-- maneuvers and its target
local debuffs = require('winxi.debuffs')
local imgui = require('imgui')
local o = H.options()
H.print('settings: visible', o.isVisible[1])

-- what the window says: every line of text drawn in a frame
local said = {}
imgui.Text = function(text) said[#said + 1] = text end
imgui.TextDisabled = function(text) said[#said + 1] = '(' .. text .. ')' end
local function shown()
    for i = #said, 1, -1 do said[i] = nil end
    H.frames(1)
    return table.concat(said, ' ')
end

-- the game: a puppetmaster (entity 1) with an automaton (2), and two enemies (7 and 8)
local game = { job = 18, buffs = {}, petMpp = 100, targeted = 0, tp = 0 }
local entities = {
    [1] = { ServerId = 1, PetTargetIndex = 2, SpawnFlags = 0x01 },
    [2] = { ServerId = 2, TargetedIndex = 0, HPPercent = 100, SpawnFlags = 0x100 },
    [7] = { ServerId = 900, Name = 'Troll Machinist', SpawnFlags = 0x10 },
    [8] = { ServerId = 901, Name = 'Wamoura', SpawnFlags = 0x10 },
}
function GetEntity(index) return entities[index] end
local memory = {
    GetPlayer = function() return { GetMainJob = function() return game.job end, GetLoginStatus = function() return 2 end,
        GetBuffs = function() return game.buffs end, GetPetMPPercent = function() return game.petMpp end } end,
    GetParty = function() return { GetMemberTargetIndex = function() return 1 end, GetMemberName = function() return 'Tester' end, GetMemberTP = function() return game.tp end } end,
    GetTarget = function() return { GetTargetIndex = function() return game.targeted end } end,
}
local core = AshitaCore
AshitaCore = setmetatable({ GetMemoryManager = function() return memory end }, { __index = core })

-- the bytes of a packet, read as the game packs them
struct.unpack = function(format, data, at)
    local low = data:byte(at) or 0
    return format == 'H' and low + (data:byte(at + 1) or 0) * 256 or low
end
-- the server's account of the automaton: the job at 0x04, head at 0x08, frame at 0x09, attachments
-- from 0x0A, and its melee, ranged and magic skill at 0x70, 0x74 and 0x78 (all three the same here)
local function describe(head, frame, skill, job, attachment)
    local bytes = {}
    for i = 0, 0x9B do bytes[i] = 0 end
    bytes[0x04], bytes[0x08], bytes[0x09], bytes[0x0C] = job or 18, head, frame, attachment or 0
    for _, at in ipairs({ 0x70, 0x74, 0x78 }) do bytes[at], bytes[at + 1] = skill % 256, math.floor(skill / 256) end
    local out = {}
    for i = 0, 0x9B do out[#out + 1] = string.char(bytes[i]) end
    H.packetData(0x044, table.concat(out))
end
local function cast(spell, target, message) debuffs.Action({ actor_id = 2, category = 4, param = spell, targets = { { id = target, actions = { { message = message or 2 } } } } }) end
local now = 1000
os.time = function() return now end

H.play(true); H.frames(3)
H.print('nothing targeted:', shown())
game.targeted = 7
H.print('not yet told of the automaton:', shown())
describe(1, 0x20, 120, 4); H.print('another job\'s packet is not read', shown():find('Not told') ~= nil)
describe(1, 0x20, 120)
H.print('Harlequin, no maneuvers:', shown())
game.buffs = { 306 }; H.print('Light:', shown())
game.buffs = { 306, 307 }; H.print('Light and Dark:', shown())
game.buffs = { 305, 301, 255, 255 }; H.print('Water and Ice:', shown())
game.buffs = {}; cast(230, 900); H.print('Bio is on it:', shown())
cast(56, 900, 236); cast(220, 900, 236); H.print('and Slow and Poison:', shown())
now = now + 400; H.print('all worn off:', shown())
entities[2].TargetedIndex = 8; cast(23, 901); H.print('the automaton fights another, with Dia on it:', shown())
entities[2].TargetedIndex = 0
describe(1, 0x20, 30); H.print('skill 30:', shown())
describe(5, 0x23, 120); game.buffs = { 303 }; H.print('Soulsoother, Earth:', shown())
describe(6, 0x23, 120); game.buffs = {}; H.print('Spiritreaver, no Dark:', shown())
game.petMpp = 50; H.print('Spiritreaver, low on MP:', shown())
game.petMpp = 100; game.buffs = { 307, 301, 301 }; H.print('Spiritreaver, Dark and two Ice:', shown())
describe(2, 0x21, 120); H.print('Valoredge frame:', shown())
describe(2, 0x20, 120); H.print('Valoredge head:', shown())
game.targeted = 0; game.buffs = {}
describe(1, 0x20, 120); H.print('Harlequin frame, skill 120:', shown())
describe(1, 0x20, 200); H.print('skill 200:', shown())
game.buffs = { 304 }; H.print('Thunder:', shown())
describe(2, 0x21, 200); game.buffs = {}; H.print('Valoredge frame:', shown())
game.buffs = { 300 }; H.print('Fire:', shown())
game.buffs = { 300, 304, 304 }; H.print('Fire and two Thunder:', shown())
describe(3, 0x22, 200); game.buffs = { 302 }; H.print('Sharpshot frame, Wind:', shown())
describe(2, 0x21, 200, 18, 3); game.buffs = {}; H.print('with an Inhibitor, the master without TP:', shown())
game.tp = 1000; H.print('and with it:', shown())
game.tp = 0; describe(1, 0x20, 120); game.targeted = 7
entities[1].PetTargetIndex = 0; H.print('no automaton out: nothing drawn', shown() == '')
entities[1].PetTargetIndex = 2; game.job = 4; H.print('another job: nothing drawn', shown() == '')
game.job = 18
H.print('/puppet config kept from the game', H.command('/puppet config')); H.frames(1)
H.command('/puppet'); H.print('/puppet hides it', o.isVisible[1] == false)
H.unload(); H.print('unload ran; saves', H.saves() > 0)
