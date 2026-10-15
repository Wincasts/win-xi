-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_settings_check.lua
local widgets = require('winxi.widgets')
local imgui = require('imgui')
local header, label, beginTab = widgets.Header, widgets.Label, imgui.BeginTabItem
local headers, labels, tabs = {}, {}, {}
widgets.Header = function(text, ...)
    headers[#headers + 1] = text
    return header(text, ...)
end
widgets.Label = function(text, ...)
    labels[#labels + 1] = text
    return label(text, ...)
end
imgui.BeginTabItem = function(text, ...)
    tabs[#tabs + 1] = text
    return beginTab(text, ...)
end
local function check(text, condition)
    H.print(text, condition)
    assert(condition, text)
end
local function hasLabel(text)
    for _, value in ipairs(labels) do if value == text then return true end end
    return false
end
local function frame(tab)
    headers, labels, tabs = {}, {}, {}
    H.tab(tab); H.frames(1)
end
H.play(true)
local o = H.options()
o.isVisible[1], o.fadeInOut[1], o.controller[1], o.treasurePool[1] = false, false, false, true
H.command('/inv config')
frame(1)
check('settings tabs ordered General, Bags, Treasure, Equipment', table.concat(tabs, ',') == 'General,Bags,Treasure,Equipment')
check('General sections ordered Window, Controller, Visibility', table.concat(headers, ',') == 'Window,Controller,Visibility')
check('the Window section: shown, pinned, where, held still, fading', table.concat(labels, ',', 1, 5)
    == 'Visible,Pin Inventory,Position,Lock,Fade In And Out')
check('the inventory window has its pin', hasLabel('Pin Inventory'))
check('General excludes bag and treasure controls', not hasLabel('Rows') and not hasLabel('Pin Treasure Pool'))
frame(2)
check('Bags has the grid and its tabs', table.concat(headers, ',') == 'Grid,Tabs')
check('Bags contains grid and bag visibility controls', hasLabel('Rows') and hasLabel('Columns') and hasLabel('Show Bag Tab')
    and hasLabel('Unified Bags') and hasLabel('Show Empty Slots'))
check('Bags excludes General and treasure controls', not hasLabel('Lock') and not hasLabel('Pin Treasure Pool'))
frame(3)
check('Treasure has the pool and how it looks', table.concat(headers, ',') == 'Treasure Pool,Display')
check('Treasure contains pool controls, in the order the monitor has them', table.concat(labels, ',')
    == 'Enable,Detach From Inventory,Pin Treasure Pool,Width,Show When Empty')
check('Treasure excludes General and Bags controls', not hasLabel('Pin Inventory') and not hasLabel('Rows'))
check('attached, the pool has no lock or position of its own', not hasLabel('Lock') and not hasLabel('Position'))
o.treasureDetached[1] = true
frame(3)
check('detached, it has its position and lock', table.concat(labels, ',')
    == 'Enable,Detach From Inventory,Pin Treasure Pool,Position,Lock,Width,Show When Empty')
o.treasureDetached[1] = false
frame(4)
check('Equipment disabled: only its Enable', table.concat(headers, ',') == 'Equipment Monitor'
    and hasLabel('Enable') and not hasLabel('Scale') and not hasLabel('Detach From Inventory'))
o.equipment.enabled[1] = true
frame(4)
check('Equipment has the monitor, how it looks, and its slots', table.concat(headers, ',') == 'Equipment Monitor,Display,Slots')
check('Equipment contains enable, detach, pin, scale and ammo controls', hasLabel('Enable') and hasLabel('Detach From Inventory') and hasLabel('Pin Equipment')
    and hasLabel('Scale') and hasLabel('Show Ammo Count'))
check('attached, the monitor has no lock or position of its own', not hasLabel('Lock') and not hasLabel('Position'))
o.equipment.detached[1] = true
frame(4)
check('detached, it has its lock and position', hasLabel('Lock') and hasLabel('Position'))
check('Equipment has independent decoration toggles', hasLabel('Quality Borders') and hasLabel('Wardrobe Markers'))
check('Equipment excludes bag and treasure controls', not hasLabel('Rows') and not hasLabel('Pin Treasure Pool'))
-- every setting's tooltip is in winxi's look (winxi.tooltip), none imgui's own
local tooltip = require('winxi.tooltip')
local setTooltip, hover, plain, themed = imgui.SetTooltip, tooltip.Hover, 0, 0
imgui.SetTooltip = function(...) plain = plain + 1 return setTooltip(...) end
tooltip.Hover = function(...) themed = themed + 1 return hover(...) end
H.ret.IsItemHovered = { true }
o.controller[1], o.controllerInfo = true, 'verbose'
for tab = 1, 4 do frame(tab) end
H.ret.IsItemHovered = { false }
check('settings tooltips are winxi\'s, not imgui\'s', plain == 0 and themed > 20)
H.unload()
