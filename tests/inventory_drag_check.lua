-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_drag_check.lua
-- While Lock Drag to Move holds the window still, items are dragged with the mouse: onto another item
-- to swap their places, or onto another tab's name to move them to that tab's bags.
local imgui = require('imgui')
local icons = require('winxi.itemicons')
local function check(label, ok)
    H.print(label, ok)
    assert(ok, label)
end
local o = H.options()
local placed = {}
icons.Frame = function() return 123 end
icons.Place = function(id) placed[#placed + 1] = id; return { 0, 0, 1, 1 } end
-- the grid at 100, 200, its slots 40 apart: the first item's middle at 116, 216, the third's at 196, 216.
-- Every tab's name is at 10..60 across, 20..38 down (the harness has one place for every item drawn).
H.ret.GetCursorScreenPos, H.ret.GetWindowPos, H.ret.GetWindowSize = { 100, 200 }, { 100, 200 }, { 400, 4000 }
H.ret.GetContentRegionAvail = { 1000, 1000 }
H.ret.IsWindowHovered = { true }
-- the left button alone: pressed this frame, and held
local pressed = false
imgui.IsMouseClicked = function(button) return button == 0 and pressed end
local function mouse(x, y, down, press)
    H.ret.GetMousePos, H.ret.IsMouseDown = { x, y }, { down }
    pressed = press or false
    H.frames(1)
    pressed = false
end
local function drag(fromX, fromY, toX, toY)
    mouse(fromX, fromY, true, true)
    mouse((fromX + toX) / 2, (fromY + toY) / 2, true)
    mouse(toX, toY, true)
    mouse(toX, toY, false)
end
local function order()
    placed = {}; H.ret.GetMousePos = { 0, 0 }; H.frames(1)
    return table.concat(placed, ',')
end
local function moves()
    local n = 0
    for _, s in ipairs(H.sent) do if s:find('^29:') then n = n + 1 end end
    return n
end

H.play(true); H.gil(100)
o.isVisible[1], o.isUnified[1], o.controller[1] = true, true, false
H.bag(0, 30, { { 1 }, { 2 }, { 3 } })
H.bag(5, 30, { })
H.bag(8, 30, { })
H.packet(0x00A); H.frames(10)
check('the bag in its usual order', order() == '1,2,3')

o.lockMovement[1] = false
drag(116, 216, 196, 216)
check('unlocked: a drag moves the window, not the item', order() == '1,2,3' and (o.manualOrder == nil or o.manualOrder.bag == nil))

o.lockMovement[1] = true
mouse(116, 216, true, true); mouse(116, 216, false)
check('locked: a click on an item is not a drag', order() == '1,2,3' and (o.manualOrder == nil or o.manualOrder.bag == nil))

drag(116, 216, 196, 216)
check('locked: dropped on another item, the two swap places', order() == '3,2,1')

drag(116, 216, 116, 216 + 40 * 3)
check('dropped where there is no item and no tab: nothing changes', order() == '3,2,1')

local sent = moves()
drag(116, 216, 30, 25)
check('dropped on another tab\'s name: moved to that tab\'s bag', moves() == sent + 1)

H.bag(5, 1, { { 9 } }); H.packet(0x01C); H.frames(10)
o.bagTabs.satchel[1] = false -- the next tab's name is the wardrobe's: no room for anything but gear
sent = moves()
local said = #H.printed
drag(116, 216, 30, 25)
check('a tab that cannot take it: nothing moved, and said so', moves() == sent
    and #H.printed > said and H.printed[#H.printed]:find('No room for', 1, true) ~= nil)
H.unload()
