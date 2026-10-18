-- widgets.FontFile, FontSize and Lock: an addon's own font and its size, and a locked window, as every
-- addon offers them; and winxi.text's edge from the theme
local widgets = require('winxi.widgets')
local theme = require('winxi.theme')
local fonts = require('winxi.fonts')
local text = require('winxi.text')
local window = require('winxi.window')
local imgui = require('imgui')

fonts.Files = function() return { 'arial.ttf', 'tahoma.ttf' } end
local labels, combos, sliders, chosen = {}, {}, {}, nil
imgui.Text = function(words) labels[#labels + 1] = words end
imgui.BeginCombo = function(id, shown) combos[id] = shown; return true end
imgui.Selectable = function(label) return label:match('^[^#]+') == chosen end
imgui.SliderInt = function(id, box, low, high, format) sliders[id] = { low = low, high = high, format = format }; return false end

local options = { fontFile = '', fontSize = { 0 } }
local changed = widgets.FontFile(options, 'fontFile', '##x.fontFile')
H.print('the theme\'s font to begin with, nothing changed', combos['##x.fontFile'] == 'Theme Font', not changed, labels[#labels] == 'Font:')
chosen = 'tahoma.ttf'
changed = widgets.FontFile(options, 'fontFile', '##x.fontFile')
H.print('a font chosen: kept, and said to have changed', options.fontFile == 'tahoma.ttf', changed)
changed = widgets.FontFile(options, 'fontFile', '##x.fontFile')
H.print('chosen again: not a change', not changed, combos['##x.fontFile'] == 'tahoma.ttf')
chosen = 'Theme Font'
local count = #labels
changed = widgets.FontFile(options, 'fontFile', '##x.fontFile', { label = false })
H.print('back to the theme\'s, with no name of its own', options.fontFile == '', changed, #labels == count)
chosen = nil
widgets.FontFile(options, 'fontFile', '##x.fontFile', { theme = 'Chat Font' })
H.print('the theme\'s own called what the addon says', combos['##x.fontFile'] == 'Chat Font')

widgets.FontSize(options, 'fontSize', '##x.fontSize')
local slider = sliders['##x.fontSize']
H.print('size 0: Theme Size, up to the theme\'s most', slider.format == 'Theme Size', slider.low == 0, slider.high == theme.MaxFontSize, labels[#labels] == 'Font Size:')
options.fontSize[1] = 18
widgets.FontSize(options, 'fontSize', '##x.fontSize', { max = 48 })
H.print('a size: in pixels', sliders['##x.fontSize'].format == '%d px', sliders['##x.fontSize'].high == 48)
options.fontSize[1] = 0
widgets.FontSize(options, 'fontSize', '##x.fontSize', { min = 8, max = 24 })
H.print('a range from above 0 offers no theme size', sliders['##x.fontSize'].format == '%d px', sliders['##x.fontSize'].low == 8)

local box, told = { false }, nil
imgui.Checkbox = function(_, value) value[1] = not value[1]; return true end
changed = widgets.Lock(box, '##x.locked', { onChanged = function(value) told = value end })
H.print('Lock Window: changed, and the addon told', changed, box[1] == true, told == true, labels[#labels] == 'Lock Window:')
widgets.Lock(box, '##x.locked', { label = 'Lock' })
H.print('under a name of the addon\'s own', labels[#labels] == 'Lock:')

-- the edge round text over a bar or the game is the theme's, in thickness and colour
local look = theme.Get()
local drawn = {}
local list = { AddText = function(_, pos, color, words) drawn[#drawn + 1] = { pos[1], pos[2], color, words } end }
imgui.GetColorU32 = function(color) return color[1] * 1000 + color[4] end
look.TextOutline = 1
drawn = {}
text.Draw(list, 10, 20, { 1, 1, 1, 1 }, 'hp')
H.print('Text Outline 1: four dark copies a pixel out, then the words', #drawn == 5, drawn[1][1] == 9 and drawn[1][2] == 19, drawn[5][1] == 10 and drawn[5][4] == 'hp')
look.TextOutline = 2
drawn = {}
text.Draw(list, 10, 20, { 1, 1, 1, 1 }, 'hp')
H.print('Text Outline 2: two pixels out', #drawn == 5, drawn[1][1] == 8 and drawn[4][2] == 22, text.Edge() == 2)
look.TextOutline = 0
drawn = {}
text.Draw(list, 10, 20, { 1, 1, 1, 1 }, 'hp')
H.print('Text Outline 0: the words alone', #drawn == 1 and drawn[1][4] == 'hp')
drawn = {}
text.Draw(list, 10, 20, { 1, 1, 1, 1 }, 'hp', 1)
H.print('an edge the addon asks for is drawn whatever the theme says', #drawn == 5)
look.TextOutline = 1
look.TextOutlineColor[1], look.TextOutlineColor[4] = 0.5, 0.8
drawn = {}
text.Draw(list, 10, 20, { 1, 1, 1, 1 }, 'hp')
local edge = text.EdgeColor()
H.print('Outline Color: the theme\'s, for the dark copies', drawn[1][3] == 500.8, edge[1] == 0.5 and edge[4] == 0.8, text.OutlineColor == edge)
theme.Reset({ 'TextOutline', 'TextOutlineColor' })
H.print('reset with the game windows\' values', look.TextOutline == 1 and look.TextOutlineColor[1] == 0)

-- a locked window is held still, and one the mouse goes through takes no input
-- (the stand-in numbers imgui's flags as they are first asked for, so they are compared whole)
local flagsSeen = nil
imgui.Begin = function(_, _, flags) flagsSeen = flags; return false end
local bit = require('bit')
window.Plain('x', { true }, 0, function() end, { locked = true })
H.print('locked: NoMove', flagsSeen == ImGuiWindowFlags_NoMove)
window.Plain('x', { true }, 0, function() end, { clickThrough = true })
H.print('click through: NoInputs', flagsSeen == ImGuiWindowFlags_NoInputs)
window.Plain('x', { true }, 0, function() end, { locked = true, clickThrough = true })
H.print('both: Lock Window over the game', flagsSeen == bit.bor(ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoInputs))
window.Plain('x', { true }, 0, function() end, { locked = false, clickThrough = false })
H.print('neither: the flags as given', flagsSeen == 0)
