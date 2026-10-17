-- Compare the preceding network chunk, preserving multiplicity within each chunk.
-- Identical hits inside one chunk are legitimate; a global payload hash would lose them.
local M = {}
function M.New()
    local current, previous = {}, {}
    return {
        Boundary = function()
            previous, current = current, {}
        end,
        Accept = function(data)
            current[data] = (current[data] or 0) + 1
            if (previous[data] or 0) > 0 then
                previous[data] = previous[data] - 1
                return false
            end
            return true
        end,
        Clear = function() current, previous = {}, {} end,
    }
end
return M
