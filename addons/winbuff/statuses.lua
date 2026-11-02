-- What the player is under, and for how long yet: read from the game each frame.
local bit = require('bit');

local statuses = {};

-- the game's timers read as winxi reads them, to the second: winxi.owntimers
local owntimers = require('winxi.owntimers');
-- who put each there: what winxi.debuffs saw land on the player, kept with the status (winxi.statustimes)
local debuffs = require('winxi.debuffs');
local statustimes = require('winxi.statustimes');

local watchIds = { count = 0 }; -- the statuses' numbers, for statustimes.Watch

local entries = {}; -- kept from frame to frame, to be filled again

-- Fills list with the player's statuses, in the game's order: each { id, seconds, mine }, seconds nil
-- for one with no end, mine whether the player put it there. Returns how many. Nothing while there is no
-- player, or between areas. wantTimers defaults to true for callers that need the full snapshot; with
-- them, who put each there is followed as well.
function statuses.Read(list, wantTimers)
    wantTimers = wantTimers ~= false;
    local count = 0;
    local memory = AshitaCore:GetMemoryManager();
    local party, player = memory:GetParty(), memory:GetPlayer();
    local me = party ~= nil and party:GetMemberServerId(0) or 0;
    if party ~= nil and player ~= nil and me ~= 0 and player:GetIsZoning() == 0 then
        local ids = player:GetStatusIcons();
        local timers, stamp, clockRead, timersRead;
        for slot = 1, 32 do
            local id = ids[slot];
            if id ~= nil and id > 0 and id ~= 255 and id < 0x400 then
                count = count + 1;
                local entry = entries[count];
                if entry == nil then
                    entry = { id = 0, seconds = nil, mine = false };
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
                entry.id, entry.seconds, entry.mine = id, seconds, false;
                list[count] = entry;
                watchIds[count] = id;
            end
        end
        if wantTimers then
            -- what is new on the player began now, and the landing seen of each is kept with it
            for index = #watchIds, count + 1, -1 do
                watchIds[index] = nil;
            end
            watchIds.count = count;
            statustimes.Watch(me, watchIds);
            for index = 1, count do
                local entry = list[index];
                entry.mine = statustimes.CastBy(me, entry.id) == me;
            end
        end
    end
    for index = #list, count + 1, -1 do
        list[index] = nil;
    end
    return count;
end

-- Every packet in: what lands on the player, and who put it there
function statuses.HandlePacket(e)
    debuffs.HandlePacket(e);
end

-- Asks the game to take a status off, as its own status window does
function statuses.Cancel(id)
    AshitaCore:GetPacketManager():AddOutgoingPacket(0xF1, { 0x00, 0x00, 0x00, 0x00, bit.band(id, 0xFF), bit.rshift(id, 8), 0x00, 0x00 });
end

return statuses;
