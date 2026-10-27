-- Experience for the clock's line: the level, the experience towards the next and how much is left,
-- and how fast it is coming, from the server's messages of experience gained.
--
--   exp.Packet(id, data)     every incoming packet: a gain of the player's own is counted
--   exp.Snapshot(now, window) what the fields write from, read now: { level, current, needed, limit,
--                            points, merits, rate }, or nil while there is no player; rate is per
--                            hour over the last window seconds (since tracking began, if sooner,
--                            and at least a minute, so the first kill does not read as a great rate)
--   exp.Reset(now)           the rate begun again
--   exp.Since()              when tracking began (os.clock), and how many gains have been counted
--
-- Gains are counted from the server's messages (packet 0x02D), not from the experience in memory,
-- which cannot be compared across a level up and does not move at all while limit points are
-- earned. On Phoenix (src/map/utils/charutils.cpp) they are messages 8 and 253 (experience, and an
-- experience chain) and 371 and 372 (limit points, and a limit chain), sent by and to the player,
-- the amount the message's first number. A merit point is 10,000 limit points (merit.cpp).
local exp = {}

exp.PointsPerMerit = 10000
do -- the server's (winxi.rules' merits, from its merit.cpp), the same where winxi's data is not installed
    local ok, rules = pcall(require, 'winxi.rules')
    local merits = ok and rules.Get('merits') or nil
    exp.PointsPerMerit = merits and merits.LimitPointsPerMerit or exp.PointsPerMerit
end
local MESSAGES = { [8] = 'exp', [253] = 'exp', [371] = 'limit', [372] = 'limit' }
local MIN_SPAN = 60

local times, amounts = {}, {}
local first, last, sum = 1, 0, 0
local started, counted = nil, 0

local function U16(data, at) local a, b = data:byte(at + 1, at + 2) return (a or 0) + (b or 0) * 256 end
local function U32(data, at) return U16(data, at) + U16(data, at + 2) * 65536 end

local function PlayerId()
    local ok, id = pcall(function() return AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0) end)
    return ok and id or nil
end

function exp.Packet(id, data, now)
    if id ~= 0x02D or type(data) ~= 'string' or #data < 0x1A then return false end
    if not MESSAGES[U16(data, 0x18)] then return false end
    local me = PlayerId()
    if me == nil or me == 0 or U32(data, 0x04) ~= me then return false end
    now = now or os.clock()
    started = started or now
    last = last + 1
    times[last], amounts[last] = now, U32(data, 0x10)
    sum = sum + amounts[last]
    counted = counted + 1
    return true
end

local function Prune(now, window)
    while first <= last and times[first] < now - window do
        sum = sum - amounts[first]
        times[first], amounts[first] = nil, nil
        first = first + 1
    end
    if first > last then first, last, sum = 1, 0, 0 end
end

function exp.Reset(now)
    times, amounts, first, last, sum = {}, {}, 1, 0, 0
    started, counted = now or os.clock(), 0
end

function exp.Since()
    return started, counted
end

function exp.Snapshot(now, window)
    local ok, player = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer() end)
    if not ok or player == nil then return nil end
    local read = function(name)
        local fine, value = pcall(function() return player[name](player) end)
        return fine and value or nil
    end
    local level = read('GetMainJobLevel')
    if not level or level == 0 then return nil end
    now = now or os.clock()
    window = window or 3600
    Prune(now, window)
    local span = started and math.max(MIN_SPAN, math.min(window, now - started)) or nil
    return {
        level = level,
        current = read('GetExpCurrent') or 0,
        needed = read('GetExpNeeded') or 0,
        limit = read('GetIsLimitModeEnabled') == true,
        points = read('GetLimitPoints') or 0,
        merits = read('GetMeritPoints') or 0,
        rate = span and math.floor(sum / span * 3600 + 0.5) or 0,
    }
end

-- 12345678 -> 12,345,678
function exp.Commas(n)
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (out:gsub('^,', ''))
end

return exp
