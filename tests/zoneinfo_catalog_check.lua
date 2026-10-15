package.path = 'addons/zone/?.lua;' .. package.path;
local catalog = require('map_catalog');
local geometry = require('area_geometry');
local editor_module = require('boundary_editor');
local position = require('map_position');
local checks = 0;
local function check(label, ok) assert(ok, label); checks = checks + 1; end
local maps, zones, areas, indexed, named, disabled = 0, 0, 0, 0, 0, 0;
for _, map in ipairs(catalog.list) do
    maps = maps + 1;
    check('unique map key', catalog.maps[map.key] == map);
    check('correct zone association', catalog.by_zone[map.zone_id] ~= nil);
    if map.table_index ~= nil then indexed = indexed + 1; end
    local ids = {};
    for _, area in ipairs(map.areas) do
        areas = areas + 1;
        check('no duplicate area ID on one raster', not ids[area.id]); ids[area.id] = true;
        check('every generated polygon is valid', editor_module.valid(area.polygon));
        if area.enabled == false then disabled = disabled + 1; end
        if area.id ~= 'draft_area' then named = named + 1; end
    end
end
for _ in pairs(catalog.by_zone) do zones = zones + 1; end
check('all unique supplied maps covered', maps == 494 and zones == 204);
check('all reviewed names plus unnamed editor drafts', areas == 833 and named == 417 and disabled == 425);
check('only matched client indices used', indexed == 469);
check('untouched POC primary shapes retained', catalog[100].poc and catalog[100].areas[1].polygon[1][1] == 226);
local patches = require('data.boundary_refinements');
local examples, inferred = 0, 0;
for _, patch in ipairs(patches) do
    local map = catalog.maps[patch.map_key]; local area;
    for _, candidate in ipairs(map.areas) do if candidate.id == patch.area_id then area = candidate; end end
    check('refinement addresses exact raster/area', area ~= nil);
    check('refinement preserves detection flag', area.enabled == patch.enabled);
    check('refinement preserves exact vertices', #area.polygon == #patch.polygon);
    for i, point in ipairs(patch.polygon) do
        check('refinement vertex unchanged', area.polygon[i][1] == point[1] and area.polygon[i][2] == point[2]);
    end
    if patch.method == 'player_authored_example' then examples = examples + 1; else inferred = inferred + 1; end
end
check('27 player examples and 383 drawn, traced or inherited shapes', examples == 27 and inferred == 383);
local north = catalog[106]; local creek;
for _, area in ipairs(north.areas) do if area.id == 'zeikt_creek' then creek = area; end end
check('traced creek follows bend instead of label oval', geometry.contains(creek.polygon, 150, 247)
    and not geometry.contains(creek.polygon, 150, 233));
check('disabled drafts never classify', geometry.classify({ { id = 'draft', enabled = false,
    polygon = { { 0, 0 }, { 10, 0 }, { 10, 10 }, { 0, 10 } } } }, 5, 5, 'draft', 10, 10) == nil);

local browser = require('map_browser').new(catalog);
browser:sync(100, catalog[100].key);
check('browser initially follows live map', browser:is_live({ zone = 100, map_key = catalog[100].key }));
local multiple;
for _, zone in ipairs(catalog.zones) do if #zone.maps > 1 and zone.id ~= 100 then multiple = zone; break; end end
browser:choose_zone(multiple.id);
browser:choose_map(multiple.maps[#multiple.maps].key);
local chosen = browser.map_key;
browser:sync(103, catalog[103].key);
check('manual browsing survives live zone changes', browser.map_key == chosen and not browser.follow[1]);
check('remote map cannot show live marker', not browser:is_live({ zone = 103, map_key = catalog[103].key }));
browser.follow[1] = true; browser:sync(103, catalog[103].key);
check('follow resumes correct live map', browser.map_key == catalog[103].key);

local function small_catalog()
    local a = { key = 'map_a', zone_id = 100, name = 'Test', areas = { { id = 'named', name = 'Named', enabled = true,
        polygon = { { 20, 20 }, { 40, 20 }, { 40, 40 }, { 20, 40 } } } } };
    local b = { key = 'map_b', zone_id = 100, name = 'Test', areas = { { id = 'named', name = 'Named', enabled = false,
        polygon = { { 50, 50 }, { 70, 50 }, { 70, 70 }, { 50, 70 } } } } };
    return { maps = { map_a = a, map_b = b }, [100] = a };
end
local path = os.tmpname(); os.remove(path);
local c = small_catalog(); local e = editor_module.new(c, path);
e:select('map_b', 'named'); e:begin(1); e:move(45, 50); e:finish();
check('same-name areas on different maps stay independent', c.maps.map_a.areas[1].polygon[1][1] == 20);
check('configure name and detection', e:configure("Test area's courtyard", true));
check('insert midpoint vertex', e:vertices(true) and #e.selected.polygon == 5);
check('remove selected vertex', e:vertices(false) and #e.selected.polygon == 4);
check('vertex removal is undoable', e:undo() and #e.selected.polygon == 5);
check('add another named area on same map', e:add('map_b', 'Another room'));
check('new area is dirty immediately', e:dirty());
check('v2 save succeeds', e:save() and not e:dirty());
local text = e:encode(); check('v2 format writes map identities', text:find('zoneinfo%-boundaries%-v2') == 1 and text:find('map_b', 1, true));
local fresh = small_catalog(); local loaded = editor_module.new(fresh, path);
check('v2 reload validates entire file', loaded:load());
check('v2 preserves geometry/name/enable', fresh.maps.map_b.areas[1].polygon[1][1] == 45
    and fresh.maps.map_b.areas[1].name == "Test area's courtyard" and fresh.maps.map_b.areas[1].enabled
    and #fresh.maps.map_b.areas[1].polygon == 5);
check('v2 persists custom area', #fresh.maps.map_b.areas == 2 and fresh.maps.map_b.areas[2].name == 'Another room');
check('v2 does not leak edits to another map', fresh.maps.map_a.areas[1].polygon[1][1] == 20);
local before = loaded:encode();
check('invalid map rejected atomically', not loaded:decode(text .. 'bad_map named 1 4141 0 0 10 0 10 10\n') and loaded:encode() == before);
check('duplicate map/area rejected', not loaded:decode(text .. text:match('(map_b named[^\n]+)') .. '\n'));
check('malformed name rejected', not loaded:decode('zoneinfo-boundaries-v2\nmap_b named 1 zz 0 0 10 0 10 10\n'));
check('invalid enable flag rejected', not loaded:decode('zoneinfo-boundaries-v2\nmap_b named 2 4141 0 0 10 0 10 10\n'));
check('legacy edits migrate to primary map only', loaded:decode('zoneinfo-boundaries-v1\n100 named 15 20 40 20 40 40 20 40\n')
    and fresh.maps.map_a.areas[1].polygon[1][1] == 15 and fresh.maps.map_b.areas[1].polygon[1][1] == 50
    and #fresh.maps.map_b.areas == 1);
check('legacy migration preserves original flags', fresh.maps.map_b.areas[1].enabled == false);
check('unknown custom map rejected without side effects', not loaded:add('missing', 'Test'));
os.remove(path); os.remove(path .. '.tmp'); os.remove(path .. '.bak');

-- Multi-floor selection uses a mocked native call, not a real FFI function.
local zone;
for id, floors in pairs(catalog.primary_by_floor) do
    local count = 0; for _ in pairs(floors) do count = count + 1; end
    if count > 1 then zone = id; break; end
end
local floor; for f in pairs(catalog.primary_by_floor[zone]) do floor = f; break; end
local memory = { find = function() return 0; end, read_uint32 = function(address) return address == 123 and 456 or 789; end };
local reader = position.new(memory);
reader.floor_pointer, reader.ffi = 123, { cast = function(_, value) return value; end };
reader.floor_func = function(object, x, height, y)
    check('floor call uses X/Z/Y convention', object == 789 and x == 1 and height == 3 and y == 2);
    return floor;
end;
check('multi-floor picks matching raster', reader:get_definition(zone, { x = 1, y = 2, z = 3 }).floor_id == floor);
local no_floor = position.new(memory);
check('missing floor signature fails closed', no_floor:get_definition(zone, { x = 1, y = 2, z = 3 }) == nil);
reader.live_map = catalog.primary_by_floor[zone][floor].key;
check('explicit live override avoids native selection', reader:get_definition(zone, nil).key == reader.live_map);
check('single-map zone does not require native call', no_floor:get_definition(100, { x = 0, y = 0, z = 0 }).poc);
check('missing pack floors do not bypass native floor selection', catalog[5].client_floor_count > 1
    and no_floor:get_definition(5, { x = 0, y = 0, z = 0 }) == nil);
print(('zoneinfo all-map catalogue/browser/storage/floors: %d assertions passed'):format(checks));
