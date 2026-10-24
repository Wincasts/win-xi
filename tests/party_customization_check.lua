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
assert(table.concat(statuses.Select(ids, style), ',') == '40,4,1,33,41')
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
style.bookends, style.outline = false, false
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
draw.Text = function(_, _, packed, text) if text == '1000' then tpColor = packed end end
style.tpReady, style.tpFlash = 2000, false
paint('off')
assert(tpColor == theme.Get().TextColor)
style.tpReady = 1000
paint('off')
assert(tpColor ~= theme.Get().TextColor)
draw.Packed, draw.Image = pack, image
H.print('warnings: configurable distance opacity and TP-ready threshold', true)

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
