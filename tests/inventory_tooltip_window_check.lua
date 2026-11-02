-- Run with: luajit tests/harness.lua winventory addons/winventory/winventory.lua tests/inventory_tooltip_window_check.lua
-- The Tooltip Window (General → Tooltips): off, an item's tooltip is beside the mouse and the controller's
-- box beside its highlight, as before; on, both are in a winxi window of their own, where the player
-- placed it, held there or dragged, growing from the corner chosen
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
o.isVisible[1], o.fadeInOut[1], o.controller[1] = true, false, false
o.gridColumns[1] = 6
H.frames(8)

check('off to begin with', o.tooltipWindow[1] == false and o.tooltipGrowFrom == 'TopLeft' and o.tooltipLock[1] == false)

-- the third item under the mouse
H.ret.IsWindowHovered, H.ret.GetMousePos = { true }, { 15 + 2 * 40, 25 }
local tips = Frame()
check('off: the tooltip beside the mouse, no window', tips > 0 and begun[NAME] == nil)

o.tooltipWindow[1] = true
local savedX, savedY = o.tooltipPos[1], o.tooltipPos[2]
tips = Frame()
check('on: the window, no tooltip beside the mouse', tips == 0 and begun[NAME] ~= nil)
check('first shown at its saved place', placed ~= nil and placed[1] == savedX and placed[2] == savedY)

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

-- where it is is the chosen corner's, kept as the window is dragged
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
Frame()
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

rawset(imgui, 'Begin', begin); rawset(imgui, 'SetNextWindowPos', setPos)
H.print('Tooltip Window: passed', true)
