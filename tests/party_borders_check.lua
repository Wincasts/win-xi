-- The theme's window border art (winxi.borders): its choices, the nine slices, tiny windows, a missing
-- image, and the window's own border switched off before Begin only where there is art in its place,
-- for party's windows and winxi's alike
H.load()
local theme = require('winxi.theme')
local borders = require('winxi.borders')
local imgui = require('imgui')
local look = theme.Get()
assert(look.BorderStyle == 'theme' and H.options().style.borderStyle == nil)
-- every choice but the plain border, each with its image in winxi's assets
local styles = {}
for _, choice in ipairs(theme.BorderStyles) do
    if choice.key ~= 'theme' then
        styles[#styles + 1] = choice.key
        local image = io.open(('addons/libs/winxi/assets/borders/%s.png'):format(choice.key), 'rb')
        assert(image, 'no image for ' .. choice.key)
        image:close()
    end
end
assert(#styles == 13)

local getPos, getSize, getList, load = imgui.GetWindowPos, imgui.GetWindowSize, imgui.GetWindowDrawList, borders.Load
local count, loaded = 0, nil
local list = { AddImage = function(_, handle, a, b, uvA, uvB)
    assert(handle == 123 and b[1] >= a[1] and b[2] >= a[2])
    assert(a[1] >= 20 and b[1] <= 220 and a[2] >= 30 and b[2] <= 130)
    assert(uvA[1] >= 0 and uvA[2] >= 0 and uvB[1] <= 1 and uvB[2] <= 1)
    if count == 0 then
        assert(b[1] - a[1] <= 3 and b[2] - a[2] <= 3, 'Border corners must be at most 3px')
    end
    count = count + 1
end }
imgui.GetWindowPos = function() return 20, 30 end
imgui.GetWindowSize = function() return 200, 100 end
imgui.GetWindowDrawList = function() return list end
borders.Load = function(style) loaded = style; return 123 end
for _, style in ipairs(styles) do
    count = 0
    borders.Draw(borders.Texture(style))
    assert(count == 8 and loaded == style)
end
assert(borders.Texture('theme') == nil and borders.Texture('invalid') == nil)
count = 0
borders.Draw(nil)
assert(count == 0)
imgui.GetWindowSize = function() return 6, 4 end
borders.Draw(123)
assert(count == 8)
imgui.GetWindowPos, imgui.GetWindowSize, imgui.GetWindowDrawList = getPos, getSize, getList

-- Integration: the native border is switched off before Begin only with a loaded texture. Textures are
-- kept once loaded, so each round is given a fresh module.
local windows = require('windows')
local window = require('winxi.window')
local saved = H.options()
saved.fade.Enabled = false
windows.Use(saved)
local push, pop, begin = imgui.PushStyleVar, imgui.PopStyleVar, imgui.Begin
local disabled, pushed = false, 0
imgui.PushStyleVar = function(key, value)
    if key == ImGuiStyleVar_WindowBorderSize and value == 0 then disabled = true end
    pushed = pushed + 1
    return push(key, value)
end
imgui.PopStyleVar = function(n) pushed = pushed - (n or 1); return pop(n) end
local expected = false
imgui.Begin = function(...)
    assert(disabled == expected, 'Native border replacement must be set before Begin')
    return begin(...)
end
local function fresh(available)
    package.loaded['winxi.borders'] = nil
    local again = require('winxi.borders')
    again.Load = function() return available and 123 or false end
    for _, name in ipairs({ 'winxi.window', 'windows' }) do package.loaded[name] = nil end
    windows, window = require('windows'), require('winxi.window')
    windows.Use(saved)
end
for _, style in ipairs(styles) do
    for _, available in ipairs({ true, false }) do
        fresh(available)
        look.BorderStyle = style
        expected, disabled, pushed = available, false, 0
        windows.Draw(windows.List.main, function() end, true)
        assert(pushed == 0, 'party window left style vars pushed')
        expected, disabled = available, false
        window.Plain('winxi.test', nil, 0, function() end)
        assert(pushed == 0, 'winxi window left style vars pushed')
        expected, disabled = available, false
        window.Plain('winxi.test', nil, 0, function() end, { kind = window.Game })
        expected, disabled = false, false
        window.Full('winxi.settings', nil, 0, function() end, { kind = window.Settings })
        assert(pushed == 0, 'a settings window keeps the plain border')
    end
end
look.BorderStyle = 'theme'
expected, disabled = false, false
windows.Draw(windows.List.main, function() end, true)
window.Full('winxi.test', nil, 0, function() end)
imgui.PushStyleVar, imgui.PopStyleVar, imgui.Begin = push, pop, begin
borders.Load = load

-- Border Opacity: a game window's border, plain or art, is faded by it; a settings window's is not
local window = require('winxi.window')
local style = require('winxi.style')
local pushColour = imgui.PushStyleColor
local borderPushed = nil
imgui.PushStyleColor = function(slot, colour) if slot == ImGuiCol_Border then borderPushed = colour[4] end end
look.BorderColor[4], look.BorderOpacity = 1, 40
theme.Touch()
style.PushPlain({ kind = window.Game }); style.Pop()
assert(math.abs(borderPushed - 0.4) < 1e-6, 'game window: faded')
style.PushPlain({ kind = window.Settings }); style.Pop()
assert(borderPushed == 1, 'settings window: solid')
local getColour, tintAlpha = imgui.GetColorU32, nil
imgui.GetColorU32 = function(colour) tintAlpha = colour[4] return 1 end
borders.Draw(123)
assert(math.abs(tintAlpha - 0.4) < 1e-6, 'border art: faded')
look.BorderOpacity, tintAlpha = 0, nil
borders.Draw(123)
assert(tintAlpha == nil, 'none at all: not drawn')
theme.Reset({ 'BorderOpacity' })
assert(look.BorderOpacity == 100)
imgui.PushStyleColor, imgui.GetColorU32 = pushColour, getColour
H.print('border choices, nine slices, tiny windows, missing-texture fallback, and settings windows plain', true)
