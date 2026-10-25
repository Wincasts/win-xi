-- What mobcast reads out of the action packets the game is sent: an enemy beginning a spell or a
-- weaponskill, breaking one off, finishing one, or using an ability, each told to the box.
local bit = require('bit')
local packets = require('winxi.packets')
local shared = require('shared')
local box = require('box')

-- Some bits of a packet, as a number, read where the packet lies without a copy being made of it:
-- the offset is counted in bits from the packet's start, the low bit of each byte first, which is how
-- the action packet is packed
local Bits = ashita.bits.unpack_be

local packetAction = packets.inbound.action.id
local categories = packets.inbound.action.categories

-- The action packet: who acted at bit 40, how many targets at 72, the kind of action at 82, what the
-- action is at 86, and from 150 each target (its id, how many results, then each result).
--
-- Beginning a spell and beginning a weaponskill are two kinds. Which spell or weaponskill is the
-- first result's number, 27 bits into it, and the ten bits after it are the message the chat log
-- says it with: 0 for one the game keeps quiet about, which is left alone here too. One broken off
-- is sent as the same kind, with what the action is (the four letters at 86, as the Phoenix server
-- writes them) beginning 'sp' rather than 'ca': a spell's keeps the spell's number, a weaponskill's
-- has no result.
--
-- A spell finished names the spell as what the action is; a mob's weaponskill done, and an ability,
-- which is used at once with no beginning sent, name the move the same way.
--
-- One that comes to nothing is sent as a spell finished, its first result with the animation of an
-- interruption (508) and a message saying why. A spell is stopped at its end by paralysis (84, the
-- chat log's "is paralyzed") or intimidation (106), and names the spell; then its casting is sent
-- broken off, as if it were, which is not said again here. An attack, an ability or an item stopped
-- the same way names nothing (an attack came out as "casts Spell 0"), and is left alone: the box is
-- for what is coming, not a swing that missed it.
local kindsStarting = { [categories.SpellStart] = 'spell', [categories.WeaponskillStart] = 'skill' }
local kindsDone = {
    [categories.SpellFinish] = 'spell',
    [categories.MobSkillFinish] = 'skill',
    [categories.WeaponskillFinish] = 'skill',
    [categories.AbilityFinish] = 'ability',
}

-- Where each of those is in the packet, counted in bits
local actionActor = 40                               -- 32 bits
local actionTargets = 72                             -- 6 bits
local actionCategory = 82                            -- 4 bits
local actionWhat = 86                                -- 32 bits
local actionFirstTarget = 150                        -- its id (32 bits), how many results (4), then each result
local actionResults = actionFirstTarget + 32         -- how many results the first target has
local actionResultAnimation = actionFirstTarget + 36 + 5 -- the first result's animation: 12 bits
local actionResultParam = actionFirstTarget + 36 + 27 -- the first result's number: 17 bits
local actionResultMessage = actionResultParam + 17   -- and its message: 10 bits

-- The two letters that begin what a broken-off action is, as the packet lays them: 's' then 'p'
local brokenOff = 0x7073

-- An action that came to nothing, and the messages of a spell stopped at its end, by what stopped it
local animationInterrupted = 508
local stoppedBy = { [84] = 'paralyzed', [106] = 'intimidated' }

-- The enemies whose spell was just stopped (server id -> true): the broken-off casting sent after it
-- is not said, so that the line says what stopped it
local stopped = { }

---------------------------------------------------------------------------------------------------
-- Who and what
---------------------------------------------------------------------------------------------------

-- The lowest bit of an entity's spawn flags is set for a player, 0x10 for a monster, and 0x100 for
-- a pet, whose master's it is: an enemy is a monster that is nobody's pet
local spawnFlagMonster, spawnFlagPet = 0x10, 0x100

-- The entity with a server id, where its place among the area's entities is in the low bits of its
-- id, as a monster's or an NPC's is
local function EntityById(serverId)
    local entity = GetEntity(bit.band(serverId, 0xFFF))
    if entity ~= nil and entity.ServerId == serverId then
        return entity
    end
    return nil
end

-- The name of whoever has a server id: a party member, by the party list; a monster or an NPC, by
-- its id; anyone else, by looking through the area's entities for the id
local function EntityName(serverId)
    local memory = AshitaCore:GetMemoryManager()
    local party = memory:GetParty()
    for place = 0, 17 do
        if party:GetMemberServerId(place) == serverId then
            local name = party:GetMemberName(place)
            if type(name) == 'string' and name ~= '' then
                return name
            end
        end
    end
    local entity = EntityById(serverId)
    if entity ~= nil and type(entity.Name) == 'string' and entity.Name ~= '' then
        return entity.Name
    end
    local entities = memory:GetEntity()
    if entities ~= nil and entities.GetServerId ~= nil then
        for index = 1, 2303 do
            if entities:GetServerId(index) == serverId then
                local name = entities:GetName(index)
                return type(name) == 'string' and name ~= '' and name or nil
            end
        end
    end
    return nil
end

-- A name the game has, or nil where it has none, or the asking fails
local function GameName(ask)
    local ok, name = pcall(ask)
    if not ok or type(name) ~= 'string' then
        return nil
    end
    name = name:gsub('[%z\1-\31].*', '')
    return name ~= '' and name or nil
end

-- What a spell, a weaponskill or an ability is called, each kind's numbers kept once asked. A
-- monster's moves are numbered from 256 up, and named in the game's list of monsters' abilities,
-- where each is 256 below its number; under that are the players' own weaponskills. An ability's
-- number is the server's own, and the game's list of abilities has it 512 further on.
local names = { spell = { }, skill = { }, ability = { } }
local fallbacks = { spell = 'Spell %d', skill = 'Weaponskill %d', ability = 'Ability %d' }

local function ActionName(kind, id)
    local known = names[kind]
    local name = known[id]
    if name ~= nil then
        return name
    end
    local resources = AshitaCore:GetResourceManager()
    if kind == 'spell' then
        name = GameName(function() return resources:GetSpellById(id).Name[1] end)
    elseif kind == 'ability' then
        name = GameName(function() return resources:GetAbilityById(id + 512).Name[1] end)
            or GameName(function() return resources:GetAbilityById(id).Name[1] end)
    elseif id > 256 then
        name = GameName(function() return resources:GetString('monsters.abilities', id - 256, 2) end)
    else
        name = GameName(function() return resources:GetAbilityById(id).Name[1] end)
    end
    name = name or fallbacks[kind]:format(id)
    known[id] = name
    return name
end

---------------------------------------------------------------------------------------------------
-- The lines
---------------------------------------------------------------------------------------------------

-- What the box says for each thing, as the chat log says it: with whom it is done to, where the
-- log says that, and without
local phrases = {
    spell = { start = '%s starts casting %s on %s.', startAlone = '%s starts casting %s.',
              doneAlone = '%s casts %s.', broken = '%s\'s casting is interrupted.',
              paralyzed = '%s is paralyzed and stops casting %s.',
              intimidated = '%s is intimidated and stops casting %s.' },
    skill = { start = '%s readies %s on %s.', startAlone = '%s readies %s.',
              doneAlone = '%s uses %s.', broken = '%s is interrupted.' },
    ability = { done = '%s uses %s on %s.', doneAlone = '%s uses %s.' },
}

local function OnAction(e)
    local options = shared.app.options
    local data = e.data_raw
    local category = Bits(data, actionCategory, 4)
    local kind, phase, id = kindsStarting[category], 'start', 0
    if kind ~= nil then
        if Bits(data, actionTargets, 6) == 0 then
            return
        end
        if bit.band(Bits(data, actionWhat, 32), 0xFFFF) == brokenOff then
            phase = 'broken'
            local actorId = Bits(data, actionActor, 32)
            if kind == 'spell' and stopped[actorId] then
                stopped[actorId] = nil
                return
            end
        elseif Bits(data, actionResults, 4) == 0 or Bits(data, actionResultMessage, 10) == 0 then
            return
        else
            id = Bits(data, actionResultParam, 17)
            stopped[Bits(data, actionActor, 32)] = nil
        end
    else
        kind = kindsDone[category]
        if kind == nil then
            return
        end
        phase, id = 'done', Bits(data, actionWhat, 32)
        if Bits(data, actionResults, 4) > 0 and Bits(data, actionResultAnimation, 12) == animationInterrupted then
            -- come to nothing: a spell stopped is said so, and anything else not at all
            local by = stoppedBy[Bits(data, actionResultMessage, 10)]
            if kind ~= 'spell' or by == nil or id == 0 then
                return
            end
            phase = by
            stopped[Bits(data, actionActor, 32)] = true
        elseif id == 0 and kind == 'spell' then
            return
        end
    end
    local wanted = kind == 'spell' and options.showSpells or kind == 'skill' and options.showSkills or options.showAbilities
    if not wanted[1] then
        return
    end

    -- who acts: an enemy, and with Only My Target, the one targeted
    local actorId = Bits(data, actionActor, 32)
    local actor = EntityById(actorId)
    if actor == nil or type(actor.Name) ~= 'string' or actor.Name == '' then
        return
    end
    local flags = actor.SpawnFlags or 0
    if bit.band(flags, spawnFlagMonster) == 0 or bit.band(flags, spawnFlagPet) ~= 0 then
        return
    end
    if options.onlyTarget[1] then
        local target = AshitaCore:GetMemoryManager():GetTarget()
        if target == nil or target:GetTargetIndex(0) ~= bit.band(actorId, 0xFFF) then
            return
        end
    end

    -- what is said: with whom it is done to, where that is wanted, known, and someone else
    local phrase = phrases[kind]
    local words
    if phase == 'broken' then
        words = phrase.broken:format(actor.Name)
    elseif phase == 'paralyzed' or phase == 'intimidated' then
        words = phrase[phase]:format(actor.Name, ActionName(kind, id))
    else
        local name = ActionName(kind, id)
        local withTarget, alone = phrase[phase], phrase[phase .. 'Alone']
        local targetName = nil
        if withTarget ~= nil and options.showTargets[1] then
            local targetId = Bits(data, actionFirstTarget, 32)
            if targetId ~= actorId and targetId ~= 0 then
                targetName = EntityName(targetId)
            end
        end
        if targetName ~= nil then
            words = withTarget:format(actor.Name, name, targetName)
        else
            words = (alone or withTarget):format(actor.Name, name)
        end
    end
    local colorKey = kind == 'spell' and 'spellColor' or kind == 'skill' and 'skillColor' or 'abilityColor'
    -- an ability stands alone; a spell's or a weaponskill's end takes the place of its beginning
    local key = kind ~= 'ability' and (actorId .. kind) or nil
    box.Say(key, words, options[colorKey], options.seconds[1])
end

-- A packet has come in: read if it is an action, once there are settings to read it by
local function Read(e)
    if e.id == packetAction and shared.app ~= nil then
        OnAction(e)
    end
end

return { Read = Read, EntityName = EntityName, ActionName = ActionName }
