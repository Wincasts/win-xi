package.path = 'addons/zone/?.lua;' .. package.path;
local model = require('banner_layout');
local checks = 0;
local function check(label, ok) assert(ok, label); checks = checks + 1; end
local function near(a, b) return math.abs(a - b) < .000001; end
local d = { hold = { 5 }, fadeIn = { .2 }, fadeOut = { 1 }, opacity = { .8 },
    zoneRegion = { true }, zoneWeather = { true }, areaWeather = { true }, areaZoneContext = { true } };
check('no timer means hidden', model.alpha(nil, 0, d) == 0);
check('fade starts transparent', model.alpha(0, 0, d) == 0);
check('fade in midpoint', near(model.alpha(0, .1, d), .4));
check('hold has configured opacity', near(model.alpha(0, 4, d), .8));
check('fade out midpoint', near(model.alpha(0, 5.5, d), .4));
check('expiry hidden', model.alpha(0, 6, d) == 0);
d.fadeOut[1], d.fadeIn[1] = 0, 0;
check('zero fade is instantaneous without division by zero', near(model.alpha(0, 4.99, d), .8) and model.alpha(0, 5, d) == 0);
local state = { title = 'West Ronfaure', zone_title = 'West Ronfaure', region = 'Ronfaure', weather = 'Clear', banner_is_area = false };
local rows = model.rows(state, nil, d);
check('region appears above large title', rows[1].words == 'Ronfaure' and not rows[1].title and rows[2].title);
check('weather remains available', rows[3].words == 'Weather: Clear');
state.title, state.banner_is_area = 'Knightwell', true;
rows = model.rows(state, nil, d);
check('sub-zone popup has no extra label', rows[1].words == 'Knightwell' and rows[1].title);
check('sub-zone title has timing identity', rows[1].key == 'areaTitle');
check('area names its zone, with no experimental label', rows[2].words == 'West Ronfaure' and rows[2].key == 'areaContext');
d.areaZoneContext[1] = false;
check('Show Zone Name off leaves it out', model.rows(state, nil, d)[2].words == 'Weather: Clear');
d.zoneRegion[1], d.zoneWeather[1], d.areaWeather[1] = false, false, false;
check('visibility switches keep only sub-zone title', #model.rows(state, nil, d) == 1);
state.banner_is_area, state.title = false, 'West Ronfaure'; d.areaZoneContext[1] = true;
rows = model.rows(state, { enabled = true, area = { name = 'Knightwell' } }, d);
check('zone entry does not include stable subzone', #rows == 1 and rows[1].words == 'West Ronfaure');
state.entry_subzone = 'Knightwell';
check('zone entry ignores sampled subzone', #model.rows(state, { enabled = false, area = { name = 'Other' } }, d) == 1);
state.entry_subzone = nil;
check('debug-only area not leaked into banner', #model.rows(state, { enabled = false, area = { name = 'Knightwell' } }, d) == 1);
print(('zoneinfo banner model: %d assertions passed'):format(checks));
