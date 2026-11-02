-- Run with: luajit tests/harness.lua winventory addons/winventory/winventory.lua tests/inventory_tooltip_window_check.lua
-- The Tooltip Window (General → Tooltips): off, an item's tooltip is beside the mouse and the controller's
-- box beside its highlight, as before; on, both are in a winxi window of their own. Attached (the
-- default) it is at the inventory's right, level with its top, or under the treasure pool while there is
-- treasure; detached, where the player placed it, held there or dragged, growing from the corner chosen
local imgui = require('imgui')
local o = H.options()
local NAME = 'winxi.inventory.tooltip'
local function check(label, ok) H.print(label, ok); assert(ok, label) end

-- the windows begun each frame, by name
-- and the place given to the Tooltip Window as it began, if one was
local begun, nextPos, placed = {}, nil, nil
local begin = imgui.Begin
rawset(imgui, 'Begin', function(name, ...)
    begun[name] = (begun[name] or 0) + 1
    if name == NAME and nextPos ~= nil then placed = nextPos end
    nextPos = nil
    return begin(name, ...)
end)
local setPos = imgui.SetNextWindowPos
rawset(imgui, 'SetNextWindowPos', function(pos, ...) nextPos = { pos[1], pos[2] }; return setPos(pos, ...) end)
local function Frame()
    for key in pairs(begun) do begun[key] = nil end
    local tips = H.calls.BeginTooltip or 0
    H.frames(1)
    return (H.calls.BeginTooltip or 0) - tips
end

H.play(true); H.gil(5000); H.bag(0, 30, { { 1, 5 }, { 20001 }, { 2, 3 } })
-- every window here is at 100, 200 and 300 by 150: the inventory's, and the pool's when it is there
H.ret.GetWindowPos, H.ret.GetWindowSize = { 100, 200 }, { 300, 150 }
H.pool(0)
o.isVisible[1], o.fadeInOut[1], o.controller[1] = true, false, false
o.gridColumns[1] = 6
H.frames(8)

check('off to begin with, attached', o.tooltipWindow[1] == false and o.tooltipDetached[1] == false
    and o.tooltipGrowFrom == 'TopLeft' and o.tooltipLock[1] == false)

-- the third item under the mouse
H.ret.IsWindowHovered, H.ret.GetMousePos = { true }, { 15 + 2 * 40, 25 }
local tips = Frame()
check('off: the tooltip beside the mouse, no window', tips > 0 and begun[NAME] == nil)

o.tooltipWindow[1] = true
local savedX, savedY = o.tooltipPos[1], o.tooltipPos[2]
tips = Frame()
check('on: the window, no tooltip beside the mouse', tips == 0 and begun[NAME] ~= nil)
check('attached, no treasure: at the inventory\'s right, level with its top', placed ~= nil and placed[1] == 100 + 300 + 6 and placed[2] == 200)
H.pool(3); Frame()
check('treasure: under the pool, pushed down', placed ~= nil and placed[1] == 100 + 300 + 6 and placed[2] == 200 + 150 + 6)
o.treasureDetached[1] = true; Frame()
check('the pool detached: level with the inventory\'s top again', placed[1] == 100 + 300 + 6 and placed[2] == 200)
o.treasureDetached[1] = false
H.pool(0); Frame()
check('the treasure gone: back up', placed[2] == 200)
check('attached: its own place untouched', o.tooltipPos[1] == savedX and o.tooltipPos[2] == savedY)
o.tooltipDetached[1] = true
Frame()
check('detached: shown at its saved place', placed ~= nil and placed[1] == savedX and placed[2] == savedY)
o.tooltipDetached[1] = false
Frame()

-- nothing under the mouse: held a moment, then gone
H.ret.IsWindowHovered, H.ret.GetMousePos = { false }, { -1000, -1000 }
local clock, now = os.clock, os.clock()
os.clock = function() return now end
Frame()
local held = begun[NAME] ~= nil
now = now + 1
Frame()
check('nothing under the mouse: held a moment, then gone', held and begun[NAME] == nil)

-- with the settings open and nothing to say, a sample, to place the window by
H.command('/winventory'); Frame()
check('settings open: a sample to place it by', begun[NAME] ~= nil)
H.command('/winventory'); Frame()
os.clock = clock

-- the controller's highlight: its box goes to the window, not beside the highlight
o.controller[1] = true
H.command('/winventory focus'); H.frames(2)
local labelName = 'winxi.label.' .. addon.name
Frame()
check('controller: the highlighted item in the window, no box beside it', begun[NAME] ~= nil and begun[labelName] == nil)
o.tooltipWindow[1] = false
Frame()
check('off again: the box beside the highlight, no window', begun[labelName] ~= nil and begun[NAME] == nil)
o.tooltipWindow[1] = true
H.command('/winventory focus'); o.controller[1] = false

-- detached, where it is is the chosen corner's, kept as the window is dragged
o.tooltipDetached[1] = true
H.ret.IsWindowHovered, H.ret.GetMousePos = { true }, { 15 + 2 * 40, 25 }
local wasPos = H.ret.GetWindowPos
H.ret.GetWindowPos = { 321, 123 }
Frame()
check('dragged: its place kept in the settings', o.tooltipPos[1] == 321 and o.tooltipPos[2] == 123)
H.ret.GetWindowPos = wasPos

-- Lock: held still, and clicks go through it
local window = require('winxi.window')
local full, given = window.Full, nil
window.Full = function(name, open, flags, draw, style)
    if name == NAME then given = { locked = style.locked, clickThrough = style.clickThrough, growFrom = style.growFrom } end
    return full(name, open, flags, draw, style)
