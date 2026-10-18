-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_scrollbar_check.lua
-- The grid's slim scroll bar is dragged with the mouse, anywhere in the strip from the grid's right
-- edge to the window's, and a press there does not move the window.
local imgui = require('imgui')
local window = require('winxi.window')
local function check(label, ok)
    H.print(label, ok)
    assert(ok, label)
end
local o = H.options()
-- the grid at 100, 200, 232 by 400; the window around it at 90, 180, 252 by 600: the strip is 332..342
local depth = 0
local beginChild, endChild = imgui.BeginChild, imgui.EndChild
imgui.BeginChild = function(...) depth = depth + 1 return beginChild(...) end
imgui.EndChild = function(...) depth = depth - 1 return endChild(...) end
imgui.GetWindowPos = function() if depth > 0 then return 100, 200 end return 90, 180 end
imgui.GetWindowSize = function() if depth > 0 then return 232, 400 end return 252, 600 end
local scrolledTo = nil
imgui.SetScrollY = function(y) scrolledTo = y end
local full, flags = window.Full, 0
window.Full = function(name, wanted, windowFlags, draw, style, ...)
    -- Lock is winxi.window's locked option: counted with the flags, as the window has it
    if name == 'winxi.inventory' then flags = require('bit').bor(windowFlags, style and style.locked and ImGuiWindowFlags_NoMove or 0) end
    return full(name, wanted, windowFlags, draw, style, ...)
end
local pressed = false
imgui.IsMouseClicked = function(button) return button == 0 and pressed end
H.ret.IsWindowHovered = { true }
local function mouse(x, y, down, press)
    H.ret.GetMousePos, H.ret.IsMouseDown = { x, y }, { down }
    pressed, scrolledTo = press or false, nil
    H.frames(1)
    pressed = false
end
-- the harness numbers imgui's flags one after another, so NoMove is told by what it adds
local unlocked
local function still() return flags == bit.bor(unlocked, ImGuiWindowFlags_NoMove) end

H.play(true); H.gil(100)
o.isVisible[1], o.controller[1], o.lockMovement[1] = true, false, false
H.bag(0, 80, { { 1 }, { 2 }, { 3 } })
H.packet(0x00A); H.frames(10)
unlocked = flags

mouse(337, 300, false); mouse(337, 300, false)
check('a grid that does not scroll: the strip is the window\'s, to move it by', not still())
mouse(337, 300, true, true); mouse(337, 400, true)
check('and a press there scrolls nothing', scrolledTo == nil)
mouse(337, 400, false)

-- 400 more pixels than the 400 shown: the bar is 200 long, at the top
H.ret.GetScrollMaxY, H.ret.GetScrollY = { 400 }, { 0 }
mouse(200, 300, false); mouse(200, 300, false)
check('unlocked, the mouse off the strip: the window moves as it did', not still())
mouse(337, 300, false); mouse(337, 300, false)
check('the mouse over the strip: the window is held still', still())

mouse(337, 300, true, true)
mouse(337, 400, true)
check('the bar, taken 100 down, follows the mouse: half way down', scrolledTo == 200 and still())
mouse(337, 900, true)
check('dragged past the foot: no further than the grid scrolls', scrolledTo == 400)
mouse(337, 900, false)
mouse(337, 450, true)
check('let go: the bar is no longer held', scrolledTo == nil)
mouse(337, 450, false)

mouse(341, 550, true, true)
mouse(341, 550, true)
check('a press below the bar, at the window\'s edge: its middle comes to the mouse', scrolledTo == 400)
mouse(341, 350, true)
check('and it is held from there', scrolledTo == 100)
mouse(341, 350, false)

mouse(320, 300, true, true); mouse(320, 400, true)
check('a press on the grid is not the bar\'s', scrolledTo == nil)
mouse(320, 400, false)
mouse(343, 300, true, true); mouse(343, 400, true)
check('nor past the window\'s edge', scrolledTo == nil)
mouse(343, 400, false)
H.ret.IsWindowHovered = { false }
mouse(337, 300, true, true); mouse(337, 400, true)
check('nor where another window covers it', scrolledTo == nil)
H.unload()
