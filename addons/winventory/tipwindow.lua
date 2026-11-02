-- The Tooltip Window: what winventory says of an item, a treasure pool line or an equipment slot, in a
-- winxi window of its own, in place of the tooltip beside the mouse and the box beside the controller's
-- highlight. Off, those are as they were. Attached (the default) it is beside the inventory window, at
-- its right, its top level with the window's, or under the treasure pool where that is there, so that
-- the pool filling pushes it down; detached, it is where the player puts it. An item's icon is at its
-- left. Attached it is drawn at the inventory's Scale, detached at its own (Tooltip Scale).
--
--   tipwindow.Begin(options, previewing, sheet)  once a frame, before anything is offered; previewing
--                                         while the settings are open, for a sample to place the window by;
--                                         sheet gives the item icons' sheet (winxi.itemicons), asked for
--                                         only when an icon is to be drawn
--   tipwindow.On()                        whether the window takes the tooltips this frame
--   tipwindow.Offer(content, arg, icon)   this frame's: a string, or a function drawn as content(arg); icon
--                                         the item whose icon goes at its left, or nil for none
--   tipwindow.Show(text, icon)            text for the window when it is on, else winxi's tooltip
--   tipwindow.Attach(x, y)                where it goes attached this frame, or nil where there is nowhere
--                                         (the inventory window off screen, and no pool): its own place then
--   tipwindow.Draw()                      once a frame, after everything has been offered
--   tipwindow.DrawSettings(options)       the Tooltips tab of the settings
local bit = require('bit')
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local tooltip = require('winxi.tooltip')
local window = require('winxi.window')
local style = require('winxi.style')
local anchor = require('winxi.anchor')
local fade = require('winxi.fade')
local itemicons = require('winxi.itemicons')
local sizing = require('sizing')

local tipwindow = {}

local windowName = 'winxi.inventory.tooltip'
local HOLD = 0.15 -- seconds the last tooltip stays, so that the mouse going between two items does not blink it

local options = nil
local previewing = false
local content, contentArg, contentIcon = nil, nil, nil -- what the window shows: kept while it fades out
local offered = false                -- whether anything was offered this frame
local offeredAt = -1                 -- when something last was
local shownLast = false              -- whether the window was up last frame: it is brought to the front as it comes up
local placeAgain = true              -- the saved place to be given to the window: at first, and when the settings change it
local attachAt = { 0, 0 }             -- where it goes attached this frame
local attachable = false

local sample = 'Tooltip Window\nWhat is said of an item, a treasure pool line or an equipment slot shows here, while it is under the mouse or the controller\'s highlight.\nDrag this window to place it.'
local sampleAttached = 'Tooltip Window\nWhat is said of an item, a treasure pool line or an equipment slot shows here, while it is under the mouse or the controller\'s highlight.\nIt sits at the inventory\'s right, under the treasure pool. Detach it from the inventory to place it yourself.'

local open = { true }
local windowStyle = { alpha = 1, growFrom = 'TopLeft', locked = nil, clickThrough = nil, fontSize = nil }
local flags = nil
local iconSheet = nil                 -- what gives the item icons' sheet this frame
local scale = 1                       -- what the window is drawn at this frame
local ICON, ICON_GAP = 32, 8          -- an item's icon, at scale 1, and the room between it and the words
local iconSize, iconAt = { 32, 32 }, { 0, 0 }
local iconEnd, uvA, uvB = { 0, 0 }, { 0, 0 }, { 1, 1 }
local white = { 1, 1, 1, 1 }

function tipwindow.Begin(drawOptions, settingsOpen, sheet)
    options, previewing, offered, attachable = drawOptions, settingsOpen and true or false, false, false
    iconSheet = sheet
end

function tipwindow.Attach(x, y)
    attachable = x ~= nil and y ~= nil
    if attachable then attachAt[1], attachAt[2] = x, y end
end

function tipwindow.On()
    return options ~= nil and options.tooltipWindow[1] == true
end

function tipwindow.Offer(what, arg, icon)
    content, contentArg, contentIcon, offered, offeredAt = what, arg, icon, true, os.clock()
end

function tipwindow.Show(text, icon)
    if text == nil then return end
    if tipwindow.On() then
        tipwindow.Offer(text, nil, icon)
    else
        tooltip.Show(text)
    end
end

-- The item's icon, at the left: from winxi.itemicons' sheet, once it has it (it comes over a frame or
-- two the first time); the room for it is kept either way, so the words do not move when it comes
local function DrawIcon()
    local x, y = imgui.GetCursorScreenPos()
    local side = math.floor(ICON * scale + 0.5)
    iconSize[1], iconSize[2] = side, side
    imgui.Dummy(iconSize)
    local sheet = type(iconSheet) == 'function' and iconSheet() or iconSheet
    local place = sheet ~= nil and itemicons.Place(contentIcon) or nil
    if place ~= nil then
        iconAt[1], iconAt[2], iconEnd[1], iconEnd[2] = x, y, x + side, y + side
        uvA[1], uvA[2], uvB[1], uvB[2] = place[1], place[2], place[3], place[4]
        imgui.GetWindowDrawList():AddImage(sheet, iconAt, iconEnd, uvA, uvB, imgui.GetColorU32(white))
    end
    imgui.SameLine(0, math.floor(ICON_GAP * scale + 0.5))
end

-- What goes in the window: drawn twice in a frame for a corner other than the top left (winxi.anchor
-- measures it first), so it only draws
local function DrawContent()
    if contentIcon ~= nil then
        DrawIcon()
        imgui.BeginGroup()
    end
    if type(content) == 'function' then
        content(contentArg)
    elseif content ~= nil then
        -- some 48 letters wide, in the window's font as it is now
        imgui.PushTextWrapPos(imgui.GetCursorPosX() + imgui.CalcTextSize('A') * 48)
        imgui.Text(content)
        imgui.PopTextWrapPos()
    end
    if contentIcon ~= nil then
        imgui.EndGroup()
    end
