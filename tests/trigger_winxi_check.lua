-- Targeted WinXI contract checks, run through tests/harness.lua.
local app = require('shared').app
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local window = require('winxi.window')
local theme = require('winxi.theme')
local indicator = require('indicator')
local game = require('winxi.game')
local text = require('winxi.text')
local o = H.options()
assert(addon.name == 'trigger' and app.spec.command == '/trigger')
assert(app.ids.config == 'Trigger Settings' and app.configStyle.kind == window.Settings)
assert(o.useSharedTheme == true and type(o.theme) == 'table')
assert(app.spec.hideAppearance == true and app.spec.drawAppearance == nil, 'no local theme tab')
assert(not H.command('/twister'), 'old command does not capture game input')
assert(H.command('/trigger'))

local configured, configure = 0, theme.Configure
theme.Configure = function(shared, own)
    assert(shared == o.useSharedTheme and own == o.theme)
    configured = configured + 1
    return configure(shared, own)
end
H.frames(2)
theme.Configure = configure
assert(configured == 2, 'theme configured once each frame')
o.useSharedTheme = false
app.spec.onSettings(o)
assert(o.useSharedTheme == true, 'saved private theme migrated to shared appearance')
local themeTabs, beginThemeTab = 0, widgets.BeginThemeTab
widgets.BeginThemeTab = function() themeTabs = themeTabs + 1; return false end
H.frames(1)
widgets.BeginThemeTab = beginThemeTab
assert(themeTabs == 0, 'Winxi Theme tab is not drawn')

-- Every settings tab's controls use the common width stack, without leaking it.
o.showIndicator[1] = true
assert(app.spec.settingsLabel == 'Notifications')
assert(app.spec.tabs[1].label == 'Triggers' and app.spec.tabs[2].label == 'Toast')
for tab = 1, 3 do
    H.tab(tab)
    local pushes, pops = H.calls.PushItemWidth or 0, H.calls.PopItemWidth or 0
    H.frames(1)
    if tab ~= 2 then assert((H.calls.PushItemWidth or 0) > pushes, 'control widths in tab ' .. tab) end
    assert((H.calls.PushItemWidth or 0) - pushes == (H.calls.PopItemWidth or 0) - pops)
end
local labels, originalLabel = {}, widgets.Label
widgets.Label = function(label, experimental)
    labels[label] = experimental and 'experimental' or true
    return originalLabel(label, experimental)
end
H.tab(1); H.frames(1)
assert(labels['Overlap Sounds'] == true, 'Overlap Sounds has no experimental tag')
H.tab(2); H.frames(1)
assert(not labels['Enable Toast'] and not labels['Grow From'], 'toast controls are separate from triggers')
H.tab(3); H.frames(1)
assert(labels['Enable Toast'] and labels['Grow From'] and labels['Fade In And Out'], 'toast controls in Toast tab')
labels = {}
o.showIndicator[1] = false
H.frames(1)
assert(labels['Enable Toast'] and not labels['Duration'] and not labels['Grow From'], 'disabled toast hides extra options')
o.showIndicator[1] = true
widgets.Label = originalLabel

-- Threshold sliders start at the same horizontal position as their sound dropdowns.
local combo, slider, cursor = imgui.BeginCombo, imgui.SliderInt, imgui.SetCursorPosX
local input = imgui.InputText
local dropdownX, extraAligned = nil, 0
local soundPositions, aligned = {}, 0
local lastCursor
rawset(imgui, 'BeginCombo', function(id, ...)
    if id == '##trigger.lowhp.sound' or id == '##trigger.lowmp.sound' then
        soundPositions[id] = imgui.GetCursorPosX()
    end
    if id:match('^##trigger%..+%.sound$') then dropdownX = imgui.GetCursorPosX() end
    if id == '##trigger.volume' then
        assert(lastCursor == dropdownX, 'volume aligned with sound dropdowns')
        extraAligned = extraAligned + 1
    end
    return combo(id, ...)
end)
rawset(imgui, 'InputText', function(id, ...)
    if id == '##trigger.drop.items' then
        assert(lastCursor == dropdownX, 'items aligned with sound dropdown')
        extraAligned = extraAligned + 1
    end
    return input(id, ...)
end)
rawset(imgui, 'SetCursorPosX', function(x)
    lastCursor = x
    return cursor(x)
end)
rawset(imgui, 'SliderInt', function(id, ...)
    local soundId = id:gsub('%.threshold$', '.sound')
    if soundPositions[soundId] ~= nil then
        assert(lastCursor == soundPositions[soundId], 'threshold aligned with ' .. soundId)
        aligned = aligned + 1
    end
    return slider(id, ...)
end)
H.tab(1); H.frames(1)
rawset(imgui, 'BeginCombo', combo)
rawset(imgui, 'SliderInt', slider)
rawset(imgui, 'SetCursorPosX', cursor)
rawset(imgui, 'InputText', input)
assert(extraAligned == 2, 'items and volume aligned')
assert(aligned == 2, 'both HP and MP thresholds aligned')

