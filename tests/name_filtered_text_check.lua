-- Exact area filtering, transparent padding and bounded GPU/cache lifecycle.
package.path = 'addons/name/?.lua;' .. package.path
local ffi = require('ffi')
ffi.cdef('typedef struct IDirect3DTexture8 IDirect3DTexture8;')
local image = require('gdi.image')
local atlas = require('gdi.atlas')
local notes = {}
package.preload.diag = function() return { Note = function(fmt, ...) notes[#notes + 1] = fmt:format(...) end } end
local filtered = require('filtered_text')
local function alpha(img, x, y) return math.floor(img:get(x, y) / 0x1000000) end
local glyph = { 0, 0, 2, 2, 0, 0, 1, 1, 3, true }
local source = image.new(8, 8):fill(function(x, y) return (math.floor(x) + math.floor(y)) % 2 end)
local mask, padX, padY = filtered.Raster(source, glyph)
assert(mask.w == 4 and mask.h == 4 and padX == 1 and padY == 1)
for y = 0, mask.h - 1 do
    for x = 0, mask.w - 1 do
        if x == 0 or y == 0 or x == mask.w - 1 or y == mask.h - 1 then
            assert(mask:get(x, y) == 0x00FFFFFF, 'guard must be transparent white')
        else
            assert(alpha(mask, x, y) == 128, 'all 16 source texels must contribute to each output pixel')
        end
    end
end
-- Fractional box overlap: [0, 0, 1, 1] averaged into three pixels gives 0, 1/2, 1.
source = image.new(4, 2):fill(function(x) return x >= 2 and 1 or 0 end)
local fractional = { 0, 0, 3, 1, 0, 0, 1, 1, 4, true }
mask = filtered.Raster(source, fractional)
assert(alpha(mask, 1, 1) == 0 and math.abs(alpha(mask, 2, 1) - 128) <= 1 and alpha(mask, 3, 1) == 255)
local subpixel = { 0.2, 0.3, 2.7, 1.8, 0, 0, 1, 1, 3, true }
mask, padX, padY = filtered.Raster(source, subpixel)
assert(mask.w == 5 and mask.h == 4 and padX == 2.5 / 3 and padY == 1.5 / 2,
    'padding must preserve fractional native bounds, not round layout metrics')
local hidden = { unpack(glyph) }; hidden[10] = false
assert(filtered.Raster(source, hidden) == nil)
local invalid = { unpack(glyph) }; invalid[7] = 2
assert(not pcall(filtered.Raster, source, invalid))

local reads, uploads, uploaded, releases = 0, 0, nil, 0
atlas.release = function() releases = releases + 1 end
atlas.read = function() reads = reads + 1; return source end
atlas.upload = function(sheet)
    uploads = uploads + 1
    uploaded = sheet
    return ffi.cast('IDirect3DTexture8*', 0x5678)
end
package.loaded.d3d8 = { gc_safe_release = function(t) return t end }
local definitions = { { height = 10, glyphs = { [65] = glyph, [32] = hidden } } }
for _, address in ipairs({ 0, 1, 0xFFFF }) do assert(filtered.Prepare(address, definitions) == nil) end
assert(reads == 0, 'font texture marks must never be read as native pointers')
assert(filtered.Prepare(0x12340000, definitions) == nil and reads == 0, 'wait one stable frame before GPU readback')
local ready = assert(filtered.Prepare(0x12340000, definitions))
assert(ready.address == 0x5678 and ready.regions[10][65] and not ready.regions[10][32])
local whiteX = math.floor(ready.white.u * uploaded.w)
local whiteY = math.floor(ready.white.v * uploaded.h)
assert(uploaded:get(whiteX, whiteY) == 0xFFFFFFFF, 'bar tile must be solid white')
local region = ready.regions[10][65].uv
assert(uploaded:get(region.x, region.y) == 0x00FFFFFF
    and uploaded:get(region.x - 1, region.y) == 0x00FFFFFF, 'atlas extrusion preserves the transparent guard')
for _ = 1, 100 do assert(filtered.Prepare(0x12340000, definitions) == ready) end
assert(reads == 1 and uploads == 1, 'warm frames must not rebuild or reread GPU data')
-- Replaced font/UV definitions invalidate; a cache from the old source must not leak.
local replacement = { { height = 10, glyphs = { [65] = glyph } } }
assert(filtered.Prepare(0x12340000, replacement) == nil)
local nextAtlas = assert(filtered.Prepare(0x12340000, replacement))
assert(nextAtlas ~= ready and reads == 2 and uploads == 2 and releases == 1,
    'replaced GPU textures must be released, not left waiting for Lua GC')
local now = 10
os.clock = function() return now end
atlas.read = function() reads = reads + 1; return nil, 'source not uploaded' end
assert(filtered.Prepare(0x99990000, replacement) == nil)
assert(filtered.Prepare(0x99990000, replacement) == nil)
assert(filtered.Prepare(0x99990000, replacement) == nil)
assert(reads == 3 and #notes == 1, 'readback failures have bounded retries and diagnostics')
now = 12
atlas.read = function() reads = reads + 1; return source end
assert(filtered.Prepare(0x99990000, replacement))
assert(reads == 4 and uploads == 3, 'failed builds recover after the retry interval')
assert(releases == 2)
filtered.Release()
assert(releases == 3, 'disabling releases the active atlas')
filtered.Release()
assert(releases == 3, 'release must be idempotent')
assert(filtered.Prepare(0x99990000, replacement) == nil, 'enabling again waits for a fresh build')
print('Filtered text: exact area coverage, fractional bounds, guards, white tile, stable-frame readback, cache and retry passed')