end

function tipwindow.Draw()
    if not tipwindow.On() then
        shownLast, placeAgain = false, true
        return
    end
    local now = os.clock()
    local wanted = offered or (content ~= nil and now - offeredAt < HOLD)
    local attached = attachable and not options.tooltipDetached[1]
    if not wanted and previewing then
        content, contentArg, contentIcon, wanted = attached and sampleAttached or sample, nil, nil, true
    end
    local alpha = wanted and 1 or 0
    if options.fadeInOut[1] then
        alpha = fade.Presence(windowName, wanted)
    end
    if alpha <= 0.01 or content == nil then
        shownLast = false
        return
    end

    local mode = options.tooltipGrowFrom
    if anchor.Labels[mode] == nil or attached then mode = anchor.Default end
    if attached then
        -- beside the inventory, every frame; held still, clicks going through it. Detached again, it
        -- goes back to its own place
        imgui.SetNextWindowPos(attachAt, ImGuiCond_Always)
        placeAgain = true
    elseif placeAgain then
        -- the saved place is the chosen corner's: the top left is imgui's own, the others winxi.anchor's
        if mode == anchor.Default then
            imgui.SetNextWindowPos(options.tooltipPos, ImGuiCond_Always)
        end
        anchor.Set(windowName, mode, options.tooltipPos[1], options.tooltipPos[2])
        placeAgain = false
    end
    if not shownLast then
        -- coming up: in front of the inventory window, which may have been clicked since it was last up
        imgui.SetNextWindowFocus()
    end
    flags = flags or bit.bor(style.TitlelessFlags(), ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoFocusOnAppearing or 0, ImGuiWindowFlags_NoNav or 0, ImGuiWindowFlags_NoSavedSettings or 0)
    local locked = (attached or options.tooltipLock[1]) and true or nil
    -- the inventory's size attached, its own detached
    scale = sizing.Clamp(attached and options.inventoryScale[1] or options.tooltipScale[1])
    windowStyle.fontSize = sizing.FontSize(scale)
    windowStyle.alpha, windowStyle.growFrom = alpha, mode
    windowStyle.locked, windowStyle.clickThrough = locked, locked
    window.Full(windowName, open, flags, DrawContent, windowStyle)
    open[1], shownLast = true, true

    -- where it is now, dragged or not: the chosen corner's place, kept in the settings (detached)
    local x, y = anchor.Point(windowName)
    if x ~= nil and not attached then
        options.tooltipPos[1], options.tooltipPos[2] = math.floor(x + 0.5), math.floor(y + 0.5)
    end
end

-- The Tooltips tab: the window, where it is, whether it can be dragged, the corner it grows from; how big
local windowSpec, detachSpec, placeSpec = {}, { parent = true }, { parent = true, format = '%d px' }
local scaleSpec = { parent = true, float = true, format = '%.2fx' }
local lockSpec = { label = 'Lock Tooltip Window', description = 'Keeps the tooltip window where it is, and lets clicks through it to the game. Off, it can be dragged.', parent = true }
local growSpec = { parent = true }
local axis = { 0 }

local function Axis(name, sentence, index, high, id)
    axis[1] = options.tooltipPos[index]
    if widgets.Slider(name, sentence, axis, 0, high, id, placeSpec) then
        options.tooltipPos[index] = axis[1]
        placeAgain = true
    end
end

function tipwindow.DrawSettings(drawOptions)
    options = drawOptions
    -- placed, sized and held by its own settings only while it is on and detached
    local free = options.tooltipWindow[1] == true and options.tooltipDetached[1] == true
    detachSpec.parent = options.tooltipWindow
    placeSpec.parent, lockSpec.parent, growSpec.parent, scaleSpec.parent = free, free, free, free
    if widgets.Header('Tooltip Window', true) then
        widgets.Check('Tooltip Window', 'Shows what is said of an item, a treasure pool line or an equipment slot in a window of its own, with the item\'s icon, instead of beside the mouse or the controller\'s highlight.',
            options.tooltipWindow, '##inv.tooltipWindow', windowSpec)
        widgets.Check('Detach From Inventory', 'Attached, the window sits at the inventory\'s right, under the treasure pool while there is treasure. Detached, it stays where you put it.',
            options.tooltipDetached, '##inv.tooltipDetached', detachSpec)
        local display = imgui.GetIO().DisplaySize
        Axis('Tooltip Position X', 'How far the window\'s corner is from the left of the screen. Dragging the window sets it too.', 1,
            math.floor(display.x or display[1] or 1920), '##inv.tooltipPosX')
        Axis('Tooltip Position Y', 'How far the window\'s corner is from the top of the screen.', 2,
            math.floor(display.y or display[2] or 1080), '##inv.tooltipPosY')
        widgets.Lock(options.tooltipLock, '##inv.tooltipLock', lockSpec)
        local chosen = widgets.GrowFrom(options.tooltipGrowFrom, growSpec)
        if chosen ~= nil then
            -- the window stays where it is: winxi.anchor takes the new corner's place from it as it is drawn
            options.tooltipGrowFrom = chosen
        end
    end
    if widgets.Header('Display') then
        widgets.Slider('Tooltip Scale', 'How big the detached window, its icon and its words are. Attached, it is the inventory\'s Scale.',
            options.tooltipScale, sizing.Least, sizing.Most, '##inv.tooltipScale', scaleSpec)
    end
end

return tipwindow
