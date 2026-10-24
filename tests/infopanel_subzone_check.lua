package.path = 'addons/libs/?.lua;' .. package.path
local subzone = require('winxi.infopanel.subzone')
-- A real Zone catalog/geometry/transform lookup, with only client memory stubbed.
ashita = { memory = {
    find = function() return 100 end,
    read_uint32 = function() return 1000 end,
    read_uint16 = function(address) return address == 1000 and 100 or 0 end,
    read_uint8 = function(address) return address == 1005 and 5 or 0 end,
} }
local x, y = 238, -337
GetPlayerEntity = function()
    return { Movement = { LocalPosition = { X = x, Y = y, Z = 0 } } }
end
local read = subzone.New('addons/zone/')
assert(read(100, 0) == nil, 'zone-in settling')
read(100, 1.1)
assert(read(100, 2.2) == 'Knightwell', 'same named boundary as Zone')
x, y = 0, 0
read(100, 3.3)
assert(read(100, 4.4) == nil, 'leaving the area clears its name')
assert(read(999, 5.5) == nil, 'unsupported zone clears its name')
assert(package.loaded.map_catalog == nil and package.loaded['data.all_maps'] == nil,
    'Zone modules stay isolated from the host addon')
print('Info panel sub-zone: Zone boundaries, settling, exits and isolated loading passed')
