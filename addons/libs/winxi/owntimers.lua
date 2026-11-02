-- winxi.owntimers: how long the player's own statuses have left, read from the game to the second.
--
--     owntimers.Clock()               the game's count of time, or nil while it cannot be read
--     owntimers.Seconds(raw, clock)   the seconds one of the player's statuses has left, from its timer as
--                                     the game keeps it (player:GetStatusTimers()): false for one that does
--                                     not run out, nil while the clock cannot be read
--     owntimers.NoTimer               the timer the game keeps for a status that does not run out
--
-- The game keeps each of the player's statuses' end in sixtieths of a second on its own count of time,
-- which starts at VANA_EPOCH. Used by winbuff and winxi.statustimes, so that both read them alike.
local owntimers = {};

local NO_TIMER   = 0x7FFFFFFF; -- what the game keeps for a status that does not run out
local VANA_EPOCH = 0x3C307D70; -- when the game's count of time starts, in seconds of ours

owntimers.NoTimer = NO_TIMER;

-- Where the game keeps the time it goes by: looked for the first time it is wanted, and once only
local clockPointer = nil;

function owntimers.Clock()
    if (clockPointer == nil) then
        clockPointer = ashita.memory.find('FFXiMain.dll', 0, '8B0D????????8B410C8B49108D04808D04808D04808D04C1C3', 2, 0) or 0;
    end
    if (clockPointer == 0) then
        return nil;
    end
    local pointer = ashita.memory.read_uint32(clockPointer);
    pointer = pointer ~= 0 and ashita.memory.read_uint32(pointer) or 0;
    if (pointer == 0) then
        return nil;
    end
    return ashita.memory.read_uint32(pointer + 0x0C);
end

function owntimers.Seconds(raw, clock)
    if (raw == NO_TIMER) then
        return false;
    end
    if (raw == nil or clock == nil) then
        return nil;
    end
    local left = raw - (clock - VANA_EPOCH) * 60;
    -- the count wraps round every few years: 2^32 sixtieths
    while (left < -2147483648) do
        left = left + 0x100000000;
    end
    if (left < 1) then
        return 0;
    end
    return math.ceil(left / 60);
end

return owntimers;
