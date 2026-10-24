-- Stable status ordering and screen-aware capacity. Returned lists are read-only to callers.
-- Weak input keys release departed rosters; value snapshots detect in-place game-data updates.
local statuses = {}
local harmful = {}
-- The debuffs, from Phoenix's data/status_effects.yaml: every effect Erase or a waltz removes, and those
-- that cannot be cancelled and do harm (sleep, petrification, charm, doom, helix, the songs on enemies,
-- the dazes, the Geo downs and the like). Others can be put first by ID with Priority Status IDs.
for _, id in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
    28, 29, 30, 31, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 144, 145,
    146, 147, 148, 149, 156, 167, 168, 174, 175, 177, 186, 189, 192, 193, 194, 217, 223, 259, 260, 261,
    262, 263, 264, 291, 298, 309, 404, 473, 536, 540, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566,
    567, 571, 572, 576, 630, 631, 802 }) do harmful[id] = true end
for id = 386, 400 do harmful[id] = true end -- lethargic, sluggish and weakened daze
for id = 448, 452 do harmful[id] = true end -- bewildered daze
local hiddenText, priorityText, hidden, priority = nil, nil, {}, {}
local cache = setmetatable({}, { __mode = 'k' })
local ranks = {}
local generation, debuffsFirst = 0, false
local perf = require('perf')
local function Parse(text, ranked)
    local list, count = {}, 0
    for word in (text or ''):gmatch('%d+') do
        local id = tonumber(word)
        if id <= 1023 and list[id] == nil then count = count + 1; list[id] = ranked and count or true end
    end
    return list
end
function statuses.Select(ids, style)
    if hiddenText ~= style.hiddenStatuses then
        hiddenText = style.hiddenStatuses; hidden = Parse(hiddenText)
        generation = generation + 1
    end
    if priorityText ~= style.priorityStatuses then
        priorityText = style.priorityStatuses; priority = Parse(priorityText, true)
        generation = generation + 1
    end
    if debuffsFirst ~= (style.debuffsFirst == true) then
        debuffsFirst = style.debuffsFirst == true
        generation = generation + 1
    end
    local kept = cache[ids]
    if not kept then
        kept = { input = {}, selected = {} }
        cache[ids] = kept
    end
    local unchanged = kept.generation == generation and #kept.input == #ids
    if unchanged then
        for index, id in ipairs(ids) do
            if kept.input[index] ~= id then unchanged = false; break end
        end
    end
    if unchanged then return kept.selected end

    perf.Count('status reorderings')
    local selected, input = kept.selected, kept.input
    local count = 0
    for index, id in ipairs(ids) do
        input[index] = id
        if not hidden[id] then
            count = count + 1
            -- Debuffs First puts every debuff before every buff; Priority Status IDs order each kind
            local rank = (priority[id] or 4096) + (style.debuffsFirst and not harmful[id] and 8192 or 0)
            local at = count
            while at > 1 and ranks[at - 1] > rank do
                selected[at], ranks[at] = selected[at - 1], ranks[at - 1]; at = at - 1
            end
            selected[at], ranks[at] = id, rank
        end
    end
    for i = #selected, count + 1, -1 do selected[i] = nil end
    for i = #input, #ids + 1, -1 do input[i] = nil end
    kept.generation = generation
    return selected
end
-- Capacity uses the widest icon, so mixed custom/native sets never run past the screen edge.
function statuses.Plan(style, left, right, screen, size, gap)
    local direction = style.buffDirection or 'left'
    if direction == 'auto' then direction = left >= screen - right and 'left' or 'right' end
    local anchor = direction == 'right' and right or left
    local rows = math.max(1, math.min(2, style.buffRows or 1))
    local limit = math.max(1, math.min(32, style.buffLimit or 16))
    local columns = math.ceil(limit / rows)
    if style.buffFitScreen ~= false then
        anchor = math.max(0, math.min(screen, anchor))
        local space = direction == 'right' and screen - anchor or anchor
        columns = math.max(0, math.min(columns, math.floor((space + gap) / math.max(1, size + gap))))
    end
    return direction, anchor, columns, math.min(limit, columns * rows)
end
return statuses
