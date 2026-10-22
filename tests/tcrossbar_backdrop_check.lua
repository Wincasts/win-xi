-- tcrossbar's backdrop (forks/addons/tcrossbar/backdrop.lua): black behind the panel, darkest in the
-- middle and fading to nothing at its edge, made once, stretched over the panel times Backdrop Size,
-- faded by Backdrop Opacity. Run alone: luajit tests/tcrossbar_backdrop_check.lua
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

local backdrop = require('backdrop')
local draws = {}
local sprite = { Draw = function(_, _, rect, scale, _, _, position, color) draws[#draws + 1] = { x = position.x, y = position.y, w = tonumber(rect.right) * scale.x, h = tonumber(rect.bottom) * scale.y, alpha = math.floor(color / 0x1000000) } end }

backdrop.Draw(sprite, 100, 200, 400, 100, 50, 150)
backdrop.Draw(sprite, 100, 200, 400, 100, 50, 150)
local d = draws[1]
print('made once', created == 1, '| 150% of the panel', d.w == 600 and d.h == 150, '| centred on it', d.x == 0 and d.y == 175)
print('half dark at 50%', d.alpha == 128)

local t = buffers[1]
local function a(x, y) return math.floor(t.buffer[y * t.w + x] / 0x1000000) end
local mid = t.w / 2
print('black, darkest in the middle', t.buffer[mid * t.w + mid] % 0x1000000 == 0 and a(mid, mid) >= 250, a(mid, mid))
print('fading outward', a(mid + 20, mid) < a(mid, mid) and a(mid + 40, mid) < a(mid + 20, mid) and a(mid + 40, mid) > 0)
print('nothing at the edge or corners', a(0, mid) == 0 and a(mid, 0) == 0 and a(0, 0) == 0 and a(t.w - 1, t.h - 1) == 0)
print('round', a(mid + 30, mid) == a(mid, mid + 30) and a(mid - 31, mid) == a(mid + 30, mid))

draws = {}; backdrop.Draw(sprite, 0, 0, 400, 100, 0, 150)
print('nothing at 0%', #draws == 0)
draws = {}; backdrop.Draw(sprite, 0, 0, 400, 100)
print('50% and 130% when unset', draws[1].alpha == 128 and math.abs(draws[1].w - 520) < 0.01, '| still one texture', created == 1)
