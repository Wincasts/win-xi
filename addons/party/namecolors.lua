-- namecolors: a target's name in the colour the game gives it over the entity's head, for Game Name
-- Colors: an enemy yellow while unclaimed, red claimed by your party or alliance, purple by anyone else
-- and orange once help has been called for; a player white, or blue in your party or alliance; an NPC
-- green; and anything dead grey. The colours are the game's, as winxi's name addon starts its own from.
--
--     namecolors.HandlePacket(e)       every incoming packet: which enemies help was called for on
--     namecolors.BeginFrame()          once a frame, before any For: the party is read again when next wanted
--     namecolors.For(entity, index)    the colour for an entity at an index, or nil for the usual
require('common')
local bit = require('bit')

local namecolors = { }

local function rgb(value)
    return { math.floor(value / 65536) % 256 / 255, math.floor(value / 256) % 256 / 255, value % 256 / 255, 1 }
end

namecolors.Colors = {
    unclaimed = rgb(0xFFFF40), claimedParty = rgb(0xFF4040), claimedOther = rgb(0xC080FF),
    callForHelp = rgb(0xFFA040), dead = rgb(0x808080),
    player = rgb(0xFFFFFF), party = rgb(0x80D0FF), alliance = rgb(0xB0E0FF), npc = rgb(0x80FF80),
}
local colors = namecolors.Colors

-- Monsters a call for help was made on, by server id: told by the entity update (0x0E), whose flags
-- at 0x21 have 0x20 while it stands, sent with its HP (mask 0x04); gone with the monster or the area
local calledFor = { }
local CALL_FOR_HELP = 0x20

local function U32(data, at)
    local a, b, c, d = data:byte(at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

function namecolors.HandlePacket(e)
    if e.id == 0x00A then
        calledFor = { }
        return
    end
    if e.id ~= 0x00E or e.data == nil or #e.data < 0x25 then return end
    local id, mask = U32(e.data, 0x04), e.data:byte(0x0A + 1)
    if bit.band(mask, 0x20) ~= 0 then
        calledFor[id] = nil
    elseif bit.band(mask, 0x04) ~= 0 then
        calledFor[id] = bit.band(e.data:byte(0x21 + 1), CALL_FOR_HELP) ~= 0 or nil
    end
end

-- The party's and the alliance's server ids, read once a frame when first wanted: the party's (slots
-- 0 to 5) for whose a player is, either for whose claim an enemy is under. ownId is the player's own,
-- whose name is not a party member's.
local partyIds, allianceIds, ownId, read = { }, { }, nil, false

function namecolors.BeginFrame()
    read = false
end

local function ReadParty()
    read = true
    for id in pairs(partyIds) do partyIds[id] = nil end
    for id in pairs(allianceIds) do allianceIds[id] = nil end
    ownId = nil
    local party = AshitaCore:GetMemoryManager():GetParty()
    if party == nil then return end
    for slot = 0, 17 do
        if party:GetMemberIsActive(slot) == 1 then
            local id = party:GetMemberServerId(slot)
            if type(id) == 'number' and id > 0 then
                if slot == 0 then ownId = id end
                if slot < 6 then partyIds[id] = true else allianceIds[id] = true end
            end
        end
    end
end

local PLAYER, MONSTER = 0x01, 0x10

function namecolors.For(entity, index)
    local flags, serverId = entity.SpawnFlags, entity.ServerId
    if type(flags) ~= 'number' or type(serverId) ~= 'number' or serverId == 0 or index == nil or index == 0 then
        return nil
    end
    local entities = AshitaCore:GetMemoryManager():GetEntity()
    -- the index another entity's now, after a change of area: nothing known of it
    if entities:GetServerId(index) ~= serverId then return nil end

    if bit.band(flags, PLAYER) ~= 0 then
        if entity.HPPercent == 0 then return colors.dead end
        if not read then ReadParty() end
        if serverId ~= ownId and partyIds[serverId] then return colors.party end
        if allianceIds[serverId] then return colors.alliance end
        return colors.player
    end

    if bit.band(flags, MONSTER) ~= 0 then
        if entity.HPPercent == 0 then return colors.dead end
        if calledFor[serverId] then return colors.callForHelp end
        local claim = entities:GetClaimStatus(index)
        if type(claim) ~= 'number' or claim == 0 then return colors.unclaimed end
        if not read then ReadParty() end
        return (partyIds[claim] or allianceIds[claim]) and colors.claimedParty or colors.claimedOther
    end

    -- an NPC's HP is always 100: its status says whether it is dead
    local status = entity.Status
    if status == 2 or status == 3 then return colors.dead end
    return colors.npc
end

return namecolors
