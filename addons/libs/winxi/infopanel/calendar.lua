-- A calendar of the Vana'diel month, for the tooltip over the panel's time, day, date and moon.
--
--   calendar.Build(context)             the month from a fields context (time, raw, weekday): nil
--                                       without a time or a raw timestamp; otherwise
--                                         title     'Windsday, 900/12/30  3:32'
--                                         year, month, day, weekday, hours, minutes
--                                         first     the weekday of the month's first day, 0 to 7
--                                         rows      the month in weeks: each a list of 8 cells, a
--                                                   day number or false before the first and after
--                                                   the 30th
--                                         moon      'Waxing Gibbous, 62%'
--                                         next      'Iceday in 23 Earth minutes'
--   calendar.Phase(percent, waxing)     the moon's phase by its fullness and whether it is waxing
--   calendar.Draw(imgui, data, style)   draws it, inside a tooltip: the title, a header of the eight
--                                       days (style.icon(weekday) gives a day's picture, or nil for its
--                                       name), the weeks with today marked (style.highlight behind it)
--                                       and the days before it in style.dim, then the moon and the
--                                       next day
local M = {}

local days = { 'Firesday', 'Earthsday', 'Watersday', 'Windsday', 'Iceday', 'Lightningday', 'Lightsday', 'Darksday' }
local short = { 'Fire', 'Earth', 'Water', 'Wind', 'Ice', 'Ltng', 'Light', 'Dark' }
M.Days, M.Short = days, short

M.SecondsPerDay = 3456 -- Earth seconds in a Vana'diel day
M.DaysPerMonth = 30

-- The game's bands: full at 90 and over, new under 10, the quarters between 40 and 59
function M.Phase(percent, waxing)
    percent = tonumber(percent) or 0
    if percent >= 90 then return 'Full Moon' end
    if percent < 10 then return 'New Moon' end
    local half = waxing and 'Waxing' or 'Waning'
    if percent >= 60 then return half .. ' Gibbous' end
    if percent >= 40 then return waxing and 'First Quarter' or 'Last Quarter' end
    return half .. ' Crescent'
end

function M.Build(context)
    local time, raw = context and context.time, tonumber(context and context.raw)
    if type(time) ~= 'table' or not raw then return nil end
    local ok, built = pcall(function()
        local weekday = tonumber(context.weekday) or tonumber(time.get_game_weekday(raw))
        local day, month, year = tonumber(time.get_game_day(raw)), tonumber(time.get_game_month(raw)), tonumber(time.get_game_year(raw))
        local hours, minutes = tonumber(time.get_game_hours(raw)), tonumber(time.get_game_minutes(raw))
        local moon = tonumber(time.get_game_moon_percent(raw)) or 0
        local tomorrow = tonumber(time.get_game_moon_percent(raw + M.SecondsPerDay)) or moon
        if not (weekday and day and month and year and hours and minutes) then return nil end
        local first = (weekday - (day - 1)) % 8
        local rows, row = {}, {}
        for _ = 1, first do row[#row + 1] = false end
        for d = 1, M.DaysPerMonth do
            row[#row + 1] = d
            if #row == 8 then rows[#rows + 1] = row; row = {} end
        end
        if #row > 0 then
            while #row < 8 do row[#row + 1] = false end
            rows[#rows + 1] = row
        end
        local waxing = tomorrow > moon or (tomorrow == moon and moon < 50)
        local left = M.SecondsPerDay - raw % M.SecondsPerDay
        local minutesLeft = math.ceil(left / 60)
        return {
            title = ('%s, %d/%02d/%02d  %d:%02d'):format(days[weekday + 1] or 'Unknown day', year, month, day, hours, minutes),
            year = year, month = month, day = day, weekday = weekday, hours = hours, minutes = minutes,
            first = first, rows = rows,
            moon = ('%s, %d%%'):format(M.Phase(moon, waxing), moon),
            next = ('%s in %s'):format(days[(weekday + 1) % 8 + 1],
                minutesLeft <= 1 and 'under an Earth minute' or ('%d Earth minutes'):format(minutesLeft)),
        }
    end)
    return ok and built or nil
end

local cellSize, cellMin, cellMax = { 0, 0 }, { 0, 0 }, { 0, 0 }
function M.Draw(imgui, data, style)
    style = style or {}
    imgui.Text(data.title)
    local size = imgui.GetFontSize()
    local digits = imgui.CalcTextSize('30')
    local cell = math.max(digits, size) + 8
    local left = imgui.GetCursorPosX()
    -- the eight days across the top: the set's picture of each, or its name
    for col = 0, 7 do
        if col > 0 then imgui.SameLine() end
        imgui.SetCursorPosX(left + col * cell)
        local icon = style.icon and style.icon(col) or nil
        if icon then
            cellSize[1], cellSize[2] = size, size
            imgui.Image(icon, cellSize)
        else
            imgui.Text(short[col + 1])
        end
    end
    for _, row in ipairs(data.rows) do
        local drawn = false
        for col = 0, 7 do
            local day = row[col + 1]
            if day then
                if drawn then imgui.SameLine() end
                drawn = true
                imgui.SetCursorPosX(left + col * cell)
                local today = day == data.day
                if today and style.highlight then
                    local x, y = imgui.GetCursorScreenPos()
                    cellMin[1], cellMin[2], cellMax[1], cellMax[2] = x - 3, y - 1, x + digits + 3, y + size + 1
                    imgui.GetWindowDrawList():AddRectFilled(cellMin, cellMax, imgui.GetColorU32(style.highlight), 3)
                end
                local dim = day < data.day and style.dim
                if dim then imgui.PushStyleColor(ImGuiCol_Text, dim) end
                imgui.Text(tostring(day))
                if dim then imgui.PopStyleColor() end
            end
        end
        if not drawn then imgui.NewLine() end
    end
    imgui.Text(data.moon)
    imgui.Text(data.next)
end

return M
