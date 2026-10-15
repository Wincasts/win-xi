-- Stable status ordering and screen-aware capacity. Returned lists are read-only to callers.
-- Weak input keys release departed rosters; value snapshots detect in-place game-data updates.
local statuses = {}
local harmful = {}
-- Common negative statuses; custom/unknown effects can be explicitly prioritized by ID.
for id = 0, 31 do harmful[id] = true end
for _, id in ipairs({ 134, 135, 136, 137, 138, 139, 140, 141, 142, 144, 146, 147, 156, 168, 177, 192, 193, 194 }) do harmful[id] = true end
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
            local rank = priority[id] or (style.debuffsFirst and harmful[id] and 2048 or 4096)
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
