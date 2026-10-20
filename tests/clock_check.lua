-- The clock addon (through tests/clock_stand_in.lua): one line where the game writes its clock, no
-- background, its font, the compass hidden, the settings, and letting go of the game's clock.
local imgui = require('imgui')
local fields = require('fields')
local p = H.print

-- the line
local raws = CLOCK.raws
local time = package.loaded['ffxi.time']
local context = fields.Context(time, '(H-9)', 'Rain')
local function Line(format, c) return fields.Line(c or context, format) end
p('the default line: time, grid, day, date, moon', Line(fields.Default) == '3:32  (H-9)  Windsday  900/12/30  Moon 42%')
p('every field from one timestamp', CLOCK.raws == raws + 1)
local noGrid = fields.Context(time, nil)
p('no grid: left out, with the spaces before it', Line(fields.Default, noGrid) == '3:32  Windsday  900/12/30  Moon 42%',
    Line(fields.Default, fields.Context(time, '')) == Line(fields.Default, noGrid))
p('dividers written as they are', Line('{time} | {grid} | {day}') == '3:32 | (H-9) | Windsday')
p('a field with nothing takes its divider away', Line('{time} | {grid} | {day}', noGrid) == '3:32 | Windsday')
p('the first, the one after it', Line('{grid} | {time} | {day}', noGrid) == '3:32 | Windsday')
p('words before, between and after kept', Line('[{time}] {day}!') == '[3:32] Windsday!')
p('a word in braces that is no field, as it is; any case', Line('{TIME} {nope}') == '3:32 {nope}')
p('weather by name', Line('{time} · {weather}') == '3:32 · Rain')
p('an empty line', Line('') == '', Line('   ') == '   ')
p('which fields a line has', fields.Has(fields.Default, 'time'), not fields.Has(fields.Default, 'weathericon'),
    not fields.Uses(fields.Default, 'exp'), fields.Uses('{time} {rate}', 'exp'))
-- 0.6's list to tick and move, as a line
p('0.6\'s list: the ticked, in order, two spaces apart', fields.FromList({ 'moon', 'gone', 'time', 'weatherIcon', 'level', 'expRate' },
    { moon = true, time = true, weatherIcon = true, level = true, expRate = true }, { exp = false }) == '{moon}  {time}  {weathericon}',
    fields.FromList({ 'moon', 'level', 'toLevel', 'expRate' }, { moon = true, level = true, toLevel = true, expRate = true }, { exp = true })
        == '{moon}  {level}  {tnl}  {rate}',
    fields.FromList({ 'time' }, { time = false }, {}) == '')

-- what the clock's window is asked
local begin, finish, setPos, pushFont, calc = imgui.Begin, imgui.End, imgui.SetNextWindowPos, imgui.PushFont, imgui.CalcTextSize
local inside, windows, placed, sized, measured = nil, {}, nil, nil, nil
imgui.Begin = function(name, open, flags) inside = name; windows[name] = flags; return begin(name, open, flags) end
imgui.End = function(...) inside = nil; return finish(...) end
imgui.SetNextWindowPos = function(pos, cond, pivot) placed = { pos[1], pos[2], pivot }; return setPos(pos, cond, pivot) end
imgui.PushFont = function(font, size) if inside == 'clock.native' then sized = size end; return pushFont(font, size) end
imgui.CalcTextSize = function(words) if inside == 'clock.native' then measured = words end; return calc(words) end
local function Since(mark)
    local seen = {}
    for i = mark + 1, #CLOCK.log do seen[#seen + 1] = CLOCK.log[i] end
    return table.concat(seen, ' ')
end
local function Has(list, word) return (' ' .. list .. ' '):find(' ' .. word .. ' ', 1, true) ~= nil end

