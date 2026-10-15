-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_grid_check.lua
local function check(label, ok)
    H.print(label, ok)
    assert(ok, label)
end
local o = H.options()
local imgui = require('imgui')
local tabs = require('winxi.tabs')
local beginChild, beginTab = imgui.BeginChild, tabs.Begin
local constraints, dummy = imgui.SetNextWindowSizeConstraints, imgui.Dummy
local bounds, spots = nil, {}
local contentWidth, scrollbarWidth = 232, 0
local contentAvailable = imgui.GetContentRegionAvail
imgui.GetContentRegionAvail = function()
    if debug.getinfo(2, 'n').name == 'BeginTab' then return contentWidth, 1000 end
    return contentAvailable()
end
local cursorX, countX = imgui.SetCursorPosX, nil
imgui.SetCursorPosX = function(x)
    if debug.getinfo(2, 'n').name == 'DrawCountsRow' then countX = x end
    return cursorX(x)
end
imgui.SetNextWindowSizeConstraints = function(minimum, maximum)
    bounds = { minimum[2], maximum[2] }
    return constraints(minimum, maximum)
end
imgui.Dummy = function(size)
    spots[#spots + 1] = { size[1], size[2] }
    return dummy(size)
end
local children, labels, selected = {}, {}, nil
local slotRects = {}
local drawList = imgui.GetWindowDrawList()
local rect = drawList.AddRectFilled
function drawList:AddRectFilled(minimum, maximum, ...)
    if math.abs(maximum[1] - minimum[1] - 32) < 0.001 and maximum[2] - minimum[2] == 32 then
        slotRects[#slotRects + 1] = { minimum[1], minimum[2] }
    end
    return rect(self, minimum, maximum, ...)
end
imgui.BeginChild = function(id, size, childFlags, windowFlags)
    assert(type(childFlags) == 'number' and type(windowFlags) == 'number',
        'BeginChild requires numeric child and window flags in the current ImGui binding')
    assert(childFlags == ImGuiChildFlags_AutoResizeY, 'grid should collapse to its contents')
    assert(windowFlags == ImGuiWindowFlags_NoBackground,
        'grid should be transparent without forcing a scrollbar')
    contentWidth = size[1] - scrollbarWidth
    children[#children + 1] = { id, size[1], bounds[2], bounds[1] }
    return beginChild(id, size, childFlags, windowFlags)
end
tabs.Begin = function(label, flags)
    labels[#labels + 1] = label:match('^[^#]+')
    if flags == ImGuiTabItemFlags_SetSelected then selected = label:match('^[^#]+') end
    return beginTab(label, flags)
end
local function frame()
    children, labels, selected, spots, slotRects = {}, {}, nil, {}, {}
    H.frames(1)
end
H.play(true)
H.gil(5000)
o.isVisible[1], o.fadeInOut[1], o.treasurePool[1], o.controller[1] = true, false, false, false
o.showEmptySlots[1] = false
H.bag(0, 80, { { 1 }, { 2 }, { 3 } })
o.gridRows[1], o.gridColumns[1] = 5, 6
frame()
check('four tabs enabled by default', table.concat(labels, ',') == 'bag,satchel,ward,house')
check('grid viewport follows rows and columns', #children == 1 and children[1][2] == 232 and children[1][3] == 176)
o.maxHeight[1] = 100
frame()
check('legacy max height no longer limits the grid', children[1][3] == 176)
o.gridRows[1], o.gridColumns[1] = 0, 100
frame()
check('out-of-range settings clamped', children[1][2] == 1192 and children[1][3] == 176)
o.gridRows[1], o.gridColumns[1] = 0, 0
frame()
check('minimum columns and rows enforced in saved settings', o.gridColumns[1] == 6 and o.gridRows[1] == 5)
for _, unified in ipairs({ true, false }) do
    o.isUnified[1] = unified
    o.bagTabs.satchel[1], o.bagTabs.wardrobe[1] = false, false
    frame()
    check('hidden groups omitted (' .. tostring(unified) .. ')', table.concat(labels, ',') == 'bag,house')
    check('same viewport in both bag layouts', #children == 1 and children[1][3] == 176)
end

o.controller[1] = true
frame()
H.tap(H.Button.RB)
check('controller next skips disabled groups', selected == 'house')
-- The harness chooses tabs by ordinal; make House the showing tab.
H.tab(2); frame()
H.tap(H.Button.RB)
check('controller wraps to enabled bag', selected == 'bag')
H.tab(1); frame()
H.tap(H.Button.LB)
check('controller previous skips disabled groups', selected == 'house')

o.controller[1] = false
o.bagTabs.bag[1] = false
frame()
check('hiding active tab selects an enabled replacement', selected == 'house')
o.bagTabs.house[1] = false
frame()
check('all tabs can be hidden safely', #labels == 0 and #children == 0)
o.bagTabs.bag[1] = true
frame()
check('a hidden tab can be restored', #labels == 1 and labels[1] == 'bag' and #children == 1)
o.isUnified[1] = true
frame()
check('closed settings allow grid to collapse', children[1][4] == 1)
local function hasGrid(width, height)
    for _, spot in ipairs(spots) do
        if math.abs(spot[1] - width) < 0.001 and spot[2] == height then return true end
    end
    return false
end
check('closed settings only reserve actual items', hasGrid(112, 32))
H.ret.GetWindowPos, H.ret.GetWindowSize = { 0, 0 }, { 1000, 1000 }
H.command('/inv config'); frame()
check('settings preview reserves chosen rows', children[1][4] == children[1][3])
check('settings preview draws all chosen slots', hasGrid(232, 176))
-- a square for every slot, the three items' first: the sixth ends the first row, the seventh wraps
check('six-column preview fills final column then wraps', #slotRects == 30
    and slotRects[6][1] == 210 and slotRects[6][2] == 20
    and slotRects[7][1] == 10 and slotRects[7][2] == 56)
o.gridRows[1], o.gridColumns[1] = 7, 8
frame()
check('increasing dimensions expands preview', hasGrid(312, 248)
    and children[1][2] == 312 and children[1][3] == 248)
check('eight-column preview fills eighth column then wraps', #slotRects == 56
    and slotRects[8][1] == 290 and slotRects[8][2] == 20
    and slotRects[9][1] == 10 and slotRects[9][2] == 56)
o.gridRows[1], o.gridColumns[1] = 5, 6
H.ret.GetContentRegionAvail = { 5000, 1000 } -- simulate a previously much wider window
frame()
check('decreasing dimensions shrinks preview', hasGrid(232, 176)
    and children[1][2] == 232 and children[1][3] == 176)
check('footer does not hold window at previous width', countX == 230)
scrollbarWidth = 14 -- emulate ImGui subtracting a visible scrollbar from content width
frame()
check('scrollbar does not enlarge the window', children[1][2] == 232)
check('scrollbar tightens gaps while retaining six full-sized columns', hasGrid(218, 176)
    and math.abs(slotRects[6][1] - 196) < 0.001
    and slotRects[6][2] == 20 and slotRects[7][1] == 10 and slotRects[7][2] == 56)
scrollbarWidth = 0
frame()
check('normal spacing restored when scrollbar disappears', hasGrid(232, 176)
    and slotRects[6][1] == 210)
H.command('/inv config'); frame()
check('closing settings removes preview slots', hasGrid(112, 32) and children[1][4] == 1)
check('full slots keep their square behind the icon', #slotRects == 3
    and slotRects[1][1] == 10 and slotRects[3][1] == 90)

local window = require('winxi.window')
local full, flags = window.Full, nil
window.Full = function(name, wanted, windowFlags, ...)
    if name == 'winxi.inventory' then flags = windowFlags end
    return full(name, wanted, windowFlags, ...)
end
check('drag movement unlocked by default', o.lockMovement[1] == false)
frame()
local unlocked = flags
o.lockMovement[1] = true
frame()
check('lock adds NoMove to inventory window', flags == require('bit').bor(unlocked, ImGuiWindowFlags_NoMove))
o.lockMovement[1] = false
frame()
check('unlock restores original window flags', flags == unlocked)
H.unload()
