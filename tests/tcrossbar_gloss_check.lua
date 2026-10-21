-- tcrossbar's gloss (forks/addons/tcrossbar/gloss.lua): white light over the upper part of an icon,
-- fading down to a curved edge lowest in the middle, a faint black shade at the foot, made once for
-- each size of icon, faded by Gloss Opacity. Run alone: luajit tests/tcrossbar_gloss_check.lua [out.ppm]
local ffi = require('ffi')
ffi.cdef[[
typedef struct { long left, top, right, bottom; } RECT;
typedef struct { float x, y; } D3DXVECTOR2;
typedef struct { int Pitch; void* pBits; } D3DLOCKED_RECT;
enum { S_OK = 0, D3DFMT_A8R8G8B8 = 21, D3DPOOL_MANAGED = 1 };
]]
package.path = 'forks/addons/tcrossbar/?.lua;' .. package.path

local created, buffers = 0, {}
local device = { CreateTexture = function(_, w, h)
    created = created + 1
    local texture = { w = w, h = h, buffer = ffi.new('uint32_t[?]', w * h) }
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

local gloss = require('gloss')
local draws = {}
local sprite = { Draw = function(_, _, rect, _, _, _, position, color) draws[#draws + 1] = { x = position.x, y = position.y, w = tonumber(rect.right), h = tonumber(rect.bottom), alpha = math.floor(color / 0x1000000) } end }
for slot = 1, 16 do gloss.Draw(sprite, slot * 50, 200, 40, 40) end
print('one texture for sixteen icons of a size', created == 1, '| drawn on the icon', draws[1].x == 50 and draws[1].y == 200 and draws[1].w == 40 and draws[1].h == 40)

local t = buffers[1]
local function px(x, y) local p = t.buffer[y * t.w + x]; return math.floor(p / 0x1000000), p % 0x1000000 end
local topA, topC = px(20, 0)
local lowA = px(20, 17)
print('white at the top, near 45%', topC == 0xFFFFFF, topA, '| fading downward', lowA < topA and lowA > 0)
print('the edge lowest in the middle', select(1, px(20, 19)) > 0, select(1, px(2, 19)) == 0)
local footA, footC = px(20, 39)
print('a faint black shade at the foot', footC == 0 and footA > 20 and footA < 50, footA, '| nothing between', select(1, px(20, 25)) == 0)
gloss.Draw(sprite, 0, 0, 60, 60); gloss.Draw(sprite, 0, 0, 40, 40)
print('another size made once', created == 2)

-- Gloss Opacity: the whole texture faded by the draw's alpha; 0 draws nothing
draws = {}; gloss.Draw(sprite, 0, 0, 40, 40, 100); gloss.Draw(sprite, 0, 0, 40, 40, 50); gloss.Draw(sprite, 0, 0, 40, 40)
print('full at 100%, half at 50%, full when unset', draws[1].alpha == 255 and draws[2].alpha == 128 and draws[3].alpha == 255)
draws = {}; gloss.Draw(sprite, 0, 0, 40, 40, 0)
print('nothing at 0%', #draws == 0, '| no new texture for opacity', created == 2)

-- the gloss over mid grey, to look at
if arg[1] then
    local f = io.open(arg[1], 'wb')
    local s = 4
    f:write(('P6 %d %d 255\n'):format(40 * s, 40 * s))
    for y = 0, 40 * s - 1 do for x = 0, 40 * s - 1 do
        local a, c = px(math.floor(x / s), math.floor(y / s)); a = a / 255
        local base = { 60, 90, 160 }
        local out = {}
        for i = 1, 3 do out[i] = math.floor(base[i] * (1 - a) + (c > 0 and 255 or 0) * a + 0.5) end
        f:write(string.char(out[1], out[2], out[3]))
    end end
    f:close()
end
