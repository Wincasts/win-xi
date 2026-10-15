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
check('movement lock first in General', labels[1] == 'Lock Drag to Move')
check('the inventory window has its pin', hasLabel('Pin Inventory'))
check('General excludes bag and treasure controls', not hasLabel('Rows') and not hasLabel('Show Treasure Pool'))
frame(2)
check('Bags has only bag settings section', table.concat(headers, ',') == 'Bags')
check('Bags contains grid and bag visibility controls', hasLabel('Rows') and hasLabel('Columns') and hasLabel('Show Bag Tab'))
check('Bags excludes General and treasure controls', not hasLabel('Lock Drag to Move') and not hasLabel('Show Treasure Pool'))
frame(3)
check('Treasure has only treasure settings section', table.concat(headers, ',') == 'Treasure Pool')
check('Treasure contains pool controls', hasLabel('Show Treasure Pool') and hasLabel('Show When Empty') and hasLabel('Pin Treasure Pool'))
check('Treasure excludes General and Bags controls', not hasLabel('Lock Drag to Move') and not hasLabel('Rows'))
frame(4)
check('Equipment disabled: only its Enable', table.concat(headers, ',') == 'Equipment Monitor'
    and hasLabel('Enable') and not hasLabel('Scale') and not hasLabel('Detach From Inventory'))
o.equipment.enabled[1] = true
frame(4)
check('Equipment has monitor and slot settings', table.concat(headers, ',') == 'Equipment Monitor,Slots')
check('Equipment contains enable, detach, pin, scale and ammo controls', hasLabel('Enable') and hasLabel('Detach From Inventory') and hasLabel('Pin Equipment')
    and hasLabel('Scale') and hasLabel('Show Ammo Count'))
check('attached, the monitor has no lock or position of its own', not hasLabel('Lock Drag to Move') and not hasLabel('Position'))
o.equipment.detached[1] = true
frame(4)
check('detached, it has its lock and position', hasLabel('Lock Drag to Move') and hasLabel('Position'))
check('Equipment has independent decoration toggles', hasLabel('Quality Borders') and hasLabel('Wardrobe Markers'))
check('Equipment excludes bag and treasure controls', not hasLabel('Rows') and not hasLabel('Show Treasure Pool'))
H.unload()
