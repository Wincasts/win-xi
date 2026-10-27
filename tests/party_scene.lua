-- party, drawn: a full party with pets and two other alliance parties, something targeted, an
-- invitation and treasure waiting; then the same filled with sample data; for tests/capture.lua.
--
-- The saved settings are a character's own from before the addon's settings were set out afresh, so
-- what is drawn from them now is to be what was drawn from them then. Variants change them first:
--   plain    as saved
--   bare     the values, outline and bookends switched off, a larger scale, and the target's debuffs on
if CAPTURE.loading then
    CAPTURE.tweak = function(saved, variant)
        saved.showConfig[1] = false
        if variant == 'bare' then
            local us = saved.tools.us
            us.xivShowMp[1], us.xivShowTp[1], us.xivOutline[1], us.xivBookends[1] = false, false, false, false
            us.xivScale[1] = 150
            us.sortByRole[1] = true
            us.inviteCorner = 'BottomLeft'
            saved.tools.tgt.mainWindow.showStatus[1] = true
            require('winxi.theme').Get().TextOutline = 0 -- the outline is the theme's now: off, as xivOutline had it
        end
    end
    return
end

-- the alliance: who is in each of its eighteen places
local jobs = { WAR = 1, MNK = 2, WHM = 3, BLM = 4, RDM = 5, THF = 6, PLD = 7, BRD = 10, SMN = 15 }
local function member(name, main, sub, hp, hpp, mp, mpp, tp, extra)
    local m = { name = name, main = jobs[main], sub = jobs[sub] or 0, hp = hp, hpp = hpp, mp = mp, mpp = mpp, tp = tp, zone = 100, flags = 0, active = 1 }
    for key, value in pairs(extra or {}) do m[key] = value end
    return m
end
local places = {
    [0] = member('Tester', 'RDM', 'WHM', 1180, 92, 640, 80, 1250, { flags = 4 + 8 }),   -- leads the party and the alliance
    [1] = member('Ironwall', 'PLD', 'WAR', 1650, 61, 180, 45, 300),
    [2] = member('Quickblade', 'THF', 'WAR', 870, 44, 0, 0, 2100),                       -- no MP to have; targeted
    [3] = member('Longnamedmage', 'BLM', 'WHM', 410, 22, 0, 0, 0),                       -- out of MP, not without it
    [4] = member('Farawaybard', 'BRD', 'WHM', 900, 100, 210, 100, 0),                    -- a long way off
    [5] = member('Elsewhere', 'WHM', 'BLM', 0, 0, 0, 0, 0, { zone = 230 }),              -- in another area
    [6] = member('Secondlead', 'WAR', 'MNK', 1500, 100, 0, 0, 1000, { flags = 4 }),
    [7] = member('Summoner', 'SMN', 'WHM', 700, 70, 900, 95, 0),
    [8] = member('Monk', 'MNK', 'WAR', 1900, 88, 0, 0, 450),
    [9] = member('Healer', 'WHM', 'SMN', 650, 55, 1020, 99, 20),
    [12] = member('Thirdlead', 'RDM', 'BLM', 1000, 76, 500, 50, 0, { flags = 4 }),
    [13] = member('Lastone', 'THF', 'MNK', 950, 31, 0, 0, 3000),
}
local party = setmetatable({
    GetAlliancePartyMemberCount1 = function() return 6 end,
    GetAlliancePartyMemberCount2 = function() return 4 end,
    GetAlliancePartyMemberCount3 = function() return 2 end,
}, { __index = function(t, k)
    local field = ({ GetMemberName = 'name', GetMemberServerId = 'id', GetMemberZone = 'zone', GetMemberFlagMask = 'flags', GetMemberTargetIndex = 'index',
        GetMemberMainJob = 'main', GetMemberSubJob = 'sub', GetMemberHPPercent = 'hpp', GetMemberMPPercent = 'mpp', GetMemberHP = 'hp',
        GetMemberMP = 'mp', GetMemberTP = 'tp', GetMemberIsActive = 'active' })[k]
    local f = function(_, place)
        local m = places[place]
        if field == nil then return 0 end
        if m == nil then return field == 'name' and '' or 0 end
        return m[field]
    end
    rawset(t, k, f)
    return f
end })
for place, m in pairs(places) do m.id, m.index = 1000 + place, 100 + place end

