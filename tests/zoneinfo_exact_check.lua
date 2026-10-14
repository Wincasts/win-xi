-- Exact areas (buildings): announced on stepping inside, with no approach distance; kept in the save file.
package.path = 'addons/zoneinfo/?.lua;' .. package.path;
local g = require('area_geometry');
local editor_module = require('boundary_editor');
local catalog = require('map_catalog');
local checks = 0;
local function check(label, ok) assert(ok, label); checks = checks + 1; end
local street = { id = 'street', polygon = { { 0, 0 }, { 100, 0 }, { 100, 40 }, { 0, 40 } } };
local shop = { id = 'shop', exact = true, polygon = { { 40, 10 }, { 60, 10 }, { 60, 30 }, { 40, 30 } } };
local pond = { id = 'pond', polygon = { { 200, 10 }, { 220, 10 }, { 220, 30 }, { 200, 30 } } };
local hut = { id = 'hut', exact = true, polygon = { { 300, 10 }, { 320, 10 }, { 320, 30 }, { 300, 30 } } };
local areas = { street, shop, pond, hut };
check('inside the shop is the shop, not the street round it', g.classify(areas, 50, 20, nil, 0, 15) == shop);
check('the order of the areas does not decide it', g.classify({ shop, street }, 50, 20, nil, 0, 15) == shop);
check('a step outside the door is the street', g.classify(areas, 38, 20, nil, 0, 15) == street);
check('leaving the shop gives the street at once', g.classify(areas, 38, 20, 'shop', 3, 15) == street);
check('an ordinary area is announced on approach', g.classify(areas, 190, 20, nil, 0, 15) == pond);
check('a building is not', g.classify(areas, 295, 20, nil, 0, 15) == nil);
check('nor from just outside its wall', g.classify(areas, 299, 20, nil, 0, 15) == nil);
check('it is on its threshold', g.classify(areas, 300, 20, nil, 0, 15) == hut);
check('a sliver of slack keeps it at the wall', g.classify(areas, 299.6, 20, 'hut', 3, 15) == hut);
check('and no more than a sliver', g.classify(areas, 299, 20, 'hut', 3, 15) == nil);
check('a building does not capture a nearby approach', g.classify({ pond, { id = 'kiosk', exact = true,
    polygon = { { 180, 15 }, { 186, 15 }, { 186, 25 }, { 180, 25 } } } }, 190, 20, nil, 0, 15).id == 'pond');
check('size is the polygon area', g.size(shop.polygon) == 400 and g.size(street.polygon) == 4000);

local tracker = g.new_tracker(1.0);
g.update(tracker, nil, 0);
g.update(tracker, 'shop', 10);
check('a building is not taken on its first sample', not g.update(tracker, 'shop', 10.25, 0.3));
check('but is within half a second', g.update(tracker, 'shop', 10.5, 0.3) == true);
g.update(tracker, 'pond', 20);
check('open country still waits its second', not g.update(tracker, 'pond', 20.5) and g.update(tracker, 'pond', 21) == true);

local function small_catalog()
    local a = { key = 'map_a', zone_id = 100, name = 'Test', areas = {
        { id = 'named', name = 'Named', enabled = true, polygon = { { 20, 20 }, { 40, 20 }, { 40, 40 }, { 20, 40 } } },
        { id = 'shop', name = 'Shop', enabled = true, exact = true, polygon = { { 60, 20 }, { 80, 20 }, { 80, 40 }, { 60, 40 } } } } };
    return { maps = { map_a = a }, [100] = a };
end
local path = os.tmpname(); os.remove(path);
local c = small_catalog(); local e = editor_module.new(c, path);
check('built-in kinds are not written', not e:encode():find('e:', 1, true));
e:select('map_a', 'named');
check('an area is made exact', e:set_exact(true) and c.maps.map_a.areas[1].exact == true and e:dirty());
check('the same kind is no change', not e:set_exact(true));
check('undone', e:undo() and c.maps.map_a.areas[1].exact == nil and not e:dirty());
e:set_exact(true); e:limit(nil, 5);
e:select('map_a', 'shop'); e:set_exact(false);
check('saved', e:save() and e:encode():find('named 1 4e616d6564 h:~:5.000 e:1 ', 1, true) ~= nil
    and e:encode():find('shop 1 53686f70 e:0 ', 1, true) ~= nil);
local fresh = small_catalog(); local loaded = editor_module.new(fresh, path);
check('kinds load, with height limits beside them', loaded:load() and fresh.maps.map_a.areas[1].exact == true
    and fresh.maps.map_a.areas[1].z_max == 5 and fresh.maps.map_a.areas[2].exact == nil);
check('round trip', loaded:encode() == e:encode());
loaded:select('map_a', 'shop');
check('restore default brings the built-in kind back', loaded:restore() and fresh.maps.map_a.areas[2].exact == true);
local tail = ' 20 20 40 20 40 40 20 40\n';
check('a file without the field keeps the built-in kind', loaded:decode('zoneinfo-boundaries-v2\nmap_a shop 1 53686f70' .. tail)
    and fresh.maps.map_a.areas[2].exact == true and fresh.maps.map_a.areas[1].exact == nil);
check('either order of fields loads', loaded:decode('zoneinfo-boundaries-v2\nmap_a named 1 4141 e:1 h:1.000:2.000' .. tail)
    and fresh.maps.map_a.areas[1].exact == true and fresh.maps.map_a.areas[1].z_min == 1);
for _, bad in ipairs({ 'e:2', 'e:', 'e:1 e:0', 'q:1', 'h:1:2 h:1:2' }) do
    check('malformed field rejected: ' .. bad, not loaded:decode('zoneinfo-boundaries-v2\nmap_a named 1 4141 ' .. bad .. tail));
end
os.remove(path); os.remove(path .. '.bak');

-- The traced buildings themselves.
local buildings, cities = 0, {};
for _, map in ipairs(catalog.list) do
    for _, area in ipairs(map.areas) do
        if area.exact then
            buildings = buildings + 1; cities[map.zone_id] = true;
            check('a building is a valid polygon', editor_module.valid(area.polygon));
            check('a building is building-sized', g.size(area.polygon) >= 20 and g.size(area.polygon) <= 8000);
            check('a building is named', type(area.name) == 'string' and #area.name > 2 and area.id ~= 'draft_area');
            local cx, cy = 0, 0;
            for _, p in ipairs(area.polygon) do cx, cy = cx + p[1] / #area.polygon, cy + p[2] / #area.polygon; end
            if g.contains(area.polygon, cx, cy) then
                local found = g.classify(map.areas, cx, cy, nil, 0, 15);
                -- Inside a building you are in it, or in a smaller one drawn inside it.
                check('standing in a building announces a building', found ~= nil and found.exact == true
                    and g.size(found.polygon) <= g.size(area.polygon));
            end
        end
    end
end
local count = 0; for _ in pairs(cities) do count = count + 1; end
check('163 buildings in 24 cities and towns', buildings == 163 and count == 24);
print(('zoneinfo exact areas and buildings: %d assertions passed'):format(checks));
