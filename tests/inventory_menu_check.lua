-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_menu_check.lua
-- The right-click menu, with popups as imgui keeps them: by name and the window they were opened in.
-- The grid is a child window inside the inventory's; a menu opened in one and begun in the other
-- never shows.
local imgui = require('imgui')
local icons = require('winxi.itemicons')
local function check(label, ok)
    H.print(label, ok)
    assert(ok, label)
end
local o = H.options()
icons.Frame = function() return 123 end
icons.Place = function() return { 0, 0, 1, 1 } end

local depth, opened, drawn = 0, {}, {}
local beginChild, endChild = imgui.BeginChild, imgui.EndChild
imgui.BeginChild = function(...) depth = depth + 1; return beginChild(...) end
imgui.EndChild = function(...) depth = depth - 1; return endChild(...) end
imgui.OpenPopup = function(name) opened[name] = depth end
local current = nil
imgui.BeginPopup = function(name)
    if opened[name] ~= depth then return false end
    current = name
    return true
end
imgui.EndPopup = function() current = nil end
imgui.CloseCurrentPopup = function() if current then opened[current] = nil end end
imgui.Selectable = function(label) drawn[#drawn + 1] = label; return false end
imgui.BeginMenu = function(label) drawn[#drawn + 1] = label; return false end
-- the right button alone
local pressed = nil
imgui.IsMouseClicked = function(button) return button == pressed end

-- the grid at 100, 200 with its slots 40 apart: the first item's middle at 116, 216
H.ret.GetCursorScreenPos, H.ret.GetWindowPos, H.ret.GetWindowSize = { 100, 200 }, { 100, 200 }, { 400, 4000 }
H.ret.GetContentRegionAvail = { 1000, 1000 }
H.ret.IsWindowHovered, H.ret.GetMousePos = { true }, { 116, 216 }

H.play(true); H.gil(100)
o.isVisible[1], o.isUnified[1], o.controller[1] = true, true, false
H.bag(0, 30, { { 20001 } }) -- gear in the inventory: Trade, Equip, Move and Drop
H.bag(5, 30, { })
H.packet(0x00A); H.frames(10)

-- the outline of the item under the mouse is drawn with the grid's clip widened by 3 (the grid,
-- here, at 100, 200 and 400 by 4000), so it is not cut off along the grid's edges, and cut to the
-- screen (1920 by 1080, winxi.clip)
local clips = {}
local draw = imgui.GetWindowDrawList()
draw.PushClipRect = function(_, minimum, maximum, intersect) clips[#clips + 1] = { minimum[1], minimum[2], maximum[1], maximum[2], intersect } end
drawn = {}; H.frames(1)
check('no menu until the item is right-clicked', #drawn == 0)
local widened = false
for _, clip in ipairs(clips) do
    widened = widened or (clip[1] == 97 and clip[2] == 197 and clip[3] == 503 and clip[4] == 1080 and clip[5] == false)
end
check('the hovered item\'s outline is clipped to the grid widened by 3, on the screen', widened)
pressed = 1; H.frames(1); pressed = nil
drawn = {}; H.frames(1)
check('right-click opens the item\'s menu', table.concat(drawn, ',') == 'Trade,Equip to Head,Move,Drop,Cancel')
H.ret.GetMousePos = { 900, 900 }
drawn = {}; H.frames(1)
check('the menu stays open as the mouse leaves the item', #drawn > 0)
H.unload()
