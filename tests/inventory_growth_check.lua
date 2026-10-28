-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_growth_check.lua
local imgui = require('imgui')
local function check(text, condition)
    H.print(text, condition)
    assert(condition, text)
end
H.play(true)
local o = H.options()
o.isVisible[1], o.fadeInOut[1], o.controller[1] = true, false, false
o.treasurePool[1], o.equipment.enabled[1] = false, false
local moves = 0
imgui.SetWindowPos = function(first, second)
    local p = type(first) == 'table' and first or second
    H.ret.GetWindowPos = { p[1], p[2] }
    moves = moves + 1
end
local function rectangle(x, y, w, h)
    H.ret.GetWindowPos, H.ret.GetWindowSize = { x, y }, { w, h }
end
local function at(x, y)
    return o.pos[1] == x and o.pos[2] == y
end
check('existing characters default to Top Left', o.growthAnchor == 'TopLeft')
for _, mode in ipairs({ 'TopLeft', 'TopRight', 'BottomLeft', 'BottomRight' }) do
    o.lockMovement[1] = false
    rectangle(500, 500, 300, 150)
    H.frames(1)
    o.growthAnchor, o.lockMovement[1] = mode, true
    H.frames(1)
    check(mode .. ': locking does not move the window', at(500, 500))
    H.ret.GetWindowSize = { 400, 250 }
    H.frames(1)
    local x = (mode == 'TopRight' or mode == 'BottomRight') and 400 or 500
    local y = (mode == 'BottomLeft' or mode == 'BottomRight') and 400 or 500
    check(mode .. ': chosen corner stays fixed when growing', at(x, y))
    local before = moves
    H.frames(3)
    check(mode .. ': stable size does not drift', at(x, y) and moves == before)
    H.ret.GetWindowSize = { 300, 150 }
    H.frames(1)
    check(mode .. ': chosen corner stays fixed when shrinking', at(500, 500))
end
o.lockMovement[1] = false
H.frames(1)
H.ret.GetWindowSize = { 400, 250 }
H.frames(1)
check('unlocked windows retain normal top-left growth', at(500, 500))
o.lockMovement[1], o.growthAnchor = true, 'BottomLeft'
H.frames(1)
o.growthAnchor = 'BottomRight'
H.frames(1)
check('changing the anchor does not move the window', at(500, 500))
rectangle(700, 600, 400, 250)
H.frames(1)
check('Position can move a locked window', at(700, 600))
H.ret.GetWindowSize = { 450, 300 }
H.frames(1)
check('growth uses the new Position', at(650, 550))
H.unload()