end
o.tooltipDetached[1] = false
Frame()
local attachedHeld = given ~= nil and given.locked and given.clickThrough
o.tooltipDetached[1] = true
Frame()
check('attached: held still, clicks through it', attachedHeld)
local free = given ~= nil and not given.locked
o.tooltipLock[1] = true
Frame()
check('Lock Tooltip Window: held still, clicks through; off, it can be dragged', free and given.locked and given.clickThrough)
o.tooltipGrowFrom = 'BottomRight'
Frame()
check('Grow From: the corner given to the window', given.growFrom == 'BottomRight')
window.Full = full

-- the treasure pool's and the equipment monitor's tooltips go there too
local text = nil
local tipwindow = require('tipwindow')
local offer = tipwindow.Offer
tipwindow.Offer = function(what, arg) if type(what) == 'string' then text = what end; return offer(what, arg) end
tipwindow.Show('Fire Crystal\nNo one has lotted yet.')
check('text for it goes to the window while it is on', text == 'Fire Crystal\nNo one has lotted yet.')
tipwindow.Offer = offer

-- the inventory toggled off with Fade In And Out: the attached window fades with it, never more
-- opaque than it, never anywhere but beside it, and gone when it is
do
    o.tooltipWindow[1], o.tooltipDetached[1], o.tooltipLock[1], o.tooltipGrowFrom = true, false, false, 'TopLeft'
    o.fadeInOut[1], o.isVisible[1] = true, true
    H.pool(0)
    H.ret.IsWindowHovered, H.ret.GetMousePos = { true }, { 15 + 2 * 40, 25 }
    local alphas = {}
    local full = window.Full
    window.Full = function(name, open, flags, draw, style)
        if name == NAME or name == 'winxi.inventory' then alphas[name] = style.alpha end
        return full(name, open, flags, draw, style)
    end
    local clock, now = os.clock, os.clock()
    os.clock = function() return now end
    local function Step()
        alphas[NAME], alphas['winxi.inventory'], placed = nil, nil, nil
        now = now + 0.02
        Frame()
    end
    for _ = 1, 10 do Step() end
    local full1 = alphas[NAME] ~= nil and alphas[NAME] > 0.99
    o.isVisible[1] = false
    local inStep, besideIt, goneWithIt, frames = true, true, true, 0
    for _ = 1, 15 do
        Step()
        local tip, inventory = alphas[NAME], alphas['winxi.inventory']
        if tip ~= nil then
            frames = frames + 1
            inStep = inStep and inventory ~= nil and tip <= inventory + 1e-6
            besideIt = besideIt and (placed == nil or (placed[1] == 100 + 300 + 6 and placed[2] == 200))
        end
        goneWithIt = goneWithIt and (inventory ~= nil or tip == nil)
    end
    os.clock = clock
    window.Full = full
    check('toggled off: fades with the inventory, beside it, gone with it', full1 and frames > 0 and inStep and besideIt and goneWithIt)
    o.fadeInOut[1], o.isVisible[1] = false, true
end

-- a treasure pool line: all that is said of the item, as in the inventory, then who is winning it;
-- by the mouse in the window or beside it, and by the controller
do
    local texts = {}
    local text = imgui.Text
    rawset(imgui, 'Text', function(words, ...) texts[#texts + 1] = words; return text(words, ...) end)
    local function Said(words) for _, w in ipairs(texts) do if w == words then return true end end return false end
    local tipwindow = require('tipwindow')
    local offer, got = tipwindow.Offer, nil
    tipwindow.Offer = function(what, arg, icon) got = { what = what, arg = arg, icon = icon }; return offer(what, arg, icon) end
    o.fadeInOut[1], o.isVisible[1], o.tooltipWindow[1], o.tooltipDetached[1] = false, true, true, false
    H.pool(2)
    -- the mouse over the first line's name (nothing of the grid under it)
    H.ret.IsWindowHovered, H.ret.GetMousePos, H.ret.IsItemHovered = { false }, { -1000, -1000 }, { true }
    H.frames(1)
    texts = {}
    Frame()
    check('pool, Tooltip Window: the item\'s details offered, with its icon', got ~= nil and type(got.what) == 'function'
        and got.arg ~= nil and got.arg.id == 101 and got.icon == 101)
    check('drawn: its details as the inventory has them (its description), then who is winning it', Said('About item 101') and Said('No one has lotted yet.'))
    o.tooltipWindow[1] = false
    texts = {}
    local tips = Frame()
    check('pool, beside the mouse: the same', tips > 0 and Said('About item 101') and Said('No one has lotted yet.'))
    H.ret.IsItemHovered = nil
    -- the controller on the pool's first line, the window on
    o.tooltipWindow[1], o.controller[1] = true, true
    H.command('/winventory focus'); H.frames(1)
    H.tap(H.Button.Y); H.frames(1)
    got = nil
    texts = {}
    Frame()
    check('controller on a pool line: the same, in the window', got ~= nil and type(got.what) == 'function' and got.arg ~= nil
        and got.arg.id ~= nil and Said('No one has lotted yet.'))
    o.tooltipWindow[1] = false
    texts = {}
    Frame()
    check('controller on the pool\'s first line, the window off: its details in the label beside the line', begun['winxi.label.' .. addon.name] ~= nil
        and Said('About item 100') and Said('No one has lotted yet.'))
    H.command('/winventory focus'); o.controller[1] = false
    tipwindow.Offer = offer
    rawset(imgui, 'Text', text)
    H.pool(0)
end

rawset(imgui, 'Begin', begin); rawset(imgui, 'SetNextWindowPos', setPos)
H.print('Tooltip Window: passed', true)
