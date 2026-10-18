local imgui, builder, format = require('imgui'), require('builder'), require('format')
local custom, fields = require('custom'), require('mob_fields')
local o = H.options()
local original, player, npc = o.monsterFormat[1], o.nameFormat[1], o.npcFormat[1]
local d = builder.Load(o)
assert(o.checkFormat[1] == '', 'existing check renderer remains the default')
assert(d.parts[1] ~= format.Compile(original)[1])
d.parts = { { kind = 'name' } }
assert(builder.Insert(d, 'letter', nil, nil, 'name'))
d.parts[2].type, d.parts[2].color = 'double', 0xFF60E0E0
assert(builder.Insert(d, 'mob', nil, nil, 'check', nil, 'family'))
assert(builder.Insert(d, 'mob', nil, nil, 'check', nil, 'modifiers.fire'))
assert(not builder.Insert(d, 'mob', nil, nil, 'name', nil, 'family'), 'mobdb data belongs in the check row')
assert(not builder.Insert(d, 'health'), 'health bars are not builder blocks')
assert(not d.fontSize and not d.minSize, 'builder must not own enemy-only name sizes')
d.checkSize[1] = 80
assert(o.monsterFormat[1] == original and o.checkFormat[1] == '', 'both rows are draft-only')
-- Health-bar changes elsewhere must not conflict or be overwritten by this editor.
o.healthBarWidth[1], o.showHealthBar[1] = 157, true
o.fontSize[1], o.minSize[1] = 26, 12
local saves = 0
assert(builder.Apply(o, d, function() saves = saves+1 end))
assert(saves == 1 and o.fontSize[1] == 26 and o.minSize[1] == 12 and o.checkSize[1] == 80,
    'builder Apply must leave current General sizes untouched')
