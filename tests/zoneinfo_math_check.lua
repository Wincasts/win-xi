-- Pure tests: no game or graphics required. Coordinates/transforms here are synthetic.
package.path = 'addons/zone/?.lua;' .. package.path;
local g = require('area_geometry');
local tracking = require('area_tracking');
local position = require('map_position');
local definitions = require('data.poc_areas');
local checks = 0;
local function check(label, value)
    assert(value, label);
    checks = checks + 1;
end
local function near(a, b) return math.abs(a - b) < 0.00001; end
local entry = { scale = 5, offset_x = -256, offset_y = -256, floor_id = 0, source = 'test' };
local x, y = g.world_to_map(entry, 20, -30);
check('scale/offset/axis transform', x == 276 and y == 286);
local wx, wy = g.map_to_world(entry, x, y);
check('inverse transform', near(wx, 20) and near(wy, -30));
local negative = { scale = -5, offset_x = -256, offset_y = -256 };
local nx, ny = g.world_to_map(negative, 20, -30);
check('signed scale uses magnitude like Boussole', nx == x and ny == y);
check('zero scale rejected', g.world_to_map({ scale = 0, offset_x = 0, offset_y = 0 }, 0, 0) == nil);
check('nonfinite positions rejected', not g.finite(0 / 0) and not g.finite(math.huge));

