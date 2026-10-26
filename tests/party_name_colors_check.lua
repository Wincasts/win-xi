-- Game Name Colors: a target's name in the game's colour for what it is: an enemy unclaimed, claimed by
-- the party or alliance or by others, called for help on, dead; a player alone, in the party, in the
-- alliance; an NPC; off, the theme's colour.
H.load()
local namecolors = require('namecolors')
local colors = namecolors.Colors
local bit = require('bit')

local claims, servers = {}, {}
local entityMemory = setmetatable({
    GetServerId = function(_, index) return servers[index] or 0 end,
    GetClaimStatus = function(_, index) return claims[index] or 0 end,
}, { __index = function() return function() return 0 end end })
local members = { [0] = 1000, [1] = 1001, [6] = 1006 } -- the player, a party member, an alliance member
local partyReads = 0
local party = setmetatable({
    GetMemberIsActive = function(_, slot) partyReads = partyReads + 1; return members[slot] and 1 or 0 end,
    GetMemberServerId = function(_, slot) return members[slot] or 0 end,
}, { __index = function() return function() return 0 end end })
local targets = { GetTargetIndex = function(_, slot) return slot == 0 and 50 or 0 end,
    GetIsActive = function() return 1 end, GetIsSubTargetActive = function() return 0 end, GetSubTargetFlags = function() return 0xFFFFFFFF end }
local core = AshitaCore
local memory = setmetatable({ GetEntity = function() return entityMemory end, GetParty = function() return party end,
    GetTarget = function() return targets end }, { __index = core.GetMemoryManager() })
AshitaCore = setmetatable({ GetMemoryManager = function() return memory end }, { __index = core })

local function Entity(index, serverId, flags, hpp, status)
    servers[index] = serverId
    return { ServerId = serverId, SpawnFlags = flags, HPPercent = hpp or 100, Status = status or 0, Name = 'E' .. index, Distance = 25 }
end
local PLAYER, NPC, MONSTER = 0x01, 0x02, 0x10

namecolors.BeginFrame()
local mob = Entity(50, 5000, MONSTER)
assert(namecolors.For(mob, 50) == colors.unclaimed, 'unclaimed: yellow')
claims[50] = 1001
assert(namecolors.For(mob, 50) == colors.claimedParty, 'claimed by the party: red')
claims[50] = 1006
assert(namecolors.For(mob, 50) == colors.claimedParty, 'by the alliance: red')
claims[50] = 1000
assert(namecolors.For(mob, 50) == colors.claimedParty, 'by the player: red')
claims[50] = 7777
assert(namecolors.For(mob, 50) == colors.claimedOther, 'by others: purple')
-- a call for help: the entity update with 0x20 in its flags, sent with its HP
local data = { }
for i = 1, 0x30 do data[i] = 0 end
local function Packet(id, mask, flag)
    data[0x04 + 1], data[0x05 + 1] = id % 256, math.floor(id / 256) % 256
    data[0x0A + 1], data[0x21 + 1] = mask, flag
    return { id = 0x00E, data = string.char(unpack(data)) }
end
namecolors.HandlePacket(Packet(5000, 0x04, 0x20))
assert(namecolors.For(mob, 50) == colors.callForHelp, 'called for help: orange')
namecolors.HandlePacket(Packet(5000, 0x04, 0x00))
assert(namecolors.For(mob, 50) == colors.claimedOther, 'call for help over')
namecolors.HandlePacket(Packet(5000, 0x04, 0x20))
namecolors.HandlePacket({ id = 0x00A, data = '' })
assert(namecolors.For(mob, 50) == colors.claimedOther, 'forgotten with the area')
mob.HPPercent = 0
assert(namecolors.For(mob, 50) == colors.dead, 'dead: grey')

assert(namecolors.For(Entity(60, 1001, PLAYER), 60) == colors.party, 'a party member: blue')
assert(namecolors.For(Entity(61, 1006, PLAYER), 61) == colors.alliance, 'an alliance member: light blue')
assert(namecolors.For(Entity(62, 1000, PLAYER), 62) == colors.player, 'the player: white')
assert(namecolors.For(Entity(63, 4242, PLAYER), 63) == colors.player, 'another player: white')
assert(namecolors.For(Entity(64, 4243, PLAYER, 0), 64) == colors.dead, 'a dead player: grey')
assert(namecolors.For(Entity(70, 9000, NPC), 70) == colors.npc, 'an NPC: green')
assert(namecolors.For(Entity(71, 9001, NPC, 100, 3), 71) == colors.dead, 'a dead NPC: grey')
local reads = partyReads
namecolors.For(Entity(60, 1001, PLAYER), 60)
assert(partyReads == reads, 'the party read once a frame')
servers[60] = 1234
assert(namecolors.For({ ServerId = 1001, SpawnFlags = PLAYER, HPPercent = 100 }, 60) == nil, 'an index someone else\'s now: nothing')
assert(namecolors.For({ ServerId = 0, SpawnFlags = PLAYER }, 60) == nil and namecolors.For({}, 60) == nil, 'nothing known: nothing')

-- drawn: the target's name in its colour with Game Name Colors on, the theme's with it off
local entities = { [50] = Entity(50, 5000, MONSTER) }
claims[50] = 7777
GetEntity = function(index) return entities[index] end
local options = H.options()
require('winxi.game').IsHidden = function() return false end
require('target').Indexes = function() return 50, 0, 0 end
options.party.enabled[1], options.target.enabled[1], options.target.showMain[1] = false, true, true
local draw = require('draw')
local lastColor, nameColor = nil, nil
local packed, text = draw.Packed, draw.Text
draw.Packed = function(color, alpha) lastColor = color; return packed(color, alpha) end
draw.Text = function(x, y, color, words, ...) if words == 'E50' then nameColor = lastColor end return text(x, y, color, words, ...) end
options.target.gameNameColors[1] = true
H.frames(2) -- the first as the window appears
assert(nameColor == colors.claimedOther, 'drawn in the game\'s colour')
options.target.gameNameColors[1] = false
nameColor = nil
H.frames(1)
assert(nameColor ~= nil and nameColor ~= colors.claimedOther, 'off: the theme\'s colour')
draw.Packed, draw.Text = packed, text
AshitaCore = core
H.print('Game Name Colors: enemies by claim, call for help and death, players by party and alliance, NPCs; drawn only when on', true)
