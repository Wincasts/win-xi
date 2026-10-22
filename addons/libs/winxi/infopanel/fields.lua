-- What the clock's line can show: a string the settings build, each field a {token} in it and
-- anything else written as it is, between them: the dividers.
--
--   fields.All                          every field, in the order the settings offer them
--   fields.ByToken[token]               one of them, by the word between its braces
--   fields.Default                      the line a new character has
--   fields.Parse(format)                the line in pieces: { literal = words } and { field = field }
--   fields.Uses(format, module)         whether any of a module's fields is in it ('exp')
--   fields.Has(format, token)           whether a field is in it
--   fields.Context(time, grid, weather) what the fields are written from, read once; the clock adds
--                                       weatherIcon (a set's picture) and exp (exp.Snapshot) to it
--   fields.Segments(context, format)    the line to draw: words (strings) and icons ({ icon = handle,
--                                       tooltip = text }); a word with a tooltip of its own is a segment
--                                       of its own, its tooltip in segments.tooltips[i]
--   fields.Line(context, format)        its words alone
--   fields.Tooltip(hover, context)      a field's tooltip: 'weather' the text of IconTooltip('weather'),
--                                       'calendar' { calendar = calendar.Build(context) }, 'schedule'
--                                       { schedule = schedule.Build(zone, raw, context.timetable) } (the
--                                       ships' and airships' timetable, winxi.infopanel.schedule, of the
--                                       lines the host puts in context.timetable), made once for each context
--   fields.IconTooltip(kind, context)   the text over the day's icon, or the weather's with the zone's
--                                       forecast (winxi.infopanel.forecast) after it
--   fields.FromList(order, shown, modules)  0.6's ordered, ticked list as a line
--
-- A field is { token, label, tip, Text(context) } or, for a picture, Icon(context) in place of Text;
-- module = 'exp' for experience, counted only while one is in the line; hover = 'calendar', 'weather'
-- or 'schedule' for a field with a tooltip. Text gives its words (Icon its handle), or nil when there are
-- none (no grid where the zone has no map). A field with none takes the divider before it away with
-- it, so that '{time} | {grid} | {day}' is '3:32 | Windsday' where there is no grid; the first in the
-- line takes the one after it instead.
local exp = require('winxi.infopanel.exp')
local forecast = require('winxi.infopanel.forecast')
local calendar = require('winxi.infopanel.calendar')
local schedule = require('winxi.infopanel.schedule')
local days = { 'Firesday', 'Earthsday', 'Watersday', 'Windsday', 'Iceday', 'Lightningday', 'Lightsday', 'Darksday' }

local fields = {}

fields.Default = '{time}  {grid}  {day}  {date}  {moon}'

local dayElements = { 'Fire', 'Earth', 'Water', 'Wind', 'Ice', 'Lightning', 'Light', 'Dark' }
local weatherElements = { 'Fire', 'Water', 'Earth', 'Wind', 'Ice', 'Lightning', 'Light', 'Dark' }
local weatherNames = forecast.Names

-- The zone the player is in, read once for each context: its id in c.zoneId and its name in c.zoneName
-- (nil while the zone is unavailable)
local function Zone(c)
    if c.zoneRead then return c.zoneId, c.zoneName end
    c.zoneRead = true
    local ok, id = pcall(function() return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0) end)
    id = ok and tonumber(id) or nil
    if not id or id ~= id or id <= 0 or id > 65535 or id % 1 ~= 0 then return nil end
    local found, name = pcall(function() return AshitaCore:GetResourceManager():GetString('zones.names', id) end)
    c.zoneId = id
    c.zoneName = found and type(name) == 'string' and name ~= '' and name or ('Zone %d'):format(id)
    return c.zoneId, c.zoneName
end

local function Forecast(context)
    local zone, name = Zone(context)
    if not zone or not tonumber(context.raw) then return '' end
    local ok, lines = pcall(function()
        local time = context.time
        local day = type(time) == 'table' and type(time.get_game_day) == 'function' and tonumber(time.get_game_day(context.raw)) or nil
        return forecast.Lines(zone, context.raw, context.weekday, day, 3)
    end)
    if not ok or not lines then return '' end
    return ('\n\nForecast for %s:\n%s'):format(name, table.concat(lines, '\n'))
end

function fields.IconTooltip(kind, context)
    if kind == 'day' then
        local weekday = tonumber(context.weekday)
        if weekday == nil and context.time then weekday = tonumber(context.time.get_game_weekday(context.raw)) end
        local index = (weekday or -1) + 1
        return ('Vana\'diel day: %s\nElement: %s'):format(days[index] or 'Unknown', dayElements[index] or 'Unknown')
    end
    local id = tonumber(context.weatherId)
    if not id or id < 0 or id > 19 or id % 1 ~= 0 then return 'Weather: Unknown' end
    local name = context.weather or weatherNames[id]
    if id < 4 then return ('Weather: %s\nNo elemental weather'):format(name) .. Forecast(context) end
    return ('Weather: %s\nElement: %s\nStrength: %s'):format(name,
        weatherElements[math.floor((id - 4) / 2) + 1], id % 2 == 0 and 'Single' or 'Double') .. Forecast(context)
