-- Public ImGui-only testing menu, following guis/name.menu.
local imgui, widgets = require('imgui'), require('winxi.widgets')
local custom, controls = require('custom'), require('controls')
local options = H.options()
AshitaCore.GetPluginManager = function() return { IsLoaded = function() return false end } end
local headers, tabs, ids, boxes, marks, widths = {}, {}, {}, {}, {}, {}
local inside, lastOffset = false, nil
local originalHeader, originalTab = widgets.Header, imgui.BeginTabItem
widgets.Header = function(text, first) headers[#headers + 1] = text; return originalHeader(text, first) end
imgui.BeginTabItem = function(label, ...) tabs[#tabs + 1] = label; return originalTab(label, ...) end
imgui.BeginChild = function(id, size) boxes[#boxes + 1] = { id = id, width = size[1] }; inside = true; return true end
imgui.EndChild = function() inside = false end
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
H.print('public tabs: Nameplates and Filters only', table.concat(tabs, '|') == 'Nameplates|Filters')
H.print('mockup sections', table.concat(headers, '|') == 'Name Appearance|Player Icons|Check')
local equal = #boxes == 3
for _, box in ipairs(boxes) do equal = equal and box.width == 440 end
H.print('equal options boxes sized to longest content row plus help', equal)
local aligned = #marks == 12
for _, position in ipairs(marks) do aligned = aligned and position == 408 end
H.print('all tooltip markers right-aligned inside boxes', aligned)
H.print('font selector, bold, numeric sizes and four outline choices', ids['##name.font'], ids['##name.fontBold'], ids['##name.fontSize'], ids['##name.minSize'], ids['0##name.outline0'], ids['3##name.outline3'])
H.print('saved formats hidden', ids['##name.nameFormat'] == nil, ids['##name.monsterFormat'] == nil, ids['##name.targetFormat'] == nil, ids['##name.checkedFormat'] == nil)
H.print('experimental controls hidden', ids['##name.gdiFonts'] == nil, ids['##name.gdiFamily'] == nil)
H.print('preferred baseline retained', options.font == 'corbeli.ttf', options.fontBold[1], options.checkSize[1] == 75)
local oldPlayers = options.showPlayers[1]
H.command('/name gdi on'); H.command('/name custom off'); H.command('/name show all')
H.print('text controls disabled and GDI remains off', not options.gdiFonts[1], options.showPlayers[1] == oldPlayers)
headers, tabs = {}, {}
H.tab(2); H.command('/name'); H.frames(1)
headers, boxes, marks = {}, {}, {}
H.frames(1); H.command('/name')
H.print('Filters retained', table.concat(headers, '|') == 'Players|Pets|NPCs And Monsters|Target')
local filterAligned = #boxes == 4 and #marks == 9
for _, box in ipairs(boxes) do filterAligned = filterAligned and box.width == 440 end
for _, position in ipairs(marks) do filterAligned = filterAligned and position == 408 end
H.print('Filters use matching boxes and aligned help column', filterAligned)
contentRight = 320
custom.DrawSettings(options)
boxes, marks = {}, {}
for frame = 1, 10 do custom.DrawSettings(options) end
local compact = #boxes == 30
for _, box in ipairs(boxes) do compact = compact and box.width == 360 end
for _, position in ipairs(marks) do compact = compact and position == 328 end
H.print('content can shrink; repeated frames do not expand window', compact)
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
