-- Current zone weather, independent of the native clock being drawn. Same weather-state
-- signature used by the zone addon: MOV AX,[absolute weather word], CMP AX,limit.
-- Read-only; missing/unrecognised clients return nil rather than inventing clear skies.
local M = {}
local address, retry, problem = nil, 0, nil
function M.Read()
    local ok, value = pcall(function()
        local memory = ashita.memory
        if not address then
            if os.clock() < retry then return nil end
            retry = os.clock() + 5
            local at = memory.find('FFXiMain.dll', 0, '66A1????????663D????72', 0, 0)
            if not at or at == 0 then problem = 'weather state was not found'; return nil end
            local found = memory.read_uint32(at + 2)
            if not found or found == 0 then problem = 'weather state address is unavailable'; return nil end
            address = found
        end
        return memory.read_uint16(address)
    end)
    if not ok then problem = 'weather state could not be read'; return nil end
    if type(value) ~= 'number' or value ~= value or value < 0 or value > 19 or value % 1 ~= 0 then return nil end
    problem = nil
    return value
end
function M.Status() return problem end
return M
