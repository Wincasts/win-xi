-- The auto attack timer: when your next round comes, from your weapons, job traits and haste, and
-- then from the gaps between your own rounds. A cut-down cadence (its core/delay.lua and
-- core/attack.lua, by Kipling): the same server rules, without its gear modifier tables.
--
-- The server times attacks in LSB attack_state.cpp, which Phoenix runs unchanged. The timer starts at
-- 3 s when you engage and the first 0.4 s server tick takes a full tick off, so the first round comes
-- 2.8 to 3.2 s after the server sees you engage. Each round adds your delay to a timer drained in
-- 0.4 s ticks, with what is left over carried, so one gap can be 0.4 s off and they average out to
-- the delay. Job abilities and weapon skills hold it 2 s; spells, items and ranged attacks hold it
-- while they run, then 2 s after a spell, 0.8 s after a ranged attack and 0.4 s after an item. Sleep,
-- stun and the like stop it where it is.
local swing = {}

---------------------------------------------------------------------------------------------------
-- The delay worked out from what you hold
---------------------------------------------------------------------------------------------------

-- Delay is in 1/60 s. An empty main hand attacks as a 480 weapon; the client keeps hand-to-hand
-- weapons' delay 240 under the server's.
local unarmedDelay, h2hClientOffset = 480, 240
local skillH2H = 1
local twoHanded = { [4] = true, [6] = true, [7] = true, [8] = true, [10] = true, [12] = true }
local dualWieldable = { [2] = true, [3] = true, [5] = true, [9] = true, [11] = true }

-- Trait ranks as { level, value }, highest first, by job: the best of the main and sub job's. They
-- are the server's (winxi.traits, made from its traits table); these are its era's rows, for when
-- winxi's data is not installed.
local MARTIAL_ARTS, DUAL_WIELD = 23, 18 -- the server's trait numbers
local martialArts = {
    [2] = { { 75, 180 }, { 61, 160 }, { 46, 140 }, { 31, 120 }, { 16, 100 }, { 1, 80 } }, -- MNK
    [18] = { { 75, 120 }, { 50, 100 }, { 25, 80 } },                                     -- PUP
}
local dualWield = {
    [13] = { { 65, 30 }, { 45, 25 }, { 25, 15 }, { 10, 10 } },                           -- NIN
}

