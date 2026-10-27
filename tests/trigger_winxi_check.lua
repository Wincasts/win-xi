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

-- The game: a character in an area, for the Triggers tab, which reads the server's triggermobs set
-- (the repository's data) for what the area's mobs do
require('winxi.gamedata').Root('addons/libs/winxi/data/')
local core = AshitaCore
local realMemory = core:GetMemoryManager()
local party = { GetMemberTargetIndex = function() return 0 end, GetMemberName = function() return 'Tester' end, GetMemberZone = function() return 102 end }
local memory = setmetatable({ GetParty = function() return party end }, { __index = realMemory })
AshitaCore = setmetatable({ GetMemoryManager = function() return memory end }, { __index = core })

-- Every tab is described rows, whose control widths come from the rows' own width stack, without leaking it.
o.showIndicator[1] = true
assert(app.spec.settingsLabel == 'Notifications')
assert(app.spec.tabs[1].label == 'Triggers' and app.spec.tabs[2].label == 'Toast')
for tab = 1, 3 do
    H.tab(tab)
    local pushes, pops = H.calls.PushItemWidth or 0, H.calls.PopItemWidth or 0
    H.frames(1)
    assert((H.calls.PushItemWidth or 0) > pushes, 'control widths in tab ' .. tab)
    assert((H.calls.PushItemWidth or 0) - pushes == (H.calls.PopItemWidth or 0) - pops)
end

-- The rows of each tab: their names, sentences, parents and experimental tags.
local rows, beginRow = {}, widgets.BeginRow
widgets.BeginRow = function(name, sentence, spec)
    rows[name] = { sentence = sentence, experimental = spec ~= nil and spec.experimental or false, parent = spec ~= nil and spec.parent or nil }
    return beginRow(name, sentence, spec)
end
H.tab(1); H.frames(1)
assert(rows['Overlap Sounds'] and rows['Overlap Sounds'].experimental, 'Overlap Sounds is tagged experimental')
assert(rows['Tell Received'] and rows['Sound'] and rows['HP Threshold'] and rows['Items'] and rows['Volume'], 'the notification rows')
assert(rows['Sound'].parent == o.events.drop.enabled and rows['Items'].parent == o.events.drop.enabled, 'the rows under an event take its switch as parent')
assert(rows['HP Threshold'].parent == o.events.lowhp.enabled, 'the threshold under its event')
H.tab(2); rows = {}; H.frames(1)
assert(not rows['Enable Toast'] and not rows['Grow From'], 'toast controls are separate from triggers')
assert(rows['Mob Type'] and rows['Action'] and rows['Create Trigger'] and rows['Create Trigger'].experimental, 'the New Trigger rows, Create tagged experimental')
H.tab(3); rows = {}; H.frames(1)
assert(rows['Enable Toast'] and rows['Duration'] and rows['Fade In And Out'] and rows['Grow From'] and rows['Hide While Map Open'] and rows['Hide With Game Interface'], 'toast controls in Toast tab')
assert(rows['Enable Toast'].parent == nil, 'the switch is under nothing')
for _, name in ipairs({ 'Duration', 'Fade In And Out', 'Grow From', 'Hide While Map Open', 'Hide During Events' }) do
    assert(rows[name].parent == o.showIndicator, name .. ' is under Enable Toast')
end
rows = {}
o.showIndicator[1] = false
local greyed = H.calls.BeginDisabled or 0
H.frames(1)
assert(rows['Enable Toast'] and rows['Duration'] and rows['Grow From'] and rows['Hide While Map Open'], 'disabled toast keeps its rows')
assert((H.calls.BeginDisabled or 0) - greyed == 8, 'and greys the eight under the switch')
o.showIndicator[1] = true
widgets.BeginRow = beginRow

-- Every control of the Notifications tab is drawn inside a described row: the rows line the controls up.
local inRow, outside, controls = false, {}, 0
local endRow = widgets.EndRow
widgets.BeginRow = function(...) inRow = true; return beginRow(...) end
widgets.EndRow = function(...) inRow = false; return endRow(...) end
local function watch(name)
    local original = imgui[name]
    rawset(imgui, name, function(id, ...)
        controls = controls + 1
        if not inRow then outside[#outside + 1] = name .. ' ' .. tostring(id) end
        return original(id, ...)
    end)
end
watch('BeginCombo'); watch('SliderInt'); watch('InputText'); watch('Checkbox')
H.tab(1); H.frames(1)
for _, name in ipairs({ 'BeginCombo', 'SliderInt', 'InputText', 'Checkbox' }) do rawset(imgui, name, nil) end
widgets.BeginRow, widgets.EndRow = beginRow, endRow
assert(#outside == 0, 'controls outside rows: ' .. table.concat(outside, ', '))
-- 11 switches and 11 sound lists, two thresholds, the items, the volume and overlap
assert(controls == 11 * 2 + 2 + 1 + 2, 'every control in a row: ' .. controls)

-- There is no other help: no (?) marks and no tooltips on any tab; every row says its piece under its name.
local tooltip = require('winxi.tooltip')
local hover, originalHover = 0, tooltip.Hover
tooltip.Hover = function() hover = hover + 1 end
local marks, sentences = 0, 0
local disabledText = imgui.TextDisabled
rawset(imgui, 'TextDisabled', function(words) if words == '(?)' then marks = marks + 1 end return disabledText(words) end)
widgets.BeginRow = function(name, sentence, spec)
    assert(type(sentence) == 'string' and sentence ~= '', name .. ' has its sentence')
    sentences = sentences + 1
    return beginRow(name, sentence, spec)
end
local tips = H.calls.BeginTooltip or 0
H.ret.IsItemHovered = { true }
for tab = 1, 3 do H.tab(tab); H.frames(1) end
H.ret.IsItemHovered = { false }
widgets.BeginRow = beginRow
rawset(imgui, 'TextDisabled', nil)
tooltip.Hover = originalHover
assert(hover == 0 and marks == 0 and (H.calls.BeginTooltip or 0) == tips, 'no help marks or tooltips, hovered or not')
assert(sentences >= 27 + 3 + 9, 'rows with sentences on every tab: ' .. sentences)

-- The rows set every control's width, in a resized window as in one fitted: the addon pushes none of its own.
local resized, available = window.IsResized, imgui.GetContentRegionAvail
window.IsResized = function() return true end
rawset(imgui, 'GetContentRegionAvail', function() return 180, 100 end)
local pushes, begun = 0, 0
rawset(imgui, 'PushItemWidth', function(width) assert(type(width) == 'number' and width > 0); pushes = pushes + 1 end)
widgets.BeginRow = function(...) begun = begun + 1; return beginRow(...) end
H.tab(1); H.frames(1)
window.IsResized = resized
rawset(imgui, 'GetContentRegionAvail', available)
rawset(imgui, 'PushItemWidth', nil)
widgets.BeginRow = beginRow
assert(begun > 0 and pushes == begun, 'the rows push every width, the addon none')

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
H.print('trigger WinXI: shared theme, no appearance tab, described rows on every tab, no help marks, row widths, indicator text/title/hide/fade', true)
