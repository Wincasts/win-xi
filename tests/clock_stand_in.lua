-- The clock addon with uihook's bridge and the game's time stood in for, for tests/clock_check.lua:
--     luajit tests/harness.lua clock tests/clock_stand_in.lua tests/clock_check.lua
-- CLOCK holds what the check sets (the game's clock's place, its grid) and what the addon asked.
package.path = 'addons/clock/?.lua;' .. package.path

CLOCK = { rect = nil, grid = '(H-9)', ready = { true, true }, log = {}, status = 'Drawn in place of the game\'s clock.',
    icons = {}, weather = nil, hidden = 0, files = {}, loads = 0 }
local function Slot(index)
    local slot = {}
    local function Note(what) CLOCK.log[#CLOCK.log + 1] = (index == 0 and 'clock.' or 'compass.') .. what end
    function slot.Begin() Note('begin'); return CLOCK.ready[index + 1] end
    function slot.Capture() Note('capture'); return true end
    function slot.Stop() Note('stop'); if index == 0 then CLOCK.hidden = 0 end end
    function slot.Status() return index == 0 and CLOCK.status or 'Native replacement ready.' end
    function slot.Weather() return index == 0 and CLOCK.weather or nil end
    function slot.IconRect(icon)
        local r = index == 0 and CLOCK.icons[icon]
        if not r then return nil end
        return unpack(r)
    end
    function slot.HideIcons(mask)
        if index ~= 0 then return false end
        CLOCK.hidden = mask
        return true
    end
    function slot.ClockRect()
        if index ~= 0 or not CLOCK.rect then return nil end
        return unpack(CLOCK.rect)
    end
    function slot.Grid() return index == 0 and CLOCK.grid or nil end
    return slot
end
package.loaded['winxi.nativehud'] = { Clock = 0, Compass = 1, DayIcon = 0, WeatherIcon = 1, SecondWeatherIcon = 2,
    HideDay = 1, HideWeather = 2, new = function(index) return Slot(index) end }

-- an icon set, 'mine', holding the pictures CLOCK.files names (days\windsday, weather\water, ...),
-- each loaded as a handle numbered from 1000
local icons = require('icons')
icons.Load = function(path) CLOCK.loads = CLOCK.loads + 1; return 1000 + CLOCK.loads end
local exists, directory = ashita.fs.exists, ashita.fs.get_directory
ashita.fs.exists = function(path)
    if type(path) == 'string' and path:find('\\icons\\mine\\$') then return true end
    local name = type(path) == 'string' and path:match('\\icons\\mine\\(.+)%.png$')
    if name then return CLOCK.files[(name:gsub('\\', '/'))] == true end
    return exists(path)
end
ashita.fs.get_directory = function(path)
    if type(path) == 'string' and path:find('\\clock\\icons\\$') then return { 'mine', 'readme.txt' } end
    return directory(path)
end

CLOCK.raws = 0
local time = { get_game_time_raw = function() CLOCK.raws = CLOCK.raws + 1; return 123 end }
for name, value in pairs({ weekday = 3, hours = 3, minutes = 32, year = 900, month = 12, day = 30, moon_percent = 42 }) do
    time['get_game_' .. name] = function(raw) assert(raw == 123, 'every field must use the same timestamp'); return value end
end
package.loaded['ffxi.time'] = time

-- a character's settings as clock 0.1 saved them
HARNESS_SAVED = { enabled = true, x = 20, y = -1 }

dofile('addons/clock/clock.lua')
