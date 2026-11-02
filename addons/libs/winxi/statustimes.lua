-- winxi.statustimes: how long a status has left, as a few letters to write under its icon, and whether
-- that is known or only estimated.
--
--     statustimes.Begin()                       once a frame, before any Text, whether or not anything is
--                                               drawn: the time now, and the player's own statuses and timers
--     statustimes.Watch(serverId, ids)          a party member's statuses as the game keeps them, each time
--                                               they are read: what is new on them is seen to begin now. Only
--                                               a read that found them: a list emptied because the game keeps
--                                               nothing for them is not one
--     statustimes.CastBy(serverId, id)          the server id of who put that status on a watched member, as
--                                               the last landing of it seen says; nil where none was seen
--     statustimes.WatchParty()                  the five others of the party read and watched, for an addon
--                                               that does not read them every frame itself
--     statustimes.Text(serverId, id, nth)       the label for the nth (1 if not given) of that status on them,
--                                               true when it is an estimate, true when the player put it
--                                               there, and the seconds left (nil where not known); nil when
--                                               nothing is written (a status that does not run out, or one the
--                                               game writes no time under)
--     statustimes.Landing(serverId, id)         the landing seen that put that status there, { by, category,
--                                               param } (the action's: 4 and the spell for a spell), or nil
--     statustimes.Label(seconds)                45, 3m, 2h: seconds under a minute, then minutes, then hours
--     statustimes.Unknown                       the label where the time cannot be known: '-'
--
-- What can be known is not the same for everyone:
--   the player's own    the game keeps each one's end, read to the second (winxi.owntimers): exact
--   the party's         the game keeps only what they are. Seen to land (winxi.debuffs), the spell's or
--                       move's usual time from then; seen to appear on them, the status's usual time from
--                       then (the server's durations set); otherwise, or once that time is past and it is
--                       still on them, not known
--   anyone else         what winxi.debuffs saw land, for its usual time; one whose length its data does
--                       not give is not known
-- Whose it is: the player's when the last landing seen of it on them was the player's, so that one
-- put there by anyone else after it, which takes its place, is not; one that was not seen to land is
-- no one's. Of the player and the party, the landing that matches what is on them is kept here for as
-- long as it is on them, so a change of area, which empties winxi.debuffs, leaves it.
-- A member not watched for FORGET seconds is new when watched again; between areas no one is watched,
-- and no one is forgotten.
-- Usual times are the server's base ones: skill, merits, gear, Composure and partial resists are not
-- known, so an estimate can run out before or after the status does.
--
-- Each addon is its own Lua state: an addon that uses this hands winxi.debuffs its packets, and calls
-- Watch for the party members it reads.
local debuffs = require('winxi.debuffs');
local partystatus = require('winxi.partystatus');
local owntimers = require('winxi.owntimers');

local statustimes = {};

statustimes.Unknown = '-';

local SLOTS      = 32;          -- statuses kept for the player
local FORGET     = 30;          -- seconds a member not watched is kept for: back after that, they are new
local LANDED_SLACK = 2;         -- seconds a landing may be seen before the status appears on the member

local now = 0;
local ownRead = false;
local ownId = 0;
local ownTimes = {};   -- status -> { seconds or false, ... } in the game's order, kept from frame to frame
local ownCount = {};   -- status -> how many of it the player has this frame
local ownList = { count = 0 }; -- the player's statuses this frame, to be watched as a member's are
local zoning = false;  -- between areas: nothing is watched, and no one forgotten
-- server id -> { seen = time last watched, since = { [status] = when it was seen to begin, or false },
-- landed = { [status] = { from, by, at, expires, known, category, param }, the landing of what is on them, from being
-- winxi.debuffs' entry it was copied from } }
local watched = {};
local lastPrune = 0;
local party = {};      -- WatchParty's lists
for member = 1, 5 do
    party[member] = { id = 0, count = 0 };
end

local function ReadOwn()
    ownRead = true;
    for id in pairs(ownCount) do
        ownCount[id] = 0;
    end
    local memory = AshitaCore:GetMemoryManager();
    local party, player = memory:GetParty(), memory:GetPlayer();
    ownId = party ~= nil and party:GetMemberServerId(0) or 0;
    zoning = player ~= nil and player:GetIsZoning() ~= 0;
    if (player == nil or ownId == 0 or zoning) then
        return;
    end
    local ids, timers, stamp = player:GetStatusIcons(), player:GetStatusTimers(), owntimers.Clock();
    if (ids == nil) then
        return;
    end
    local listed = 0;
    for slot = 1, SLOTS do
        local id = ids[slot];
        if (id ~= nil and id > 0 and id ~= 255 and id < 0x400) then
            local count = (ownCount[id] or 0) + 1;
            ownCount[id] = count;
            listed = listed + 1;
            ownList[listed] = id;
            local times = ownTimes[id];
            if (times == nil) then
                times = {};
                ownTimes[id] = times;
            end
            times[count] = owntimers.Seconds(timers ~= nil and timers[slot] or nil, stamp);
        end
    end
    for index = #ownList, listed + 1, -1 do
        ownList[index] = nil;
    end
    ownList.count = listed;
    statustimes.Watch(ownId, ownList);
end

function statustimes.Begin()
    now = os.time();
    ReadOwn();
    if (zoning) then
        -- no one is read between areas: they are not forgotten for it
        for _, member in pairs(watched) do
            member.seen = now;
        end
        return;
    end
    if (now - lastPrune >= FORGET) then
        lastPrune = now;
        for serverId, member in pairs(watched) do
            if (now - member.seen > FORGET) then
                watched[serverId] = nil;
            end
        end
    end
end

-- A member's statuses this time they are read. The first time a member is watched, or the first after
-- FORGET seconds unwatched, what is on them already began at a time not known; what appears after that
-- began now. The landing seen of each, if any, that is the one on them is kept with it.
local present = {};

function statustimes.Watch(serverId, ids)
    if (serverId == nil or serverId == 0 or ids == nil or zoning) then
        return;
    end
    local time = os.time();
    local member = watched[serverId];
    local fresh = member == nil or time - member.seen > FORGET;
    if (fresh) then
        member = { since = {}, landed = {} };
        watched[serverId] = member;
    end
    member.seen = time;
    for id in pairs(present) do
        present[id] = nil;
    end
    local since, landed = member.since, member.landed;
    local on = debuffs.Statuses(serverId);
    for index = 1, (ids.count or #ids) do
        local id = ids[index];
        if (id ~= nil and not present[id]) then
            present[id] = true;
            if (since[id] == nil) then
                since[id] = (not fresh) and time or false;
            end
            -- a landing seen of it: when it appeared on them (or not long before), or, when that is not
            -- known, one not yet run out; a later one takes the place of the one kept
            local entry = on and on[id];
            local began, kept = since[id], landed[id];
            if (entry ~= nil and (kept == nil or (kept.from ~= entry and (entry.at or 0) >= kept.at))
                    and (began and (entry.at or 0) >= began - LANDED_SLACK or (not began and time < entry.expires))) then
                if (kept == nil) then
                    kept = {};
                    landed[id] = kept;
                end
                kept.from, kept.by, kept.at, kept.expires, kept.known = entry, entry.by, entry.at or 0, entry.expires, entry.known;
                kept.category, kept.param = entry.category, entry.param;
            end
        end
    end
    for id in pairs(since) do
        if (not present[id]) then
            since[id], landed[id] = nil, nil;
        end
    end
end

function statustimes.CastBy(serverId, id)
    local member = serverId ~= nil and watched[serverId] or nil;
    local kept = member and member.landed[id];
    return kept and kept.by or nil;
end

function statustimes.WatchParty()
    if (zoning) then
        return;
    end
    partystatus.Party(party);
    for member = 1, #party do
        statustimes.Watch(party[member].id, party[member]);
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

-- What is known of a status on them: the landing kept with a watched member, or winxi.debuffs' entry
-- for anyone else, and when it was seen to begin, and whether the player put it there
local function Known(serverId, id)
    local member = serverId ~= nil and watched[serverId] or nil;
    if (member ~= nil) then
        local entry = member.landed[id];
        return entry, member.since[id], entry ~= nil and ownId ~= 0 and entry.by == ownId;
    end
    local on = serverId ~= nil and debuffs.Statuses(serverId) or nil;
    local entry = on and on[id];
    return entry, nil, entry ~= nil and ownId ~= 0 and entry.by == ownId and now < entry.expires;
end

function statustimes.Landing(serverId, id)
    if (not ownRead) then
        ReadOwn();
    end
    local entry, _, _ = Known(serverId, id);
    if (entry ~= nil and (watched[serverId] ~= nil or now < entry.expires)) then
        return entry;
    end
    return nil;
end

function statustimes.Text(serverId, id, nth)
    if (id == nil or HidesTimer(id)) then
        return nil;
    end
    if (not ownRead) then
        ReadOwn();
    end
    -- the player and the party: what is kept with them; anyone else: what winxi.debuffs saw land
    local entry, since, mine = Known(serverId, id);
    if (serverId ~= nil and serverId ~= 0 and serverId == ownId) then
        local count = ownCount[id] or 0;
        if (count > 0) then
            local seconds = ownTimes[id][math.min(nth or 1, count)];
            if (seconds == false) then
                return nil;
            end
            if (seconds ~= nil) then
                return statustimes.Label(seconds), false, mine, seconds;
            end
        end
        return statustimes.Unknown, true, mine, nil;
    end

    if (entry ~= nil and entry.known ~= false and now < entry.expires) then
        return statustimes.Label(entry.expires - now), true, mine, entry.expires - now;
    end
    if (since) then
        local usual = debuffs.UsualSeconds(id);
        if (usual ~= nil and since + usual > now) then
            return statustimes.Label(since + usual - now), true, mine, since + usual - now;
        end
    end
    return statustimes.Unknown, true, mine, nil;
end

return statustimes;
