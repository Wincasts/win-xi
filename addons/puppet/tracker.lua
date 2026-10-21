-- tracker: when the automaton last did each kind of thing, from the actions the server reports.
--
--     tracker.Action(action, petId)    an action as winxi.packets parses it, and the automaton's id
--     tracker.Since(kind, now)         seconds since it last did that, or nil if it has not been seen to
--     tracker.Clear()                  forget everything: another automaton, another area
--
-- The kinds are magic (any spell), heal, enfeeble, elemental and status (each kind of spell), ranged,
-- bash, and one for each thing an attachment does of its own accord (provoke, flash, stoneskin, spikes,
-- blink, eraser, economizer, converter, barrage, capacitor, disruptor, regulator). The server times each
-- from the moment the automaton begins, so a spell is counted from the start of its casting, whether or
-- not it is finished.
local bit = require('bit')

local tracker = {}

local categorySpellStart = 8
local categoryMobSkill = 11
-- A spell-start packet's param is a four-letter code for the kind of magic and whether it begins or is
-- broken off: "cawh" (0x68776163) for white magic beginning, "cabk" for black, "spwh" for white magic
-- broken off, and so on. The last two letters, the low sixteen bits, say which: "ca" begins, "sp" stops.
local spellBegins = 0x6163 -- "ca"

-- The kind of each thing the automaton does as a mob skill, by the server's number for it
local skillKinds = {
    [1949] = 'ranged',
    [1944] = 'bash',
    [1945] = 'provoke',    -- Strobe
    [1946] = 'stoneskin',  -- Shock Absorber
    [1947] = 'flash',      -- Flashbulb
    [1948] = 'converter',  -- Mana Converter
    [2021] = 'eraser',     -- Eraser
    [2031] = 'spikes',     -- Reactive Shield
    [2068] = 'economizer', -- Economizer
    [2132] = 'blink',      -- Replicator
    [2745] = 'capacitor',  -- Heat Capacitor
    [2746] = 'barrage',    -- Barrage Turbine
    [2747] = 'disruptor',  -- Disruptor
    [3485] = 'regulator',  -- Regulator
}

-- The kind of each spell an automaton casts
local spellKinds = {}
for spell = 1, 6 do spellKinds[spell] = 'heal' end                 -- Cure to Cure VI
for spell = 14, 20 do spellKinds[spell] = 'status' end             -- Poisona to Cursna
spellKinds[143] = 'status'                                         -- Erase
for spell = 144, 173 do spellKinds[spell] = 'elemental' end        -- Fire to Water V
for _, spell in ipairs({ 23, 24, 230, 231, 220, 221, 59, 56, 254, 58, 286, 260, 245, 247, 248, 266 }) do
    spellKinds[spell] = 'enfeeble'                                 -- Dia, Bio, Poison, Silence, Slow, Blind, Paralyze, Addle, Dispel, Drain, Aspir, Absorb-INT
end

local last = {} -- kind -> when

function tracker.Action(action, petId)
    if petId == nil or action.actor_id ~= petId then
        return
    end

    local now = os.clock()
    if action.category == categorySpellStart and bit.band(action.param, 0xFFFF) == spellBegins then
        local target = action.targets[1]
        local result = target and target.actions[1]
        last.magic = now
        local kind = result and spellKinds[result.param]
        if kind then
            last[kind] = now
        end
    elseif action.category == categoryMobSkill then
        local kind = skillKinds[action.param]
        if kind then
            last[kind] = now
        end
    end
end

function tracker.Since(kind, now)
    local at = last[kind]
    return at and ((now or os.clock()) - at) or nil
end

function tracker.Clear()
    last = {}
end

return tracker
