-- Bounded message history and a UTF-8-safe tail layout (ten rows in compact mode). No Ashita/ImGui dependency.
local M = { Rows = 10, Capacity = 256, MaxBytes = 8192 }
local npcModes = { [142] = true, [144] = true, [150] = true, [151] = true, [210] = true }

-- Remove FFXI formatting before CP932 conversion, without eating Shift-JIS trail bytes.
-- With icons enabled, return CP932 text runs interleaved with UTF-8 icon records.
-- Icons must bypass Windows' CP932 decoder: EF 27/28 are game codes, not SJIS.
function M.Clean(raw, icons, colors)
    local out, runs, i, preview = {}, {}, 1, false
    local function icon(text)
        if #out > 0 then runs[#runs + 1] = table.concat(out); out = {} end
        runs[#runs + 1] = { text = text }
    end
    while i <= #raw do
        local b, nextByte = raw:byte(i), raw:byte(i + 1)
        if icons and b == 0xef and (nextByte == 0x27 or nextByte == 0x28) then
            icon(nextByte == 0x27 and '❮' or '❯'); i = i + 2
        elseif icons and b == 0xef and nextByte and nextByte >= 0x1f and nextByte <= 0x26 then
            local elements = {'fire','ice','wind','earth','lightning','water','light','dark'}
            icon('[' .. elements[nextByte - 0x1e] .. ']'); i = i + 2
        elseif b == 0xef and nextByte and nextByte >= 0x1f and nextByte <= 0x4d then
            i = i + 2 -- the game's other pictographs, drawn from its table, not the font: nothing to show
        elseif icons and b == 0x7f and (nextByte == 0x66 or nextByte == 0x69 or nextByte == 0x64) then
            local opening = nextByte == 0x69 or (nextByte == 0x66 and not preview)
            icon(opening and '❮' or '❯')
            if nextByte == 0x66 then preview = not preview end
            i = i + 2
        elseif b == 0x1e or b == 0x1f then
            if colors and nextByte then
                if #out > 0 then runs[#runs + 1] = table.concat(out); out = {} end
                runs[#runs + 1] = { bank = b, slot = nextByte }
            end
            i = i + 2 -- palette escape + slot (the slot may itself be a control byte)
        elseif b == 0x7f then
            local third = raw:byte(i + 2)
            i = i + ((nextByte and nextByte >= 0x31 and nextByte <= 0x37
                and third and third >= 1 and third <= 6) and 3 or 2)
        elseif b == 0x81 and (nextByte == 0x3f or nextByte == 0x40) then
            -- Live combat capture: FFXI uses 81 3F between enemy-name words.
            -- It is not valid CP932: dropping only 81 would leak a literal '?'.
            -- Also normalise the SJIS ideographic space (81 40). Recognise both
            -- at character boundaries, never inside another SJIS character.
            out[#out + 1] = ' '; i = i + 2
        elseif (b >= 0x81 and b <= 0x9f) or (b >= 0xe0 and b <= 0xfc) then
            if nextByte and nextByte >= 0x40 and nextByte <= 0xfc and nextByte ~= 0x7f then
                out[#out + 1] = raw:sub(i, i + 1); i = i + 2
            else i = i + 1 end
        elseif b == 7 or b == 13 then
            -- NPC paragraph separator / carriage return, not a printable glyph.
            if not (b == 13 and nextByte == 10) then out[#out + 1] = '\n' end
            i = i + 1
        elseif b == 10 then
            out[#out + 1] = '\n'; i = i + 1
        elseif b == 9 then
            out[#out + 1] = ' '; i = i + 1
        elseif b >= 0x20 and b ~= 0x7f then
            out[#out + 1] = raw:sub(i, i); i = i + 1
        else i = i + 1 end
    end
    if not icons then return table.concat(out) end
    if #out > 0 then runs[#runs + 1] = table.concat(out) end
    return runs
end

function M.New() return { messages = {}, revision = 0 } end
function M.Clear(log)
    log.messages, log.cache, log.lastNpc, log.metrics, log.wraps = {}, nil, nil, nil, nil
    log.revision = log.revision + 1
end
function M.Add(log, text, mode, now, originalMode, spans)
    if type(text) ~= 'string' or #text > M.MaxBytes or not text:find('%S') then return false end
    if npcModes[mode] or npcModes[originalMode] then
        local stamp = M.Stamp(text) or ''
        local body = text:sub(#stamp + 1)
        -- Only label a named speaker, never anonymous dialogue or continuation lines.
        local name, separator, rest = body:match('^([^:\n]+)(:%s*)(.*)$')
        if not name then name, separator, rest = body:match('^([^\n]-)(：%s*)(.*)$') end
        if name and #name <= 96 then
            local rich = require('richtext')
            local tagStart, tagEnd = name:find('%[[Nn][Pp][Cc]%]')
            local first
            if tagStart then
                -- Normalise pre-existing tags without duplicating them or shifting their spans.
                text = stamp .. name:sub(1,tagStart-1) .. '[NPC]' .. name:sub(tagEnd+1) .. separator .. rest
                first = #stamp + tagStart + 1
            else
                local prefix = stamp .. name:gsub('%s+$', '')
                local oldEnd = #stamp + #name
                spans = rich.Insert(spans, oldEnd, #prefix + 6 - oldEnd)
                text = prefix .. ' [NPC]' .. separator .. rest
                first = #prefix + 3
            end
            -- Only the letters are yellow; brackets and surrounding text keep their source colour.
            spans = rich.Paint(spans, first, first+2, 31, 50)
        end
    end
    -- NPC dialogue can reach text_in more than once, including a 150/151
    -- channel change. Compare decoded text, not palette/prompt control bytes.
    -- Keep this scoped to dialogue: repeated player/combat/system lines are real.
    if mode == 150 or mode == 151 or originalMode == 150 or originalMode == 151 then
        now = now or os.clock()
        local previous = log.lastNpc
        if previous and previous.text == text and now >= previous.time and now - previous.time < 1 then
            return false
        end
        log.lastNpc = { text = text, time = now }
    end
    log.messages[#log.messages + 1] = { text = text, mode = mode, originalMode = originalMode,
        time = now or os.clock(), spans = spans }
    if #log.messages > M.Capacity then
        local removed = table.remove(log.messages, 1)
        for _, layout in ipairs(log.wraps or {}) do layout.messages[removed] = nil end
    end
    log.revision = log.revision + 1
    return true
end

-- Each boundary is a whole UTF-8 code point. Incoming text has already been decoded by Windows.
local function Boundaries(text)
    local at, boundaries = 1, { 0 }
    while at <= #text do
        local b = text:byte(at)
        at = at + (b < 0x80 and 1 or b < 0xe0 and 2 or b < 0xf0 and 3 or 4)
        boundaries[#boundaries + 1] = math.min(at - 1, #text)
    end
    return boundaries
end
function M.Wrap(text, width, measure)
    local rows = {}
    for paragraph in (text .. '\n'):gmatch('(.-)\n') do
        paragraph = paragraph:gsub('\r', '')
        if paragraph == '' then rows[#rows + 1] = '' end
        local boundaries, first = Boundaries(paragraph), 1
        while first < #boundaries do
            local low, high, best = first + 1, #boundaries, first + 1
            while low <= high do
                local mid = math.floor((low + high) / 2)
                if measure(paragraph:sub(boundaries[first] + 1, boundaries[mid])) <= width then
                    best, low = mid, mid + 1
                else high = mid - 1 end
            end
            -- Prefer a word boundary. A word wider than the window still advances one glyph at least.
            local stop = boundaries[best]
            local piece = paragraph:sub(boundaries[first] + 1, stop)
            if best < #boundaries and not paragraph:sub(stop + 1, boundaries[best + 1]):match('^%s$') then
                local space = piece:match('^.*()%s')
                if space and space > 1 then
                    stop = boundaries[first] + space
                    while best > first + 1 and boundaries[best] > stop do best = best - 1 end
                    piece = paragraph:sub(boundaries[first] + 1, boundaries[best])
                end
            end
            rows[#rows + 1] = piece:gsub('%s+$', '')
            first = best
            while first < #boundaries and paragraph:sub(boundaries[first] + 1, boundaries[first + 1]):match('^%s$') do
                first = first + 1
            end
        end
    end
    return rows
end
-- Two layouts cover the full width and scrollbar-reserved width. Wrapping is independent of
-- channel filters and viewport offsets; retain it per message, not per rendered viewport.
-- Eviction in Add and reset in Clear bound storage to retained messages in these two layouts.
local function Wrapped(log, width, font, size, measure)
    local layouts = log.wraps or {}
    log.wraps = layouts
    for i, layout in ipairs(layouts) do
        if layout.width == width and layout.font == font and layout.size == size then
            if i > 1 then table.remove(layouts, i); table.insert(layouts, 1, layout) end
            return layout.messages
        end
    end
    local messages = {}
    table.insert(layouts, 1, { width = width, font = font, size = size, messages = messages })
    if #layouts > 2 then table.remove(layouts) end
    return messages
end
local function Lines(cache, message, width, measure)
    local wrapped = cache[message]
    if not wrapped then
        wrapped = { lines = M.Wrap(message.text, width, measure) }
        cache[message] = wrapped
    end
    return wrapped
end
local function Offsets(wrapped, text)
    if wrapped.offsets then return wrapped.offsets end
    local offsets, at = {}, 1
    for n, line in ipairs(wrapped.lines) do
        offsets[n] = text:find(line, at, true) or at
        at = offsets[n] + #line
        if text:sub(at, at) == '\n' then at = at + 1 end
    end
    wrapped.offsets = offsets
    return offsets
end

-- Total wrapped rows plus cumulative row counts by newest-message index. Used by the scrollbar
-- and keyboard browser to describe the same viewport. Cached separately from the tail layout.
function M.Metrics(log, width, font, size, measure, modes)
    local cache = log.metrics or {}
    for _, cached in ipairs(cache) do
        if cached.width == width and cached.font == font and cached.size == size and cached.modes == modes then
            if cached.revision == log.revision then return cached end
        end
    end
    local wrapped = Wrapped(log, width, font, size, measure)
    local metrics = {revision=log.revision,width=width,font=font,size=size,modes=modes,total=0,newer={[0]=0},counts={}}
    local index = 0
    for i=#log.messages,1,-1 do
        local message = log.messages[i]
        if not modes or modes[message.mode] then
            index = index+1
            local count = #Lines(wrapped, message, width, measure).lines
            metrics.counts[message] = count
            metrics.total = metrics.total + count
            metrics.newer[index] = metrics.total
        end
    end
    table.insert(cache,1,metrics)
    if #cache > 2 then table.remove(cache) end
    log.metrics = cache
    return metrics
end

-- modes, if given, is a set of the chat modes to show (a channel of the full log); nil shows them all.
-- newer: how many of the newest of those to leave out, to look further back (0 for the newest).
-- Each row has its message: index, its place counting back from the newest shown by modes (1 the
-- newest), and message itself (text and mode).
function M.Tail(log, width, font, size, measure, rowCount, modes, newer, rowOffset)
    rowCount = math.max(1, math.min(2048, math.floor(tonumber(rowCount) or M.Rows)))
    newer = math.max(0, math.floor(tonumber(newer) or 0))
    rowOffset = math.max(0, math.min(M.Capacity*(M.MaxBytes+1), math.floor(tonumber(rowOffset) or 0)))
    local requestedOffset = rowOffset
    local cache = log.cache
    if cache and cache.revision == log.revision and cache.width == width and cache.font == font and cache.size == size
        and cache.rowCount == rowCount and cache.modes == modes and cache.newer == newer and cache.rowOffset == rowOffset then
        return cache.rows, cache.actualOffset, cache.overflow
    end
    local wrapped = Wrapped(log, width, font, size, measure)
    local groups, count, index, remaining = {}, 0, 0, false
    for i = #log.messages, 1, -1 do
        local message = log.messages[i]
        if not modes or modes[message.mode] then
            index = index + 1
            if index > newer then
                local entry = Lines(wrapped, message, width, measure)
                local lines, offsets = entry.lines, Offsets(entry, message.text)
                groups[#groups + 1] = { lines = lines, offsets = offsets, mode = message.mode, index = index, message = message }
                count = count + #lines
                if count >= rowCount + rowOffset then
                    for j = i - 1, 1, -1 do
                        if not modes or modes[log.messages[j].mode] then remaining = true; break end
                    end
                    break
                end
            end
        end
    end
    local rows = {}
    rowOffset = math.min(rowOffset, math.max(0, count - rowCount))
    local skip = math.max(0, count - rowCount - rowOffset)
    for i = #groups, 1, -1 do
        local group = groups[i]
        for line, text in ipairs(group.lines) do
            -- first: the message's first row, where a timestamp would be
            if skip > 0 then skip = skip - 1
            elseif #rows < rowCount then rows[#rows + 1] = { text = text, mode = group.mode, first = line == 1, index = group.index, message = group.message,
                spans = require('richtext').Slice(group.message.spans, group.offsets[line], #text) } end
        end
    end
    log.cache = { revision = log.revision, width = width, font = font, size = size, rowCount = rowCount, modes = modes,
        newer = newer, rowOffset = requestedOffset, actualOffset = rowOffset, overflow = remaining or count > rowCount, rows = rows }
    return rows, rowOffset, log.cache.overflow
end
-- How many messages modes shows (all of them for nil).
function M.Count(log, modes)
    if not modes then return #log.messages end
    local count = 0
    for _, message in ipairs(log.messages) do
        if modes[message.mode] then count = count + 1 end
    end
    return count
end
-- A timestamp at the start of a line, as Ashita's timestamps write it ([23:55:59], [11:55 PM]), or nil.
function M.Stamp(text)
    return type(text) == 'string' and text:match('^(%[%d%d?:%d%d[%d:]*%s?[AaPp]?[Mm]?%])') or nil
end
return M
