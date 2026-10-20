-- The info panel's tooltips over its words: the zone's forecast as the Phoenix server rolls the weather,
-- the calendar of the Vana'diel month and the ships' and airships' timetable as the server runs them; and
-- the words' tooltips carried through the segments.
package.path = 'addons/libs/?.lua;' .. package.path
local forecast = require('winxi.infopanel.forecast')
local calendar = require('winxi.infopanel.calendar')
local schedule = require('winxi.infopanel.schedule')
local fields = require('winxi.infopanel.fields')
local panel = require('winxi.infopanel.panel')

local function p(what, ...)
    for i = 1, select('#', ...) do assert(select(i, ...), what .. ' (' .. i .. ')') end
    print(what, true)
end

-- the server's day of the cycle: Vana'diel days since the epoch, 3456 Earth seconds each, mod 2160
p('day of the cycle', forecast.Day(0) == 0, forecast.Day(3455) == 0, forecast.Day(3456) == 1,
    forecast.Day(2160 * 3456) == 0, forecast.Day(2161 * 3456 + 5) == 1, forecast.Day('x') == nil, forecast.Day(-1) == nil)

-- the generated tables: every pattern 2160 bytes, every byte a triple of weathers, the zones mapped
local tables = require('winxi.infopanel.zone_weather')
local patterns, zones = 0, 0
for _, pattern in ipairs(tables.patterns) do
    assert(#pattern == tables.cycle, 'a pattern of 2160 days')
    for i = 1, #pattern do
        local triple = tables.triples[pattern:byte(i) - 32]
        assert(triple and #triple == 3, 'a known triple on every day')
        for _, w in ipairs(triple) do assert(w >= 0 and w <= 19, 'a weather id') end
    end
    patterns = patterns + 1
end
for zone, index in pairs(tables.zones) do assert(tables.patterns[index] and not tables.fixed[zone], 'a rolling zone has one pattern'); zones = zones + 1 end
p('the generated tables are whole', patterns == #tables.patterns, zones > 100, tables.fixed[0] == 1, tables.cities[230] == true)
p('West Ronfaure rolls, San d\'Oria is a city, a zone the server has not is unknown',
    forecast.Odds(100, 0) ~= nil, forecast.City(230), not forecast.City(100), forecast.Odds(60000, 0) == nil)

-- the rolls, on tables of this check's own: day 0 rain, rain, squalls; day 2 a clear sky; day 3 three weathers;
-- a zone fixed to sunshine; a city
local a, b, c = string.char(33), string.char(34), string.char(35)
local pattern = (a .. a .. b .. c):rep(540) -- 2160 days
forecast.Use({ cycle = 2160,
    triples = { { 6, 6, 7 }, { 0, 1, 2 }, { 1, 6, 15 } },
    patterns = { pattern }, zones = { [5] = 1, [9] = 1 }, fixed = { [7] = 1, [8] = 0 }, cities = { [9] = true } })
local odds = forecast.Odds(5, 0)
p('rain, rain, squalls: 85% rain then 15% squalls', #odds == 2, odds[1].weather == 6 and odds[1].chance == 85, odds[2].weather == 7 and odds[2].chance == 15)
odds = forecast.Odds(5, 3)
p('three weathers: the normal 50, the common 35, the rare 15', #odds == 3, odds[1].weather == 1 and odds[1].chance == 50,
    odds[2].weather == 6 and odds[2].chance == 35, odds[3].weather == 15 and odds[3].chance == 15)
p('the cycle wraps', forecast.Odds(5, 2160)[1].weather == 6, forecast.Odds(5, 2162)[1].weather == 0)
p('a fixed zone', forecast.Odds(7, 0).fixed == 1, forecast.Odds(8, 400).fixed == 0)
local lines = forecast.Lines(5, 3456 * 2 + 100, 3, 30) -- day 2 of the cycle, a Windsday the 30th
p('five days from today, named', #lines == 7,
    lines[1] == 'Today, Windsday 30: 50% Clear skies, 35% Sunshine, 15% Clouds',
    lines[2] == 'Tomorrow, Iceday 1: 50% Sunshine, 35% Rain, 15% Thunderstorms',
    lines[3] == 'Lightningday 2: 85% Rain, 15% Squalls', lines[4] == 'Lightsday 3: 85% Rain, 15% Squalls',
    lines[5] == 'Darksday 4: 50% Clear skies, 35% Sunshine, 15% Clouds')
p('the fog rule outside a city, and the rolls', lines[6] == 'Fog from 2:00 to 7:00 whenever the roll is a clear sky.',
    lines[7] == 'The weather is rolled again every 3 to 30 Earth minutes.')
lines = forecast.Lines(9, 3456 * 2, 3, 30)
p('a city: no fog line', #lines == 6, lines[6]:find('rolled again', 1, true) ~= nil)
lines = forecast.Lines(5, 0, nil, nil, 2)
p('without the weekday: counted', #lines == 4, lines[1]:find('^Today: 85%% Rain') ~= nil, lines[2]:find('^Tomorrow: 85%% Rain') ~= nil)
p('a fixed zone, said once', #forecast.Lines(7, 0, 3, 30) == 1, forecast.Lines(7, 0, 3, 30)[1] == 'Always sunshine: the weather never changes here.',
    forecast.Lines(8, 0)[1] == 'Always clear skies: the weather never changes here.')
p('unknown: nothing', forecast.Lines(6, 0) == nil, forecast.Lines(5, nil) == nil)

-- the weather tooltip carries the forecast for the zone the player is in; the zone read once for the context
local core = AshitaCore
local lookups = 0
AshitaCore = {
    GetMemoryManager = function() return { GetParty = function() return { GetMemberZone = function() return 5 end } end } end,
    GetResourceManager = function() return { GetString = function(_, key, id) assert(key == 'zones.names' and id == 5); lookups = lookups + 1; return 'Testing Grounds' end } end,
}
local time = { get_game_day = function() return 30 end }
local context = { weatherId = 7, weekday = 3, raw = 3456 * 2 + 100, time = time }
local text = fields.IconTooltip('weather', context)
p('the weather, its element and strength, then the forecast', text:find('^Weather: Squalls\nElement: Water\nStrength: Double\n\nForecast for Testing Grounds:\nToday, Windsday 30: 50%% Clear skies') ~= nil,
    text:find('rolled again every 3 to 30 Earth minutes.$') ~= nil)
p('a clear sky too', fields.IconTooltip('weather', { weatherId = 0, raw = 0, time = time }):find('No elemental weather\n\nForecast for Testing Grounds:\nToday: 85%% Rain', 1) ~= nil)
p('the same text again for the context, the zone read once', fields.Tooltip('weather', context) == fields.Tooltip('weather', context), lookups == 2)
p('no timestamp: no forecast', fields.IconTooltip('weather', { weatherId = 6 }) == 'Weather: Rain\nElement: Water\nStrength: Single')
AshitaCore = nil
p('no game: the weather alone', fields.IconTooltip('weather', { weatherId = 6, raw = 0 }) == 'Weather: Rain\nElement: Water\nStrength: Single')
AshitaCore = core
forecast.Use(nil)

-- the calendar: Vana'diel's months of 30 days over its weeks of 8, from the game's own functions of the
-- timestamp, as Ashita's ffxi.time gives them (3456 Earth seconds to a day, 103680 to a month, 1244160 to a year)
local function Game(raw)
    local day = math.floor(raw / 3456)
    return { weekday = day % 8, dom = day % 30 + 1, month = math.floor(raw / 103680) % 12 + 1, year = math.floor(raw / 1244160) + 886,
        hours = math.floor(raw % 3456 / 144), minutes = math.floor(raw % 144 / 2.4) }
end
local moons = {}
time = {
    get_game_weekday = function(raw) return Game(raw).weekday end, get_game_day = function(raw) return Game(raw).dom end,
    get_game_month = function(raw) return Game(raw).month end, get_game_year = function(raw) return Game(raw).year end,
    get_game_hours = function(raw) return Game(raw).hours end, get_game_minutes = function(raw) return Game(raw).minutes end,
    get_game_moon_percent = function(raw) return moons[raw] or 42 end,
}
local raw = 14 * 1244160 + 11 * 103680 + 29 * 3456 + 3 * 144 + 32 * 2.4 -- 900/12/30 3:32
local game = Game(raw)
p('the stand-in is the game\'s calendar', game.year == 900, game.month == 12, game.dom == 30, game.hours == 3, game.minutes == 32)
moons[raw], moons[raw + 3456] = 42, 45
local built = calendar.Build({ time = time, raw = raw, weekday = game.weekday })
p('the title', built.title == ('%s, 900/12/30  3:32'):format(calendar.Days[game.weekday + 1]), built.day == 30, built.month == 12)
p('the first of the month on its weekday, the 30th on today\'s', built.first == (game.weekday - 29) % 8, built.rows[1][built.first + 1] == 1)
local seen, cells = {}, 0
for r, row in ipairs(built.rows) do
    assert(#row == 8, 'eight cells to a week')
    for col, cell in ipairs(row) do
        if cell then seen[#seen + 1] = cell; cells = cells + 1; assert((col - 1) == (built.first + cell - 1) % 8, 'each day under its weekday') end
    end
end
p('the thirty days once each, in order, in the weeks', cells == 30, seen[1] == 1, seen[30] == 30, #built.rows == math.ceil((built.first + 30) / 8))
p('the moon, waxing when fuller tomorrow', built.moon == 'First Quarter, 42%')
moons[raw + 3456] = 40
p('waning when less', calendar.Build({ time = time, raw = raw }).moon == 'Last Quarter, 42%')
p('the next day in Earth minutes', built.next == ('%s in %d Earth minutes'):format(calendar.Days[(game.weekday + 1) % 8 + 1], math.ceil((3456 - raw % 3456) / 60)))
p('under a minute', calendar.Build({ time = time, raw = 3456 - 30 }).next:find('in under an Earth minute$') ~= nil)
p('the phases by fullness', calendar.Phase(0, true) == 'New Moon', calendar.Phase(9, false) == 'New Moon', calendar.Phase(10, true) == 'Waxing Crescent',
    calendar.Phase(39, false) == 'Waning Crescent', calendar.Phase(40, true) == 'First Quarter', calendar.Phase(59, false) == 'Last Quarter',
    calendar.Phase(60, true) == 'Waxing Gibbous', calendar.Phase(89, false) == 'Waning Gibbous', calendar.Phase(90, true) == 'Full Moon', calendar.Phase(100, false) == 'Full Moon')
p('without a time or a timestamp: nothing', calendar.Build({}) == nil, calendar.Build({ time = time }) == nil, calendar.Build({ time = {}, raw = 1 }) == nil)
p('the first of a month that begins the week', calendar.Build({ time = time, raw = 0 }).first == 0, calendar.Build({ time = time, raw = 30 * 3456 }).first == 6)

-- drawing: the title, the eight days (pictures where the set has them), each day under its weekday, today marked,
-- the days gone dimmed, the moon and the next day
local texts, images, rects, pushes, pops, cursor = {}, {}, {}, 0, 0, 0
local imgui = {
    Text = function(s) texts[#texts + 1] = { s, cursor } end, GetFontSize = function() return 14 end,
    CalcTextSize = function(s) return #s * 7 end, GetCursorPosX = function() return 10 end,
    SetCursorPosX = function(x) cursor = x end, SameLine = function() end, NewLine = function() end,
    Image = function(handle, size) images[#images + 1] = { handle, size[1], cursor } end,
    GetCursorScreenPos = function() return cursor + 100, 50 end,
    GetWindowDrawList = function() return { AddRectFilled = function(_, a, b, color, rounding) rects[#rects + 1] = { a[1], a[2], b[1], b[2], color, rounding } end } end,
    GetColorU32 = function() return 777 end,
    PushStyleColor = function() pushes = pushes + 1 end, PopStyleColor = function() pops = pops + 1 end,
}
ImGuiCol_Text = 0
calendar.Draw(imgui, built, { icon = function(weekday) return weekday < 4 and 500 + weekday or nil end, dim = { 1, 1, 1, 0.5 }, highlight = { 1, 1, 1, 1 } })
local cell = 14 + 8
p('the title first, the moon and the next day last', texts[1][1] == built.title, texts[#texts - 1][1] == built.moon, texts[#texts][1] == built.next)
p('four pictures then four names across the top, a cell apart', #images == 4, images[1][1] == 500 and images[1][3] == 10, images[4][3] == 10 + 3 * cell,
    texts[2][1] == 'Ice' and texts[2][2] == 10 + 4 * cell, texts[5][1] == 'Dark' and texts[5][2] == 10 + 7 * cell)
local placed = 0
for _, t in ipairs(texts) do
    local day = tonumber(t[1])
    if day then placed = placed + 1; assert(t[2] == 10 + ((built.first + day - 1) % 8) * cell, 'day ' .. day .. ' under its weekday') end
end
p('thirty days placed', placed == 30)
p('today marked once, rounded, in the highlight', #rects == 1, rects[1][1] == 100 + 10 + ((built.first + 29) % 8) * cell - 3, rects[1][5] == 777, rects[1][6] == 3)
p('the 29 days gone dimmed, each push popped', pushes == 29, pops == 29)
texts, images, rects, pushes = {}, {}, {}, 0
calendar.Draw(imgui, built, {})
p('without a style: names, no mark, nothing dimmed', #images == 0, texts[2][1] == 'Fire', #rects == 0, pushes == 0)

-- the words' tooltips through the segments: a word with one stands alone, the words round it their own
local ctx = { time = time, raw = raw, weekday = game.weekday, weather = 'Rain', weatherId = 6, grid = '(H-9)' }
local segments = fields.Segments(ctx, '{time} - {grid} - {date}')
p('time and date segments of their own, the divider and grid between them one', #segments == 3, segments[1] == '3:32', segments[2] == ' - (H-9) - ',
    segments[3] == '900/12/30', segments.tooltips[1] and segments.tooltips[1].calendar ~= nil, segments.tooltips[2] == nil, segments.tooltips[3] == segments.tooltips[1])
segments = fields.Segments(ctx, '{weather} {moon}')
p('the weather\'s words carry its text, the moon\'s the calendar', type(segments.tooltips[1]) == 'string' and segments.tooltips[1]:find('^Weather: Rain') ~= nil,
    segments[2] == ' ', segments.tooltips[3].calendar == segments.tooltips[1] == false and segments.tooltips[3].calendar ~= nil)
p('the line is the words alone, as before', fields.Line(ctx, '{time} - {grid} - {date}') == '3:32 - (H-9) - 900/12/30')
local pp = panel.Defaults()
pp.slots[1].format = '{time} | {grid}'; pp.slots[2].format = '{weather}'; pp.slots[3].format = '{date} | {moon}'
pp.dayPlace[1], pp.weatherPlace[1] = 1, 1
local slots = panel.Build(pp, fields, ctx)
p('the panel keeps the words\' tooltips beside the styled dividers', slots[1][1] == '3:32' and slots[1].tooltips[1].calendar ~= nil,
    slots[1][2] == ' ' and slots[1][3].separator and slots[1][4] == ' (H-9)' and slots[1].tooltips[4] == nil,
    slots[2][1] == 'Rain' and slots[2].tooltips[1]:find('^Weather') ~= nil,
    slots[3][1] == '900/12/30' and slots[3][3].separator and slots[3][5] == 'Moon 42%' and slots[3].tooltips[5].calendar ~= nil and slots[3].tooltips[4] == nil)

ctx.dayIcon, ctx.weatherIcon = 101, 102
pp.dayPlace[1], pp.dayAfter[1], pp.weatherPlace[1], pp.weatherAfter[1] = 3, false, 5, false
slots = panel.Build(pp, fields, ctx)
p('icons put before the words move their tooltips along with them', slots[1][1].icon == 101 and slots[1][2] == '  ' and slots[1][3] == '3:32',
    slots[1].tooltips[1] == nil and slots[1].tooltips[3].calendar ~= nil,
    slots[3][1].icon == 102 and slots[3][3] == '900/12/30' and slots[3].tooltips[3].calendar ~= nil and slots[3][7] == 'Moon 42%' and slots[3].tooltips[7].calendar ~= nil)
pp.dayAfter[1], pp.weatherAfter[1] = true, true
slots = panel.Build(pp, fields, ctx)
p('and after them, where they stay', slots[1][1] == '3:32' and slots[1].tooltips[1].calendar ~= nil and slots[1][#slots[1]].icon == 101,
    slots[3][5] == 'Moon 42%' and slots[3].tooltips[5].calendar ~= nil and slots[3][7].icon == 102)
ctx.dayIcon, ctx.weatherIcon = nil, nil
pp.dayPlace[1], pp.weatherPlace[1] = 1, 1

-- hovering a word: the mouse over its drawn width, within the slot, gives its tooltip; off it, nothing
local mouse, tips = { x = -1, y = -1 }, {}
local list = { AddText = function() end, AddImage = function() end, AddLine = function() end, AddTriangleFilled = function() end, PushClipRect = function() end, PopClipRect = function() end }
package.loaded.imgui = { GetIO = function() return { MousePos = mouse } end, GetWindowDrawList = function() return list end,
    GetFontSize = function() return 14 end, GetColorU32 = function() return 1 end, CalcTextSize = function(s) return #s * 7 end, Dummy = function() end }
package.loaded['winxi.theme'] = { GameBorderColor = function() return { 1, 1, 1, 1 } end }
package.loaded['winxi.text'] = { Draw = function() end }
local drawn = { { '3:32', { separator = true }, '(H-9)', tooltips = { [1] = { calendar = built } } }, {}, {} }
local options = { textColor = { 1, 1, 1, 1 }, iconScale = { 1 }, weatherScale = { 1 }, iconOffset = { 0 }, reserve = false, tooltip = function(t) tips[#tips + 1] = t end }
pp = panel.Defaults(); pp.slots[1].align[1] = 1
-- slot 1 from 13 to 113 (padding 3, then 4 in): the words start at 17, '3:32' 28 wide, the line 14 tall from y 25
panel.Draw(pp, drawn, { left = 10, top = 20, width = 306, height = 24 }, options)
mouse.x, mouse.y = 30, 30; panel.Draw(pp, drawn, { left = 10, top = 20, width = 306, height = 24 }, options)
p('over the time: its calendar', #tips == 1 and tips[1].calendar == built)
mouse.x, mouse.y = 60, 30; panel.Draw(pp, drawn, { left = 10, top = 20, width = 306, height = 24 }, options)
p('over the grid, which has none: nothing', #tips == 1)
mouse.x, mouse.y = 30, 20; panel.Draw(pp, drawn, { left = 10, top = 20, width = 306, height = 24 }, options)
p('above the panel: nothing', #tips == 1)
options.tooltip = nil; mouse.x, mouse.y = 30, 30; panel.Draw(pp, drawn, { left = 10, top = 20, width = 306, height = 24 }, options)
p('without a tooltip function (the legacy clock): nothing asked', #tips == 1)

-- the timetable: the generated runs whole, then the server's cycle on runs of this check's own
local transports = require('winxi.infopanel.transports')
local runs, zonesWithRuns, groupKeys = 0, {}, {}
for _, g in ipairs(transports.groups) do groupKeys[g.key] = true end
for _, run in ipairs(transports.runs) do
    assert(groupKeys[run.group], 'a known group: ' .. tostring(run.group))
    assert(type(run.from) == 'string' and type(run.to) == 'string' and run.zone > 0, 'labels and a zone')
    assert(run.every > 0 and run.boards < run.leaves and run.leaves <= run.departs and run.departs <= run.every, 'the door opens, shuts, then it departs, within the cycle')
    assert(run.disembark >= 0 and run.disembark < run.every and #run.crossings > 0, 'put ashore within the cycle, a crossing named')
    runs = runs + 1; zonesWithRuns[run.zone] = true
end
local bastok
for _, run in ipairs(transports.runs) do if run.name == 'bastok_jeuno_airship' then bastok = run end end
p('the generated runs are whole', runs >= 20, zonesWithRuns[236] and zonesWithRuns[246] and zonesWithRuns[248] and zonesWithRuns[249],
    bastok and bastok.every == 864 and bastok.crossings[1] == 224)
-- the Selbina ferry leaves on the hours the server's own timetable (scripts/globals/transport.lua) says:
-- 8:00, 16:00 and 24:00 Vana'diel
local selbina
for _, run in ipairs(transports.runs) do if run.name == 'selbina_mhaura_boat' then selbina = run end end
local leaving = selbina.offset + selbina.leaves
p('the ferry leaves Selbina at 8:00, 16:00 and 0:00', schedule.Clock(leaving) == '8:00', schedule.Clock(leaving + 1152) == '16:00', schedule.Clock(leaving + 2304) == '0:00')

-- runs of this check's own: a cycle of 100 from offset 10, the door open from 20 to 50, ashore at 70 (a
-- crossing of 20); a second run with the same ends, offset 60, so the row is the nearer; a ferry whose
-- riders go ashore after the cycle wraps
schedule.Use({
    groups = { { key = 'air', label = 'Airships' }, { key = 'sea', label = 'Ferries' }, { key = 'none', label = 'Nothing' } },
    runs = {
        { name = 'a', group = 'air', from = 'Here', to = 'There', zone = 5, every = 100, offset = 10, boards = 20, leaves = 50, departs = 52, disembark = 70, crossings = { 9 } },
        { name = 'b', group = 'air', from = 'There', to = 'Here', zone = 6, every = 100, offset = 60, boards = 20, leaves = 50, departs = 52, disembark = 70, crossings = { 9 } },
        { name = 'c', group = 'air', from = 'There', to = 'Here', zone = 6, every = 100, offset = 10, boards = 20, leaves = 50, departs = 52, disembark = 70, crossings = { 9 } },
        { name = 'd', group = 'sea', from = 'Port', to = 'Isle', zone = 7, every = 1152, offset = 920, boards = 41, leaves = 233, departs = 234, disembark = 25, crossings = { 11, 12 } },
        { name = 'e', group = 'other', from = 'X', to = 'Y', zone = 8, every = 100, offset = 0, boards = 20, leaves = 50, departs = 52, disembark = 70, crossings = { 13 } },
    },
})
local run = { every = 100, offset = 10, boards = 20, leaves = 50, departs = 52, disembark = 70 }
p('seconds into the cycle from the offset, wrapping', schedule.Into(run, 10) == 0, schedule.Into(run, 109) == 99, schedule.Into(run, 110) == 0, schedule.Into(run, 5) == 95)
local status = schedule.Status(run, 40) -- 30 in: the door open
p('the door open: boarding, leaves in 20, the crossing 20', status.boarding, status.boardsIn == 0, status.leavesIn == 20, status.trip == 20, not status.carrying)
status = schedule.Status(run, 15) -- 5 in: before the door opens
p('before the door: opens in 15, leaves in 45', not status.boarding, status.boardsIn == 15, status.leavesIn == 45)
status = schedule.Status(run, 70) -- 60 in: under way
p('under way: carrying, ashore in 10, the next door in 60', status.carrying, status.ashoreIn == 10, status.boardsIn == 60, status.leavesIn == 90)
status = schedule.Status(run, 95) -- 85 in: ashore, waiting for the next
p('ashore: nothing carried', not status.carrying, not status.boarding, status.boardsIn == 35)
local ferry = { every = 1152, offset = 920, boards = 41, leaves = 233, departs = 234, disembark = 25 }
status = schedule.Status(ferry, 920 + 233) -- the door just shut
p('a crossing past the end of the cycle: carrying, 944 to go', status.carrying, status.ashoreIn == 944, status.trip == 944)
status = schedule.Status(ferry, 920 + 10)
p('and carrying still at 10 into the next cycle, ashore in 15', status.carrying, status.ashoreIn == 15, not status.boarding)
p('the Vana\'diel clock of a timestamp', schedule.Clock(0) == '0:00', schedule.Clock(144 * 8) == '8:00', schedule.Clock(144 * 23 + 143) == '23:59', schedule.Clock(3456 * 5 + 144 + 24) == '1:10')
p('spans in minutes and seconds, hours past one', schedule.Span(0) == '0:00', schedule.Span(59) == '0:59', schedule.Span(265) == '4:25', schedule.Span(3600) == '1:00:00', schedule.Span(3725.7) == '1:02:05', schedule.Span(-3) == '0:00')

local built = schedule.Build(5, 40)
p('the title, the columns and the groups in order; a group with no runs is empty, an unknown group dropped', built.title == 'Ships and airships', #built.columns == 6, built.columns[1] == 'From' and built.columns[5] == 'At',
    #built.groups == 3, built.groups[1].label == 'Airships' and #built.groups[1].rows == 2, built.groups[2].label == 'Ferries' and #built.groups[2].rows == 1, #built.groups[3].rows == 0)
local row = built.groups[1].rows[1]
p('the zone\'s own run: boarding now, leaves in 0:20 at the Vana\'diel time of 60, a crossing of 0:20, marked', row.here, built.here,
    row.cells[1] == 'Here' and row.cells[2] == 'There', row.cells[3] == 'now', row.cells[4] == '0:20', row.cells[5] == schedule.Clock(60), row.cells[6] == '0:20')
row = built.groups[1].rows[2]
-- at 40: run c (offset 10) is 30 in, leaves in 20; run b (offset 60) is 80 in, leaves in 70: the row is c's
p('two runs with the same ends: one row, the nearer leaving, not the zone\'s', not row.here, row.cells[1] == 'There' and row.cells[2] == 'Here', row.cells[3] == 'now', row.cells[4] == '0:20')
built = schedule.Build(5, 95) -- run c is 85 in (leaves in 65), run b 35 in (leaves in 15): b's turn
p('and the other when it is nearer', built.groups[1].rows[2].cells[3] == 'now', built.groups[1].rows[2].cells[4] == '0:15',
    built.groups[1].rows[1].cells[3] == '0:35' and built.groups[1].rows[1].cells[4] == '1:05')
p('no aboard lines ashore', built.aboard == nil)
built = schedule.Build(9, 70) -- the crossing of a and c, both 60 in: both carrying
p('aboard: a line for each run carrying through the zone', built.aboard and #built.aboard == 2, built.aboard[1] == 'Bound for There: ashore in 0:10', built.aboard[2] == 'Bound for Here: ashore in 0:10', not built.here)
built = schedule.Build(12, 920 + 10) -- the ferry's second crossing zone, 10 into the next cycle
p('the ferry\'s riders ashore in 15 in either of its crossings', built.aboard and #built.aboard == 1 and built.aboard[1] == 'Bound for Isle: ashore in 0:15', schedule.Build(11, 930).aboard[1] == built.aboard[1])
built = schedule.Build(9, 95) -- in the crossing with nothing carried
p('in a crossing with nothing carried: arriving', built.aboard and #built.aboard == 1 and built.aboard[1]:find('^Arriving') ~= nil)
built = schedule.Build(100, 40)
p('a zone of no runs: the whole timetable, nothing marked, no aboard lines', built and not built.here and built.aboard == nil and #built.groups[1].rows == 2)
p('without a zone: the timetable still', schedule.Build(nil, 40) ~= nil and not schedule.Build(nil, 40).here)
p('without a timestamp: nothing', schedule.Build(5, nil) == nil, schedule.Build(5, 'x') == nil, schedule.Build(5, 0 / 0) == nil)

-- drawing: the title, the aboard lines, the headings dimmed, each group's label and its rows in columns as
-- wide as their widest words, the zone's rows marked, the note dimmed
texts, rects, pushes, pops, cursor = {}, {}, 0, 0, 0
built = schedule.Build(9, 70) -- aboard, with run a's zone 5 not here
schedule.Draw(imgui, built, { dim = { 1, 1, 1, 0.5 }, highlight = { 1, 1, 1, 1 } })
p('the title then the two aboard lines', texts[1][1] == 'Ships and airships', texts[2][1] == built.aboard[1], texts[3][1] == built.aboard[2])
p('the headings next, the note last, both dimmed (a push and a pop each)', texts[4][1] == 'From', texts[9][1] == 'Trip', texts[#texts][1] == built.note, pushes == 2, pops == 2)
p('the group labels and rows, the empty group left out', texts[10][1] == 'Airships', texts[11][1] == 'Here', texts[17][1] == 'There', texts[23][1] == 'Ferries', texts[24][1] == 'Port', texts[#texts - 1][1] == '15:44')
-- the first column holds 'From', 'Here', 'There', 'Port': 'There' the widest at 35; the gap 14 (two spaces at 7)
local gap = 14
p('columns as wide as their widest words', texts[4][2] == 10, texts[5][2] == 10 + 35 + gap, texts[12][2] == 10 + 35 + gap)
p('nothing marked away from the zone', #rects == 0)
texts, rects, pushes, pops = {}, {}, 0, 0
schedule.Draw(imgui, schedule.Build(5, 40), { dim = { 1, 1, 1, 0.5 }, highlight = { 1, 1, 1, 1 } })
p('the zone\'s row marked once, the width of the table, rounded', #rects == 1, rects[1][5] == 777 and rects[1][6] == 3, rects[1][1] == 100 + 10 - 3)
texts, rects, pushes = {}, {}, 0
schedule.Draw(imgui, schedule.Build(5, 40), {})
p('without a style: nothing dimmed or marked', pushes == 0, #rects == 0, texts[1][1] == 'Ships and airships')
schedule.Use(nil)

-- the zone's words carry the timetable, built once for the context
AshitaCore = {
    GetMemoryManager = function() return { GetParty = function() return { GetMemberZone = function() return 236 end } end } end,
    GetResourceManager = function() return { GetString = function() return 'Port Bastok' end } end,
}
ctx = { time = time, raw = raw, weekday = game.weekday }
segments = fields.Segments(ctx, '{zone} {time}')
p('the zone\'s words stand alone with the timetable, Port Bastok\'s airship marked', segments[1] == 'Port Bastok', segments.tooltips[1] and segments.tooltips[1].schedule ~= nil,
    segments.tooltips[1].schedule.here == true, segments.tooltips[1].schedule.groups[1].rows[3].here and segments.tooltips[1].schedule.groups[1].rows[3].cells[1] == 'Bastok',
    segments.tooltips[3].calendar ~= nil)
p('the same timetable again for the context', fields.Tooltip('schedule', ctx) == segments.tooltips[1])
p('without a timestamp: no tooltip, the words still', fields.Segments({ time = time }, '{zone}')[1] == 'Port Bastok', fields.Tooltip('schedule', { time = time }) == nil)
AshitaCore = core
print('Info panel tooltips: the forecast, the calendar, the timetable, the words\' tooltips and hovering them passed')
