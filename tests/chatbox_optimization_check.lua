-- Shared wrapping must survive viewport/filter changes without retaining evicted history.
package.path = 'addons/chatbox/?.lua;' .. package.path
local model = require('log')
local calls = 0
local function measure(text) calls = calls + 1; return #text end
local log = model.New()
for i = 1, model.Capacity do
    model.Add(log, ('Player%d: repeated words for wrapping\nsecond paragraph'):format(i), i % 2 + 1,
        nil, nil, {{ first = 1, last = 6, bank = 31, slot = 50 }})
end
local function metrics(width, modes, font, size, fn)
    return model.Metrics(log, width, font or 'font', size or 12, fn or measure, modes)
end
local function tail(width, offset, modes, font, size, fn)
    return model.Tail(log, width, font or 'font', size or 12, fn or measure, 10, modes, 0, offset)
end
metrics(24); metrics(20)
local before = calls
for i = 1, 100 do
    local modes = i % 2 == 0 and {[1] = true} or nil
    metrics(24, modes); metrics(20, modes)
    tail(20, i * 3, modes)
end
assert(calls == before, 'scrolling and filter changes reuse wrapping at both widths')
-- Compare cached rows, including sliced spans and message identities, against a cold layout.
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local cold = model.New()
cold.messages, cold.revision = log.messages, log.revision
for _, modes in ipairs({false, {[1] = true}, {[2] = true}}) do
    for _, offset in ipairs({0, 3, 50, 700, 100000}) do
        local rows, actual, overflow = tail(20, offset, modes or nil)
        cold.cache, cold.wraps = nil, nil
        local expected, expectedOffset, expectedOverflow = model.Tail(cold, 20, 'font', 12, measure, 10, modes or nil, 0, offset)
        assert(same(rows, expected) and actual == expectedOffset and overflow == expectedOverflow,
            'cached viewport preserves rows, spans, offsets and overflow')
    end
end
local removed = log.messages[1]
model.Add(log, 'new message for wrapping', 1)
for _, layout in ipairs(log.wraps) do
    assert(layout.messages[removed] == nil, 'evicted messages leave wrap caches immediately')
end
before = calls
metrics(24); metrics(20)
local appendedCalls = calls - before
assert(appendedCalls > 0, 'new message is measured')
before = calls
metrics(24); metrics(20); tail(20, 30)
assert(calls == before, 'append retains existing message layouts')
for _, change in ipairs({
    function() metrics(19) end,
    function() metrics(19, nil, 'other-font') end,
    function() metrics(19, nil, 'other-font', 14) end,
}) do
    before = calls; change()
    assert(calls > before, 'width/font/size changes invalidate wrapping')
    assert(#log.wraps <= 4, 'layout cache remains bounded')
end
for _, layout in ipairs(log.wraps) do
    local count = 0
    for _ in pairs(layout.messages) do count = count + 1 end
    assert(count <= model.Capacity, 'message cache remains bounded')
end
-- Two boxes (the game's second log window), each with its own filter and width and both overflowing so each
-- uses its scrollbar-reserved width too: once laid out, a frame wraps nothing and filters nothing.
local filtered = 0
local first = function(message) filtered = filtered + 1; return message.mode == 1 end
local second = function(message) filtered = filtered + 1; return message.mode == 2 end
local function box(width, filter, rows)
    if metrics(width, filter).total > rows then width = width - 2; metrics(width, filter) end
    model.Tail(log, width, 'font', 12, measure, rows, filter, 0, 0)
end
local function frames() for _ = 1, 3 do box(24, first, 10); box(18, second, 6) end end
frames()
before, filtered = calls, 0
frames()
assert(calls == before and filtered == 0, 'two boxes keep each other\'s wrapping, metrics and rows')
model.Clear(log)
assert(log.wraps == nil and #tail(20, 0) == 0, 'clear discards cached private history')
print('Chatbox optimization: shared wrapping, scrolling, filters, spans, eviction, layout invalidation, two boxes and clear passed')
