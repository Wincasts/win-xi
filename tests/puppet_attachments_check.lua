-- Run with: luajit tests/harness.lua puppet addons/puppet/puppet.lua tests/puppet_attachments_check.lua
package.path = 'addons/libs/?.lua;' .. package.path; require('winxi.gamedata').Root('addons/libs/winxi/data/') -- the server's sets, from the repository's data
local bonuses = require('attachments')
local definitions = require('winxi.gamedata').Read('attachments', 'index').attachments
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end
local function text(id, maneuvers, equipped, overdrive)
    equipped = equipped or {}; equipped[id] = true
    for _, row in ipairs(bonuses.Rows(equipped, { maneuvers = maneuvers or {}, overdrive = overdrive, frame = 33 })) do
        if row.name == definitions[id].name then return row.text, row.count end
    end
end
check(text(98, { earth = 1 }) == 'Defense +15%', 'era armor plate, not PDT')
check(text(70, { wind = 2 }) == 'Gear haste +20%', 'era gear haste')
check(text(33, { ice = 3 }) == 'Magic cooldown -8s', 'era mana booster')
check(text(1, { fire = 1 }) == 'Enmity +15', 'era Strobe')
check(text(1, { fire = 1, light = 1 }, { [198] = true }) == 'Enmity +18', 'Optic Fiber scales eligible modifiers')
check(text(69, { wind = 1, light = 3 }, { [198] = true }) == 'Shot delay reduction +4s; Ranged accuracy -30', 'Drum penalties and no Optic scaling')
check(text(162, { water = 3 }) == 'Extra burden decay +1/tick', 'era Heatsink')
check(text(1, { fire = 1 }, nil, true) == 'Enmity +40', 'Overdrive raises active element to three')
check(text(1, {}, nil, true) == 'Enmity +5', 'Overdrive does not create maneuvers')
check(text(225, { dark = 2 }):find('Refresh +2/tick', 1, true), 'era Mana Tank has no max MP scaling')
check(text(196, { light = 1 }):find('2 + 0.4% max HP', 1, true), 'era Repair Kit II formula')
check(text(99, { earth = 2 }):find('-30%', 1, true), 'era Analyzer special handling')
check(text(97, { earth = 3 }) == 'Stoneskin 100 HP on activation', 'era Shock Absorber')
check(text(71, { wind = 2 }) == 'Blink 3 shadows; consumes Wind', 'era Replicator')
check(text(16, { fire = 2 }) == 'Attack +24%; Ranged attack +24%', 'Tension Spring V by the name the server keys it by')
check(text(196, { light = 1 }, nil, nil):find('Max HP', 1, true), 'Repair Kit names its frame bonus')
local function frameText(id, frame)
    for _, row in ipairs(bonuses.Rows({ [id] = true }, { maneuvers = {}, frame = frame })) do return row.text end
end
check(frameText(205, 33):find('Max HP +16.6667%', 1, true), 'Repair Kit IV on Valoredge: 4 / 24, the server\'s divisor')
check(frameText(235, 35):find('Max MP +16.6667%', 1, true), 'Mana Tank IV on Stormwaker: 4 / 24')
check(frameText(235, 34):find('No max MP bonus on this frame', 1, true), 'Mana Tank on Sharpshot: no MP to raise')
check(frameText(235, nil):find('depends on frame', 1, true), 'frame not known yet')
check(#bonuses.Rows({}) == 0, 'empty fitting')
check(bonuses.Rows({ [255] = true })[1].text == 'Not in Phoenix\'s data', 'unknown attachment not invented, the server named from its data')
for id, def in pairs(definitions) do
    for _, mod in ipairs(def.mods) do
        check(mod.values[4] ~= nil or def.base ~= nil, 'complete data for ' .. id)
    end
end

local imgui = require('imgui')
local game = { buffs = { 300 }, pet = 2 }
function GetEntity(id)
    if id == 1 then return { ServerId = 1, PetTargetIndex = game.pet } end
    if id == 2 then return { ServerId = 2, HPPercent = 100 } end
end
local original = AshitaCore
local memory = {
    GetPlayer = function() return {
        GetMainJob = function() return 18 end, GetLoginStatus = function() return 2 end,
        GetBuffs = function() return game.buffs end, GetPetMPPercent = function() return 100 end,
        GetPetTP = function() return 0 end,
    } end,
    GetParty = function() return {
        GetMemberTargetIndex = function() return 1 end, GetMemberServerId = function() return 1 end,
        GetMemberHPPercent = function() return 100 end, GetMemberName = function() return 'Tester' end,
    } end,
}
AshitaCore = setmetatable({ GetMemoryManager = function() return memory end }, { __index = original })
H.play(true); H.frames(3)
local o = H.options()
-- Reload through settings so the fixture exercises persisted equipped attachment restoration.
o.automaton.attachments = { 1 }; o.automaton.head = 1; o.automaton.frame = 33
-- Use the real extended-job packet path to fit Strobe.
struct.unpack = function(format, data, at)
    local value = 0
    for i = ({ B = 1, H = 2, I = 4 })[format] - 1, 0, -1 do value = value * 256 + (data:byte(at + i) or 0) end
    return value
end
local bytes = {}
for i = 0, 155 do bytes[i + 1] = string.char(i == 4 and 18 or i == 8 and 1 or i == 9 and 33 or i == 10 and 1 or 0) end
H.packetData(0x044, table.concat(bytes))
o.showAttachments[1] = true
local said = {}
imgui.Text = function(s) said[#said + 1] = s end
imgui.TextColored = function(_, s) said[#said + 1] = s end
imgui.TextDisabled = function(s) said[#said + 1] = s end
local function drawn()
    H.frames(20); said = {}; H.frames(1); return table.concat(said, '|')
end
check(drawn():find('Enmity +15', 1, true), 'bonus window draws fitted current contribution')
game.buffs = { 300, 300 }
check(drawn():find('Enmity +25', 1, true), 'maneuver changes refresh window')
o.showAttachments[1] = false
check(not drawn():find('Enmity', 1, true), 'bonus toggle hides window')
o.showAttachments[1] = true; game.pet = 0
check(not drawn():find('Enmity', 1, true), 'no pet hides contributions')
H.print(('puppet attachments: %d assertions passed'):format(checks))
