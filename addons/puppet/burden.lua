-- burden: how much burden the automaton has of each element, reckoned as the server reckons it.
--
--     burden.Spawned()                     a new automaton: it starts with 35 of every element
--     burden.Clear()                       nothing is known: another area, another character
--     burden.Action(action, state)         an action of the master's, as winxi.packets parses it
--     burden.Update(state, now)            settle elapsed ticks before changing decay modifiers
--     burden.Get(element, state)           value (or nil), exact-at-observation flag; time is monotonic
--     burden.Chance(element, state)        the chance in a hundred that one more maneuver of it overloads
--
-- An element is its place in burden.Elements, 1 to 8. state is what the reckoning needs of the game:
--
--     { frame = 0x20, attachments = { [162] = true }, overdrive = false }
--
-- The server's rules, as Phoenix runs them: an automaton starts with 35 of each element, and loses one
-- of each every three seconds, two with a Heatsink fitted. A maneuver adds between 14 and 20 to its
-- element, by how the master's stat for it stands against the automaton's; a Dark one 14, or 8 on a
-- Valoredge or Sharpshot frame. Past 30 a maneuver may overload: the chance in a hundred is the burden
-- less 25. Cooldown halves the lot.
--
-- The automaton's stats are not told to the game, so what a maneuver adds is not known beforehand: it
-- is taken for 20 until it has been seen. It is seen in what the server says of every maneuver, the
-- chance of overloading, which gives the burden exactly whenever there is any chance at all; with none,
-- the burden is 25 or less. So the figures put themselves right as maneuvers are used.
--
-- What is not known: the burden of an automaton that was out before the addon was loaded, until a
-- maneuver of that element says; and gear that moves the point of overloading, which puts a figure
-- taken from the server's chance out by as much.
local burden = {}

burden.Elements = { 'fire', 'ice', 'wind', 'earth', 'thunder', 'water', 'light', 'dark' }

local categoryAbility = 6
local abilityActivate, abilityDeusExAutomata, abilityCooldown = 136, 310, 309
local abilityFireManeuver = 141 -- the eight follow one another, in the elements' order
local elementDark = 8

local attachmentHeatsink = 162
local frameValoredge, frameSharpshot = 0x21, 0x22

local spawnedWith = 35
local tickSeconds = 3
local overloadPast = 30    -- with more than this, a maneuver may overload
local chanceLess = 25      -- and the chance is the burden less this
local costUnseen = 20      -- what a maneuver is taken to add until it has been seen: the most it can
local costLeast, costMost = 14, 20

-- element -> { value, at, sure }: the burden when it was last reckoned, and whether that was the
-- server's own figure (or follows from one) rather than a guess
local known = {}
local costs = {} -- element -> what a maneuver of it adds, once seen
local tickAt, decayRate = nil, 1

local function Decay(state)
    return (state.attachments and state.attachments[attachmentHeatsink]) and 2 or 1
end

local function Cost(element, state)
    if element == elementDark then
        return (state.frame == frameValoredge or state.frame == frameSharpshot) and 8 or 14
    end
    return costs[element] or costUnseen
end

-- Keep one decay phase for all elements; maneuvers must not restart their ticks.
-- The exact server phase is unavailable, so values between observations remain estimates.
function burden.Update(state, now)
    now = now or os.clock()
    if tickAt == nil or now < tickAt then tickAt = now end
    local ticks = math.floor((now - tickAt) / tickSeconds)
    if ticks > 0 then
        for _, entry in pairs(known) do
            entry.value = math.max(0, entry.value - decayRate * ticks)
        end
        tickAt = tickAt + ticks * tickSeconds
    end
    -- Settle elapsed ticks at the old rate before changing attachments.
    decayRate = Decay(state)
end

local function Set(element, value, sure, now)
    known[element] = { value = math.max(0, math.min(255, math.floor(value))), at = now, sure = sure }
end

function burden.Spawned(now)
    now = now or os.clock()
    tickAt = now
    for element = 1, #burden.Elements do
        Set(element, spawnedWith, true, now)
    end
end

function burden.Clear()
    known, costs = {}, {}
    tickAt, decayRate = nil, 1
end

function burden.Get(element, state, now)
    now = now or os.clock()
    burden.Update(state, now)
    local entry = known[element]
    if entry == nil then return nil end
    return entry.value, entry.sure and now == entry.at
end

function burden.Chance(element, state, now)
    local value = burden.Get(element, state, now)
    if value == nil or state.overdrive then
        return 0
    end
    local after = value + Cost(element, state)
    return after > overloadPast and math.min(100, math.floor(after - chanceLess + 0.5)) or 0
end

local function Maneuver(element, chance, state, now)
    local before = burden.Get(element, state, now)
    local entry = known[element]

    if chance > 0 then
        -- the server's own figure
        local after = chance + chanceLess
        if before ~= nil and entry.sure and element ~= elementDark then
            costs[element] = math.max(costLeast, math.min(costMost, math.floor(after - before + 0.5)))
        end
        Set(element, after, true, now)
    elseif state.overdrive then
        -- no chance is said in Overdrive, whatever the burden
        if before ~= nil then
            Set(element, before + Cost(element, state), false, now)
        end
    else
        -- no chance: it is at the most 25. A guess that comes to more was too much.
        local after = before and (before + Cost(element, state)) or chanceLess
        local seen = element == elementDark or costs[element] ~= nil
        Set(element, math.min(after, chanceLess), before ~= nil and entry.sure and seen and after <= chanceLess, now)
    end
end

function burden.Action(action, state, now)
    if action.category ~= categoryAbility then
        return
    end
    now = now or os.clock()

    burden.Update(state, now)
    local ability = action.param
    if ability == abilityActivate or ability == abilityDeusExAutomata then
        burden.Spawned(now)
    elseif ability == abilityCooldown then
        for element = 1, #burden.Elements do
            local value = burden.Get(element, state, now)
            if value ~= nil then
                Set(element, value / 2, known[element].sure, now)
            end
        end
    elseif ability >= abilityFireManeuver and ability < abilityFireManeuver + #burden.Elements then
        local target = action.targets and action.targets[1]
        local result = target and target.actions[1]
        Maneuver(ability - abilityFireManeuver + 1, result and result.param or 0, state, now)
    end
end

return burden
