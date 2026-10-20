package.path = 'addons/parse/?.lua;tests/fixtures/?.lua;' .. package.path
PARSE = { now = 0 }
ashita.time.qpc = function() return { q = PARSE.now } end
ashita.addons_version = 4.3
addon_feature = { use_packet_chunks = 1 }
addon.instance = { enable_feature = function(_, feature) PARSE.feature = feature end }
local register = ashita.events.register
ashita.events.register = function(event, name, callback)
    if name == 'parse_packet' then PARSE.packet = callback end
    return register(event, name, callback)
end
local session = require('parse_session')
local new = session.New
session.New = function() PARSE.session = new(); return PARSE.session end
local entities = {
    [1] = { id = 1, name = 'Tester' },
    [2] = { id = 2, name = 'Pet', flags = 0x10 },
    [3] = { id = 100, name = 'Crab', flags = 0x10 },
}
local manager = {
    GetServerId = function(_, index) return entities[index] and entities[index].id or 0 end,
    GetName = function(_, index) return entities[index] and entities[index].name end,
    GetSpawnFlags = function(_, index) return entities[index] and entities[index].flags or 0 end,
    GetTrustOwnerTargetIndex = function() return 0 end,
    GetPetTargetIndex = function(_, index) return index == 1 and 2 or 0 end,
    GetFellowTargetIndex = function() return 0 end,
}
local memory = AshitaCore.GetMemoryManager
AshitaCore.GetMemoryManager = function(...)
    local result = memory(...)
    local party = result:GetParty()
    -- Solo local player: slot zero need not have the party-active flag.
    party.GetMemberIsActive = function() return 0 end
    party.GetMemberServerId = function() return 1 end
    party.GetMemberTargetIndex = function() return 1 end
    result.GetParty = function() return party end
    result.GetEntity = function() return manager end
    return result
end
dofile('addons/parse/parse.lua')
