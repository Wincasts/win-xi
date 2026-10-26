-- target: what the player has targeted, as lines for frames.lua to draw. There are three: the target,
-- the sub-target while one is being chosen, and whatever the target itself has targeted.
--
--     target.Indexes(settings)     the entity index of each, or 0: main, sub, target of target
--     target.Line(key, entity)     the one-line list for an entity, kept for the window called key
--     target.Samples               a made-up entity for each window, by key, for arranging them
--
-- A target's line has its name, its HP bar with the percentage, and how far away it is where a party
-- member's TP goes. The percentage is coloured as it falls for a player, and not for anything else.
require('common')
local bit = require('bit')
local perf = require('perf')

local target = { }


target.Samples = {
    main = { Name = 'Sample Target', Distance = 8 * 8, HPPercent = 75, ServerId = 0 },
    sub = { Name = 'Sample Sub-target', Distance = 12 * 12, HPPercent = 100, ServerId = 0 },
    tot = { Name = 'Sample Target of Target', Distance = 3 * 3, HPPercent = 40, ServerId = 0 },
}

-- Which entity each window is for, by its index, or 0 for none. settings say which windows are wanted.
function target.Indexes(settings)
    if not settings.showMain[1] and not settings.showSub[1] and not settings.showTot[1] then return 0,0,0 end
    local targets = AshitaCore:GetMemoryManager():GetTarget()
    local mainIndex = targets:GetTargetIndex(0)
    local mainActive = targets:GetIsActive(0) == 1
    local subIndex = targets:GetTargetIndex(1)
    local subActive = targets:GetIsSubTargetActive() == 1

    -- the game holds its targets as a stack: with a sub-target out, that is first and the target second
    if subActive then
        mainIndex, subIndex = subIndex, mainIndex
    end

    -- the target of target comes from the target itself, so that it still shows when the target's
    -- own window is switched off
    mainIndex = (mainActive and mainIndex ~= 0) and mainIndex or 0
    local totIndex=0
    if settings.showTot[1] and mainIndex~=0 then
        local mainEntity=perf.Entity(mainIndex)
        totIndex=mainEntity and mainEntity.TargetedIndex or 0
    end

    return settings.showMain[1] and mainIndex or 0,
        (settings.showSub[1] and subActive) and subIndex or 0,
        totIndex
end

-- The lowest bit of an entity's spawn flags is set for a player character, and for nothing else
local spawnFlagPlayer = 0x01

local function IsPlayer(entity)
    return entity.SpawnFlags ~= nil and bit.band(entity.SpawnFlags, spawnFlagPlayer) ~= 0
end

local sampleIds = { main = -3001, sub = -3002, tot = -3003 }

-- Each window's line, kept: its figures are only made into words again when they change
local kept = { } -- key -> { the line }

function target.Line(key, entity)
    local lines = kept[key]
    if lines == nil then
        lines = { { isInZone = true, tp = 0 } }
        kept[key] = lines
    end

    local line = lines[1]
    line.name = entity.Name
    line.statusServerId = entity.ServerId ~= 0 and entity.ServerId or nil
    -- its own kept figures, apart from a party member's of the same id; a made-up target, whose id is
    -- none, has its window's own
    local serverId = entity.ServerId or 0
    line.serverId = serverId ~= 0 and -serverId or sampleIds[key]
    line.plainHp = not IsPlayer(entity)
    if line.hpp ~= entity.HPPercent then
        line.hpp = entity.HPPercent
        line.hpText = string.format('%d%%', entity.HPPercent)
    end
    -- the distance is written to a tenth
    local tenths = math.floor(math.sqrt(entity.Distance) * 10 + 0.5)
    if line.tenths ~= tenths then
        line.tenths = tenths
        line.tpText = string.format('%.1fm', tenths / 10)
    end
    return lines
end

-- A monster's spawn letter, as name writes it over the monster, upper case, or nil for none. The area's
-- list of names is read from the game's files when first wanted there (winxi.zone_names), and the
-- letters given by it (winxi.mob_letters), the same for every player.
local letters, zoneNames = nil, nil
local lettersZone = nil
local upper = { } -- letters -> in upper case, made once each
local spawnFlagMonster = 0x10
function target.Letter(entity, index)
    if entity.SpawnFlags == nil or bit.band(entity.SpawnFlags, spawnFlagMonster) == 0 or index == nil then return nil end
    if letters == nil then
        letters, zoneNames = require('winxi.mob_letters'), require('winxi.zone_names')
        letters.Quiet = true -- name says it, where the list is not the game's
    end
    local zone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)
    if zone ~= lettersZone then
        lettersZone = zone
        letters.Set(zone ~= nil and zone ~= 0 and zoneNames.Read(zone) or { }, zone)
    end
    local letter = letters.Of(index, entity.Name, entity.ServerId)
    if letter == '' then return nil end
    local shown = upper[letter]
    if shown == nil then
        shown = letter:upper()
        upper[letter] = shown
    end
    return shown
end

-- Whether the player is locked on to the main target
function target.LockedOn()
    local flags = AshitaCore:GetMemoryManager():GetTarget():GetLockedOnFlags()
    return type(flags) == 'number' and bit.band(flags, 1) ~= 0
end

return target
