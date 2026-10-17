-- Synthetic protocol fixtures. Slow bit-at-a-time writer, deliberately independent
-- from the production decoder. No client, GPL parser, or binary extension required.
local M = {}
function M.Packet(actor, category, ability, targets, sequence)
    local bytes = { 0x28, 0, (sequence or 1) % 256, math.floor((sequence or 1) / 256), 0 }
    local at = 40
    local function put(value, width)
        for bit = 0, width - 1 do
            local index, offset = math.floor(at / 8) + 1, at % 8
            bytes[index] = (bytes[index] or 0) + (math.floor(value / 2^bit) % 2) * 2^offset
            at = at + 1
        end
    end
    put(actor, 32); put(#targets, 6); put(0, 4); put(category, 4); put(ability, 32); put(0, 32)
    for _, target in ipairs(targets) do
        put(target.id, 32); put(#target.results, 4)
        for _, result in ipairs(target.results) do
            put(result.reaction or 0, 3); put(result.kind or 0, 2); put(result.animation or 0, 12)
            put(result.effect or 0, 5); put(result.scale or 0, 5)
            put(result.value or 0, 17); put(result.message or 0, 10); put(result.modifier or 0, 31)
            put(result.additional and 1 or 0, 1)
            if result.additional then
                local p = result.additional
                put(p.animation or 0, 6); put(p.effect or 0, 4); put(p.value, 17); put(p.message, 10)
            end
            put(result.reactive and 1 or 0, 1)
            if result.reactive then
                local r = result.reactive
                put(r.animation or 0, 6); put(r.effect or 0, 4); put(r.value, 14); put(r.message, 10)
            end
        end
    end
    bytes[5] = math.ceil(at / 8)
    while #bytes % 4 ~= 0 do bytes[#bytes + 1] = 0 end
    bytes[2] = #bytes / 2
    local chars = {}
    for i, byte in ipairs(bytes) do chars[i] = string.char(byte) end
    return table.concat(chars)
end
function M.Single(actor, category, message, damage, target, sequence)
    return M.Packet(actor, category, 42, { { id = target or 100, results = { { message = message, value = damage } } } }, sequence)
end
return M
