-- The resting (/heal) ticks: when the next one lands, about what it restores, and about when HP and
-- MP are full. A cut-down cadence (its core/resting.lua, by Kipling).
--
-- The server's rules (its scripts/effects/healing.lua, read by tools/build_rules.py into winxi.rules,
-- with these as they are there for where winxi's data is not installed): resting ticks every 10 s
-- from the moment you sit, and tick k restores 10 + (k - 2) HP and 12 + (k - 2) MP, more with gear
-- that adds to them; the first tick restores nothing. Under Signet or Sigil, HP is
-- 10 + 3 x (level / 10) + (k - 2) x (1 + max HP / 300), each division rounded down. The ticks run only on the zone's 3 s
-- effect pass, so each lands up to 3.2 s after its 10 s mark, and the gaps run 9, 9, 12. The first
-- that restores anything lands 20 to 23 s after you sit.
--
-- Until a tick is seen, the next is put at its mark and a little over; once one is seen, the passes
-- are known (every 3 s from it) and each tick is put on the first pass after its mark. What a seen
-- tick restored over the formula is taken for gear, and added to those after it.
local rest = {}

local period, pass = 10, 3
local hpBase, mpBase = 10, 12
local signetHp = { Base = 10, PerTenLevels = 3, Levels = 10, MaxHpPerTick = 300 }
do
    local ok, rules = pcall(require, 'winxi.rules')
    local resting = ok and rules.Get('resting') or nil
    if resting and resting.Tick and resting.EffectPass then
        period, pass = resting.Tick, resting.EffectPass
        hpBase, mpBase = resting.Hp.Base, resting.Mp.Base
        signetHp = resting.HpSignet or signetHp
    end
end
-- a tick lands this long after its mark, at the most; before the passes are known, it is put this
-- long after
local passLatest, passGuess = 3.2, 1.4
-- resting shows on your character about this long after the server starts it
local sitDelay = 0.25
-- how far after its time a change can come and still be taken for the tick, once the passes are known;
-- and a tick not seen by then is taken to have come all the same (at full HP and MP nothing shows)
local window = 0.7
local lateTick = 1.0

local state = {
    active = false,
    sat = nil,        -- when the server started resting, as near as is known
    passAt = nil,     -- when an effect pass was seen, or nil
    tick = 0,         -- the number of the last tick, seen or taken to have come
    hp = 0, mp = 0, hpMax = 0, mpMax = 0,
    bonusHp = 0,      -- what the last seen tick restored over the formula
    bonusMp = 0,
    lastHp = nil,     -- what the last seen tick restored
    lastMp = nil,
}

-- When tick k lands
local function TickTime(k)
    local mark = state.sat + period * k
    if state.passAt == nil then
        return mark + passGuess
    end
    return state.passAt + math.ceil((mark - state.passAt) / pass - 1e-6) * pass
end

local function Gains(k)
    local hp = hpBase + (k - 2)
    if state.signet then
        hp = signetHp.Base + signetHp.PerTenLevels * math.floor((state.level or 1) / signetHp.Levels)
            + (k - 2) * (1 + math.floor(state.hpMax / signetHp.MaxHpPerTick))
    end
    return hp + state.bonusHp, mpBase + (k - 2) + state.bonusMp
end

