-- Settings windows: resizable whatever their flags, fitted to their content until a grip or an edge
-- is taken hold of, then kept at the size they are given (no bigger than the screen) with controls
-- narrowed to fit; a double-click there fits them again. Windows of the game kind are left alone.
H.load()
local imgui = require('imgui')
local window = require('winxi.window')
local widgets = require('winxi.widgets')
local settings = { kind = window.Settings }

local real = {}
for _, name in ipairs({ 'SetNextWindowSize', 'Begin', 'GetWindowPos', 'GetWindowSize', 'GetMousePos', 'IsMouseClicked',
        'IsMouseDoubleClicked', 'GetIO', 'PushItemWidth', 'GetContentRegionAvail', 'GetCursorPosX', 'CalcTextSize' }) do
    real[name] = imgui[name]
end
local fitted, sized, flagsGiven, mouse, clicked, doubled, width, display = false, nil, nil, { 0, 0 }, false, false, nil, { x = 1920, y = 1080 }
local pos, size = { 100, 100 }, { 400, 300 }
imgui.SetNextWindowSize = function(s) if s[1] == 0 and s[2] == 0 then fitted = true else sized = { s[1], s[2] } end end
imgui.Begin = function(_, _, flags) flagsGiven = flags; return true end
imgui.GetWindowPos = function() return pos[1], pos[2] end
imgui.GetWindowSize = function() return size[1], size[2] end
imgui.GetMousePos = function() return mouse[1], mouse[2] end
imgui.IsMouseClicked = function() return clicked end
imgui.IsMouseDoubleClicked = function() return doubled end
imgui.GetIO = function() return { DisplaySize = display } end
imgui.PushItemWidth = function(w) width = w end
imgui.GetContentRegionAvail = function() return size[1] - 20 end
imgui.GetCursorPosX = function() return 10 end
imgui.CalcTextSize = function(text) return #text * 7, 14 end

local function frame(kind, flags)
    fitted, sized, width = false, nil, nil
    window.Full('winxi.settingsTest', nil, flags or ImGuiWindowFlags_AlwaysAutoResize, function()
        widgets.BeginLabels('winxi.settingsTest')
        widgets.Label('A Fairly Long Setting Name')
        widgets.PushControlWidth()
        widgets.PopControlWidth()
    end, kind)
end

frame(settings)
assert(fitted, 'a settings window fits its content')
assert(bit.band(flagsGiven, ImGuiWindowFlags_AlwaysAutoResize) == 0, 'and can be resized whatever its flags')
assert(width == 14 * widgets.ControlWidth, 'fitting, its controls keep their width')

-- a click inside, away from the edges, changes nothing
mouse, clicked = { 300, 250 }, true
frame(settings); clicked = false
assert(fitted, 'a click inside leaves it fitting')

-- taking hold of the bottom right grip: from then it keeps its size, and its controls fit it
mouse, clicked = { 498, 398 }, true
frame(settings); clicked = false
assert(not fitted, 'resized, it is no longer fitted')
assert(bit.band(flagsGiven, ImGuiWindowFlags_HorizontalScrollbar) ~= 0, 'what is too wide for it scrolls')
size = { 300, 300 }
frame(settings)
assert(not fitted and width < 14 * widgets.ControlWidth and width >= 14 * widgets.ControlMinWidth, 'its controls narrow to fit it')

-- bigger than the screen: brought back on to it
size, display = { 2500, 1500 }, { x = 1920, y = 1080 }
frame(settings) -- the size it was drawn at is seen as it is drawn, and acted on the next frame
frame(settings)
assert(sized and sized[1] == 1920 and sized[2] == 1080, 'no bigger than the screen')
size = { 400, 300 }

-- a double-click on an edge fits it again
mouse, clicked, doubled = { 100, 200 }, true, true
frame(settings); clicked, doubled = false, false
assert(fitted, 'a double-click on an edge fits it again')

-- a window of the game kind is left as its addon has it
frame(nil)
assert(not fitted and bit.band(flagsGiven, ImGuiWindowFlags_AlwaysAutoResize) ~= 0, 'game windows are left alone')
assert(width == 14 * widgets.ControlWidth, 'and their controls keep their width')

for name, f in pairs(real) do imgui[name] = f end
H.print('settings windows: fitted, resizable, kept on screen, controls narrowed, double-click refits', true)
