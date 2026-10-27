-- What mark knows of the notorious monsters, and how it is put into words. Nothing here draws.
--
-- The data is the server's own, written out by tools/build_mark_data.py as winxi's marks set (the
-- chosen server's: index lists every zone with its monsters, and <zone id> has each monster of a zone
-- in full). A zone's file is
-- read the first time it is asked for.
--
--   hunts.Zones(showScripted)        the zones with something to list, each { id, name, monsters }
--   hunts.Monster(zone, name)        one monster's record, or nil
--   hunts.Find(words, showScripted)  the monsters whose name has the words in it, each { zone, name }
--   hunts.Chance(th, rate)           what a roll of that rate comes to with that much Treasure Hunter
--   hunts.Appears(record, itemName)  how the monster comes to be there, a line to each thing said
--   hunts.Drops(record, itemName)    its drops as rows for a table, the same rolls gathered together
--   hunts.Places(points, areas, square)  where a spawn is, a line to each thing said
local hunts = {};

local index = nil;      -- data/index.lua, once read
local zoneNames = {};   -- zone id -> the name it goes by
local zoneFiles = {};   -- zone id -> its monsters, or false where there is no file

local gamedata = require('winxi.gamedata');

-- One file of the chosen server's marks set: index, or a zone's
local function Read(name)
    return gamedata.Read('marks', name);
end
gamedata.OnChange(function () index, zoneNames, zoneFiles = nil, {}, {}; end); -- another server's data chosen

-- The game's own name for a zone, where it has one: the data's is the server's folder name tidied up
local function ZoneName(id, fallback)
    local ok, name = pcall(function()
        return AshitaCore:GetResourceManager():GetString('zones.names', id);
    end);
    if ok and type(name) == 'string' and name ~= '' then
        return name;
    end
    return fallback;
end

local function Index()
    if index == nil then
        index = Read('index') or {};
        for _, zone in ipairs(index) do
            zone.name = ZoneName(zone.id, zone.name);
            zoneNames[zone.id] = zone.name;
        end
        table.sort(index, function(a, b) return a.name < b.name; end);
    end
    return index;
end

function hunts.ZoneName(id)
    Index();
    return zoneNames[id] or ('Zone %d'):format(id);
end

-- Whether a monster is listed: one the data knows no more of than that a script brings it is left out
-- unless asked for. kinds is a letter for each way it comes: l(ottery), t(imed), f(orced), s(cripted).
local function Listed(kinds, showScripted)
    return showScripted or kinds ~= 's';
end

local listings = {}; -- showScripted -> the zones as listed

