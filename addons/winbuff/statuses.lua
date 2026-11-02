-- What the player is under, and for how long yet: read from the game each frame.
local bit = require('bit');

local statuses = {};

-- the game's timers read as winxi reads them, to the second: winxi.owntimers
local owntimers = require('winxi.owntimers');

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
                    if raw ~= nil and raw ~= owntimers.NoTimer and not clockRead then
                        stamp, clockRead = owntimers.Clock(), true;
                    end
                    seconds = owntimers.Seconds(raw, stamp) or nil; -- false, none to run out: nil, as before
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
