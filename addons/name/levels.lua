-- The levels a monster can be, from the tables of the area it is in.
--
--   levels.Of(index, name, id)   what to write for the entity with this index, name and server id:
--                            the level it was found to be when its player checked it; or the levels it
--                            can be, '5-6', or '8' where it can only be the one; or nil if neither is known
--   levels.Checked(index, id)    what the check found: { text = its level, or nil for one whose strength
--                            is impossible to gauge, hard = how hard a fight it was said to be, at =
--                            when, by os.clock, hardShort = difficulty abbreviation (or '???') }, or nil
--   levels.Monster(index, name)  what the tables say of it, as mobdb has it (Aggro, Link, Sight, Sound,
--                            Blood, Magic, JA, Scent, TrueSight, Notorious, Family), or nil
--   levels.HandlePacket(e)   every packet in goes by this: the area entered, checks and deaths
--   levels.Generation()      a number that changes whenever what levels.Of would say may have
--   levels.Tidy()            each frame: what was checked and has since died and gone is forgotten
--   levels.Set(data)         the tables to look in, for whoever has them some other way
--   levels.Notorious()       the names of the area's notorious monsters, in order
--   levels.Placeholders(name)  the monsters a notorious monster is drawn by lot from, as a set of their
--                            indices, { [index] = true }, or nil if the server's scripts list none
--   levels.DoubleLetters(on)  whether a name with more than 26 slots goes on to aa, ab and on
--   levels.LetterPairs()     how many of those double letters the area needs, aa being the first
--   levels.RosterProblem()   what to tell the user while the area's names could not be read from the game's
--                            files, or differ from what the game shows, or nil
--
-- The game does not tell the client a monster's level. winxi.mobs' tables say what levels each of an
-- area's monsters can be: mobdb's, made from the server's own (libs\winxi\data, by
-- tools/build_winxi_data.py), so that mobdb need not be there. A monster is looked for by its index,
-- and failing that by its name: two of one name in an area can be of different levels.
--
-- The area's tables are read as the area is entered, and that is all the reading there is.
--
-- The one time the game does tell a monster's level is in its answer to /check. When the player
-- checks a monster the level in the answer is kept for it, and written in place of what the tables
-- say, until its body is gone or the player leaves the area: the monster that next has its place is
-- another, of a level of its own, though it has the same server id. Its death is only noted, so that the
-- level stays while the body lies there, its health grey; the check is forgotten as the client stops
-- showing it, or as the place is seen alive again. It is kept five minutes at most, so that a long evening of checking in one
-- place does not leave more and more kept. Nothing is asked of the game for this: only its answers are read.
local levels = {};
local mobLetters = require('mob_letters');
local zoneNames = require('zone_names');
local mobs = require('winxi.mobs');

