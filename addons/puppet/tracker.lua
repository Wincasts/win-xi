-- tracker: when the automaton last did each kind of thing, from the actions the server reports.
--
--     tracker.Action(action, petId)    an action as winxi.packets parses it, and the automaton's id
--     tracker.Since(kind, now)         seconds since it last did that, or nil if it has not been seen to
--     tracker.Clear()                  forget everything: another automaton, another area
--
-- The kinds are magic (any spell), heal, enfeeble, elemental and status (each kind of spell), ranged
-- and bash. The server times each from the moment the automaton begins, so a spell is counted from
-- the start of its casting, whether or not it is finished.
local tracker = {}

local categorySpellStart = 8
local categoryMobSkill = 11
local spellBegins = 24931 -- the start of a casting, as against one broken off

local skillRanged = 1949
local skillBash = 1944

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
    if action.category == categorySpellStart and action.param == spellBegins then
        local target = action.targets[1]
        local result = target and target.actions[1]
        last.magic = now
        local kind = result and spellKinds[result.param]
        if kind then
            last[kind] = now
        end
    elseif action.category == categoryMobSkill then
        if action.param == skillRanged then
            last.ranged = now
        elseif action.param == skillBash then
            last.bash = now
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
