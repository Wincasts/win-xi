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

local target = { }


target.Samples = {
    main = { Name = 'Sample Target', Distance = 8 * 8, HPPercent = 75, ServerId = 0 },
    sub = { Name = 'Sample Sub-target', Distance = 12 * 12, HPPercent = 100, ServerId = 0 },
    tot = { Name = 'Sample Target of Target', Distance = 3 * 3, HPPercent = 40, ServerId = 0 },
}

-- Which entity each window is for, by its index, or 0 for none. settings say which windows are wanted.
function target.Indexes(settings)
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
    local mainEntity = mainIndex ~= 0 and GetEntity(mainIndex) or nil
    local totIndex = mainEntity and mainEntity.TargetedIndex or 0

    return settings.showMain[1] and mainIndex or 0,
        (settings.showSub[1] and subActive) and subIndex or 0,
        settings.showTot[1] and totIndex or 0
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

return target
