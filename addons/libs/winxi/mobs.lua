-- winxi.mobs: an area's monsters as the server has them, from winxi.gamedata's mobs and placeholders.
--
--     mobs.Zone(zone, subZone)        the area's tables, { Names = { [name] = monster },
--                                     Indices = { [index] = monster } }, or nil; a part of an area
--                                     (numbered 1000 to 1299, as mobdb has it) with tables of its own
--                                     has those
--     mobs.Find(tables, index, name)  one monster of them: by its index, and failing that by its name,
--                                     two of one name in an area being able to be of different levels
--     mobs.Placeholders(zone)         the area's notorious monsters and what each is drawn by lot from,
--                                     { [name] = { index, ... } }, or nil where the server lists none
--
-- A monster is as mobdb has it: Name, Notorious, Aggro, Link, TrueSight, Family, Job, SubJob,
-- MinLevel, MaxLevel, Immunities, Respawn, the senses (Sight, Sound, Blood, Magic, JA, Scent), Drops,
-- Steal, Despoil, Spells and Modifiers. The game tells none of it; the tables are read when asked
-- for, which is once an area for those that keep them, and nothing is kept here.
local gamedata = require('winxi.gamedata');

local mobs = {};

function mobs.Zone(zone, subZone)
    local tables = nil;
    if (type(subZone) == 'number' and subZone >= 1000 and subZone <= 1299) then
        tables = gamedata.Read('mobs', subZone);
    end
    if (tables == nil and type(zone) == 'number' and zone > 0) then
        tables = gamedata.Read('mobs', zone);
    end
    return tables;
end

function mobs.Find(tables, index, name)
    if (tables == nil) then
        return nil;
    end
    return (tables.Indices ~= nil and index ~= nil and tables.Indices[index])
        or (tables.Names ~= nil and name ~= nil and tables.Names[name]) or nil;
end

function mobs.Placeholders(zone)
    if (type(zone) ~= 'number' or zone <= 0) then
        return nil;
    end
    return gamedata.Read('placeholders', zone);
end

return mobs;