-- joined: resting began before tempo was there, so when is not known: the first tick seen tells it,
-- by how much it restored. signet: Signet or Sigil is on, which the server restores more HP under, by
-- level (the main job's)
function rest.Start(now, hp, mp, hpMax, mpMax, joined, signet, level)
    state.active, state.sat, state.passAt, state.tick = true, now - sitDelay, nil, 0
    state.signet, state.level = signet == true, level
    state.joined = joined == true
    state.hp, state.mp, state.hpMax, state.mpMax = hp, mp, hpMax, mpMax
    state.lastHp, state.lastMp = nil, nil
end

function rest.Stop()
    state.active = false
end

function rest.IsActive()
    return state.active
end

-- How far before and after its time a change can be taken for a tick: before the passes are known,
-- anywhere from its mark to passLatest after
local function Window()
    if state.passAt == nil then
        return passGuess + 0.2, passLatest - passGuess + lateTick
    end
    return window, window + lateTick
end

-- The tick a change at now is, or nil: the next one, or the one last taken to have come
local function Match(now)
    local early, late = Window()
    for k = math.max(state.tick, 2), state.tick + 1 do
        local at = TickTime(k)
        if now >= at - early and now <= at + late then
            return k
        end
    end
    return nil
end

-- Each frame while resting, with your HP and MP as they are
function rest.Frame(now, hp, mp, hpMax, mpMax)
    if not state.active then return end
    local gainedHp, gainedMp = hp - state.hp, mp - state.mp
    state.hp, state.mp, state.hpMax, state.mpMax = hp, mp, hpMax, mpMax

    if (gainedHp > 0 or gainedMp > 0) and state.joined then
        -- which tick it was, from the formula, MP first (less gear adds to it); then it is matched
        local k = (gainedMp > 0 and mp < mpMax and gainedMp - 10) or (gainedHp > 0 and hp < hpMax and gainedHp - 8) or nil
        if k ~= nil then
            state.joined, state.tick = false, math.max(2, k) - 1
            state.sat, state.passAt = now - period * (state.tick + 1) - passGuess, now
        end
    end

    if gainedHp > 0 or gainedMp > 0 then
        local k = Match(now)
        if k ~= nil then
            state.tick, state.passAt = k, now
            -- the tick came between its mark and passLatest after: when resting began, more nearly
            state.sat = math.max(now - period * k - passLatest, math.min(state.sat, now - period * k))
            state.lastHp, state.lastMp = gainedHp > 0 and gainedHp or nil, gainedMp > 0 and gainedMp or nil
            -- what it restored over the formula, where it was not cut short by the most there is
            local baseHp, baseMp = 10 + (k - 2), 12 + (k - 2)
            if gainedHp > 0 and hp < hpMax then state.bonusHp = math.max(0, gainedHp - baseHp) end
            if gainedMp > 0 and mp < mpMax then state.bonusMp = math.max(0, gainedMp - baseMp) end
            return
        end
    end

    -- ticks that showed nothing (at full, or diseased) are counted all the same
    local _, late = Window()
    while not state.joined and now > TickTime(state.tick + 1) + late do
        state.tick = state.tick + 1
    end
end

-- Returns nil when not resting, or: how full the bar is to the next tick (0 to 1), the seconds to it,
-- the HP and MP it should restore (nil for MP with none), the seconds until both are full (0 when
-- they are, nil when it cannot be told), and whether the passes are known
function rest.Progress(now)
    if not state.active then return nil end
    -- joined late, and no tick seen yet: nothing can be told
    if state.joined then return 0, nil, nil, nil, nil, false end
    local k = math.max(state.tick + 1, 2)
    local at = TickTime(k)
    -- the bar runs from the tick before (or from sitting down, for the first)
    local from = state.tick >= 2 and TickTime(state.tick) or state.sat + sitDelay
    local span = at - from
    local left = math.max(at - now, 0)
    local fill = span > 0 and 1 - left / span or 1

    local hpGain, mpGain = Gains(k)
    local missingHp, missingMp = state.hpMax - state.hp, state.mpMax - state.mp
    hpGain = math.max(0, math.min(hpGain, missingHp))
    mpGain = state.mpMax > 0 and math.max(0, math.min(mpGain, missingMp)) or nil

    -- the ticks to come, until both are full
    local full = 0
    local hp, mp = missingHp, state.mpMax > 0 and missingMp or 0
    local step = k
    while (hp > 0 or mp > 0) and step < k + 200 do
        local h, m = Gains(step)
        hp, mp = hp - h, mp - m
        full = TickTime(step) - now
        step = step + 1
    end
    if hp > 0 or mp > 0 then full = nil end
    return fill, left, hpGain, mpGain, full and math.max(full, 0), state.passAt ~= nil
end

return rest