H.load()
p('0.1\'s saved settings load, and are brought over', H.options().replace[1] == true, H.options().enabled == nil, H.options().x == nil)
local mark = #CLOCK.log
H.frames(2)
local seen = Since(mark)
p('before uihook has seen the clock: none of its own, the game\'s left alone', windows['clock.native'] == nil, Has(seen, 'clock.stop'), not Has(seen, 'clock.begin'))
p('the compass hidden from the start', Has(seen, 'compass.begin'))

CLOCK.rect = { 26, 1098, 106, 1108 }
mark = #CLOCK.log
H.frames(1)
seen = Since(mark)
p('drawn where the game writes its clock: its left, its middle', placed[1] == 26, placed[2] == 1103, placed[3][1] == 0 and placed[3][2] == 0.5)
p('the line, with the game\'s grid', measured == '3:32  (H-9)  Windsday  900/12/30  Moon 42%')
p('no background', bit.band(windows['clock.native'], ImGuiWindowFlags_NoBackground) ~= 0)
p('begun, then captured inside its window', Has(seen, 'clock.begin'), Has(seen, 'clock.capture'))
p('outlined: the words drawn with their edge', (H.calls['draw.AddText'] or 0) >= 5)
p('Font Size 0: the theme\'s size', sized == 14)
local options = H.options()
local texts = H.calls['draw.AddText'] or 0
H.frames(1)
p('Outline 1: the words and their edge, four times over', (H.calls['draw.AddText'] or 0) - texts == 5)
require('winxi.theme').Get().TextOutline = 0 -- the theme's, for every addon
texts = H.calls['draw.AddText'] or 0
H.frames(1)
p('Outline 0: the words alone', (H.calls['draw.AddText'] or 0) - texts == 1)
require('winxi.theme').Get().TextOutline = 1
options.fontSize[1] = 28
H.frames(1)
p('Font Size 28', sized == 28)
options.fontSize[1] = 0

-- Attached chat: the full Winxi frame is captured, with the chat's width and top edge.
local setSize, requested = imgui.SetNextWindowSize, nil
imgui.SetNextWindowSize = function(size, ...)
    requested = { size[1], size[2] }; return setSize(size, ...)
end
local window = require('winxi.window')
local plain, stripOptions = window.Plain, nil
window.Plain = function(name, open, flags, draw, options)
    if name == 'clock.native' then stripOptions = options end
    return plain(name, open, flags, draw, options)
end
local outlined = require('winxi.text')
local drawText, textAt = outlined.Draw, nil
outlined.Draw = function(list, x, y, color, words, ...)
    textAt = { x, y, imgui.CalcTextSize(words) }
    return drawText(list, x, y, color, words, ...)
end
CLOCK.chat = { 8, 1080, 648, 1200 }
mark = #CLOCK.log
H.frames(1)
p('attached: frame bottom on chat top, left aligned', placed[1] == 8, placed[2] == 1080,
    placed[3][1] == 0 and placed[3][2] == 1)
p('attached: chat width, input-style line height', requested[1] == 640, requested[2] == 20)
p('attached: contents centered horizontally and vertically', textAt[1] == 8 + (640 - textAt[3]) / 2,
    textAt[2] == 1080 - 20 + (20 - 14) / 2)
CLOCK.input = { 8, 1200, 648, 1224 }
H.frames(1)
p('attached: native input height matched', requested[2] == 24)
CLOCK.input = nil
H.frames(1)
p('attached: input height retained when typing closes', requested[2] == 24)
outlined.Draw = drawText
p('attached: themed background, capture after drawing', bit.band(windows['clock.native'], ImGuiWindowFlags_NoBackground) == 0,
    Has(Since(mark), 'clock.capture'))
