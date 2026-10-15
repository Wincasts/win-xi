-- The inventory's own tabs of the settings: General (the window, the controller; the shell adds
-- Visibility after them) and Bags (the grid, and which tabs it has). Treasure and Equipment are
-- pool.DrawSettings and equipment.DrawSettings, laid out the same way: what turns them on, whether they
-- are attached to the inventory window, their pin, where they are, then how they look.
--
--   config.General(options)   the General tab
--   config.Bags(options)      the Bags tab
--   config.tabGroups, config.tabNames   the inventory's main tabs, set by inventory.lua
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local tooltip = require('winxi.tooltip')
local shell = require('winxi.shell')

local config = { tabGroups = { }, tabNames = { } }
local windowName = 'winxi.inventory'

local controllerTip = 'Work the inventory with a controller while its window is showing.\nD-pad: move the highlight.  LB / RB: change tab.\nA: open the item\'s menu, and choose from it.  B: back out of the menu, or give the controller back to the game (the window stays open: /inv toggle closes it, /inv focus gives it the controller again).\nX (square): the sort menu. Auto puts the tab back in the usual order and part stacks together; Manual swaps the places of two items; Recycle Bin takes back what was dropped.\nThose buttons do not reach the game while the window is showing. Open it with /inv toggle, from a macro.'

-- Two choices, one under the other, in the column of the controls
local function Choice(firstLabel, firstOn, secondLabel)
    local column = imgui.GetCursorPosX()
    local first = imgui.RadioButton(firstLabel, firstOn)
    imgui.SetCursorPosX(column)
    local second = imgui.RadioButton(secondLabel, not firstOn)
    return first, second
end

-- The inventory's own controller settings, between the sounds and the kind of controller
local function DrawControllerSettings(options)
    widgets.Label('Controller Item Info')
    local verbose = options.controllerInfo == 'verbose'
    local simple, chose = Choice('Simple##inv.controllerInfo', not verbose, 'Verbose##inv.controllerInfo')
    if simple then options.controllerInfo = 'simple' elseif chose then options.controllerInfo = 'verbose' end
    tooltip.Hover('What is said of the highlighted item.\nSimple: its name, in a box under it.  Verbose: its name, stats and description; for gear, its slot, races, level and jobs as well.')

    if verbose then
        widgets.Label('Verbose Info Position')
        local window, item = Choice('Below Window##inv.controllerInfoPlace', options.controllerInfoPlace ~= 'item',
            'Under Item##inv.controllerInfoPlace')
        if window then options.controllerInfoPlace = 'window' elseif item then options.controllerInfoPlace = 'item' end
        tooltip.Hover('Where the verbose box goes: under the inventory window (or the equipment monitor under it), in line with its left edge, or under the highlighted item.')
    end
end

function config.General(options)
    if widgets.Header('Window', true) then
        widgets.Label('Visible')
        imgui.Checkbox('##inv.visible', options.isVisible)
        tooltip.Hover('Whether the inventory window is shown; /inv toggle switches it.')
        widgets.Label('Pin Inventory')
        imgui.Checkbox('##inv.pinned', options.isPinned)
        tooltip.Hover('Keeps the inventory window on screen when /inv toggle hides it; the treasure pool and equipment monitor have pins of their own.\nToggled off while pinned, the window stays but gives the controller back to the game.')
        widgets.Label('Position')
        imgui.SetNextItemWidth(widgets.NumberWidth(2))
        if imgui.InputInt2('##inv.position', options.pos) then
            imgui.SetWindowPos(windowName, options.pos)
        end
        widgets.Label('Lock Drag to Move')
        imgui.Checkbox('##inv.lockMovement', options.lockMovement)
        tooltip.Hover('Prevent dragging the inventory window. The Position fields can still move it.\nWhile it is locked, items can be dragged with the mouse: onto another item to swap their places, or onto another tab\'s name to move them to that tab\'s bags.')
        widgets.Label('Fade In And Out')
        imgui.Checkbox('##inv.fade', options.fadeInOut)
        tooltip.Hover('The window fades in as it is shown and out as it is hidden, in place of appearing and going at once. The treasure pool and equipment monitor fade with it.')
    end

    if widgets.Header('Controller') then
        shell.ControllerSettings(options, controllerTip, DrawControllerSettings)
    end
end

-- A count of the grid's, typed in and kept between low and high
local function Count(label, id, value, low, high, tip)
    widgets.Label(label)
    imgui.SetNextItemWidth(widgets.NumberWidth(1))
    imgui.InputInt(id, value, 0, 0)
    tooltip.Hover(tip)
    value[1] = math.max(low, math.min(high, value[1]))
end

function config.Bags(options)
    if widgets.Header('Grid', true) then
        Count('Rows', '##inv.gridRows', options.gridRows, 5, 30,
            'How many rows of slots the grid shows before it scrolls, from 5 to 30.')
        Count('Columns', '##inv.gridColumns', options.gridColumns, 6, 30,
            'How many slots across the grid is, from 6 to 30.')
        widgets.Label('Show Empty Slots')
        imgui.Checkbox('##inv.emptySlots', options.showEmptySlots)
        tooltip.Hover('Draws a spot for every slot of each bag, with the empty ones as faint squares after the items.')
    end

    if widgets.Header('Tabs') then
        widgets.Label('Unified Bags')
        imgui.Checkbox('##inv.unified', options.isUnified)
        tooltip.Hover('Each tab shows its bags together in one grid, with a tab for each bag along the bottom to show just that one.\nOff, each bag is shown under its own title, one after another.')
        for index, key in ipairs(config.tabGroups) do
            local name = config.tabNames[index]
            widgets.Label('Show ' .. name .. ' Tab')
            imgui.Checkbox('##inv.tab.' .. key, options.bagTabs[key])
        end
    end
end

return config
