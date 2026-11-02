-- winxi.owntimers: the player's own statuses' time left, as winbuff read it before it was shared. The
-- same seconds for every timer but at the count's wrap, where winbuff added one sixtieth too few.
local owntimers = require('winxi.owntimers')

-- winbuff 1.2's own, as it was (addons/winbuff/statuses.lua before winxi 77)
local function Before(raw, stamp)
    if raw == nil or raw == 0x7FFFFFFF or stamp == nil then return nil end
    local left = raw - (stamp - 0x3C307D70) * 60
    while left < -2147483648 do left = left + 0xFFFFFFFF end
    if left < 1 then return 0 end
    return math.ceil(left / 60)
end

local EPOCH = 0x3C307D70
local same, tried, first = 0, 0, nil
for _, clock in ipairs({ EPOCH + 1, EPOCH + 5000, EPOCH + 1000000, EPOCH + 30000000 }) do
    for _, ahead in ipairs({ -600, -1, 0, 1, 59, 60, 61, 89, 3599, 3600, 3601, 7200 * 60, 30000 }) do
        local raw = (clock - EPOCH) * 60 + ahead
        tried = tried + 1
        local now, was = owntimers.Seconds(raw, clock), Before(raw, clock)
        if now == was then same = same + 1 elseif first == nil then first = ('%d %d: %s, was %s'):format(clock, ahead, tostring(now), tostring(was)) end
    end
end
H.print('every timer: the same seconds as winbuff had', same == tried, same, tried, first or '')
H.print('one that does not run out: no end, as winbuff had', owntimers.Seconds(0x7FFFFFFF, EPOCH + 5) == false, Before(0x7FFFFFFF, EPOCH + 5) == nil)
H.print('the clock not read: nil', owntimers.Seconds(1000, nil) == nil)
-- past the wrap: the game's count has gone round 2^32 sixtieths, the timer 90 s past it
local clock = EPOCH + math.floor(0x100000000 / 60) + 10
local raw = (clock - EPOCH) * 60 + 90 * 60 - 0x100000000
H.print('past the wrap: 90 s, as winbuff had it (its sixtieth short is lost in the rounding up)', owntimers.Seconds(raw, clock) == 90, Before(raw, clock) == 90)

-- the clock, found by its signature
local memory = { [0x9000] = 0x9100, [0x9100] = 0x9200, [0x9200 + 0x0C] = EPOCH + 77 }
ashita.memory.find = function(module, _, pattern) return module == 'FFXiMain.dll' and pattern == '8B0D????????8B410C8B49108D04808D04808D04808D04C1C3' and 0x9000 or 0 end
ashita.memory.read_uint32 = function(at) return memory[at] or 0 end
H.print('the clock, as the game keeps it', owntimers.Clock() == EPOCH + 77)

-- winbuff reads its timers with it: the player under Protect (90 s) and Signet (no end)
local winbuff = dofile('addons/winbuff/statuses.lua')
local player = { GetIsZoning = function() return 0 end, GetStatusIcons = function() return { 40, 253, 255 } end,
    GetStatusTimers = function() return { 77 * 60 + 90 * 60, 0x7FFFFFFF, 0 } end }
AshitaCore = AshitaCore or {}
AshitaCore.GetMemoryManager = function() return { GetPlayer = function() return player end,
    GetParty = function() return { GetMemberServerId = function() return 0x100 end } end } end
local list = {}
local count = winbuff.Read(list, true)
H.print('winbuff: Protect 90 s, Signet no end (nil)', count == 2, list[1].id == 40 and list[1].seconds == 90, list[2].id == 253 and list[2].seconds == nil)
