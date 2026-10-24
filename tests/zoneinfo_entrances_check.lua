-- Dungeon entrances (data/entrances.lua, from the server's zone lines) and the distance each kind of
-- zone announces from. Pure: the transform is synthetic, the places the generated data's own.
package.path = 'addons/zone/?.lua;' .. package.path;
local g = require('area_geometry');
local tracking = require('area_tracking');
local entrances = require('data.entrances');
local checks = 0;
local function check(label, value)
    assert(value, label);
    checks = checks + 1;
end

local total, numbered = 0, 0;
for zone, list in pairs(entrances) do
    for _, e in ipairs(list) do
        total = total + 1;
        if e.label then numbered = numbered + 1; end
        check(('entrance %d:%s is a place with a dungeon'):format(zone, e.id), g.finite(e.x) and g.finite(e.y)
            and g.finite(e.z) and type(e.to) == 'number' and type(e.to_name) == 'string' and e.to_name ~= '');
    end
end
check('every entrance into a dungeon from open country or a city', total == 184);
check('most carry the number their map gives them', numbered == 123);

local function find(zone, id)
    for _, e in ipairs(entrances[zone]) do if e.id == id then return e; end end
end
local sinkhole = find(125, 'z3hc');
check('the map\'s number is in the name', tracking.entrance_name(sinkhole) == 'Quicksand Caves Entrance 7');
check('and the name the map gives the place', tracking.entrance_name(find(116, 'z388'))
    == 'Outer Horutoto Ruins Entrance 6 (Lilac Tower)');
check('an entrance the map does not number has none', tracking.entrance_name(find(100, 'z2s8')) == 'Ghelsba Outpost Entrance');

check('a city is announced from closer in than a dungeon, a dungeon than open country',
    tracking.APPROACH.city < tracking.APPROACH.dungeon and tracking.APPROACH.dungeon < tracking.APPROACH.outdoors);
check('an entrance from closer in than open country', tracking.ENTRANCE.yalms < tracking.APPROACH.outdoors);
check('the kinds', tracking.kind(125) == 'outdoors' and tracking.kind(230) == 'city' and tracking.kind(193) == 'dungeon'
    and tracking.kind(99999) == 'outdoors');

-- Western Altepa Desert, one map yalm to the pixel round its middle.
local entry = { scale = 5, offset_x = -512, offset_y = -512, floor_id = 0 };
local c = tracking.new({ get_entry = function() return entry; end });
c.state.enabled = true;
c:set_zone(125, 0, 0);
c.announce_after = 0;
local function at(x, y, z, now) return c:sample(125, { x = x, y = y, z = z }, now); end
local time = 0;
local function stand(x, y, z)
    local said;
    for _ = 1, 8 do time = time + .25; said = at(x, y, z, time) or said; end
    return said;
end
stand(sinkhole.x + 200, sinkhole.y + 200, sinkhole.z);
local said = stand(sinkhole.x + 12, sinkhole.y, sinkhole.z + 2);
check('walking up to it announces it', said and said.name == 'Quicksand Caves Entrance 7' and said.entrance);
check('in open country', c.state.approach_yalms == tracking.APPROACH.outdoors);
said = stand(sinkhole.x + 21, sinkhole.y, sinkhole.z);
check('a step outside is kept', said == nil and c.state.area and c.state.area.id == 'entrance_z3hc');
stand(sinkhole.x + 40, sinkhole.y, sinkhole.z);
check('further off it is left', c.state.area == nil or c.state.area.id ~= 'entrance_z3hc');
stand(sinkhole.x + 200, sinkhole.y + 200, sinkhole.z);
said = stand(sinkhole.x + 5, sinkhole.y, sinkhole.z + 30);
check('far above it, it is not', said == nil or said.id ~= 'entrance_z3hc');

c.state.entrances.enabled = false;
c:reset(time);
stand(sinkhole.x + 200, sinkhole.y + 200, sinkhole.z);
said = stand(sinkhole.x, sinkhole.y, sinkhole.z);
check('turned off, entrances are not announced', said == nil or not said.entrance);
c.state.entrances.enabled = true;

c.state.entrances.yalms = 8;
c:reset(time);
stand(sinkhole.x + 200, sinkhole.y + 200, sinkhole.z);
said = stand(sinkhole.x + 12, sinkhole.y, sinkhole.z);
check('the distance is a setting', said == nil or said.id ~= 'entrance_z3hc');

-- Inside a field feature, the entrance (the smaller) is named; its circle does not reach as far as
-- open country's features do.
local field = { id = 'dunes', name = 'Dunes', polygon = { { 0, 0 }, { 200, 0 }, { 200, 200 }, { 0, 200 } } };
local mouth = tracking.entrance_areas(125, { scale = 5, offset_x = sinkhole.x - 100, offset_y = -sinkhole.y - 100 }, 20);
local here;
for _, area in ipairs(mouth) do if area.id == 'entrance_z3hc' then here = area; end end
check('the entrance lies where the line is', g.contains(here.polygon, 100, 100) and not g.contains(here.polygon, 100, 125));
check('inside a feature, the entrance wins', g.classify({ field, here }, 105, 100, nil, 0, 50, sinkhole.z) == here);
check('its own reach, not open country\'s', g.classify({ here }, 100, 135, nil, 0, 50, sinkhole.z) == nil);
check('made once for a map', tracking.entrance_areas(125, entry, 20) == tracking.entrance_areas(125, entry, 20));

print(('zoneinfo dungeon entrances: %d assertions passed'):format(checks));
