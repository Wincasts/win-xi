-- What the clock's line can show, each a field the settings switch on or off and put in order.
--
--   fields.All                         every field, in the order a new character gets them
--   fields.ByKey[key]                  one of them
--   fields.Defaults()                  order (a list of keys) and shown (key -> true or false), for the settings
--   fields.Normalize(order, shown)     the settings made whole: unknown and repeated keys out, fields
--                                      added since in, at the end, shown as they are to begin with
--   fields.Move(order, at, by)         the field at a place moved up (-1) or down (1)
--   fields.Context(time, grid, weather) what the fields are written from, read once
--   fields.Line(context, order, shown) the line: the shown fields' words, in order, two spaces apart
--
-- A field is { key, label, tip, show, Text(context) }: label and tip are for the settings, show is
-- whether a new character has it, and Text gives its words, or nil when there are none to give (no
-- grid where the zone has no map). A new field (the EXP tracker, say) is one more entry in All, with
-- what it needs read into the context; characters' settings pick it up through Normalize.
local days = { 'Firesday', 'Earthsday', 'Watersday', 'Windsday', 'Iceday', 'Lightningday', 'Lightsday', 'Darksday' }

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

function fields.Line(context, order, shown)
    local parts = {}
    for _, key in ipairs(order) do
        local field = fields.ByKey[key]
        if field and shown[key] then
            local words = field.Text(context)
            if words ~= nil and words ~= '' then parts[#parts + 1] = words end
        end
    end
    return table.concat(parts, fields.Separator)
end

return fields
