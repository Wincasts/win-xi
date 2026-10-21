-- tp: how fast the automaton builds TP, from its TP as the game shows it, and so how long until it has
-- the TP for a weapon skill.
--
--     tp.Sample(value, now)     the automaton's TP now: called every frame, kept when it has changed
--     tp.Rate(now)              TP a second, from the last half minute, or nil until it has been seen to gain
--     tp.Until(target, now)     seconds until it has target TP: 0 with it already, nil with no rate known
--     tp.Clear()                another automaton, another area: nothing known
--
-- The rate is the TP gained over the samples of the last window seconds, from the first of them to the
-- last. A fall in TP is a weapon skill (or Cannibal Blade, or rest), and the samples start again from
-- it, so that the rate is of the TP built since.
local tp = {}

local window = 30     -- seconds of samples kept
local atLeast = 3     -- seconds of gaining before a rate is given
local samples = {}    -- { at, tp }, oldest first

function tp.Sample(value, now)
    now = now or os.clock()
    local last = samples[#samples]
    if last ~= nil and value < last.tp then
        samples = {}
        last = nil
    end
    if last == nil or value ~= last.tp then
        samples[#samples + 1] = { at = now, tp = value }
    end
    -- the samples older than the window go, but the last two are kept, so that a rate can still be given
    -- while the TP sits unchanged
    while #samples > 2 and now - samples[1].at > window do
        table.remove(samples, 1)
    end
end

function tp.Rate(now)
    local first, last = samples[1], samples[#samples]
    if first == nil or last == first or last.at - first.at < atLeast or last.tp <= first.tp then
        return nil
    end
    return (last.tp - first.tp) / (last.at - first.at)
end

function tp.Until(target, now)
    local last = samples[#samples]
    if last == nil then
        return nil
    end
    if last.tp >= target then
        return 0
    end
    local rate = tp.Rate(now)
    if rate == nil then
        return nil
    end
    return (target - last.tp) / rate
end

function tp.Clear()
    samples = {}
end

return tp
