addon.name    = 'mark';
addon.author  = 'win (and claude)';
addon.version = '1.8';
addon.desc    = 'Pick a notorious monster, make it your mark, and see how it appears, its placeholders and their respawns, where it spawns on the map, when its window opens and what it drops.';
addon.link    = 'https://github.com/Wincasts/ffxi-addons';

-- A notorious monster looked up, and one of them hunted. The window has two dropdowns, a zone's and a
-- monster's, and under them what the server's own data says of the monster chosen: how it comes to be
-- there, its placeholders, where it and they spawn (as a square of the map and as a point), and each
-- drop with its chance at each level of Treasure Hunter. A second window is the zone's map, with where
-- the monster and its placeholders can spawn laid over it.
--
-- The window has a header, with a button that closes it, and three tabs. Database shows the selected
-- monster above a separate search footer. Marks lists every mark and other monster with a time of death. Stats keeps
-- observed PH/NM kills, hunting durations and source-attributed loot in a per-character database.
--
-- Set As Mark makes the monster a mark, one of as many as are wanted: the Marks tab then says whether
-- it and its placeholders are in range and which way, each placeholder's respawn is timed from when it
-- is seen dead, the chat log says as the mark appears, and time is kept from its death. A time of
-- death can be given by hand for any monster.
--
--   /mark                 shows or hides the window
--   /mark config          opens or closes the settings
--   /mark stats           opens the hunting statistics tab
--   /mark compact         switches between the whole window and the marks' few lines
--   /mark map             shows or hides the map
--   /mark pin             pins or unpins the map (pinning also opens it)
--   /mark set <name>      makes a monster a mark, by its name or a part of it
--   /mark clear           there are no marks any more (/mark clear <name>: that one is a mark no more)
--   /mark tod             the mark (the one of the zone you are in, or the only one; failing that, the
--                         monster on show) died just now
--   /mark tod 15          ... fifteen minutes ago
--   /mark tod 14:35       ... at that time by the computer's clock
--   /mark tod clear       its time of death is forgotten
--   /mark ph 126          the placeholder of that ID died just now (/mark ph 126 2: two minutes ago;
--                         /mark ph 126 clear: it is no longer timed)
--
-- The data is in data/, written by tools/build_mark_data.py from the server's source. hunts.lua reads
-- it and puts it into words, maps.lua knows the maps, and this file draws and watches the game.

require('common');
local bit = require('bit');
local imgui = require('imgui');
local widgets = require('winxi.widgets');
local window = require('winxi.window');
local style = require('winxi.style');
local shell = require('winxi.shell');
local sound = require('winxi.sound');
local game = require('winxi.game');
local settings = require('settings');
local hunts = require('hunts');
local maps = require('maps');
local mapView = require('map_view');
local stats = require('stats');

local TextBaseWidth = imgui.CalcTextSize('A');

local gold = { 1.0, 215 / 255, 0.0, 1.0 };
local green = { 0.55, 1.0, 0.55, 1.0 };
local amber = { 1.0, 0.8, 0.4, 1.0 };
local dim = { 0.6, 0.6, 0.6, 1.0 };

-- Text as it is: imgui.Text and TextWrapped take theirs as a format, and make something else of a
-- percent sign with a letter after it. Wrapped where a wrap has been set.
local hasUnformatted = imgui.TextUnformatted ~= nil;
local function Plain(text)
    if hasUnformatted then
        imgui.TextUnformatted(text);
    else
        imgui.Text(text);
    end
end

local app = nil; -- the shell's: made once the settings' defaults are set out, below
local tracker = nil; -- persistent aggregate database, with session-only observations
local statsRows, statsDetails, chosenStats = nil, nil, nil;

local function Say(text)
    print(('\30\81[mark]\30\01 %s'):format(text));
end

local function ItemName(id)
    local item = AshitaCore:GetResourceManager():GetItemById(id);
    local name = item ~= nil and item.Name ~= nil and item.Name[1] or nil;
    if name == nil or name == '' then
        return ('Item %d'):format(id);
    end
    return name;
end

-- A wait as a clock counts it down: 3:20, 1:04:09
local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds));
    if seconds >= 3600 then
        return ('%d:%02d:%02d'):format(seconds / 3600, seconds % 3600 / 60, seconds % 60);
    end
    return ('%d:%02d'):format(seconds / 60, seconds % 60);
end

----------------------------------------------------------------------------------------------------
-- Times of death: one kept for each monster it is known of, the mark's or any other's, given by hand
-- or taken as the mark is seen dead. Kept in the settings as a list of { zone, name, at }.
----------------------------------------------------------------------------------------------------
local function Tod(options, zone, name)
    for place, tod in ipairs(options.tods) do
        if tod.zone == zone and tod.name == name then
            return tod, place;
        end
    end
    return nil;
end

