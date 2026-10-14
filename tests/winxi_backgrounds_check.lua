-- The theme's window background: none for Plain or a settings window, the window's own background left
-- clear under one that is drawn, the gradient and its lines, the tiles side by side and never
-- stretched, a tile that will not load leaving the flat background, and party's windows the same
H.load()
local imgui = require('imgui')
local theme = require('winxi.theme')
local style = require('winxi.style')
local window = require('winxi.window')
local backgrounds = require('winxi.backgrounds')
local windows = require('windows')
local saved = H.options()
saved.fade.Enabled = false
local look = theme.Get()

-- every choice is one the generator made, or one drawn
for _, choice in ipairs(theme.BackgroundStyles) do
    if choice.key ~= 'plain' and choice.key ~= 'gradient' and choice.key ~= 'ffxi' then
        local image = io.open(('addons/libs/winxi/assets/backgrounds/%s.png'):format(choice.key), 'rb')
        assert(image, 'no tile for ' .. choice.key)
        image:close()
    end
end

assert(look.BackgroundStyle == 'plain' and backgrounds.For(nil) == nil)
look.BackgroundStyle = 'gradient'
assert(backgrounds.For(nil) ~= nil and backgrounds.For({ kind = window.Settings }) == nil)

-- the window's own background: clear under a drawn one, the theme's otherwise
local pushColour, windowBg = imgui.PushStyleColor, nil
imgui.PushStyleColor = function(slot, colour) if slot == ImGuiCol_WindowBg then windowBg = colour end end
style.PushPlain({ kind = window.Game }); style.Pop()
assert(windowBg[4] == 0 and style.Background() ~= nil)
style.PushPlain({ kind = window.Settings }); style.Pop()
assert(windowBg == look.SettingsBackgroundColor and style.Background() == nil)
imgui.PushStyleColor = pushColour

-- drawn: a gradient, and for FFXI-inspired a line every other row; tiles at their own size
local list, counts, uvs = {}, {}, {}
for _, name in ipairs({ 'AddRectFilledMultiColor', 'AddRectFilled', 'AddImage', 'AddText', 'AddRect', 'PushClipRect', 'PopClipRect' }) do
    list[name] = function(_, ...)
        counts[name] = (counts[name] or 0) + 1
        if name == 'AddImage' then local _, a, b, uvA, uvB = ...; uvs[#uvs + 1] = { b[1] - a[1], b[2] - a[2], uvB[1], uvB[2] } end
    end
end
local getList, getPos, getSize = imgui.GetWindowDrawList, imgui.GetWindowPos, imgui.GetWindowSize
imgui.GetWindowDrawList = function() return list end
imgui.GetWindowPos = function() return 10, 20 end
imgui.GetWindowSize = function() return 300, 150 end
backgrounds.Draw(backgrounds.For(nil), look.BackgroundColor)
assert(counts.AddRectFilledMultiColor == 1 and counts.AddRectFilled == nil)
look.BackgroundStyle, counts = 'ffxi', {}
backgrounds.Draw(backgrounds.For(nil), look.BackgroundColor)
assert(counts.AddRectFilledMultiColor == 1 and counts.AddRectFilled == 75)

local load = backgrounds.Load
backgrounds.Load = function(name) return name == 'marble' and 77 or false end
look.BackgroundStyle, counts = 'marble', {}
backgrounds.Draw(backgrounds.For(nil), look.BackgroundColor)
assert(counts.AddImage == 6, 'three across and two down')
for _, uv in ipairs(uvs) do
    assert(math.abs(uv[1] / 128 - uv[3]) < 1e-9 and math.abs(uv[2] / 128 - uv[4]) < 1e-9, 'never stretched')
end
-- a tile that will not load: the flat background
look.BackgroundStyle = 'weave'
assert(backgrounds.For(nil) == nil)
counts = {}
backgrounds.Draw(backgrounds.For(nil), look.BackgroundColor)
assert(next(counts) == nil)

-- winxi's game windows and party's draw it; a settings window does not
look.BackgroundStyle, counts = 'marble', {}
window.Plain('winxi.test', nil, 0, function() end)
assert(counts.AddImage == 6)
counts = {}
window.Full('winxi.settings', nil, 0, function() end, { kind = window.Settings })
assert(counts.AddImage == nil)
counts = {}
windows.Draw(windows.List.main, function() end, true)
assert(counts.AddImage == 6)

look.BackgroundStyle, backgrounds.Load = 'plain', load
imgui.GetWindowDrawList, imgui.GetWindowPos, imgui.GetWindowSize = getList, getPos, getSize
H.print('backgrounds: plain and settings windows left alone, gradient, lines, tiles unstretched, missing tile, winxi and party windows', true)
