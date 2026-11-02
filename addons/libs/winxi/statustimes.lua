-- winxi.statustimes: how long a status has left, as a few letters to write under its icon, and whether
-- that is known or only estimated.
--
--     statustimes.Begin()                       once a frame, before any Text: the time now; the player's
--                                               own timers are read again the first time they are asked for
--     statustimes.Watch(serverId, ids)          a party member's statuses as the game keeps them, each time
--                                               they are read: what is new on them is seen to begin now
--     statustimes.Text(serverId, id, nth)       the label for the nth (1 if not given) of that status on them,
--                                               true when it is an estimate, and true when the player put it
--                                               there; nil when nothing is written (a status that does not run
--                                               out, or one the game writes no time under)
--     statustimes.Label(seconds)                45, 3m, 2h: seconds under a minute, then minutes, then hours
--     statustimes.Unknown                       the label where the time cannot be known: '-'
--
-- What can be known is not the same for everyone:
--   the player's own    the game keeps each one's end, read to the second: exact
--   the party's         the game keeps only what they are. Seen to land (winxi.debuffs), the spell's or
--                       move's usual time from then; seen to appear on them, the status's usual time from
--                       then (the server's durations set); otherwise, or once that time is past and it is
--                       still on them, not known
--   anyone else         what winxi.debuffs saw land, for its usual time; one whose length its data does
--                       not give is not known
-- Whose it is: the player's when the last landing seen of it on them was the player's, so that one
-- put there by anyone else after it, which takes its place, is not. Of the player's own statuses,
-- the same; one that was not seen to land is no one's.
-- Usual times are the server's base ones: skill, merits, gear, Composure and partial resists are not
-- known, so an estimate can run out before or after the status does.
--
-- Each addon is its own Lua state: an addon that uses this hands winxi.debuffs its packets, and calls
-- Watch for the party members it reads.
local debuffs = require('winxi.debuffs');

local statustimes = {};

statustimes.Unknown = '-';

local NO_TIMER   = 0x7FFFFFFF;  -- what the game keeps for a status of the player's that does not run out
local VANA_EPOCH = 0x3C307D70;  -- when the game's count of time starts, in seconds of ours
local SLOTS      = 32;          -- statuses kept for the player
local FORGET     = 30;          -- seconds a member not watched is kept for: back after that, they are new
local LANDED_SLACK = 2;         -- seconds a landing may be seen before the status appears on the member

local now = 0;
local ownRead = false;
local ownId = 0;
local ownTimes = {};   -- status -> { seconds or false, ... } in the game's order, kept from frame to frame
local ownCount = {};   -- status -> how many of it the player has this frame
local watched = {};    -- server id -> { seen = time last watched, [status] = when it was seen to begin, or false }
local lastPrune = 0;

-- Where the game keeps the time it goes by, as the buff addon finds it: looked for the first time the
-- player's timers are wanted
local stampPointer = nil;

local function Stamp()
    if (stampPointer == nil) then
        stampPointer = ashita.memory.find('FFXiMain.dll', 0, '8B0D????????8B410C8B49108D04808D04808D04808D04C1C3', 2, 0) or 0;
    end
    if (stampPointer == 0) then
        return nil;
    end
    local pointer = ashita.memory.read_uint32(stampPointer);
    pointer = pointer ~= 0 and ashita.memory.read_uint32(pointer) or 0;
    if (pointer == 0) then
        return nil;
    end
    return ashita.memory.read_uint32(pointer + 0x0C);
end

-- The seconds one of the player's statuses has left, from what the game keeps for it (sixtieths of a
-- second, on its own count of time): false for one that does not run out, nil while it cannot be read
local function OwnSeconds(raw, stamp)
    if (raw == NO_TIMER) then
        return false;
    end
    if (raw == nil or stamp == nil) then
        return nil;
    end
    local left = raw - (stamp - VANA_EPOCH) * 60;
    -- the count wraps round every few years
    while (left < -2147483648) do
        left = left + 0xFFFFFFFF;
    end
    if (left < 1) then
        return 0;
    end
    return math.ceil(left / 60);
end