assert(o.healthBarWidth[1] == 157 and o.showHealthBar[1])
assert(o.nameFormat[1] == player and o.npcFormat[1] == npc)
local generated = format.Compile(o.checkFormat[1])
assert(generated[#generated].field == 'modifiers.fire' and generated[#generated-1].field == 'family')
custom.Settle(o); assert(o.checkFormat[1] == builder.Format(d, 'check'))
o.checkFormat[1] = '[difficulty]'
assert(not builder.Apply(o, d), 'external check-line edits must conflict')
d = builder.Load(o); o.checkSize[1] = 85
assert(not builder.Apply(o, d), 'external check appearance edits must conflict')
d = builder.Load(o)
for _, text in ipairs({ '[name]', '[/]', '[yellow]', '[#fff]text[/]', 'non-ASCII: \195\169' }) do
    d.checkParts = { { kind = 'text', text = text } }
    assert(builder.Validate(d), 'text cannot inject tokens or tags into either row')
end
d.checkParts = {}; assert(builder.Validate(d))
d.showCheckDetails[1] = false; assert(not builder.Validate(d))
d.parts = {}; assert(builder.Validate(d))
for i = 1, 24 do assert(builder.Insert(d, 'name', nil, nil, 'name')) end
assert(not builder.Insert(d, 'name', nil, nil, 'name') and builder.Insert(d, 'name', 1, 24, 'name'))
-- All source schema fields and individual modifiers can compile and resolve.
local mob = dofile('addons/name/data/147.lua').Names['Darksteel Quadav']
for key in pairs(mob) do assert(fields.ByKey[key:lower()], 'missing mobdb field: ' .. key) end
for key in pairs(mob.Modifiers) do assert(fields.ByKey['modifiers.' .. key:lower()]) end
for _, item in ipairs(fields.List) do
    local p = format.Compile('[mob: field=' .. item.field .. ', color=cyan, space=6]')[1]
    assert(p.kind == 'mob' and p.field == item.field and p.space == 6)
    assert(format.Compile(format.Serialize({p}))[1].field == item.field)
    assert(type(fields.Value(p, mob)) == 'string')
end
assert(fields.Value({kind='mob', field='notorious'}, mob) == 'Notorious: No')
assert(fields.Value({kind='mob', field='job'}, mob) == 'Job (ID): 7')
assert(fields.Value({kind='mob', field='subjob'}, {}) == '')
assert(fields.Value({kind='mob', field='spells'}, { Spells = {} }) == 'Spells (IDs): none')
assert(fields.Value({kind='mob', field='modifiers.fire'}, mob):find('1',1,true))
assert(format.Compile('[mob]')[1].kind == 'text' and format.Compile('[mob: field=nope]')[1].kind == 'text')

-- Actual tab order and mouse drag/release across the two workspaces.
o.monsterFormat[1], o.checkFormat[1] = '[name]', '[difficulty]'
d = builder.Load(o)
local last, pressed, mx, my, down, clicked, cursors, hovered = '', nil, 0, 0, false, false, 0, nil
local texts, buttons, pushedSizes = {}, {}, {}
imgui.PushFont = function(_, size) pushedSizes[#pushedSizes+1] = size end
imgui.GetCursorScreenPos = function() cursors = cursors+1; return 20, cursors == 1 and 20 or 200 end
imgui.GetMousePos = function() return mx, my end
imgui.IsMouseDown = function() return down end
imgui.IsMouseClicked = function() return clicked end
imgui.Button = function(label) last = label; buttons[label] = true; return pressed == label end
imgui.InvisibleButton = function(id) last = id end
imgui.IsItemHovered = function() return last == hovered end
imgui.CalcTextSize = function(text) return #text*7, 14 end
imgui.Text = function(text) texts[#texts+1] = text end
imgui.BeginCombo = function() return false end
imgui.TreeNode = function() return true end
imgui.Checkbox, imgui.RadioButton, imgui.SliderInt = function() return false end, function() return false end, function() return false end
local function frame()
    cursors, texts, pushedSizes = 0, {}, {}; builder.Draw(o)
    assert(pushedSizes[1] == (d.preview.distant[1] and o.minSize[1] or o.fontSize[1]), 'preview uses shared General sizes')
    assert(texts[1] == 'Example' and texts[2] == 'Builder' and texts[3] == 'Blocks', 'page order must be Example > Builder > Blocks')
    clicked, pressed = false, nil
end
mx, my, down, clicked, hovered = 30, 550, true, true, 'Letters##builder.add.name.letter'
frame()
mx, my, hovered = 300, 245, '##builder.workspace'; frame()
down = false; frame()
assert(#d.parts == 2 and d.parts[2].kind == 'letter')
mx, my, down, clicked = 165, 245, true, true; frame()
mx = 35; frame(); down = false; frame()
assert(d.parts[1].kind == 'letter', 'name-row blocks reorder')
mx, my, down, clicked, hovered = 30, 550, true, true, 'Family##builder.add.check.family'
frame()
mx, my, hovered = 580, 335, '##builder.workspace'; frame(); down = false; frame()
assert(#d.checkParts == 2 and d.checkParts[2].field == 'family', 'mobdb block must drop into check row')
mx, my, down, clicked = 150, 335, true, true; frame()
mx = 35; frame(); down = false; frame()
assert(d.checkParts[1].field == 'family', 'check information blocks reorder just like names')
local picker = imgui.ColorEdit4
imgui.ColorEdit4 = function(_, value) value[1], value[2], value[3] = 0.5, 0.25, 1; return true end
frame(); imgui.ColorEdit4 = picker
assert(d.checkParts[1].color == 0xFF8040FF)
assert(not buttons['Health bar##builder.add.health'] and not d.healthBarWidth and not d.showHealthBar)
assert(o.checkFormat[1] == '[difficulty]', 'check-row dragging is draft-only')
d.preview.distant[1] = true
o.minSize[1] = 13; frame()
assert(pushedSizes[1] == 13, 'distant preview follows General changes immediately')
d.preview.distant[1] = false
assert(not buttons['Nearby name size (px)##builder.fontSize'] and not d.fontSize)
pressed = 'Apply to Enemy Names##builder.apply'; frame()
assert(format.Compile(o.checkFormat[1])[1].field == 'family' and o.healthBarWidth[1] == 157)
pressed = 'Reload Current##builder.reload'; frame()
local other = {}; custom.Defaults(other); custom.Settle(other)
assert(not builder.Apply(other, d))
H.tab(5); H.command('/name'); H.frames(1); H.command('/name')
H.print('enemy builder: Example/Builder/Blocks order, two-row dragging, complete mobdb catalog, isolated apply and untouched health settings', true)
