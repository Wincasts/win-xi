-- winxi.perf outside the game: the register wrapped, the handlers timed into this state's own rows.
-- luajit tests/winxi_perf_check.lua
package.path = 'addons/libs/?.lua;' .. package.path
local clock, handlers = 0, {}
ashita = { time = { qpf = function() return { q = 1000000 } end, qpc = function() return { q = clock } end },
           events = { register = function(event, _, fn) handlers[event] = handlers[event] or {}; table.insert(handlers[event], fn) end } }
addon = { name = 'checked' }
local perf = require('winxi.perf')
print('active:', perf.Active == true)
print('not shared here:', perf.Shared == false)
ashita.events.register('d3d_present', 'present', function() clock = clock + 1500 end)
ashita.events.register('packet_in', 'packet', function(e) clock = clock + 200; return e end)
ashita.events.register('key', 'key', function() clock = clock + 10 end)
ashita.events.register('load', 'load', function() clock = clock + 5 end)
for _ = 1, 3 do handlers.d3d_present[1]() end
handlers.packet_in[1]({ id = 1 })
handlers.key[1]()
handlers.load[1]()
local rows = perf.Rows()
print('one row, named:', #rows == 1 and rows[1].name == 'checked')
local e = rows[1].events
print('present: 3 calls, 4500 us, longest 1500:', e[1].calls == 3 and e[1].us == 4500 and e[1].maxus == 1500)
print('packet_in once, 200 us:', e[2].calls == 1 and e[2].us == 200)
print('key under input:', e[6].calls == 1 and e[6].us == 10)
print('load under other:', e[7].calls == 1 and e[7].us == 5)
print('touched in seconds:', rows[1].touched == 0)
perf.ResetMax()
print('longest reset, sums kept:', perf.Rows()[1].events[1].maxus == 0 and perf.Rows()[1].events[1].us == 4500)
for _, fn in ipairs(handlers.unload) do fn() end
print('unload clears the row:', #perf.Rows() == 0)
