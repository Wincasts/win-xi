-- One native timestamp for every field avoids mixed dates/minutes across a rollover.
local days = { 'Firesday', 'Earthsday', 'Watersday', 'Windsday', 'Iceday', 'Lightningday', 'Lightsday', 'Darksday' }
local M = {}
function M.Read(time, weather)
    local raw = time.get_game_time_raw()
    local day = days[tonumber(time.get_game_weekday(raw)) + 1] or 'Unknown day'
    local lines = {
        ('%02d:%02d  %s'):format(time.get_game_hours(raw), time.get_game_minutes(raw), day),
        ("Vana'diel %04d-%02d-%02d"):format(time.get_game_year(raw), time.get_game_month(raw), time.get_game_day(raw)),
        ('Moon: %d%%'):format(time.get_game_moon_percent(raw)),
    }
    if weather then lines[#lines + 1] = 'Weather: ' .. weather end
    return lines
end
return M