-- what is around: the members themselves, two pets, and a monster
local entities = {}
for place, m in pairs(places) do
    entities[m.index] = { Name = m.name, ServerId = m.id, HPPercent = m.hpp, Distance = (2 + place) ^ 2, SpawnFlags = 1, TargetedIndex = 0 }
end
entities[104].Distance = 40 ^ 2                                  -- beyond casting range
entities[100].PetTargetIndex, entities[102].PetTargetIndex = 300, 302
entities[300] = { Name = 'Carbuncle', ServerId = 5000, HPPercent = 80, Distance = 9 }
entities[302] = { Name = 'FunguarFamiliar', ServerId = 5002, HPPercent = 37, Distance = 49 }
entities[500] = { Name = 'Greater Colibri', ServerId = 9000, HPPercent = 62, Distance = 12.3 ^ 2, SpawnFlags = 16, TargetedIndex = 100 }
entities[102].TargetedIndex = 500                                -- the member targeted is fighting the monster
GetEntity = function(index) return entities[index] end
GetPlayerEntity = function() return entities[100] end

local zero = setmetatable({}, { __index = function(t, k) local f = function() return 0 end rawset(t, k, f) return f end })
local buffs = { 40, 41, 0, 255 }
local player = setmetatable({ GetStatusIcons = function() return buffs end, GetMPMax = function() return 800 end, GetHPMax = function() return 1280 end,
    GetPetMPPercent = function() return 60 end, GetPetTP = function() return 1200 end, GetMainJob = function() return 5 end, GetSubJob = function() return 3 end,
    GetLoginStatus = function() return 2 end },
    { __index = zero })
local targets = setmetatable({ GetTargetIndex = function(_, which) return which == 0 and 102 or 0 end, GetIsActive = function(_, which) return which == 0 and 1 or 0 end,
    GetIsSubTargetActive = function() return 0 end, GetServerId = function(_, which) return which == 0 and 1002 or 0 end, GetSubTargetFlags = function() return 0 end },
    { __index = zero })
local core = AshitaCore
local inventory = core.GetMemoryManager():GetInventory()
local memory = setmetatable({ GetParty = function() return party end, GetPlayer = function() return player end, GetTarget = function() return targets end,
    GetInventory = function() return inventory end, GetEntity = function() return zero end }, { __index = function() return function() return zero end end })
-- a status icon is whatever the game has for it: here a blank one of the right size
function table.map(t, f) local mapped = T{} for i, v in ipairs(t) do mapped[i] = f(v) end return mapped end
local blank = T{} for i = 1, 40 + 32 * 32 * 4 do blank[i] = 0 end
local resources = setmetatable({ GetStatusIconByIndex = function() return { Bitmap = { totable = function() return blank end }, ImageSize = 4136 } end,
    GetString = function(_, _, id) return id == 230 and 'SOUTHERN SAN DORIA' or ('Area %d'):format(id) end }, { __index = function() return function() return nil end end })
AshitaCore = setmetatable({ GetMemoryManager = function() return memory end, GetResourceManager = function() return resources end }, { __index = core })

-- a packet's bytes are read as the game's library reads them
struct.unpack = function(format, data, at)
    if format == 'c16' then return data:sub(at, at + 15) elseif format == 'B' or format == 'H' then return data:byte(at) or 0 end
    return 0
end

H.load()
H.play(true)
H.frames(40)                                                       -- past every fade in

CAPTURE.start(); H.frames(1); CAPTURE.dump('a party, pets, two alliance parties and a target')

H.pool(2)
H.packetData(0x0DC, ('\0'):rep(0x0B) .. string.char(5) .. ('\0'):rep(20))
H.frames(20)
CAPTURE.start(); H.frames(1); CAPTURE.dump('with an alliance invite and treasure waiting')

assert(H.command('/pt'), 'Party settings command must be handled')
assert(CAPTURE.options.showConfig[1], 'settings must be open for the organize scene')
require('winxi.organize').SetActive(true)
H.packetOut(0x074); H.pool(0); H.frames(20)
assert(CAPTURE.options.showConfig[1] and require('winxi.organize').IsActive(), 'organize scene must remain active')
CAPTURE.start(); H.frames(1); CAPTURE.dump('filled with sample data, the settings open')