local function ReadOwn()
    ownRead = true;
    for id in pairs(ownCount) do
        ownCount[id] = 0;
    end
    local memory = AshitaCore:GetMemoryManager();
    local party, player = memory:GetParty(), memory:GetPlayer();
    ownId = party ~= nil and party:GetMemberServerId(0) or 0;
    if (player == nil or ownId == 0 or player:GetIsZoning() ~= 0) then
        return;
    end
    local ids, timers, stamp = player:GetStatusIcons(), player:GetStatusTimers(), Stamp();
    if (ids == nil) then
        return;
    end
    for slot = 1, SLOTS do
        local id = ids[slot];
        if (id ~= nil and id > 0 and id ~= 255 and id < 0x400) then
            local count = (ownCount[id] or 0) + 1;
            ownCount[id] = count;
            local times = ownTimes[id];
            if (times == nil) then
                times = {};
                ownTimes[id] = times;
            end
            times[count] = OwnSeconds(timers ~= nil and timers[slot] or nil, stamp);
        end
    end
end

function statustimes.Begin()
    now = os.time();
    ownRead = false;
    if (now - lastPrune >= FORGET) then
        lastPrune = now;
        for serverId, member in pairs(watched) do
            if (now - member.seen > FORGET) then
                watched[serverId] = nil;
            end
        end
    end
end

-- A member's statuses this time they are read. The first time a member is watched, what is on them
-- already began at a time not known; what appears after that began now.
local present = {};

function statustimes.Watch(serverId, ids)
    if (serverId == nil or serverId == 0 or ids == nil) then
        return;
    end
    local time = os.time();
    local member = watched[serverId];
    local fresh = member == nil;
    if (fresh) then
        member = {};
        watched[serverId] = member;
    end
    member.seen = time;
    for id in pairs(present) do
        present[id] = nil;
    end
    for index = 1, (ids.count or #ids) do
        local id = ids[index];
        if (id ~= nil) then
            present[id] = true;
            if (member[id] == nil) then
                member[id] = (not fresh) and time or false;
            end
        end
    end
    for id in pairs(member) do
        if (id ~= 'seen' and not present[id]) then
            member[id] = nil;
        end
    end
end

-- The labels, each made once
local labels = {};

function statustimes.Label(seconds)
    local key, form, value;
    if (seconds >= 3600) then
        value = math.floor(seconds / 3600);
        key, form = 20000 + value, '%dh';
    elseif (seconds >= 60) then
        value = math.floor(seconds / 60);
        key, form = 10000 + value, '%dm';
    else
        value = math.max(0, math.floor(seconds));
        key, form = value, '%d';
    end
    local label = labels[key];
    if (label == nil) then
        label = form:format(value);
        labels[key] = label;
    end
    return label;
end

-- The statuses the game writes no time under, as the buff addon leaves them without one
local timerHidden = {};

local function HidesTimer(id)
    local hidden = timerHidden[id];
    if (hidden == nil) then
        local icon = AshitaCore:GetResourceManager():GetStatusIconByIndex(id);
        hidden = icon ~= nil and icon.HideTimer ~= 0;
        -- one not loaded yet is asked again
        if (icon ~= nil) then
            timerHidden[id] = hidden;
        end
    end
    return hidden;
end

-- Whether the player put it there: the last landing of it seen on them was theirs, and is the one on
-- them now (not before it last appeared, and not run out where when it appeared is not known)
local function Mine(entry, since)
    return entry ~= nil and ownId ~= 0 and entry.by == ownId
        and (not since or (entry.at or 0) >= since - LANDED_SLACK)
        and (since or now < entry.expires);
end

function statustimes.Text(serverId, id, nth)
    if (id == nil or HidesTimer(id)) then
        return nil;
    end
    if (not ownRead) then
        ReadOwn();
    end
    local on = serverId ~= nil and debuffs.Statuses(serverId) or nil;
    local entry = on and on[id];
    if (serverId ~= nil and serverId ~= 0 and serverId == ownId) then
        local mine = Mine(entry, nil);
        local count = ownCount[id] or 0;
        if (count > 0) then
            local seconds = ownTimes[id][math.min(nth or 1, count)];
            if (seconds == false) then
                return nil;
            end
            if (seconds ~= nil) then
                return statustimes.Label(seconds), false, mine;
            end
        end
        return statustimes.Unknown, true, mine;
    end

    local member = serverId ~= nil and watched[serverId] or nil;
    local since = member and member[id] or nil; -- false: on them since a time not known
    local mine = Mine(entry, since);
    -- seen to land, and not before the status last appeared on them
    if (entry ~= nil and entry.known ~= false and now < entry.expires
            and (not since or (entry.at or 0) >= since - LANDED_SLACK)) then
        return statustimes.Label(entry.expires - now), true, mine;
    end
    if (since) then
        local usual = debuffs.UsualSeconds(id);
        if (usual ~= nil and since + usual > now) then
            return statustimes.Label(since + usual - now), true, mine;
        end
    end
    return statustimes.Unknown, true, mine;
end

return statustimes;
