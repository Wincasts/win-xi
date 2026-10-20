-- The info panel's tooltips over its words: the zone's forecast as the Phoenix server rolls the weather,
-- and the calendar of the Vana'diel month; and the words' tooltips carried through the segments.
package.path = 'addons/libs/?.lua;' .. package.path
local forecast = require('winxi.infopanel.forecast')
local calendar = require('winxi.infopanel.calendar')
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
print('Info panel tooltips: the forecast, the calendar, the words\' tooltips and hovering them passed')
