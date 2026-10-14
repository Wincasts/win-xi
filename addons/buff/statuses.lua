-- What the player is under, and for how long yet: read from the game each frame.
local bit = require('bit');

local statuses = {};

local noTimer = 0x7FFFFFFF;    -- what the game keeps for a status that does not run out
local vanaEpoch = 0x3C307D70;  -- when the game's count of time starts, in seconds of ours

-- where the game keeps the time it goes by: found once
local stampPointer = ashita.memory.find('FFXiMain.dll', 0, '8B0D????????8B410C8B49108D04808D04808D04808D04C1C3', 2, 0);

local function Stamp()
    if stampPointer == nil or stampPointer == 0 then
        return nil;
    end
    local pointer = ashita.memory.read_uint32(stampPointer);
    pointer = pointer ~= 0 and ashita.memory.read_uint32(pointer) or 0;
    if pointer == 0 then
        return nil;
    end
    return ashita.memory.read_uint32(pointer + 0x0C);
end

-- The seconds a status has left, from what the game keeps for it (sixtieths of a second, on its own
-- count of time). nil for one that does not run out, or while the time cannot be read.
local function Seconds(raw, stamp)
    if raw == nil or raw == noTimer or stamp == nil then
        return nil;
    end
    local left = raw - (stamp - vanaEpoch) * 60;
    -- the count wraps round every few years
    while left < -2147483648 do
        left = left + 0xFFFFFFFF;
    end
    if left < 1 then
        return 0;
    end
    return math.ceil(left / 60);
end

local entries = {}; -- kept from frame to frame, to be filled again

-- Fills list with the player's statuses, in the game's order: each { id, seconds }, seconds nil for
-- one with no end. Returns how many. Nothing while there is no player, or between areas.
-- wantTimers defaults to true for callers that need the full snapshot.
function statuses.Read(list, wantTimers)
    local count = 0;
    local memory = AshitaCore:GetMemoryManager();
    local party, player = memory:GetParty(), memory:GetPlayer();
    if party ~= nil and player ~= nil and party:GetMemberServerId(0) ~= 0 and player:GetIsZoning() == 0 then
        local ids = player:GetStatusIcons();
        local timers, stamp, clockRead, timersRead;
        wantTimers = wantTimers ~= false;
        for slot = 1, 32 do
            local id = ids[slot];
            if id ~= nil and id > 0 and id ~= 255 and id < 0x400 then
                count = count + 1;
                local entry = entries[count];
                if entry == nil then
                    entry = { id = 0, seconds = nil };
                    entries[count] = entry;
                end
                local seconds;
                if wantTimers then
                    if not timersRead then
                        timers, timersRead = player:GetStatusTimers(), true;
                    end
                    local raw = timers and timers[slot];
                    if raw ~= nil and raw ~= noTimer and not clockRead then
                        stamp, clockRead = Stamp(), true;
                    end
                    seconds = Seconds(raw, stamp);
                end
                entry.id, entry.seconds = id, seconds;
                list[count] = entry;
            end
        end
    end
    for index = #list, count + 1, -1 do
        list[index] = nil;
    end
    return count;
end

-- Asks the game to take a status off, as its own status window does
function statuses.Cancel(id)
    AshitaCore:GetPacketManager():AddOutgoingPacket(0xF1, { 0x00, 0x00, 0x00, 0x00, bit.band(id, 0xFF), bit.rshift(id, 8), 0x00, 0x00 });
end

return statuses;