-- A trait's ranks from winxi.traits, or nil where there are none to be had
local function RanksOf(id)
    local ok, traits = pcall(require, 'winxi.traits')
    local rows = ok and traits and traits.Rows(id) or {}
    if #rows == 0 then
        return nil
    end
    local ranks = {}
    for _, row in ipairs(rows) do
        local list = ranks[row.job] or {}
        ranks[row.job] = list
        list[#list + 1] = { row.level, row.value }
    end
    for _, list in pairs(ranks) do
        table.sort(list, function (a, b) return a[1] > b[1] end)
    end
    return ranks
end
martialArts = RanksOf(MARTIAL_ARTS) or martialArts
dualWield = RanksOf(DUAL_WIELD) or dualWield

-- Buffs the client can see, and how much delay each takes off; negative adds it. guessed: its
-- strength changes from one cast to the next, so what was learned with it is not kept.
local hasteBuffs = {
    [33] = { magic = 0.1465 },                          -- Haste
    [214] = { magic = 0.06, guessed = true },           -- March
    [126] = { magic = 0.25 },                           -- Spirit Surge
    [13] = { magic = -0.18, guessed = true },           -- Slow
    [194] = { magic = -0.25, guessed = true },          -- Elegy
    [1] = { magic = -1.0 },                             -- Weakness
    [353] = { ability = 0.10, twoHandedOnly = true },   -- Hasso
}
local hundredFists = 46
local magicCap, abilityCap = 0.4375, 0.25
-- the most delay haste can take off: the server's main.DELAY_REDUCTION_CAP
local hasteCap = 0.93

-- The server's (winxi.rules, read from its code) where winxi's data is installed: the caps, and what
-- Haste, Spirit Surge and Hasso give; the numbers above are the same, for where it is not
local HASTE_SPELL, HASTE_STATUS, SPIRIT_SURGE, HASSO = 57, 33, 126, 353
local okRules, rules = pcall(require, 'winxi.rules')
do
    local caps = okRules and rules.Get('haste') or nil
    if caps then
        magicCap, abilityCap, hasteCap = caps.MagicCap or magicCap, caps.AbilityCap or abilityCap, caps.DelayReductionCap or hasteCap
    end
    local effects = okRules and rules.Get('hasteEffects') or nil
    if effects then
        local spell = effects.Spells and effects.Spells[HASTE_SPELL]
        if spell then hasteBuffs[HASTE_STATUS] = { magic = spell } end
        for status, symbol in pairs({ [SPIRIT_SURGE] = 'SPIRIT_SURGE', [HASSO] = 'HASSO' }) do
            local fixed = effects.Fixed and effects.Fixed[symbol]
            if fixed then
                hasteBuffs[status] = { [fixed.Kind] = fixed.Haste, twoHandedOnly = fixed.TwoHanded or nil }
            end
        end
    end
end

local function Ms(units)
    return math.floor(units * 1000 / 60)
end

local function Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function Trait(ranks, loadout)
    local best = 0
    for _, side in ipairs({ { loadout.mainJob, loadout.mainLevel }, { loadout.subJob, loadout.subLevel } }) do
        for _, rank in ipairs(ranks[side[1]] or {}) do
            if (side[2] or 0) >= rank[1] then
                best = math.max(best, rank[2])
                break
            end
        end
    end
    return best
end

-- loadout = { main = { id, delay, skill } or nil, sub = the same or nil, mainJob, mainLevel, subJob,
-- subLevel, buffs = { [id] = true } }. Returns the seconds between rounds.
function swing.Estimate(loadout)
    local main = loadout.main
    local skill = main and main.skill or skillH2H
    local h2h = skill == skillH2H
    local units = main and main.delay or unarmedDelay
    if main ~= nil and h2h then units = units + h2hClientOffset end

    local weapon = Ms(units)
    local martial = h2h and Ms(Trait(martialArts, loadout)) or 0
    local dual = 0
    if not h2h and dualWieldable[skill] and loadout.sub ~= nil and dualWieldable[loadout.sub.skill] then
        weapon = weapon + Ms(loadout.sub.delay)
        dual = Trait(dualWield, loadout)
    end

    if loadout.buffs[hundredFists] then
        -- with any weapon; nothing else counts
        return math.floor(Clamp(weapon - martial, 1600, 8000) * 0.25) / 1000
    end

    local magic, ability = 0, 0
    for id, haste in pairs(hasteBuffs) do
        if loadout.buffs[id] and (not haste.twoHandedOnly or twoHanded[skill]) then
            magic = magic + (haste.magic or 0)
            ability = ability + (haste.ability or 0)
        end
    end
    magic = Clamp(magic, -1, magicCap)
    ability = Clamp(ability, -abilityCap, abilityCap)
    local haste = Clamp(1 - magic - ability, 1 - hasteCap, 2)

    local ms = math.floor((weapon - martial) * (1 - dual / 100))
    ms = math.floor(ms * haste)
    return Clamp(ms, math.floor(weapon * 0.2), weapon * 2) / 1000
end

-- What the estimate depends on, as a string: the gaps learned are kept under it
function swing.Key(loadout)
    local ids = {}
    for id in pairs(loadout.buffs) do
        if hasteBuffs[id] or id == hundredFists then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ('%d:%d:%d/%d:%d/%d:%s'):format(loadout.main and loadout.main.id or 0, loadout.sub and loadout.sub.id or 0,
        loadout.mainJob or 0, loadout.mainLevel or 0, loadout.subJob or 0, loadout.subLevel or 0, table.concat(ids, ','))
end

-- True when a key holds a buff whose strength is guessed: what is learned with it is not kept
local function Guessed(key)
    for id in (key:match(':([%d,]*)$') or ''):gmatch('%d+') do
        local haste = hasteBuffs[tonumber(id)]
        if haste and haste.guessed then return true end
    end
    return false
end

---------------------------------------------------------------------------------------------------
-- The timer
---------------------------------------------------------------------------------------------------

-- The first round comes the server's engage wait, less the tick that takes a full tick off it; an
-- action holds the timer for its own animation (passed to Ability and CastEnd, from winxi's sets),
-- or for these where that is not known; a ranged attack for the server's weapon return, an item for a
-- tick. The server's where winxi's data is installed (winxi.rules' swing).
local firstRound = 2.8
local abilityHold = 2.0
local castHold = { spell = 2.0, ranged = 0.8, item = 0.4 }
do
    local timing = okRules and rules.Get('swing') or nil
    if timing and timing.EngageDelay and timing.Tick then
        firstRound = timing.EngageDelay - timing.Tick
        castHold.ranged = timing.RangedHold or castHold.ranged
        castHold.item = timing.Tick
    end
end
local gapsToTrust, gapsKept, keysKept = 3, 6, 16
local snapToEstimate = 0.04
-- a gap longer than this many times the estimate had a pause that was not seen
local longestClean = 1.5
-- a paralyzed round sends the packet a paralyzed ability does: well before a round is due, it is one
local dueSoon = 0.5

local state = {
    active = false,
    last = nil,       -- when the last round came (or the engage, before the first)
    next = nil,       -- when the next is expected
    delay = nil,      -- seconds between rounds in use
    estimate = nil,
    key = nil,
    gaps = {},
    clean = false,    -- false when something held the timer since the last round
    stalled = false,
    reason = nil,     -- 'Too Far' or 'Not Facing', after the server said so
    heldSince = nil,
    heldBy = nil,     -- 'spell', 'ranged' or 'item'
    stoppedSince = nil,
    stoppedBy = nil,  -- what stops it: 'Asleep', 'Stunned' and the like
    lateJoin = false, -- engaged before tempo saw it: the first round's time is not known
}

local gapsByKey, keysByUse = {}, {}

local function GapsFor(key)
    for index, used in ipairs(keysByUse) do
        if used == key then
            table.remove(keysByUse, index)
            break
        end
    end
    keysByUse[#keysByUse + 1] = key
    if #keysByUse > keysKept then
        gapsByKey[table.remove(keysByUse, 1)] = nil
    end
    local gaps = gapsByKey[key]
    if gaps == nil or Guessed(key) then
        gaps = {}
        gapsByKey[key] = gaps
    end
    return gaps
end

local function Learned(gaps)
    if #gaps < gapsToTrust then return nil end
    local total = 0
    for _, gap in ipairs(gaps) do total = total + gap end
    return total / #gaps
end

local function Choose(gaps, estimate)
    local learned = Learned(gaps)
    -- the estimate is right to the millisecond when nothing unseen changes it
    if learned == nil or math.abs(learned - estimate) <= snapToEstimate then return estimate end
    return learned
end

local function UseKey(key)
    if key ~= state.key then
        state.key = key
        state.gaps = GapsFor(key)
    end
end

function swing.Engage(now, estimate, key, lateJoin)
    UseKey(key)
    state.active, state.lateJoin = true, lateJoin == true
    state.last, state.next = now, now + firstRound
    state.estimate, state.delay = estimate, Choose(state.gaps, estimate)
    state.heldSince, state.stoppedSince = nil, nil
    state.clean, state.stalled, state.reason = false, false, nil
end

function swing.Disengage()
    state.active = false
    state.heldSince, state.stoppedSince, state.reason = nil, nil, nil
end

-- One of your rounds came. The gear and buffs you have now decide the next gap.
function swing.Round(now, estimate, key)
    if not state.active then return end
    if key ~= state.key then
        UseKey(key)
    elseif state.clean then
        local gap = now - state.last
        if gap > 0 and gap <= estimate * longestClean then
            table.insert(state.gaps, gap)
            if #state.gaps > gapsKept then table.remove(state.gaps, 1) end
        end
    end
    state.estimate, state.delay = estimate, Choose(state.gaps, estimate)
    state.last, state.next = now, now + state.delay
    state.lateJoin, state.heldSince, state.stoppedSince = false, nil, nil
    -- the round after a stall comes on a short timer: that gap is not learned
    state.clean, state.stalled, state.reason = not state.stalled, false, nil
end

-- A job ability or weapon skill went off; hold: its animation's seconds, where they are known
function swing.Ability(now, hold)
    if not state.active then return end
    state.next = now + math.max(state.next - now, 0) + (hold or abilityHold)
    state.clean, state.reason = false, nil
end

-- A paralyzed (or intimidated) round, or a paralyzed ability: told apart by when it came
function swing.Paralyzed(now)
    if not state.active or state.heldSince ~= nil then return end
    if now < state.next - dueSoon then
        swing.Ability(now)
        return
    end
    state.last, state.next = now, now + state.delay
    state.clean, state.reason = false, nil
end

-- A spell, item or ranged attack began ('spell', 'item' or 'ranged'): the timer waits for it
function swing.CastBegin(now, kind)
    if not state.active or state.heldSince ~= nil then return end
    state.heldSince, state.heldBy, state.clean = now, kind, false
end

function swing.CastEnd(now, hold)
    if not state.active or state.heldSince == nil then return end
    state.next = now + math.max(state.next - state.heldSince, 0) + (hold or castHold[state.heldBy])
    state.heldSince, state.reason = nil, nil
    if state.stoppedSince ~= nil then state.stoppedSince = now end
end

-- The server said you cannot attack: 'Too Far', 'Not Facing'
function swing.OutOfReach(reason)
    state.clean, state.stalled, state.reason = false, true, reason
end

-- Sleep, stun and the like (why: what to say), or nil once none is on you
function swing.Stopped(now, why)
    if why ~= nil then
        state.clean, state.stoppedBy = false, why
        if state.active and state.stoppedSince == nil then state.stoppedSince = now end
    elseif state.stoppedSince ~= nil then
        if state.active and state.heldSince == nil then
            state.next = now + math.max(state.next - state.stoppedSince, 0)
        end
        state.stoppedSince = nil
    end
end

-- Returns nil out of a fight, or: how full the bar is (0 to 1), the seconds to the next round (nil
-- before the first round of a fight joined late), the delay in use, whether it was learned, and what
-- to say instead of the time ('Too Far', 'Casting', 'Asleep'), or nil
local holdWords = { spell = 'Casting', ranged = 'Shooting', item = 'Using Item' }
function swing.Progress(now)
    if not state.active then return nil end
    local learned = Learned(state.gaps) ~= nil
    local why = (state.stoppedSince and state.stoppedBy) or (state.heldSince and holdWords[state.heldBy]) or state.reason
    if state.lateJoin then
        return 0, nil, state.delay, learned, why
    end
    local clock = state.heldSince or state.stoppedSince or now
    local span = state.next - state.last
    local left = math.max(state.next - clock, 0)
    return span > 0 and 1 - left / span or 1, left, state.delay, learned, why
end

function swing.IsActive()
    return state.active
end

-- Zoning: what was learned stays
function swing.Reset()
    swing.Disengage()
    state.key, state.gaps = nil, {}
end

-- Another character: nothing learned carries over
function swing.Forget()
    swing.Reset()
    gapsByKey, keysByUse = {}, {}
end

return swing
