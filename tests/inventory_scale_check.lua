-- Run with: luajit tests/harness.lua winventory addons/winventory/winventory.lua tests/inventory_scale_check.lua
-- Each window's Scale: the inventory's icons, the room between them and its font; the treasure pool and
-- the Tooltip Window at the inventory's while attached, their own detached; the equipment monitor's
-- words with its slots, and the theme's shadow under it. The Tooltip Window has the item's icon at its left.
local imgui = require('imgui')
local window = require('winxi.window')
local itemicons = require('winxi.itemicons')
local sizing = require('sizing')
local o = H.options()
local function check(label, ok) H.print(label, ok); assert(ok, label) end

-- what each window is given, by name
local given = {}
local full = window.Full
window.Full = function(name, open, flags, draw, style)
    given[name] = { fontSize = style and style.fontSize, shadow = style and style.shadow }
    return full(name, open, flags, draw, style)
end
-- the icons drawn, by their width, and the items whose icons are asked for
local widths, asked = {}, {}
local drawList = imgui.GetWindowDrawList()
rawset(drawList, 'AddImage', function(_, _, a, b) widths[#widths + 1] = b[1] - a[1] end)
local place, sheet = itemicons.Place, itemicons.Frame
itemicons.Frame = function() return 123 end -- a sheet, as the device would make it
itemicons.Place = function(id) asked[id] = true; return { 0, 0, 1, 1 } end
local function Frame()
    for key in pairs(given) do given[key] = nil end
    widths, asked = {}, {}
    H.frames(1)
end
local function Has(list, value) for _, v in ipairs(list) do if v == value then return true end end return false end

H.play(true); H.gil(5000); H.bag(0, 30, { { 1, 5 }, { 20001 }, { 2, 3 } })
-- the windows at the screen's corner, as big as the grid at 2, so its items are in view
H.ret.GetWindowPos, H.ret.GetWindowSize = { 0, 0 }, { 600, 600 }
o.isVisible[1], o.fadeInOut[1], o.controller[1] = true, false, false
o.gridColumns[1] = 6
H.pool(0); H.frames(8)

check('every Scale is 1 to begin with', o.inventoryScale[1] == 1 and o.treasureScale[1] == 1 and o.tooltipScale[1] == 1)
Frame()
check('at 1: the theme\'s own font, 32-pixel icons', given['winxi.inventory'] ~= nil and given['winxi.inventory'].fontSize == nil
    and Has(widths, 32))

o.inventoryScale[1] = 2
Frame()
check('the inventory at 2: twice the font, 64-pixel icons', given['winxi.inventory'].fontSize == sizing.FontSize(2)
    and Has(widths, 64) and not Has(widths, 32))

-- the pool, attached and detached
H.pool(3); o.treasureScale[1] = 1.5
Frame()
check('the pool attached: the inventory\'s Scale', given['winxi.inventory.pool'] ~= nil and given['winxi.inventory.pool'].fontSize == sizing.FontSize(2))
o.treasureDetached[1] = true
Frame()
check('the pool detached: its own', given['winxi.inventory.pool'].fontSize == sizing.FontSize(1.5))
o.treasureDetached[1] = false
H.pool(0)

-- the Tooltip Window: the item's icon at its left, at the window's Scale
o.tooltipWindow[1], o.tooltipScale[1] = true, 0.75
H.ret.IsWindowHovered, H.ret.GetMousePos = { true }, { 15 + 2 * 40 * 2, 25 }
Frame()
local tip = given['winxi.inventory.tooltip']
check('the Tooltip Window attached: the inventory\'s Scale', tip ~= nil and tip.fontSize == sizing.FontSize(2))
local ids = 0
for _ in pairs(asked) do ids = ids + 1 end
check('the hovered item\'s icon in it, as big as the inventory\'s', ids > 0 and Has(widths, 64))
o.tooltipDetached[1] = true
Frame()
check('detached: its own Scale, and its icon with it', given['winxi.inventory.tooltip'].fontSize == sizing.FontSize(0.75) and Has(widths, 24))
local tipwindow = require('tipwindow')
H.ret.IsWindowHovered, H.ret.GetMousePos = { false }, { -1000, -1000 }
widths = {}
tipwindow.Begin(o, false, function() return 7 end)
tipwindow.Offer('Some words')
local before = #widths
tipwindow.Draw()
check('words with no item: no icon', #widths == before)
o.tooltipWindow[1], o.tooltipDetached[1] = false, false

-- the equipment monitor: the theme's shadow under it, and its words at its Scale
o.equipment.enabled[1] = true
H.frames(3)
o.equipment.scale[1] = 1.5
Frame()
local monitor = given['winxi.inventory.equipment']
check('the monitor: the theme\'s shadow, its words at its Scale', monitor ~= nil and monitor.shadow ~= false
    and monitor.fontSize == sizing.FontSize(1.5))

itemicons.Place, itemicons.Frame, window.Full = place, sheet, full
H.print('Scale: passed', true)
