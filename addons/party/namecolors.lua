-- namecolors: a target's name in the colour the game gives it over the entity's head, for Game Name
-- Colors.
--
-- With the namehook plugin loaded and the name in its list (the game was about to draw it last frame),
-- the colour is the game's own, read from there: whatever the game shows, exactly. The game pulses the
-- target's name toward white and back; the colour the pulse starts from is kept, as name keeps it.
--
-- Otherwise it is worked out from the entity: an enemy yellow while unclaimed, red claimed by your
-- party or alliance, purple by anyone else and orange once help has been called for; a player white,
-- or blue in your party or alliance; an NPC green; anything dead grey. White, blue and green are the
-- game's, read from it (namehook, 2026-10-25); the others are name's colour overrides' starting
-- colours, near the game's.
--
--     namecolors.HandlePacket(e)       every incoming packet: which enemies help was called for on
--     namecolors.BeginFrame()          once a frame, before any For
--     namecolors.For(entity, index)    the colour for an entity at an index, or nil for the usual
require('common')
local bit = require('bit')
local nameplates = nil -- winxi.nameplates, loaded the first time a colour is wanted

local namecolors = { }

-- One part of a game colour, where 0x80 is full and more than that is no brighter
local function Part(value)
    return value >= 0x80 and 1 or value * 2 / 255
end

-- A game colour (0xRRGGBB, 0x80 for full) as imgui's
local function Game(value)
    return { Part(bit.band(bit.rshift(value, 16), 0xFF)), Part(bit.band(bit.rshift(value, 8), 0xFF)), Part(bit.band(value, 0xFF)), 1 }
end

local function Rgb(value)
    return { math.floor(value / 65536) % 256 / 255, math.floor(value / 256) % 256 / 255, value % 256 / 255, 1 }
end

namecolors.Colors = {
    unclaimed = Rgb(0xFFFF40), claimedParty = Rgb(0xFF4040), claimedOther = Rgb(0xC080FF),
    callForHelp = Rgb(0xFFA040), dead = Rgb(0x808080),
    player = Game(0x808080), party = Game(0x416180), alliance = Rgb(0xB0E0FF), npc = Game(0x618061),
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

-- What is kept of each target's name as the game showed it, by entity index: its server id, the
-- colour it had while not the target, and the one its pulse starts from while it is
local seen = { }

function namecolors.HandlePacket(e)
    if e.id == 0x00A then
        calledFor = { }
        seen = { }
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
-- whose name is not a party member's. hook is namehook's block for the frame, false until asked.
local partyIds, allianceIds, ownId, read = { }, { }, nil, false
local hook = false

function namecolors.BeginFrame()
    read, hook = false, false
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

-- whether colour a is colour b gone toward white or toward dark, as the game's pulse takes a name:
-- each channel the same share of the way, give or take PULSE_SLACK (as name tells it)
local PULSE_SLACK = 3
local function PulseOf(a, b)
    local ar, ag, ab = math.min(0x80, bit.rshift(a, 16)), math.min(0x80, bit.band(bit.rshift(a, 8), 0xFF)), math.min(0x80, bit.band(a, 0xFF))
    local br, bg, bb = math.min(0x80, bit.rshift(b, 16)), math.min(0x80, bit.band(bit.rshift(b, 8), 0xFF)), math.min(0x80, bit.band(b, 0xFF))
    for _, toward in ipairs({ 0, 0x80 }) do
        local far, near = br, ar
        if math.abs(toward - bg) > math.abs(toward - far) then far, near = bg, ag end
        if math.abs(toward - bb) > math.abs(toward - far) then far, near = bb, ab end
        local share = far == toward and 0 or (near - far) / (toward - far)
        if share >= -0.05 and share <= 1.05
            and math.abs(ar - (br + (toward - br) * share)) <= PULSE_SLACK
            and math.abs(ag - (bg + (toward - bg) * share)) <= PULSE_SLACK
            and math.abs(ab - (bb + (toward - bb) * share)) <= PULSE_SLACK then
            return true
        end
    end
    return false
end

-- The game's colours as imgui's, made once each
local made = { }
local madeCount = 0
local function Made(value)
    local color = made[value]
    if color == nil then
        if madeCount >= 256 then made, madeCount = { }, 0 end
        color = Game(value)
        made[value], madeCount = color, madeCount + 1
    end
    return color
end

-- The game's own colour for the name over an entity, or nil where namehook has none for it
local function FromGame(index, serverId)
    nameplates = nameplates or require('winxi.nameplates')
    if hook == false then hook = nameplates.Hook() or nil end
    if hook == nil then return nil end
    local name = nameplates.Find(index, hook)
    if name == nil or name.ServerId ~= serverId or bit.rshift(name.NameColor, 24) == 0 then return nil end

    local rgb = name.NameColor % 0x1000000
    local known = seen[index]
    if known == nil or known.serverId ~= serverId then
        known = { serverId = serverId }
        seen[index] = known
    end
    if bit.band(name.Flags, nameplates.Flag.Target) ~= 0 then
        -- A colour that is the kept one gone toward white or dark is the pulse; one the kept colour is
        -- a pulse of is truer, and taken; any other (a claim's) is taken at once.
        local base = known.base or known.plain or rgb
        if not PulseOf(rgb, base) and (PulseOf(base, rgb) or known.base ~= nil) then base = rgb end
        known.base = base
        return Made(base)
    end
    known.base, known.plain = nil, rgb
    return Made(rgb)
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

    local isPlayer, isMonster = bit.band(flags, PLAYER) ~= 0, bit.band(flags, MONSTER) ~= 0
    -- a corpse is grey, never the claim's colour it last had
    if (isPlayer or isMonster) and entity.HPPercent == 0 then return colors.dead end
    local status = entity.Status
    if not isPlayer and not isMonster and (status == 2 or status == 3) then return colors.dead end

    local own = FromGame(index, serverId)
    if own ~= nil then return own end

    if isPlayer then
        if not read then ReadParty() end
        if serverId ~= ownId and partyIds[serverId] then return colors.party end
        if allianceIds[serverId] then return colors.alliance end
        return colors.player
    end

    if isMonster then
        if calledFor[serverId] then return colors.callForHelp end
        local claim = entities:GetClaimStatus(index)
        if type(claim) ~= 'number' or claim == 0 then return colors.unclaimed end
        if not read then ReadParty() end
        return (partyIds[claim] or allianceIds[claim]) and colors.claimedParty or colors.claimedOther
    end

    -- an NPC's HP is always 100: its status says whether it is dead (above)
    return colors.npc
end

return namecolors
