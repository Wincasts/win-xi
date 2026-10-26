-- Drawing into the world through namehook 1.46's layers, as winxi.layers gives them: a layer taken (the
-- same again for the same owner, none when all are taken), begun each frame (renewed, its drawings begun
-- afresh), drawings at an entity (offset) and at a point of the world, over everything where asked, quads
-- laid out as names' and stopped at a drawing's 256, textures 0 to 31, a lost layer noticed, released and
-- cleared; none from an older namehook.
package.path = 'addons/libs/?.lua;' .. package.path
local ffi = require('ffi')

local failures = 0
local function check(ok, what) if not ok then failures = failures + 1; print('FAILED: ' .. what) end end

local clock = 0
os.clock = function() clock = clock + 2; return clock end
local addresses = {}
AshitaCore = { GetPluginManager = function() return { IsLoaded = function() return true end } end }
ashita = { memory = { find = function(module, _, magic) return addresses[module .. ':' .. magic] or 0 end } }
package.loaded.imgui = { GetIO = function() return { DisplaySize = { x = 1920, y = 1080 } } end }

local nameplates = require('winxi.nameplates')
nameplates.Module = function() return 1, 0, 0 end
local layers = require('winxi.layers')

pcall(ffi.cdef, 'void* mmap(void*, size_t, int, int, int, long);')
local function low(ctype) return ffi.cast(ctype .. '*', ffi.C.mmap(nil, ffi.sizeof(ctype), 3, 0x62, -1, 0)) end
local function at(p) return tonumber(ffi.cast('uintptr_t', ffi.cast('void*', p))) end

local names = low('namehook_t')
names.Version, names.Size, names.NameSize, names.Hooked, names.Frame = 3, ffi.sizeof('namehook_t'), ffi.sizeof('namehook_name_t'), 1, 70
-- a picture twice the screen's width and as high: drawn X halved, the scale the picture's height over the screen's
names.TargetWidth, names.TargetHeight, names.Width, names.Height = 3840, 1080, 1920, 1080
addresses['namehook.dll:4E414D45484F4F4B0000000000000000'] = at(names)

local owner = nameplates.OwnerOf('markers')
check(layers.Take(owner) == nil and select(2, layers.Take(owner)):find('1.46', 1, true) ~= nil, 'an older namehook: no layer, and it says so')

local block = low('namehook_layers_t')
block.Version, block.Size, block.SlotSize, block.SlotsMax = 1, ffi.sizeof('namehook_layers_t'), ffi.sizeof('namehook_layer_slot_t'), 4
local draws = {}
for i = 0, 3 do draws[i] = low('namehook_layer_draw_t'); draws[i].QuadsMax, draws[i].DrawingsMax = 8192, 512; block.Slots[i].Draw = at(draws[i]) end
addresses['namehook.dll:4E414D45484F4F4B4C41594552530000'] = at(block)

local layer = layers.Take(owner, 5)
check(layer == 1 and block.Slots[0].Owner == owner and block.Slots[0].Order == 5 and block.Slots[0].ClaimFrame == 70, 'a layer taken')
check(layers.Take(owner) == 1, 'the same owner: the same layer')
for _, other in ipairs({ 'b', 'c', 'd' }) do layers.Take(nameplates.OwnerOf(other)) end
check(layers.Take(nameplates.OwnerOf('e')) == nil, 'all taken: none')

names.Frame = 71
local scale = layers.Begin(layer, owner)
check(scale == 1 and block.Slots[0].ClaimFrame == 71 and draws[0].Frame == 71 and draws[0].Count == 0, 'begun: renewed, afresh')
check(draws[0].Reserved == 2 * 65536, 'its X fitted to a picture of another shape, as names')
check(layers.SetTexture(31, 0x7777) and draws[0].Textures[31] == 0x7777 and not layers.SetTexture(32, 1), 'textures 0 to 31')
check(layers.AtEntity(0x401, 0x2000, 0, 0.5, 0, 0.8, 1, 0xFF000000), 'a drawing at an entity')
check(layers.Quad(-10, -5, 10, 5, 0, 0, 1, 1, 0xFFFFFFFF, 31), 'a quad')
layers.End()
local d = draws[0].Drawings[0]
check(d.Flags == 1 and d.EntityIndex == 0x401 and d.ServerId == 0x2000 and d.Y == 0.5 and d.Drawing.Count == 1 and d.Drawing.Alpha > 0.79, 'at the entity, offset')
check(draws[0].Quads[0].X0 == -20 and draws[0].Quads[0].X1 == 20 and draws[0].Quads[0].Texture == 31, 'its quad laid out as a name\'s')
check(layers.AtWorld(1, 2, 3, 1, 0, 0, true), 'a drawing at a point of the world')
for _ = 1, 300 do layers.Quad(0, 0, 1, 1, 0, 0, 1, 1, 0xFFFFFFFF, 0) end
layers.End()
local w = draws[0].Drawings[1]
check(w.Flags == 2 + 4 and w.X == 1 and w.Z == 3 and w.Drawing.First == 1 and w.Drawing.Count == 256, 'at the point, over everything, stopped at 256 quads')
check(draws[0].Count == 2 and draws[0].QuadCount == 257, 'two drawings, their quads')

names.Frame = 72
check(layers.Begin(layer, owner) ~= nil and draws[0].Count == 0 and draws[0].QuadCount == 0, 'the next frame begins afresh')
block.Slots[0].Owner = nameplates.OwnerOf('f')
check(layers.Begin(layer, owner) == nil and not layers.AtWorld(0, 0, 0), 'a layer another has taken is noticed, and nothing drawn into it')
layers.Release(layer, owner)
check(block.Slots[0].Owner == nameplates.OwnerOf('f'), 'nor released from under it')
block.Slots[0].Owner = owner
layers.Begin(layer, owner); layers.SetTexture(0, 0x1111); layers.AtWorld(0, 0, 0); layers.Quad(0, 0, 1, 1, 0, 0, 1, 1, 0xFFFFFFFF, 0); layers.End()
layers.Release(layer, owner)
check(block.Slots[0].Owner == 0 and draws[0].Count == 0 and draws[0].QuadCount == 0 and draws[0].Textures[0] == 0, 'released: free, its drawings cleared')

if failures == 0 then
    print('winxi layers: taken, the same again, none when full, begun afresh each frame, at an entity and at a point, over everything, quads as names\' and stopped at 256, textures 0 to 31, a lost layer noticed, released and cleared, none before namehook 1.46 passed')
else
    os.exit(1)
end
