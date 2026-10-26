package.path = 'addons/chatbox/?.lua;' .. package.path
local model = require('log')
local function measure(s) return #s end
local first = function(m) return m.mode == 1 or m.mode == 3 end
local second = function(m) return m.mode == 2 or m.mode == 3 end
local filters = { first, second }
local log = model.New()
model.SetRetention(log, filters)
local function add(text, mode) assert(model.Add(log, text, mode)) end
local function tail(filter) return model.Tail(log, 1000, nil, 14, measure, 10, filter) end
for i=1,9 do add('quiet '..i, 2) end
-- Warm the wrapping, metrics and tail caches before evictions.
assert(#tail(second)==9)
model.Metrics(log, 1000, nil, 14, measure, second)
for i=1,600 do add('busy '..i, 1) end
assert(#tail(second)==9 and tail(second)[1].text=='quiet 1')
assert(model.Count(log, first)==model.Capacity and model.Count(log, second)==9)
assert(model.Metrics(log, 1000, nil, 14, measure, second).total==9)
-- Traffic not routed to either window still has a bounded global budget.
for i=1,600 do add('unrouted '..i, 4) end
assert(#log.messages==2*model.Capacity+9 and #tail(second)==9)
for i=1,600 do add('second '..i, 2) end
assert(#log.messages==2*model.Capacity, 'global and second-window budgets overlap')
assert(model.Count(log, first)==model.Capacity and model.Count(log, second)==model.Capacity)
-- Overlapping routes retain the very same message, never duplicate it.
for i=1,600 do add('both '..i, 3) end
assert(#log.messages==model.Capacity and model.Count(log, first)==model.Capacity)
for _, layout in ipairs(log.wraps or {}) do
    local count=0; for _ in pairs(layout.messages) do count=count+1 end
    assert(count<=#log.messages, 'evicted messages leave wrapping caches')
end
-- Import can seed a quiet window even when the global budget is already full.
local entries={}
for i=1,20 do entries[i]={text='import '..i,mode=2} end
model.Clear(log)
for i=1,600 do add('first '..i, 1) end
assert(model.Prepend(log, entries)==20)
assert(model.Count(log, second)==20 and tail(second)[10].text=='import 20')
assert(log.messages[1].imported and log.messages[1].time==0)
-- Route changes prune against the new budgets, and invalidate cached metrics.
model.SetRetention(log, {first})
assert(model.Count(log, second)==0 and #tail(second)==0)
model.SetRetention(log, nil)
assert(#log.messages==model.Capacity)
model.SetRetention(log, filters)
model.Clear(log)
assert(#log.messages==0 and #tail(first)==0 and #tail(second)==0)
for i=1,9 do add('after clear '..i, 1) end
for i=1,600 do add('second '..i, 2) end
assert(model.Count(log, first)==9, 'clear preserves the retention policy')
print('Chatbox retention: independent window budgets, bounded union, shared routes, imports, caches, routing changes and clear passed')
