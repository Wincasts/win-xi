-- What the clock's line can show, each a field the settings switch on or off and put in order.
--
--   fields.All                         every field, in the order a new character gets them
--   fields.ByKey[key]                  one of them
--   fields.Defaults()                  order (a list of keys) and shown (key -> true or false), for the settings
--   fields.Normalize(order, shown)     the settings made whole: unknown and repeated keys out, fields
--                                      added since in, at the end, shown as they are to begin with
--   fields.Move(order, at, by)         the field at a place moved up (-1) or down (1)
--   fields.Context(time, grid, weather) what the fields are written from, read once; the clock adds
--                                      weatherIcon (a set's picture) and exp (exp.Snapshot) to it
--   fields.Segments(context, order, shown, modules)
--                                      the line in pieces: words (a string: the shown fields'
--                                      words between icons, two spaces apart) and icons ({ icon =
--                                      handle }), in order
--   fields.Line(context, order, shown, modules)  the line's words alone, two spaces apart
--
-- A field is { key, label, tip, show, Text(context) } or, for a picture, Icon(context) in place of
-- Text: label and tip are for the settings, show is whether a new character has it, and Text gives
-- its words (Icon its handle), or nil when there are none to give (no grid where the zone has no
-- map). A field of a module (module = 'exp') is on the line only while modules[module] is true.
-- A new field is one more entry in All, with what it needs read into the context; characters'
-- settings pick it up through Normalize.
local days = { 'Firesday', 'Earthsday', 'Watersday', 'Windsday', 'Iceday', 'Lightningday', 'Lightsday', 'Darksday' }

local exp = require('exp')
local fields = {}

fields.Separator = '  ' -- as the game puts between its time and grid

fields.All = {
    { key = 'time', label = 'Time', show = true,
        tip = 'Vana\'diel time, as the game writes it: 3:32.',
        Text = function(c) return ('%d:%02d'):format(c.time.get_game_hours(c.raw), c.time.get_game_minutes(c.raw)) end },
    { key = 'grid', label = 'Map Grid', show = true,
        tip = 'Where you are on the zone\'s map, as the game writes it: (H-9).\nThere is none where the zone has no map.',
        Text = function(c) return c.grid ~= nil and #c.grid > 0 and c.grid or nil end },
    { key = 'day', label = 'Day', show = true,
        tip = 'The day of the week: Windsday.\nThe game\'s icon for the day stays to the left of the line.',
        Text = function(c) return days[tonumber(c.time.get_game_weekday(c.raw)) + 1] or 'Unknown day' end },
    { key = 'date', label = 'Date', show = true,
        tip = 'Vana\'diel\'s year, month and day: 900/12/30.',
        Text = function(c)
            return ('%d/%02d/%02d'):format(c.time.get_game_year(c.raw), c.time.get_game_month(c.raw), c.time.get_game_day(c.raw))
        end },
    { key = 'moon', label = 'Moon', show = true,
        tip = 'How full the moon is: Moon 42%.',
        Text = function(c) return ('Moon %d%%'):format(c.time.get_game_moon_percent(c.raw)) end },
    { key = 'weather', label = 'Weather', show = false,
        tip = 'The weather by name: Rain.\nThe game already shows its icon above the clock. None when the sky is clear.',
        Text = function(c) return c.weather end },
    { key = 'weatherIcon', label = 'Weather Icon', show = false,
        tip = 'The weather\'s icon in the line, where the game would draw it above the clock, from the Icon Set.\nWhere the set has no picture for the weather, the game\'s own stays above.',
        Icon = function(c) return c.weatherIcon end },
    { key = 'level', module = 'exp', label = 'Level', show = true,
        tip = 'Your main job\'s level: Lv75.',
        Text = function(c) return c.exp and ('Lv%d'):format(c.exp.level) or nil end },
    { key = 'exp', module = 'exp', label = 'EXP', show = true,
        tip = 'Experience towards the next level, and how much the level takes: EXP 12,345/30,000.\nIn limit mode, limit points towards the next merit point: LP 4,000/10,000.',
        Text = function(c)
            local e = c.exp
            if not e then return nil end
            if e.limit then return ('LP %s/%s'):format(exp.Commas(e.points), exp.Commas(exp.PointsPerMerit)) end
            if e.needed <= 0 then return ('EXP %s'):format(exp.Commas(e.current)) end
            return ('EXP %s/%s'):format(exp.Commas(e.current), exp.Commas(e.needed))
        end },
    { key = 'toLevel', module = 'exp', label = 'EXP To Level', show = true,
        tip = 'Experience still needed for the next level: TNL 17,655.\nIn limit mode, limit points still needed for the next merit point: TNM 6,000.',
        Text = function(c)
            local e = c.exp
            if not e then return nil end
            if e.limit then return ('TNM %s'):format(exp.Commas(math.max(0, exp.PointsPerMerit - e.points))) end
            if e.needed <= 0 then return nil end
            return ('TNL %s'):format(exp.Commas(math.max(0, e.needed - e.current)))
        end },
    { key = 'expRate', module = 'exp', label = 'EXP Per Hour', show = true,
        tip = 'Experience gained per hour, over the time set under Experience: 4,200 EXP/hr.\nLimit points in limit mode: LP/hr.',
        Text = function(c)
            local e = c.exp
            if not e then return nil end
            return ('%s %s/hr'):format(exp.Commas(e.rate), e.limit and 'LP' or 'EXP')
        end },
}

fields.ByKey = {}
for _, field in ipairs(fields.All) do fields.ByKey[field.key] = field end

function fields.Defaults()
    local order, shown = T{}, T{}
    for i, field in ipairs(fields.All) do
        order[i] = field.key
        shown[field.key] = field.show
    end
    return order, shown
end

-- In place, as they are the settings' own tables.
function fields.Normalize(order, shown)
    local seen, kept = {}, {}
    for _, key in ipairs(order) do
        if fields.ByKey[key] and not seen[key] then
            seen[key] = true
            kept[#kept + 1] = key
        end
    end
    for _, field in ipairs(fields.All) do
        if not seen[field.key] then kept[#kept + 1] = field.key end
    end
    for i = #order, 1, -1 do order[i] = nil end
    for i, key in ipairs(kept) do order[i] = key end
    for key in pairs(shown) do
        if not fields.ByKey[key] then shown[key] = nil end
    end
    for _, field in ipairs(fields.All) do
        if type(shown[field.key]) ~= 'boolean' then shown[field.key] = field.show end
    end
end

function fields.Move(order, at, by)
    local to = at + by
    if at < 1 or at > #order or to < 1 or to > #order then return false end
    order[at], order[to] = order[to], order[at]
    return true
end

-- One native timestamp for every field avoids mixed dates/minutes across a rollover.
function fields.Context(time, grid, weather)
    return { time = time, raw = time.get_game_time_raw(), grid = grid, weather = weather }
end

local function On(field, shown, modules)
    return shown[field.key] and (field.module == nil or (modules ~= nil and modules[field.module] == true))
end

function fields.Segments(context, order, shown, modules)
    local segments, words = {}, {}
    local function Flush()
        if #words > 0 then segments[#segments + 1] = table.concat(words, fields.Separator) end
        words = {}
    end
    for _, key in ipairs(order) do
        local field = fields.ByKey[key]
        if field and On(field, shown, modules) then
            if field.Icon then
                local handle = field.Icon(context)
                if handle then
                    Flush()
                    segments[#segments + 1] = { icon = handle }
                end
            else
                local text = field.Text(context)
                if text ~= nil and text ~= '' then words[#words + 1] = text end
            end
        end
    end
    Flush()
    return segments
end

function fields.Line(context, order, shown, modules)
    local parts = {}
    for _, segment in ipairs(fields.Segments(context, order, shown, modules)) do
        if type(segment) == 'string' then parts[#parts + 1] = segment end
    end
    return table.concat(parts, fields.Separator)
end

return fields
