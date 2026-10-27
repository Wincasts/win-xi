-- The settings as described rows (winxi 65): every tab's sections, sub-sections and rows, each row a
-- sentence, its dependents greyed under their parent, and no help besides.
local imgui, widgets = require('imgui'), require('winxi.widgets')
local custom, controls, types = require('custom'), require('controls'), require('name_types')
local customSettings = require('custom_settings')
local options = H.options()
AshitaCore.GetPluginManager = function() return { IsLoaded = function() return false end } end
local headers, subs, tabs, ids, kinds, disabledIds = {}, {}, {}, {}, {}, {}
local section, sub, locations, subOf, subsIn, notes = nil, nil, {}, {}, {}, {}
local expanded = {}
local disabled = false
local disabledStack, order = {}, {}
widgets.Header = function(text, first, collapsed)
    section, sub = text, nil
    headers[#headers + 1] = text
    return not collapsed or expanded[text] == true
end
widgets.SubHeader = function(text, first, collapsed)
    sub = text
    subs[#subs + 1] = text
    subsIn[section .. '/' .. text] = true
    return not collapsed or expanded[section .. '/' .. text] == true
end
local originalTab = imgui.BeginTabItem
imgui.BeginTabItem = function(label, ...) tabs[#tabs + 1] = label; return originalTab(label, ...) end
-- the sentence of the row being drawn goes to the control recorded in it
local lastSentence, help = nil, {}
local beginRow, endRow = widgets.BeginRow, widgets.EndRow
widgets.BeginRow = function(name, sentence, spec) lastSentence = sentence; return beginRow(name, sentence, spec) end
widgets.EndRow = function() lastSentence = nil; return endRow() end
local note = widgets.Note
widgets.Note = function(text) notes[#notes + 1] = { section = section, sub = sub, text = text }; return note(text) end
local function record(id)
    order[#order + 1] = id
    ids[id] = true; disabledIds[id] = disabled; locations[id] = section; subOf[id] = sub; help[id] = lastSentence
    return false
end
local function recorder(kind) return function(id) kinds[id] = kind; return record(id) end end
imgui.Checkbox, imgui.InputInt, imgui.SliderInt = recorder('Checkbox'), recorder('InputInt'), recorder('SliderInt')
imgui.InputText, imgui.BeginCombo, imgui.Button, imgui.ColorEdit4 = recorder('InputText'), recorder('BeginCombo'), recorder('Button'), recorder('ColorEdit4')
-- what a described row never has: radio buttons, tree nodes, (?) marks and tooltips
imgui.RadioButton = function(id) error('no radio buttons: ' .. tostring(id)) end
imgui.TreeNode = function(id) error('no tree nodes: ' .. tostring(id)) end
imgui.BeginTooltip = function() error('no tooltips') end
imgui.SetTooltip = function() error('no tooltips') end
imgui.TextDisabled = function(text) assert(text ~= '(?)', 'no (?) marks') end
imgui.BeginDisabled = function(value)
    disabledStack[#disabledStack + 1] = disabled
    disabled = disabled or value
end
imgui.EndDisabled = function()
    assert(#disabledStack > 0, 'balanced disabled groups')
    disabled = table.remove(disabledStack)
end
imgui.GetFontSize = function() return 14 end
imgui.GetContentRegionAvail = function() error('Window widths must not feed back into auto-sizing') end
local function clear() headers, subs, tabs, ids, kinds, disabledIds, locations, subOf, subsIn, notes, order = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {} end
-- every control recorded was drawn in a row with a sentence, but the status list's own ticks
local function sentences()
    for id in pairs(ids) do
        if not id:find('##name.status.', 1, true) then
            assert(type(help[id]) == 'string' and #help[id] > 0, 'a sentence under ' .. id)
            assert(not help[id]:find(';', 1, true) and not help[id]:find('(', 1, true), 'plain: ' .. help[id])
        end
    end
end
H.tab(2); H.command('/name'); H.frames(1)
clear(); H.frames(1); H.command('/name')
assert(table.concat(tabs, '|') == 'General|Names|Bars|Check Details|Statuses|Visibility', 'NM Tracking waits for /name dev')
H.command('/name dev'); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(tabs, '|') == 'General|Names|Bars|Check Details|Statuses|Visibility|NM Tracking', '/name dev shows NM Tracking')
H.command('/name dev'); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(tabs, '|') == 'General|Names|Bars|Check Details|Statuses|Visibility', 'a second /name dev hides it')
assert(table.concat(headers, '|') == 'Appearance|Player Names|Enemy Names|NPC Names|Distance Thresholds')
assert(table.concat(subs, '|') == 'Font|Size|Outlines|Format Tokens|Colour Overrides|Format Tokens|Colour Overrides|Format Tokens|Colour Overrides',
    'Appearance in three families; each kind of name its tokens and colour overrides')
sentences()
assert(not ids['##name.partyIcons'] and not ids['##name.showVendorIcons'], 'party and vendor signs are tokens, not settings')
assert(ids['##name.font'] and ids['##name.fontBold'] and ids['##name.fontSmooth'] and ids['##name.subtargetScale'] and ids['##name.textOutlineOpacity'])
assert(kinds['##name.font'] == 'BeginCombo' and subOf['##name.font'] == 'Font', 'the font is a dropdown under Font')
for index, id in ipairs(order) do
    if id == '##name.fontBold' then
        assert(order[index + 1] == '##name.fontSmooth', 'Smooth Font follows Bold')
    end
end
assert(ids['##name.fontSize'] and ids['##name.minSize'] and subOf['##name.fontSize'] == 'Size', 'shared size controls belong in Names, under Size')
assert(kinds['##name.fontSize'] == 'SliderInt', 'a size is a slider with its unit')
assert(ids['##name.iconOutline'] and kinds['##name.iconOutline'] == 'BeginCombo' and ids['##name.iconOutlineOpacity'], 'an outline is a dropdown of thicknesses')
assert(ids['##name.outline'] and kinds['##name.outline'] == 'BeginCombo' and subOf['##name.outline'] == 'Outlines')
assert(options.iconOutline[1] == 1 and options.iconOutlineOpacity[1] == 100)
assert(ids['##name.distanceColours'] and not ids['##name.crowdDeclutter'], 'Crowd Decluttering is in Visibility')
assert(disabledIds['##name.distanceWarning'] and disabledIds['##name.distanceWarningColor'], 'opt-in policy controls wait, greyed, under Distance Colours')
for _, key in ipairs({ 'nameFormat', 'monsterFormat', 'npcFormat' }) do
    local reset = 'Reset##name.' .. (key == 'monsterFormat' and 'resetFormat' or ('reset.' .. key))
    assert(kinds['##name.' .. key] == 'InputText' and kinds[reset] == 'Button')
    for index, id in ipairs(order) do
        if id == '##name.' .. key then
            assert(order[index + 1] == reset and locations[reset] == locations[id], 'Reset is the row after ' .. key)
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
local sectionOf = { playerNames = 'Player Names', enemyNames = 'Enemy Names', npcNames = 'NPC Names' }
for _, key in ipairs(types.List) do
    for _, field in ipairs({ 'showHealthBar', 'healthBarWidth', 'healthBarHeight' }) do
        local id = '##name.' .. key .. '.' .. field
        assert(not ids[id], 'obsolete per-type bar control must be absent')
    end
    assert(subsIn[sectionOf[key] .. '/Colour Overrides'], 'each category has colour overrides, a sub-section collapsed to start')
    assert(not ids['##name.colours.' .. key .. '.normal.enabled'] and not ids['##name.colours.' .. key .. '.dead.enabled'], 'collapsed: its rows not drawn')
    assert(not ids['##name.' .. key .. '.healthBarPreview'], 'preview controls must be absent')
    assert(not ids['##name.' .. key .. '.fontSize'] and not ids['##name.' .. key .. '.minSize'], 'category size controls must be absent')
end
assert(locations['##name.nameFormat'] == 'Player Names'
    and locations['##name.monsterFormat'] == 'Enemy Names' and locations['##name.npcFormat'] == 'NPC Names',
    'category format editors remain in their own sections')
assert(not ids['##name.diagnosticsEnabled'])
for _, field in ipairs({ 'showHealthBar', 'healthBarsCombatOnly', 'healthBarWidth', 'healthBarHeight',
        'showCastBar', 'showCheckDetails', 'checkSize', 'abbreviateDifficulty', 'checkDetailsInWords' }) do
    assert(not ids['##name.' .. field], 'bars and check details have tabs of their own, not a place under Names')
end
H.print('Names: shared Appearance rows, per-category colour overrides, no obsolete toggles', true)

-- the tokens each format can have: a sub-section of its own, collapsed to start, with the reference in it
local tokens = {
    nameFormat = { 'name', 'icons', 'distance', 'space' },
    monsterFormat = { 'name', 'level', 'aggro', 'checked', 'letters', 'distance', 'space' },
    npcFormat = { 'name', 'icons', 'distance', 'space' },
}
for _, found in ipairs(notes) do assert(found.sub ~= 'Format Tokens', 'the token reference is drawn only once Format Tokens is opened') end
for _, section in pairs(sectionOf) do expanded[section .. '/Format Tokens'] = true end
clear(); customSettings.DrawSettings(options)
local tokenNotes = {}
for _, found in ipairs(notes) do
    if found.sub == 'Format Tokens' then tokenNotes[found.section] = found.text end
end
for key, section in pairs(sectionOf) do
    local formatKey = key == 'playerNames' and 'nameFormat' or (key == 'enemyNames' and 'monsterFormat' or 'npcFormat')
    assert(not ids['Tokens & Examples##name.formatHelp.' .. formatKey], 'token dropdown must be absent')
    local tip = assert(tokenNotes[section], section .. ' has its token reference under Format Tokens')
    for _, token in ipairs(tokens[formatKey]) do
        assert(tip:find('[' .. token .. ']', 1, true), formatKey .. ' lists [' .. token .. ']')
    end
    -- the options, after the tokens and before the example: what any token takes, and the token's own
    local found = tip:match('\nOptions go after a colon[^\n]*\n(.-)\n\nExample format:')
    assert(found ~= nil, formatKey .. ' lists the options between the tokens and the example')
    for _, option in ipairs({ 'color=', 'space=', 'when=', 'within=', 'spacing=', 'decimals=' }) do
        assert(found:find(option, 1, true), formatKey .. ' lists ' .. option)
    end
    assert(found:find('size=', 1, true), formatKey .. ' lists size=')
    assert(formatKey ~= 'monsterFormat' or (found:find('nocombat', 1, true) and found:find('exact', 1, true)
        and found:find('type=', 1, true) and found:find('[aggro], [checked] - size=', 1, true)), 'enemy options')
    assert(formatKey ~= 'nameFormat' or (found:find('gap=', 1, true) and found:find('replace', 1, true)), 'player options')
    assert(tip:find('[name]', 1, true) and tip:find('[distance]', 1, true))
    local example = assert(tip:match('Example format:\n([^\n]+)\nExample result:'))
    local compiled = require('format').Compile(example)
    assert(compiled.distance, 'each category has a usable example format')
    for _, part in ipairs(compiled) do
        assert(part.kind ~= 'text' or not part.text:find('[', 1, true), 'example tokens must parse')
    end
end
assert(tokenNotes['NPC Names']:find('Babubu (4.2y)', 1, true))
for _, section in pairs(sectionOf) do expanded[section .. '/Format Tokens'] = nil end
options.showHealthBar[1] = true
clear(); customSettings.DrawBars(options)
assert(not disabledIds['##name.healthBarWidth'] and not disabledIds['##name.healthBarsCombatOnly'])
options.showHealthBar[1] = false
local slider = imgui.SliderInt
imgui.SliderInt = function(id, value)
    if id == '##name.fontSize' then value[1] = 28; return true end
    if id == '##name.healthBarHeight' then value[1] = 11; return true end
    return slider(id, value)
end
local barWidth = options.healthBarWidth[1]
customSettings.DrawSettings(options)
customSettings.DrawBars(options)
imgui.SliderInt = slider
custom.Settle(options)
assert(options.fontSize[1] == 28 and options.healthBarHeight[1] == 11 and options.healthBarWidth[1] == barWidth)
H.print('Shared name-size and bar dimensions remain independent', true)

for _, section in pairs(sectionOf) do expanded[section .. '/Colour Overrides'] = true end
clear(); customSettings.DrawSettings(options)
for _, key in ipairs(types.List) do
    for _, state in ipairs(require('name_colours').States[key]) do
        local id = '##name.colours.' .. key .. '.' .. state[1]
        -- a state's tick and its colour share a row; the colour is greyed out while its state is off.
        -- Normal and Alliance are on in the preferred defaults
        assert(ids[id .. '.enabled'] and ids[id .. '.color'] and subOf[id .. '.color'] == 'Colour Overrides')
        assert(help[id .. '.enabled'] == help[id .. '.color'], 'one row for the state')
        assert(not disabledIds[id .. '.color'] == options.nameColours[key][state[1]].enabled[1])
    end
    assert(kinds['Use Game Colours##name.colours.reset.' .. key] == 'Button', 'a row to put the game colours back')
end
sentences()
options.nameColours.enemyNames.callForHelp.enabled[1] = true
clear(); customSettings.DrawSettings(options)
assert(not disabledIds['##name.colours.enemyNames.callForHelp.color'])
imgui.Button = function(id) return id == 'Use Game Colours##name.colours.reset.enemyNames' end
customSettings.DrawSettings(options)
assert(not options.nameColours.enemyNames.callForHelp.enabled[1], 'reset restores game colours')
imgui.Button = recorder('Button')
for _, section in pairs(sectionOf) do expanded[section .. '/Colour Overrides'] = nil end

imgui.InputText = function(id, value)
    if id == '##name.nameFormat' then value[1] = 'Player: [name]'; return true end
    if id == '##name.monsterFormat' then value[1] = '[level] [name] [letters: type=double]'; return true end
    if id == '##name.npcFormat' then value[1] = '[name] ([distance]y)'; return true end
    return record(id)
end
customSettings.DrawSettings(options); custom.Settle(options)
assert(options.monsterFormat[1] == '[level] [name] [letters: type=double]')
imgui.InputText = recorder('InputText')
imgui.Button = function(id) return id == 'Reset##name.resetFormat' end
local saves = 0
customSettings.DrawSettings(options, function() saves = saves + 1 end)
assert(saves == 1 and options.monsterFormat[1] == '[aggro] [name] [letters]')
assert(options.nameFormat[1] == 'Player: [name]' and options.npcFormat[1] == '[name] ([distance]y)')
imgui.Button = recorder('Button')
imgui.BeginCombo = function(id) return id == '##name.checkDetailsInWords' end
imgui.Selectable = function(id) return id:find('Text Only', 1, true) ~= nil end
customSettings.DrawCheck(options); assert(options.checkDetailsInWords[1])
imgui.BeginCombo = recorder('BeginCombo')
H.print('Category format editors/reset preserve each other', true)

options.showHealthBar[1], options.showCastBar[1] = false, false
H.tab(3); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Shared Bar Settings|Health Bars|Cast Bars|Cast Text',
    'what the bars share first, then each kind; Cast Text waits, greyed, for Enabled')
assert(table.concat(subs, '|') == 'Entity Types', 'the kinds with a health bar, under Health Bars')
sentences()
for _, id in ipairs({ '##name.healthBarWidth', '##name.healthBarHeight', '##name.castBarAutoWidth', '##name.barPreview' }) do
    assert(ids[id] and locations[id] == 'Shared Bar Settings' and disabledIds[id], 'shared: ' .. id .. ', waiting for either bar')
end
assert(not ids['##name.healthBarPreview'] and not ids['##name.castBarPreview'], 'one preview for both')
for _, key in ipairs({ 'self', 'party', 'alliance', 'players', 'myPet', 'pets', 'npcs', 'monsters' }) do
    local id = '##name.healthBarTypes.' .. key
    assert(ids[id] and locations[id] == 'Health Bars' and subOf[id] == 'Entity Types' and disabledIds[id], 'Entity Types has ' .. key .. ', waiting for Enabled')
end
for _, id in ipairs({ '##name.showHealthBar', '##name.healthBarsCombatOnly' }) do
    assert(ids[id] and locations[id] == 'Health Bars' and subOf[id] == nil, 'Health Bars has ' .. id)
end
assert(disabledIds['##name.healthBarsCombatOnly'], 'the rest wait for Enabled')
assert(ids['##name.showCastBar'] and locations['##name.showCastBar'] == 'Cast Bars')
assert(ids['##name.castBarWeaponskills'] and disabledIds['##name.castBarWeaponskills'], 'Show Weaponskills waits, greyed, for Enabled')
assert(ids['##name.castFont'] and disabledIds['##name.castFont'] and locations['##name.castFont'] == 'Cast Text', 'Cast Text waits for Enabled too')
H.print('Bars: one tab, third: the shared size, Fit To Name and Preview, then Health Bars, its Entity Types and Cast Bars', true)

options.showCastBar[1]=true
clear();customSettings.DrawBars(options)
assert(not disabledIds['##name.healthBarWidth'] and not disabledIds['##name.barPreview'] and disabledIds['##name.healthBarsCombatOnly'],
    'cast bars alone enable what is shared, not the health bars\' own')
assert(table.concat(headers, '|') == 'Shared Bar Settings|Health Bars|Cast Bars|Cast Text')
assert(ids['##name.castNameScale'] and ids['##name.castTimerScale'] and ids['##name.castFont'] and not disabledIds['##name.castFont'])
assert(options.castBarAutoWidth[1]==false, 'Fit To Name is opt-in')
assert(options.castNameScale[1]==75 and options.castTimerScale[1]==75 and options.castBarPreview==nil and options.barPreview==nil)
local sizes=custom.Defaults({});sizes.castNameScale={999};sizes.castTimerScale={'bad'};custom.Settle(sizes)
assert(sizes.castNameScale[1]==200 and sizes.castTimerScale[1]==75)
assert(ids['##name.castBarWeaponskills'] and not disabledIds['##name.castBarWeaponskills'])
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
assert(et.Draw('healthBarTypes', mask, 'A health bar') and mask[1] == 0x7F, 'unticking Monsters takes its bit out')
imgui.Checkbox = function(id, value) if id == '##name.healthBarTypes.monsters' then value[1] = true; return true end; return false end
assert(et.Draw('healthBarTypes', mask, 'A health bar') and mask[1] == 0xFF, 'and ticking it puts it back')
imgui.Checkbox = recorder('Checkbox')
assert(et.Settle(T{ 'bad' })[1] == 0xFF and et.Settle(nil)[1] == 0xFF and et.Settle(T{ 0x1FF })[1] == 0xFF and et.Settle(T{ 0x12 })[1] == 0x12, 'a bad mask is every kind')
H.print('Bars: cast bars enable the shared settings, Cast Text, and one preview for both', true)

H.tab(4); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Check Details')
sentences()
for _, id in ipairs({ '##name.showCheckDetails', '##name.checkSize', '##name.abbreviateDifficulty', '##name.checkDetailsInWords' }) do
    assert(ids[id] and locations[id] == 'Check Details', 'Check Details tab has ' .. id)
end
assert(kinds['##name.checkDetailsInWords'] == 'BeginCombo', 'Display Style is a dropdown')
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
sentences()
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
imgui.BeginCombo, imgui.Selectable = recorder('BeginCombo'), function() return false end
assert(applied == 1 and general.Matching(options).key == 'default', 'choosing a preset in the list applies and saves it')
assert(options.drawNames[1] and general.Drawing(options))
options.drawNames[1] = false; clear(); general.DrawSettings(options)
assert(order[1] == '##name.drawNames' and order[2] == '##name.preset', 'Enable Name precedes Preset')
assert(not disabledIds['##name.drawNames'], 'Enable Name remains usable while off')
assert(disabledIds['##name.preset'], 'all other General settings wait for Enable Name')
options.drawNames[1] = true
H.print('General: Enable Name first; the preset greyed under it while off', true)
H.tab(6); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Names Shown|Crowd Decluttering', 'Visibility: the kinds shown, then the crowd')
assert(table.concat(subs, '|') == 'Players|Pets|NPCs & Monsters', 'the kinds in three families')
sentences()
assert(ids['##name.showSelf'] and subOf['##name.showSelf'] == 'Players' and subOf['##name.showMonsters'] == 'NPCs & Monsters')
assert(ids['##name.alwaysTarget'] and locations['##name.alwaysTarget'] == 'Names Shown' and subOf['##name.alwaysTarget'] == 'NPCs & Monsters',
    'Always Show Target is a row of Names Shown after its families')
assert(ids['##name.crowdDeclutter'] and disabledIds['##name.crowdThreshold'] and locations['##name.crowdHold'] == 'Crowd Decluttering')
H.command('/name diag on')
expanded.Diagnostics = true
H.tab(1); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(ids['##name.diagnosticsEnabled'] and ids['Write Log##name.diag.write'] and ids['Write Report##name.diag.report'])
assert(kinds['Write Log##name.diag.write'] == 'Button' and locations['Write Log##name.diag.write'] == 'Diagnostics', 'the logs are action rows of Diagnostics')
sentences()
H.command('/name diag off')
imgui.GetFrameHeightWithSpacing = function() return 20 end
AshitaCore.GetResourceManager = function() return { GetString = function() return '' end } end
H.tab(5); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Display|Entity Types|Selected Statuses')
sentences()
for _, key in ipairs({ 'self', 'party', 'alliance', 'players', 'myPet', 'pets', 'npcs', 'monsters' }) do
    assert(ids['##name.statusTypes.' .. key] and locations['##name.statusTypes.' .. key] == 'Entity Types', 'statuses\' Entity Types has ' .. key)
end
assert(ids['##name.statusOffsetX'] and ids['##name.statusOffsetY'] and not ids['##name.statusTimers'], 'X and Y Offset in Display, and no Timers')
assert(ids['##name.statusIcons'] and locations['##name.statusIcons'] == 'Display', 'Icons is in Statuses → Display')
assert(kinds['##name.statusSearch'] == 'InputText' and locations['##name.statusSearch'] == 'Selected Statuses')
options.showStatuses[1] = false
clear(); require('statuses').DrawSettings(options)
assert(ids['##name.statusIcons'] and disabledIds['##name.statusIcons'] and disabledIds['##name.statusTypes.monsters'] and not disabledIds['##name.showStatuses'],
    'the rest wait, greyed, for Enabled')
options.showStatuses[1] = true
H.command('/name dev'); H.tab(7); H.command('/name'); clear(); H.frames(1); H.command('/name')
assert(table.concat(headers, '|') == 'Tracked Monster')
sentences()
assert(ids['##name.huntScale'] and disabledIds['##name.huntScale'] and not ids['##name.labelPlaceholders'], 'the size waits for a tracked monster; placeholders need one with some')
local levels = require('levels')
local original = levels.Placeholders
levels.Placeholders = function() return {} end
options.trackedNm[1] = 'Test NM'
clear(); customSettings.DrawTracking(options)
assert(table.concat(headers, '|') == 'Tracked Monster' and ids['##name.labelPlaceholders'] and not disabledIds['##name.huntScale'],
    'one with placeholders has Label Placeholders, in the same section')
levels.Placeholders = original
options.trackedNm[1] = ''
H.print('Visibility, diagnostics, statuses and tracking on rows, each with its sentence', true)

-- All Name tabs keep their controls visible but disabled while Enable Name is off.
options.drawNames[1] = false
local formatsBefore = options.nameFormat[1] .. options.monsterFormat[1] .. options.npcFormat[1]
for tab, expected in ipairs({
    { '##name.preset' },
    { '##name.font', '##name.fontBold', '##name.fontSmooth', '##name.nameFormat', '##name.playerIconSource' },
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
    and not disabledIds['##name.fontSmooth'], 'settings are editable again after enabling')
local boldBeforeSmooth = options.fontBold[1]
imgui.Checkbox = function(id, value)
    if id == '##name.fontSmooth' then value[1] = true; return true end
    return record(id)
end
customSettings.DrawSettings(options)
assert(options.fontSmooth[1] and options.fontBold[1] == boldBeforeSmooth, 'Smooth Font toggles independently of Bold')
imgui.Checkbox = recorder('Checkbox')
options.fontSmooth[1] = false
H.print('Enable Name: all other tabs greyed out while off, saved values retained, controls restored when on', true)
