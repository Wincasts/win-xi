-- The last of the 2026-10-21 concepts: Nation Seal, Atlas Cartouche and Edge Toast as styles,
-- Discovery over the sub-zone style, and the location line's Breadcrumb look.
local imgui = require('imgui');
package.loaded['ffxi.time'] = { get_game_time_raw = function() return 0; end, get_game_weekday = function() return 0; end,
    get_game_hours = function() return 14; end, get_game_minutes = function() return 20; end,
    get_game_moon_percent = function(raw) return raw == 0 and 62 or 66; end };
local p = require('presentation');
local styles = require('banner_styles');
local mapdat = require('winxi.mapdat');
local d = p.app.options.display;
local checks = 0;
local function check(label, ok) H.print(label, ok); assert(ok, label); checks = checks + 1; end
d.backdrop[1] = false;

local drawn = {};
local list = setmetatable({}, { __index = function(_, k)
    return function(_, ...)
        local call = { k, ... };
        if k == 'AddText' then assert(type(call[4]) == 'string', 'AddText given ' .. type(call[4])); end
        for i = 2, #call do if type(call[i]) == 'table' then call[i] = { call[i][1], call[i][2] }; end end
        drawn[#drawn + 1] = call;
    end;
end });
imgui.GetBackgroundDrawList = function() return list; end;
imgui.GetWindowDrawList = function() return list; end;
local function count(kind, words)
    local n = 0;
    for _, call in ipairs(drawn) do if call[1] == kind and (words == nil or call[4] == words) then n = n + 1; end end
    return n;
end
local function wrote(words)
    for _, call in ipairs(drawn) do if call[1] == 'AddText' and call[4]:find(words, 1, true) then return true; end end
    return false;
end
local function at(state, age, tracking)
    drawn = {};
    return p.draw(state, tracking, 100 + age);
end

check('three more styles to choose', styles.valid('seal') and styles.valid('atlas') and styles.valid('toast')
    and styles.labels.seal == 'Nation Seal' and styles.labels.atlas == 'Atlas Cartouche' and styles.labels.toast == 'Edge Toast');
check('Discovery is not one to choose', not styles.valid('discovery'));

-- Nation Seal
local state = { title = 'Southern San d\'Oria', zone_title = 'Southern San d\'Oria', region = 'Kingdom of San d\'Oria',
    weather = 'Clear', banner_is_area = false, flag = 'sandoria' };
d.zoneStyle = 'seal';
p.start(state, 100);
check('the seal stamps down from large', at(state, .05) and count('AddCircleFilled') >= 3);
local early;
for _, call in ipairs(drawn) do if call[1] == 'AddCircleFilled' and not early then early = call[3]; end end
at(state, 3);
local settled;
for _, call in ipairs(drawn) do if call[1] == 'AddCircleFilled' and not settled then settled = call[3]; end end
check('and settles at its own size', early > settled * 1.5);
-- The game loads the flag; here the style is given one.
local direct = { alpha = 1, age = 3, x = 960, y = 100, alignment = 'center', title = 'Southern San d\'Oria',
    upper = 'Kingdom of San d\'Oria', meta = '', title_size = 52, detail_size = 18, title_color = { 1, 1, 1, 1 },
    detail_color = { 1, 1, 1, 1 }, outline = { 0, 0, 0, 1 }, edge = 1, flag = 'sandoria', flag_image = { handle = 'flag' } };
drawn = {};
styles.draw('seal', list, direct);
local round;
for _, call in ipairs(drawn) do if call[1] == 'AddImageRounded' then round = call; end end
check('the nation\'s flag round on it', round and round[2] == 'flag' and math.abs(round[8] * 2 - (round[4][1] - round[3][1])) < .001);
check('the region and name beside it', wrote('KINGDOM') or count('AddText', 'K') > 0);
check('the name', wrote('Southern San d\'Oria'));
state.flag = nil;
at(state, 3);
check('no flag: a crystal on a plain seal', count('AddImageRounded') == 0 and count('AddQuadFilled') == 1);

-- Atlas Cartouche
local loaded = 0;
mapdat.Load = function(dat) loaded = loaded + 1; return { dat = dat }, 'handle:' .. dat; end;
local square = { { 100, 100 }, { 140, 100 }, { 140, 130 }, { 100, 130 } };
local tracking = { definition = { dat = 'ROM/18/59.DAT', areas = {} }, entry = { scale = 4 }, map_x = 120, map_y = 115,
    area = { id = 'lion_square', name = 'Lion Square', polygon = square } };
local sub = { title = 'Lion Square', zone_title = 'Southern San d\'Oria', region = 'Kingdom of San d\'Oria',
    weather = 'Clear', banner_is_area = true, flag = 'sandoria' };
d.areaStyle = 'atlas';
p.start(sub, 100);
at(sub, 3, tracking);
check('the ribbon carries the name, in ink', wrote('Lion Square'));
check('the map round beside it', count('AddImageRounded') == 1 and loaded == 1);
local image;
for _, call in ipairs(drawn) do if call[1] == 'AddImageRounded' then image = call; end end
check('its picture is the map the player is on', image[2] == 'handle:ROM/18/59.DAT');
check('the part round the area, larger than it', image[5][1] < 100 / 512 and image[6][1] > 140 / 512);
check('the area\'s outline on it', count('AddLine') > 20);
check('and you on it', count('AddCircleFilled') >= 3);
at(sub, 3.5, tracking);
check('the picture is kept, not loaded each frame', loaded == 1);
at(sub, 3, nil);
check('without a map, the ribbon alone', count('AddImageRounded') == 0 and wrote('Lion Square'));
p.start(sub, 100);
at(sub, .1, tracking);
check('the ribbon unrolls, the inset still to come', count('AddImageRounded') == 0);

-- Edge Toast
d.areaStyle = 'toast';
local toast = { title = 'Lion Square', zone_title = 'Southern San d\'Oria', region = 'Kingdom of San d\'Oria',
    weather = 'Clear', banner_is_area = true, left_title = 'Lion Springs Tavern' };
d.areaZoneContext[1] = false;
p.start(toast, 100);
at(toast, 1.5);
check('a tag at the edge, entering', wrote('ENTERING') and wrote('Lion Square'));
check('the place just left under it', wrote('LEAVING') and wrote('Lion Springs Tavern'));
local left_x = math.huge;
for _, call in ipairs(drawn) do if call[1] == 'AddRectFilledMultiColor' then left_x = math.min(left_x, call[2][1]); end end
check('from the left edge', left_x == 0);
at(toast, 3.6);
check('the place left fades away', not wrote('LEAVING') and wrote('Lion Square'));
p.start(toast, 100);
at(toast, .05);
local early_x = math.huge;
for _, call in ipairs(drawn) do if call[1] == 'AddRectFilledMultiColor' then early_x = math.min(early_x, call[2][1]); end end
check('it slides in from off the screen', early_x < 0);
d.alignment = 'right';
at(toast, 1.5);
local right_x = 0;
for _, call in ipairs(drawn) do if call[1] == 'AddRectFilledMultiColor' then right_x = math.max(right_x, call[3][1]); end end
check('aligned right, from the right edge', right_x == 1920);
d.alignment = 'center';
local weather = { title = 'Weather: Rain', zone_title = 'Southern San d\'Oria', banner_is_weather = true, weather = 'Rain', left_title = 'X' };
p.start(weather, 100);
at(weather, 1.5);
check('a weather popup says so, and leaves nothing', wrote('WEATHER') and not wrote('LEAVING'));
d.areaZoneContext[1] = true;

-- Discovery: over the sub-zone style, the first time only.
d.areaStyle = 'titlecard';
local found = { title = 'Knightwell', zone_title = 'West Ronfaure', weather = 'Clear', banner_is_area = true,
    discovery = { count = 4, total = 7 } };
p.start(found, 100);
at(found, 2);
check('a new area is discovered', wrote('N') and count('AddText', 'N') >= 3 and wrote('Knightwell') and wrote('4 / 7'));
check('a pip for each of the zone\'s areas', count('AddQuadFilled') == 7);
p.start(found, 100);
at(found, .1);
check('a ring bursts behind it', count('AddCircle') == 2);
found.discovery = nil;
p.start(found, 100);
at(found, 2);
check('come to again, the sub-zone style', not wrote('4 / 7') and count('AddQuadFilled') == 0);
found.discovery = { count = 1, total = 37 };
p.start(found, 100);
at(found, 2);
check('more areas than twenty: the count alone', wrote('1 / 37') and count('AddQuadFilled') == 0);
d.areaDiscovery[1] = false;
at(found, 2);
check('Celebrate New Areas off: the sub-zone style', not wrote('1 / 37'));
d.areaDiscovery[1] = true;

-- What the addon keeps: zone.lua finds it on the first announcement, saved, and not again.
check('nothing discovered yet', next(d.discovered) == nil);
d.discovered['k:a'], d.discovered[5], d.discovered['k:b'] = true, true, 'yes';
p.complete(p.app.options);
check('saved discoveries are checked', d.discovered['k:a'] == true and d.discovered[5] == nil and d.discovered['k:b'] == nil);
d.discovered['k:a'] = nil;
check('the line style starts plain', d.locationStyle == 'plain');
d.locationStyle = 'fancy'; p.complete(p.app.options);
check('an unknown line style is plain again', d.locationStyle == 'plain');

-- Breadcrumb
d.locationEnabled[1], d.locationStyle = true, 'breadcrumb';
local info = { zone = 'West Ronfaure', region = 'Ronfaure', area = 'Knightwell', kind = 'outdoors', weather = 'Rain', weather_id = 6 };
drawn = {};
p.draw_location('West Ronfaure - Knightwell', info, 10);
H.frames(0);
check('a chip, region › zone › sub-zone', wrote('Ronfaure') and wrote('West Ronfaure') and wrote('Knightwell') and wrote(' › '));
check('the weather, the moon and the time under it', wrote('Rain') and wrote('Waxing Gibbous 62%') and wrote('Firesday 14:20'));
check('the weather\'s crystal', count('AddQuadFilled') == 1);
info.weather_id = 7; drawn = {};
p.draw_location('West Ronfaure - Knightwell', info, 11);
check('two for double weather', count('AddQuadFilled') == 2);
info.kind = 'city'; drawn = {};
p.draw_location('West Ronfaure - Knightwell', info, 12);
check('a city\'s towers', count('AddRectFilled') >= 4);
d.locationStyle = 'plain'; drawn = {};
p.draw_location('West Ronfaure - Knightwell', info, 20);
check('plain: the words alone', not wrote(' › '));
d.locationEnabled[1] = false;

H.print(('zone more styles: %d assertions passed'):format(checks));
