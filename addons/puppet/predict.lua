-- predict: the enfeebling spells an automaton will cast, in the order it will cast them.
--
--     local queue, reason = predict.Queue({
--         head = 1, frame = 0x20,              -- as the server names them
--         skill = 120,                         -- the automaton's magic skill
--         maneuvers = { light = 1, dark = 0 }, -- how many of each element are up
--         has = function(kind) ... end,        -- whether the target has a debuff, by winxi.debuffs' kinds
--         hpp = 100, mpp = 100,                -- the automaton's own HP and MP, as percentages
--     })
--
-- queue is a list of spell names, the next to be cast first. When it is empty, reason says why.
--
-- This is the server's own choosing, from its automaton controller, as Phoenix runs it: every head
-- has a set order, each maneuver moves the spells of its element to the front, and a spell is passed
-- over when the automaton lacks the skill for it or the target has its effect already. Addle,
-- Poison II, Dispel, Aspir II and Absorb-INT are left out: no automaton can cast them in this era.
--
-- It says nothing of when: healing and nuking can come first, each spell waits on its own timer, and
-- an enemy immune to a spell is passed over without this knowing.
local predict = {}

predict.Heads = {
    Harlequin = 1,
    Valoredge = 2,
    Sharpshot = 3,
    Stormwaker = 4,
    Soulsoother = 5,
    Spiritreaver = 6,
}

-- The frames that cast at all
local castingFrames = { [0x20] = true, [0x23] = true } -- Harlequin, Stormwaker

-- kind: the debuff it leaves. skill: the magic skill it needs. unless: a debuff it will not be cast over.
local BioII    = { name = 'Bio II',   kind = 'bio',     skill = 111, unless = 'dia' }
local DiaII    = { name = 'Dia II',   kind = 'dia',     skill =  96, unless = 'bio' }
local Bio      = { name = 'Bio',      kind = 'bio',     skill =  33, unless = 'dia' }
local Dia      = { name = 'Dia',      kind = 'dia',     skill =   0, unless = 'bio' }
local Poison   = { name = 'Poison',   kind = 'poison',  skill =  18 }
local Silence  = { name = 'Silence',  kind = 'silence', skill =  57 }
local Slow     = { name = 'Slow',     kind = 'slow',    skill =  42 }
local Blind    = { name = 'Blind',    kind = 'blind',   skill =  27 }
local Paralyze = { name = 'Paralyze', kind = 'para',    skill =  21 }
local Aspir    = { name = 'Aspir',    skill = 78 }
local Drain    = { name = 'Drain',    skill = 45 }

-- Each head's order, and for each spell the element whose maneuver brings it forward
local usualOrder = {
    { BioII, 'dark' }, { DiaII, 'light' }, { Bio, 'dark' }, { Dia, 'light' }, { Poison, 'water' },
    { Silence, 'wind' }, { Slow, 'earth' }, { Blind, 'dark' }, { Paralyze, 'ice' },
}
local soulsootherOrder = {
    { Slow, 'earth' }, { Poison, 'water' }, { Blind, 'dark' }, { BioII, 'dark' }, { DiaII, 'light' },
    { Bio, 'dark' }, { Dia, 'light' }, { Silence, 'wind' }, { Paralyze, 'ice' },
}
-- A Spiritreaver's Blind and Bio are never brought forward: it takes one Dark maneuver to have it
-- enfeeble at all, and two of another element to bring that element's spell forward
local spiritreaverOrder = {
    { Blind }, { BioII }, { DiaII, 'light' }, { Bio }, { Dia, 'light' }, { Poison, 'water' },
    { Silence, 'wind' }, { Slow, 'earth' }, { Paralyze, 'ice' },
}
local spiritreaverNeeds = 75 -- below this much of its own MP it casts Aspir, and of its HP Drain

function predict.Queue(state)
    if state.head == nil or state.frame == nil then
        return {}, 'Not told about the automaton yet. Change area or an attachment.'
    end
    if not castingFrames[state.frame] then
        return {}, 'This frame casts no spells.'
    end
    if state.head == predict.Heads.Valoredge then
        return {}, 'A Valoredge head only heals.'
    end

    local maneuvers = state.maneuvers or {}
    local function up(element)
        return maneuvers[element] or 0
    end

    local first, rest = {}, {}
    local order, needed = usualOrder, 1

    if state.head == predict.Heads.Soulsoother then
        order = soulsootherOrder
    elseif state.head == predict.Heads.Spiritreaver then
        order, needed = spiritreaverOrder, 2
        local lowMp = (state.mpp or 100) < spiritreaverNeeds
        local lowHp = (state.hpp or 100) < spiritreaverNeeds
        if up('dark') == 0 and not lowMp and not lowHp then
            return {}, 'A Spiritreaver head needs a Dark maneuver to enfeeble.'
        end
        if lowMp then
            first[#first + 1] = Aspir
        end
        if lowHp then
            first[#first + 1] = Drain
        end
        if up('dark') == 0 then
            order = {}
        end
    end

    for _, entry in ipairs(order) do
        local spell, element = entry[1], entry[2]
        if not (spell.unless and state.has(spell.unless)) then
            if element and up(element) >= needed then
                first[#first + 1] = spell
            else
                rest[#rest + 1] = spell
            end
        end
    end

    -- one spell for each debuff: the first the automaton can cast, where the target has not got it
    local queue, taken = {}, {}
    local function consider(spell)
        if (state.skill or 0) < spell.skill then
            return
        end
        if spell.kind then
            if state.has(spell.kind) or taken[spell.kind] then
                return
            end
            -- once Bio or Dia is on, the other is not cast
            if spell.unless and taken[spell.unless] then
                return
            end
            taken[spell.kind] = true
        end
        queue[#queue + 1] = spell.name
    end
    for _, spell in ipairs(first) do consider(spell) end
    for _, spell in ipairs(rest) do consider(spell) end

    if #queue == 0 then
        return queue, 'Nothing left to cast on this target.'
    end
    return queue, nil
end

return predict
