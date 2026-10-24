-- All supplied rasters; multiple variants/floors have independent polygons and save keys.
local catalog = { maps = {}, list = {}, by_zone = {}, zones = {}, primary_by_floor = {} };
local poc = require('data.poc_areas');
local refinements = {};
for _, patch in ipairs(require('data.boundary_refinements')) do
    refinements[patch.map_key] = refinements[patch.map_key] or {};
    refinements[patch.map_key][patch.area_id] = patch;
end
local function score(map)
    local value = map.table_index and 10 or 0;
    for _, area in ipairs(map.areas) do if area.enabled ~= false then value = value + 1; end end
    if map.poc then value = value + 1000; end
    return value;
end
for _, map in ipairs(require('data.all_maps')) do
    local original = poc[map.zone_id];
    if original and original.dat == map.dat then
        map.areas, map.image, map.poc = original.areas, original.image, true;
        for _, area in ipairs(map.areas) do area.provenance = 'existing_POC'; end
    end
    for _, area in ipairs(map.areas) do
        local patch = refinements[map.key] and refinements[map.key][area.id];
        if patch then
            area.polygon, area.enabled, area.provenance = patch.polygon, patch.enabled, patch.method;
            if patch.name then area.name = patch.name; end
            area.exact = patch.exact or nil;
            area.z_min, area.z_max = patch.z_min, patch.z_max;
        end
    end
    -- A feature added by a refinement is already in the generated data; the POC maps above took
    -- their areas from elsewhere, so it is added to them here.
    local added = {};
    for id, patch in pairs(refinements[map.key] or {}) do
        local found = false;
        for _, area in ipairs(map.areas) do found = found or area.id == id; end
        if patch.add and not found then added[#added + 1] = id; end
    end
    table.sort(added);
    for _, id in ipairs(added) do
        local patch = refinements[map.key][id];
        map.areas[#map.areas + 1] = { id = id, name = patch.name, enabled = patch.enabled,
            provenance = patch.method, polygon = patch.polygon, exact = patch.exact or nil,
            z_min = patch.z_min, z_max = patch.z_max };
    end
    catalog.maps[map.key] = map;
    catalog.list[#catalog.list + 1] = map;
    catalog.by_zone[map.zone_id] = catalog.by_zone[map.zone_id] or {};
    table.insert(catalog.by_zone[map.zone_id], map);
    local floors = catalog.primary_by_floor[map.zone_id] or {};
    catalog.primary_by_floor[map.zone_id] = floors;
    if map.table_index and (not floors[map.floor_id] or score(map) > score(floors[map.floor_id])) then floors[map.floor_id] = map; end
end
for zone, maps in pairs(catalog.by_zone) do
    table.sort(maps, function(a, b)
        if a.floor_id ~= b.floor_id then return a.floor_id < b.floor_id; end
        return a.key < b.key;
    end);
    catalog.zones[#catalog.zones + 1] = { id = zone, name = maps[1].name, maps = maps };
    local best;
    for _, map in pairs(catalog.primary_by_floor[zone]) do
        if not best or map.floor_id < best.floor_id then best = map; end
    end
    catalog[zone] = best or maps[1]; -- Legacy callers and deterministic migration target.
end
table.sort(catalog.zones, function(a, b) return a.name == b.name and a.id < b.id or a.name < b.name; end);
return catalog;
