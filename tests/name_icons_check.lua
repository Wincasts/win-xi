-- Run with luajit tests/name_icons_check.lua; no game or Direct3D device needed.
package.path = 'addons/name/?.lua;' .. package.path
-- Any attempt to use the old resource discovery/loading path fails this check.
ashita = { memory = setmetatable({}, { __index = function() error('player icons must not read game memory') end }) }
package.preload.d3d8 = function() error('icons must use the shared sheet loader') end
local icons = require('icons')
local texture, calls = 0, 0
local function sheet(file)
    assert(file == 'player-icons.png')
    calls = calls + 1
    return texture
end
assert(not icons.Begin(sheet))
assert(icons.Texture() == nil and not (icons.Place(0x92) ~= false))
texture = 0x1234
assert(icons.Begin(sheet))
assert(icons.Texture() == texture and (icons.Place(0x92) ~= false))
local pearl, star = icons.Place(0x92), icons.Place(0xAD)
assert(pearl[1] == 0 and pearl[2] == 0.25 and pearl[3] == 0.125 and pearl[4] == 0.375)
assert(star[1] == 0.75 and star[2] == 0.25 and star[3] == 0.875 and star[4] == 0.375)
assert((icons.Place(0xAC) ~= false) and (icons.Place(0xAD) ~= false), 'composite status base and standalone star remain mapped')
local badge = icons.Overlays(0xAC)[1]
assert(badge[1] == -1/16 and badge[2] == -1/16 and badge[3]-badge[1] == 0.5 and badge[4]-badge[2] == 0.5)
assert(not icons.Overlays(0x91) and not icons.Overlays(0xAD), 'ordinary seeking-party and mastery stars have no extra layer')
assert(not (icons.Place(0x20) ~= false) and not (icons.Place(0xFF) ~= false))
local count = 0
for byte = 0x8E, 0xB1 do
    local at = icons.Place(byte)
    assert(at and at[1] >= 0 and at[2] >= 0 and at[3] <= 1 and at[4] <= 1)
    assert(at[1] < at[3] and at[2] < at[4])
    count = count + 1
end
assert(count == 36)
texture = 0
assert(not icons.Begin(sheet) and not (icons.Place(0x92) ~= false))
texture = 0x5678
assert(icons.Begin(sheet) and icons.Texture() == texture)
assert(calls == 4)
print('name icons: bundled atlas, fixed UVs, stars, two-part mapping and load recovery; no game memory\ttrue')
