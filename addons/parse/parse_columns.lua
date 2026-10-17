-- Stable column identities. Labels and formatted values never determine saved order.
local core = require('parse_core')
local M = {}
M.Definitions = {
    actor = { label = 'Actor', width = 250, id = 1 },
    damage = { label = 'Damage', width = 100, id = 2 },
    share = { label = 'Share', width = 70, id = 3 },
    dps = { label = 'DPS', width = 90, id = 4 },
    melee = { label = 'Melee', width = 80, id = 5 },
    ranged = { label = 'Ranged', width = 80, id = 6 },
    magic = { label = 'Magic Damage', width = 110, id = 7 },
    ws_count = { label = 'WS Count', width = 85, id = 8 },
    ws_accuracy = { label = 'WS Hit % (TP)', width = 115, id = 9 },
    ws_unknown = { label = 'WS TP Unknown', width = 120, id = 10 },
    magic_accuracy = { label = 'Magic Land %', width = 110, id = 11 },
    magic_resists = { label = 'Magic Resists', width = 110, id = 12 },
}
function M.DefaultOrder() return { 'actor', 'damage', 'share', 'dps', 'melee', 'ranged', 'magic',
    'ws_count', 'ws_accuracy', 'ws_unknown', 'magic_accuracy', 'magic_resists' } end
function M.DefaultShown() return { actor = true, damage = true, share = true, dps = true, melee = true, ranged = true, magic = false,
    ws_count = false, ws_accuracy = false, ws_unknown = false, magic_accuracy = false, magic_resists = false } end
function M.Normalize(options)
    local order, seen = {}, {}
    for _, key in ipairs(type(options.columnOrder) == 'table' and options.columnOrder or {}) do
        if M.Definitions[key] and not seen[key] then order[#order + 1], seen[key] = key, true end
    end
    for _, key in ipairs(M.DefaultOrder()) do
        if not seen[key] then order[#order + 1] = key end
    end
    local shown, old = {}, type(options.columnShown) == 'table' and options.columnShown or {}
    local defaults = M.DefaultShown()
    for _, key in ipairs(order) do
        if old[key] == nil then shown[key] = defaults[key] else shown[key] = old[key] ~= false end
    end
    options.columnOrder, options.columnShown = order, shown
end
function M.Visible(options)
    local result = {}
    for _, key in ipairs(options.columnOrder) do
        if options.columnShown[key] then result[#result + 1] = key end
    end
    return result
end
function M.Move(options, index, direction)
    local other = index + direction
    if other < 1 or other > #options.columnOrder then return false end
    local order = options.columnOrder
    order[index], order[other] = order[other], order[index]
    return true
end
function M.TableId(visible)
    -- Preserve the original six-column layout's saved widths. Other layouts get
    -- their own native settings slot so widths cannot attach to the wrong stat.
    if table.concat(visible, ',') == 'actor,damage,share,dps,melee,ranged' then return '##parse.results' end
    return '##parse.results:' .. table.concat(visible, ',')
end
local function rate(stat)
    local value = stat and core.Rate(stat)
    return value and ('%.1f%%'):format(value) or '--'
end
function M.Value(key, row)
    if key == 'melee' then
        local value = core.MeleeRate(row)
        return value and ('%.1f%%'):format(value) or '--'
    end
    if key == 'ws_count' or key == 'ws_unknown' then
        local stat = row.categories[key]
        return tostring(stat and stat.count or 0)
    end
    if key == 'ws_accuracy' then return rate(row.categories.ws_hits) end
    if key == 'magic_resists' then return tostring(row.categories.magic_accuracy and row.categories.magic_accuracy.misses or 0) end
    if key == 'actor' then return row.name .. ' [' .. row.key .. ']' end
    if key == 'damage' then return tostring(row.damage) end
    if key == 'magic' then
        local spells, bursts = row.categories.spell, row.categories.burst
        return tostring((spells and spells.damage or 0) + (bursts and bursts.damage or 0))
    end
    if key == 'share' then return row.share and ('%.1f%%'):format(row.share) or '--' end
    if key == 'dps' then return row.dps and ('%.1f'):format(row.dps) or '--' end
    return rate(row.categories[key])
end
return M
