-- The zone's weather forecast, as the Phoenix server rolls it (src/map/zone.cpp, UpdateWeather; the
-- tables in zone_weather.lua, built by tools/build_zone_weather.py from sql/zone_weather.sql).
--
--   forecast.Names[id]                  the weather by id, 0 to 19: Clear skies, Sunshine, ... Darkness
--   forecast.Day(raw)                   the day of the 2160-day cycle the raw game time is in: the
--                                       Vana'diel days since the epoch (3456 Earth seconds each), mod 2160
--   forecast.Odds(zone, day)            what the zone may roll on that day: nil where the zone is not
--                                       known; { fixed = id } where it never rolls; otherwise a list of
--                                       { weather = id, chance = percent }, the likeliest first, the
--                                       same weather's chances added up (a day of rain, rain, squalls
--                                       is 85% rain, 15% squalls)
--   forecast.City(zone)                 whether the fog rule leaves the zone alone
--   forecast.Lines(zone, raw, weekday, dayOfMonth, days)
--                                       the forecast as lines of text: today and the days after it (5
--                                       in all unless days says otherwise), each day's odds; nil where
--                                       the zone is not known or raw is not a number
local M = {}

M.Names = { [0] = 'Clear skies', 'Sunshine', 'Clouds', 'Fog', 'Hot spells', 'Heat waves',
    'Rain', 'Squalls', 'Dust storms', 'Sandstorms', 'Winds', 'Gales', 'Snow', 'Blizzards',
    'Thunder', 'Thunderstorms', 'Auroras', 'Stellar glare', 'Gloom', 'Darkness' }

M.SecondsPerDay = 3456 -- Earth seconds in a Vana'diel day: the raw game time counts them
M.RareChance, M.CommonChance = 15, 35 -- of 100; the normal weather takes the rest: the server's, from
-- zone_weather.lua (tools/build_zone_weather.py reads them from its zone.cpp), these where it has none

local days = { 'Firesday', 'Earthsday', 'Watersday', 'Windsday', 'Iceday', 'Lightningday', 'Lightsday', 'Darksday' }

local data = nil
local function Data()
    if data == nil then
        local ok, found = pcall(require, 'winxi.infopanel.zone_weather')
        data = ok and type(found) == 'table' and found or false
        if data and data.rareChance and data.commonChance then
            M.RareChance, M.CommonChance = data.rareChance, data.commonChance
        end
    end
    return data or nil
end

-- For the checks: tables in place of the generated ones (nil for the generated ones again)
function M.Use(tables) data = tables end

function M.Day(raw)
    raw = tonumber(raw)
    if not raw or raw ~= raw or raw < 0 then return nil end
    local tables = Data()
    return math.floor(raw / M.SecondsPerDay) % (tables and tables.cycle or 2160)
end

function M.City(zone)
    local tables = Data()
    return tables ~= nil and tables.cities[zone] == true
end

function M.Odds(zone, day)
    local tables = Data()
    zone, day = tonumber(zone), tonumber(day)
    if not tables or not zone or not day then return nil end
    if tables.fixed[zone] then return { fixed = tables.fixed[zone] } end
    local pattern = tables.patterns[tables.zones[zone] or 0]
    if not pattern then return nil end
    local triple = tables.triples[(pattern:byte(day % tables.cycle + 1) or 0) - 32]
    if not triple then return nil end
    local chances = { [triple[1]] = 100 - M.RareChance - M.CommonChance }
    chances[triple[2]] = (chances[triple[2]] or 0) + M.CommonChance
    chances[triple[3]] = (chances[triple[3]] or 0) + M.RareChance
    local odds = {}
    for weather, chance in pairs(chances) do odds[#odds + 1] = { weather = weather, chance = chance } end
    table.sort(odds, function(a, b)
        if a.chance ~= b.chance then return a.chance > b.chance end
        return a.weather < b.weather
    end)
    return odds
end

local function Said(odds)
    local parts = {}
    for _, o in ipairs(odds) do parts[#parts + 1] = ('%d%% %s'):format(o.chance, M.Names[o.weather] or ('Weather ' .. o.weather)) end
    return table.concat(parts, ', ')
end

function M.Lines(zone, raw, weekday, dayOfMonth, count)
    local today = M.Day(raw)
    if today == nil then return nil end
    local first = M.Odds(zone, today)
    if first == nil then return nil end
    if first.fixed then
        return { ('Always %s: the weather never changes here.'):format((M.Names[first.fixed] or ('Weather ' .. first.fixed)):lower()) }
    end
    local lines = {}
    weekday, dayOfMonth = tonumber(weekday), tonumber(dayOfMonth)
    for k = 0, (tonumber(count) or 5) - 1 do
        local odds = k == 0 and first or M.Odds(zone, today + k)
        local label = k == 0 and 'Today' or k == 1 and 'Tomorrow' or nil
        if weekday and dayOfMonth then
            local name = days[(weekday + k) % 8 + 1]
            local day = (dayOfMonth - 1 + k) % 30 + 1
            label = label and ('%s, %s %d'):format(label, name, day) or ('%s %d'):format(name, day)
        else
            label = label or ('In %d days'):format(k)
        end
        lines[#lines + 1] = ('%s: %s'):format(label, odds and not odds.fixed and Said(odds) or 'unknown')
    end
    return lines
end

return M
