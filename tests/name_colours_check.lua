local custom, colours, plates = require('custom'), require('name_colours'), require('winxi.nameplates')
local o = {}; custom.Defaults(o); custom.Settle(o)
local name = { EntityIndex = 300, ServerId = 123, Category = plates.Category.Monster, Flags = 0 }
local id, hp, status, claim = 123, 50, 0, 0
local entities = {
    GetServerId = function() return id end, GetHPPercent = function() return hp end,
    GetStatus = function() return status end, GetClaimStatus = function() return claim end,
}
local party = { GetMemberIsActive = function(_, slot) return slot == 0 or slot == 7 end,
    GetMemberServerId = function(_, slot) return slot == 0 and 777 or (slot == 7 and 888 or 0) end }
local memory = { GetParty = function() return party end }
local function enable(key, state, r, g, b)
    local p = o.nameColours[key][state]; p.enabled[1] = true; p.color = { r, g, b, 1 }
end
assert(colours.Resolve(o, name, entities, nil, false) == nil, 'all overrides default to game/format colour')
assert(colours.Context(o, memory) == nil, 'default colours avoid party scans')
assert(not colours.InCombat(name, entities))
status = 1; assert(colours.InCombat(name, entities))
for _, value in ipairs({ 0, -1, 101, 0/0 }) do hp = value; assert(not colours.InCombat(name, entities)) end
hp = 50; id = 456; assert(not colours.InCombat(name, entities)); id = 123
local getStatus = entities.GetStatus; entities.GetStatus = nil; assert(not colours.InCombat(name, entities)); entities.GetStatus = getStatus

enable('enemyNames', 'unclaimed', 1, 1, 0)
enable('enemyNames', 'claimedParty', 1, 0, 0)
enable('enemyNames', 'claimedOther', 0, 0, 1)
enable('enemyNames', 'targeted', 0, 1, 0)
enable('enemyNames', 'dead', 0.5, 0.5, 0.5)
local ids = colours.Context(o, memory)
assert(ids[777] and ids[888], 'self and active alliance claims count as ours')
assert(colours.Resolve(o, name, entities, ids, false) == 0xFFFFFF00)
claim = 777; assert(colours.Resolve(o, name, entities, ids, false) == 0xFFFF0000)
claim = 888; assert(colours.Resolve(o, name, entities, ids, false) == 0xFFFF0000)
claim = 999; assert(colours.Resolve(o, name, entities, ids, false) == 0xFF0000FF)
assert(colours.Resolve(o, name, entities, nil, false) == nil, 'unknown party must not mean outside claim')
name.Flags = plates.Flag.Target; assert(colours.Resolve(o, name, entities, ids, false) == 0xFF00FF00)
assert(colours.Resolve(o, name, entities, ids, true) == 0xFF808080, 'dead beats targeted and claim')
o.nameColours.enemyNames.dead.enabled[1] = false
assert(colours.Resolve(o, name, entities, ids, true) == nil, 'default corpse grey must not inherit a live override')
o.nameColours.enemyNames.targeted.enabled[1] = false
assert(colours.Resolve(o, name, entities, ids, false) == 0xFF0000FF, 'disabled target state falls back to claim')
claim = nil; assert(colours.Resolve(o, name, entities, ids, false) == nil)
claim = 0; id = 456; assert(colours.Resolve(o, name, entities, ids, false) == nil); id = 123

name.Category, name.Flags = plates.Category.Player, 0
enable('playerNames', 'normal', 1, 0, 0); enable('playerNames', 'combat', 0, 1, 0)
enable('playerNames', 'targeted', 0, 0, 1); enable('playerNames', 'dead', 0.5, 0.5, 0.5)
status = 0; assert(colours.Resolve(o, name, entities, ids, false) == 0xFFFF0000)
status = 1; assert(colours.Resolve(o, name, entities, ids, false) == 0xFF00FF00)
name.Flags = plates.Flag.Target; assert(colours.Resolve(o, name, entities, ids, false) == 0xFF0000FF)
hp = 0; assert(colours.Resolve(o, name, entities, ids, false) == 0xFF808080)
o.nameColours.playerNames.dead.enabled[1] = false
assert(colours.Resolve(o, name, entities, ids, false) == nil)
hp = 50
for _, category in ipairs({ plates.Category.Self, plates.Category.Party, plates.Category.Alliance, plates.Category.MyPet, plates.Category.Pet }) do
    name.Category = category; assert(colours.Resolve(o, name, entities, ids, false) == 0xFF0000FF)
end
name.Category = plates.Category.Npc
enable('npcNames', 'normal', 1, 0, 0); enable('npcNames', 'targeted', 0, 1, 0)
assert(colours.Resolve(o, name, entities, nil, false) == 0xFF00FF00)
name.Flags = 0; assert(colours.Resolve(o, name, entities, nil, false) == 0xFFFF0000)
o.nameColours.npcNames.normal.color = { 0/0, -1, 5, 0 }
custom.Settle(o)
local c = o.nameColours.npcNames.normal.color
assert(c[1] == 128/255 and c[2] == 0 and c[3] == 1 and c[4] == 1, 'sanitize RGB and never override live alpha')
H.print('state colours: default compatibility, combat, claims/self/alliance, priority, missing data, pets and RGB validation', true)
