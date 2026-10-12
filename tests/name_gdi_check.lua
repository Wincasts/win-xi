-- CPU atlas/backend checks; no Windows DLL or Direct3D device is loaded.
package.path = 'addons/name/?.lua;' .. package.path
local ffi = require('ffi')
local image = require('gdi.image')
local atlas = require('gdi.atlas')
local rasterizations, uploads, destroyed = 0, 0, false
local failUpload = false
local commaCaptured = false
local lastFontFlags
package.loaded['gdifonts.include'] = {
    FontFlags = { None = 0, Bold = 1 },
    set_auto_render = function(_, on) assert(on == false) end,
    get_font_available = function(_, family) return family ~= 'Missing' end,
    destroy_interface = function() destroyed = true end,
    create_object = function(_, settings, manual)
        assert(manual and settings.outline_width == 0 and settings.font_color == 0xFFFFFFFF)
        lastFontFlags = settings.font_flags
        local str = ''
        return {
            set_text = function(_, text) str = text end,
            get_texture = function()
                rasterizations = rasterizations + 1
                -- Model the unsafe DLL: low standalone punctuation is not a
                -- valid input. All glyph captures must carry visible sentinels.
                assert(#str >= 2, 'standalone glyph rasterization is unsafe')
                local tex = { w = #str * 6, h = settings.font_height, text = str }
                return tex, { right = tex.w, bottom = tex.h }
            end,
        }
    end,
}
package.loaded.d3d8 = { gc_safe_release = function(tex) return tex end }
atlas.read = function(tex)
    assert(#tex.text == 3 and tex.text:sub(1, 1) == '0' and tex.text:sub(3, 3) == '0')
    if tex.text == '0,0' then commaCaptured = true end
    local img = image.new(tex.w, tex.h)
    for y = 0, tex.h - 1 do
        for x = 0, tex.w - 1 do
            img.px[y * tex.w + x] = (x >= 6 and x < 12) and 0xFF000002 or 0xFF000001
        end
    end
    return img
end
atlas.upload = function(sheet)
    assert(sheet.w > 0 and sheet.h > 0)
    for i = 0, sheet.w * sheet.h - 1 do
        assert(sheet.px[i] ~= 0xFF000001, 'sentinel ink leaked into glyph atlas')
    end
    if failUpload then error('upload failed') end
    uploads = uploads + 1
    return ffi.cast('void*', 0x1000 + uploads)
end
local backend = require('gdi_font')
local first = backend.Prepare('Arial', { 16, 12, 8 })
assert(uploads == 1 and first.address == 0x1001 and commaCaptured)
for _, h in ipairs({ 16, 12, 8 }) do
    local glyphs = first.sets[h].glyphs
    assert(glyphs[32][9] == 6 and glyphs[32][10] == false)
    assert(glyphs[65][9] == 6 and glyphs[65][4] == h and glyphs[65][10])
    assert(glyphs[65][5] >= 0 and glyphs[65][7] <= 1)
end
local reads = rasterizations
assert(backend.Prepare('Arial', { 16, 12, 8 }) == first)
assert(rasterizations == reads and uploads == 1)
assert(not pcall(backend.Prepare, 'Missing', { 16 }))
assert(backend.Prepare('Arial', { 16, 12, 8 }) == first)
failUpload = true
assert(not pcall(backend.Prepare, 'Tahoma', { 16 }))
assert(backend.Prepare('Arial', { 16, 12, 8 }) == first)
failUpload = false
local second = backend.Prepare('Tahoma', { 16, 16 })
assert(uploads == 2 and second.sets[16] and second.address == 0x1002)
local nativeBold = backend.Prepare('Tahoma', { 16, 16 }, true)
assert(nativeBold ~= second and lastFontFlags == 1 and uploads == 3)
reads = rasterizations
assert(backend.Prepare('Tahoma', { 16, 16 }, true) == nativeBold and rasterizations == reads)
local regularAgain = backend.Prepare('Tahoma', { 16, 16 }, false)
assert(regularAgain ~= nativeBold and lastFontFlags == 0 and uploads == 4)
backend.Shutdown()
assert(destroyed)
print('GDI atlas: sentinel captures/cropping, comma safety, metrics, UVs, caching, failed-build safety, native bold caching and cleanup\ttrue')
