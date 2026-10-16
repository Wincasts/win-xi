-- The clock addon (through tests/clock_stand_in.lua): one line where the game writes its clock, no
-- background, its text scale, the compass hidden, the settings, and letting go of the game's clock.
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
p('text scale 1: the theme\'s size', sized == 14)

local options = H.options()
options.textScale[1] = 2
H.frames(1)
p('text scale 2: twice the theme\'s size', sized == 28)
options.textScale[1] = 1

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
p('/clock opens the settings', H.command('/clock'))
local sliders = H.calls.SliderFloat or 0
H.frames(1)
p('the settings: Text Scale among them', (H.calls.SliderFloat or 0) > sliders)
local smalls, inputs = H.calls.SmallButton or 0, H.calls.InputText or 0
H.frames(1)
p('the Line section: the line to write, a button a field, five dividers and Default', (H.calls.InputText or 0) - inputs == 1,
    (H.calls.SmallButton or 0) - smalls == #fields.All + 6)
-- a button pressed: the field after two spaces, a divider in place of the spaces at the end
local small = imgui.SmallButton
local pressed = nil
imgui.SmallButton = function(label, ...) small(label, ...); return label == pressed end
options.format = '{time}  '
pressed = '|##clock.divider.1'
H.frames(1)
p('a divider: in place of the spaces', options.format == '{time} | ')
pressed = 'Map Grid##clock.add.grid'
H.frames(1)
p('a field: after the divider, as it is', options.format == '{time} | {grid}')
pressed = 'Moon##clock.add.moon'
H.frames(1)
p('a field after a field: two spaces between', options.format == '{time} | {grid}  {moon}')
pressed = 'Default##clock.formatDefault'
H.frames(1)
p('Default: the line a new character has', options.format == fields.Default)
pressed = nil
imgui.SmallButton = small
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
options.textScale[1] = 9
H.resettle()
p('a text scale out of range is brought in', H.options().textScale[1] == 3)

mark = #CLOCK.log
H.unload()
seen = Since(mark)
p('unloaded: the clock and the compass given back', Has(seen, 'clock.stop'), Has(seen, 'compass.stop'))

-- the set that comes with the addon: every day, every element, and the clear sky
local missing = {}
for _, name in ipairs({ 'days/firesday', 'days/earthsday', 'days/watersday', 'days/windsday', 'days/iceday',
    'days/lightningday', 'days/lightsday', 'days/darksday', 'weather/fire', 'weather/ice', 'weather/wind',
    'weather/earth', 'weather/thunder', 'weather/water', 'weather/light', 'weather/dark', 'weather/clear' }) do
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
p('the experience fields', Line(experience, c) == 'Lv75  EXP 12,345/30,000  TNL 17,655  4,200 EXP/hr')
p('none while not counted', Line(experience, fields.Context(time, nil, nil)) == '')
c.exp.limit = true
p('in limit mode: limit points to the next merit', Line(experience, c) == 'Lv75  LP 4,000/10,000  TNM 6,000  4,200 LP/hr')
c.exp.limit, c.exp.needed = false, 0
p('no level to go to: the experience alone, no TNL', Line(experience, c) == 'Lv75  EXP 12,345  4,200 EXP/hr')
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
p('in the line: written, after the clock\'s own fields', measured ~= nil and measured:find('Moon 42%  Lv75  EXP 12,345/30,000  TNL 17,655', 1, true) ~= nil, measured)
H.packetData(0x02D, Message(CLOCK.id, 500, 8))
p('and counted', select(2, exp.Since()) == before + 1)
p('/clock exp reset', H.command('/clock exp reset'), select(2, exp.Since()) == 0)
H.command('/clock')
local smalls2 = H.calls.SmallButton or 0
H.frames(1)
p('with experience in the line, Begin Again', (H.calls.SmallButton or 0) - smalls2 == #fields.All + 7)
H.command('/clock')

-- 0.6's settings: a list to tick and move, and experience a switch, brought over as a line
options.order, options.shown = T{ 'moon', 'time', 'level', 'expRate' }, T{ moon = true, time = true, level = true, expRate = true }
options.experience, options.expWindow = T{ true }, T{ 30 }
H.resettle()
options = H.options()
p('0.6 settings brought over', options.format == '{moon}  {time}  {level}  {rate}', options.order == nil and options.shown == nil,
    options.experience == nil and options.expWindow == nil)
