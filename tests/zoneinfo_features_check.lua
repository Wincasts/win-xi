-- Region flags, the weather popup, saved detection settings and the location line.
local p = require('presentation');
local bg = require('banner_background');
local catalog = require('map_catalog');
local imgui = require('imgui');
local d = p.app.options.display;
local game = H.zoneinfo_game;
local checks = 0;
local function check(label, ok) H.print(label, ok); assert(ok, label); checks = checks + 1; end
local function count(words)
    local total = 0;
    for _, line in ipairs(H.printed) do if line:find(words, 1, true) then total = total + 1; end end
    return total;
end
local function move(x, y) game.x, game.y = x - 256, 256 - y; end

-- The weather where the addon reads it, and its names.
local weather = 0;
local find, read32, read8 = ashita.memory.find, ashita.memory.read_uint32, ashita.memory.read_uint8;
ashita.memory.find = function(module, base, sig, ...) if sig:sub(1, 4) == '66A1' then return 5000; end return find(module, base, sig, ...); end;
ashita.memory.read_uint32 = function(address) if address == 5002 then return 6000; end return read32(address); end;
ashita.memory.read_uint8 = function(address) if address == 6000 then return weather; end return read8(address); end;
local names = { [0] = 'Clear', [6] = 'Rain', [8] = 'Dust Storm' };
AshitaCore.GetResourceManager = function()
    return { GetString = function(_, kind, id) return kind == 'zones.names' and ('Zone ' .. id) or names[id]; end };
end;
-- What is drawn, and in which windows.
local draw = imgui.GetWindowDrawList();
local original_text, original_begin, original_pos = draw.AddText, imgui.Begin, imgui.SetNextWindowPos;
local written, begun, placed = {}, {}, nil;
draw.AddText = function(self, pos, color, words) written[words] = (written[words] or 0) + 1; return original_text(self, pos, color, words); end;
imgui.Begin = function(name, ...) begun[name] = (begun[name] or 0) + 1; return original_begin(name, ...); end;
imgui.SetNextWindowPos = function(pos, cond, pivot) if not pivot then placed = { pos[1], pos[2], cond }; end return original_pos(pos, cond, pivot); end;

-- Weather popup
H.load(); H.frames(40);
check('weather popups are on by default', p.weather_enabled());
check('the first reading is silent', count('Weather:') == 0);
weather = 6; H.frames(40);
check('a change of weather is announced once', count('Weather: Rain - Zone 100') == 1);
check('the popup shows the weather as its title, with the zone under it', (written['Weather: Rain'] or 0) > 0 and (written['Zone 100'] or 0) > 0);
H.frames(400);
check('unchanged weather does not repeat', count('Weather:') == 1);

-- Region flags
check('flags are on by default, the chosen image off', d.backgroundFlags[1] and not d.backgroundEnabled[1]);
check("a nation's region shows its flag", H.background_cache.file == 'flags/sandoria.png' and H.background_loads == 1);
for _, flag in pairs(require('data.region_flags')) do
    local file = io.open('addons/zone/assets/backgrounds/flags/' .. flag .. '.png', 'rb');
    check('flag file is bundled: ' .. flag, file ~= nil and bg.valid_flag(flag));
    if file then file:close(); end
end
local x, y, w, h = bg.bounds(d, 1920, { width = 256, height = 256, fit = true });
check('a flag keeps its proportions inside Image Size', x == 890 and y == 94 and w == 140 and h == 140);
x, y, w, h = bg.bounds(d, 1920, { width = 256, height = 256 });
check('a chosen image still fills Image Size', x == 640 and y == 94 and w == 640 and h == 140);
check('flag names cannot leave the flags folder', not bg.valid_flag('../x') and not bg.valid_flag('a/b') and not bg.valid_flag(''));
game.zone = 234; H.frames(2);
check('another nation, another flag', H.background_cache.file == 'flags/bastok.png' and count('Republic of Bastok - Zone 234 - Rain') == 1);
weather = 8; H.frames(40);
check('weather read just after zoning only corrects the banner', count('Weather: Dust Storm') == 0 and (written['Weather: Dust Storm'] or 0) > 0);
H.frames(400);
weather = 0; H.frames(40);
check('later changes are announced again', count('Weather: Clear - Zone 234') == 1);
d.weatherEnabled[1] = false; weather = 6; H.frames(400);
check('weather popups can be turned off', count('Weather: Rain - Zone 234') == 0);
d.weatherEnabled[1] = true;
weather = 0; H.frames(40);
local before = count('Weather: Clear - Zone 234');
weather = 6; H.packet(0x00A); H.frames(40);
check('zoning into the same zone settles too', count('Weather: Rain - Zone 234') == 0 and count('Weather: Clear - Zone 234') == before);
game.zone = 103; H.frames(2);
check('a region without a flag shows none', H.background_cache.file == nil);
d.backgroundEnabled[1], d.backgroundFile[1] = true, 'banner.png'; H.frames(1);
check('there the chosen image is used', H.background_cache.file == 'banner.png');
game.zone = 100; H.frames(2);
check('a flag takes the place of the chosen image', H.background_cache.file == 'flags/sandoria.png');
d.backgroundFlags[1] = false; H.frames(1);
check('flags can be turned off', H.background_cache.file == 'banner.png');
d.backgroundEnabled[1], d.backgroundFlags[1] = false, true;