function hunts.Zones(showScripted)
    local key = showScripted and true or false;
    if listings[key] == nil then
        local zones = {};
        for _, zone in ipairs(Index()) do
            local monsters = {};
            for _, monster in ipairs(zone) do
                if Listed(monster[2], key) then
                    monsters[#monsters + 1] = monster[1];
                end
            end
            if #monsters > 0 then
                zones[#zones + 1] = { id = zone.id, name = zone.name, label = ('%s##%d'):format(zone.name, zone.id), monsters = monsters };
            end
        end
        listings[key] = zones;
    end
    return listings[key];
end

function hunts.Monster(zone, name)
    if zoneFiles[zone] == nil then
        zoneFiles[zone] = Read(('%u'):format(zone)) or false;
    end
    return zoneFiles[zone] and zoneFiles[zone][name] or nil;
end

-- Keep the current search only: an open dropdown asks for it every frame. The catalog is immutable;
-- callers treat the returned list and its rows as read-only.
local search = {};

-- The monsters whose name has the words in it, whichever zone they are in: no more than limit of them
function hunts.Find(words, showScripted, limit)
    words = words:lower();
    showScripted = showScripted and true or false;
    limit = limit or 40;
    if search.words == words and search.scripted == showScripted and search.limit == limit then
        return search.found;
    end
    local found = {};
    search.words, search.scripted, search.limit, search.found = words, showScripted, limit, found;
    for _, zone in ipairs(hunts.Zones(showScripted)) do
        for _, name in ipairs(zone.monsters) do
            if name:lower():find(words, 1, true) then
                found[#found + 1] = { zone = zone.id, name = name, label = ('%s (%s)'):format(name, zone.name) };
                if #found >= limit then
                    return found;
                end
            end
        end
    end
    return found;
end

-- Treasure Hunter, as the server reckons it: a roll's rate puts it in one of seven brackets, and each
-- level of Treasure Hunter has a rate for each bracket. A roll that always drops, or never does, is
-- left alone. Rates are out of 10000. They are winxi.rules' (read from the server's
-- scripts/combat/basic/treasure_hunter.lua); these, the same table, for when winxi's data is not installed.
local thRates = {
    [0]  = { 2400, 1500, 1000,  500,  100,  50,  10 },
    [1]  = { 4800, 3000, 1200,  600,  150,  75,  20 },
    [2]  = { 5600, 4000, 1500,  700,  200, 100,  30 },
    [3]  = { 6000, 4250, 1650,  750,  225, 120,  35 },
    [4]  = { 6400, 4500, 1800,  800,  250, 140,  40 },
    [5]  = { 6666, 4750, 1900,  850,  300, 160,  45 },
    [6]  = { 6800, 5000, 2000,  900,  350, 180,  50 },
    [7]  = { 6900, 5250, 2100,  950,  400, 200,  60 },
    [8]  = { 7050, 5500, 2250, 1050,  475, 230,  70 },
    [9]  = { 7200, 5750, 2400, 1150,  550, 260,  80 },
    [10] = { 7350, 6000, 2650, 1250,  650, 300,  90 },
    [11] = { 7400, 6250, 2800, 1350,  750, 350, 100 },
    [12] = { 7600, 6500, 2950, 1550,  825, 400, 115 },
    [13] = { 7800, 6750, 3100, 1750,  900, 450, 130 },
    [14] = { 8000, 7000, 3250, 2000, 1000, 500, 150 },
};
local thBrackets = { 2400, 1500, 1000, 500, 100, 50, 0 };

hunts.MaxTreasureHunter = 14;

do
    local ok, rules = pcall(require, 'winxi.rules');
    local th = ok and rules.Get('treasureHunter') or nil;
    if th ~= nil and th.Levels ~= nil and th.Brackets ~= nil then
        thRates, thBrackets, hunts.MaxTreasureHunter = th.Levels, th.Brackets, th.MaxLevel or hunts.MaxTreasureHunter;
    end
end

-- rate is the data's, in tenths of a percent. Returns the chance out of 10000.
function hunts.Chance(th, rate)
    local base = math.max(0, math.min(10000, rate * 10));
    if base == 10000 or base == 0 then
        return base;
    end
    th = math.max(0, math.min(hunts.MaxTreasureHunter, th));
    for bracket, floor in ipairs(thBrackets) do
        if base >= floor then
            return thRates[th][bracket];
        end
    end
    return base;
end

-- A chance out of 10000 as a percentage with no more figures than it needs: 24%, 0.5%, 66.66%
function hunts.Percent(chance)
    local text = ('%.2f'):format(chance / 100):gsub('0+$', ''):gsub('%.$', '');
    return text .. '%';
end

-- A wait in seconds, in the largest units that say it: 40 min, 2 hr, 1 hr 30 min, 3 days
function hunts.Duration(seconds)
    seconds = math.floor(seconds + 0.5);
    if seconds < 90 then
        return ('%d sec'):format(seconds);
    end
    local minutes = math.floor(seconds / 60 + 0.5);
    if minutes < 60 then
        return ('%d min'):format(minutes);
    end
    local hours, rest = math.floor(minutes / 60), minutes % 60;
    if hours >= 48 and hours % 24 == 0 and rest == 0 then
        return ('%d days'):format(hours / 24);
    end
    if rest == 0 then
        return ('%d hr'):format(hours);
    end
    return ('%d hr %d min'):format(hours, rest);
end

local function Window(least, most)
    if most == nil or most == least then
        return hunts.Duration(least);
    end
    return ('%s to %s'):format(hunts.Duration(least), hunts.Duration(most));
end

-- A point as the game's /pos gives it, without the height: east-west, then north-south
function hunts.Point(point)
    return ('(%d, %d)'):format(math.floor(point[1] + 0.5), math.floor(point[3] + 0.5));
end

local compass = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW' };

-- The way from one place to another, as a point of the compass: east is more x, north more z
function hunts.Compass(east, north)
    local angle = math.deg(math.atan2(east, north)) % 360;
    return compass[math.floor((angle + 22.5) / 45) % 8 + 1];
end

-- The hours are the server's (winxi.rules' spawnWindows, from its spawn_handler.cpp and zone.cpp's
-- fog), these where winxi's data is not installed
local windows = { AtNight = { 20, 4 }, AtEvening = { 18, 6 }, Fog = { 2, 7 } };
do
    local ok, rules = pcall(require, 'winxi.rules');
    windows = (ok and rules.Get('spawnWindows')) or windows;
end
local function Hours(window)
    return ('%d:00 to %d:00'):format(window[1], window[2]);
end
local conditions = {
    at_night = ('Only at night (%s).'):format(Hours(windows.AtNight)),
    at_evening = ('Only from evening to morning (%s).'):format(Hours(windows.AtEvening)),
    weather = 'Only in certain weather.',
    fog = ('Only in fog (%s).'):format(Hours(windows.Fog)),
    moonphase = 'Only at certain phases of the moon.',
};

local function Join(words)
    if #words <= 1 then
        return words[1] or '';
    end
    return table.concat(words, ', ', 1, #words - 1) .. ' and ' .. words[#words];
end

-- How the monster comes to be there, a line to each thing said. itemName gives an item's name by id.
function hunts.Appears(record, itemName)
    local lines = {};
    local lottery = record.lottery;
    if lottery ~= nil then
        if lottery.chance == nil then
            lines[#lines + 1] = 'Lottery: it can take a placeholder\'s place as that respawns. The server\'s scripts do not give the chance in a form this reads.';
        else
            lines[#lines + 1] = ('Lottery: a %s%% chance to take a placeholder\'s place each time one is killed.'):format(
                ('%.1f'):format(lottery.chance):gsub('%.0$', ''));
            if lottery.cooldown <= 60 and lottery.cooldownMost == nil then
                lines[#lines + 1] = 'No wait after it dies: the lottery is open again at once.';
            else
                lines[#lines + 1] = ('The lottery is closed for %s after it dies.'):format(Window(lottery.cooldown, lottery.cooldownMost));
            end
        end
        if lottery.immediate then
            lines[#lines + 1] = 'It appears as the placeholder dies, without waiting for the placeholder\'s respawn.';
        end
        if lottery.day then
            lines[#lines + 1] = 'Only by day (4:00 to 20:00).';
        elseif lottery.night then
            lines[#lines + 1] = 'Only by night (20:00 to 4:00).';
        end
        if record.placeholders == nil then
            lines[#lines + 1] = 'The server\'s scripts list no placeholder for it in this zone.';
        end
    end
    if record.respawn ~= nil then
        lines[#lines + 1] = ('Timed: it respawns %s after it dies.'):format(Window(record.respawn[1], record.respawn[2]));
    end
    for _, forced in ipairs(record.forced or {}) do
        local where = forced.at and (' at %s'):format(hunts.Point(forced.at)) or '';
        if #forced.items > 0 then
            local items = {};
            for place, id in ipairs(forced.items) do
                items[place] = itemName(id);
            end
            lines[#lines + 1] = ('Forced: trade %s to the %s%s.'):format(Join(items), forced.npc, where);
            if forced.unsure then
                lines[#lines + 1] = 'The script takes more than one trade there, and which is this monster\'s could not be told.';
            end
        else
            lines[#lines + 1] = ('Forced: brought out at the %s%s. What the script asks for is not an item this reads.'):format(forced.npc, where);
        end
    end
    if record.kinds == 's' then
        lines[#lines + 1] = 'Scripted: a quest, a battlefield or an event brings it. The server\'s data says no more.';
    end
    for _, condition in ipairs(record.conditions or {}) do
        lines[#lines + 1] = conditions[condition] or condition;
    end
    return lines;
end

-- Where a spawn is: its points written out while they are few, or the stretch they cover; and for
-- one put down anywhere in a region, the middle of the region and how far it reaches. square, if
-- given, says which square of the map's grid a point is in ('H-7'), or nil where that cannot be told:
-- the square then goes before the point.
function hunts.Places(points, areas, square)
    local lines = {};
    points = points or {};
    local function Written(point)
        local grid = square ~= nil and square(point) or nil;
        if grid ~= nil then
            return ('%s %s'):format(grid, hunts.Point(point));
        end
        return hunts.Point(point);
    end
    if #points > 0 and #points <= 6 then
        local written = {};
        for place, point in ipairs(points) do
            written[place] = Written(point);
        end
        lines[#lines + 1] = table.concat(written, '   ');
    elseif #points > 6 then
        local west, east, south, north = points[1][1], points[1][1], points[1][3], points[1][3];
        local grids, listed = {}, {};
        for _, point in ipairs(points) do
            west, east = math.min(west, point[1]), math.max(east, point[1]);
            south, north = math.min(south, point[3]), math.max(north, point[3]);
            local grid = square ~= nil and square(point) or nil;
            if grid ~= nil and not listed[grid] then
                listed[grid] = true;
                grids[#grids + 1] = grid;
            end
        end
        table.sort(grids);
        lines[#lines + 1] = ('%d points%s, from %s to %s'):format(#points, #grids > 0 and (' in ' .. table.concat(grids, ', ')) or '',
            hunts.Point({ west, 0, south }), hunts.Point({ east, 0, north }));
    end
    for _, area in ipairs(areas or {}) do
        lines[#lines + 1] = ('Anywhere within about %d yalms of %s'):format(area.reach, Written(area.at));
    end
    return lines;
end

-- Where a spawn is, as briefly as can be said: its spawn point (the middle of the region, for one
-- put down anywhere in a region), and how many more there are if there are several
function hunts.Spot(points, areas, square)
    local first, count = nil, 0;
    for _, point in ipairs(points or {}) do
        first, count = first or point, count + 1;
    end
    for _, area in ipairs(areas or {}) do
        first, count = first or area.at, count + 1;
    end
    if first == nil then
        return '';
    end
    local grid = square ~= nil and square(first) or nil;
    local written = grid ~= nil and ('%s %s'):format(grid, hunts.Point(first)) or hunts.Point(first);
    if count > 1 then
        written = ('%s (+%d)'):format(written, count - 1);
    end
    return written;
end

-- The drops as rows for a table. Rolls that are the same are gathered into one row with a count. A
-- roll that gives one of several items is a heading row (group = true) with a row to each item under
-- it (indent = true), whose rate is the roll's and whose share is its part of the roll out of 10000.
function hunts.Drops(record, itemName)
    local rows, seen = {}, {};
    for _, roll in ipairs(record.drops or {}) do
        local key = tostring(roll.rate);
        for _, item in ipairs(roll.items) do
            key = ('%s,%d:%d'):format(key, item[1], item[2]);
        end
        if seen[key] ~= nil then
            seen[key].count = seen[key].count + 1;
        elseif #roll.items == 1 and roll.items[1][2] == 10000 then
            local row = { name = itemName(roll.items[1][1]), id = roll.items[1][1], rate = roll.rate, share = 10000, count = 1 };
            rows[#rows + 1], seen[key] = row, row;
        else
            local row = { name = 'One Of', rate = roll.rate, share = 10000, count = 1, group = true };
            rows[#rows + 1], seen[key] = row, row;
            for _, item in ipairs(roll.items) do
                rows[#rows + 1] = { name = itemName(item[1]), id = item[1], rate = roll.rate, share = item[2], indent = true };
            end
        end
    end
    return rows;
end

return hunts;
