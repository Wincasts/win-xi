-- Offline CPU/heap benchmark; not a measurement of Ashita graphics or game FPS.
package.path = 'addons/zone/?.lua;' .. package.path;
local start = os.clock();
if arg[1] then package.loaded['area_geometry'] = dofile(arg[1]); end -- Optional baseline snapshot.
local catalog = require('map_catalog');
local geometry = require('area_geometry');
local editor = require('boundary_editor').new(catalog, '/tmp/zoneinfo-benchmark-unused.txt');
collectgarbage('collect');
print(('startup: %.3f ms | Lua heap: %.1f KiB'):format((os.clock() - start) * 1000, collectgarbage('count')));
local function bench(label, count, fn)
    for i = 1, math.min(100, count) do fn(i); end -- Warm LuaJIT traces/caches.
    collectgarbage('collect');
    local before, t = collectgarbage('count'), os.clock();
    for i = 1, count do fn(i); end
    local elapsed, transient = os.clock() - t, collectgarbage('count') - before;
    collectgarbage('collect');
    local retained = collectgarbage('count') - before;
    print(('%s: %.3f ms total | %.4f ms/op | transient/retained heap delta %.1f/%.1f KiB'):format(
        label, elapsed * 1000, elapsed * 1000 / count, transient, retained));
end
local matches = 0;
bench('classify across all maps', 100000, function(i)
    local map = catalog.list[(i - 1) % #catalog.list + 1];
    local area = geometry.classify(map.areas, i * 17 % 512, i * 31 % 512, nil, 3, 30);
    if area then matches = matches + 1; end
end);
local worst = catalog.list[1];
for _, map in ipairs(catalog.list) do if #map.areas > #worst.areas then worst = map; end end
local lines = 0;
bench('rebuild busiest map outlines (' .. #worst.areas .. ' areas)', 100, function()
    for _, area in ipairs(worst.areas) do lines = lines + #geometry.approach_outline(area.polygon, 30); end
end);
bench('cached unsaved-change check', 100000, function() editor:dirty(); end);
-- A live sample, four a second in game: the map's areas and the zone's entrances, height, the
-- zone's own approach distance and re-announce memory. Ru'Aun Gardens has the most entrances.
local tracking = require('area_tracking');
local ruaun = { scale = 1, offset_x = -256, offset_y = -256, floor_id = 0 };
local sampler = tracking.new({ get_entry = function() return ruaun; end, get_definition = function() return catalog[130]; end });
sampler.state.enabled = true;
sampler:set_zone(130, 0, 0); sampler.announce_after = 0;
local here, clock = { x = 0, y = 0, z = 0 }, 0;
bench('live sample with entrances (Ru\'Aun Gardens)', 100000, function(i)
    clock = clock + .25;
    here.x, here.y = geometry.map_to_world(ruaun, i * 7 % 512, i * 13 % 512);
    here.z = i % 40 - 20;
    sampler:sample(130, here, clock);
end);
print(('checksums: matches=%d outline_segments=%d'):format(matches, lines));
