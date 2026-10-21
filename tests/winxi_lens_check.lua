-- winxi.lens: the Lua copy of lens's mapping goes back and forth for both modes at every strength,
-- leaves the middle and strength 0 alone, moves a point near the edge outward as the warp does, and
-- leaves points alone without lens or while its warp is not live. Run from the repo root:
-- luajit tests/winxi_lens_check.lua
package.path = 'addons/libs/?.lua;' .. package.path
local loaded, base, address = false, 0, 0
AshitaCore = { GetPluginManager = function () return { IsLoaded = function (_, name) return loaded and name == 'lens' end } end }
ashita = { memory = { get_base = function () return base end, find = function () return address end } }
local ffi = require('ffi')
local lens = require('winxi.lens')

local function check(label, ...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    print(label .. '\t' .. table.concat(parts, ' '))
    for i = 1, select('#', ...) do assert(select(i, ...) ~= false, label) end
end
local function near(a, b, e) return math.abs(a - b) < (e or 1e-6) end

local tanH, tanV = 1 / 0.556459, 1 / 1.260417
local back = true
for _, mode in ipairs({ lens.Panini, lens.Cylindrical }) do
    for _, k in ipairs({ 0, 0.25, 0.5, 0.75 }) do
        for s0 = 0.05, 0.96, 0.15 do for t0 = 0.05, 0.96, 0.15 do
            local s, t = lens.ScreenOf(s0, t0, tanH, tanV, mode, k)
            local us, vs = lens.SourceOf(s, t, tanH, tanV, mode, k)
            back = back and near(us, s0) and near(vs, t0)
        end end
    end
end
check('ScreenOf undoes SourceOf, both modes, every strength', back)
local s, t = lens.ScreenOf(0.3, 0.7, tanH, tanV, lens.Panini, 0)
check('strength 0 leaves a point alone', near(s, 0.3), near(t, 0.7))
s, t = lens.ScreenOf(0.5, 0.5, tanH, tanV, lens.Cylindrical, 0.5)
check('the middle stays', near(s, 0.5), near(t, 0.5))
s, t = lens.ScreenOf(0.95, 0.5, tanH, tanV, lens.Panini, 0.25)
check('near the edge moves outward', s > 0.95, near(t, 0.5))
local cs, ct = lens.SourceOf(0, 0, tanH, tanV, lens.Panini, 1)
check('Panini\'s corner reads the picture\'s corner', near(cs, 0), near(ct, 0))

-- the block: none without lens; with it, live only while the warp ran in the last frame or two
check('no lens, no warp', lens.Current() == nil)
local x, y = lens.Point(nil, 100, 200, 3440, 1440)
check('a point left alone without a warp', x == 100, y == 200)
local blocks = ffi.new('lens_warp_t[1]')
local block = blocks[0]
ffi.copy(block.Magic, 'LENS-WARP')
block.Version, block.Size = 1, ffi.sizeof('lens_warp_t')
block.Frame, block.WarpedFrame, block.Mode, block.Strength, block.TanH, block.TanV = 10, 9, lens.Panini, 0.25, tanH, tanV
loaded, base, address = true, 0x10000000, tonumber(ffi.cast('uintptr_t', blocks))
local warp = lens.Current()
check('lens warping: found', warp ~= nil, warp and warp.mode == lens.Panini, warp and near(warp.strength, 0.25))
x, y = lens.Point(warp, 3440 * 0.95, 720, 3440, 1440)
local ws = lens.ScreenOf(0.95, 0.5, tanH, tanV, lens.Panini, 0.25)
check('a point moved as the warp shows it', near(x, ws * 3440, 1e-3), near(y, 720, 1e-3))
block.Frame = 20
check('not live after a few frames', lens.Current() == nil)
block.WarpedFrame = 19
loaded = false
check('lens unloaded, none', lens.Current() == nil)
print('winxi lens: all checks passed')
