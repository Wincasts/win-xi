-- The levels a monster can be, from the tables of the area it is in.
--
--   levels.Of(index, name)   what to write for the entity with this index and name: '5-6', or '8'
--                            where it can only be the one, or nil if the tables do not have it
--   levels.Set(data)         the tables to look in, for whoever has them some other way
--
-- The game does not tell the client a monster's level. The tables in the data folder say what levels
-- each of an area's monsters can be: they are mobdb's, made from the server's own, and are a copy,
-- so that mobdb need not be there. A monster is looked for by its index, and failing that by its
-- name: two of one name in an area can be of different levels.
--
-- The area's tables are read as the area is entered, and that is all the reading there is.
local levels = {};

local data = nil;      -- the area's tables: { Indices = { [index] = monster }, Names = { [name] = monster } }
local zoneKnown = false;
local written = {};    -- monster -> what is written for it

function levels.Set(tables)
    data = tables;
    written = {};
    zoneKnown = true;
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

function levels.Of(index, name)
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

ashita.events.register('packet_in', 'name_levels_zone', function (e)
    -- the area being entered, and the part of it
    if (e.id == 0x00A) then
        load(struct.unpack('H', e.data, 0x30 + 1), struct.unpack('H', e.data, 0x9E + 1));
    end
end);

return levels;
