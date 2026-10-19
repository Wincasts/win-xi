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
enable('enemyNames', 'callForHelp', 1, 0.5, 0)
enable('enemyNames', 'dead', 0.5, 0.5, 0.5)
local ids = colours.Context(o, memory)
assert(ids[777] and ids[888], 'self and active alliance claims count as ours')
assert(colours.Resolve(o, name, entities, ids, false) == 0xFFFFFF00)
claim = 777; assert(colours.Resolve(o, name, entities, ids, false) == 0xFFFF0000)
claim = 888; assert(colours.Resolve(o, name, entities, ids, false) == 0xFFFF0000)
claim = 999; assert(colours.Resolve(o, name, entities, ids, false) == 0xFF0000FF)
assert(colours.Resolve(o, name, entities, nil, false) == nil, 'unknown party must not mean outside claim')
name.Flags = plates.Flag.Target; assert(colours.Resolve(o, name, entities, ids, false) == 0xFF0000FF, 'a target keeps its claim colour')
name.Flags = 0
assert(colours.Resolve(o, name, entities, ids, true) == 0xFF808080, 'dead beats claim')
o.nameColours.enemyNames.dead.enabled[1] = false
assert(colours.Resolve(o, name, entities, ids, true) == nil, 'default corpse grey must not inherit a live override')
o.nameColours.enemyNames.dead.enabled[1] = true
claim = nil; assert(colours.Resolve(o, name, entities, ids, false) == nil)
claim = 0; id = 456; assert(colours.Resolve(o, name, entities, ids, false) == nil); id = 123

-- call for help: the entity update's flags at 0x21 with 0x20, sent with its HP (mask 0x04)
local function update(serverId, mask, flags)
    local bytes = {}
    for i = 1, 0x30 do bytes[i] = 0 end
    for k = 0, 3 do bytes[0x04 + 1 + k] = math.floor(serverId / 256 ^ k) % 256 end
    bytes[0x0A + 1], bytes[0x21 + 1] = mask, flags
    colours.HandlePacket({ id = 0x0E, data = string.char(unpack(bytes)) })
end
update(123, 0x07, 0x20)
assert(colours.Resolve(o, name, entities, ids, false) == 0xFFFF8000, 'called for help, though unclaimed')
assert(colours.Resolve(o, name, entities, ids, true) == 0xFF808080, 'dead beats call for help')
update(123, 0x01, 0x00); assert(colours.CalledFor(123), 'a position alone says nothing of the flags')
o.nameColours.enemyNames.callForHelp.enabled[1] = false
assert(colours.Resolve(o, name, entities, ids, false) == nil, 'off: the game\'s own colour, not unclaimed')
o.nameColours.enemyNames.callForHelp.enabled[1] = true
update(123, 0x04, 0x00); assert(not colours.CalledFor(123), 'cleared with the next HP update')
update(123, 0x04, 0x20); update(123, 0x20, 0x00); assert(not colours.CalledFor(123), 'despawned')
update(123, 0x04, 0x20); colours.HandlePacket({ id = 0x0A, data = '' }); assert(not colours.CalledFor(123), 'another area')
assert(colours.Resolve(o, name, entities, ids, false) == 0xFFFFFF00)

name.Category, name.Flags = plates.Category.Player, 0
enable('playerNames', 'normal', 1, 0, 0); enable('playerNames', 'party', 0, 1, 0)
enable('playerNames', 'alliance', 0, 0, 1); enable('playerNames', 'dead', 0.5, 0.5, 0.5)
status = 1; assert(colours.Resolve(o, name, entities, ids, false) == 0xFFFF0000, 'in combat is still Normal')
name.Flags = plates.Flag.Target; assert(colours.Resolve(o, name, entities, ids, false) == 0xFFFF0000, 'targeted is still Normal')
name.Flags = 0
name.Category = plates.Category.Party; assert(colours.Resolve(o, name, entities, ids, false) == 0xFF00FF00)
name.Category = plates.Category.Alliance; assert(colours.Resolve(o, name, entities, ids, false) == 0xFF0000FF)
o.nameColours.playerNames.alliance.enabled[1] = false
assert(colours.Resolve(o, name, entities, ids, false) == nil, 'off: the game\'s alliance colour, not Normal')
hp = 0; assert(colours.Resolve(o, name, entities, ids, false) == 0xFF808080)
o.nameColours.playerNames.dead.enabled[1] = false
assert(colours.Resolve(o, name, entities, ids, false) == nil, 'a dead player never takes a live colour')
name.Category = plates.Category.Player; assert(colours.Resolve(o, name, entities, ids, false) == nil)
assert(colours.Resolve(o, name, entities, ids, false, { 0x91 }) == nil, 'a dead seeker is dead')
hp = 50
-- looking for party, by its icon (0x91, or 0xAC with the star); the game has no colour for it
enable('playerNames', 'seeking', 1, 1, 0)
assert(colours.Resolve(o, name, entities, ids, false, { 0x91 }) == 0xFFFFFF00)
assert(colours.Resolve(o, name, entities, ids, false, { 0x9E, 0xAC }) == 0xFFFFFF00, 'the starred icon too')
assert(colours.Resolve(o, name, entities, ids, false, { 0x9E }) == 0xFFFF0000, 'other icons: Normal')
assert(colours.Resolve(o, name, entities, ids, false) == 0xFFFF0000, 'no icons: Normal')
o.nameColours.playerNames.seeking.enabled[1] = false
assert(colours.Resolve(o, name, entities, ids, false, { 0x91 }) == 0xFFFF0000, 'off: coloured as Normal, the game having no colour of its own for it')
for _, category in ipairs({ plates.Category.Self, plates.Category.MyPet, plates.Category.Pet }) do
    name.Category = category; assert(colours.Resolve(o, name, entities, ids, false) == 0xFFFF0000)
end
name.Category = plates.Category.Npc
enable('npcNames', 'normal', 1, 0, 0); enable('npcNames', 'dead', 0, 1, 0)
status = 0; hp = 0; assert(colours.Resolve(o, name, entities, nil, false) == 0xFFFF0000, 'an NPC is dead by its status, not its HP')
status = 3; assert(colours.Resolve(o, name, entities, nil, false) == 0xFF00FF00)
status = 0; hp = 50
o.nameColours.playerNames.combat = T{ enabled = T{ true }, color = { 1, 1, 1, 1 } }
o.nameColours.npcNames.targeted = T{ enabled = T{ true }, color = { 1, 1, 1, 1 } }
o.nameColours.npcNames.normal.color = { 0/0, -1, 5, 0 }
custom.Settle(o)
local c = o.nameColours.npcNames.normal.color
assert(c[1] == 128/255 and c[2] == 0 and c[3] == 1 and c[4] == 1, 'sanitize RGB and never override live alpha')
assert(o.nameColours.playerNames.combat == nil and o.nameColours.npcNames.targeted == nil, 'In Combat and Targeted dropped')
H.print('state colours: the game\'s states, claims, call for help from 0x0E, party and alliance, looking for party by its icon, dead first, NPCs dead by status, old states dropped, RGB validation', true)
