-- The ships' and airships' timetable, as the Phoenix server runs them (src/map/transports/ship_handler.cpp;
-- the runs in transports.lua, built by tools/build_transports.py from data/zones/<name>/zone.yaml), for the
-- tooltip over the panel's zone name: the next few to leave, of the lines the player wants to see.
--
-- Every run is a cycle of `every` seconds from its `offset`, the seconds into it being (raw - offset) mod
-- every, raw the client's raw game time (the Earth seconds since the Vana'diel epoch, which is the server's
-- Vana'diel timestamp). The door opens at `boards` seconds into the cycle and shuts at `leaves`; the riders
-- are put ashore at `disembark` seconds into it, so the crossing takes (disembark - leaves) mod every.
--
--   schedule.Lines()                    every line, in order: { key, group (its label), from, to }, for the
--                                       settings' whitelist; nil without the tables
--   schedule.Count                      how many ships are shown: 4
--   schedule.Into(run, raw)             seconds into the run's cycle
--   schedule.Status(run, raw)           boarding (the door open now), boardsIn, leavesIn, trip (seconds),
--                                       carrying (riders at sea or in the air), ashoreIn
--   schedule.Clock(raw)                 the Vana'diel time of a raw timestamp: '8:00'
--   schedule.Span(seconds)              Earth time to come: '4:25', '1:02:14' past an hour
--   schedule.Build(zone, raw, shown)    the timetable from the zone the player is in and the sample's raw
--                                       time, of the lines shown (a map of line key to true or false, or
--                                       to { true } or { false } as the settings hold them; nil for every
--                                       line): nil without the tables or a timestamp; otherwise
--                                         title     'Ships and airships'
--                                         aboard    lines for a player on a crossing ('Bound for Jeuno: ashore
--                                                   in 2:14'), or nil
--                                         columns   the headings: From, To, Boarding, Leaves, At, Trip
--                                         rows      the next Count ships to leave, the soonest first, each
--                                                   { cells = { ... }, here = bool, key }: a line's two runs
--                                                   (the barge from the central landing by day and by night)
--                                                   count once, the nearer; here marks the rows that board in
--                                                   the player's zone
--                                         here      whether any row is the zone's
--                                         empty     what to say where no line is shown, or nil
--                                         note      what the columns are
--   schedule.Draw(imgui, data, style)   draws it, inside a tooltip: the title, the aboard lines, the headings
--                                       in style.dim, the rows in columns, the zone's own rows over
--                                       style.highlight, the note in style.dim
local M = {}

M.SecondsPerDay = 3456 -- Earth seconds in a Vana'diel day
M.Columns = { 'From', 'To', 'Boarding', 'Leaves', 'At', 'Trip' }
M.Title = 'Ships and airships'
M.Count = 4
M.Empty = 'No lines are shown: tick some in the Timetable tab of the Info Panel settings.'
M.Note = 'The next %d to leave. Earth minutes:seconds until the door opens and shuts; At is the Vana\'diel time it leaves; Trip the crossing.'

local data = nil
local function Data()
    if data == nil then
        local ok, found = pcall(require, 'winxi.infopanel.transports')
        data = ok and type(found) == 'table' and type(found.runs) == 'table' and found or false
    end
    return data or nil
end

-- For the checks: tables in place of the generated ones (nil for the generated ones again)
function M.Use(tables) data = tables end

function M.Lines()
    local tables = Data()
    if not tables or type(tables.lines) ~= 'table' then return nil end
    local labels = {}
    for _, group in ipairs(tables.groups or {}) do labels[group.key] = group.label end
    local lines = {}
    for _, line in ipairs(tables.lines) do
        lines[#lines + 1] = { key = line.key, group = labels[line.group] or line.group, from = line.from, to = line.to }
    end
    return lines
end

function M.Into(run, raw)
    return (raw - run.offset) % run.every
end

function M.Status(run, raw)
    local into = M.Into(run, raw)
    local every = run.every
    local boarding = into >= run.boards and into < run.leaves
    local carrying
    if run.leaves <= run.disembark then
        carrying = into >= run.leaves and into < run.disembark
    else
        carrying = into >= run.leaves or into < run.disembark
    end
    return {
        boarding = boarding,
        boardsIn = boarding and 0 or (run.boards - into) % every,
        leavesIn = (run.leaves - into) % every,
        trip = (run.disembark - run.leaves) % every,
        carrying = carrying,
        ashoreIn = (run.disembark - into) % every,
    }
end

function M.Clock(raw)
    local day = raw % M.SecondsPerDay
    return ('%d:%02d'):format(math.floor(day / 144), math.floor(day % 144 / 2.4))
end

function M.Span(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 3600 then
        return ('%d:%02d:%02d'):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
    end
    return ('%d:%02d'):format(math.floor(seconds / 60), seconds % 60)
end

local function Shown(shown, key)
    if shown == nil then return true end
    local value = shown[key]
    if type(value) == 'table' then value = value[1] end
    return value ~= false
end

function M.Build(zone, raw, shown)
    local tables = Data()
    raw, zone = tonumber(raw), tonumber(zone)
    if not tables or not raw or raw ~= raw then return nil end
    local built = { title = M.Title, columns = M.Columns, rows = {}, note = M.Note:format(M.Count), here = false }
    local rows, byLine = {}, {}
    local aboard = {}
    local any = false
    for _, run in ipairs(tables.runs) do
        local status = M.Status(run, raw)
        local key = run.line or run.name
        if Shown(shown, key) then
            any = true
            local row = byLine[key]
            if not row or status.leavesIn < row.leavesIn then
                if not row then
                    row = { key = key }
                    rows[#rows + 1] = row
                    byLine[key] = row
                end
                row.leavesIn = status.leavesIn
                row.here = run.zone == zone
                row.cells = { run.from, run.to, status.boarding and 'now' or M.Span(status.boardsIn),
                    M.Span(status.leavesIn), M.Clock(raw + status.leavesIn), M.Span(status.trip) }
            end
        end
        if zone and status.carrying then
            for _, crossing in ipairs(run.crossings) do
                if crossing == zone then
                    aboard[#aboard + 1] = ('Bound for %s: ashore in %s'):format(run.to, M.Span(status.ashoreIn))
                end
            end
        end
    end
    -- the soonest to leave first; alike, in the tables' order
    for i, row in ipairs(rows) do row.order = i end
    table.sort(rows, function(a, b)
        if a.leavesIn ~= b.leavesIn then return a.leavesIn < b.leavesIn end
        return a.order < b.order
    end)
    for i = 1, math.min(M.Count, #rows) do
        local row = rows[i]
        row.order, row.leavesIn = nil, nil
        built.rows[i] = row
        if row.here then built.here = true end
    end
    if not any then built.empty = M.Empty end
    if #aboard == 0 and zone then
        for _, run in ipairs(tables.runs) do
            for _, crossing in ipairs(run.crossings) do
                if crossing == zone and #aboard == 0 then aboard[1] = 'Arriving: the riders are put ashore now.' end
            end
        end
    end
    if #aboard > 0 then built.aboard = aboard end
    return built
end

local rowMin, rowMax = { 0, 0 }, { 0, 0 }
function M.Draw(imgui, built, style)
    style = style or {}
    imgui.Text(built.title)
    for _, line in ipairs(built.aboard or {}) do imgui.Text(line) end
    if built.empty then
        imgui.Text(built.empty)
        return
    end
    -- each column as wide as its widest words, a gap between
    local widths = {}
    for i, heading in ipairs(built.columns) do widths[i] = imgui.CalcTextSize(heading) end
    for _, row in ipairs(built.rows) do
        for i, cell in ipairs(row.cells) do widths[i] = math.max(widths[i] or 0, imgui.CalcTextSize(cell)) end
    end
    local gap = math.max(8, imgui.CalcTextSize('  '))
    local left = imgui.GetCursorPosX()
    local total = 0
    for i = 1, #widths do total = total + widths[i] + (i > 1 and gap or 0) end
    local function Cells(cells, dim)
        if dim then imgui.PushStyleColor(ImGuiCol_Text, dim) end
        local x = left
        for i, cell in ipairs(cells) do
            if i > 1 then imgui.SameLine() end
            imgui.SetCursorPosX(x)
            imgui.Text(cell)
            x = x + widths[i] + gap
        end
        if dim then imgui.PopStyleColor() end
    end
    Cells(built.columns, style.dim)
    local size = imgui.GetFontSize()
    for _, row in ipairs(built.rows) do
        if row.here and style.highlight then
            imgui.SetCursorPosX(left)
            local x, y = imgui.GetCursorScreenPos()
            rowMin[1], rowMin[2], rowMax[1], rowMax[2] = x - 3, y - 1, x + total + 3, y + size + 1
            imgui.GetWindowDrawList():AddRectFilled(rowMin, rowMax, imgui.GetColorU32(style.highlight), 3)
        end
        Cells(row.cells)
    end
    if style.dim then imgui.PushStyleColor(ImGuiCol_Text, style.dim) end
    imgui.Text(built.note)
    if style.dim then imgui.PopStyleColor() end
end

return M
