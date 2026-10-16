-- The clock's one line, as the game writes its own and more: the time, the map grid, the day, the
-- date and the moon. One native timestamp for every field avoids mixed dates/minutes across a rollover.
local days = { 'Firesday', 'Earthsday', 'Watersday', 'Windsday', 'Iceday', 'Lightningday', 'Lightsday', 'Darksday' }
local M = {}
-- grid is the game's own "(H-9)", or nil where there is none
function M.Line(time, grid)
    local raw = time.get_game_time_raw()
    local parts = { ('%d:%02d'):format(time.get_game_hours(raw), time.get_game_minutes(raw)) }
    if grid and #grid > 0 then parts[#parts + 1] = grid end
    parts[#parts + 1] = days[tonumber(time.get_game_weekday(raw)) + 1] or 'Unknown day'
    parts[#parts + 1] = ('%d/%02d/%02d'):format(time.get_game_year(raw), time.get_game_month(raw), time.get_game_day(raw))
    parts[#parts + 1] = ('Moon %d%%'):format(time.get_game_moon_percent(raw))
    -- two spaces between, as the game puts between its time and grid
    return table.concat(parts, '  ')
end
return M
