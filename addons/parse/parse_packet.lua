-- Bounded, unsigned decoder for the documented server 0x028 wire format.
-- Offsets: XiPackets world/server/0x0028; no runtime or copied decoder dependency.
local M = {}
function M.Decode(data)
    if type(data) ~= 'string' or #data < 19 or #data > 512 then
        return nil, 'invalid action packet size'
    end
    local position = 40 -- four-byte packet header, then WorkSize
    local function read(width)
        if position + width > #data * 8 then error('truncated action packet', 0) end
        local value, shift = 0, 0
        while width > 0 do
            local offset = position % 8
            local take = math.min(width, 8 - offset)
            local byte = data:byte(math.floor(position / 8) + 1)
            value = value + (math.floor(byte / 2 ^ offset) % 2 ^ take) * 2 ^ shift
            position, shift, width = position + take, shift + take, width - take
        end
        return value
    end
    local function decode()
        local action = { actor = read(32), target_count = read(6) }
        if action.actor == 0 then error('invalid actor ID', 0) end
        read(4) -- reserved result count
        action.category, action.ability, action.recast = read(4), read(32), read(32)
        action.targets = {}
        for i = 1, action.target_count do
            local target = { id = read(32), count = read(4), results = {} }
            if target.id == 0 then error('invalid target ID', 0) end
            for j = 1, target.count do
                local result = {
                    reaction = read(3), kind = read(2), animation = read(12), effect = read(5),
                    scale = read(5), value = read(17), message = read(10), modifier = read(31),
                }
                if read(1) == 1 then
                    result.additional = { animation = read(6), effect = read(4), value = read(17), message = read(10) }
                end
                if read(1) == 1 then
                    result.reactive = { animation = read(6), effect = read(4), value = read(14), message = read(10) }
                end
                target.results[j] = result
            end
            action.targets[i] = target
        end
        return action
    end
    local ok, result = pcall(decode)
    if not ok then return nil, tostring(result) end
    return result
end
return M