-- Saved detection settings
local saves = H.saves();
check('open country is announced from further off than a dungeon, a dungeon than a town',
    d.fieldApproach[1] == 50 and d.dungeonApproach[1] == 15 and d.townApproach[1] == 10);
check('dungeon entrances are announced to begin with, closer in than open country',
    d.entrancesEnabled[1] == true and d.entranceYalms[1] < d.fieldApproach[1]);
check('a return is announced again only after ten seconds away, to begin with', d.reannounceSeconds[1] == 10);
check('town entrances too, from further off than a dungeon\'s', d.townEntrancesEnabled[1] == true
    and d.townEntranceYalms[1] > d.entranceYalms[1]);
H.command('/zone approach 45');
check('the approach command is saved, for open country', d.fieldApproach[1] == 45 and H.saves() > saves);
H.command('/zone approach town 8'); H.command('/zone approach dungeon 12');
check('town and dungeon each have their own', d.townApproach[1] == 8 and d.dungeonApproach[1] == 12 and d.fieldApproach[1] == 45);
d.fieldApproach[1] = 12; H.frames(1); H.command('/zone sample');
check('the setting drives detection', count('approach=12 yalms') == 1);
d.townApproach[1] = 33; H.frames(1); H.command('/zone sample');
check('a town\'s distance is not open country\'s', count('approach=33 yalms') == 0);
local primary = catalog[100].key;
H.command('/zone livemap ' .. primary);
check('the live map is saved for its zone', d.liveMaps.z100 == primary);
game.zone = 103; H.frames(400); H.command('/zone sample');
check('another zone does not inherit it', d.liveMaps.z103 == nil and count('map=' .. primary) == 0);
game.zone = 100; H.frames(400); H.command('/zone sample');
check('it is used again on return', count('zone=100 | map=' .. primary) == 1);
H.command('/zone livemap auto');
check('automatic selection clears the saved map', d.liveMaps.z100 == nil);
d.liveMaps.z100, d.liveMaps.bad, d.liveMaps.z7 = 'no_such_map', 'x', 5; d.fieldApproach[1] = 500;
d.entranceYalms[1], d.approachYalms, d.reannounceSeconds[1] = 0, T{ 30 }, 400;
p.complete(p.app.options); H.resettle(); H.frames(2);
check('saved values are validated', d.liveMaps.bad == nil and d.liveMaps.z7 == nil and d.fieldApproach[1] == 100
    and d.entranceYalms[1] == 5 and d.reannounceSeconds[1] == 60);
check('the one distance of before is dropped', d.approachYalms == nil);
H.command('/zone sample');
check('an unknown saved map is ignored', count('map=no_such_map') == 0);
d.fieldApproach[1], d.townApproach[1], d.dungeonApproach[1], d.entranceYalms[1] = 30, 10, 15, 20;
d.reannounceSeconds[1] = 10;

-- Location line
check('the location line is off by default', not d.locationEnabled[1] and begun['##zone_location'] == nil);
d.areaEnabled[1] = false; d.locationEnabled[1] = true;
move(200, 300); H.frames(400);
check('it names the zone', begun['##zone_location'] ~= nil and (written['Zone 100'] or 0) > 0 and written['Zone 100 - Knightwell'] == nil);
check('dragging it is kept', d.locationPosition[1] == 100 and d.locationPosition[2] == 200);
local announced = count('Sub-zone:');
move(238, 337); H.frames(70);
check('it names the sub-zone, without a popup', (written['Zone 100 - Knightwell'] or 0) > 0 and count('Sub-zone:') == announced);
move(200, 300); written = {}; H.frames(70); written = {}; H.frames(2);
check('leaving the sub-zone drops its name', (written['Zone 100'] or 0) > 0 and written['Zone 100 - Knightwell'] == nil);
d.locationLocked[1], d.locationPosition[1], d.locationPosition[2] = true, 5, 6; H.frames(2);
check('locked, it stays where the settings put it', d.locationPosition[1] == 5 and d.locationPosition[2] == 6
    and placed[1] == 5 and placed[2] == 6 and placed[3] == ImGuiCond_Always);
local windows = begun['##zone_location'];
d.locationEnabled[1] = false; H.frames(5);
check('turned off, nothing is drawn', begun['##zone_location'] == windows);
draw.AddText, imgui.Begin, imgui.SetNextWindowPos = original_text, original_begin, original_pos;
H.print(('zoneinfo flags/weather/detection/location: %d assertions passed'):format(checks));
