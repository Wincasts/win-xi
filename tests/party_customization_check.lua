H.load()
local o = H.options()
local options = require('options')
-- Malformed edited settings cannot select invalid enums or unbounded sliders.
o.style.buffLimit[1], o.style.barShadows = 900, 'invalid'
options.Complete(o)
assert(o.style.buffLimit[1] == 32 and o.style.barShadows == 'full')
local exposed = {}
for _, tab in ipairs(options.Tabs) do
    for _, entry in ipairs(tab.entries) do
        if entry.key == 'scale' or entry.key == 'sortByRole' then
            exposed[entry.key] = not entry.when or entry.when(o)
        end
    end
end
assert(exposed.scale and exposed.sortByRole == false, 'scale visible, role-sort toggle hidden')
local config, imgui = require('config'), require('imgui')
for _, tab in ipairs(config.Tabs) do assert(not tab.name:find('Profiles', 1, true), 'no Profiles tab') end
o.profiles = { Old = {} }
options.Complete(o)
assert(o.profiles == nil, 'profiles of earlier versions are dropped')
local button = imgui.Button
imgui.Button = function(label, ...)
    assert(not label:find('##party.reset', 1, true) and not label:match('^Reset .+ Settings'),
        'settings tabs must not expose section-reset buttons')
    return button(label, ...)
end
for _, tab in ipairs(config.Tabs) do tab.draw(o) end
imgui.Button = button
H.print('settings: malformed values bounded, no Profiles tab, old profiles dropped, no reset buttons', true)

local statuses = require('statuses')
local style = { debuffsFirst = true, priorityStatuses = '40,4', hiddenStatuses = '7' }
local ids = { 33, 7, 1, 40, 4, 41 }
assert(table.concat(statuses.Select(ids, style), ',') == '4,1,40,33,41',
    'Debuffs First outranks Priority Status IDs, which order each kind')
