-- The clock addon (through tests/clock_stand_in.lua): one line where the game writes its clock, no
-- background, its text scale, the compass hidden, the settings, and letting go of the game's clock.
local imgui = require('imgui')
local fields = require('fields')
local p = H.print

-- the line
local raws = CLOCK.raws
local time = package.loaded['ffxi.time']
local order, shown = fields.Defaults()
local context = fields.Context(time, '(H-9)', 'Rain')
p('one line: time, grid, day, date, moon; weather off to begin with',
    fields.Line(context, order, shown) == '3:32  (H-9)  Windsday  900/12/30  Moon 42%')
p('every field from one timestamp', CLOCK.raws == raws + 1)
p('no grid: left out', fields.Line(fields.Context(time, nil), order, shown) == '3:32  Windsday  900/12/30  Moon 42%',
    fields.Line(fields.Context(time, ''), order, shown) == fields.Line(fields.Context(time, nil), order, shown))
shown.weather, shown.date = true, false
p('weather on, date off', fields.Line(context, order, shown) == '3:32  (H-9)  Windsday  Moon 42%  Rain')
p('moved: day up past the grid, and the time to the end', fields.Move(order, 3, -1), fields.Move(order, 1, 1),
    fields.Move(order, 2, 1), fields.Move(order, 3, 1), fields.Move(order, 4, 1), fields.Move(order, 5, 1),
    fields.Line(context, order, shown) == 'Windsday  (H-9)  Moon 42%  Rain  3:32')
p('not past either end', not fields.Move(order, 1, -1), not fields.Move(order, #order, 1))
-- settings from before a field was there, with one since gone and one twice over
local old, oldShown = T{ 'moon', 'gone', 'time', 'moon' }, T{ moon = false, gone = true }
fields.Normalize(old, oldShown)
p('made whole: kept in their order, the rest after, as they begin',
    table.concat(old, ',') == 'moon,time,grid,day,date,weather', oldShown.gone == nil,
    oldShown.moon == false, oldShown.time == true, oldShown.weather == false)
shown = select(2, fields.Defaults())
for key in pairs(shown) do shown[key] = false end
p('nothing ticked: an empty line', fields.Line(context, order, shown) == '')

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
local smalls, boxes = H.calls.SmallButton or 0, H.calls.Checkbox or 0
H.frames(1)
p('the Line section: a field to a row, ticked, with Up and Down', (H.calls.SmallButton or 0) - smalls == 2 * #fields.All,
    (H.calls.Checkbox or 0) - boxes >= #fields.All)
-- a field moved and switched off: the line follows by its next reading, a quarter of a second
fields.Move(options.order, 1, 1)
options.shown.moon = false
H.frames(9)
p('the line follows the settings', measured == '(H-9)  3:32  Windsday  900/12/30')
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
