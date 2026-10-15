-- Height limits: an area announced only inside a band of elevation, edited, saved and loaded.
package.path = 'addons/zone/?.lua;' .. package.path;
local g = require('area_geometry');
local editor_module = require('boundary_editor');
local checks = 0;
local function check(label, ok) assert(ok, label); checks = checks + 1; end
local square = { { 0, 0 }, { 10, 0 }, { 10, 10 }, { 0, 10 } };
local upper = { id = 'upper', polygon = square, z_min = 5, z_max = 12 };
local lower = { id = 'lower', polygon = square, z_max = 0 };
local open = { id = 'open', polygon = { { 20, 0 }, { 30, 0 }, { 30, 10 }, { 20, 10 } } };
local areas = { upper, lower, open };
check('inside the band is announced', g.classify(areas, 5, 5, nil, 0, 0, 8) == upper);
check('stacked area below is chosen by height', g.classify(areas, 5, 5, nil, 0, 0, -3) == lower);
check('between the bands nothing is announced', g.classify(areas, 5, 5, nil, 0, 0, 3) == nil);
check('an area without limits has every height', g.classify(areas, 25, 5, nil, 0, 0, 500) == open);
check('no sampled height ignores limits', g.classify(areas, 5, 5, nil, 0, 0) == upper);
check('non-finite height ignores limits', g.classify(areas, 5, 5, nil, 0, 0, 0 / 0) == upper);
check('the current area keeps a little slack', g.classify(areas, 5, 5, 'upper', 3, 0, 12.8) == upper);
check('slack is not given on entry', g.classify(areas, 5, 5, nil, 3, 0, 12.8) == nil);
check('slack is finite', g.classify(areas, 5, 5, 'upper', 3, 0, 14) == nil);
check('limits apply in the approach buffer', g.classify(areas, 13, 5, nil, 0, 6, 8) == upper
    and g.classify(areas, 13, 5, nil, 0, 6, 3) == nil);
check('one open side', g.in_height(lower, -1000) and not g.in_height(lower, 0.5));

local function small_catalog()
    local a = { key = 'map_a', zone_id = 100, name = 'Test', areas = { { id = 'named', name = 'Named', enabled = true,
        polygon = { { 20, 20 }, { 40, 20 }, { 40, 40 }, { 20, 40 } } } } };
    return { maps = { map_a = a }, [100] = a };
end
local path = os.tmpname(); os.remove(path);
local c = small_catalog(); local e = editor_module.new(c, path);
e:select('map_a', 'named');
local plain = e:encode();
check('no limits writes the format as before', not plain:find('h:', 1, true));
check('limits are set', e:limit(-4.5, 12) and e.selected.z_min == -4.5 and e.selected.z_max == 12 and e:dirty());
check('the same limits are no change', not e:limit(-4.5, 12));
check('minimum above maximum refused', not e:limit(5, 1) and e.selected.z_min == -4.5);
check('non-finite limit refused', not e:limit(math.huge, nil));
check('limits are undone', e:undo() and e.selected.z_min == nil and e.selected.z_max == nil and not e:dirty());
check('one side may be left open', e:limit(nil, 3) and e.selected.z_min == nil and e.selected.z_max == 3);
check('saved', e:save() and not e:dirty() and e:encode():find('h:~:3.000', 1, true) ~= nil);
local fresh = small_catalog(); local loaded = editor_module.new(fresh, path);
check('limits load', loaded:load() and fresh.maps.map_a.areas[1].z_min == nil and fresh.maps.map_a.areas[1].z_max == 3);
check('limits survive a round trip', loaded:encode() == e:encode());
loaded:select('map_a', 'named');
check('restore default clears limits', loaded:restore() and fresh.maps.map_a.areas[1].z_max == nil);
local head = 'zoneinfo-boundaries-v2\nmap_a named 1 4141 ';
local tail = ' 20 20 40 20 40 40 20 40\n';
check('both sides load', loaded:decode(head .. 'h:-2.500:7.000' .. tail) and fresh.maps.map_a.areas[1].z_min == -2.5
    and fresh.maps.map_a.areas[1].z_max == 7);
check('a file without limits loads as none', loaded:decode(head:sub(1, -2) .. tail) and fresh.maps.map_a.areas[1].z_min == nil);
for _, bad in ipairs({ 'h:~:~', 'h:5:1', 'h:x:1', 'h:1', 'h:1:2:3', 'h:nan:1', 'h:inf:~' }) do
    check('malformed limits rejected: ' .. bad, not loaded:decode(head .. bad .. tail));
end
os.remove(path); os.remove(path .. '.bak');
print(('zoneinfo height limits: %d assertions passed'):format(checks));