local data = nil;      -- the area's tables: { Indices = { [index] = monster }, Names = { [name] = monster } }
local zoneKnown = false;
local unread = nil;    -- why the area's names could not be read from the game's files, where they could not
local placeholders = {}; -- notorious monster's name -> { [index] = true }, from the placeholders folder
local notorious = nil;   -- their names in order, made when first asked for
local written = {};    -- monster -> what is written for it
local checked = {};    -- index -> { id = the monster's server id, text = its level }, for those checked
local checkedCount = 0;
local generation = 0;

-- The game's answer to /check: a message about a target, with the level and how hard a fight it is
local MESSAGE          = 0x029;
local MESSAGE_TARGET   = 0x08; -- the target's server id
local MESSAGE_VALUE    = 0x0C; -- for a check, its level
local MESSAGE_VALUE2   = 0x10; -- for a check, 0x40 (too weak) to 0x47 (incredibly tough)
local MESSAGE_INDEX    = 0x16; -- the target's index
local MESSAGE_NUMBER   = 0x18;
local CHECK_FIRST, CHECK_LAST = 170, 178; -- the nine answers, by the monster's defence and evasion
local HARD_FIRST, HARD_LAST   = 0x40, 0x47;
local KEPT_FOR                = 300;      -- seconds a check is kept
local NO_GAUGE                = 249;      -- the answer for a monster whose strength is impossible to gauge

-- How hard a fight the answer says it is, from HARD_FIRST on, in the game's words
local HARD = { 'Too Weak', 'Incredibly Easy Prey', 'Easy Prey', 'Decent Challenge', 'Even Match', 'Tough', 'Very Tough', 'Incredibly Tough' };
local HARD_SHORT = { 'TW', 'IEP', 'EP', 'DC', 'EM', 'T', 'VT', 'IT' };
local HARD_NO_GAUGE = 'Impossible To Gauge';
local DEFEATED, FALLS         = 6, 20;    -- the messages that say a target has died
local SPAWNED                 = 0x200;    -- GetRenderFlags0: the client is showing this entity

local function forget(index)
    if (checked[index] ~= nil) then
        checked[index] = nil;
        checkedCount = checkedCount - 1;
        generation = generation + 1;
    end
end

-- Said to be defeated: kept for its body, until levels.Tidy sees it gone. Its health may not yet
-- read 0 as this comes, so that is left for levels.Tidy to see (known.dead).
local function defeated(index)
    local known = checked[index];
    if (known ~= nil) then
        known.defeated = true;
    end
end

local function forgetAll()
    if (checkedCount > 0) then
        checked, checkedCount = {}, 0;
    end
    generation = generation + 1;
end

function levels.Generation()
    return generation;
end

function levels.Set(tables, spawnNames, zone, lots)
    data = tables;
    placeholders, notorious = {}, nil;
    for name, indices in pairs(lots or {}) do
        local set = {};
        for _, index in ipairs(indices) do set[index] = true; end
        placeholders[name] = set;
    end
    -- Production supplies the game's own list of the area's names. Indices in level data are
    -- sparse stat exceptions, not a spawn catalogue. The fallback is for explicit test/injected tables.
    -- zone, if given, lets the list be checked against the zone's own monsters as they are met.
    unread = nil;
    mobLetters.Set(spawnNames ~= nil and spawnNames or (tables ~= nil and tables.Indices or nil), zone);
    written = {};
    zoneKnown = true;
    generation = generation + 1;
end

-- The tables of an area, and of the part of it the player is in if that has tables of its own
local function load(zone, subZone)
    local tables = mobs.Zone(zone, subZone);

    -- The game's own list, read from its files. One that cannot be read must never silently fall
    -- back to sparse exception indices: there are then no letters, and the reason is kept to be told.
    local spawnNames, why = nil, nil;
    if (zone ~= nil and zone ~= 0) then
        spawnNames, why = zoneNames.Read(zone);
    end
    levels.Set(tables, spawnNames or {}, zone, mobs.Placeholders(zone));
    if (spawnNames == nil and why ~= nil and zone ~= nil and zone ~= 0) then
        unread = ('Mob Letters: this area\'s names could not be read from the game\'s files (%s). There are no letters here.'):format(why);
    end
end

-- A monster that was checked is forgotten the moment it is gone, however that is learnt: here by
-- looking, each frame, at the few there are. One that died is gone once the client no longer shows
-- it, or once its place is alive again (it was respawned while out of sight). One that lives is
-- kept though it goes out of sight.
function levels.Tidy()
    if (checkedCount == 0) then
        return;
    end

    local entities = AshitaCore:GetMemoryManager():GetEntity();
    if (entities == nil) then
        return;
    end
    local now = os.clock();
    for index, known in pairs(checked) do
        local hp = entities:GetHPPercent(index);
        if (hp == 0) then
            known.dead = true;
        end
        local gone = now - known.at > KEPT_FOR or entities:GetServerId(index) ~= known.id;
        if (not gone and (known.dead or known.defeated)) then
            local flags = entities.GetRenderFlags0 ~= nil and entities:GetRenderFlags0(index) or nil;
            gone = (known.dead and hp ~= 0) or (type(flags) == 'number' and bit.band(flags, SPAWNED) == 0);
        end
        if (gone) then
            forget(index);
        end
    end
end

function levels.Checked(index, id)
    local known = checked[index];
    if (known ~= nil and (id == nil or known.id == id)) then
        return known;
    end
    return nil;
end

-- loaded after the area was entered: the area is asked of the game, the once
local function ensure()
    if (not zoneKnown) then
        local ok, zone = pcall(function ()
            return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
        end);
        load(ok and zone or 0, nil);
    end
end

function levels.Notorious()
    ensure();
    if (notorious == nil) then
        local seen = {};
        notorious = {};
        local function add(name)
            if (type(name) == 'string' and name ~= '' and not seen[name]) then
                seen[name] = true;
                notorious[#notorious + 1] = name;
            end
        end
        for _, part in ipairs({ 'Names', 'Indices' }) do
            for key, monster in pairs(data ~= nil and data[part] or {}) do
                if (type(monster) == 'table' and monster.Notorious) then
                    add(monster.Name or (type(key) == 'string' and key or nil));
                end
            end
        end
        -- one the server draws by lot is to be found though its table does not call it notorious
        for name in pairs(placeholders) do add(name); end
        table.sort(notorious, function (a, b) return a:lower() < b:lower(); end);
    end
    return notorious;
end

function levels.Placeholders(name)
    ensure();
    return placeholders[name];
end

function levels.Monster(index, name)
    ensure();
    if (data == nil) then
        return nil;
    end

    return mobs.Find(data, index, name);
end

-- Uses the full zone catalogue, including spawn slots no client has seen yet.
-- Checking, death, draw order and respawning do not renumber those slots.
function levels.Letter(index, name, id, double)
    levels.Monster(index, name); -- ensure the current zone tables have been loaded
    return mobLetters.Of(index, name, id, double);
end

-- What levels.Letter says changes with this, so the generation does too
function levels.DoubleLetters(on)
    if (mobLetters.Double(on)) then
        generation = generation + 1;
    end
end

function levels.LetterPairs()
    return mobLetters.Pairs();
end

-- A sentence for the user while the area's names are not to be had, or are not what the game shows, or nil
function levels.RosterProblem()
    return mobLetters.Problem() or unread;
end

function levels.Of(index, name, id)
    -- one checked and found impossible to gauge has no level of its own
    local known = levels.Checked(index, id);
    if (known ~= nil and known.text ~= nil) then
        return known.text;
    end

    local monster = levels.Monster(index, name);
    if (monster == nil) then
        return nil;
    end

    local found = written[monster];
    if (found == nil) then
        local low, high = tonumber(monster.MinLevel) or 0, tonumber(monster.MaxLevel) or 0;
        if (low <= 0 and high <= 0) then
            found = false;
        elseif (low == high or high <= 0) then
            found = tostring(low);
        else
            found = ('%d-%d'):format(low, high);
        end
        written[monster] = found;
    end
    return found or nil;
end

function levels.HandlePacket(e)
    -- the area being entered, and the part of it: nothing that was checked is there any more
    if (e.id == 0x00A) then
        forgetAll();
        load(struct.unpack('H', e.data, 0x30 + 1), struct.unpack('H', e.data, 0x9E + 1));
        return;
    end

    if (e.id ~= MESSAGE) then
        return;
    end

    local number = struct.unpack('H', e.data, MESSAGE_NUMBER + 1);
    local index = struct.unpack('H', e.data, MESSAGE_INDEX + 1);

    if (number == DEFEATED or number == FALLS) then
        defeated(index);
    elseif (number >= CHECK_FIRST and number <= CHECK_LAST) then
        local level = struct.unpack('I', e.data, MESSAGE_VALUE + 1);
        local hard = struct.unpack('I', e.data, MESSAGE_VALUE2 + 1);
        -- other messages have these numbers' neighbours: only an answer to a check has both of these
        if (hard >= HARD_FIRST and hard <= HARD_LAST and level >= 1 and level <= 255 and index > 0) then
            if (checked[index] == nil) then
                checkedCount = checkedCount + 1;
            end
            checked[index] = { id = struct.unpack('I', e.data, MESSAGE_TARGET + 1), text = tostring(level), hard = HARD[hard - HARD_FIRST + 1], hardShort = HARD_SHORT[hard - HARD_FIRST + 1], at = os.clock() };
            generation = generation + 1;
        end
    elseif (number == NO_GAUGE and index > 0) then
        -- checked all the same, though nothing is learnt of its level
        if (checked[index] == nil) then
            checkedCount = checkedCount + 1;
        end
        checked[index] = { id = struct.unpack('I', e.data, MESSAGE_TARGET + 1), text = nil, hard = HARD_NO_GAUGE, hardShort = '???', at = os.clock() };
        generation = generation + 1;
    end
end

return levels;