local square = { { 0, 0 }, { 10, 0 }, { 10, 10 }, { 0, 10 } };
check('polygon interior', g.contains(square, 5, 5));
check('polygon exterior', not g.contains(square, 11, 5));
check('polygon edge and vertex', g.contains(square, 0, 5) and g.contains(square, 10, 10));
check('edge distance', near(g.edge_distance(square, 12, 5), 2));
local concave = { { 0, 0 }, { 10, 0 }, { 10, 4 }, { 4, 4 }, { 4, 10 }, { 0, 10 } };
check('concave polygon does not fill missing corner', not g.contains(concave, 8, 8) and g.contains(concave, 2, 8));
local areas = { { id = 'a', polygon = square } };
check('unlabelled remains unlabelled', g.classify(areas, 40, 40, nil, 3) == nil);
check('hysteresis retains current outside edge', g.classify(areas, 12, 5, 'a', 3).id == 'a');
check('hysteresis does not extend entry boundary', g.classify(areas, 12, 5, nil, 3) == nil);
check('hysteresis releases beyond margin', g.classify(areas, 14, 5, 'a', 3) == nil);
check('approach enters before feature boundary', g.classify(areas, 15, 5, nil, 0, 6).id == 'a');
check('approach remains finite', g.classify(areas, 17, 5, nil, 0, 6) == nil);
check('approach has rounded corners, not an expanded bounding box', g.classify(areas, 15, 15, nil, 0, 6) == nil);
local nearby = { areas[1], { id = 'b', polygon = { { 20, 0 }, { 30, 0 }, { 30, 10 }, { 20, 10 } } } };
check('overlapping approach buffers choose closest feature', g.classify(nearby, 18, 5, nil, 0, 10).id == 'b');
check('stable buffer membership avoids overlap chatter', g.classify(nearby, 18, 5, 'a', 3, 10).id == 'a');
check('entering actual feature overrides neighbouring buffer', g.classify(nearby, 25, 5, 'a', 3, 20).id == 'b');
local outline = g.approach_outline(square, 6);
check('debug approach outline generated', #outline > 0);
check('zero approach needs no buffer outline', #g.approach_outline(square, 0) == 0);

local t = g.new_tracker(1);
check('initial sample does not announce', not g.update(t, nil, 0));
check('entry starts debounce', not g.update(t, 'a', 0.2));
check('brief entry does not announce', not g.update(t, nil, 0.7) and t.current == nil);
g.update(t, 'a', 1);
check('entry waits full delay', not g.update(t, 'a', 1.8));
check('stable entry commits once', g.update(t, 'a', 2.1) and t.current == 'a');
check('same area does not repeat', not g.update(t, 'a', 3));
g.update(t, nil, 4);
check('nil exit is debounced', not g.update(t, nil, 4.5));
check('stable exit clears', g.update(t, nil, 5.1) and t.current == nil);
g.reset(t);
check('reset seeds current silently', not g.update(t, 'a', 6) and t.current == 'a');

local calls = 0;
local reader = { get_entry = function() calls = calls + 1; return entry; end };
local c = tracking.new(reader);
check('open country is announced from further off than a dungeon, a dungeon than a town',
    c.state.approach.outdoors == 50 and c.state.approach.dungeon == 15 and c.state.approach.city == 10);
c.state.approach.outdoors = 30; -- The places below were laid out for a 30-yalm buffer.
c.state.enabled = true;
local function sample(map_x, map_y, at, zone)
    local px, py = g.map_to_world(entry, map_x, map_y);
    return c:sample(zone or 100, { x = px, y = py, z = 10 }, at);
end
check('zone entry waits for memory', sample(200, 300, 0) == nil and c.state.map_x == nil);
sample(200, 300, 1.1);
check('unlabelled terrain initializes nil', c.state.area == nil);
sample(238, 337, 2);
check('area transition waits behind zone banner', sample(238, 337, 3.1) == nil and c.state.area.id == 'knightwell');
check('queued stable area announces after zone banner', sample(238, 337, 6.1).id == 'knightwell');
check('controller does not spam', sample(238, 337, 7) == nil);
check('the zone\'s kind sets the buffer, in world yalms', c.state.approach_yalms == 30 and c.state.approach_pixels == 30);
sample(200, 300, 8); sample(200, 300, 9.1);
check('stable exit does not invent a name', c.state.area == nil);
sample(238, 337, 10);
check('reentry can announce', sample(238, 337, 11.1).id == 'knightwell');
c:sample(100, nil, 12);
check('missing player clears stale marker/area', c.state.map_x == nil and c.state.area == nil);
check('recovery reseeds without duplicate banner', sample(238, 337, 13) == nil and c.state.area.id == 'knightwell');
c:set_zone(103, 14, 0);
sample(57, 225, 14, 103);
check('zone change cannot carry old area', c.state.area.id == 'secret_sands');
sample(57, 225, 15, 999);
check('unsupported zone fails closed', c.state.area == nil and c.state.entry == nil);

c:set_zone(100, 16, 0);
c.state.editing = true;
sample(238, 337, 16);
check('vertex dragging pauses membership but retains map coordinates', c.state.area == nil and c.state.map_x == 238);
c.state.editing = false;
check('release reseeds without editing-induced announcement', sample(238, 337, 17) == nil and c.state.area.id == 'knightwell');

local small_entry = { scale = 2, offset_x = -256, offset_y = -256, floor_id = 0 };
local small = tracking.new({ get_entry = function() return small_entry; end });
small.state.debug = true;
small.state.approach.outdoors = 30;
small:set_zone(100, 0, 0);
local sx, sy = g.map_to_world(small_entry, 260, 337);
small:sample(100, { x = sx, y = sy, z = 0 }, 0);
check('approach buffer scales with map transform, not raster resolution', near(small.state.approach_pixels, 12));
check('player approaching pond matches before core containment', small.state.raw_area and small.state.raw_area.id == 'knightwell'
    and not g.contains(definitions[100].areas[1].polygon, 260, 337));

local attempts = 0;
local bad = tracking.new({ get_entry = function() attempts = attempts + 1; return nil, 'missing signature'; end });
bad.state.debug = true;
bad:set_zone(100, 0, 0);
for i = 0, 4 do bad:sample(100, { x = 0, y = 0, z = 0 }, i); end
check('signature failures back off rather than scan each frame', attempts == 1 and bad.state.area == nil);
bad:sample(100, { x = 0, y = 0, z = 0 }, 5);
check('signature retry after five seconds', attempts == 2);

local memory = {
    find = function() return 1000; end,
    read_uint32 = function(address) assert(address == 1028); return 2000; end,
    read_uint16 = function(address)
        if address == 2000 then return 100; end
        if address == 2010 or address == 2012 then return 65536 - 256; end
        error('unexpected address');
    end,
    read_uint8 = function(address)
        if address == 2002 then return 0; end
        if address == 2005 then return 251; end -- signed -5
        error('unexpected address');
    end,
};
local r = position.new(memory);
local e = r:get_entry(100);
check('live adapter reads signed scale and offsets', e.scale == -5 and e.offset_x == -256 and e.offset_y == -256);
check('unknown zone never reads arbitrary memory', r:get_entry(999) == nil);
local mismatch = position.new({ find = memory.find, read_uint32 = memory.read_uint32,
    read_uint16 = function() return 999; end, read_uint8 = function() return 0; end });
check('mismatched table entry refused', mismatch:get_entry(100) == nil);
local failed = position.new({ find = function() return 0; end });
check('missing signature refused', failed:get_entry(100) == nil);
check('manual fallback works only for supported zone', failed:set_override(100, 5, -256, -256)
    and failed:get_entry(100).scale == 5 and not failed:set_override(999, 5, 0, 0));
check('invalid manual transform refused', not failed:set_override(100, 0, 0, 0) and not failed:set_override(100, math.huge, 0, 0));
function GetPlayerEntity() return { Movement = { LocalPosition = { X = 1, Y = 2, Z = 3 } } }; end
check('player position uses X/Y horizontal and Z height', position.player_position().z == 3);
function GetPlayerEntity() return {}; end
check('missing movement safely rejected', position.player_position() == nil);

local count = 0;
for _, def in pairs(definitions) do
    for _, area in ipairs(def.areas) do
        count = count + 1;
        check('each test polygon has at least three vertices', #area.polygon >= 3);
        for _, point in ipairs(area.polygon) do
            check('each test vertex lies in reference image', point[1] >= 0 and point[1] <= 512 and point[2] >= 0 and point[2] <= 512);
        end
    end
end
check('three-zone seven-area POC, and the outpost added to Valkurm', count == 8);
print(('zoneinfo geometry/transform/tracker: %d assertions passed'):format(checks));
