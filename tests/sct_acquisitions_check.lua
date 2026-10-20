-- Run with: luajit tests/sct_acquisitions_check.lua
package.path = 'addons/sct/?.lua;' .. package.path
local acquisitions = require('acquisitions')
local bags, keys, received = {}, {}, {}
local inventory = {
    GetContainerCountMax = function() return 4 end,
    GetContainerItem = function(_, bag, slot) return bags[bag] and bags[bag][slot] end,
}
local memory = {
    GetInventory = function() return inventory end,
    GetPlayer = function() return { HasKeyItem = function(_, id) return keys[id] == true end } end,
}
local tracker = acquisitions.New(function(id, count, key)
    received[#received + 1] = { id = id, count = count, key = key }
end)
local function put(bag, slot, id, count)
    bags[bag] = bags[bag] or {}
    bags[bag][slot] = count > 0 and { Id = id, Count = count } or nil
end
local function update()
    tracker:Packet(0x020)
    tracker:Update(memory)
end
local function silent(label)
    assert(#received == 0, label)
    print(label .. ': passed')
end
local function gain(id, count, key)
    assert(#received == 1 and received[1].id == id and received[1].count == count and received[1].key == key,
        'incorrect acquisition')
    received = {}
end
local function move(source, slot, count)
    local bytes = { 0, 0, 0, 0 }
    for i = 5, 8 do bytes[i] = count % 256; count = math.floor(count / 256) end
    bytes[9], bytes[10], bytes[11], bytes[12] = source, 0, slot, 0
    tracker:Outgoing(0x029, string.char(unpack(bytes)), memory)
end

put(0, 1, 100, 2)
keys[20] = true
update()
silent('Existing inventory and key items are baseline only')
-- Simulate wardrobe/storage arriving long after the zone settle timer.
put(8, 1, 200, 1); put(2, 1, 300, 12); update()
silent('Late wardrobe and storage contents never notify')
put(0, 1, 100, 5); update(); gain(100, 3, false)
print('Main Inventory stack increase: passed')
-- A transfer received together needs no outgoing packet to identify it.
put(2, 1, 300, 8); put(0, 2, 300, 4); update()
silent('Storage-to-Inventory transfer in one update is silent')
-- Destination arrives first, source update comes a frame later.
move(2, 1, 3)
put(0, 2, 300, 7); update()
silent('Destination-first transfer is silent')
put(2, 1, 300, 5); update()
silent('Later transfer source update is silent')
-- Source arrives first, destination later.
move(2, 1, 2)
put(2, 1, 300, 3); update()
put(0, 2, 300, 9); update()
silent('Source-first transfer is silent')
-- Move-all plus a genuine reward of the same item in the same frame.
move(2, 1, 0)
put(2, 1, 300, 0); put(0, 2, 300, 14); update(); gain(300, 2, false)
print('Transfer and real receipt of the same item: passed')
-- Sorting/merging stacks within the main Inventory is not acquisition.
put(0, 3, 300, 4); put(0, 2, 300, 10); update()
silent('Inventory stack rearrangement is silent')
put(0, 1, 100, 4); update()
silent('Inventory loss is silent')
-- A new zone's bag sync can run past the time-based status settle period.
tracker:Packet(0x00A)
update()
tracker:Packet(0x01D, string.rep('\0', 5))
put(0, 4, 400, 1); update()
silent('Main Inventory refresh while loading is silent')
tracker:Packet(0x01D, string.rep('\0', 4) .. '\1')
tracker:Update(memory)
silent('Completed container sync establishes baseline')
put(0, 4, 400, 2); update(); gain(400, 1, false)
print('Real main Inventory gain after zone sync: passed')
keys[21] = true
tracker:Packet(0x055); tracker:Update(memory); gain(21, 1, true)
tracker:Packet(0x055); tracker:Update(memory)
silent('Key-item refresh does not replay gains')
print('SCT acquisition checks passed')
