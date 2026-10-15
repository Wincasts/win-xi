-- On-demand CPU profiling. GPU execution is not measured. Memory deltas are GC-sensitive estimates.
local perf = {}
local measuring, countersEnabled = false, false
local started, frequency, report
local render, packets, counters
local capacity = 16384
local function Bucket()
    return { count = 0, total = 0, worst = 0, samples = {}, memory = 0, memoryCount = 0 }
end
function perf.Start(reportTo, countOperations)
    report, countersEnabled = reportTo, countOperations == true
    frequency, started = tonumber(ashita.time.qpf().q), tonumber(ashita.time.qpc().q)
    render, packets, counters = Bucket(), Bucket(), {}
    measuring = true
end
function perf.Count(key)
    if measuring and countersEnabled then counters[key] = (counters[key] or 0) + 1 end
end
function perf.Entity(index)
    perf.Count('entity reads')
    return GetEntity(index)
end
local function Measure(bucket, fn, arg)
    local before = tonumber(ashita.time.qpc().q)
    local memory = collectgarbage('count')
    fn(arg)
    local after = tonumber(ashita.time.qpc().q)
    local grown = collectgarbage('count') - memory
    local took = (after - before) / frequency * 1000
    bucket.count, bucket.total = bucket.count + 1, bucket.total + took
    bucket.worst = math.max(bucket.worst, took)
    if #bucket.samples < capacity then bucket.samples[#bucket.samples + 1] = took end
    if grown >= 0 then
        bucket.memory, bucket.memoryCount = bucket.memory + grown, bucket.memoryCount + 1
    end
    return after
end
local function Summary(label, bucket)
    if bucket.count == 0 then return label .. ': no samples' end
    local samples = bucket.samples
    table.sort(samples)
    local function percentile(p) return samples[math.max(1, math.ceil(#samples * p))] end
    return ('%s: %d calls; avg %.3f ms, median %.3f, p95 %.3f, p99 %.3f, max %.3f; memory delta estimate %.2f KB/call%s')
        :format(label, bucket.count, bucket.total / bucket.count, percentile(.5), percentile(.95), percentile(.99),
            bucket.worst, bucket.memory / math.max(1, bucket.memoryCount),
            bucket.count > capacity and ' (percentiles: first 16384 samples)' or '')
end
local function Finish(now)
    measuring = false
    local text = ('%.1f s; %s | %s. Memory excludes negative GC deltas; not exact allocations. CPU only, not GPU.')
        :format((now - started) / frequency, Summary('render', render), Summary('packets', packets))
    if countersEnabled then
        local keys = {}
        for key in pairs(counters) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do text = text .. (' %s=%d;'):format(key, counters[key]) end
    end
    report(text)
end
function perf.Run(fn)
    if not measuring then return fn() end
    local now = Measure(render, fn)
    if (now - started) / frequency >= 5 then Finish(now) end
end
function perf.Packet(fn, event)
    if not measuring then return fn(event) end
    Measure(packets, fn, event)
end
return perf
