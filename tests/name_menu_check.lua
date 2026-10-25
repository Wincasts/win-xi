-- Per-type settings layout and legacy-setting compatibility.
local imgui, widgets = require('imgui'), require('winxi.widgets')
local custom, controls, types = require('custom'), require('controls'), require('name_types')
local customSettings = require('custom_settings')
local options = H.options()
AshitaCore.GetPluginManager = function() return { IsLoaded = function() return false end } end
local headers, tabs, ids, marks, widths, disabledIds = {}, {}, {}, {}, {}, {}
local section, locations = nil, {}
local expanded = {}
local inside, offset, disabled = false, nil, false
local disabledStack, order = {}, {}
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
    order[#order + 1] = id
    lastId = id; ids[id] = true; disabledIds[id] = disabled; locations[id] = section; return false
end
imgui.Checkbox, imgui.InputInt, imgui.SliderInt = record, record, record
imgui.InputText, imgui.BeginCombo, imgui.RadioButton, imgui.Button = record, record, record, record
imgui.TreeNode = function(id)
    assert(not id:find('Help / Examples', 1, true), 'no Help / Examples dropdowns: ' .. id)
    ids[id] = true; lastId = id; return expanded[id] == true
end
imgui.TreePop = function() end
imgui.BeginDisabled = function(value)
    disabledStack[#disabledStack + 1] = disabled
    disabled = disabled or value
end
imgui.EndDisabled = function()
    assert(#disabledStack > 0, 'balanced disabled groups')
    disabled = table.remove(disabledStack)
end
imgui.GetFontSize = function() return 14 end
local right = 400
imgui.GetWindowPos = function() return 100, 200 end
imgui.GetItemRectMax = function() return 100 + right, 220 end
imgui.SetNextItemWidth = function(value) widths[#widths + 1] = value end
imgui.SameLine = function(value) offset = value end
imgui.TextDisabled = function(text) if text == '(?)' and inside then marks[#marks + 1] = offset end end
imgui.GetContentRegionAvail = function() error('Window widths must not feed back into auto-sizing') end
local function clear() headers, tabs, ids, marks, disabledIds, locations, order = {}, {}, {}, {}, {}, {}, {} end
H.tab(2); H.command('/name'); H.frames(1)
clear(); H.frames(1); H.command('/name')
assert(table.concat(tabs, '|') == 'General|Names|Bars|Check Details|Statuses|Visibility', 'NM Tracking waits for /name dev')
H.command('/name dev'); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(tabs, '|') == 'General|Names|Bars|Check Details|Statuses|Visibility|NM Tracking', '/name dev shows NM Tracking')
H.command('/name dev'); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(tabs, '|') == 'General|Names|Bars|Check Details|Statuses|Visibility', 'a second /name dev hides it')
assert(table.concat(headers, '|') == 'General Name Appearance|Player Names|Enemy Names|NPC Names|Distance Thresholds')
assert(not ids['##name.partyIcons'] and not ids['##name.showVendorIcons'], 'party and vendor signs are tokens, not settings')
assert(ids['##name.font'] and ids['##name.fontBold'] and ids['Smooth Font##name.fontSmooth'] and ids['##name.subtargetScale'] and ids['##name.textOutlineOpacity'])
for index, id in ipairs(order) do
    if id == '##name.fontBold' then
        assert(order[index + 1] == 'Smooth Font##name.fontSmooth', 'Smooth Font is beside Bold')
    end
end
assert(ids['##name.fontSize'] and ids['##name.minSize'], 'shared size controls belong in General')
assert(ids['0##name.iconOutline0'] and ids['3##name.iconOutline3'] and ids['##name.iconOutlineOpacity'])
assert(options.iconOutline[1] == 1 and options.iconOutlineOpacity[1] == 100)
assert(ids['##name.distanceColours'] and not ids['##name.crowdDeclutter'], 'Crowd Decluttering is in Visibility')
assert(disabledIds['##name.distanceWarning'], 'opt-in policy controls start disabled')
for _, key in ipairs({ 'nameFormat', 'monsterFormat', 'npcFormat' }) do
    local reset = 'Reset##name.' .. (key == 'monsterFormat' and 'resetFormat' or ('reset.' .. key))
    for index, id in ipairs(order) do
        if id == '##name.' .. key then
            assert(order[index + 1] == reset and locations[reset] == locations[id], 'Reset beside ' .. key)
        end
    end
end
local outlineOptions = custom.Defaults({})
outlineOptions.iconOutline, outlineOptions.iconOutlineOpacity = {9}, {-1}
custom.Settle(outlineOptions)
assert(outlineOptions.iconOutline[1] == 3 and outlineOptions.iconOutlineOpacity[1] == 0)
outlineOptions.iconOutline, outlineOptions.iconOutlineOpacity = false, {'bad'}
custom.Settle(outlineOptions)
assert(outlineOptions.iconOutline[1] == 1 and outlineOptions.iconOutlineOpacity[1] == 100)
assert(ids['##name.playerIconSource'] and locations['##name.playerIconSource'] == 'Player Names',
    'player artwork source belongs beside Player Format, separate from party role icons')
assert(options.playerIconSource[1] == 'game', 'new and migrated settings default to active DATs')
local sourceOptions = custom.Defaults({})
for _, source in ipairs(require('icons').Sources) do
    sourceOptions.playerIconSource = { source.key }
    custom.Settle(sourceOptions)
    assert(sourceOptions.playerIconSource[1] == source.key, 'retain each valid saved source')
end
for _, bad in ipairs({ 'bad', 123, false, { 'missing' }, { 123 } }) do
    sourceOptions.playerIconSource = bad
    custom.Settle(sourceOptions)
    assert(sourceOptions.playerIconSource[1] == 'game', 'repair malformed or unknown saved sources')
end
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
for _, field in ipairs({ 'showHealthBar', 'healthBarsCombatOnly', 'healthBarWidth', 'healthBarHeight',
        'showCastBar', 'showCheckDetails', 'checkSize', 'abbreviateDifficulty', 'checkDetailsInWords' }) do
    assert(not ids['##name.' .. field], 'bars and check details have tabs of their own, not a place under Names')
end
H.print('Names: shared General text controls, per-category colour overrides, no obsolete toggles', true)

local tokens = {
    nameFormat = { 'name', 'icons', 'distance', 'space' },
    monsterFormat = { 'name', 'level', 'aggro', 'checked', 'letters', 'distance', 'space' },
    npcFormat = { 'name', 'icons', 'distance', 'space' },
}
for _, key in ipairs({ 'nameFormat', 'monsterFormat', 'npcFormat' }) do
    assert(not ids['Tokens & Examples##name.formatHelp.' .. key], 'token dropdown must be absent')
    local tip = assert(help['Reset##name.' .. (key == 'monsterFormat' and 'resetFormat' or ('reset.' .. key))],
        'format editor must have (?) help after its Reset')
    for _, token in ipairs(tokens[key]) do
        assert(tip:find('[' .. token .. ']', 1, true), key .. ' lists [' .. token .. ']')
    end
    -- the options, after the tokens and before the example: what any token takes, and the token's own
    local options = tip:match('\nOptions go after a colon[^\n]*\n(.-)\n\nExample format:')
    assert(options ~= nil, key .. ' lists the options between the tokens and the example')
    for _, option in ipairs({ 'color=', 'space=', 'when=', 'within=', 'spacing=', 'decimals=' }) do
        assert(options:find(option, 1, true), key .. ' lists ' .. option)
    end
    assert(options:find('size=', 1, true), key .. ' lists size=')
    assert(key ~= 'monsterFormat' or (options:find('nocombat', 1, true) and options:find('exact', 1, true)
        and options:find('type=', 1, true) and options:find('[aggro], [checked] - size=', 1, true)), 'enemy options')
    assert(key ~= 'nameFormat' or (options:find('gap=', 1, true) and options:find('replace', 1, true)), 'player options')
    assert(tip:find('[name]', 1, true) and tip:find('[distance]', 1, true))
    local example = assert(tip:match('Example format:\n([^\n]+)\nExample result:'))
    local compiled = require('format').Compile(example)
    assert(compiled.distance, 'each category has a usable example format')
    for _, part in ipairs(compiled) do
        assert(part.kind ~= 'text' or not part.text:find('[', 1, true), 'example tokens must parse')
    end
end
assert(help['Reset##name.reset.npcFormat']:find('Babubu (4.2y)', 1, true))
controls.Mark = mark
options.showHealthBar[1] = true
clear(); customSettings.DrawBars(options)
assert(not disabledIds['##name.healthBarWidth'] and not disabledIds['##name.healthBarsCombatOnly'])
options.showHealthBar[1] = false
local input = imgui.InputInt
imgui.InputInt = function(id, value)
    if id == '##name.fontSize' then value[1] = 28; return true end
    if id == '##name.healthBarHeight' then value[1] = 11; return true end
    return input(id, value)
end
local barWidth = options.healthBarWidth[1]
customSettings.DrawSettings(options)
customSettings.DrawBars(options)
imgui.InputInt = input
custom.Settle(options)
assert(options.fontSize[1] == 28 and options.healthBarHeight[1] == 11 and options.healthBarWidth[1] == barWidth)
H.print('Shared name-size and bar dimensions remain independent', true)

imgui.ColorEdit4 = record
for _, key in ipairs(types.List) do expanded['Colour Overrides##name.colours.' .. key] = true end
clear(); customSettings.DrawSettings(options)
for _, key in ipairs(types.List) do
    for _, state in ipairs(require('name_colours').States[key]) do
        local id = '##name.colours.' .. key .. '.' .. state[1]
        -- a colour is greyed out while its state is off; Normal and Alliance are on in the preferred defaults
        assert(ids[id .. '.enabled'] and ids[id .. '.color'] and not disabledIds[id .. '.color'] == options.nameColours[key][state[1]].enabled[1])
    end
end
options.nameColours.enemyNames.callForHelp.enabled[1] = true
clear(); customSettings.DrawSettings(options)
assert(not disabledIds['##name.colours.enemyNames.callForHelp.color'])
imgui.Button = function(id) return id == 'Use Game Colours##name.colours.reset.enemyNames' end
customSettings.DrawSettings(options)
assert(not options.nameColours.enemyNames.callForHelp.enabled[1], 'reset restores game colours')
imgui.Button = record
for _, key in ipairs(types.List) do expanded['Colour Overrides##name.colours.' .. key] = false end

imgui.InputText = function(id, value)
    if id == '##name.nameFormat' then value[1] = 'Player: [name]'; return true end
    if id == '##name.monsterFormat' then value[1] = '[level] [name] [letters: type=double]'; return true end
    if id == '##name.npcFormat' then value[1] = '[name] ([distance]y)'; return true end
    return record(id)
end
customSettings.DrawSettings(options); custom.Settle(options)
assert(options.monsterFormat[1] == '[level] [name] [letters: type=double]')
imgui.InputText = record
imgui.Button = function(id) return id == 'Reset##name.resetFormat' end
local saves = 0
customSettings.DrawSettings(options, function() saves = saves + 1 end)
assert(saves == 1 and options.monsterFormat[1] == '[aggro] [name] [letters]')
assert(options.nameFormat[1] == 'Player: [name]' and options.npcFormat[1] == '[name] ([distance]y)')
imgui.Button = record
imgui.BeginCombo = function(id) return id == '##name.checkDetailsInWords' end
imgui.Selectable = function(id) return id:find('Text Only', 1, true) ~= nil end
customSettings.DrawCheck(options); assert(options.checkDetailsInWords[1])
imgui.BeginCombo = record
H.print('Category format editors/reset preserve each other', true)

options.showHealthBar[1], options.showCastBar[1] = false, false
H.tab(3); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Shared Bar Settings|Health Bars|Health Bar Entity Types|Cast Bars',
    'what the bars share first, then each kind; Cast Text waits for Enabled')
for _, id in ipairs({ '##name.healthBarWidth', '##name.healthBarHeight', '##name.castBarAutoWidth', '##name.barPreview' }) do
    assert(ids[id] and locations[id] == 'Shared Bar Settings' and disabledIds[id], 'shared: ' .. id .. ', waiting for either bar')
end
assert(not ids['##name.healthBarPreview'] and not ids['##name.castBarPreview'], 'one preview for both')
for _, key in ipairs({ 'self', 'party', 'alliance', 'players', 'myPet', 'pets', 'npcs', 'monsters' }) do
    local id = '##name.healthBarTypes.' .. key
    assert(ids[id] and locations[id] == 'Health Bar Entity Types' and disabledIds[id], 'Entity Types has ' .. key .. ', waiting for Enabled')
end
for _, id in ipairs({ '##name.showHealthBar', '##name.healthBarsCombatOnly', '##name.healthBarTexture' }) do
    assert(ids[id] and locations[id] == 'Health Bars', 'Health Bars has ' .. id)
end
assert(disabledIds['##name.healthBarsCombatOnly'] and disabledIds['##name.healthBarTexture'], 'the rest wait for Enabled')
assert(ids['##name.showCastBar'] and locations['##name.showCastBar'] == 'Cast Bars' and not ids['##name.castBarWeaponskills'])
H.print('Bars: one tab, third: the shared size, Fit to Name and Preview, then Health Bars, its Entity Types and Cast Bars', true)

options.showCastBar[1]=true
clear();customSettings.DrawBars(options)
assert(not disabledIds['##name.healthBarWidth'] and not disabledIds['##name.barPreview'] and disabledIds['##name.healthBarsCombatOnly'],
    'cast bars alone enable what is shared, not the health bars\' own')
assert(table.concat(headers, '|') == 'Shared Bar Settings|Health Bars|Health Bar Entity Types|Cast Bars|Cast Text')
assert(ids['##name.castNameScale'] and ids['##name.castTimerScale'] and ids['##name.castBarTexture'] and ids['##name.castFont'])
assert(options.castBarAutoWidth[1]==false, 'Fit to Name is opt-in')
assert(options.castNameScale[1]==75 and options.castTimerScale[1]==75 and options.castBarPreview==nil and options.barPreview==nil)
local sizes=custom.Defaults({});sizes.castNameScale={999};sizes.castTimerScale={'bad'};custom.Settle(sizes)
assert(sizes.castNameScale[1]==200 and sizes.castTimerScale[1]==75)
assert(ids['##name.castBarWeaponskills'])
for _, id in ipairs({ '##name.castShowName', '##name.castShowTimer', '##name.castTextColour', '##name.castNameScale', '##name.castTimerScale', '##name.castFont' }) do
    assert(locations[id]=='Cast Text', 'Cast Text has ' .. id)
end
assert(locations['##name.castBarSkillTextOnly']=='Cast Bars' and disabledIds['##name.castBarSkillTextOnly'], 'Text Only waits for Show Weaponskills')
assert(not ids['##name.castTextColor'], 'the custom colour shows only for Custom')
assert(options.castBarSkillTextOnly[1] and options.castShowName[1] and options.castShowTimer[1] and options.castTextColour[1]=='white')
local text=custom.Defaults({});text.castTextColour={'pink'};text.castTextColor={2,'x',-1};custom.Settle(text)
assert(text.castTextColour[1]=='white' and text.castTextColor[1]==1 and text.castTextColor[2]==1 and text.castTextColor[3]==0)
-- the one preview drives both kinds, each while it is enabled
local casts, healthbar = require('castbar'), require('healthbar')
healthbar.Preview[1] = true
options.showHealthBar[1] = true
clear();customSettings.DrawBars(options)
assert(casts.Preview[1], 'the cast preview follows the shared one')
healthbar.Begin(nil, os.clock()); assert(healthbar.previewing, 'and the health bars\' too')
healthbar.Preview[1] = false
clear();customSettings.DrawBars(options)
assert(not casts.Preview[1], 'and off together')
options.showCastBar[1], options.showHealthBar[1] = false, false
local et = require('entity_types')
local mask = T{ 0xFF }
imgui.Checkbox = function(id, value) if id == '##name.healthBarTypes.monsters' then value[1] = false; return true end; return false end
assert(et.Draw('healthBarTypes', mask) and mask[1] == 0x7F, 'unticking Monsters takes its bit out')
imgui.Checkbox = function(id, value) if id == '##name.healthBarTypes.monsters' then value[1] = true; return true end; return false end
assert(et.Draw('healthBarTypes', mask) and mask[1] == 0xFF, 'and ticking it puts it back')
imgui.Checkbox = record
assert(et.Settle(T{ 'bad' })[1] == 0xFF and et.Settle(nil)[1] == 0xFF and et.Settle(T{ 0x1FF })[1] == 0xFF and et.Settle(T{ 0x12 })[1] == 0x12, 'a bad mask is every kind')
H.print('Bars: cast bars enable the shared settings, Cast Text, and one preview for both', true)

H.tab(4); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Check Details')
for _, id in ipairs({ '##name.showCheckDetails', '##name.checkSize', '##name.abbreviateDifficulty', '##name.checkDetailsInWords' }) do
    assert(ids[id] and locations[id] == 'Check Details', 'Check Details tab has ' .. id)
end
options.showCheckDetails[1] = false
clear(); customSettings.DrawCheck(options)
assert(not disabledIds['##name.showCheckDetails'] and disabledIds['##name.checkSize'] and disabledIds['##name.checkDetailsInWords'],
    'the rest wait for Enabled')
options.showCheckDetails[1] = true
clear(); customSettings.DrawCheck(options)
assert(not disabledIds['##name.checkSize'] and not disabledIds['##name.abbreviateDifficulty'])
H.print('Check Details: a tab of its own, fifth, with Enabled, Size, Abbreviate Difficulty and Display Style', true)

-- General: Enable Name first, then the preset; each part is switched on in its own tab
local general = require('general')
H.tab(1); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'General|Diagnostics', 'Diagnostics is under General')
for _, id in ipairs({ '##name.preset', '##name.drawNames' }) do
    assert(ids[id] and locations[id] == 'General', 'General has ' .. id)
end
for _, id in ipairs({ '##name.general.showHealthBar', '##name.general.showStatuses', '##name.showHealthBar',
        '##name.showCastBar', '##name.showCheckDetails', '##name.showStatuses' }) do
    assert(not ids[id], 'each part is switched on in its own tab, not General: ' .. id)
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
assert(order[1] == '##name.drawNames' and order[2] == '##name.preset', 'Enable Name precedes Preset')
assert(not disabledIds['##name.drawNames'], 'Enable Name remains usable while off')
assert(disabledIds['##name.preset'], 'all other General settings wait for Enable Name')
options.drawNames[1] = true
H.print('General: Enable Name first; the preset disabled while off', true)
H.tab(6); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Players|Pets|NPCs & Monsters|Target|Crowd Decluttering')
assert(ids['##name.crowdDeclutter'] and disabledIds['##name.crowdThreshold'] and locations['##name.crowdHold'] == 'Crowd Decluttering')
H.command('/name diag on')
expanded.Diagnostics = true
H.tab(1); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(ids['##name.diagnosticsEnabled'] and ids['Write Log##name.diag.write'] and ids['Write Report##name.diag.report'])
H.command('/name diag off')
right = 320
customSettings.DrawSettings(options)
for frame = 1, 10 do
    marks = {}; customSettings.DrawSettings(options)
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
H.tab(5); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Display|Entity Types|Selected Statuses')
for _, key in ipairs({ 'self', 'party', 'alliance', 'players', 'myPet', 'pets', 'npcs', 'monsters' }) do
    assert(ids['##name.statusTypes.' .. key] and locations['##name.statusTypes.' .. key] == 'Entity Types', 'statuses\' Entity Types has ' .. key)
end
assert(ids['##name.statusOffsetX'] and ids['##name.statusOffsetY'] and not ids['##name.statusTimers'], 'X and Y Offset in Display, and no Timers')
assert(ids['##name.statusIcons'] and locations['##name.statusIcons'] == 'Display', 'Icons is in Statuses → Display')
H.command('/name dev'); H.tab(7); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Tracked Monster')
local levels = require('levels')
local original = levels.Placeholders
levels.Placeholders = function() return {} end
options.trackedNm[1] = 'Test NM'
clear(); customSettings.DrawTracking(options)
assert(table.concat(headers, '|') == 'Tracked Monster|Placeholder Options')
levels.Placeholders = original
H.print('Visibility, diagnostics, statuses/tracking and stable aligned/wrapped layouts retained', true)

-- All Name tabs keep their controls visible but disabled while Enable Name is off.
options.drawNames[1] = false
local formatsBefore = options.nameFormat[1] .. options.monsterFormat[1] .. options.npcFormat[1]
for tab, expected in ipairs({
    { '##name.preset' },
    { '##name.font', '##name.fontBold', 'Smooth Font##name.fontSmooth', '##name.nameFormat', '##name.playerIconSource' },
    { '##name.showHealthBar', '##name.healthBarWidth', '##name.healthBarTypes.monsters', '##name.showCastBar', '##name.barPreview' },
    { '##name.showCheckDetails', '##name.checkSize' },
    { '##name.showStatuses', '##name.statusTypes.monsters', '##name.statusSearch' },
    { '##name.showSelf', '##name.alwaysTarget' },
    { '##name.trackedNm' },
}) do
    H.tab(tab); H.command('/name'); clear(); H.frames(1); H.command('/name')
    for _, id in ipairs(expected) do
        assert(ids[id] and disabledIds[id], 'disabled while Name is off: ' .. id)
    end
    assert(#disabledStack == 0 and not disabled, 'no disabled state leaks between tabs')
end
H.tab(1); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(ids['##name.diagnosticsEnabled'] and not disabledIds['##name.diagnosticsEnabled'], 'diagnostics work while Name is off')
assert(formatsBefore == options.nameFormat[1] .. options.monsterFormat[1] .. options.npcFormat[1], 'disabling keeps saved formats')
options.drawNames[1] = true
H.tab(2); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(not disabledIds['##name.font'] and not disabledIds['##name.nameFormat']
    and not disabledIds['Smooth Font##name.fontSmooth'], 'settings are editable again after enabling')
local boldBeforeSmooth = options.fontBold[1]
imgui.Checkbox = function(id, value)
    if id == 'Smooth Font##name.fontSmooth' then value[1] = true; return true end
    return record(id)
end
customSettings.DrawSettings(options)
assert(options.fontSmooth[1] and options.fontBold[1] == boldBeforeSmooth, 'Smooth Font toggles independently of Bold')
imgui.Checkbox = record
options.fontSmooth[1] = false
H.print('Enable Name: all other tabs greyed out while off, saved values retained, controls restored when on', true)
