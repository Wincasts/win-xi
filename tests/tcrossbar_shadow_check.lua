-- tcrossbar's frame shadow (forks/addons/tcrossbar/frameshadow.lua): made once for each size of frame
-- and each set of the theme's Shadow settings, as winxi.shadow's layers; none while the theme's shadow
-- is off; tcrossbar's own settings in place of the theme's, with Match Theme Shadow off. Run alone: luajit tests/tcrossbar_shadow_check.lua [out.pgm]
local ffi = require('ffi')
ffi.cdef[[
typedef struct { long left, top, right, bottom; } RECT;
typedef struct { float x, y; } D3DXVECTOR2;
typedef struct { int Pitch; void* pBits; } D3DLOCKED_RECT;
enum { S_OK = 0, D3DFMT_A8R8G8B8 = 21, D3DPOOL_MANAGED = 1 };
]]
package.path = 'forks/addons/tcrossbar/?.lua;addons/libs/?.lua;' .. package.path

local created, buffers = 0, {}
local device = { CreateTexture = function(_, w, h)
    created = created + 1
    local buffer = ffi.new('uint32_t[?]', w * h)
    local texture = { w = w, h = h, buffer = buffer }
    texture.lpVtbl = {
        LockRect = function(t, _, locked) locked[0].Pitch = t.w * 4; locked[0].pBits = t.buffer; return 0 end,
        UnlockRect = function() return 0 end,
    }
    buffers[#buffers + 1] = texture
    return 0, texture
end }
package.preload['d3d8'] = function() return {
    D3DCOLOR_ARGB = function(a, r, g, b) return a * 0x1000000 + r * 0x10000 + g * 0x100 + b end,
    get_device = function() return device end,
    gc_safe_release = function(x) return x end,
} end
local look = { ShadowEnabled = true, ShadowOpacity = 30, ShadowOffset = 2, ShadowBlur = 3 }
package.preload['winxi.theme'] = function() return { Get = function() return look end } end

local frameshadow = require('frameshadow')
local draws = {}
local sprite = { Draw = function(_, texture, rect, scale, _, _, position) draws[#draws + 1] = { texture = texture, x = position.x, y = position.y, w = tonumber(rect.right), h = tonumber(rect.bottom) } end }
local frame = { Rect = ffi.new('RECT', { 0, 0, 44, 44 }), Scale = ffi.new('D3DXVECTOR2', { 1, 1 }) }

for slot = 1, 16 do frameshadow.Draw(sprite, frame, 100 + slot * 50, 200) end
local d = draws[1]
print('one texture for sixteen frames of a size', created == 1, '| sixteen drawn', #draws == 16)
print('drawn round the frame, its padding', d.x < 150 and d.y < 200, 150 - d.x, d.w, d.h)

local t = buffers[1]
local pad = 150 - d.x
local function alpha(x, y) return math.floor(t.buffer[(y + pad) * t.w + (x + pad)] / 0x1000000) end
-- winxi.shadow: three layers of 10% each; where all three cover, 1 - 0.9^3 = 27%
print('under the frame, all layers: 27%', alpha(30, 30), math.floor(0.271 * 255 + 0.5))
print('down and to the right of the frame', alpha(44, 30) > 0, alpha(30, 45) > 0, '| fading outward', alpha(46, 30) < alpha(44, 30))
print('none past the soft edge', alpha(52, 30) == 0, '| none up and left beyond the blur', alpha(-3, 30) == 0)
print('only black', t.buffer[(30 + pad) * t.w + 30 + pad] % 0x1000000 == 0)

-- another size of frame: a texture of its own; the same again: none made
frameshadow.Draw(sprite, { Rect = frame.Rect, Scale = ffi.new('D3DXVECTOR2', { 1.5, 1.5 }) }, 0, 0)
frameshadow.Draw(sprite, frame, 0, 0)
print('a second size made once', created == 2)

-- a change of the theme's settings makes them again; off draws nothing
look.ShadowBlur = 6; frameshadow.Draw(sprite, frame, 0, 0)
print('made again for new settings', created == 3)
local before = #draws
look.ShadowEnabled = false; frameshadow.Draw(sprite, frame, 0, 0)
look.ShadowEnabled, look.ShadowOpacity = true, 0; frameshadow.Draw(sprite, frame, 0, 0)
print('nothing drawn with the shadow off, or at 0%', #draws == before)

-- tcrossbar's own settings: drawn though the theme's shadow is off, made for them, kept within range
look.ShadowEnabled, look.ShadowOpacity = false, 30
before = #draws
local made = created
frameshadow.Draw(sprite, frame, 0, 0, { Opacity = 60, Offset = 4, Blur = 1 })
local own = buffers[#buffers]
local ownPad = -draws[#draws].x
local function ownAlpha(x, y) return math.floor(own.buffer[(y + ownPad) * own.w + (x + ownPad)] / 0x1000000) end
print('own settings drawn with the theme\'s off', #draws == before + 1, created == made + 1, '| one layer of 60%', ownAlpha(30, 30), math.floor(0.6 * 255 + 0.5))
print('own offset: 4px down and right', ownAlpha(46, 30) > 0, ownAlpha(49, 30) == 0)
frameshadow.Draw(sprite, frame, 0, 0, { Opacity = 60, Offset = 4, Blur = 1 })
print('the same own settings made once', created == made + 1)
before = #draws; frameshadow.Draw(sprite, frame, 0, 0, { Opacity = 0, Offset = 4, Blur = 1 })
print('own at 0%: nothing', #draws == before)
frameshadow.Draw(sprite, frame, 0, 0, { Opacity = 500, Offset = 99, Blur = 99 })
print('own kept within range, as the theme\'s', -draws[#draws].x <= 20 + 19 * 20 / 6 + 2)

-- the image, to look at
if arg[1] then
    local f = io.open(arg[1], 'wb')
    f:write(('P5 %d %d 255\n'):format(d.w, d.h))
    for y = 0, d.h - 1 do for x = 0, d.w - 1 do f:write(string.char(255 - math.floor(t.buffer[y * t.w + x] / 0x1000000))) end end
    f:close()
end
