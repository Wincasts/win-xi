-- What trigger reads out of the packets the game is sent: chat, invitations, trades, being examined,
-- messages, treasure, and what the mobs do.
local bit = require('bit')
local packets = require('winxi.packets')
local shared = require('shared')
local playing = require('playing')
local mobdata = require('mobdata')
local triggers = require('triggers')
local indicator = require('indicator')

local Sound, Ask = playing.Sound, playing.Ask
local Area, CurrentZone = mobdata.Area, mobdata.CurrentZone
local Indicate = indicator.Indicate

-- Some bits of a packet, as a number, read where the packet lies without a copy being made of it:
-- the offset is counted in bits from the packet's start, the low bit of each byte first, which is how
-- the action packet is packed
local Bits = ashita.bits.unpack_be

local packetSystemMessage = 0x009
local packetChat = 0x017
local packetTrade = 0x021 -- someone asks to trade
local packetAction = packets.inbound.action.id
local packetMessage = packets.inbound.message.id
local packetTreasure = 0x0D2 -- an item is in the treasure pool
local packetInvite = 0x0DC

local chatTell = 3
-- party and linkshell chat, with and without the speaker shown
local chatAmongFriends = { [4] = true, [5] = true, [15] = true, [16] = true, [27] = true, [28] = true }

-- The player's name in small letters, and the pattern that finds it as a word of its own, not as
-- part of another: made again only when the name is another one
local knownName, ownName, namePattern = nil, nil, nil

local function OwnName()
    local name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)
    if type(name) ~= 'string' or name == '' then
        return nil
    end
    if name ~= knownName then
        knownName, ownName = name, name:lower()
        namePattern = '%f[%a]' .. ownName:gsub('%p', '%%%0') .. '%f[%A]'
    end
    return ownName
end

-- A string of bytes that ends at its first zero
local function Text(data, first, last)
    local text = data:sub(first, last)
    local zero = text:find('\0', 1, true)
    return zero and text:sub(1, zero - 1) or text
end

-- What reads a packet is given the packet as the game hands it over. Numbers are read out of it
-- where it lies (Bits, with the place counted in bits: eight to a byte). A copy of it (data) is asked
-- for only by what has words to read, the chat, and only once the words are wanted.