CLOCK.chat[3] = 808
H.frames(1)
p('attached: resized chat width followed', requested[1] == 800)
p('attached: compact padding and no exterior shadow', stripOptions.padding == 3, stripOptions.shadow == false)
p('attached: explicit width wins over auto resize', bit.band(windows['clock.native'], ImGuiWindowFlags_AlwaysAutoResize) == 0)
window.Plain = plain
CLOCK.chat = nil
H.frames(1)
p('detached: transparent native placement restored', placed[1] == 26, placed[2] == 1103,
    bit.band(windows['clock.native'], ImGuiWindowFlags_NoBackground) ~= 0)
imgui.SetNextWindowSize = setSize

-- the icons: the game's, unless the chosen set has a picture for the day or the weather
local icons = require('icons')
local function Images() return H.calls['draw.AddImage'] or 0 end
-- where each picture went: the last drawn, as { handle, left, top, right, bottom }
local drawn = {}
rawset(imgui.GetWindowDrawList(), 'AddImage', function(_, handle, from, to)
    H.calls['draw.AddImage'] = (H.calls['draw.AddImage'] or 0) + 1
    drawn[#drawn + 1] = { handle, from[1], from[2], to[1], to[2] }
end)
local function At(entry, l, t, r, b) return entry ~= nil and entry[2] == l and entry[3] == t and entry[4] == r and entry[5] == b end
CLOCK.icons[0] = { 8, 1096, 24, 1112 }
local images = Images()
H.frames(1)
p('no set: the game\'s icons, none of its own', CLOCK.hidden == 0, Images() == images)
p('the line clear of the game\'s day icon (8 to 24), four pixels on: 28, past the game\'s text at 26', placed[1] == 28)
local listed = icons.Sets()
p('the sets: the folders of icons, files left out', #listed == 1 and listed[1].key == 'mine')
options.iconSet = 'mine'
H.frames(1)
p('a set with no picture for Windsday: still the game\'s', CLOCK.hidden == 0)
CLOCK.files['days/windsday'] = true
icons.Forget()
images = Images()
H.frames(1)
p('a picture for Windsday: the game\'s day icon left undrawn, ours where it was', CLOCK.hidden == 1, Images() == images + 1)
CLOCK.icons[0] = nil
H.frames(1)
p('until uihook has seen where the day icon goes, the game\'s', CLOCK.hidden == 0)
CLOCK.icons[0] = { 8, 1096, 24, 1112 }
-- a clear sky, which the game draws no icon for: the set's where the game's weather icon would be,
-- 68 of the game's units above its day icon, which is 16 of them across
CLOCK.files['weather/clear'] = true
CLOCK.weather = 1
drawn = {}
H.frames(1)
p('sunshine: the clear sky, above the day icon, none of the game\'s hidden', CLOCK.hidden == 1, At(drawn[#drawn], 8, 1028, 24, 1044))
CLOCK.icons[0] = { 8, 1096, 40, 1128 }
drawn = {}
H.frames(1)
p('the game\'s icons drawn twice as large: twice as far up', At(drawn[#drawn], 8, 960, 40, 992))
CLOCK.icons[0] = { 8, 1096, 24, 1112 }
CLOCK.weather, CLOCK.icons[1], CLOCK.icons[2] = 7, { 8, 1030, 24, 1046 }, { 24, 1030, 40, 1046 }
CLOCK.files['weather/water'] = true
images = Images()
H.frames(1)
p('a squall, double water: both weather icons ours, beside the day\'s', CLOCK.hidden == 3, Images() == images + 3,
    At(drawn[#drawn - 1], 8, 1030, 24, 1046), At(drawn[#drawn], 24, 1030, 40, 1046))
CLOCK.weather = 4
H.frames(1)
p('a hot spell, no fire picture: the game\'s weather icon', CLOCK.hidden == 1)
CLOCK.weather = 2
H.frames(1)
p('clouds, for which the game draws none: none hidden', CLOCK.hidden == 1)
CLOCK.weather, CLOCK.icons[1], CLOCK.icons[2] = 0, nil, nil
drawn = {}
H.frames(1)
p('no weather: the clear sky where the game was last seen to put its weather icon', CLOCK.hidden == 1, At(drawn[#drawn], 8, 1030, 24, 1046))
-- Weather Offset: the game's weather icon moved in its units, the set's with it
options.weatherOffset[1] = -6
drawn = {}
H.frames(1)
p('Weather Offset -6: the game\'s moved 6 of its units, the clear sky 6 pixels up', CLOCK.shift == -6, At(drawn[#drawn], 8, 1024, 24, 1040))
CLOCK.icons[0] = { 8, 1096, 40, 1128 }
H.frames(1)
p('the game\'s icons twice as large: 3 of its units', CLOCK.shift == -3)
CLOCK.icons[0] = { 8, 1096, 24, 1112 }
options.weatherOffset[1] = 0
H.frames(1)
p('back to 0', CLOCK.shift == 0)
-- Show All Weather Icons: a row from the weather icon's place, the set's where it has them
local check = imgui.Checkbox
imgui.Checkbox = function(label, value, ...)
    if label == '##clock.showAll' and TURN_ALL ~= nil then value[1] = TURN_ALL; TURN_ALL = nil; return true end
    return check(label, value, ...)
end
H.tab(5) -- Icons
H.command('/clock')
TURN_ALL = true
drawn = {}
H.frames(1)
local function DrawnAt(l, t, r, b) for _, d in ipairs(drawn) do if At(d, l, t, r, b) then return true end end return false end
p('all shown: the game\'s own for each element the set has no picture for, water and the clear sky the set\'s',
    CLOCK.preview == 0xFF - 32, DrawnAt(98, 1030, 114, 1046), DrawnAt(152, 1030, 168, 1046), bit.band(CLOCK.hidden, 2) ~= 0)
TURN_ALL = false
H.frames(1)
p('turned off: none of the game\'s drawn for it', CLOCK.preview == 0)
H.command('/clock')
-- Weather Scale: the game's weather icons drawn larger by uihook, the set's with them
options.weatherScale[1] = 2
CLOCK.weather, CLOCK.icons[1], CLOCK.icons[2] = 7, { 8, 1030, 24, 1046 }, { 24, 1030, 40, 1046 }
drawn = {}
H.frames(1)
p('Weather Scale 2: handed to uihook, a squall\'s two the set\'s, twice as large and side by side', CLOCK.scale == 2,
    DrawnAt(0, 1022, 32, 1054), DrawnAt(32, 1022, 64, 1054), DrawnAt(8, 1096, 24, 1112))
H.command('/clock')
TURN_ALL = true
drawn = {}
H.frames(1)
p('all shown at Weather Scale 2: the row as far apart as the grown icons and two', DrawnAt(170, 1022, 202, 1054))
TURN_ALL = false
H.frames(1)
H.command('/clock')
options.weatherScale[1] = 1
CLOCK.icons[1], CLOCK.icons[2] = nil, nil
imgui.Checkbox = check
local loads = CLOCK.loads
H.frames(5)
p('each picture loaded once', CLOCK.loads == loads, loads == 3)
H.command('/clock off')
H.frames(1)
p('off: the game\'s icons back', CLOCK.hidden == 0)
H.command('/clock on')

-- Icon Scale: the set's icons grown about their middles where the game draws its own
CLOCK.weather = 7
CLOCK.icons[1], CLOCK.icons[2] = { 8, 1030, 24, 1046 }, { 24, 1030, 40, 1046 }
options.iconScale[1] = 2
drawn = {}
H.frames(1)
p('Icon Scale 2: the day icon twice as large about its middle', At(drawn[#drawn - 2], 0, 1088, 32, 1120))
p('and the line clear of it, four pixels on', placed[1] == 36)
options.iconScale[1] = 1

-- Weather Icon: the weather's picture in the line, the game's hidden, nothing above
options.format = fields.Default .. '  {weathericon}'
H.frames(9)
drawn = {}
local hiddenBefore = CLOCK.hidden
H.frames(1)
local inline = drawn[1]
p('in the line: the game\'s weather icons hidden, the day icon still the set\'s', CLOCK.hidden == 3,
    #drawn == 2, inline ~= nil and inline[3] == 20 and inline[5] - inline[3] == 14)
options.iconScale[1] = 2
H.frames(1)
p('in the line at Icon Scale 2: twice the text\'s height', drawn[#drawn - 1][5] - drawn[#drawn - 1][3] == 28)
options.iconScale[1] = 1
CLOCK.weather = 4
H.frames(9)
drawn = {}
H.frames(1)
p('in the line, no picture for a hot spell: the game\'s above, nothing in the line', CLOCK.hidden == 1, #drawn == 1)
options.format = fields.Default

options.iconSet = icons.None
CLOCK.weather, CLOCK.icons = nil, {}
H.frames(1)

-- the compass
options.hideCompass[1] = false
mark = #CLOCK.log
H.frames(1)
seen = Since(mark)
p('Hide Compass off: the compass given back, not hidden', Has(seen, 'compass.stop'), not Has(seen, 'compass.begin'))
options.hideCompass[1] = true

-- the commands
p('/clock off', H.command('/clock off'), options.replace[1] == false)
windows['clock.native'], mark = nil, #CLOCK.log
H.frames(1)
seen = Since(mark)
p('off: the game\'s clock given back, nothing drawn', Has(seen, 'clock.stop'), windows['clock.native'] == nil, Has(seen, 'compass.begin'))
p('/clock on', H.command('/clock on'), options.replace[1] == true)
local before = #H.printed
p('/clock status says the clock and the compass', H.command('/clock status'), #H.printed == before + 2,
    tostring(H.printed[before + 1]):find('Drawn in place', 1, true) ~= nil, tostring(H.printed[before + 2]):find('Compass', 1, true) ~= nil)
local widgets = require('winxi.widgets')
local themeTab, themeTabs = widgets.BeginThemeTab, 0
widgets.BeginThemeTab = function(...) themeTabs = themeTabs + 1; return themeTab(...) end
H.tab(1)
p('/clock opens the settings', H.command('/clock'))
local generalInputs = H.calls.InputText or 0
H.frames(1)
p('General keeps data editors out of visibility controls', (H.calls.InputText or 0) == generalInputs)
H.tab(5)
local sliders = H.calls.SliderFloat or 0
H.frames(1)
p('the settings: Icon Scale among them, and no Winxi Theme tab', (H.calls.SliderFloat or 0) > sliders, themeTabs == 0)
H.tab(4)
local headers, combos, colors = H.calls.CollapsingHeader or 0, H.calls.BeginCombo or 0, H.calls.ColorEdit4 or 0
H.frames(1)
p('Text tab: Font, Font Size, Text Color', (H.calls.BeginCombo or 0) - combos == 1, (H.calls.ColorEdit4 or 0) - colors == 1)
H.tab(3)
local smalls, inputs = H.calls.SmallButton or 0, H.calls.InputText or 0
local setWidth, widths = imgui.SetNextItemWidth, {}
imgui.SetNextItemWidth = function(width, ...) widths[#widths + 1] = width; return setWidth(width, ...) end
H.frames(1)
imgui.SetNextItemWidth = setWidth
p('the line\'s box a width of its own: the settings window fits itself to it, and one as wide as the window shrinks it',
    #widths > 0, (function() for _, w in ipairs(widths) do if not (w > 0) then return false end end return true end)())
p('the Line section: the line to write, five dividers and Default', (H.calls.InputText or 0) - inputs == 1,
    (H.calls.SmallButton or 0) - smalls == 6)
-- a button pressed: the field after two spaces, a divider in place of the spaces at the end
local small, combo, selectable = imgui.SmallButton, imgui.BeginCombo, imgui.Selectable
local pressed = nil
imgui.SmallButton = function(label, ...) small(label, ...); return label == pressed end
-- Add Field's list, open, and a field in it chosen
imgui.BeginCombo = function(label, ...) combo(label, ...); return label == '##clock.addField' and pressed ~= nil and pressed:find('##clock.add.', 1, true) ~= nil end
imgui.Selectable = function(label, ...) selectable(label, ...); return label == pressed end
options.format = '{time}  '
pressed = '|##clock.divider.1'
H.frames(1)
p('a divider: in place of the spaces', options.format == '{time} | ')
pressed = 'Map Grid  {grid}##clock.add.grid'
H.frames(1)
p('a field: after the divider, as it is', options.format == '{time} | {grid}')
pressed = 'Moon  {moon}##clock.add.moon'
H.frames(1)
p('a field after a field: two spaces between', options.format == '{time} | {grid}  {moon}')
pressed = 'Default##clock.formatDefault'
H.frames(1)
p('Default: the line a new character has', options.format == fields.Default)
pressed = nil
imgui.SmallButton, imgui.BeginCombo, imgui.Selectable = small, combo, selectable
-- written: the line follows by its next reading, a quarter of a second
options.format = '{grid} | {time}'
H.frames(9)
p('the line follows the settings', measured == '(H-9) | 3:32', measured)
options.format = fields.Default
H.command('/clock')

-- a capability uihook does not have: nothing of its own drawn
CLOCK.ready[1] = false
windows['clock.native'] = nil
H.frames(1)
p('uihook without the clock: no window of its own', windows['clock.native'] == nil)
CLOCK.ready[1] = true

-- 0.1's settings given again, off: brought over as off
options.enabled, options.x, options.y = false, 20, -1
H.resettle()
options = H.options()
p('0.1 settings brought over', options.replace[1] == false and options.enabled == nil, options.x == nil and options.y == nil)
options.fontSize[1] = 99
H.resettle()
p('a font size out of range is brought in', H.options().fontSize[1] == 48)
-- 0.8's Text Scale, against the theme's size: a Font Size the first time the line is drawn
options = H.options()
options.textScale, options.fontSize[1], options.replace[1] = T{ 2 }, 0, true
H.resettle()
H.frames(1)
p('Text Scale 2 brought over: twice the theme\'s 14', H.options().textScale == nil, H.options().fontSize[1] == 28)
options = H.options()
options.fontSize[1], options.replace[1] = 0, false

mark = #CLOCK.log
H.unload()
seen = Since(mark)
p('unloaded: the clock and the compass given back', Has(seen, 'clock.stop'), Has(seen, 'compass.stop'))

-- the set that comes with the addon: every day, every element, and the skies the game draws none for
local missing = {}
for _, name in ipairs({ 'days/firesday', 'days/earthsday', 'days/watersday', 'days/windsday', 'days/iceday',
    'days/lightningday', 'days/lightsday', 'days/darksday', 'weather/fire', 'weather/ice', 'weather/wind',
    'weather/earth', 'weather/thunder', 'weather/water', 'weather/light', 'weather/dark', 'weather/clear', 'weather/clouds',
    'weather/fog' }) do
    local file = io.open('addons/clock/icons/gems/' .. name .. '.png', 'rb')
    if file then file:close() else missing[#missing + 1] = name end
end
p('the gems set is whole', #missing == 0, table.concat(missing, ' '))

-- experience
local exp = require('exp')
local function Message(actor, amount, message)
    local function le(n, bytes) local s = '' for _ = 1, bytes do s = s .. string.char(n % 256); n = math.floor(n / 256) end return s end
    return le(0, 4) .. le(actor, 4) .. le(actor, 4) .. le(0, 4) .. le(amount, 4) .. le(0, 4) .. le(message, 2) .. le(0, 2)
end
p('commas', exp.Commas(0) == '0', exp.Commas(999) == '999', exp.Commas(1000) == '1,000', exp.Commas(12345678) == '12,345,678')
exp.Reset(1000)
p('a gain of the player\'s own is counted', exp.Packet(0x02D, Message(CLOCK.id, 200, 8), 1000))
p('an EXP chain and limit points too', exp.Packet(0x02D, Message(CLOCK.id, 300, 253), 1100), exp.Packet(0x02D, Message(CLOCK.id, 50, 371), 1200),
    exp.Packet(0x02D, Message(CLOCK.id, 50, 372), 1200))
p('not another\'s, another message or another packet', not exp.Packet(0x02D, Message(5, 999, 8), 1200),
    not exp.Packet(0x02D, Message(CLOCK.id, 999, 6), 1200), not exp.Packet(0x028, Message(CLOCK.id, 999, 8), 1200),
    not exp.Packet(0x02D, 'short', 1200))
local snap = exp.Snapshot(1000 + 1800, 3600)
p('the rate: 600 in half an hour, 1,200 an hour', snap.rate == 1200, snap.level == 75, snap.current == 12345, snap.needed == 30000)
p('at least a minute: one gain at once is not a great rate', (function()
    exp.Reset(5000); exp.Packet(0x02D, Message(CLOCK.id, 100, 8), 5000)
    return exp.Snapshot(5001, 3600).rate == 6000
end)())
exp.Reset(0)
exp.Packet(0x02D, Message(CLOCK.id, 100, 8), 0)
exp.Packet(0x02D, Message(CLOCK.id, 300, 8), 3000)
p('over the window alone: the first gain an hour and more ago forgotten', exp.Snapshot(3700, 3600).rate == 300)
p('since: when it began, how many', select(2, exp.Since()) == 2)

-- the fields
local c = fields.Context(time, nil, nil)
c.exp = { level = 75, current = 12345, needed = 30000, limit = false, points = 4000, merits = 3, rate = 4200 }
local experience = '{level}  {exp}  {tnl}  {rate}'
p('the experience fields', Line(experience, c) == 'Lv75  12,345/30,000  TNL 17,655  4,200 EXP/hr')
p('none while not counted', Line(experience, fields.Context(time, nil, nil)) == '')
c.exp.limit = true
p('in limit mode: limit points to the next merit', Line(experience, c) == 'Lv75  LP 4,000/10,000  TNM 6,000  4,200 LP/hr')
c.exp.limit, c.exp.needed = false, 0
p('no level to go to: the experience alone, no TNL', Line(experience, c) == 'Lv75  12,345  4,200 EXP/hr')
c.weatherIcon = 1234
local pieces = fields.Segments(c, '{weathericon} {level}')
p('the weather icon a piece of its own, the words after it', #pieces == 2, type(pieces[1]) == 'table' and pieces[1].icon == 1234,
    pieces[2] == ' Lv75')

-- in the clock: off to begin with, then on, counted from packets
H.load()
options = H.options()
options.replace[1] = true -- left off by the 0.1 settings above
CLOCK.rect = { 26, 1098, 106, 1108 }
H.frames(9)
p('no experience field: not on the line', measured ~= nil and not measured:find('Lv75', 1, true))
local before = select(2, exp.Since())
H.packetData(0x02D, Message(CLOCK.id, 500, 8))
p('nor counted', select(2, exp.Since()) == before)
options.format = fields.Default .. '  {level}  {exp}  {tnl}  {rate}'
H.frames(9)
p('in the line: written, after the clock\'s own fields', measured ~= nil and measured:find('Moon 42%  Lv75  12,345/30,000  TNL 17,655', 1, true) ~= nil, measured)
H.packetData(0x02D, Message(CLOCK.id, 500, 8))
p('and counted', select(2, exp.Since()) == before + 1)
p('/clock exp reset', H.command('/clock exp reset'), select(2, exp.Since()) == 0)
H.tab(3)
H.command('/clock')
local smalls2 = H.calls.SmallButton or 0
H.frames(1)
p('with experience in the line, Begin Again', (H.calls.SmallButton or 0) - smalls2 == 7)
H.command('/clock')

-- 0.6's settings: a list to tick and move, and experience a switch, brought over as a line
options.order, options.shown = T{ 'moon', 'time', 'level', 'expRate' }, T{ moon = true, time = true, level = true, expRate = true }
options.experience, options.expWindow = T{ true }, T{ 30 }
H.resettle()
options = H.options()
p('0.6 settings brought over', options.format == '{moon}  {time}  {level}  {rate}', options.order == nil and options.shown == nil,
    options.experience == nil and options.expWindow == nil)

-- Full info panel: legacy mode above remains unchanged and can be selected again.
local panel = require('panel')
options.panel = panel.Defaults()
local shadow = require('winxi.shadow')
local drawShadow, capturedShadow = shadow.Draw, nil
shadow.Draw = function(captured) capturedShadow = captured; return drawShadow(captured) end
options.panel.slots[1].format = '{level}'
options.replace[1] = true
CLOCK.chat = { 8, 1080, 648, 1200 }
CLOCK.input = { 8, 1200, 648, 1224 }
local panelSize, originalSize = nil, imgui.SetNextWindowSize
imgui.SetNextWindowSize = function(size, ...)
    panelSize = {size[1],size[2]}; return originalSize(size,...)
end
mark = #CLOCK.log
H.frames(1)
p('full panel: attached to upper chat with input height', windows['clock.panel'] ~= nil,
    placed[1] == 8, placed[2] == 1056, panelSize[1] == 640, panelSize[2] == 24,
    Has(Since(mark),'clock.capture'))
p('full panel: shared shadow included in native capture', capturedShadow == true)
shadow.Draw = drawShadow
local beforePanelEXP = select(2,exp.Since())
options.format = '{time}'
H.packetData(0x02D, Message(CLOCK.id, 500, 8))
p('full panel: experience counted from slot formats, not legacy line',select(2,exp.Since())==beforePanelEXP+1)
options.panel.width[1],options.panel.height[1] = 900,40
H.frames(1)
p('full panel: custom width and height',panelSize[1]==900,panelSize[2]==40,placed[2]==1040)
options.panel.attached[1]=false
options.panel.x[1],options.panel.y[1]=50,70
H.frames(1)
p('full panel: custom top-left position',placed[1]==50,placed[2]==70)
options.panel.dayPlace[1],options.panel.weatherPlace[1]=2,2
H.frames(1)
p('full panel: native icon placement leaves icons alone',CLOCK.hidden==0)
options.panel.slots[1].format='{dayicon} {level}'
H.frames(1)
p('full panel: inline token takes precedence over native placement',bit.band(CLOCK.hidden,1)~=0)
H.command('/clock')
local checkbox, labels = imgui.Checkbox, {}
imgui.Checkbox = function(label, ...) labels[label]=true; return checkbox(label,...) end
for tab=1,5 do
    H.tab(tab)
    local inputCount = H.calls.InputText or 0
    H.frames(1)
    p('full panel: data editors isolated to Data tab '..tab,
        (H.calls.InputText or 0)-inputCount == (tab==3 and 3 or 0))
end
imgui.Checkbox = checkbox
p('full panel: legacy weather preview hidden',not labels['##clock.showAll'])
p('full panel: mode and icon controls remain accessible',labels['##panel.enabled'],labels['##panel.dayAfter'])
H.command('/clock'); H.tab(1)
p('full panel: settings render',windows['clock.panel'] ~= nil)
options.panel.enabled[1]=false
H.frames(1)
p('full panel: legacy line still available',windows['clock.native'] ~= nil)
imgui.SetNextWindowSize = originalSize
CLOCK.chat,CLOCK.input=nil,nil
