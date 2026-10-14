-- The theme's font: pushed around winxi's windows and party's only when one is set, taken off again
-- after End, each file loaded once, and a path or a size out of range never taken into the theme
H.load()
local imgui = require('imgui')
local theme = require('winxi.theme')
local fonts = require('winxi.fonts')
local window = require('winxi.window')
local windows = require('windows')
local saved = H.options()
saved.fade.Enabled = false

local push, pop, begin, finish, add = imgui.PushFont, imgui.PopFont, imgui.Begin, imgui.End, imgui.AddFontFromFileTTF
local depth, began, last, loads = 0, nil, nil, 0
imgui.PushFont = function(font, size) depth = depth + 1; last = { font, size } end
imgui.PopFont = function() depth = depth - 1 end
imgui.Begin = function(...) began = depth; return begin(...) end
imgui.AddFontFromFileTTF = function(path, size) loads = loads + 1; return path:match('good') and { path = path } or nil end

local look = theme.Get()
assert(look.FontFile == '' and look.FontSize == 0)
local function both()
    began, last = nil, nil
    window.Plain('winxi.test', nil, 0, function() end)
    local plain = began
    windows.Draw(windows.List.main, function() end, true)
    assert(depth == 0, 'a font left pushed')
    return plain, began
end
local plain, frames = both()
assert(plain == 0 and frames == 0 and last == nil, 'Default pushes nothing')

look.FontSize = 18
plain, frames = both()
assert(plain == 1 and frames == 1 and last[1] == nil and last[2] == 18, 'a size alone keeps the font')

-- a settings window has a font and size of its own, so the Font and Font Size of the game's windows
-- do not change the window they are set in
began, last = nil, nil
window.Full('winxi.settings', nil, 0, function() end, { kind = window.Settings })
assert(began == 0 and last == nil and depth == 0, 'a settings window keeps its own size')
look.FontFile = 'good.ttf'
window.Full('winxi.settings', nil, 0, function() end, { kind = window.Settings })
assert(began == 0 and last == nil and depth == 0, 'and its own font')
look.SettingsFontFile, look.SettingsFontSize = 'good.ttf', 15
window.Full('winxi.settings', nil, 0, function() end, { kind = window.Settings })
assert(began == 1 and last[1].path and last[2] == 15 and depth == 0, 'which it is written in')
look.SettingsFontFile, look.SettingsFontSize = '', 0
local configStyle = nil
do
    local full = window.Full
    window.Full = function(name, open, flags, draw, options) configStyle = options; return true end
    saved.showConfig[1] = true
    require('config').Draw(saved)
    saved.showConfig[1] = false
    window.Full = full
end
assert(configStyle and configStyle.kind == window.Settings, 'party\'s settings window is a settings window')
loads = 0

look.FontFile, look.FontSize = 'good.ttf', 0
plain, frames = both()
assert(plain == 1 and last[1].path == 'C:\\Windows\\Fonts\\good.ttf' and last[2] == 0, 'a font alone keeps the size')
both()
assert(loads == 0, 'a font is loaded once')

look.FontFile = 'bad.ttf'
plain = both()
assert(plain == 0 and loads == 1, 'a font that will not load leaves the usual one')
fonts.Get('bad.ttf')
assert(loads == 1, 'nor is it tried again')

-- an addon's own theme with a path and a size out of range keeps neither
local own = { FontFile = '..\\..\\evil.ttf', FontSize = 99 }
look.FontFile, look.FontSize = '', 0
theme.Configure(false, own)
assert(own.FontFile == '' and own.FontSize == theme.MaxFontSize)
theme.Configure(true, saved.theme)

imgui.PushFont, imgui.PopFont, imgui.Begin, imgui.End, imgui.AddFontFromFileTTF = push, pop, begin, finish, add
H.print('theme font: pushed when set, balanced, loaded once, bad values refused, settings windows in their own font and size', true)
