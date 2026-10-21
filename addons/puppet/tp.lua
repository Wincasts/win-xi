-- TP gain over a rolling window. Time without gains counts too; a stalled rate expires.
local tp = {}

local window = 30
local atLeast = 3
local staleAfter = 10
local samples = {}
local burstUntil

function tp.Sample(value, now)
    now = now or os.clock()
    -- Pet memory can lag the action packet. Rebaseline through that update rather than counting
    -- an attachment's burst as ordinary attack gain on the following frame.
    if burstUntil and now <= burstUntil then
        samples = { { at = now, tp = value } }
        return
    end
    burstUntil = nil
    local last = samples[#samples]
    if last ~= nil and (value < last.tp or now < last.at or now - last.at >= staleAfter) then
        samples = {}
        last = nil
    end
    if last == nil or value ~= last.tp then
        samples[#samples + 1] = { at = now, tp = value }
    end
    -- Keep one predecessor at the window boundary, not two arbitrarily old samples.
    while #samples > 1 and samples[2].at <= now - window do
        table.remove(samples, 1)
    end
end

function tp.Rate(now)
    now = now or os.clock()
    local first, last = samples[1], samples[#samples]
    if first == nil or first == last or now < last.at or now - last.at >= staleAfter
        or now - first.at < atLeast or last.tp <= first.tp then
        return nil
    end
    return (last.tp - first.tp) / (now - first.at)
end

function tp.Until(target, now)
    local last = samples[#samples]
    if last == nil then return nil end
    if last.tp >= target then return 0 end
    local rate = tp.Rate(now)
    return rate and (target - last.tp) / rate or nil
end

function tp.Clear()
    samples, burstUntil = {}, nil
end

function tp.Burst(now)
    tp.Clear()
    burstUntil = (now or os.clock()) + 1
end

return tp
