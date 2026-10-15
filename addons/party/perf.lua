-- perf: how long the addon takes over each frame, measured in play, for /pt perf.
--
--     perf.Start(report)     measures the frames of the next few seconds, then hands report the words
--     perf.Run(fn)           runs fn, the frame's work: timed while measuring, and only run otherwise
--
-- What is measured is all the addon does in a frame, the settings window included if it is open: the
-- time, by the high-resolution clock, and the memory made. A frame in which the collector ran has
-- made less than nothing, and is left out of the memory.
local perf = { }

local seconds = 5

local measuring = false
local report = nil
local frequency = 1
local started, frames, total, worst = 0, 0, 0, 0
local made, madeFrames = 0, 0

function perf.Start(reportTo)
    report = reportTo
    frequency = ashita.time.qpf().q
    started = ashita.time.qpc().q
    frames, total, worst, made, madeFrames = 0, 0, 0, 0, 0
    measuring = true
end

local function Finish(now)
    measuring = false
    local span = (now - started) / frequency
    local average = frames > 0 and total / frames or 0
    local memory = madeFrames > 0 and ('%.2f KB'):format(made / madeFrames) or 'unknown'
    report(('%d frames over %.1f s: %.3f ms a frame on average, %.3f ms at worst; %s of memory made a frame')
        :format(frames, span, average * 1000, worst * 1000, memory))
end

function perf.Run(fn)
    if not measuring then
        return fn()
    end

    local before = ashita.time.qpc().q
    local memory = collectgarbage('count')
    fn()
    local grown = collectgarbage('count') - memory
    local after = ashita.time.qpc().q

    local took = (after - before) / frequency
    frames, total = frames + 1, total + took
    if took > worst then
        worst = took
    end
    if grown >= 0 then
        made, madeFrames = made + grown, madeFrames + 1
    end

    if (after - started) / frequency >= seconds then
        Finish(after)
    end
end

return perf