-- at: when it died (os.time), or nil to forget
local function SetTod(options, zone, name, at, deferSave)
    local tod, place = Tod(options, zone, name);
    if at == nil then
        if place ~= nil then
            table.remove(options.tods, place);
        end
    elseif tod ~= nil then
        tod.at = at;
    else
        options.tods[#options.tods + 1] = T{ zone = zone, name = name, at = at };
    end
    if not deferSave then
        app:Save();
    end
end

-- How a monster's window stands, from when it died: in a sentence, whether it is open, and in the
-- few words the Next Spawn column has room for (nil where nothing follows from its death)
local function Standing(record, at)
    local age = os.time() - at;
    local said = ('Died %s ago.'):format(hunts.Duration(age));
    local lottery = record.lottery;
    if lottery ~= nil and lottery.cooldown ~= nil then
        local wait = (lottery.cooldownMost or lottery.cooldown) - age;
        if wait > 0 then
            return ('%s The lottery opens in %s%s.'):format(said, lottery.cooldownMost and 'at most ' or '', Clock(wait)), false,
                ('Window in %s%s'):format(lottery.cooldownMost and 'at most ' or '', Clock(wait));
        end
        return said .. ' The lottery is open.', true, 'Window open';
    elseif record.respawn ~= nil then
        local least, most = record.respawn[1] - age, record.respawn[2] - age;
        if least > 0 then
            return ('%s Its window opens in %s.'):format(said, Clock(least)), false, ('Window in %s'):format(Clock(least));
        elseif most > 0 then
            return ('%s Its window is open, for %s more.'):format(said, Clock(most)), true, ('Window open, %s more'):format(Clock(most));
        end
        return said .. ' It is due.', true, 'Due';
    end
    return said, false;
end

-- When, from what is typed after /mark tod: nothing is now, a number is that many minutes ago, and
-- hours:minutes is that time by the computer's clock, today's or (were that yet to come) yesterday's
local function ParseWhen(text)
    if text == nil or text == '' then
        return os.time();
    end
    local hours, minutes = text:match('^(%d%d?):(%d%d)$');
    if hours ~= nil then
        local now = os.date('*t');
        now.hour, now.min, now.sec = tonumber(hours), tonumber(minutes), 0;
        if now.hour > 23 or now.min > 59 then
            return nil;
        end
        local at = os.time(now);
        if at > os.time() then
            at = at - 86400;
        end
        return at;
    end
    local ago = tonumber(text);
    if ago ~= nil and ago >= 0 then
        return os.time() - math.floor(ago * 60);
    end
    return nil;
end

----------------------------------------------------------------------------------------------------
-- The marks: kept in the settings as a list of { zone, name }
----------------------------------------------------------------------------------------------------
local function Key(zone, name)
    return ('%d:%s'):format(zone, name);
end

local function IsMark(options, zone, name)
    for place, mark in ipairs(options.marks) do
        if mark.zone == zone and mark.name == name then
            return place;
        end
    end
    return nil;
end

----------------------------------------------------------------------------------------------------
-- The game, looked at four times a second: the zone, where the player is, and whether each monster
-- being watched (the marks and their placeholders, and those of the monster on show) is in range
----------------------------------------------------------------------------------------------------
local live = {
    checked = 0,
    zone = 0,
    x = nil, y = nil, z = nil, -- the player: east-west, height and north-south, as the server's data has them
    floor = nil,               -- the map the player is on, where that can be told
    looked = {},               -- entity indices already read this poll, including those out of range
    watchedPlaceholders = {},  -- placeholder indices already processed this poll
    sights = {},               -- entity index -> { up, text, x, z } for those in range
    status = {},               -- placeholder's entity index -> { text, tone, next }: in range, or how its respawn stands; next is the Next Spawn column's words for it, nil where nothing is known
    deaths = {},               -- placeholder's entity index -> when it was seen dead (os.time)
    counted = {},              -- placeholder's entity index -> true while the corpse seen is one already timed
    spawns = {},               -- placeholder's entity index -> when it was seen to come back (os.time)
    marks = {},                -- a mark's key -> { up, dead }: whether it was up when last looked for, and whether its corpse has been counted
    nearest = nil,             -- how far the monster on show's nearest spawn point is, in words
    viewTimer = nil,           -- how the monster on show's window stands, in words
    timers = {},               -- and every one kept: a line to each of options.tods
    timerOf = {},              -- the same, by the monster's key
    rows = {},                 -- the Marks tab's list: every mark, then every other monster a time of death is kept for
};

local watching = nil; -- the settings, for what is said as the game is looked at
local placeholderSaveNeeded = false;

-- Observations belong to a session and a character. Only saved death times survive a reset.
local function ResetLive()
    if tracker then tracker:Reset(); end
    live.checked, live.zone = 0, 0;
    live.x, live.y, live.z, live.floor = nil, nil, nil, nil;
    live.sights, live.looked, live.watchedPlaceholders = {}, {}, {};
    live.deaths, live.counted, live.status, live.spawns, live.marks = {}, {}, {}, {}, {};
    live.nearest, live.viewTimer = nil, nil;
    live.timers, live.timerOf, live.rows = {}, {}, {};
    watching, placeholderSaveNeeded = nil, false;
end

local function RestorePlaceholders(options, zone)
    live.deaths, live.counted, live.status, live.spawns = {}, {}, {}, {};
    for _, tod in ipairs(options.phTods) do
        if tod.zone == zone then
            live.deaths[tod.index] = tod.at;
            -- Seeing the same corpse after a reload must not move its death time to now.
            live.counted[tod.index] = true;
        end
    end
end

-- Entity indices are zone-local. Persist transitions, not countdown ticks; a poll saves once.
local function SetPlaceholderTod(options, index, at, deferSave)
    local found, place = nil, nil;
    for each, tod in ipairs(options.phTods) do
        if tod.zone == live.zone and tod.index == index then
            found, place = tod, each;
            break;
        end
    end
    local changed = false;
    if at == nil then
        if place ~= nil then
            table.remove(options.phTods, place);
            changed = true;
        end
    elseif found ~= nil then
        changed = found.at ~= at;
        found.at = at;
    else
        options.phTods[#options.phTods + 1] = T{ zone = live.zone, index = index, at = at };
        changed = true;
    end
    live.deaths[index], live.spawns[index] = at, nil;
    if at ~= nil then
        live.counted[index] = true;
    end
    if changed then
        if deferSave then
            placeholderSaveNeeded = true;
        else
            app:Save();
        end
    end
end

local SPAWNED = 0x200; -- the render flag of an entity the client is showing

-- An entity in range: how far and which way, and whether it lives
local function Look(entities, index)
    if live.looked[index] then
        return live.sights[index];
    end
    live.looked[index] = true;
    if bit.band(entities:GetRenderFlags0(index), SPAWNED) == 0 then
        return nil;
    end
    local distance = math.sqrt(entities:GetDistance(index));
    local up = entities:GetHPPercent(index) > 0;
    -- the game's own names for the two level directions are X and Y; the server's are x and z
    local x, z = entities:GetLocalPositionX(index), entities:GetLocalPositionY(index);
    local way = '';
    if live.x ~= nil then
        way = ' ' .. hunts.Compass(x - live.x, z - live.z);
    end
    local where = ('%d yalms%s'):format(math.floor(distance + 0.5), way);
    local sight = { up = up, x = x, z = z, where = where, text = ('%s, %s'):format(up and 'Up' or 'Dead', where) };
    live.sights[index] = sight;
    return sight;
end

-- A placeholder: in range or not, its respawn timed from when it died (seen dead, or said to have
-- died), and how long it has been up since it was seen to come back
local function WatchPlaceholder(entities, placeholder)
    local index = placeholder.index;
    if live.watchedPlaceholders[index] then
        return;
    end
    live.watchedPlaceholders[index] = true;
    local sight = Look(entities, index);
    local status = live.status[index] or {};
    live.status[index] = status;
    if sight ~= nil and not sight.up then
        if not live.counted[index] then
            live.counted[index] = true;
            SetPlaceholderTod(watching, index, os.time(), true);
        end
        live.spawns[index] = nil;
    else
        live.counted[index] = nil;
        if sight ~= nil and live.deaths[index] ~= nil then
            -- up again: its spawn is timed from now
            SetPlaceholderTod(watching, index, nil, true);
            live.spawns[index] = os.time();
            if watching ~= nil and watching.announcePlaceholders[1] then
                Say(('%s (%03X) has respawned, %s.'):format(placeholder.name, index, sight.where));
            end
        end
    end

    local died = live.deaths[index];
    local told = status.told;
    status.told = nil;
    if sight ~= nil and sight.up then
        local spawned = live.spawns[index];
        status.text = spawned and ('%s, for %s'):format(sight.text, Clock(os.time() - spawned)) or sight.text;
        status.tone, status.next = 'up', status.text;
    elseif died == nil then
        status.text, status.tone, status.next = 'Not In Range', nil, nil;
    elseif placeholder.respawn == nil then
        status.text, status.tone, status.next = ('Died %s ago'):format(Clock(os.time() - died)), 'wait', nil;
    else
        local wait = placeholder.respawn - (os.time() - died);
        if wait > 0 then
            status.text, status.tone, status.next = ('Respawns in %s'):format(Clock(wait)), 'wait', ('In %s'):format(Clock(wait));
        elseif wait > -1800 then
            status.text, status.tone = ('Due %s ago'):format(Clock(-wait)), 'due';
            status.next = status.text;
            -- said once, as it falls due
            status.told = true;
            if not told and watching ~= nil and watching.announcePlaceholders[1] then
                Say(('%s (%03X) is due to respawn.'):format(placeholder.name, index));
            end
        else
            -- long past: it has come and gone unseen
            SetPlaceholderTod(watching, index, nil, true);
            status.text, status.tone, status.next = 'Not In Range', nil, nil;
        end
    end
end

local function Watch(entities, record)
    local up, dead = false, false;
    for _, index in ipairs(record.indices) do
        local sight = Look(entities, index);
        if sight ~= nil then
            up = up or sight.up;
            dead = dead or not sight.up;
        end
    end
    for _, placeholder in ipairs(record.placeholders or {}) do
        WatchPlaceholder(entities, placeholder);
    end
    return up, dead;
end

-- How far the nearest of a monster's spawn points (or the middle of its regions) is, and which way
local function Nearest(record)
    if live.x == nil then
        return nil;
    end
    local best, east, north = nil, 0, 0;
    local function Try(point)
        local dx, dz = point[1] - live.x, point[3] - live.z;
        local distance = math.sqrt(dx * dx + dz * dz);
        if best == nil or distance < best then
            best, east, north = distance, dx, dz;
        end
    end
    for _, point in ipairs(record.points or {}) do
        Try(point);
    end
    for _, area in ipairs(record.areas or {}) do
        Try(area.at);
    end
    if best == nil then
        return nil;
    end
    return ('Nearest is %d yalms %s of you.'):format(math.floor(best + 0.5), hunts.Compass(east, north));
end

local function AddMark(options, zone, name)
    if IsMark(options, zone, name) == nil then
        options.marks[#options.marks + 1] = T{ zone = zone, name = name };
    end
    live.marks[Key(zone, name)] = nil;
    live.checked = 0;
    app:Save();
end

local function RemoveMark(options, zone, name)
    local place = IsMark(options, zone, name);
    if place ~= nil then
        table.remove(options.marks, place);
    end
    live.marks[Key(zone, name)] = nil;
    live.checked = 0;
    app:Save();
end

-- A line of the Marks tab's list: what does not change is put into words once
local function Row(place, zone, name, isMark)
    local row = live.rows[place] or {};
    live.rows[place] = row;
    if row.zone ~= zone or row.name ~= name then
        row.zone, row.name, row.zoneName = zone, name, hunts.ZoneName(zone);
        row.record = hunts.Monster(zone, name);
        row.placeholders = {};
        for each, placeholder in ipairs(row.record and row.record.placeholders or {}) do
            row.placeholders[each] = { index = placeholder.index, label = ('   %s (%03X)'):format(placeholder.name, placeholder.index) };
        end
    end
    row.mark, row.here, row.timer, row.index = isMark, zone == live.zone, live.timerOf[Key(zone, name)], nil;
    -- whichever of its spawns is in range, one that is up before one that is dead
    for _, index in ipairs(row.here and row.record and row.record.indices or {}) do
        local sight = live.sights[index];
        if sight ~= nil and (row.index == nil or sight.up) then
            row.index = index;
        end
    end
end

local function StatsTargets(options, zone)
    local targets, seen = {}, {};
    local function Add(z, name)
        if z == zone and name ~= '' and not seen[name] then
            seen[name] = true;
            local record = hunts.Monster(z, name);
            if record then targets[#targets + 1] = { zone = z, name = name, record = record }; end
        end
    end
    Add(options.viewZone, options.viewName);
    for _, mark in ipairs(options.marks) do Add(mark.zone, mark.name); end
    return targets;
end

local function Update(options)
    -- The client can retain the last character's entities on the login screen. Do not time them.
    if not settings.logged_in or game.IsLoading() then
        if live.zone ~= 0 then
            ResetLive();
        end
        return;
    end
    local now = os.clock();
    if now - live.checked < 0.25 then
        return;
    end
    live.checked = now;
    watching = options;
    placeholderSaveNeeded = false;

    local memory = AshitaCore:GetMemoryManager();
    local party = memory:GetParty();
    local entities = memory:GetEntity();
    local zone = party:GetMemberZone(0);
    if zone ~= live.zone then
        -- Restore only this zone's saved times; identical indices in other zones are unrelated.
        RestorePlaceholders(options, zone);
    end
    live.zone = zone;
    local me = party:GetMemberTargetIndex(0);
    if me ~= 0 then
        live.x, live.y, live.z = entities:GetLocalPositionX(me), entities:GetLocalPositionZ(me), entities:GetLocalPositionY(me);
        live.floor = maps.FloorAt(zone, zone, live.x, live.y, live.z);
    else
        live.x, live.y, live.z, live.floor = nil, nil, nil, nil;
    end
    for index in pairs(live.sights) do
        live.sights[index] = nil;
    end

    for index in pairs(live.looked) do
        live.looked[index] = nil;
    end
    for index in pairs(live.watchedPlaceholders) do
        live.watchedPlaceholders[index] = nil;
    end
    local marked = {}; -- membership for the rows: no scan of every mark for every time of death
    local saveNeeded = false;
    local shown = options.viewName ~= '' and hunts.Monster(options.viewZone, options.viewName) or nil;
    live.nearest = nil;
    if shown ~= nil and live.zone == options.viewZone then
        Watch(entities, shown);
        live.nearest = Nearest(shown);
    end

    for _, mark in ipairs(options.marks) do
        local key = Key(mark.zone, mark.name);
        marked[key] = true;
        local state = live.marks[key] or { up = false, dead = false };
        live.marks[key] = state;
        local record = hunts.Monster(mark.zone, mark.name);
        if record == nil or live.zone ~= mark.zone then
            state.up, state.dead = false, false;
        else
            local up, dead = Watch(entities, record);
            if up and not state.up then
                -- it is back: what was known of its last death is of no more use
                if Tod(options, mark.zone, mark.name) ~= nil then
                    SetTod(options, mark.zone, mark.name, nil, true);
                    saveNeeded = true;
                end
                if options.announce[1] then
                    local sight = nil;
                    for _, index in ipairs(record.indices) do
                        if live.sights[index] ~= nil and live.sights[index].up then
                            sight = live.sights[index];
                        end
                    end
                    Say(('%s: %s.'):format(mark.name, sight.text));
                end
                sound.SetEnabled(options.sound[1]);
                sound.Play('open');
            end
            if dead and not up and not state.dead then
                SetTod(options, mark.zone, mark.name, os.time(), true);
                saveNeeded = true;
                if options.announce[1] then
                    Say(('%s is dead. The time is kept from now.'):format(mark.name));
                end
            end
            state.up, state.dead = up, dead and not up;
        end
    end

    tracker:Watch(zone, StatsTargets(options, zone));
    tracker:Observe(live.sights, os.time());
    if saveNeeded or placeholderSaveNeeded or tracker.changed then
        if tracker.changed then statsRows, statsDetails = nil, nil; end
        tracker.changed = false;
        app:Save();
    end

    -- how each window stands
    live.viewTimer = nil;
    for key in pairs(live.timerOf) do
        live.timerOf[key] = nil;
    end
    for place, tod in ipairs(options.tods) do
        local record = hunts.Monster(tod.zone, tod.name);
        local timer = live.timers[place] or {};
        live.timers[place] = timer;
        timer.text, timer.open, timer.short = '', false, nil;
        if record ~= nil then
            timer.text, timer.open, timer.short = Standing(record, tod.at);
        end
        live.timerOf[Key(tod.zone, tod.name)] = timer;
        if tod.zone == options.viewZone and tod.name == options.viewName then
            live.viewTimer = timer;
        end
    end
    for place = #options.tods + 1, #live.timers do
        live.timers[place] = nil;
    end

    -- the Marks tab's list
    local count = 0;
    for _, mark in ipairs(options.marks) do
        count = count + 1;
        Row(count, mark.zone, mark.name, true);
    end
    for _, tod in ipairs(options.tods) do
        if not marked[Key(tod.zone, tod.name)] then
            count = count + 1;
            Row(count, tod.zone, tod.name, false);
        end
    end
    for place = count + 1, #live.rows do
        live.rows[place] = nil;
    end
end

----------------------------------------------------------------------------------------------------
-- The monster on show: its record put into words once, when it is chosen
----------------------------------------------------------------------------------------------------
local view = { zone = nil, name = nil, th = nil, here = nil, record = nil, missing = false, built = 0 };

local function Names(ids)
    local names = {};
    for place, id in ipairs(ids) do
        names[place] = ItemName(id);
    end
    return table.concat(names, ', ');
end

-- The square of the map's grid a point of the zone on show is in, or nil where it cannot be told: no
-- map, a zone of several maps the player is not in, or a scale the game has not given up yet
local function Square(point)
    local floor = maps.FloorAt(view.zone, live.zone, point[1], point[2], point[3]);
    if floor == nil then
        return nil;
    end
    local entry = maps.Entry(view.zone, floor);
    if entry == nil then
        view.missing = true; -- to be tried again
        return nil;
    end
    return maps.Square(maps.ToMap(entry, point[1], point[3]));
end

local function Routes(lines, routes)
    for _, route in ipairs(routes or {}) do
        local first, last = route.points[1], route.points[#route.points];
        local from, to = Square(first), Square(last);
        lines[#lines + 1] = ('%s %d points from %s%s to %s%s'):format(route.loop and 'Circles' or 'Walks', #route.points,
            from and (from .. ' ') or '', hunts.Point(first), to and (to .. ' ') or '', hunts.Point(last));
    end
end

local function BuildView(options)
    local th = math.max(0, math.min(hunts.MaxTreasureHunter, options.maxTh[1]));
    local here = live.zone == options.viewZone;
    if view.zone == options.viewZone and view.name == options.viewName and view.th == th and view.here == here
        and not (view.missing and os.clock() - view.built > 5) then
        return;
    end
    view.zone, view.name, view.th, view.here = options.viewZone, options.viewName, th, here;
    view.missing, view.built = false, os.clock();
    local record = options.viewName ~= '' and hunts.Monster(options.viewZone, options.viewName) or nil;
    view.record = record;
    if record == nil then
        return;
    end

    view.appears = hunts.Appears(record, ItemName);
    view.places = hunts.Places(record.points, record.areas, Square);
    Routes(view.places, record.routes);

    view.placeholders = {};
    for place, placeholder in ipairs(record.placeholders or {}) do
        view.placeholders[place] = {
            index = placeholder.index,
            name = placeholder.name,
            id = ('%03X'):format(placeholder.index),
            respawn = placeholder.respawn and hunts.Duration(placeholder.respawn) or '',
            where = hunts.Spot(placeholder.points, placeholder.areas, Square),
            walks = placeholder.routes ~= nil,
            mapId = ('Map##mark.phMap%d'):format(place),
            todId = ('TOD##mark.phTod%d'):format(place),
            clearId = ('x##mark.phClear%d'):format(place),
            place = place,
        };
    end

    -- each drop's chance at each level of Treasure Hunter shown, worked out here and not as it is drawn
    view.headings = {};
    for level = 0, th do
        view.headings[level + 1] = level == 0 and 'No TH' or ('TH%d'):format(level);
    end
    view.drops = hunts.Drops(record, ItemName);
    for _, row in ipairs(view.drops) do
        row.label = (row.indent and '   ' or '') .. row.name .. (row.count ~= nil and row.count > 1 and (' x%d'):format(row.count) or '');
        row.cells = {};
        for level = 0, th do
            row.cells[level + 1] = hunts.Percent(hunts.Chance(level, row.rate) * row.share / 10000);
        end
    end
    view.steal = record.steal and Names(record.steal) or nil;
    view.despoil = record.despoil and Names(record.despoil) or nil;
    view.stealLine = view.steal and ('Steal: ' .. view.steal) or nil;
    view.despoilLine = view.despoil and ('Despoil: ' .. view.despoil) or nil;
end

local function Show(options, zone, name)
    options.viewZone, options.viewName = zone, name or '';
    live.checked = 0; -- looked at again at once
end

----------------------------------------------------------------------------------------------------
-- The map: the zone's picture with where the monster on show and its placeholders can spawn laid
-- over it. A region is filled, a spawn point is a spot, and each is so thin that where several lie
-- over one another the colour deepens: the more that can spawn in a place, the hotter it shows.
----------------------------------------------------------------------------------------------------
local heat = {
    monster = imgui.GetColorU32({ 1.0, 0.25, 0.15, 0.30 }),
    monsterSpot = imgui.GetColorU32({ 1.0, 0.3, 0.2, 0.45 }),
    placeholder = imgui.GetColorU32({ 0.2, 0.6, 1.0, 0.22 }),
    placeholderSpot = imgui.GetColorU32({ 0.3, 0.7, 1.0, 0.40 }),
    route = imgui.GetColorU32({ 1.0, 0.9, 0.3, 0.9 }),
    edge = imgui.GetColorU32({ 0.0, 0.0, 0.0, 0.9 }),
    player = imgui.GetColorU32({ 1.0, 1.0, 1.0, 1.0 }),
    up = imgui.GetColorU32({ 0.4, 1.0, 0.4, 1.0 }),
    dead = imgui.GetColorU32({ 0.6, 0.6, 0.6, 1.0 }),
    blank = imgui.GetColorU32({ 0.08, 0.08, 0.1, 0.9 }),
    white = imgui.GetColorU32({ 1.0, 1.0, 1.0, 1.0 }),
};
local monsterLegend, placeholderLegend = { 1.0, 0.45, 0.35, 1.0 }, { 0.45, 0.75, 1.0, 1.0 };

-- zone, name, floor, size and here are what the shapes were made for; choice is the floor chosen by
-- hand, which lasts until another monster is shown
local chart = { zone = nil, name = nil, floor = nil, size = nil, here = nil, entry = nil, choice = nil,
    rects = {}, spots = {}, lines = {}, labels = {} };
local mapState = mapView.New();
local mapPlaced, mapMoved = false, false;

-- A region's outline, filled a few pixels at a time: the stretches of each row that lie inside it
local function Fill(entry, scale, poly, color)
    local xs, ys, count = {}, {}, #poly / 2;
    local top, bottom = math.huge, -math.huge;
    for place = 1, count do
        local px, py = maps.ToMap(entry, poly[place * 2 - 1], poly[place * 2]);
        xs[place], ys[place] = px * scale, py * scale;
        top, bottom = math.min(top, ys[place]), math.max(bottom, ys[place]);
    end
    local step = 3;
    local crossings = {};
    for row = math.floor(top), math.ceil(bottom), step do
        local y = row + step / 2;
        local found = 0;
        for place = 1, count do
            local nextPlace = place % count + 1;
            local y1, y2 = ys[place], ys[nextPlace];
            if (y1 <= y and y2 > y) or (y2 <= y and y1 > y) then
                found = found + 1;
                crossings[found] = xs[place] + (y - y1) / (y2 - y1) * (xs[nextPlace] - xs[place]);
            end
        end
        for place = found + 1, #crossings do
            crossings[place] = nil;
        end
        table.sort(crossings);
        for place = 1, found - 1, 2 do
            chart.rects[#chart.rects + 1] = { crossings[place], row, crossings[place + 1], row + step, color };
        end
    end
end

-- Whether a place is to be drawn on the map chosen: it is unless it is known to be on another
local function OnFloor(point, floor, floors)
    if #floors == 1 or not chart.here then
        return true;
    end
    local found = maps.FloorAt(chart.zone, live.zone, point[1], point[2], point[3]);
    return found == nil or found == floor;
end

local function Chart(record, floor, floors, entry, size)
    chart.rects, chart.spots, chart.lines = {}, {}, {};
    local scale = size / maps.Size;
    local function Lay(points, areas, routes, fill, spot)
        for _, area in ipairs(areas or {}) do
            if OnFloor(area.at, floor, floors) then
                Fill(entry, scale, area.poly, fill);
            end
        end
        for _, point in ipairs(points or {}) do
            if OnFloor(point, floor, floors) then
                local px, py = maps.ToMap(entry, point[1], point[3]);
                chart.spots[#chart.spots + 1] = { px * scale, py * scale, spot };
            end
        end
        for _, route in ipairs(routes or {}) do
            for place = 1, #route.points - (route.loop and 0 or 1) do
                local a, b = route.points[place], route.points[place % #route.points + 1];
                if OnFloor(a, floor, floors) then
                    local ax, ay = maps.ToMap(entry, a[1], a[3]);
                    local bx, by = maps.ToMap(entry, b[1], b[3]);
                    chart.lines[#chart.lines + 1] = { ax * scale, ay * scale, bx * scale, by * scale };
                end
            end
        end
    end
    -- the placeholders under, the monster's own over them
    for place, placeholder in ipairs(record.placeholders or {}) do
        if chart.focus == nil or chart.focus == place then
            Lay(placeholder.points, placeholder.areas, placeholder.routes, heat.placeholder, heat.placeholderSpot);
        end
    end
    Lay(record.points, record.areas, record.routes, heat.monster, heat.monsterSpot);
end

-- The map of the zone's that most of the monster's places are on, where that can be told
local function BestFloor(record, floors)
    if #floors == 1 or live.zone ~= view.zone then
        return floors[1];
    end
    local counts, best = {}, floors[1];
    local function Count(point)
        local floor = maps.FloorAt(view.zone, live.zone, point[1], point[2], point[3]);
        if floor ~= nil then
            counts[floor] = (counts[floor] or 0) + 1;
            if counts[floor] > (counts[best] or 0) then
                best = floor;
            end
        end
    end
    for _, point in ipairs(record.points or {}) do Count(point); end
    for _, area in ipairs(record.areas or {}) do Count(area.at); end
    for _, placeholder in ipairs(record.placeholders or {}) do
        for _, point in ipairs(placeholder.points or {}) do Count(point); end
        for _, area in ipairs(placeholder.areas or {}) do Count(area.at); end
    end
    return best;
end

local cornerA, cornerB, uvA, uvB = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 1, 1 };
local canvas = { 0, 0 };

local function Spot(drawList, x, y, color, radius)
    cornerA[1], cornerA[2] = x, y;
    drawList:AddCircleFilled(cornerA, radius, color, 16);
end

local function DrawMap(options)
    if imgui.Checkbox('Pin Map##mark.mapPin', options.pinMap) then
        app:Save();
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Keeps this map open when Mark\'s main window is closed. Drag outside the map canvas to move the window.');
    end
    imgui.SameLine();
    if imgui.Button('x##mark.mapClose') then
        options.showMap[1] = false;
        app:Save();
    end
    local record = view.record;
    if record == nil then
        imgui.TextDisabled('Choose a notorious monster to see its map.');
        return;
    end
    imgui.TextColored(widgets.HeaderColor, view.name);
    imgui.SameLine();
    imgui.TextDisabled(hunts.ZoneName(view.zone));

    local floors = maps.Floors(view.zone);
    if floors == nil then
        imgui.Text('There is no map of this zone.');
        return;
    end
    if chart.zone ~= view.zone or chart.name ~= view.name then
        chart.choice, chart.focus = nil, nil;
    end
    local focused = chart.focus and record.placeholders and record.placeholders[chart.focus] or nil;
    if focused ~= nil then
        imgui.TextColored(placeholderLegend, ('%s (%03X)'):format(focused.name, focused.index));
        imgui.SameLine();
        if imgui.SmallButton('Show All##mark.mapAll') then
            chart.focus = nil;
        end
    end
    -- asked of the client once for each monster shown, not every frame
    if chart.best == nil or chart.bestZone ~= view.zone or chart.bestName ~= view.name or chart.bestHere ~= view.here then
        chart.best, chart.bestZone, chart.bestName, chart.bestHere = BestFloor(record, floors), view.zone, view.name, view.here;
    end
    local floor = chart.choice or chart.best;
    if #floors > 1 then
        for place, each in ipairs(floors) do
            chart.labels[place] = chart.labels[place] or ('Map %d##mark.floor%d'):format(place, place);
            if place > 1 then
                imgui.SameLine();
            end
            if imgui.RadioButton(chart.labels[place], each == floor) then
                chart.choice, floor = each, each;
            end
        end
        if not view.here then
            imgui.PushTextWrapPos(imgui.GetCursorPosX() + options.mapSize[1]);
            imgui.TextWrapped('This zone has several maps, and which one a place is on can be told only in the zone: until then everything is drawn on the map chosen, and what belongs to another will look out of place.');
            imgui.PopTextWrapPos();
        end
    end

    local entry = maps.Entry(view.zone, floor);
    if entry == nil then
        imgui.Text('The map\'s scale could not be read from the game.');
        return;
    end
    if mapState.zone ~= view.zone or mapState.name ~= view.name or mapState.floor ~= floor then
        mapView.Reset(mapState);
        mapState.zone, mapState.name, mapState.floor = view.zone, view.name, floor;
    end
    if imgui.SmallButton('-##mark.mapZoomOut') then
        mapView.Zoom(mapState, mapState.zoom / 1.25, 256, 256);
    end
    imgui.SameLine();
    Plain(('%.1fx'):format(mapState.zoom));
    imgui.SameLine();
    if imgui.SmallButton('+##mark.mapZoomIn') then
        mapView.Zoom(mapState, mapState.zoom * 1.25, 256, 256);
    end
    imgui.SameLine();
    if imgui.SmallButton('Reset View##mark.mapReset') then
        mapView.Reset(mapState);
    end
    imgui.TextDisabled('Drag to pan; mouse wheel to zoom.');

    local size = math.max(256, math.min(1024, options.mapSize[1]));
    if chart.zone ~= view.zone or chart.name ~= view.name or chart.floor ~= floor or chart.size ~= size or chart.here ~= view.here
        or chart.laid ~= (chart.focus or 0) then
        chart.zone, chart.name, chart.floor, chart.size, chart.here, chart.entry = view.zone, view.name, floor, size, view.here, entry;
        chart.laid = chart.focus or 0;
        Chart(record, floor, floors, entry, size);
    end

    local left, top = imgui.GetCursorScreenPos();
    canvas[1], canvas[2] = size, size;
    imgui.InvisibleButton('##mark.mapCanvas', canvas);
    local hovered, active = imgui.IsItemHovered(), imgui.IsItemActive();
    local mouseX, mouseY = imgui.GetMousePos();
    local baseScale = size / maps.Size;
    if hovered and mouseX ~= nil and mouseY ~= nil then
        local wheel = imgui.GetIO().MouseWheel or 0;
        if wheel ~= 0 then
            mapView.Zoom(mapState, mapState.zoom * 1.25 ^ wheel, (mouseX - left) / baseScale, (mouseY - top) / baseScale);
        end
    end
    if active and imgui.IsMouseDown(0) and mouseX ~= nil and mouseY ~= nil then
        if mapState.mouseX ~= nil then
            mapView.Pan(mapState, (mouseX - mapState.mouseX) / baseScale, (mouseY - mapState.mouseY) / baseScale);
        end
        mapState.mouseX, mapState.mouseY = mouseX, mouseY;
    else
        mapState.mouseX, mapState.mouseY = nil, nil;
    end
    local originX, originY = left + mapState.x * baseScale, top + mapState.y * baseScale;
    local zoom = mapState.zoom;
    local drawList = imgui.GetWindowDrawList();
    cornerA[1], cornerA[2], cornerB[1], cornerB[2] = left, top, left + size, top + size;
    drawList:PushClipRect(cornerA, cornerB, true);
    local extent = size * zoom;
    cornerA[1], cornerA[2], cornerB[1], cornerB[2] = originX, originY, originX + extent, originY + extent;
    local picture = maps.Texture(floor);
    if picture ~= nil then
        drawList:AddImage(picture, cornerA, cornerB, uvA, uvB, heat.white);
    else
        drawList:AddRectFilled(cornerA, cornerB, heat.blank, 0);
    end

    for _, rect in ipairs(chart.rects) do
        cornerA[1], cornerA[2], cornerB[1], cornerB[2] = originX + rect[1] * zoom, originY + rect[2] * zoom,
            originX + rect[3] * zoom, originY + rect[4] * zoom;
        drawList:AddRectFilled(cornerA, cornerB, rect[5], 0);
    end
    for _, line in ipairs(chart.lines) do
        cornerA[1], cornerA[2], cornerB[1], cornerB[2] = originX + line[1] * zoom, originY + line[2] * zoom,
            originX + line[3] * zoom, originY + line[4] * zoom;
        drawList:AddLine(cornerA, cornerB, heat.route, 2);
    end
    -- a spot is hottest at its middle
    for _, spot in ipairs(chart.spots) do
        local x, y = originX + spot[1] * zoom, originY + spot[2] * zoom;
        Spot(drawList, x, y, spot[3], 9);
        Spot(drawList, x, y, spot[3], 5);
        Spot(drawList, x, y, spot[3], 2.5);
    end

    -- what is there now: those in range, and the player
    local scale = baseScale * zoom;
    if view.here then
        for _, sight in pairs(live.sights) do
            local px, py = maps.ToMap(entry, sight.x, sight.z);
            Spot(drawList, originX + px * scale, originY + py * scale, heat.edge, 5);
            Spot(drawList, originX + px * scale, originY + py * scale, sight.up and heat.up or heat.dead, 3.5);
        end
        if live.x ~= nil and (#floors == 1 or live.floor == nil or live.floor == floor) then
            local px, py = maps.ToMap(entry, live.x, live.z);
            Spot(drawList, originX + px * scale, originY + py * scale, heat.edge, 5);
            Spot(drawList, originX + px * scale, originY + py * scale, heat.player, 3.5);
        end
    end

    drawList:PopClipRect();

    if hovered then
        if mouseX ~= nil and mouseY ~= nil then
            local px, py = (mouseX - originX) / scale, (mouseY - originY) / scale;
            local x, z = maps.ToWorld(entry, px, py);
            imgui.SetTooltip(('%s (%d, %d)'):format(maps.Square(px, py), x, z));
        end
    end

    if picture == nil then
        imgui.TextDisabled('The map\'s picture was not found: install Mark\'s assets\\maps, or Zoneinfo\'s assets\\maps\\all fallback.');
    end
    imgui.TextColored(monsterLegend, 'Monster');
    imgui.SameLine();
    imgui.TextColored(placeholderLegend, 'Placeholders');
    if view.here then
        imgui.SameLine();
        imgui.TextColored(green, 'In Range');
        imgui.SameLine();
        imgui.Text('You');
    end
end

----------------------------------------------------------------------------------------------------
-- The window
----------------------------------------------------------------------------------------------------
local find = { '' };      -- what is typed to look a monster up by name, in any zone
local minutesAgo = { 0 }; -- how long ago the death being reported was

local function Sight(index)
    local sight = live.sights[index];
    if sight == nil then
        imgui.TextDisabled('Not In Range');
    elseif sight.up then
        imgui.TextColored(green, sight.text);
    else
        imgui.TextDisabled(sight.text);
    end
end

-- A placeholder: in range, or how its respawn stands
local function Status(index)
    local status = live.status[index];
    if status == nil or status.tone == nil then
        imgui.TextDisabled('Not In Range');
    elseif status.tone == 'up' then
        imgui.TextColored(green, status.text);
    elseif status.tone == 'due' then
        imgui.TextColored(gold, status.text);
    else
        imgui.TextColored(amber, status.text);
    end
end

-- A placeholder's next spawn: the time to it where its death was seen or told, that it is up, or that
-- nothing is known. Only of the zone the player is in is anything known.
local function NextSpawn(index, here)
    local status = here and live.status[index] or nil;
    if status == nil or status.next == nil then
        imgui.TextDisabled('Unknown');
    elseif status.tone == 'up' then
        imgui.TextColored(green, status.next);
    else
        imgui.TextColored(status.tone == 'due' and gold or amber, status.next);
    end
end

local function Timer(timer)
    if timer.open then
        imgui.TextColored(green, timer.text);
    else
        Plain(timer.text);
    end
end

-- A monster of the list's next spawn: that it is up and where, the time to its window where its death
-- is known, or that nothing is known
local function Presence(row)
    local sight = row.here and live.sights[row.index or 0] or nil;
    local timer = row.timer;
    if sight ~= nil and sight.up then
        imgui.TextColored(green, sight.text);
    elseif timer ~= nil and timer.short ~= nil then
        if timer.open then
            imgui.TextColored(green, timer.short);
        else
            imgui.TextColored(amber, timer.short);
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip(timer.text);
        end
    else
        imgui.TextDisabled('Unknown');
    end
end

-- The marks, where each is and what is known of its return: what the compact window is made of
local function DrawCompact()
    local drawn = false;
    for _, row in ipairs(live.rows) do
        if row.mark then
            imgui.TextColored(gold, row.name);
            imgui.SameLine();
            if row.here then
                Sight(row.index);
            else
                imgui.TextDisabled(row.zoneName);
            end
            if row.timer ~= nil then
                Timer(row.timer);
            end
            for _, placeholder in ipairs(row.here and row.placeholders or {}) do
                imgui.Text(placeholder.label);
                imgui.SameLine();
                Status(placeholder.index);
            end
            drawn = true;
        end
    end
    return drawn;
end

local wantTab = nil; -- a tab to be turned to: 1 for Database

-- The Marks tab: every mark, and every other monster a time of death is kept for
local function DrawMarks(options)
    if #live.rows == 0 then
        imgui.TextDisabled('No marks, and no times of death.');
        imgui.TextDisabled('Set As Mark or Report TOD, on the Database tab, puts a monster here.');
        return;
    end
    if not imgui.BeginTable('mark.marks', 4, ImGuiTableFlags_SizingFixedFit) then
        return;
    end
    imgui.TableSetupColumn('Monster', ImGuiTableColumnFlags_WidthFixed);
    imgui.TableSetupColumn('Zone', ImGuiTableColumnFlags_WidthFixed);
    imgui.TableSetupColumn('Next Spawn', ImGuiTableColumnFlags_WidthFixed);
    imgui.TableSetupColumn('##mark.marksButtons', ImGuiTableColumnFlags_WidthFixed);
    imgui.TableHeadersRow();
    for place, row in ipairs(live.rows) do
        imgui.PushID(place);
        imgui.TableNextRow();
        imgui.TableNextColumn();
        imgui.AlignTextToFramePadding();
        imgui.TextColored(row.mark and gold or widgets.HeaderColor, row.name);
        if not row.mark and imgui.IsItemHovered() then
            imgui.SetTooltip('Not a mark: here for its time of death.');
        end
        imgui.TableNextColumn();
        imgui.Text(row.zoneName);
        imgui.TableNextColumn();
        Presence(row);
        imgui.TableNextColumn();
        if imgui.SmallButton('Database') then
            Show(options, row.zone, row.name);
            wantTab = 1;
        end
        imgui.SameLine();
        if imgui.SmallButton('TOD') then
            SetTod(options, row.zone, row.name, os.time());
            live.checked = 0;
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('It died just now: its window is counted from here. For a death some time ago, Report TOD on the Database tab, or /mark tod.');
        end
        if row.timer ~= nil then
            imgui.SameLine();
            if imgui.SmallButton('Clear TOD') then
                SetTod(options, row.zone, row.name, nil);
                live.checked = 0;
            end
        end
        imgui.SameLine();
        if row.mark then
            if imgui.SmallButton('Clear Mark') then
                RemoveMark(options, row.zone, row.name);
            end
        elseif imgui.SmallButton('Set As Mark') then
            AddMark(options, row.zone, row.name);
        end
        -- a mark of the zone the player is in: its placeholders under it
        for _, placeholder in ipairs(row.mark and row.here and row.placeholders or {}) do
            imgui.TableNextRow();
            imgui.TableNextColumn();
            imgui.TextDisabled(placeholder.label);
            imgui.TableNextColumn();
            imgui.TableNextColumn();
            NextSpawn(placeholder.index, true);
        end
        imgui.PopID();
    end
    imgui.EndTable();
end

local function DrawStats(options)
    imgui.TextDisabled('Observed kills, not party/claim credit. Manual TOD entries do not count as kills.');
    imgui.TextDisabled('Pop times: first PH kill to next NM sighting, without logout, zoning or stopping tracking.');
    if statsRows == nil then
        statsRows = {};
        for key, row in pairs(options.hunting.monsters) do
            statsRows[#statsRows + 1] = { key = key, data = row, zoneName = hunts.ZoneName(row.zone) };
        end
        table.sort(statsRows, function(a, b)
            if a.zoneName ~= b.zoneName then return a.zoneName < b.zoneName; end
            return a.data.name < b.data.name;
        end);
    end
    if #statsRows == 0 then
        imgui.TextDisabled('No hunting observations yet. Watch a mark or a monster on Database.');
        return;
    end
    if chosenStats == nil then
        local lookup = Key(options.viewZone, options.viewName);
        chosenStats = options.hunting.monsters[lookup] and lookup or statsRows[1].key;
    end
    if imgui.BeginTable('mark.stats', 8, ImGuiTableFlags_SizingFixedFit) then
        for _, name in ipairs({ 'Monster', 'Zone', 'PH Kills', 'NM Kills', 'Sightings', 'Pop Samples', 'Avg To Pop', 'Avg PH / Pop' }) do
            imgui.TableSetupColumn(name, ImGuiTableColumnFlags_WidthFixed);
        end
        imgui.TableHeadersRow();
        for _, entry in ipairs(statsRows) do
            local row, pop = entry.data, entry.data.pops;
            imgui.PushID(entry.key);
            imgui.TableNextRow(); imgui.TableNextColumn();
            if imgui.Selectable(row.name, chosenStats == entry.key) then
                chosenStats, statsDetails = entry.key, nil;
            end
            imgui.TableNextColumn(); Plain(entry.zoneName);
            imgui.TableNextColumn(); Plain(tostring(row.phKills));
            imgui.TableNextColumn(); Plain(tostring(row.nmKills));
            imgui.TableNextColumn(); Plain(tostring(row.sightings));
            imgui.TableNextColumn(); Plain(tostring(pop.count));
            imgui.TableNextColumn(); Plain(pop.count > 0 and Clock(pop.total / pop.count) or 'Unknown');
            imgui.TableNextColumn(); Plain(pop.count > 0 and ('%.1f'):format(pop.phTotal / pop.count) or 'Unknown');
            imgui.PopID();
        end
        imgui.EndTable();
    end
    local row = options.hunting.monsters[chosenStats];
    if not row then return; end
    if not widgets.Header(row.name .. ' — Hunting Record') then return; end
    if row.lastKill then Plain('Last observed kill: ' .. os.date('%Y-%m-%d %H:%M', row.lastKill)); end
    if row.lastSeen then Plain('Last sighting: ' .. os.date('%Y-%m-%d %H:%M', row.lastSeen)); end
    if row.pops.count > 0 then
        Plain(('Fastest / slowest observed pop: %s / %s'):format(Clock(row.pops.min), Clock(row.pops.max)));
    end
    if row.returns.count > 0 then
        Plain(('Observed return after NM kill: average %s; fastest %s; slowest %s (%d samples)'):format(
            Clock(row.returns.total / row.returns.count), Clock(row.returns.min), Clock(row.returns.max), row.returns.count));
    end
    Plain(('Kills with loot seen: %d / %d observed NM kills'):format(row.lootKills, row.nmKills));
    imgui.TextDisabled('Drops are items found, not items won. Missing loot/TH/other hunters bias these observations.');
    if statsDetails == nil then
        statsDetails = { items = {}, placeholders = {} };
        local ids = {};
        local record = hunts.Monster(row.zone, row.name);
        for _, roll in ipairs(record and record.drops or {}) do
            for _, item in ipairs(roll.items) do ids[tostring(item[1])] = true; end
        end
        for id in pairs(row.items) do ids[id] = true; end
        for id in pairs(ids) do
            statsDetails.items[#statsDetails.items + 1] = { id = id, name = ItemName(tonumber(id)) };
        end
        table.sort(statsDetails.items, function(a, b) return a.name < b.name; end);
        for index, kills in pairs(row.placeholders) do
            statsDetails.placeholders[#statsDetails.placeholders + 1] = { index = tonumber(index), kills = kills };
        end
        table.sort(statsDetails.placeholders, function(a, b) return a.index < b.index; end);
    end
    for _, ph in ipairs(statsDetails.placeholders) do
        Plain(('PH %03X: %d observed kills'):format(ph.index, ph.kills));
    end
    if imgui.BeginTable('mark.statsDrops', 4, ImGuiTableFlags_SizingFixedFit) then
        for _, label in ipairs({ 'Item', 'Quantity Seen', 'Kills With Item', '% Observed Kills' }) do
            imgui.TableSetupColumn(label, ImGuiTableColumnFlags_WidthFixed);
        end
        imgui.TableHeadersRow();
        for _, item in ipairs(statsDetails.items) do
            local drop = row.items[item.id] or { quantity = 0, kills = 0 };
            imgui.TableNextRow(); imgui.TableNextColumn(); Plain(item.name);
            imgui.TableNextColumn(); Plain(tostring(drop.quantity));
            imgui.TableNextColumn(); Plain(tostring(drop.kills));
            imgui.TableNextColumn(); Plain(row.nmKills > 0 and ('%.1f%%'):format(100 * drop.kills / row.nmKills) or 'Unknown');
        end
        imgui.EndTable();
    end
end

local function DrawPicker(options, width)
    local zones = hunts.Zones(options.showScripted[1]);
    local scale = math.max(0.25, math.min(1, (width - 100) / (TextBaseWidth * 80)));

    imgui.SetNextItemWidth(TextBaseWidth * 30 * scale);
    if imgui.BeginCombo('##mark.zone', options.viewZone ~= 0 and hunts.ZoneName(options.viewZone) or 'Zone') then
        for _, zone in ipairs(zones) do
            if imgui.Selectable(zone.label, zone.id == options.viewZone) and zone.id ~= options.viewZone then
                Show(options, zone.id, zone.monsters[1]);
            end
        end
        imgui.EndCombo();
    end

    imgui.SameLine();
    imgui.SetNextItemWidth(TextBaseWidth * 34 * scale);
    if imgui.BeginCombo('##mark.monster', options.viewName ~= '' and options.viewName or 'Notorious Monster') then
        if find[1] ~= '' then
            -- looked up by name: whichever zone they are in
            for _, found in ipairs(hunts.Find(find[1], options.showScripted[1])) do
                if imgui.Selectable(found.label, found.zone == options.viewZone and found.name == options.viewName) then
                    Show(options, found.zone, found.name);
                end
            end
        else
            for _, zone in ipairs(zones) do
                if zone.id == options.viewZone then
                    for _, name in ipairs(zone.monsters) do
                        if imgui.Selectable(name, name == options.viewName) and name ~= options.viewName then
                            Show(options, zone.id, name);
                        end
                    end
                end
            end
        end
        imgui.EndCombo();
    end

    imgui.SameLine();
    imgui.AlignTextToFramePadding();
    imgui.Text('Find:');
    imgui.SameLine();
    imgui.SetNextItemWidth(TextBaseWidth * 16 * scale);
    imgui.InputText('##mark.find', find, 64);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Type a part of a name: the monsters dropdown then lists every monster with it, in any zone.');
    end
end

local function Lines(lines)
    for _, line in ipairs(lines) do
        Plain(line);
    end
end

local tightCells = { 6, 1 };
local dropFlags = bit.bor(ImGuiTableFlags_SizingFixedFit, ImGuiTableFlags_NoHostExtendX, ImGuiTableFlags_RowBg, ImGuiTableFlags_BordersInnerV);

local function DrawMonster(options)
    local record = view.record;
    local isMark = IsMark(options, options.viewZone, options.viewName) ~= nil;

    imgui.AlignTextToFramePadding();
    imgui.TextColored(isMark and gold or widgets.HeaderColor, options.viewName);
    imgui.SameLine();
    if isMark then
        if imgui.Button('Clear Mark##mark.clear') then
            RemoveMark(options, options.viewZone, options.viewName);
        end
    elseif imgui.Button('Set As Mark##mark.set') then
        AddMark(options, options.viewZone, options.viewName);
    end
    imgui.SameLine();
    if imgui.Button(options.showMap[1] and 'Hide Map##mark.map' or 'Show Map##mark.map') then
        options.showMap[1] = not options.showMap[1];
    end
    -- its time of death: given here, and what follows from it
    if imgui.Button('Report TOD##mark.tod') then
        SetTod(options, options.viewZone, options.viewName, os.time() - math.max(0, minutesAgo[1]) * 60);
        minutesAgo[1] = 0;
        live.checked = 0;
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Keeps a time of death for this monster, from which its window is counted: now, or as many minutes ago as the box says.\n/mark tod does the same for the mark.');
    end
    imgui.SameLine();
    imgui.SetNextItemWidth(TextBaseWidth * 12);
    imgui.InputInt('Minutes Ago##mark.todAgo', minutesAgo);
    if live.viewTimer ~= nil then
        imgui.SameLine();
        if imgui.Button('Clear TOD##mark.todClear') then
            SetTod(options, options.viewZone, options.viewName, nil);
            live.checked = 0;
        end
        Timer(live.viewTimer);
    end

    -- the sentences keep to the width of the tables under them
    imgui.PushTextWrapPos(imgui.GetCursorPosX() + TextBaseWidth * 96);

    if widgets.Header('How It Appears') then
        Lines(view.appears);
    end

    if #view.placeholders > 0 then
        local here = live.zone == options.viewZone;
        if widgets.Header('Placeholders') then
            if imgui.BeginTable('mark.placeholders', 6, ImGuiTableFlags_SizingFixedFit) then
                imgui.TableSetupColumn('Placeholder', ImGuiTableColumnFlags_WidthFixed);
                imgui.TableSetupColumn('ID', ImGuiTableColumnFlags_WidthFixed);
                imgui.TableSetupColumn('Respawn', ImGuiTableColumnFlags_WidthFixed);
                imgui.TableSetupColumn('Where', ImGuiTableColumnFlags_WidthFixed);
                imgui.TableSetupColumn('Next Spawn', ImGuiTableColumnFlags_WidthFixed);
                imgui.TableSetupColumn('##mark.phButtons', ImGuiTableColumnFlags_WidthFixed);
                imgui.TableHeadersRow();
                for _, placeholder in ipairs(view.placeholders) do
                    imgui.TableNextRow();
                    imgui.TableNextColumn();
                    imgui.AlignTextToFramePadding();
                    imgui.Text(placeholder.name);
                    imgui.TableNextColumn();
                    imgui.Text(placeholder.id);
                    imgui.TableNextColumn();
                    imgui.Text(placeholder.respawn);
                    imgui.TableNextColumn();
                    imgui.Text(placeholder.where);
                    imgui.TableNextColumn();
                    NextSpawn(placeholder.index, here);
                    imgui.TableNextColumn();
                    if imgui.SmallButton(placeholder.mapId) then
                        chart.focus = placeholder.place;
                        options.showMap[1] = true;
                    end
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip('The map, with this placeholder alone beside the monster: all the ground it can spawn on, and its route if it walks one.');
                    end
                    if here then
                        imgui.SameLine();
                        if imgui.SmallButton(placeholder.todId) then
                            SetPlaceholderTod(options, placeholder.index, os.time());
                            live.checked = 0;
                        end
                        if imgui.IsItemHovered() then
                            imgui.SetTooltip('This placeholder died just now: its respawn is timed from here. One seen dead is timed without being told.\n/mark ph <ID> does the same, and /mark ph <ID> 2 says it died two minutes ago.');
                        end
                        if live.deaths[placeholder.index] ~= nil then
                            imgui.SameLine();
                            if imgui.SmallButton(placeholder.clearId) then
                                SetPlaceholderTod(options, placeholder.index, nil);
                                live.checked = 0;
                            end
                        end
                    end
                end
                imgui.EndTable();
            end
        end
    end

    if widgets.Header('Spawn Locations') then
        if #view.places == 0 then
            imgui.TextWrapped(#view.placeholders > 0 and 'The server\'s data gives it no place of its own: it stands where its placeholder would have.'
                or 'The server\'s data gives it no place of its own.');
        else
            Lines(view.places);
            if live.nearest ~= nil then
                imgui.Text(live.nearest);
            end
        end
    end

    if widgets.Header('Drops') then
        if #view.drops == 0 then
            imgui.Text('Nothing, by the server\'s data.');
        else
            -- each column as wide as what is in it and no wider, and the rows close together
            imgui.PushStyleVar(ImGuiStyleVar_CellPadding, tightCells);
            local begun = imgui.BeginTable('mark.drops', #view.headings + 1, dropFlags);
            if begun then
            imgui.TableSetupColumn('Item', ImGuiTableColumnFlags_WidthFixed);
            for _, heading in ipairs(view.headings) do
                imgui.TableSetupColumn(heading, ImGuiTableColumnFlags_WidthFixed);
            end
            imgui.TableHeadersRow();
            for _, row in ipairs(view.drops) do
                imgui.TableNextRow();
                imgui.TableNextColumn();
                -- a roll of several is told from the items under it by its colour
                if row.group then
                    imgui.PushStyleColor(ImGuiCol_Text, dim);
                end
                Plain(row.label);
                for _, cell in ipairs(row.cells) do
                    imgui.TableNextColumn();
                    Plain(cell);
                end
                if row.group then
                    imgui.PopStyleColor();
                end
            end
            imgui.EndTable();
            end
            imgui.PopStyleVar();
        end
        if view.steal ~= nil then
            Plain(view.stealLine);
        end
        if view.despoil ~= nil then
            Plain(view.despoilLine);
        end
    end

    imgui.PopTextWrapPos();
end

local databaseChild = { zone = nil, name = nil };
local databaseSize = { 0, 0 };
local function DrawDatabaseDetails(options)
    if databaseChild.zone ~= options.viewZone or databaseChild.name ~= options.viewName then
        imgui.SetScrollX(0);
        imgui.SetScrollY(0);
        databaseChild.zone, databaseChild.name = options.viewZone, options.viewName;
    end
    if view.record ~= nil then
        DrawMonster(options);
    elseif options.viewName ~= '' then
        Plain('There is no data for ' .. options.viewName .. '.');
    else
        imgui.TextDisabled('Choose a zone and a notorious monster below.');
    end
end

local function DrawDatabase(options)
    -- A bounded details pane keeps the search footer reachable even for long drop/PH lists.
    -- Horizontal scrolling preserves wide Treasure Hunter tables rather than clipping columns.
    local display = imgui.GetIO().DisplaySize;
    local width, height = display.x or display[1], display.y or display[2];
    databaseSize[1] = math.min(TextBaseWidth * 104, math.max(320, width - 80));
    databaseSize[2] = math.max(180, math.min(600, height - 260));
    local shown = imgui.BeginChild('##mark.databaseDetails', databaseSize, ImGuiChildFlags_None or 0, ImGuiWindowFlags_HorizontalScrollbar);
    local ok, err = true, nil;
    if shown ~= false then
        ok, err = pcall(DrawDatabaseDetails, options);
    end
    imgui.EndChild(); -- required when clipped, and before propagating a draw failure
    if not ok then error(err, 0); end
    imgui.Separator();
    DrawPicker(options, databaseSize[1]);
end

-- The header: the addon's name, and at the far end of the line a button that closes the window. How
-- far that is, is what is under the header was wide the frame before: the button is not to be what
-- holds the window to its width.
local header = { body = 0, button = TextBaseWidth * 3 };

local function DrawHeader(options)
    local left = imgui.GetCursorPosX();
    imgui.AlignTextToFramePadding();
    imgui.TextColored(widgets.HeaderColor, 'Mark');
    imgui.SameLine();
    local nextTo = imgui.GetCursorPosX();
    imgui.SameLine(math.max(nextTo, left + header.body - header.button));
    if imgui.Button('x##mark.close') then
        options.isVisible[1] = false;
        app:Save();
    end
    header.button = imgui.GetItemRectSize() or header.button;
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Closes the window. /mark brings it back; the marks are watched meanwhile.');
    end
end

local function Draw(options)
    if options.compact[1] then
        if not DrawCompact() then
            imgui.Text('No mark is set.');
            imgui.TextDisabled('/mark compact brings the whole window back.');
        end
        return;
    end

    DrawHeader(options);
    local turnTo = wantTab;
    wantTab = nil;
    imgui.BeginGroup();
    if imgui.BeginTabBar('##mark.tabs', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        if imgui.BeginTabItem('Database##mark.database', 0, turnTo == 1 and ImGuiTabItemFlags_SetSelected or 0) then
            DrawDatabase(options);
            imgui.EndTabItem();
        end
        if imgui.BeginTabItem('Marks##mark.marksTab') then
            DrawMarks(options);
            imgui.EndTabItem();
        end
        if imgui.BeginTabItem('Stats##mark.statsTab', 0, turnTo == 3 and ImGuiTabItemFlags_SetSelected or 0) then
            DrawStats(options);
            imgui.EndTabItem();
        end
        imgui.EndTabBar();
    end
    imgui.EndGroup();
    header.body = imgui.GetItemRectSize() or header.body;
end

----------------------------------------------------------------------------------------------------
-- The settings, the settings window, the command and the main window's frame are the shell's
----------------------------------------------------------------------------------------------------
local defaults = T{
    isVisible = T{ true },
    pos = T{ 100, 100 },
    marks = T{ },                -- the marks: each { zone, name }
    tods = T{ },                 -- times of death kept: each { zone, name, at (os.time) }
    phTods = T{ },               -- placeholder deaths: each { zone, index, at (os.time) }
    hunting = T{ version = 1, monsters = T{ } }, -- aggregate hunting database, per character
    viewZone = 0,                -- the monster on show
    viewName = '',
    compact = T{ false },        -- only the mark's few lines
    announce = T{ true },        -- says in the chat log that the mark is up, or dead
    sound = T{ true },           -- and sounds as it comes up
    announcePlaceholders = T{ true }, -- says in the chat log that a timed placeholder is due, and that it is up
    showScripted = T{ false },   -- lists the monsters the data knows only as brought by a script
    maxTh = T{ 4 },              -- the highest Treasure Hunter the drops are worked out for
    showMap = T{ false },        -- the map window
    pinMap = T{ false },         -- keep the map open when the main window is closed
    mapPos = T{ 160, 160 },      -- independent map window position
    mapSize = T{ 512 },          -- how many pixels across the map is drawn
};

local windowName = 'winxi.mark';

local function DrawSettings(options)
    widgets.Label('Visible');
    imgui.Checkbox('##mark.visible', options.isVisible);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Whether the window shows. /mark switches this.');
    end
    widgets.Label('Position');
    if imgui.InputInt2('##mark.position', options.pos) then
        imgui.SetWindowPos(windowName, options.pos);
    end
    widgets.Label('Compact Window');
    imgui.Checkbox('##mark.compact', options.compact);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Only the marks, with no header and no tabs: whether each and its placeholders are in range, and what is known of its return. /mark compact switches this.');
    end

    widgets.Gap();
    widgets.Label('Show Map');
    imgui.Checkbox('##mark.showMap', options.showMap);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The zone\'s map in a window of its own, with where the monster on show (red) and its placeholders (blue) can spawn laid over it: the deeper the colour, the more can spawn there. /mark map switches this.');
    end
    widgets.Label('Pin Map');
    imgui.Checkbox('##mark.pinMap', options.pinMap);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Keeps the map open when Mark\'s main window is closed; the usual loading and cutscene hiding rules still apply.');
    end
    widgets.Label('Map Size');
    imgui.SliderInt('##mark.mapSize', options.mapSize, 256, 1024);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The viewport size in pixels, independent of zoom. Native-resolution map pictures preserve more detail when enlarged; some source maps are only 512 pixels.');
    end

    widgets.Gap();
    widgets.Label('Show Scripted Spawns');
    imgui.Checkbox('##mark.scripted', options.showScripted);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Lists the notorious monsters a quest, a battlefield or an event brings as well: the server\'s data has their drops, and nothing of how they are brought.');
    end
    widgets.Label('Highest Treasure Hunter');
    imgui.SliderInt('##mark.maxTh', options.maxTh, 0, hunts.MaxTreasureHunter);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The drops are worked out for every level of Treasure Hunter up to this one.\nThe server takes up to 4 from a job that is not a thief\'s, up to 8 from a thief, and more only as a thief\'s blows raise it during the fight.');
    end

    widgets.Gap();
    widgets.Label('Announce Mark');
    imgui.Checkbox('##mark.announce', options.announce);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Says in the chat log that the mark has come into range, how far and which way, and that it has been seen dead.');
    end
    widgets.Label('Announce Placeholders');
    imgui.Checkbox('##mark.announcePh', options.announcePlaceholders);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Says in the chat log that a placeholder being timed is due to respawn, and that it has been seen up again.');
    end
    widgets.Label('Sound When Up');
    imgui.Checkbox('##mark.sound', options.sound);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Plays a sound as the mark comes into range: open.wav in libs\\winxi\\sounds.');
    end
end

app = shell.New({
    defaults = defaults,
    window = windowName,
    configTitle = 'Mark Settings',
    command = '/mark',
    help = '/mark shows or hides the window; /mark config opens or closes the settings; /mark stats opens hunting statistics; /mark compact switches to the marks\' few lines and back; /mark map shows or hides the map; /mark pin keeps the map open independently; /mark set <name> makes a monster a mark; /mark clear [name] leaves none, or one fewer; /mark tod [minutes ago | hours:minutes | clear] keeps a mark\'s time of death; /mark ph <ID> [minutes ago | clear] times a placeholder.',
    drawSettings = DrawSettings,
    onSettings = function(options)
        ResetLive(); -- reloaded settings or a different character: no observations carry over
        options.hunting = stats.Prepare(options.hunting);
        tracker = stats.New(options.hunting);
        databaseChild.zone, databaseChild.name = nil, nil;
        statsRows, statsDetails, chosenStats = nil, nil, nil;
        mapView.Reset(mapState);
        mapState.zone, mapState.name, mapState.floor = nil, nil, nil;
        mapPlaced, mapMoved = false, false;
        if type(options.pinMap) ~= 'table' or type(options.pinMap[1]) ~= 'boolean' then
            options.pinMap = T{ false };
        end
        if type(options.mapPos) ~= 'table' or type(options.mapPos[1]) ~= 'number' or type(options.mapPos[2]) ~= 'number'
            or options.mapPos[1] ~= options.mapPos[1] or options.mapPos[2] ~= options.mapPos[2]
            or math.abs(options.mapPos[1]) == math.huge or math.abs(options.mapPos[2]) == math.huge then
            options.mapPos = T{ options.pos[1] + 60, options.pos[2] + 60 };
        end
        -- anything a saved file has in another shape than it should
        for _, key in ipairs({ 'compact', 'announce', 'sound', 'announcePlaceholders', 'showScripted', 'maxTh', 'showMap', 'mapSize', 'tods', 'marks' }) do
            if type(options[key]) ~= 'table' then
                options[key] = defaults[key];
            end
        end
        for place = #options.marks, 1, -1 do
            local mark = options.marks[place];
            if type(mark) ~= 'table' or type(mark.zone) ~= 'number' or type(mark.name) ~= 'string' then
                table.remove(options.marks, place);
            end
        end
        -- the one mark of a file saved when there could be no more
        if type(options.markName) == 'string' and options.markName ~= '' and type(options.markZone) == 'number'
            and IsMark(options, options.markZone, options.markName) == nil then
            options.marks[#options.marks + 1] = T{ zone = options.markZone, name = options.markName };
        end
        options.markZone, options.markName = nil, nil;
        -- a time of death with a part missing is of no use
        for place = #options.tods, 1, -1 do
            local tod = options.tods[place];
            if type(tod) ~= 'table' or type(tod.zone) ~= 'number' or type(tod.name) ~= 'string' or type(tod.at) ~= 'number' then
                table.remove(options.tods, place);
            end
        end
        if type(options.phTods) ~= 'table' then
            options.phTods = T{ };
        end
        local seen = {};
        for place = #options.phTods, 1, -1 do
            local tod = options.phTods[place];
            local valid = type(tod) == 'table' and type(tod.zone) == 'number' and tod.zone > 0
                and tod.zone < math.huge and tod.zone % 1 == 0
                and type(tod.index) == 'number' and tod.index >= 1 and tod.index <= 0xFFF and tod.index % 1 == 0
                and type(tod.at) == 'number' and tod.at > 0 and tod.at < math.huge;
            local key = valid and Key(tod.zone, tostring(tod.index)) or nil;
            if not valid or seen[key] then
                table.remove(options.phTods, place);
            else
                seen[key] = true;
            end
        end
    end,
    commands = {
        stats = function(options)
            options.isVisible[1], options.compact[1] = true, false;
            wantTab = 3;
        end,
        compact = function(options)
            options.compact[1] = not options.compact[1];
        end,
        map = function(options)
            options.showMap[1] = not options.showMap[1];
            app:Save();
        end,
        pin = function(options)
            options.pinMap[1] = not options.pinMap[1];
            if options.pinMap[1] then
                options.showMap[1] = true;
            end
            app:Save();
        end,
        ph = function(options, args)
            if not settings.logged_in or game.IsLoading() then
                Say('Log in before reporting a placeholder death.');
                return;
            end
            -- a placeholder of a mark's or of the monster on show's, in the zone the player is in, by its ID
            local index = args[3] ~= nil and tonumber(args[3], 16) or nil;
            local found = nil;
            local function Among(zone, name)
                local record = zone == live.zone and name ~= '' and hunts.Monster(zone, name) or nil;
                for _, placeholder in ipairs(record and record.placeholders or {}) do
                    if placeholder.index == index then
                        found = placeholder;
                    end
                end
            end
            Among(options.viewZone, options.viewName);
            for _, mark in ipairs(options.marks) do
                Among(mark.zone, mark.name);
            end
            if found == nil then
                Say('/mark ph <ID> [minutes ago | clear]: the ID of a placeholder of the mark\'s, in the zone you are in, as the window shows it.');
                return;
            end
            live.checked = 0;
            if args[4] ~= nil and args[4]:lower() == 'clear' then
                SetPlaceholderTod(options, index, nil);
                Say(('%s (%03X) is no longer timed.'):format(found.name, index));
                return;
            end
            local ago = args[4] == nil and 0 or tonumber(args[4]);
            if ago == nil or ago < 0 then
                Say('/mark ph <ID> [minutes ago | clear]');
                return;
            end
            SetPlaceholderTod(options, index, os.time() - math.floor(ago * 60));
            Say(('%s (%03X) is timed from %s.'):format(found.name, index, os.date('%H:%M:%S', live.deaths[index])));
        end,
        tod = function(options, args)
            -- the mark's: the one of the zone the player is in, or the only one there is. Failing
            -- that, the monster on show's.
            local zone, name = options.viewZone, options.viewName;
            local here, only = nil, 0;
            for _, mark in ipairs(options.marks) do
                if mark.zone == live.zone then
                    here, only = mark, only + 1;
                end
            end
            if only == 1 then
                zone, name = here.zone, here.name;
            elseif #options.marks == 1 then
                zone, name = options.marks[1].zone, options.marks[1].name;
            end
            if name == '' or hunts.Monster(zone, name) == nil then
                Say('There is no mark, and no monster on show, to keep a time of death for.');
                return;
            end
            live.checked = 0;
            if args[3] ~= nil and args[3]:lower() == 'clear' then
                SetTod(options, zone, name, nil);
                Say(('%s: its time of death is forgotten.'):format(name));
                return;
            end
            local at = ParseWhen(args[3]);
            if at == nil then
                Say('/mark tod, alone for now; or with how many minutes ago (/mark tod 15), a time by the clock (/mark tod 14:35), or clear.');
                return;
            end
            SetTod(options, zone, name, at);
            Say(('%s: died at %s. %s'):format(name, os.date('%H:%M', at), (Standing(hunts.Monster(zone, name), at)):gsub('^Died .- ago%.%s*', '')));
        end,
        clear = function(options, args)
            -- every mark, or the one named
            local words = table.concat(args, ' ', 3):lower();
            local cleared = 0;
            for place = #options.marks, 1, -1 do
                local mark = options.marks[place];
                if words == '' or mark.name:lower():find(words, 1, true) ~= nil then
                    Say(('%s is no longer a mark.'):format(mark.name));
                    table.remove(options.marks, place);
                    live.marks[Key(mark.zone, mark.name)] = nil;
                    cleared = cleared + 1;
                end
            end
            if cleared > 0 then
                live.checked = 0;
                app:Save();
            end
            if cleared == 0 and words ~= '' then
                Say(('No mark has "%s" in its name.'):format(words));
            end
        end,
        set = function(options, args)
            local words = table.concat(args, ' ', 3);
            if words == '' then
                Say('/mark set <name>: a notorious monster\'s name, or a part of it.');
                return;
            end
            -- one of the zone the player is in before any other, and a whole name before a part of one
            local found = hunts.Find(words, true, 200);
            local best, bestScore = nil, nil;
            local lower = words:lower();
            for _, monster in ipairs(found) do
                local score = (monster.name:lower() == lower and 2 or 0) + (monster.zone == live.zone and 1 or 0);
                if best == nil or score > bestScore then
                    best, bestScore = monster, score;
                end
            end
            if best == nil then
                Say(('No notorious monster has "%s" in its name.'):format(words));
                return;
            end
            AddMark(options, best.zone, best.name);
            Show(options, best.zone, best.name);
            Say(('%s is a mark.'):format(best.label));
        end,
    },
});

local mapWindowName = 'winxi.mark.map';
local function drawMapWindow()
    local options = app.options;
    DrawMap(options);
    local x, y = imgui.GetWindowPos();
    if x ~= options.mapPos[1] or y ~= options.mapPos[2] then
        options.mapPos[1], options.mapPos[2] = x, y;
        mapMoved = true;
    end
end

ashita.events.register('packet_in', 'mark_hunting_packets', function(e)
    if e.id ~= 0x029 and e.id ~= 0x0D2 then return; end
    if e.blocked or e.injected or not settings.logged_in or game.IsLoading() then return; end
    local event = stats.Packet(e.id, e.data_raw or e.data);
    if event == nil or event.index == nil or event.source == nil or event.source == 0
        or bit.band(event.source, 0xFFF) ~= event.index then return; end
    local zone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
    -- Monster server IDs include the zone as well as the local entity index.
    if bit.band(bit.rshift(event.source, 12), 0xFFF) ~= zone then return; end
    tracker:Watch(zone, StatsTargets(app.options, zone));
    if event.kind == 'death' then
        tracker:Death(event.index, os.time(), true);
    else
        tracker:Drop(event.index, event.item, event.quantity, event.token, os.time());
    end
    if tracker.changed then
        statsRows, statsDetails = nil, nil;
        tracker.changed = false;
        app:Save();
    end
end);

ashita.events.register('d3d_present', 'mark_present', function()
    -- the marks are watched whether or not the window is there to be seen
    local shown = app:BeginFrame();
    local options = app.options;
    Update(options);
    if not shown then
        mapState.mouseX, mapState.mouseY = nil, nil;
        return;
    end

    -- nothing chosen yet: the zone the player is in, if it has any to list
    if options.viewZone == 0 and live.zone ~= 0 then
        for _, zone in ipairs(hunts.Zones(options.showScripted[1])) do
            if zone.id == live.zone then
                Show(options, zone.id, zone.monsters[1]);
            end
        end
    end
    BuildView(options);
    app:Window(options.isVisible, Draw);
    if options.showMap[1] and (options.isVisible[1] or options.pinMap[1]) then
        if not mapPlaced then
            imgui.SetNextWindowPos(options.mapPos, ImGuiCond_Always);
            mapPlaced = true;
        end
        local flags = bit.bor(style.TitlelessFlags(), ImGuiWindowFlags_NoScrollWithMouse, ImGuiWindowFlags_NoScrollbar);
        if not window.Full(mapWindowName, options.showMap, flags, drawMapWindow) then
            mapState.mouseX, mapState.mouseY = nil, nil;
        end
        if mapMoved and not imgui.IsMouseDown(0) then
            mapMoved = false;
            app:Save();
        end
    else
        mapState.mouseX, mapState.mouseY = nil, nil;
    end
end);