-- Defense Down, Threnody, Magic Evasion Down, a Geo down and a daze are debuffs as well as the ailments
local mixed = { 33, 149, 43, 217, 404, 557, 386, 40 }
assert(table.concat(statuses.Select(mixed, { debuffsFirst = true }), ',') == '149,217,404,557,386,33,43,40')
style.priorityStatuses, style.hiddenStatuses, style.debuffsFirst = '', '', false
assert(table.concat(statuses.Select(ids, style), ',') == '33,7,1,40,4,41')
assert(#statuses.Select({}, style) == 0, 'scratch list must not retain old IDs')
for _, direction in ipairs({ 'left', 'right', 'auto' }) do
    style.buffDirection, style.buffRows, style.buffLimit = direction, 2, 32
    local dir, anchor, columns, capacity = statuses.Plan(style, 10, 200, 640, 24, 2)
    assert(capacity <= 32 and capacity == columns * 2)
    if dir == 'left' then assert(columns == 0) else assert(anchor + columns * 26 - 2 <= 640) end
end
H.print('statuses: stable filtering/priorities, two rows, direction and screen capacity', true)

local frames, draw, imgui = require('frames'), require('draw'), require('imgui')
local theme = require('winxi.theme')
local member = { name = 'Long member name', serverId = 123, hp = 500, hpp = 50, mp = 200, mpp = 50,
    tp = 1000, isInZone = true, isPlayer = true, statusIds = {} }
local members = { member }
style = options.Style(o)
style.bookends, style.outline, style.barGlow = false, false, 0
local images, texts = 0, {}
draw.Texture = function() return 1 end
draw.Image = function() images = images + 1 end
draw.Text = function(_, _, _, words) texts[#texts + 1] = words end
local measured = 0
imgui.CalcTextSize = function(text) measured = measured + 1; return #text * 8, 14 end
local function paint(shadows)
    style.barShadows = shadows; images = 0
    frames.Draw(members, 'party', nil, style)
    return images
end
assert(paint('full') == 10 and paint('simple') == 8 and paint('off') == 6)
local count = measured
paint('off')
assert(measured == count, 'unchanged font should reuse measurements')
theme.Get().FontFile = 'new-theme.ttf'
paint('off')
assert(measured > count, 'theme font change must invalidate text measurements')
style.lowHp = 60
paint('off')
assert(table.concat(texts, '|'):find('!', 1, true))
local _, oneHeight = frames.FullSize(6, 'party', style)
style.buffRows = 2
local _, twoHeight = frames.FullSize(6, 'party', style)
assert(twoHeight > oneHeight, 'two rows must reserve vertical space')
-- More statuses than capacity draw an overflow label, without loading off-screen textures.
style.buffRows, style.buffLimit, style.buffDirection, style.buffFitScreen = 1, 2, 'right', true
member.statusIds = { 1, 2, 3, 4 }
local loads = 0
texts = {}
frames.Draw(members, 'party', function() loads = loads + 1; return 7, false end, style)
assert(loads == 1 and table.concat(texts, '|'):find('+3', 1, true))
-- Debuffs First: the debuffs nearest the frame, the rest following in the grow direction
style.buffLimit, style.buffFitScreen, style.debuffsFirst, style.priorityStatuses, style.hiddenStatuses = 8, false, true, '', ''
member.statusIds = { 33, 40, 149, 4 }
local image = draw.Image
for _, direction in ipairs({ 'left', 'right' }) do
    style.buffDirection = direction
    local placed = {}
    draw.Image = function(texture, x1) if texture >= 1000 then placed[#placed + 1] = { texture - 1000, x1 } end end
    frames.Draw(members, 'party', function(id) return 1000 + id, false end, style)
    table.sort(placed, function(p, q) if direction == 'left' then return p[2] > q[2] end return p[2] < q[2] end)
    local order = {}
    for i, p in ipairs(placed) do order[i] = p[1] end
    assert(table.concat(order, ',') == '149,4,33,40', direction .. ': ' .. table.concat(order, ','))
end
draw.Image = image
H.print('drawing: shadow quality, font invalidation, low-HP warning, row geometry and overflow', true)
local pack, image = draw.Packed, draw.Image
local alphas = {}
draw.Packed = function(_, alpha) return alpha end
draw.Image = function(_, _, _, _, _, packed) alphas[#alphas + 1] = packed end
member.statusIds, member.isPlayer, member.targetIndex = {}, false, 10
member.entity = { Distance = 400 }
style.castRange, style.targetRange, style.nearOpacity, style.farOpacity = 10, 30, .33, .12
paint('off')
assert(alphas[2] == .33)
alphas = {}; member.entity.Distance = 1600
paint('off')
assert(alphas[2] == .12)
alphas = {}; member.isPlayer = true
paint('off')
assert(alphas[2] == 1)
local tpColor
draw.Packed = function(color) return color end
local tpText = '999'
draw.Text = function(_, _, packed, text) if text == tpText then tpColor = packed end end
style.tpFlash = false
member.tp = 999
paint('off')
assert(tpColor == theme.Get().TextColor, 'TP under 1000 is not ready')
member.tp, tpText = 1000, '1000'
style.tpReady = 3000 -- a threshold of earlier versions is not read
paint('off')
assert(tpColor ~= theme.Get().TextColor, 'TP is ready at 1000')
style.tpReady = nil
-- TP Ready Color: ready TP in the chosen colour, kept there without the flash and pulsing toward white with it
style.tpColor = { 1, 0.25, 0, 1 }
paint('off')
assert(tpColor[1] == 1 and tpColor[2] == 0.25 and tpColor[3] == 0, 'ready TP is the chosen colour')
style.tpFlash = true
paint('off')
assert(tpColor[1] == 1 and tpColor[2] >= 0.25 and tpColor[2] <= 0.75 and tpColor[3] >= 0 and tpColor[3] <= 2 / 3,
    'the flash goes no further than two thirds toward white')
style.tpColor, style.tpFlash = nil, false
draw.Packed, draw.Image = pack, image
o.style.tpReady = { 2000 }
options.Complete(o)
assert(o.style.tpReady == nil, 'the saved threshold of earlier versions is dropped')
for _, tab in ipairs(options.Tabs) do
    for _, entry in ipairs(tab.entries) do assert(entry.key ~= 'tpReady', 'no TP Ready Threshold setting') end
end
local warnings
for _, tab in ipairs(options.Tabs) do
    for _, entry in ipairs(tab.entries) do
        if entry.kind == 'header' and entry.label == 'Warnings' then warnings = tab.name end
        if entry.key == 'tpColor' then
            assert(warnings == 'Style' and entry.kind == 'color' and entry.label == 'TP Ready Color', 'TP Ready Color under Style -> Warnings')
        end
    end
end
assert(type(o.style.tpColor) == 'table' and #o.style.tpColor == 4, 'TP Ready Color kept as r, g, b, a')
o.style.tpColor = 'blue'
options.Complete(o)
assert(type(o.style.tpColor) == 'table' and math.abs(o.style.tpColor[3] - 0xFA / 255) < 1e-9, 'a malformed colour goes back to blue')
assert(options.Style(o).tpColor == o.style.tpColor, 'the chosen colour reaches the frames')
H.print('warnings: configurable distance opacity, TP ready at 1000 and in its chosen colour', true)

-- Show Statuses: off, the party and alliance draw no status icons and every status setting is greyed
local partyDraws = {}
local frameDraw = frames.Draw
frames.Draw = function(list, kind, texture) partyDraws[kind] = texture ~= nil end
assert(o.style.showStatuses[1] == true, 'statuses are shown to begin with')
o.party.enabled[1], o.showConfig[1] = true, false
local organizer, winxiGame = require('winxi.organize'), require('winxi.game')
local isActive, isHidden = organizer.IsActive, winxiGame.IsHidden
organizer.IsActive, winxiGame.IsHidden = function() return true end, function() return false end
local roster = require('roster')
local counts, rosterMembers = roster.Counts, roster.Members
roster.Counts, roster.Members = function() return 6, 6, 6, true end, function() return { member } end
H.frames(1)
assert(partyDraws.party, 'statuses shown: the party has its icons')
o.style.showStatuses[1] = false
partyDraws = {}
H.frames(1)
assert(partyDraws.party == false and partyDraws.alliance == false, 'statuses off: the party and alliance have none')
frames.Draw, organizer.IsActive, winxiGame.IsHidden = frameDraw, isActive, isHidden
roster.Counts, roster.Members = counts, rosterMembers
o.style.showStatuses[1] = true
local widgets = require('winxi.widgets')
-- a status setting is a row under Show Statuses (winxi 65's rows: spec.parent), greyed while it is off
local header, disabled, greyedLabels, beginRow = widgets.Header, 0, {}, widgets.BeginRow
local begin, finish = imgui.BeginDisabled, imgui.EndDisabled
widgets.Header = function() return true end
widgets.BeginRow = function(text, sentence, spec)
    local parent = spec and spec.parent
    greyedLabels[text] = disabled > 0 or (type(parent) == 'table' and not parent[1]) or false
    return beginRow(text, sentence, spec)
end
imgui.BeginDisabled = function() disabled = disabled + 1 end
imgui.EndDisabled = function() disabled = disabled - 1 end
local styleTab
for _, tab in ipairs(config.Tabs) do if tab.name == 'Style' then styleTab = tab end end
styleTab.draw(o)
assert(disabled == 0, 'every greyed setting is closed again')
assert(greyedLabels['Buff Icon Size'] == false and greyedLabels['Debuffs First'] == false,
    'statuses on: nothing greyed')
for k in pairs(greyedLabels) do greyedLabels[k] = nil end
o.style.showStatuses[1] = false
styleTab.draw(o)
assert(disabled == 0 and greyedLabels['Show Statuses'] == false, 'the toggle itself is never greyed')
for _, name in ipairs({ 'Buff Icon Size', 'Buff Spacing', 'Buff Distance', 'Maximum Status Icons', 'Status Rows',
    'Status Growth', 'Fit Status Icons To Screen', 'Status Overflow Count', 'Debuffs First', 'Priority Effects',
    'Hidden Effects', 'Priority Status IDs', 'Hidden Status IDs' }) do
    assert(greyedLabels[name] == true, name .. ' greyed while statuses are off')
end
assert(greyedLabels['Frame Scale'] == false and greyedLabels['Low HP Warning'] == false, 'other settings are not greyed')
widgets.Header, widgets.BeginRow, imgui.BeginDisabled, imgui.EndDisabled = header, beginRow, begin, finish
o.style.showStatuses[1] = true
H.print('Show Statuses: icons left out of party windows and the status settings greyed', true)

local geometry = require('geometry')
local fullSize, calls = frames.FullSize, 0
frames.FullSize = function(...) calls = calls + 1; return fullSize(...) end
local height = geometry.Reserve(o, 14, 14, 4, 2)
assert(calls > 0)
calls = 0
assert(geometry.Reserve(o, 14, 14, 4, 2) == height and calls == 0)
local sixHeight = geometry.Reserve(o, 14, 14, 4, 6)
assert(sixHeight > height and calls > 0)
calls = 0
o.style.valueSize[1] = o.style.valueSize[1] + 1
geometry.Reserve(o, 14, 14, 4, 6)
assert(calls > 0)
frames.FullSize = fullSize
H.print('layout: cached reservation invalidates for styles and six pets', true)

local pets = require('pets')
local party = { GetMemberTargetIndex = function(_, i) return i + 10 end,
    GetMemberIsActive = function() return 1 end, GetMemberZone = function() return 1 end,
    GetMemberName = function(_, i) return 'Owner' .. i end }
local player = { GetPetMPPercent = function() return 50 end, GetPetTP = function() return 0 end,
    GetMainJob = function() return 1 end, GetSubJob = function() return 1 end }
AshitaCore.GetMemoryManager = function() return { GetParty = function() return party end, GetPlayer = function() return player end } end
GetPlayerEntity = function() return {} end
GetEntity = function(index)
    if index < 20 then return { PetTargetIndex = index + 10 } end
    return { Name = 'Pet' .. index, HPPercent = 100 }
end
o.pets.showParty[1], o.pets.nameFormat = true, 'ownerPet'
pets.Forget()
assert(#pets.Lines(false, o.pets) == 6)
assert(pets.Lines(false, o.pets)[2].name == 'Owner1: Pet21')
o.pets.nameFormat = 'petOwner'
assert(pets.Lines(false, o.pets)[2].name == 'Pet21 (Owner1)')
o.pets.nameFormat = 'pet'
assert(pets.Lines(false, o.pets)[2].name == 'Pet21')
H.print('pets: six pets, owner labels and immediate format changes', true)

-- Early hidden return skips both pet polling and geometry while still accepting settings.
require('winxi.game').IsHidden = function() return true end
require('game').StPartyIndex = function() return nil end
o.showConfig[1], o.automaticPositioning[1] = false, true
pets.Lines = function() error('hidden frame polled pets') end
geometry.Reserve = function() error('hidden frame reserved geometry') end
H.frames(1)
H.print('hidden frame skips pet polling and geometry', true)
require('winxi.game').IsHidden = function() return false end
local windows = require('windows')
windows.UpdateFade, windows.Draw = function() end, function() end
windows.IsFadedOut = function() return false end
require('roster').Counts = function() return 0, 0, 0 end
o.target.enabled[1] = false
local reserved
pets.Lines = function() return { 1, 2, 3, 4, 5, 6 } end
geometry.Reserve = function(_, _, _, _, count) reserved = count; return 600, 60, 250 end
windows.UpdatePositions = function(main, target, alliance) assert(main == 600 and target == 60 and alliance == 250) end
o.pets.reserve[1], o.pets.enabled[1], o.pets.showParty[1] = 2, true, true
H.frames(1)
assert(reserved == 6, 'present must reserve the actual six-pet count, not the configured minimum')
H.print('present integrates live six-pet reservation', true)

-- The effect picker keeps the saved value a comma-separated list of IDs, in the order chosen
local picker = require('statuspicker')
local ids = picker.Parse('5, 3,5,2000, 7')
assert(table.concat(ids, ',') == '5,3,7', 'duplicates and IDs past 1023 are dropped')
local value = { '5,3' }
picker.Set(value, 9, true); picker.Set(value, 9, true)
assert(value[1] == '5,3,9', 'an effect is added once, at the end')
picker.Set(value, 3, false)
assert(value[1] == '5,9')
picker.Set(value, 1.5, true); picker.Set(value, 4000, true)
assert(value[1] == '5,9', 'IDs that are not effects are ignored')
picker.Move(value, 9, -1); assert(value[1] == '9,5')
picker.Move(value, 9, -1); assert(value[1] == '9,5', 'the first cannot move up')
picker.Move(value, 5, 1); assert(value[1] == '9,5', 'the last cannot move down')
assert(picker.Matches({ id = 12, lower = 'protect' }, 'PRO') and picker.Matches({ id = 12, lower = 'protect' }, '12')
    and not picker.Matches({ id = 12, lower = 'protect' }, '1'), 'search by name, any case, or by the whole ID')
value[1] = '9,5'
local core, names = AshitaCore, { [5] = 'Blindness', [9] = 'Protect', [12] = 'Shell' }
AshitaCore = { GetResourceManager = function() return { GetString = function(_, _, id) return names[id] end } end }
local combo, shown = imgui.BeginCombo, {}
imgui.BeginCombo = function() return true end
local checkbox = imgui.Checkbox
imgui.Checkbox = function(label) shown[#shown + 1] = label:match('^[^#]+'); return false end
picker.Draw('priorityStatuses', value, true)
imgui.BeginCombo, imgui.Checkbox, AshitaCore = combo, checkbox, core
assert(table.concat(shown, '|') == '1. Protect (9)|2. Blindness (5)|Blindness (5)|Protect (9)|Shell (12)', table.concat(shown, '|'))
H.print('effect picker: parse, add, remove, reorder, search and draw', true)
