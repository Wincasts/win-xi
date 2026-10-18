-- Experimental, deterministic letters for zone spawn slots, not encounter order.
-- All users with the same zone tables sort the same name groups by entity index.
-- No visible-entity scan, network messages, or discovery-order state is involved.
--
-- The roster is the game's own list of the zone's names (zone_names.lua), the same for
-- every client of one server. A monster of this zone standing in a slot the list lacks,
-- or under another name than the list's, says so: the server has renamed it, or the files
-- read are not the ones the game uses. That is reported once per zone and kept for
-- letters.Problem(). Nothing is rebuilt from it: no client sees a whole zone, so a list
-- mended from what one player has met would differ from another's.
local letters = {};
local assigned = {};
local zone = nil;    -- the zone the roster is of, while it has one to check against
local noted = {};    -- index -> true, for slots already found to differ
local double = false; -- past z: aa, ab and on, in place of a again
local longest = 0;   -- how many slots the name with the most has
local labels = { [false] = {}, [true] = {} }; -- a slot's place among its name's -> what is written for it
local stale = nil;   -- { count, index, name, expected = the list's name, or nil for a slot it lacks }

-- What is written for the slot at this place among those of its name, the first being 0. Past the
-- twenty-sixth it is a again, or with double letters aa, ab and on to zz, and then aa again.
local function label(place, mode)
    if (mode == nil) then mode = double; end
    local kept = labels[mode];
    local text = kept[place];
    if (text == nil) then
        if (place < 26 or not mode) then
            text = string.char(97 + place % 26);
        else
            local pair = (place - 26) % 676;
            text = string.char(97 + math.floor(pair / 26), 97 + pair % 26);
        end
        kept[place] = text;
    end
    return text;
end

-- Whether a name with more than 26 slots goes on to double letters. True if that changed.
function letters.Double(on)
    on = on == true;
    if (double == on) then return false; end
    double = on;
    return true;
end

-- How many double letters the zone needs, aa being the first: none unless they are on
function letters.Pairs()
    return double and math.max(0, math.min(676, longest - 26)) or 0;
end

function letters.Set(indices, zoneId)
    assigned = {};
    longest = 0;
    zone, noted, stale = nil, {}, nil;
    local groups = {};
    for index, mob in pairs(indices or {}) do
        local name = type(mob) == 'table' and mob.Name or mob;
        if (type(index) == 'number' and index > 0 and index < 0x900
            and type(name) == 'string' and name ~= '') then
            local group = groups[name] or {};
            groups[name] = group;
            group[#group + 1] = index;
            assigned[index] = { name = name };
            zone = zoneId;
        end
    end
    for _, group in pairs(groups) do
        table.sort(group);
        for ordinal, index in ipairs(group) do
            assigned[index].place = ordinal - 1;
        end
        longest = math.max(longest, #group);
    end
end

-- Only a server id made of this zone and this index is one of the zone's own spawn
-- slots: charmed players, dynamic entities and another zone's leftovers are not.
local function check(index, name, id, known)
    if (zone == nil or noted[index] or type(name) ~= 'string' or name == ''
        or id % 0x1000 ~= index or math.floor(id / 0x1000) % 0x1000 ~= zone) then
        return;
    end
    if (known ~= nil and known.name == name) then return; end
    noted[index] = true;
    if (stale == nil) then
        stale = { count = 0, index = index, name = name, expected = known and known.name or nil };
    end
    stale.count = stale.count + 1;
    if (stale.count == 1) then
        print('\30\81[name]\30\01 ' .. letters.Problem());
    end
end

-- A sentence for the user while this zone's list is known to differ from what the game shows, or nil
function letters.Problem()
    if (stale == nil) then return nil; end
    local first = stale.expected ~= nil
        and ('slot %d is "%s", the game\'s files have "%s"'):format(stale.index, stale.name, stale.expected)
        or ('"%s" in slot %d is not in the game\'s files'):format(stale.name, stale.index);
    local more = stale.count > 1 and (', and %d more'):format(stale.count - 1) or '';
    return ('Mob Letters: this area\'s names in the game\'s files differ from what the game shows (%s%s). Those have no letter, and letters here may not match other players\'.'):format(first, more);
end

function letters.Of(index, name, id, mode)
    local known = assigned[index];
    if (id == nil or id == 0) then return ''; end
    check(index, name, id, known);
    -- Do not label missing/renamed entries by guessing from their ID. Respawns
    -- with the same name in the same slot deliberately keep the same letter.
    if (known == nil or known.name ~= name) then return ''; end
    return label(known.place, mode);
end

return letters;
