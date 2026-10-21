-- tcrossbar's frame border (forks/addons/tcrossbar/frameborder.lua): winxi.borders' nine slices drawn
-- with sprite draws round a rect, corners 3 pixels and edges stretched, faded by the theme's Border
-- Opacity; 'theme' follows the Window Border, none for the plain one. Run alone: luajit tests/tcrossbar_border_check.lua
local ffi = require('ffi')
ffi.cdef[[
typedef struct { long left, top, right, bottom; } RECT;
typedef struct { float x, y; } D3DXVECTOR2;
typedef struct IDirect3DTexture8 IDirect3DTexture8;
]]
package.path = 'forks/addons/tcrossbar/?.lua;addons/libs/?.lua;' .. package.path

package.preload['d3d8'] = function() return {
    D3DCOLOR_ARGB = function(a, r, g, b) return a * 0x1000000 + r * 0x10000 + g * 0x100 + b end,
} end
local look = { BorderStyle = 'ffxi', BorderOpacity = 100 }
package.preload['winxi.theme'] = function() return {
    Get = function() return look end,
    BorderStyles = { { key = 'theme', label = 'Theme' }, { key = 'silver', label = 'Brushed Silver' }, { key = 'ffxi', label = 'FFXI-inspired' } },
} end
local asked = {}
package.preload['winxi.borders'] = function() return {
    Texture = function(style) asked[#asked + 1] = style; if style == 'theme' then return nil end return style == 'ffxi' and 0x1000 or 0x2000 end,
} end

local frameborder = require('frameborder')
local draws = {}
local sprite = { Draw = function(_, texture, rect, scale, _, _, position, color)
    draws[#draws + 1] = { texture = tonumber(ffi.cast('uintptr_t', texture)), l = tonumber(rect.left), t = tonumber(rect.top), r = tonumber(rect.right), b = tonumber(rect.bottom),
        sx = scale.x, sy = scale.y, x = position.x, y = position.y, color = color }
end }
local function Covers(d) return d.x, d.y, d.x + (d.r - d.l) * d.sx, d.y + (d.b - d.t) * d.sy end

frameborder.Draw(sprite, 'silver', 100, 200, 44, 40)
print('eight slices, no middle', #draws == 8, '| the chosen style', draws[1].texture == 0x2000)
local x1, y1, x2, y2 = Covers(draws[1])
print('top left corner 3px from 8px of the image', x1 == 100 and y1 == 200 and math.abs(x2 - 103) < 1e-4 and math.abs(y2 - 203) < 1e-4, draws[1].r, draws[1].b)
x1, y1, x2, y2 = Covers(draws[2])
print('top edge stretched between the corners', x1 == 103 and math.abs(x2 - 141) < 1e-4 and draws[2].l == 8 and draws[2].r == 56)
x1, y1, x2, y2 = Covers(draws[8])
print('bottom right corner ends at the rect\'s', math.abs(x2 - 144) < 1e-4 and math.abs(y2 - 240) < 1e-4 and draws[8].l == 56 and draws[8].t == 56)
print('opaque white at 100%', draws[1].color == 0xFFFFFFFF)

draws = {}; look.BorderOpacity = 50; frameborder.Draw(sprite, 'theme', 0, 0, 44, 44)
print('Window Border follows the theme\'s', draws[1].texture == 0x1000, '| half faded', math.floor(draws[1].color / 0x1000000) == 128)
draws = {}; look.BorderStyle = 'theme'; frameborder.Draw(sprite, 'theme', 0, 0, 44, 44)
print('none while the theme\'s border is plain', #draws == 0)
draws = {}; frameborder.Draw(sprite, 'none', 0, 0, 44, 44); look.BorderOpacity = 0; frameborder.Draw(sprite, 'silver', 0, 0, 44, 44)
print('none for None, or at 0%', #draws == 0)
local labels = {}; for _, c in ipairs(frameborder.Choices()) do labels[#labels + 1] = c.label end
print('choices: None, Window Border, then the art', table.concat(labels, ', ') == 'None, Window Border, Brushed Silver, FFXI-inspired', frameborder.Label('silver'))
