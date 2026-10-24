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

local total, numbered, towns = 0, 0, 0;
for zone, list in pairs(entrances) do
    for _, e in ipairs(list) do
        total = total + 1;
        if e.label then numbered = numbered + 1; end
        if e.kind == 'town' then towns = towns + 1; end
        check(('entrance %d:%s is a place with a dungeon'):format(zone, e.id), g.finite(e.x) and g.finite(e.y)
            and g.finite(e.z) and type(e.to) == 'number' and type(e.to_name) == 'string' and e.to_name ~= '');
    end
end
check('every entrance into a dungeon from open country or a city, and into a town', total == 222 and towns == 38);
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
check('a dungeon\'s entrance from closer in than open country', tracking.ENTRANCE.yalms < tracking.APPROACH.outdoors);
check('a town\'s from further off than a dungeon\'s', tracking.ENTRANCE.town_yalms > tracking.ENTRANCE.yalms);
check('a town is named', tracking.entrance_name(find(100, 'z2s0')) == "Southern San d'Oria Entrance" and find(100, 'z2s0').kind == 'town');
check('Jeuno\'s bridges already name the way in', find(110, 'z326') == nil and find(105, 'z2x4') == nil
    and find(120, 'z3c4') == nil and find(126, 'z3i0') ~= nil);
check('both of West Ronfaure\'s ways into Northern San d\'Oria are one entrance', find(100, 'z2s2') ~= nil and find(100, 'z2sa') == nil);
check('Nashmau is a town', find(79, 'z270').kind == 'town');
check('so is Norg, from its grotto', find(176, 'z4w2').kind == 'town');
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
local mouth = tracking.entrance_areas(125, { scale = 5, offset_x = sinkhole.x - 100, offset_y = -sinkhole.y - 100 },
    { enabled = true, yalms = 20, towns = true, town_yalms = 40 });
local here;
for _, area in ipairs(mouth) do if area.id == 'entrance_z3hc' then here = area; end end
check('the entrance lies where the line is', g.contains(here.polygon, 100, 100) and not g.contains(here.polygon, 100, 125));
check('inside a feature, the entrance wins', g.classify({ field, here }, 105, 100, nil, 0, 50, sinkhole.z) == here);
check('its own reach, not open country\'s', g.classify({ here }, 100, 135, nil, 0, 50, sinkhole.z) == nil);
local wanted = { enabled = true, yalms = 20, towns = true, town_yalms = 40 };
check('made once for a map', tracking.entrance_areas(125, entry, wanted) == tracking.entrance_areas(125, entry, wanted));

-- Rabao's gate in Western Altepa: a town, from further off, with a switch of its own.
local rabao = find(125, 'z3h4');
c.state.entrances.yalms = 20;
c:reset(time);
stand(rabao.x + 200, rabao.y + 200, rabao.z);
said = stand(rabao.x + 35, rabao.y, rabao.z);
check('a town is announced from further off', said and said.name == 'Rabao Entrance' and said.entrance == 'town');
c.state.entrances.towns = false;
c:reset(time);
stand(rabao.x + 200, rabao.y + 200, rabao.z);
said = stand(rabao.x, rabao.y, rabao.z);
check('town entrances turn off apart from dungeons\'', said == nil and c.state.entrances.enabled);
c.state.entrances.towns = true;
local only_towns = tracking.entrance_areas(125, entry, { enabled = false, yalms = 20, towns = true, town_yalms = 40 });
check('and dungeons\' apart from towns\'', #only_towns == 1 and only_towns[1].id == 'entrance_z3h4');

-- The Tenshodo, under Lower Jeuno's street: a building, only below street level.
local catalog = require('map_catalog');
local tenshodo;
for _, area in ipairs(catalog[245].areas) do if area.id == 'tenshodo_hq' then tenshodo = area; end end
check('the Tenshodo is on Lower Jeuno\'s map', tenshodo and tenshodo.name == 'Tenshodo H.Q.' and tenshodo.exact and tenshodo.z_min == 1);
local jeuno = { scale = 4, offset_x = -288, offset_y = -208 }; -- the client's own for this map
local hx, hy = g.world_to_map(jeuno, 28.5, -46.7); -- where its merchants stand
check('down among its merchants it is named', g.classify(catalog[245].areas, hx, hy, nil, 0, 10, 3.9) == tenshodo);
check('on the street above it is not', g.classify(catalog[245].areas, hx, hy, nil, 0, 10, -0.1) ~= tenshodo);

-- Re-announce After: time away. A shop inside a square, on a synthetic map one yalm to the pixel.
local square = { id = 'square', name = 'Lion Square', polygon = { { 0, 0 }, { 100, 0 }, { 100, 100 }, { 0, 100 } } };
local inn = { id = 'inn', name = 'Lion Springs Tavern', exact = true, polygon = { { 40, 40 }, { 60, 40 }, { 60, 60 }, { 40, 60 } } };
local town = { key = 'town', areas = { square, inn } };
local flat = { scale = 5, offset_x = 0, offset_y = 0 };
local r = tracking.new({ get_entry = function() return flat; end, get_definition = function() return town; end });
r.state.enabled, r.state.entrances.enabled, r.state.entrances.towns = true, false, false;
r:set_zone(230, 0, 0); r.announce_after = 0;
local clock = 0;
local function walk(x, y, seconds)
    local said = {};
    for _ = 1, seconds * 4 do
        clock = clock + .25;
        local area = r:sample(230, { x = x, y = -y, z = 0 }, clock);
        if area then said[#said + 1] = area.name; end
    end
    return table.concat(said, ',');
end
walk(200, 200, 2);
check('into the square, it is named', walk(20, 20, 3) == 'Lion Square');
check('into the inn, the inn', walk(50, 50, 3) == 'Lion Springs Tavern');
check('out after a moment, the square is not named again', walk(20, 20, 3) == '');
check('back into the inn soon after, nor is the inn', walk(50, 50, 12) == '');
check('out after more than ten seconds inside, the square is', walk(20, 20, 3) == 'Lion Square');
walk(200, 200, 11);
check('away long enough, it is named on return', walk(20, 20, 3) == 'Lion Square');
r.state.reannounce = 0;
walk(50, 50, 3);
check('at 0, every return is named', walk(20, 20, 3) == 'Lion Square');
r.state.reannounce = 10;
walk(200, 200, 2);
r:set_zone(230, clock, 0); r.announce_after = 0;
walk(200, 200, 2);
check('zoning forgets what was left: the square is named at once', walk(20, 20, 3) == 'Lion Square');

print(('zoneinfo dungeon entrances: %d assertions passed'):format(checks));
