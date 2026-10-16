-- The clock addon (through tests/clock_stand_in.lua): one line where the game writes its clock, no
-- background, its text scale, the compass hidden, the settings, and letting go of the game's clock.
local imgui = require('imgui')
local display = require('display')
local p = H.print

-- the line
local raws = CLOCK.raws
local time = package.loaded['ffxi.time']
p('one line: time, grid, day, date, moon', display.Line(time, '(H-9)') == '3:32  (H-9)  Windsday  900/12/30  Moon 42%')
p('every field from one timestamp', CLOCK.raws == raws + 1)
p('no grid: left out', display.Line(time, nil) == '3:32  Windsday  900/12/30  Moon 42%', display.Line(time, '') == display.Line(time, nil))

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
p('/clock off', H.command('/clock off'), options.enabled[1] == false)
windows['clock.native'], mark = nil, #CLOCK.log
H.frames(1)
seen = Since(mark)
p('off: the game\'s clock given back, nothing drawn', Has(seen, 'clock.stop'), windows['clock.native'] == nil, Has(seen, 'compass.begin'))
p('/clock on', H.command('/clock on'), options.enabled[1] == true)
local before = #H.printed
p('/clock status says the clock and the compass', H.command('/clock status'), #H.printed == before + 2,
    tostring(H.printed[before + 1]):find('Drawn in place', 1, true) ~= nil, tostring(H.printed[before + 2]):find('Compass', 1, true) ~= nil)
p('/clock opens the settings', H.command('/clock'))
local sliders = H.calls.SliderFloat or 0
H.frames(1)
p('the settings: Text Scale among them', (H.calls.SliderFloat or 0) > sliders)

-- a capability uihook does not have: nothing of its own drawn
CLOCK.ready[1] = false
windows['clock.native'] = nil
H.frames(1)
p('uihook without the clock: no window of its own', windows['clock.native'] == nil)
CLOCK.ready[1] = true

-- 0.1's settings: enabled as true or false, and a place of its own
options.enabled, options.x, options.y = false, 20, -1
H.resettle()
options = H.options()
p('0.1 settings brought over', type(options.enabled) == 'table' and options.enabled[1] == false, options.x == nil and options.y == nil)
options.textScale[1] = 9
H.resettle()
p('a text scale out of range is brought in', H.options().textScale[1] == 3)

mark = #CLOCK.log
H.unload()
seen = Since(mark)
p('unloaded: the clock and the compass given back', Has(seen, 'clock.stop'), Has(seen, 'compass.stop'))
