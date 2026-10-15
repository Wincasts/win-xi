-- Run with: luajit tests/harness.lua simplelog tests/empty.lua tests/simplelog_ui_check.lua
H.load()
string.fmt = string.format -- Ashita's string helper
local imgui = require('imgui')
local theme = require('winxi.theme')
local window = require('winxi.window')
local ui = dofile('addons/simplelog/lib/ui.lua')
gProfileSettings = dofile('addons/simplelog/configuration.lua')
gProfileFilter = dofile('addons/simplelog/filters.lua')
gProfileColor = dofile('addons/simplelog/colors.lua')
gStatus = { CurrentFilters = 'default_filters.lua' }
addon.version, addon.link, addon.author = 'test', 'test link', 'test author'

local realFull, realTab = window.Full, imgui.BeginTabItem
local selected, calls = 'Settings', 0
imgui.BeginTabItem = function(label) return label == selected or label == 'Player' end
window.Full = function(name, open, flags, draw, options)
    assert(options.kind == window.Settings, 'SimpleLog must use the settings window kind')
    calls = calls + 1
    return realFull(name, open, flags, draw, options)
end
imgui.BeginChild = function() error('settings must render directly on the Winxi background') end
imgui.StyleColorsDark = function() error('must not reset the global imgui style') end
imgui.SetTooltip = function() error('must use Winxi tooltips') end
ui.state.open[1] = true
for _, tab in ipairs({ 'Settings', 'Filters', 'Colors' }) do
    selected = tab
    ui.render_config(false)
end
assert(calls == 3, 'all three tabs render through Winxi')
ui.state.open[1] = false
ui.render_config(false)
assert(calls == 3, 'closed settings do not draw')
window.Full, imgui.BeginTabItem = realFull, realTab
H.print('simplelog: settings-kind window, all tabs, no global style reset or native tooltips', true)
