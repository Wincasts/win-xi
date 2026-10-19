-- Per-type settings layout and legacy-setting compatibility.
local imgui, widgets = require('imgui'), require('winxi.widgets')
local custom, controls, types = require('custom'), require('controls'), require('name_types')
local options = H.options()
AshitaCore.GetPluginManager = function() return { IsLoaded = function() return false end } end
local headers, tabs, ids, marks, widths, disabledIds = {}, {}, {}, {}, {}, {}
local section, locations = nil, {}
local expanded = { ['Check Details##name.checkOptions'] = true }
local inside, offset, disabled = false, nil, false
widgets.Header = function(text, first, collapsed)
    section = text
    headers[#headers + 1] = text
    return not collapsed or expanded[text] == true
end
local originalTab = imgui.BeginTabItem
imgui.BeginTabItem = function(label, ...) tabs[#tabs + 1] = label; return originalTab(label, ...) end
imgui.BeginGroup, imgui.EndGroup = function() inside = true end, function() inside = false end
local lastId, help = nil, {}
local mark = controls.Mark
controls.Mark = function(text) help[lastId or ''] = text; mark(text) end
local function record(id)
    lastId = id; ids[id] = true; disabledIds[id] = disabled; locations[id] = section; return false
end
imgui.Checkbox, imgui.InputInt, imgui.SliderInt = record, record, record
imgui.InputText, imgui.BeginCombo, imgui.RadioButton, imgui.Button = record, record, record, record
imgui.TreeNode = function(id) ids[id] = true; return expanded[id] == true end
imgui.TreePop = function() end
imgui.BeginDisabled, imgui.EndDisabled = function(value) disabled = value end, function() disabled = false end
imgui.GetFontSize = function() return 14 end
local right = 400
imgui.GetWindowPos = function() return 100, 200 end
imgui.GetItemRectMax = function() return 100 + right, 220 end
imgui.SetNextItemWidth = function(value) widths[#widths + 1] = value end
imgui.SameLine = function(value) offset = value end
imgui.TextDisabled = function(text) if text == '(?)' and inside then marks[#marks + 1] = offset end end
imgui.GetContentRegionAvail = function() error('Window widths must not feed back into auto-sizing') end
local function clear() headers, tabs, ids, marks, disabledIds, locations = {}, {}, {}, {}, {}, {} end
H.tab(2); H.command('/name'); H.frames(1)
clear(); H.frames(1); H.command('/name')
assert(table.concat(tabs, '|') == 'General|Names|Health Bars|Statuses|Visibility', 'NM Tracking waits for /name dev')
H.command('/name dev'); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(tabs, '|') == 'General|Names|Health Bars|Statuses|Visibility|NM Tracking', '/name dev shows NM Tracking')
H.command('/name dev'); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(tabs, '|') == 'General|Names|Health Bars|Statuses|Visibility', 'a second /name dev hides it')
assert(table.concat(headers, '|') == 'General Name Appearance|Player Names|Enemy Names|NPC Names|Diagnostics')
assert(ids['##name.font'] and ids['##name.fontBold'] and ids['##name.subtargetScale'])
assert(ids['##name.fontSize'] and ids['##name.minSize'], 'shared size controls belong in General')
for _, removed in ipairs({ 'showIcons', 'showMobLevel', 'showAggroIcons',
    'showMobLetter', 'doubleMobLetters' }) do
    assert(not ids['##name.' .. removed], 'obsolete global/toggle control must be absent: ' .. removed)
end
for _, key in ipairs(types.List) do
    for _, field in ipairs({ 'showHealthBar', 'healthBarWidth', 'healthBarHeight' }) do
        local id = '##name.' .. key .. '.' .. field
        assert(not ids[id], 'obsolete per-type bar control must be absent')
    end
    assert(ids['Colour Overrides##name.colours.' .. key], 'each category has colour overrides')
    assert(not ids['##name.' .. key .. '.healthBarPreview'], 'preview controls must be absent')
    assert(not ids['##name.' .. key .. '.fontSize'] and not ids['##name.' .. key .. '.minSize'], 'category size controls must be absent')
end
assert(locations['##name.nameFormat'] == 'Player Names'
    and locations['##name.monsterFormat'] == 'Enemy Names' and locations['##name.npcFormat'] == 'NPC Names',
    'category format editors remain in their own sections')
assert(not ids['##name.diagnosticsEnabled'])
for _, position in ipairs(marks) do assert(position == marks[1] and position > right) end
for _, field in ipairs({ 'showHealthBar', 'healthBarsCombatOnly', 'healthBarWidth', 'healthBarHeight' }) do
    assert(not ids['##name.' .. field], 'the health bars have a tab of their own, not a place under General')
end
H.print('Names: shared General text controls, per-category colour overrides, no obsolete toggles', true)

for _, key in ipairs({ 'nameFormat', 'monsterFormat', 'npcFormat' }) do
    assert(not ids['Tokens & Examples##name.formatHelp.' .. key], 'token dropdown must be absent')
    local tip = assert(help['##name.' .. key], 'format editor must have (?) help')
    assert(tip:find('[name]', 1, true) and tip:find('[distance]', 1, true))
    local example = assert(tip:match('Example format:\n([^\n]+)\nExample result:'))
    local compiled = require('format').Compile(example)
    assert(compiled.distance, 'each category has a usable example format')
    for _, part in ipairs(compiled) do
        assert(part.kind ~= 'text' or not part.text:find('[', 1, true), 'example tokens must parse')
    end
end
assert(help['##name.nameFormat']:find('[icons]', 1, true))
assert(help['##name.monsterFormat']:find('[letters]', 1, true))
assert(help['##name.npcFormat']:find('Mog House (4.2y)', 1, true))
controls.Mark = mark
options.showHealthBar[1] = true
clear(); custom.DrawHealthBars(options)
assert(not disabledIds['##name.healthBarWidth'] and not disabledIds['##name.healthBarsCombatOnly'])
options.showHealthBar[1] = false
local input = imgui.InputInt
imgui.InputInt = function(id, value)
    if id == '##name.fontSize' then value[1] = 28; return true end
    if id == '##name.healthBarHeight' then value[1] = 11; return true end
    return input(id, value)
end
local barWidth = options.healthBarWidth[1]
custom.DrawSettings(options)
custom.DrawHealthBars(options)
imgui.InputInt = input
custom.Settle(options)
assert(options.fontSize[1] == 28 and options.healthBarHeight[1] == 11 and options.healthBarWidth[1] == barWidth)
H.print('Shared name-size and bar dimensions remain independent', true)

imgui.ColorEdit4 = record
for _, key in ipairs(types.List) do expanded['Colour Overrides##name.colours.' .. key] = true end
clear(); custom.DrawSettings(options)
for _, key in ipairs(types.List) do
    for _, state in ipairs(require('name_colours').States[key]) do
        local id = '##name.colours.' .. key .. '.' .. state[1]
        -- a colour is greyed out while its state is off; Normal and Alliance are on in the preferred defaults
        assert(ids[id .. '.enabled'] and ids[id .. '.color'] and not disabledIds[id .. '.color'] == options.nameColours[key][state[1]].enabled[1])
    end
end
options.nameColours.enemyNames.callForHelp.enabled[1] = true
clear(); custom.DrawSettings(options)
assert(not disabledIds['##name.colours.enemyNames.callForHelp.color'])
imgui.Button = function(id) return id == 'Use Game Colours##name.colours.reset.enemyNames' end
custom.DrawSettings(options)
assert(not options.nameColours.enemyNames.callForHelp.enabled[1], 'reset restores game colours')
imgui.Button = record
for _, key in ipairs(types.List) do expanded['Colour Overrides##name.colours.' .. key] = false end

imgui.InputText = function(id, value)
    if id == '##name.nameFormat' then value[1] = 'Player: [name]'; return true end
    if id == '##name.monsterFormat' then value[1] = '[level] [name] [letters: type=double]'; return true end
    if id == '##name.npcFormat' then value[1] = '[name] ([distance]y)'; return true end
    return record(id)
end
custom.DrawSettings(options); custom.Settle(options)
assert(options.monsterFormat[1] == '[level] [name] [letters: type=double]')
imgui.InputText = record
imgui.Button = function(id) return id == 'Reset##name.resetFormat' end
local saves = 0
custom.DrawSettings(options, function() saves = saves + 1 end)
assert(saves == 1 and options.monsterFormat[1] == '[aggro] [name] [letters]')
assert(options.nameFormat[1] == 'Player: [name]' and options.npcFormat[1] == '[name] ([distance]y)')
imgui.Button = record
imgui.BeginCombo = function(id) return id == '##name.checkDetailsInWords' end
imgui.Selectable = function(id) return id:find('Text Only', 1, true) ~= nil end
custom.DrawSettings(options); assert(options.checkDetailsInWords[1])
imgui.BeginCombo = record
H.print('Category format editors/reset preserve each other', true)

H.tab(3); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Health Bars|Entity Types')
for _, key in ipairs({ 'self', 'party', 'alliance', 'players', 'myPet', 'pets', 'npcs', 'monsters' }) do
    local id = '##name.healthBarTypes.' .. key
    assert(ids[id] and locations[id] == 'Entity Types' and disabledIds[id], 'Entity Types has ' .. key .. ', waiting for Enabled')
end
for _, id in ipairs({ '##name.showHealthBar', '##name.healthBarsCombatOnly', '##name.healthBarWidth', '##name.healthBarHeight' }) do
    assert(ids[id] and locations[id] == 'Health Bars', 'Health Bars tab has ' .. id)
end
assert(disabledIds['##name.healthBarWidth'] and disabledIds['##name.healthBarsCombatOnly'], 'the rest wait for Enabled')
local et = require('entity_types')
local mask = T{ 0xFF }
imgui.Checkbox = function(id, value) if id == '##name.healthBarTypes.monsters' then value[1] = false; return true end; return false end
assert(et.Draw('healthBarTypes', mask) and mask[1] == 0x7F, 'unticking Monsters takes its bit out')
imgui.Checkbox = function(id, value) if id == '##name.healthBarTypes.monsters' then value[1] = true; return true end; return false end
assert(et.Draw('healthBarTypes', mask) and mask[1] == 0xFF, 'and ticking it puts it back')
imgui.Checkbox = record
assert(et.Settle(T{ 'bad' })[1] == 0xFF and et.Settle(nil)[1] == 0xFF and et.Settle(T{ 0x1FF })[1] == 0xFF and et.Settle(T{ 0x12 })[1] == 0x12, 'a bad mask is every kind')
H.print('Health Bars: a tab of its own, third, with Enabled, Combat Only, width and height, and Entity Types', true)

-- General: the preset, Custom Nameplates, and the health bars' and statuses' switches
local general = require('general')
H.tab(1); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'General')
for _, id in ipairs({ '##name.preset', '##name.drawNames', '##name.general.showHealthBar', '##name.general.showStatuses' }) do
    assert(ids[id] and locations[id] == 'General', 'General has ' .. id)
end
local presets = {}
for _, preset in ipairs(general.Presets) do presets[#presets + 1] = preset.label end
assert(table.concat(presets, '|') == 'Default|Minimal|Robust|Immersive')
local fontBefore, sizeBefore = options.font, options.fontSize[1]
assert(general.Apply(options, 'minimal') and general.Matching(options).key == 'minimal')
assert(options.monsterFormat[1] == '[name]' and not options.showHealthBar[1] and not options.showStatuses[1] and not options.showCheckDetails[1])
assert(general.Apply(options, 'robust') and general.Matching(options).key == 'robust')
assert(options.showHealthBar[1] and not options.healthBarsCombatOnly[1] and options.monsterFormat[1]:find('[letters]', 1, true) and options.monsterFormat[1]:find('[distance', 1, true))
assert(general.Apply(options, 'immersive') and general.Matching(options).key == 'immersive')
assert(options.showHealthBar[1] and options.healthBarsCombatOnly[1] and options.monsterFormat[1] == '[name]' and not options.showStatuses[1])
assert(options.font == fontBefore and options.fontSize[1] == sizeBefore, 'a preset leaves the font and sizes')
options.npcFormat[1] = '[name] ([distance]y)'
assert(general.Matching(options) == nil, 'an edit away from every preset is Custom')
local applied = 0
imgui.BeginCombo = function(id) return id == '##name.preset' end
imgui.Selectable = function(id) return id == 'Default##name.preset.default' end
general.DrawSettings(options, function() applied = applied + 1 end)
imgui.BeginCombo, imgui.Selectable = record, function() return false end
assert(applied == 1 and general.Matching(options).key == 'default', 'choosing a preset in the list applies and saves it')
assert(options.drawNames[1] and general.Drawing(options))
options.drawNames[1] = false; clear(); general.DrawSettings(options)
assert(disabledIds['##name.general.showHealthBar'] and disabledIds['##name.general.showStatuses'], 'bars and statuses wait for Custom Nameplates')
options.drawNames[1] = true
H.print('General: presets apply, match and leave the rest; Custom Nameplates and the bars\' and statuses\' switches', true)
H.tab(5); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Players|Pets|NPCs & Monsters|Target')
H.command('/name diag on')
expanded.Diagnostics = true
H.tab(2); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(ids['##name.diagnosticsEnabled'] and ids['Write Log##name.diag.write'])
H.command('/name diag off')
right = 320
custom.DrawSettings(options)
for frame = 1, 10 do
    marks = {}; custom.DrawSettings(options)
    for _, position in ipairs(marks) do assert(position == 328) end
end
controls.Width(); assert(widths[#widths] == 260)
local wraps = H.calls.PushTextWrapPos or 0
imgui.IsItemHovered = function() return true end
controls.Mark('Wrapped help')
assert((H.calls.PushTextWrapPos or 0) == wraps + 1)
imgui.IsItemHovered = function() return false end
imgui.GetFrameHeightWithSpacing = function() return 20 end
AshitaCore.GetResourceManager = function() return { GetString = function() return '' end } end
H.tab(4); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Display|Entity Types|Selected Statuses')
for _, key in ipairs({ 'self', 'party', 'alliance', 'players', 'myPet', 'pets', 'npcs', 'monsters' }) do
    assert(ids['##name.statusTypes.' .. key] and locations['##name.statusTypes.' .. key] == 'Entity Types', 'statuses\' Entity Types has ' .. key)
end
assert(ids['##name.statusOffsetX'] and ids['##name.statusOffsetY'] and not ids['##name.statusTimers'], 'X and Y Offset in Display, and no Timers')
assert(ids['##name.statusIcons'] and locations['##name.statusIcons'] == 'Display', 'Icons is in Statuses → Display')
H.command('/name dev'); H.tab(6); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Tracked Monster')
local levels = require('levels')
local original = levels.Placeholders
levels.Placeholders = function() return {} end
options.trackedNm[1] = 'Test NM'
clear(); custom.DrawTracking(options)
assert(table.concat(headers, '|') == 'Tracked Monster|Placeholder Options')
levels.Placeholders = original
H.print('Visibility, diagnostics, statuses/tracking and stable aligned/wrapped layouts retained', true)
