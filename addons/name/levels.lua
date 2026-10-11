-- The levels a monster can be, from the tables of the area it is in.
--
--   levels.Of(index, name, id)   what to write for the entity with this index, name and server id:
--                            the level it was found to be when its player checked it; or the levels it
--                            can be, '5-6', or '8' where it can only be the one; or nil if neither is known
--   levels.Generation()      a number that changes whenever what levels.Of would say may have
--   levels.Tidy()            each frame: what was checked and has since died is forgotten
--   levels.Set(data)         the tables to look in, for whoever has them some other way
--
-- The game does not tell the client a monster's level. The tables in the data folder say what levels
-- each of an area's monsters can be: they are mobdb's, made from the server's own, and are a copy,
-- so that mobdb need not be there. A monster is looked for by its index, and failing that by its
-- name: two of one name in an area can be of different levels.
--
-- The area's tables are read as the area is entered, and that is all the reading there is.
--
-- The one time the game does tell a monster's level is in its answer to /check. When the player
-- checks a monster the level in the answer is kept for it, and written in place of what the tables
-- say, until it dies or the player leaves the area: the monster that next has its place is another,
-- of a level of its own. Nothing is asked of the game for this: only its answers are read.
local levels = {};

local data = nil;      -- the area's tables: { Indices = { [index] = monster }, Names = { [name] = monster } }
local zoneKnown = false;
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
local DEFEATED, FALLS         = 6, 20;    -- the messages that say a target has died

local function forget(index)
    if (checked[index] ~= nil) then
        checked[index] = nil;
        checkedCount = checkedCount - 1;
        generation = generation + 1;
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

function levels.Set(tables)
    data = tables;
    written = {};
    zoneKnown = true;
    generation = generation + 1;
end

-- The tables of an area, and of the part of it the player is in if that has tables of its own
local function load(zone, subZone)
    local tables = nil;

    local function read(number)
        local path = ('%sdata/%u.lua'):format(addon.path, number);
        if (not ashita.fs.exists(path)) then
            return nil;
        end
        local chunk = loadfile(path);
        if (chunk == nil) then
            return nil;
        end
        local ok, result = pcall(chunk);
        return ok and type(result) == 'table' and result or nil;
    end

    -- as mobdb has it: a part of an area is numbered from 1000
    if (subZone ~= nil and subZone >= 1000 and subZone <= 1299) then
        tables = read(subZone);
    end
    if (tables == nil and zone ~= nil and zone ~= 0) then
        tables = read(zone);
    end

    levels.Set(tables);
end

-- A monster that was checked is forgotten the moment it is dead or gone, however that is learnt:
-- here by looking, each frame, at the few there are
function levels.Tidy()
    if (checkedCount == 0) then
        return;
    end

    local entities = AshitaCore:GetMemoryManager():GetEntity();
    if (entities == nil) then
        return;
    end
    for index, known in pairs(checked) do
        if (entities:GetServerId(index) ~= known.id or entities:GetHPPercent(index) == 0) then
            forget(index);
        end
    end
end

function levels.Of(index, name, id)
    local known = checked[index];
    if (known ~= nil and (id == nil or known.id == id)) then
        return known.text;
    end

    -- loaded after the area was entered: the area is asked of the game, the once
    if (not zoneKnown) then
        local party = AshitaCore:GetMemoryManager():GetParty();
        load(party ~= nil and party:GetMemberZone(0) or 0, nil);
    end
    if (data == nil) then
        return nil;
    end

    local monster = (data.Indices ~= nil and data.Indices[index]) or (data.Names ~= nil and name ~= nil and data.Names[name]) or nil;
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

ashita.events.register('packet_in', 'name_levels_packet', function (e)
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
        forget(index);
    elseif (number >= CHECK_FIRST and number <= CHECK_LAST) then
        local level = struct.unpack('I', e.data, MESSAGE_VALUE + 1);
        local hard = struct.unpack('I', e.data, MESSAGE_VALUE2 + 1);
        -- other messages have these numbers' neighbours: only an answer to a check has both of these
        if (hard >= HARD_FIRST and hard <= HARD_LAST and level >= 1 and level <= 255 and index > 0) then
            if (checked[index] == nil) then
                checkedCount = checkedCount + 1;
            end
            checked[index] = { id = struct.unpack('I', e.data, MESSAGE_TARGET + 1), text = tostring(level) };
            generation = generation + 1;
        end
    end
end);

return levels;
