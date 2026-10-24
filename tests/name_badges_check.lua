package.path = 'addons/name/?.lua;' .. package.path
local ffi = require('ffi')
ffi.cdef('typedef struct IDirect3DTexture8 IDirect3DTexture8;')
local image = require('gdi.image')
local atlas = require('gdi.atlas')
-- This standalone raster/cache test has no Ashita runtime. Diagnostics are tested separately;
-- loading the real module here would pull in imgui and winxi.nameplates unnecessarily.
local diagnosticNotes = {}
package.preload['diag'] = function()
    return { Note = function(format, ...) diagnosticNotes[#diagnosticNotes + 1] = format:format(...) end }
end
local badges = require('letter_badges')
-- A solid glyph has a genuinely transparent centre even after area sampling.
local source = image.new(3, 3):fill(function() return 1 end)
local glyph = { 0, 1, 3, 4, 0, 0, 1, 1, 4, true }
local function alpha(img, x, y) return math.floor(img:get(x, y) / 0x1000000) end
local badge = badges.Raster(source, glyph, 7, false)
assert(badge.w == 5 and badge.h == 5, 'badge must be about a third smaller than the font height')
assert(alpha(badge, 0, 0) < 255, 'rounded corners must soften the fill')
local silhouette = badges.Raster(image.new(3, 3), glyph, 7, false)
assert(alpha(silhouette, 2, 0) == 255, 'straight box edges must remain opaque before adding the filtering guard')
assert(alpha(badge, 2, 2) == 0, 'letter must be truly transparent, not dark text')
assert(badge:get(2, 2) == 0x00FFFFFF, 'transparent pixels remain white to prevent dark filtering fringes')
source:fill(function() return 0.5 end)
badge = badges.Raster(source, glyph, 7, false)
assert(alpha(badge, 2, 2) == 127, 'antialias coverage must be inverted')
source:fill(function() return 1 end)
-- The texture guard must remain transparent WHITE even after atlas extrusion.
local padded = badges.Padded(silhouette)
assert(padded.w == silhouette.w + 2 and padded.h == silhouette.h + 2)
for y = 0, padded.h - 1 do
    for x = 0, padded.w - 1 do
        if x == 0 or y == 0 or x == padded.w - 1 or y == padded.h - 1 then
            assert(padded:get(x, y) == 0x00FFFFFF, 'transparent guard must not introduce a dark fringe')
        else
            assert(padded:get(x, y) == silhouette:get(x - 1, y - 1), 'padding must not alter badge content')
        end
    end
end
local sheet, packed = atlas.pack({ { name = 'badge', img = padded } })
local uv = packed.badge
assert(alpha(sheet, uv.x - 1, uv.y + 3) == 0 and alpha(sheet, uv.x, uv.y + 3) == 0,
    'extrusion must repeat the transparent guard, not the opaque box edge')
assert(alpha(sheet, uv.x + 3, uv.y + 1) == 255,
    'logical straight edge remains opaque just inside the transparent ramp')
local thinSource = image.new(3, 3)
thinSource:set_alpha(1, 1, 1)
local thin = badges.Raster(thinSource, glyph, 7, false)
assert(alpha(thin, 2, 2) > 0 and alpha(thin, 2, 2) < 255,
    'a subpixel cutout is area sampled, rather than becoming a binary hole or disappearing')

local normal = badges.Raster(source, glyph, 20, false)
local bold = badges.Raster(source, glyph, 20, true)
local function cutout(img)
    local amount = 0
    for y = 0, img.h - 1 do for x = 0, img.w - 1 do amount = amount + 255 - alpha(img, x, y) end end
    return amount
end
assert(cutout(bold) > cutout(normal), 'synthetic bold must enlarge the hole, not the fill')

-- A double letter: one wider box, both letters cut out of it, its corners rounded as the square's
local wideSource = image.new(8, 3)
wideSource:set_alpha(1, 1, 1)
wideSource:set_alpha(5, 1, 1)
local firstGlyph = { 0, 1, 3, 4, 0, 0, 3 / 8, 1, 4, true }
local secondGlyph = { 0, 1, 3, 4, 4 / 8, 0, 7 / 8, 1, 4, true }
local square = badges.Raster(wideSource, firstGlyph, 20, false)
local double = badges.Raster(wideSource, { firstGlyph, secondGlyph }, 20, false)
assert(double.h == square.h and double.w == math.floor(square.w * 1.5 + 0.5), 'as tall as the square and half as wide again')
assert(alpha(double, 0, 0) < 255 and alpha(double, double.w - 1, double.h - 1) < 255, 'rounded at both ends')
local middle = math.floor(double.h / 2)
local holes, inside = 0, false
for x = 0, double.w - 1 do
    local open = alpha(double, x, middle) < 255
    if open and not inside then holes = holes + 1 end
    inside = open
end
assert(holes == 2 and alpha(double, math.floor(double.w / 2), middle) == 255, 'two letters, with the box solid between them')
assert(badges.PairAt(0) == 'AA' and badges.PairAt(27) == 'BB' and badges.PairAt(675) == 'ZZ' and badges.PairAt(676) == nil)

local reads, uploads = 0, 0
atlas.read = function() reads = reads + 1; return source end
atlas.upload = function(sheet)
    uploads = uploads + 1
    assert(sheet.w >= 5 and sheet.h >= 5)
    return ffi.cast('IDirect3DTexture8*', 0x5678)
end
package.loaded.d3d8 = { gc_safe_release = function(texture) return texture end }
local releases = 0
atlas.release = function() releases = releases + 1 end
local definitions = { { height = 5, glyphs = { A = glyph }, bold = false } }
-- none, or winxi.fonts' mark for imgui's font texture, is never handed to Direct3D to read
for _ = 1, 3 do
    assert(badges.Prepare(1, definitions, 'selected-font') == nil)
    assert(badges.Prepare(0, definitions, 'selected-font') == nil)
    assert(badges.Prepare(nil, definitions, 'selected-font') == nil)
end
assert(reads == 0, 'a mark or none was read as a texture')
assert(badges.Prepare(0x12340000, definitions, 'selected-font') == nil)
assert(reads == 0, 'must allow ImGui a frame to upload new glyph pixels before reading')
local first = assert(badges.Prepare(0x12340000, definitions, 'selected-font'))
local region = first.regions[5].A
assert(first.address == 0x5678 and region.width == math.floor(5 * badges.Scale + 0.5))
assert(region.uv.w == region.width + 2 * badges.Padding and region.uv.h == region.height + 2 * badges.Padding,
    'texture guard must be separate from logical badge dimensions')
assert(badges.Prepare(0x12340000, definitions, 'selected-font') == first)
assert(reads == 1 and uploads == 1, 'unchanged frames must reuse the texture')
definitions[1].bold = true
assert(badges.Prepare(0x12340000, definitions, 'selected-font') == nil)
assert(badges.Prepare(0x12340000, definitions, 'selected-font') ~= first)
assert(reads == 2 and uploads == 2, 'bold changes must rebuild')
assert(badges.Prepare(0x12340000, definitions, 'different-font') == nil)
assert(badges.Prepare(0x12340000, definitions, 'different-font'))
assert(reads == 3 and uploads == 3, 'font changes must rebuild')
glyph[5] = 0.1
assert(badges.Prepare(0x12340000, definitions, 'different-font') == nil)
assert(badges.Prepare(0x12340000, definitions, 'different-font'))
assert(reads == 4 and uploads == 4, 'atlas repacking must invalidate the UV cache')
local now = 100
os.clock = function() return now end
atlas.read = function() reads = reads + 1; return nil, 'texture not ready' end
assert(badges.Prepare(0x99990000, definitions, 'different-font') == nil)
assert(badges.Prepare(0x99990000, definitions, 'different-font') == nil)
assert(reads == 5, 'startup failures must have bounded retries')
assert(#diagnosticNotes == 1 and diagnosticNotes[1]:find('texture not ready', 1, true),
    'a failed badge build must report its reason once')
now = 102
atlas.read = function() reads = reads + 1; return source end
assert(badges.Prepare(0x99990000, definitions, 'different-font'))
assert(reads == 6 and uploads == 5, 'failed texture creation must recover')
-- Immutable renderer definitions bypass value serialization on unchanged frames.
local fixed = { { height = 5, glyphs = { A = glyph }, bold = true } }
local ready = badges.Prepare(0x99990000, fixed, 'fixed-font', true)
if not ready then ready = assert(badges.Prepare(0x99990000, fixed, 'fixed-font', true)) end
local originalTostring, serialized = tostring, 0
tostring = function(value) serialized = serialized + 1; return originalTostring(value) end
assert(badges.Prepare(0x99990000, fixed, 'fixed-font', true) == ready)
tostring = originalTostring
assert(serialized == 0, 'warm immutable definitions must not rebuild the cache key')
local replacement = { unpack(glyph) }
replacement[1] = replacement[1] + 1
fixed = { { height = 5, glyphs = { A = replacement }, bold = true } }
assert(badges.Prepare(0x99990000, fixed, 'fixed-font', true) == nil)
assert(badges.Prepare(0x99990000, fixed, 'fixed-font', true) ~= ready,
    'replacing immutable definitions after a glyph change must rebuild the atlas')
print('name badges: supersampled cutout, transparent filtering guard/extrusion, bold, compact bounds, cache invalidation, immutable fast path and retry', true)
-- Double letters are made only as far as they are wanted, and made again when more are
local paired = { { height = 5, glyphs = { A = glyph, B = glyph }, bold = false, pairs = 2 } }
if not badges.Prepare(0x99990000, paired, 'paired-font') then assert(badges.Prepare(0x99990000, paired, 'paired-font')) end
local made = badges.Prepare(0x99990000, paired, 'paired-font')
assert(made.regions[5].A and made.regions[5].AA and made.regions[5].AB and made.regions[5].AC == nil)
assert(made.regions[5].AA.uv.w > made.regions[5].A.uv.w and made.regions[5].AA.uv.h == made.regions[5].A.uv.h)
paired[1].pairs = 27
assert(badges.Prepare(0x99990000, paired, 'paired-font') == nil)
local more = assert(badges.Prepare(0x99990000, paired, 'paired-font'))
assert(more ~= made and more.regions[5].BA and more.regions[5].AC == nil, 'a pair with a letter the font lacks is left out')
assert(releases > 0 and made.texture == nil, 'rebuilding promptly releases the replaced GPU atlas')
local released = releases
badges.Release()
assert(releases == released + 1 and more.texture == nil)
badges.Release()
assert(releases == released + 1, 'release must be idempotent')
assert(badges.Prepare(0x99990000, paired, 'paired-font') == nil, 'released atlases prepare fresh on re-enable')

