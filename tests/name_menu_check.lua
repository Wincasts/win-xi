-- The settings menu, following guis/name.menu.
local imgui, widgets = require('imgui'), require('winxi.widgets')
local custom, controls = require('custom'), require('controls')
local options = H.options()
AshitaCore.GetPluginManager = function() return { IsLoaded = function() return false end } end
local headers, tabs, ids, boxes, marks, widths = {}, {}, {}, {}, {}, {}
local inside, lastOffset = false, nil
local originalHeader, originalTab = widgets.Header, imgui.BeginTabItem
widgets.Header = function(text, first) headers[#headers + 1] = text; return originalHeader(text, first) end
imgui.BeginTabItem = function(label, ...) tabs[#tabs + 1] = label; return originalTab(label, ...) end
imgui.BeginGroup = function() boxes[#boxes + 1] = true; inside = true end
imgui.EndGroup = function() inside = false end
imgui.Checkbox = function(id) ids[id] = true; return false end
imgui.InputInt = function(id) ids[id] = true; return false end
imgui.SliderInt = function(id) ids[id] = true; return false end
imgui.InputText = function(id) ids[id] = true; return false end
imgui.BeginCombo = function(id) ids[id] = true; return false end
imgui.RadioButton = function(id) ids[id] = true; return false end
imgui.GetFontSize = function() return 14 end
local contentRight = 400
imgui.GetWindowPos = function() return 100, 200 end
imgui.GetItemRectMax = function() return 100 + contentRight, 220 end
imgui.SetNextItemWidth = function(width) widths[#widths + 1] = width end
imgui.SameLine = function(offset) lastOffset = offset end
imgui.TextDisabled = function(text) if text == '(?)' and inside then marks[#marks + 1] = lastOffset end end
imgui.GetContentRegionAvail = function() error('Auto-size must not feed back into option widths') end
H.tab(1); H.command('/name'); H.frames(1)
headers, tabs, boxes, marks = {}, {}, {}, {}
H.frames(1); H.command('/name')
H.print('public tabs: Nameplates, Filters, Statuses and NM Tracking', table.concat(tabs, '|') == 'Nameplates|Filters|Statuses|NM Tracking')
H.print('mockup sections', table.concat(headers, '|') == 'Name Appearance|Player Icons|Mob Nameplates|Check')
H.print('each section open, its settings in a group', #boxes == 4)
local aligned = #marks == 16
for _, position in ipairs(marks) do aligned = aligned and position == marks[1] end
H.print('all tooltip markers in one column, past the widest option', aligned, (marks[1] or 0) > contentRight)
H.print('font selector, bold, numeric sizes and four outline choices', ids['##name.font'], ids['##name.fontBold'], ids['##name.fontSize'], ids['##name.minSize'], ids['0##name.outline0'], ids['3##name.outline3'])
assert(ids['##name.showMobLevel'] and ids['##name.showAggroIcons'] and ids['##name.showMobLetter'])
assert(not options.showMobLetter[1], 'experimental letters must start disabled')
assert(ids['##name.doubleMobLetters'] == nil and not options.doubleMobLetters[1], 'Double Letters is hidden while Mob Letters is off, and starts off')
assert(ids['##name.monsterFormat'])
assert(ids['##name.trackedNm'] == nil, 'NM tracking has a tab of its own')
assert(ids['##name.targetFormat'] == nil and ids['##name.checkedFormat'] == nil)
H.print('mob toggles and format exposed; player, target and checked formats hidden', ids['##name.nameFormat'] == nil,
    ids['##name.showMobLevel'], ids['##name.showAggroIcons'], ids['##name.monsterFormat'], ids['##name.targetFormat'] == nil, ids['##name.checkedFormat'] == nil)
H.print('preferred baseline retained', options.font == 'corbeli.ttf', options.fontBold[1], options.checkSize[1] == 75)
local oldPlayers = options.showPlayers[1]
H.command('/name custom off'); H.command('/name show all')
H.print('verbs only say the help', options.showPlayers[1] == oldPlayers)
headers, tabs = {}, {}
H.tab(2); H.command('/name'); H.frames(1)
headers, boxes, marks = {}, {}, {}
H.frames(1); H.command('/name')
-- Status is there without the plugin too: the custom names' state and the diagnostic log
H.print('Filters retained', table.concat(headers, '|') == 'Players|Pets|NPCs And Monsters|Target|Status')
local filterAligned = #boxes == 5 and #marks == 11
for _, position in ipairs(marks) do filterAligned = filterAligned and position == marks[1] end
H.print('Filters use groups and one help column', filterAligned)
contentRight = 320
custom.DrawSettings(options)
boxes, marks = {}, {}
for frame = 1, 10 do custom.DrawSettings(options) end
local compact = #boxes == 40
for _, position in ipairs(marks) do compact = compact and position == 328 end
H.print('content can shrink; repeated frames do not expand window', compact)
local realCheckbox, realInputText = imgui.Checkbox, imgui.InputText
imgui.Checkbox = function(id, value)
    if id == '##name.showMobLevel' or id == '##name.showAggroIcons' then value[1] = false; return true end
    return realCheckbox(id, value)
end
imgui.InputText = function(id, value)
    if id == '##name.monsterFormat' then value[1] = '[name] ([distance]y)'; return true end
    return realInputText(id, value)
end
custom.DrawSettings(options)
assert(not options.showMobLevel[1] and not options.showAggroIcons[1])
assert(options.monsterFormat[1] == '[name] ([distance]y)', 'format editor must update character settings')
custom.Settle(options)
assert(not options.showMobLevel[1] and not options.showAggroIcons[1], 'saved false toggles must survive settling')
assert(options.monsterFormat[1] == '[name] ([distance]y)')
imgui.Checkbox, imgui.InputText = realCheckbox, realInputText
H.print('mob controls edit saved settings; off toggles and custom strings survive reload settling', true)
ids, widths = {}, {}
options.showIcons[1], options.showStars[1], options.showCheckDetails[1] = false, false, false
custom.DrawSettings(options)
H.print('dependent settings hidden', ids['##name.iconSize'] == nil, ids['##name.iconSpacing'] == nil, ids['##name.checkSize'] == nil, ids['##name.abbreviateDifficulty'] == nil, ids['##name.checkDetailsInWords'] == nil)
controls.Width()
H.print('option width scope does not leak', widths[#widths] == 260)
local wraps = H.calls.PushTextWrapPos or 0
imgui.IsItemHovered = function() return true end
controls.Mark('Wrapped help')
H.print('tooltips stay wrapped', (H.calls.PushTextWrapPos or 0) == wraps + 1)
imgui.IsItemHovered = function() return false end
local tagged, realLabel = {}, widgets.Label
widgets.Label = function(text, experimental) tagged[text] = experimental == true; return realLabel(text, experimental) end
headers, boxes, ids = {}, {}, {}
H.tab(4); H.command('/name'); H.frames(1); H.command('/name')
widgets.Label = realLabel
H.print('NM Tracking tab: one box, the dropdown, marked experimental', table.concat(headers, '|') == 'Tracked Monster', #boxes == 1,
    ids['##name.trackedNm'], tagged['Tracked NM'], ids['##name.huntScale'] == nil, ids['##name.labelPlaceholders'] == nil)
