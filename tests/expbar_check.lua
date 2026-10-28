package.path = 'addons/expbar/?.lua;' .. package.path
local tracker = require('tracker').New()
local function packet(message, amount, actor)
    local bytes = {}
    for i = 1, 28 do bytes[i] = 0 end
    local function put(at, value, size)
        for i = 1, size do bytes[at + i] = value % 256; value = math.floor(value / 256) end
    end
    put(0x04, actor or 42, 4)
    put(0x10, amount, 4)
    put(0x18, message, 2)
    return string.char(unpack(bytes))
end
assert(not tracker:Packet(0x02D, '', 42, 1, 0))
assert(not tracker:Packet(0x029, packet(8, 100), 42, 1, 0))
assert(not tracker:Packet(0x02D, packet(8, 100, 43), 42, 1, 0))
assert(not tracker:Packet(0x02D, packet(371, 100), 42, 1, 0))
assert(not tracker:Packet(0x02D, packet(8, 0), 42, 1, 0))
assert(tracker:Rate(0) == 0)
assert(tracker:Packet(0x02D, packet(8, 100), 42, 1, 10))
assert(tracker.total == 100 and tracker:Rate(10) == 6000)
assert(tracker:Packet(0x02D, packet(253 + 1024, 200), 42, 1, 70))
assert(tracker.total == 300 and tracker:Rate(70) == 18000)
assert(tracker:Rate(3610) == 300) -- idle time counts; no rolling-window pruning
tracker:Identity(42, 2)
assert(tracker.total == 0 and tracker:Rate(4000) == 0)
tracker:Packet(0x02D, packet(8, 500), 42, 2, 4000)
tracker:Identity(43, 2)
assert(tracker.total == 0)
tracker:Packet(0x02D, packet(8, 500, 43), 43, 2, 5000)
tracker:Reset()
assert(tracker.total == 0 and tracker:Rate(6000) == 0)
print('expbar packet filtering, chains, session rate, idle time, identity and reset: true')