-- The chat packet: the kind of message at 0x04, who said it at 0x08 (15 bytes), what they said from 0x17
local function OnChat(e)
    local kind = Bits(e.data_raw, 0x04 * 8, 8)
    if kind == chatTell then
        Sound('tell')
    elseif chatAmongFriends[kind] and shared.app.options.events.mention.enabled[1] then
        local own = OwnName()
        if own == nil then
            return
        end
        local data = e.data
        if Text(data, 0x08 + 1, 0x08 + 15):lower() == own then
            return
        end
        if Text(data, 0x17 + 1, #data):lower():find(namePattern) then
            Sound('mention')
        end
    end
end

-- The message packet: who it is about at 0x08, their place among the area's entities at 0x16, and
-- which message at 0x18, in its low 15 bits. A skill rising and a skill reaching a level are two of
-- them, and the player's own and their pet's are the ones wanted: an automaton's skills rise under
-- its own name, not its master's.
local messageSkillRises, messageSkillLevel = 38, 53

local function OnMessage(e)
    if not shared.app.options.events.skillup.enabled[1] then
        return
    end
    local raw = e.data_raw
    local message = Bits(raw, 0x18 * 8, 15)
    if message ~= messageSkillRises and message ~= messageSkillLevel then
        return
    end
    local memory = AshitaCore:GetMemoryManager()
    local party = memory:GetParty()
    if Bits(raw, 0x08 * 8, 32) == party:GetMemberServerId(0) then
        Sound('skillup')
        return
    end
    local ownIndex = party:GetMemberTargetIndex(0)
    local petIndex = ownIndex ~= 0 and memory:GetEntity():GetPetTargetIndex(ownIndex) or 0
    if petIndex ~= 0 and Bits(raw, 0x16 * 8, 16) == petIndex then
        Sound('skillup')
    end
end

-- The system message packet: which message at 0x0A. One of them says that someone examines you, and
-- it is sent only to the one examined.
local systemMessageExamines = 89

local function OnSystemMessage(e)
    if shared.app.options.events.examine.enabled[1] and Bits(e.data_raw, 0x0A * 8, 16) == systemMessageExamines then
        Sound('examine')
    end
end

-- The items listened for, by name in small letters: read from what is written in the settings, names
-- with commas between them, and read again only when that is something else
local wantedText, wanted = nil, { }

local function Wanted(text)
    if text ~= wantedText then
        wantedText, wanted = text, { }
        for name in text:gmatch('[^,]+') do
            name = name:match('^%s*(.-)%s*$'):lower()
            if name ~= '' then
                wanted[name] = true
            end
        end
    end
    return wanted
end

-- The treasure packet: which item at 0x10, and at 0x15 whether it was in the pool already, as every
-- item in it is told of again on arriving in an area. A place in the pool with nothing in it is item 0.
local function OnTreasure(e)
    if not shared.app.options.events.drop.enabled[1] then
        return
    end
    local raw = e.data_raw
    if Bits(raw, 0x15 * 8, 8) ~= 0 then
        return
    end
    local id = Bits(raw, 0x10 * 8, 16)
    local item = id ~= 0 and AshitaCore:GetResourceManager():GetItemById(id) or nil
    local name = item ~= nil and item.Name ~= nil and item.Name[1] or nil
    if type(name) == 'string' and Wanted(shared.app.options.dropItems[1])[name:lower()] then
        Sound('drop')
    end
end

---------------------------------------------------------------------------------------------------
-- Triggers: a mob begins a spell or a weaponskill, or uses an ability
---------------------------------------------------------------------------------------------------

-- The name of whoever has a server id: a mob's place among the area's entities is in the low bits
-- of its id
local function EntityName(serverId)
    local entity = GetEntity(bit.band(serverId, 0xFFF))
    if entity ~= nil and entity.ServerId == serverId and type(entity.Name) == 'string' then
        return entity.Name
    end
    return nil
end

-- The action packet: who acted at bit 40, how many targets at 72, the kind of action at 82, what the
-- action is at 86, and from 150 each target (its id, how many results, then each result).
--
-- Beginning a weaponskill and beginning a spell are two kinds, and which weaponskill or spell is the
-- first result's number, 27 bits into it. One broken off is sent as the same kind: a weaponskill then
-- has no number, and a spell no message (the ten bits after the number).
--
-- An ability is used at once, with no beginning sent, so it is heard as it is used: the kinds that
-- say a mob's move is done (of a move numbered under 256, and of the others), which name the move as
-- what the action is.
--
-- Action packets come thick in a fight and most are rounds of attacks, so nothing is read with no
-- triggers made, and then the kind first, and the rest only for the kinds wanted.
local categories = packets.inbound.action.categories
local beginsKinds = { [categories.WeaponskillStart] = 'skill', [categories.SpellStart] = 'spell' }
local doneKinds = { [categories.WeaponskillFinish] = true, [categories.MobSkillFinish] = true }

-- Where each of those is in the packet, counted in bits
local actionActor = 40                               -- 32 bits
local actionTargets = 72                             -- 6 bits
local actionCategory = 82                            -- 4 bits
local actionParam = 86                               -- 32 bits
local actionFirstTarget = 150                        -- its id (32 bits), how many results (4), then each result
local actionResults = actionFirstTarget + 32         -- how many results the first target has
local actionResultParam = actionFirstTarget + 36 + 27 -- the first result's number: 17 bits
local actionResultMessage = actionResultParam + 17   -- and its message: 10 bits

local function OnAction(e)
    if #shared.app.options.triggers == 0 then
        return
    end
    local data = e.data_raw
    local category = Bits(data, actionCategory, 4)
    local kind, id = beginsKinds[category], 0
    if kind ~= nil then
        if Bits(data, actionTargets, 6) == 0 or Bits(data, actionResults, 4) == 0 then
            return
        end
        id = Bits(data, actionResultParam, 17)
        if kind == 'spell' and Bits(data, actionResultMessage, 10) == 0 then
            return
        end
    elseif doneKinds[category] then
        kind, id = 'ability', Bits(data, actionParam, 32)
    end
    if id == 0 then
        return
    end

    local found = triggers.For(kind, id)
    if found == nil then
        return
    end

    -- which kind of mob it is that acts: asked only now that a trigger is for this spell or move
    local actor = EntityName(Bits(data, actionActor, 32))
    local actorKind = actor ~= nil and Area(CurrentZone()).kindOf[actor:lower()]
    if not actorKind then
        return
    end
    for _, trigger in ipairs(found) do
        if trigger.mob == actorKind and trigger.enabled[1] then
            Ask(trigger.sound, trigger)
            Indicate(trigger, actor)
        end
    end
end

-- What reads each packet trigger has a use for. Every packet the game is sent comes by here, and
-- nearly all of them are none of these: what a packet is, is asked once, and looked up.
local packetReaders = {
    [packetChat] = OnChat,
    [packetInvite] = function() Sound('invite') end,
    [packetTrade] = function() Sound('trade') end,
    [packetSystemMessage] = OnSystemMessage,
    [packetMessage] = OnMessage,
    [packetTreasure] = OnTreasure,
    [packetAction] = OnAction,
}

-- A packet has come in: given to what reads it, once there are settings to read it by
local function Read(e)
    local read = packetReaders[e.id]
    if read ~= nil and shared.app ~= nil then
        read(e)
    end
end

return { Read = Read }