-- Help marks on every tab delegate to WinXI, including beside/aligned variants.
local tooltip = require('winxi.tooltip')
local controls = require('controls')
local hover, originalHover = {}, tooltip.Hover
tooltip.Hover = function(words) hover[#hover + 1] = words end
controls.Mark('Aligned help')
controls.Mark('Beside help', true)
local rightX
rawset(imgui, 'SetCursorPosX', function(x) rightX = x end)
local expectedRight = imgui.GetCursorPosX() + imgui.GetContentRegionAvail() - imgui.CalcTextSize('(?)')
controls.RightMark('Right-edge help')
rawset(imgui, 'SetCursorPosX', cursor)
assert(rightX == expectedRight and hover[3] == 'Right-edge help', 'right-edge WinXI help mark')
assert(hover[1] == 'Aligned help' and hover[2] == 'Beside help')
for tab = 1, 3 do
    local before = #hover
    H.tab(tab); H.frames(1)
    assert(#hover > before, 'WinXI help tooltips in tab ' .. tab)
    if tab == 3 then
        assert(#hover - before >= 8, 'help for toast, duration, hiding, fade and grow')
    end
end
tooltip.Hover = originalHover

-- Disabled shared tooltips must suppress help.
local sharedTheme = theme.Shared()
local enabled, isHovered = sharedTheme.TooltipsEnabled, imgui.IsItemHovered
sharedTheme.TooltipsEnabled = false
rawset(imgui, 'IsItemHovered', function() return true end)
local before = H.calls.BeginTooltip or 0
controls.Mark('Hidden help', true)
assert((H.calls.BeginTooltip or 0) == before, 'shared tooltip visibility respected')
sharedTheme.TooltipsEnabled = enabled
rawset(imgui, 'IsItemHovered', isHovered)

-- Controls shrink in a resized window; do not use fixed pixel widths.
local resized, available = window.IsResized, imgui.GetContentRegionAvail
window.IsResized = function() return true end
rawset(imgui, 'GetContentRegionAvail', function() return 180, 100 end)
local widths = {}
rawset(imgui, 'PushItemWidth', function(width) widths[#widths + 1] = width end)
H.tab(1); H.frames(1)
window.IsResized = resized
rawset(imgui, 'GetContentRegionAvail', available)
rawset(imgui, 'PushItemWidth', nil)
assert(#widths > 0)
for _, width in ipairs(widths) do assert(width >= 70 and width <= 180) end

-- Indicator is a game window with a theme title, outlined text and configurable hiding/fade.
local plain, outlined, hidden = window.Plain, text.Outlined, game.IsHidden
local drawn, lines = 0, 0
window.Plain = function(name, open, flags, draw, options)
    assert(name == 'trigger.indicator' and options.title == 'Trigger')
    assert(options.kind == nil or options.kind == window.Game)
    assert(options.alpha == 1, 'disabled fade appears immediately')
    drawn = drawn + 1
    draw()
end
text.Outlined = function(words) assert(words:find('Sheep Song', 1, true)); lines = lines + 1 end
local hide = false
game.IsHidden = function(rules) assert(rules == o.hide); return hide end
o.showIndicator[1], o.fadeInOut[1] = true, false
indicator.sample = true; indicator.Frame(os.clock())
assert(drawn == 1 and lines == 1)
hide = true
indicator.sample = true; indicator.Frame(os.clock())
assert(drawn == 1, 'hidden indicator not drawn')
hide = false
indicator.Frame(os.clock())
assert(drawn == 1, 'disabled fade leaves no lingering window')
window.Plain, text.Outlined, game.IsHidden = plain, outlined, hidden
H.print('trigger WinXI: shared theme, no appearance tab, indicator controls, tooltips, widths, indicator text/title/hide/fade', true)
