-- winxi.partystatus against a stand-in for the game's memory: the player's own statuses, and the others'
-- packed two high bits four to a byte, read in one block and a byte at a time alike.
package.path = 'addons/libs/?.lua;' .. package.path

local zoning, icons = 0, { 4, 40, 0, 255, 0x400, 13 }
local player = { GetIsZoning = function() return zoning end, GetStatusIcons = function() return icons end }
local pointerAt = 0x4000
AshitaCore = {
    GetMemoryManager = function() return { GetPlayer = function() return player end } end,
    GetPointerManager = function() return { Get = function(_, name) return name == 'party.statusicons' and pointerAt or 0 end } end,
}

-- the five: the second (server id 0x1401) under 13, 300 and 513; the fourth (0x1402) under nothing
local BASE = 0x5000
local memory = { [0x4000] = BASE }
local function member(place, id, statuses)
    local at = BASE + 0x30 * (place - 1)
    for i = 0, 3 do memory[at + i] = math.floor(id / 256 ^ i) % 256 end
    for slot = 0, 31 do
        local status = statuses[slot + 1] or 255
        memory[at + 16 + slot] = status % 256
        local high = at + 8 + math.floor(slot / 4)
        memory[high] = (memory[high] or 0) + math.floor(status / 256) * 4 ^ (slot % 4)
    end
end
member(2, 0x1401, { 13, 300, 513 })
member(4, 0x1402, {})
ashita = { memory = {
    read_uint32 = function(at) local v = 0; for i = 3, 0, -1 do v = v * 256 + (memory[at + i] or 0) end; return v end,
    read_uint8 = function(at) return memory[at] or 0 end,
} }
local bulk = function(at, count) local bytes = {}; for i = 1, count do bytes[i] = memory[at + i - 1] or 0 end; return bytes end

local partystatus = require('winxi.partystatus')
local function same(list, want)
    if list.count ~= #want or #list ~= #want then return false end
    for i = 1, #want do if list[i] ~= want[i] then return false end end
    return true
end

local own = { 99, 99, 99, 99, 99, 99, 99 }
partystatus.Own(own)
assert(same(own, { 4, 40, 13 }), 'own: empty slots and numbers past ten bits left out, nothing kept from before')
zoning = 1
partystatus.Own(own)
assert(same(own, {}), 'own: none between areas')
zoning = 0

for _, block in ipairs({ bulk, nil, function() error('no block reads') end }) do
    ashita.memory.read_array = block
    local list = { 7, 7, 7, 7, 7 }
    assert(partystatus.Member(0x1401, list) and same(list, { 13, 300, 513 }), 'a member, high bits and all')
    assert(partystatus.Member(0x1402, list) and same(list, {}), 'a member under nothing')
    assert(not partystatus.Member(0x9999, list) and same(list, {}), 'a stranger: none kept')
    assert(not partystatus.Member(0, list), 'an empty place does not match the empty entries')
    local lists = {}
    for i = 1, 5 do lists[i] = { 1 } end
    partystatus.Party(lists)
    assert(lists[1].id == 0 and same(lists[1], {}), 'an empty place')
    assert(lists[2].id == 0x1401 and same(lists[2], { 13, 300, 513 }), 'the second, all at once')
    assert(lists[4].id == 0x1402 and same(lists[4], {}), 'the fourth, under nothing')
end

pointerAt = 0
package.loaded['winxi.partystatus'] = nil
partystatus = require('winxi.partystatus')
ashita.memory.read_uint32 = function(at) assert(at ~= 0, 'null pointer read'); return 0 end
local list = { 1 }
assert(not partystatus.Member(0x1401, list) and same(list, {}), 'no pointer: nothing, and no read of low memory')
print('winxi.partystatus: own, members, whole party, in block and by byte, without a pointer', true)