end

function fields.Tooltip(hover, context)
    if hover == 'weather' then
        context.weatherTooltip = context.weatherTooltip or fields.IconTooltip('weather', context)
        return context.weatherTooltip
    end
    if hover == 'calendar' then
        if context.calendarTooltip == nil then
            local built = calendar.Build(context)
            context.calendarTooltip = built and { calendar = built } or false
        end
        return context.calendarTooltip or nil
    end
    if hover == 'schedule' then
        if context.scheduleTooltip == nil then
            local zone, name = Zone(context)
            local ok, built = pcall(schedule.Build, zone, context.raw, context.timetable)
            local area = require('winxi.infopanel.subzone').Read(zone)
            context.scheduleTooltip = ok and built and { schedule = built,
                location = name and ('Zone: ' .. name .. (area and ('\nSub-zone: ' .. area) or '')) } or false
        end
        return context.scheduleTooltip or nil
    end
    return nil
end

fields.All = {
    { token = 'time', label = 'Time', hover = 'calendar',
        tip = 'Vana\'diel time, as the game writes it: 3:32.\nResting the mouse on it shows the month\'s calendar.',
        Text = function(c) return ('%d:%02d'):format(c.time.get_game_hours(c.raw), c.time.get_game_minutes(c.raw)) end },
    { token = 'grid', label = 'Map Grid',
        tip = 'Where you are on the zone\'s map, as the game writes it: (H-9).\nThere is none where the zone has no map.',
        Text = function(c) return c.grid ~= nil and #c.grid > 0 and c.grid or nil end },
    { token = 'zone', label = 'Zone Name', hover = 'schedule',
        tip = 'The current zone name, such as West Ronfaure. None while the zone is unavailable.\nResting the mouse on it shows the zone and current named sub-zone, then the next ships and airships to leave (the Timetable tab), the zone\'s own marked.',
        Text = function(c) local _, name = Zone(c); return name end },
    { token = 'day', label = 'Day', hover = 'calendar',
        tip = 'The day of the week: Windsday.\nThe game\'s icon for the day stays to the left of the line.\nResting the mouse on it shows the month\'s calendar.',
        Text = function(c) return days[tonumber(c.time.get_game_weekday(c.raw)) + 1] or 'Unknown day' end },
    { token = 'date', label = 'Date', hover = 'calendar',
        tip = 'Vana\'diel\'s year, month and day: 900/12/30.\nResting the mouse on it shows the month\'s calendar.',
        Text = function(c)
            return ('%d/%02d/%02d'):format(c.time.get_game_year(c.raw), c.time.get_game_month(c.raw), c.time.get_game_day(c.raw))
        end },
    { token = 'moon', label = 'Moon', hover = 'calendar',
        tip = 'How full the moon is: Moon 42%.\nResting the mouse on it shows the moon\'s phase and the month\'s calendar.',
        Text = function(c) return ('Moon %d%%'):format(c.time.get_game_moon_percent(c.raw)) end },
    { token = 'weather', label = 'Weather', hover = 'weather',
        tip = 'The weather by name: Rain. None when the sky is clear.\nResting the mouse on it shows the weather\'s element and the zone\'s forecast.',
        Text = function(c) return c.weather end },
    { token = 'dayicon', label = 'Day Icon',
        tip = 'The day icon inside an info panel slot; its position follows the token.',
        Icon = function(c) return c.dayIcon end },
    { token = 'weathericon', label = 'Weather Icon',
        tip = 'The weather\'s icon in the line, from the Icon Set, in place of the game\'s above the clock.\nWhere the set has no picture for the weather, the game\'s own stays above.\nResting the mouse on it shows the weather\'s element and the zone\'s forecast.',
        Icon = function(c) return c.weatherIcon end },
    { token = 'level', module = 'exp', label = 'Level',
        tip = 'Your main job\'s level: Lv75.',
        Text = function(c) return c.exp and ('Lv%d'):format(c.exp.level) or nil end },
    { token = 'exp', module = 'exp', label = 'EXP',
        tip = 'Experience towards the next level, and how much the level takes: 12,345/30,000.\nIn limit mode, limit points towards the next merit point: LP 4,000/10,000.',
        Text = function(c)
            local e = c.exp
            if not e then return nil end
            if e.limit then return ('LP %s/%s'):format(exp.Commas(e.points), exp.Commas(exp.PointsPerMerit)) end
            if e.needed <= 0 then return exp.Commas(e.current) end
            return ('%s/%s'):format(exp.Commas(e.current), exp.Commas(e.needed))
        end },
    { token = 'tnl', module = 'exp', label = 'EXP To Level',
        tip = 'Experience still needed for the next level: TNL 17,655.\nIn limit mode, limit points still needed for the next merit point: TNM 6,000.',
        Text = function(c)
            local e = c.exp
            if not e then return nil end
            if e.limit then return ('TNM %s'):format(exp.Commas(math.max(0, exp.PointsPerMerit - e.points))) end
            if e.needed <= 0 then return nil end
            return ('TNL %s'):format(exp.Commas(math.max(0, e.needed - e.current)))
        end },
    { token = 'rate', module = 'exp', label = 'EXP Per Hour',
        tip = 'Experience gained in the last hour: 4,200 EXP/hr (since counting began, if sooner).\nLimit points in limit mode: LP/hr.',
        Text = function(c)
            local e = c.exp
            if not e then return nil end
            return ('%s %s/hr'):format(exp.Commas(e.rate), e.limit and 'LP' or 'EXP')
        end },
}

fields.ByToken = {}
for _, field in ipairs(fields.All) do fields.ByToken[field.token] = field end

-- Parsed once for each line, as the settings change it seldom
local parsed = {}
function fields.Parse(format)
    format = type(format) == 'string' and format or ''
    local pieces = parsed[format]
    if pieces then return pieces end
    pieces = {}
    local at = 1
    while at <= #format do
        local open, close, word = format:find('{(%w+)}', at)
        local field = open and fields.ByToken[word:lower()]
        if not open then
            pieces[#pieces + 1] = { literal = format:sub(at) }
            break
        end
        if open > at then pieces[#pieces + 1] = { literal = format:sub(at, open - 1) } end
        -- a word in braces that is no field is written as it is
        pieces[#pieces + 1] = field and { field = field } or { literal = format:sub(open, close) }
        at = close + 1
    end
    parsed[format] = pieces
    return pieces
end

function fields.Uses(format, module)
    for _, piece in ipairs(fields.Parse(format)) do
        if piece.field and piece.field.module == module then return true end
    end
    return false
end

function fields.Has(format, token)
    for _, piece in ipairs(fields.Parse(format)) do
        if piece.field and piece.field.token == token then return true end
    end
    return false
end

-- One native timestamp for every field avoids mixed dates/minutes across a rollover.
function fields.Context(time, grid, weather)
    return { time = time, raw = time.get_game_time_raw(), grid = grid, weather = weather }
end

function fields.Segments(context, format)
    local segments = { tooltips = {} }
    local pending, written, skipNext = '', false, false
    -- a word with a tooltip stands alone: the words before it and after it are segments of their own
    local function Words(words, tooltip)
        if words == '' then return end
        if tooltip == nil and type(segments[#segments]) == 'string' and segments.tooltips[#segments] == nil then
            segments[#segments] = segments[#segments] .. words
        else
            segments[#segments + 1] = words
            segments.tooltips[#segments] = tooltip
        end
    end
    for _, piece in ipairs(fields.Parse(format)) do
        if piece.literal then
            if skipNext then skipNext = false else pending = pending .. piece.literal end
        else
            local field = piece.field
            local value
            if field.Icon then value = field.Icon(context) else value = field.Text(context) end
            if value == nil or value == '' then
                -- the divider goes with it: the one before, or the first's the one after
                if written then pending = '' else pending, skipNext = '', true end
            else
                Words(pending)
                pending, written = '', true
                if field.Icon then
                    local kind = field.token == 'dayicon' and 'day' or 'weather'
                    segments[#segments + 1] = { icon = value, kind = kind, tooltip = kind == 'weather' and fields.Tooltip('weather', context) or fields.IconTooltip(kind, context) }
                else Words(value, field.hover and fields.Tooltip(field.hover, context) or nil) end
            end
        end
    end
    Words(pending)
    return segments
end

function fields.Line(context, format)
    local parts = {}
    for _, segment in ipairs(fields.Segments(context, format)) do
        if type(segment) == 'string' then parts[#parts + 1] = segment end
    end
    return table.concat(parts)
end

-- 0.6 kept an order of keys and which were ticked: as a line, two spaces apart, as it was drawn
local OLD = { time = 'time', grid = 'grid', day = 'day', date = 'date', moon = 'moon', weather = 'weather',
    weatherIcon = 'weathericon', level = 'level', exp = 'exp', toLevel = 'tnl', expRate = 'rate' }
function fields.FromList(order, shown, modules)
    local tokens = {}
    for _, key in ipairs(type(order) == 'table' and order or {}) do
        local token = OLD[key]
        local field = token and fields.ByToken[token]
        if field and type(shown) == 'table' and shown[key] == true
            and (field.module == nil or (modules ~= nil and modules[field.module] == true)) then
            tokens[#tokens + 1] = '{' .. token .. '}'
        end
    end
    return table.concat(tokens, '  ')
end

return fields
