-- tcrossbar's cooldown swipe and cost tints (forks/addons/tcrossbar/cooldown.lua, element.lua): the
-- wedge from 12 o'clock shrinking clockwise, made once a step for each size, faded by Swipe Opacity;
-- a tint in its colour over the whole icon; each recast's length tracked, run down between ticks.
-- Run alone: luajit tests/tcrossbar_cooldown_check.lua [out.ppm]
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

local cooldown = require('cooldown')
local draws = {}
local sprite = { Draw = function(_, texture, rect, scale, _, _, position, color)
    draws[#draws + 1] = { texture = texture, x = position.x, y = position.y, w = tonumber(rect.right), h = tonumber(rect.bottom), sx = scale.x, sy = scale.y, color = color }
end }
local function A(color) return math.floor(color / 0x1000000) end

-- the wedge: what is left, from 1 - left of the turn round to 12 o'clock
print('a quarter left: the top left quarter dark, the rest clear', cooldown.Covered(10, 5, 40, 40, 0.25), not cooldown.Covered(30, 5, 40, 40, 0.25),
    not cooldown.Covered(30, 35, 40, 40, 0.25), not cooldown.Covered(10, 35, 40, 40, 0.25))
print('three quarters left: all but the top right', not cooldown.Covered(30, 5, 40, 40, 0.75), cooldown.Covered(30, 35, 40, 40, 0.75), cooldown.Covered(10, 5, 40, 40, 0.75))
print('steps: none at 0, all at 1, at least one just begun', cooldown.Step(0) == 0, cooldown.Step(1) == 60, cooldown.Step(0.001) == 1, cooldown.Step(0.5) == 30)

cooldown.DrawSwipe(sprite, 100, 200, 40, 40, 0.25, 60)
local d = draws[1]
print('drawn on the icon at 60%', d.x == 100 and d.y == 200 and d.w == 40 and d.h == 40, A(d.color) == 153)
local t = buffers[1]
local function px(x, y) return t.buffer[y * t.w + x] end
print('black, dark top left, clear top right and below', px(10, 5) == 255 * 0x1000000, px(30, 5) == 0, px(30, 35) == 0, px(10, 35) == 0)
for _ = 1, 10 do cooldown.DrawSwipe(sprite, 0, 0, 40, 40, 0.25, 60) end
cooldown.DrawSwipe(sprite, 0, 0, 40, 40, 0.249, 60)
print('a step made once', created == 1)
cooldown.DrawSwipe(sprite, 0, 0, 40, 40, 0.4, 60); cooldown.DrawSwipe(sprite, 0, 0, 60, 60, 0.25, 60)
print('another step, another size: one each', created == 3)
local soft = false
for i = 0, 39 * 64 + 39 do local a = A(buffers[2].buffer[i]); if a > 0 and a < 255 then soft = true end end
print('0.4 left: a soft edge where the wedge is cut across pixels', soft)
local before = #draws
cooldown.DrawSwipe(sprite, 0, 0, 40, 40, 0, 60); cooldown.DrawSwipe(sprite, 0, 0, 40, 40, 0.5, 0)
print('nothing when ready, or at 0%', #draws == before)

-- the tints: one white texture, scaled to the icon, drawn in the colour
cooldown.DrawTint(sprite, 50, 60, 40, 40, { 0.2, 0.4, 1.0, 0.45 })
d = draws[#draws]
print('a tint over the icon', d.x == 50 and d.y == 60 and d.w * d.sx == 40 and d.h * d.sy == 40,
    d.color == 115 * 0x1000000 + 51 * 0x10000 + 102 * 0x100 + 255)
cooldown.DrawTint(sprite, 0, 0, 30, 30, { 1, 0.45, 0.1, 0.4 })
print('one white texture for every tint', created == 4, buffers[4].buffer[0] == 0xFFFFFFFF)
before = #draws; cooldown.DrawTint(sprite, 0, 0, 30, 30, { 1, 1, 1, 0 }); cooldown.DrawTint(sprite, 0, 0, 30, 30, nil)
print('none at alpha 0, or with no colour', #draws == before)

-- element.lua's recast tracking, with stand-ins for what it loads
T = T or function(t) return t end
for _, name in ipairs({ 'gdifonts.encoding', 'gdifonts.include', 'frameborder', 'frameshadow', 'gloss', 'recasttext' }) do
    package.preload[name] = function() return {} end
end
for _, name in ipairs({ 'ability', 'command', 'empty', 'item', 'spell', 'trust', 'weaponskill' }) do
    package.preload['updaters.' .. name] = function() return {} end
end
local Element = require('element')
local e = setmetatable({ State = { RecastLeft = 0 }, SwipeLeft = 0 }, { __index = Element })
e.State.RecastLeft = 30; e:TrackRecast(10)
print('a recast begun: all of it left', e:SwipeFraction(10) == 1, '| run down between ticks', math.abs(e:SwipeFraction(17.5) - 0.75) < 1e-9)
e.State.RecastLeft = 15; e:TrackRecast(25)
print('half way: half left', e:SwipeFraction(25) == 0.5)
e.State.RecastLeft = 0; e:TrackRecast(40)
print('ready: none, and the length forgotten', e:SwipeFraction(40) == 0, e.SwipeLength == nil)
e.State.RecastLeft = 20; e:TrackRecast(50)
print('the next recast its own length', e.SwipeLength == 20)
e.State.RecastLeft, e.State.RecastLength = 10, 40; e:TrackRecast(60)
print('a charge: the length the updater gives', e:SwipeFraction(60) == 0.25)
print('never past either end', e:SwipeFraction(1000) == 0, e:SwipeFraction(0) == 1)

-- A cooldown which starts while no bar is rendered retains its original length on reveal.
local ticks, timer = 0, 0
local hidden = setmetatable({ State = {}, SwipeLeft = 0 }, { __index = Element })
hidden.Updater = { Tick = function()
    ticks = ticks + 1
    hidden.State.RecastLeft = timer
end }
hidden:Tick(0)
timer = 60; hidden:Tick(1)
timer = 15; hidden:Tick(46)
assert(hidden.SwipeLength == 60 and hidden:SwipeFraction(46) == 0.25,
    'revealing a hidden bar must not restart the swipe from full')
hidden:Tick(46.01)
assert(ticks == 3, 'background and render ticks must share the throttle')
timer = 0; hidden:Tick(61)
timer = 20; hidden:Tick(62)
assert(hidden.SwipeLength == 20, 'a cooldown completed while hidden must reset its length')

-- Both displays tick every slot without calling Render, including inactive trigger groups.
package.preload['backdrop'] = function() return {} end
local SingleDisplay = require('singledisplay')
local DoubleDisplay = require('doubledisplay')
local seen = {}
local function slot(id)
    return { Tick = function(_, now) seen[id] = now end }
end
local single = setmetatable({ Valid = true, ElementGroups = {
    { slot('LT') }, { slot('RT') }, { slot('LTRT') },
} }, { __index = SingleDisplay })
local double = setmetatable({ Valid = true, Elements = { slot('left'), slot('right') } },
    { __index = DoubleDisplay })
single:Tick(100); double:Tick(100)
for _, id in ipairs({ 'LT', 'RT', 'LTRT', 'left', 'right' }) do
    assert(seen[id] == 100, 'hidden slot not sampled: ' .. id)
end
print('hidden cooldown tracking and all display groups: passed')

-- a wedge, to look at
if arg[1] then
    cooldown.DrawSwipe(sprite, 0, 0, 40, 40, 0.6, 100)
    local w = buffers[#buffers]
    local f = io.open(arg[1], 'wb')
    local s = 4
    f:write(('P6 %d %d 255\n'):format(40 * s, 40 * s))
    for y = 0, 40 * s - 1 do for x = 0, 40 * s - 1 do
        local a = A(w.buffer[math.floor(y / s) * w.w + math.floor(x / s)]) / 255 * 0.6
        f:write(string.char(math.floor(200 * (1 - a)), math.floor(150 * (1 - a)), math.floor(60 * (1 - a))))
    end end
    f:close()
end
