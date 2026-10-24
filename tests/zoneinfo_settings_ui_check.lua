-- The settings' tabs: Appearance (Preview first), Behaviour (its sections in
-- order, the entrance distances greyed while their switch is off) and Visibility (Timing, Hide Banner).
local imgui = require('imgui');
local p = require('presentation');
local checks = 0;
local function check(label, ok) H.print(label, ok); assert(ok, label); checks = checks + 1; end
H.load(); H.frames(5);
local d = p.app.options.display;

local headers, labels, disabled, presses = {}, {}, 0, {};
local real = { TextColored = imgui.TextColored, Button = imgui.Button, BeginDisabled = imgui.BeginDisabled,
    EndDisabled = imgui.EndDisabled, SliderFloat = imgui.SliderFloat };
imgui.TextColored = function(color, words)
    headers[#headers + 1] = (words:gsub('^%[[-+]%] ', '')); return real.TextColored(color, words);
end;
imgui.Button = function(label) labels[#labels + 1] = label; return presses[label] == true; end;
local greyed = {};
imgui.BeginDisabled = function() disabled = disabled + 1; end;
imgui.EndDisabled = function() disabled = disabled - 1; end;
imgui.SliderFloat = function(id, ...) if disabled > 0 then greyed[id] = true; end return real.SliderFloat(id, ...); end;

local function show(tab)
    headers, labels, greyed = {}, {}, {};
    if not p.app.showConfig[1] then H.command('/zone'); end
    H.tab(tab); H.frames(1);
end
local function behaviour() show(2); end -- after Appearance
show(1);
local order = table.concat(headers, ', ');
check('Appearance begins with Preview, then the banner\'s look', order:find('Preview, Banner Style', 1, true) == 1);
local buttons = table.concat(labels, ', ');
check('the previews are there, and no map button', buttons:find('Preview Zone Once', 1, true) ~= nil
    and not buttons:find('Map', 1, true));
behaviour();
order = table.concat(headers, ', ');
check('Behaviour: switches in Announcements, then what the popups say and where', order:find(
    'Announcements, Zone Entry Popup, Sub-zone Popup, Detection, Entrances, Location Line', 1, true) == 1);
check('no Weather Popup section of one checkbox', not order:find('Weather Popup', 1, true));
check('no preview, timing or hiding there', not order:find('Preview', 1, true) and not order:find('Timing', 1, true)
    and not order:find('Hide Banner', 1, true));
show(3);
order = table.concat(headers, ', ');
check('Visibility: Timing and Hide Banner', order:find('Timing, Hide Banner', 1, true) == 1);
check('distances usable while their entrances are announced', not greyed['##zone.entranceYalms'] and not greyed['##zone.townEntranceYalms']);
d.entrancesEnabled[1] = false; behaviour();
check('a dungeon entrance\'s distance greyed while off', greyed['##zone.entranceYalms'] and not greyed['##zone.townEntranceYalms']);
d.entrancesEnabled[1], d.townEntrancesEnabled[1] = true, false; behaviour();
check('and a town\'s', greyed['##zone.townEntranceYalms'] and not greyed['##zone.entranceYalms']);
d.townEntrancesEnabled[1] = true;

local function said(words)
    for _, line in ipairs(H.printed) do if line:find(words, 1, true) then return true; end end
    return false;
end
local windows = {};
local begin = imgui.Begin;
imgui.Begin = function(name, ...) windows[name] = true; return begin(name, ...); end;
local backgrounds = require('winxi.backgrounds');
local real_background, painted = backgrounds.Draw, 0;
backgrounds.Draw = function(...) painted = painted + 1; return real_background(...); end;
H.frames(1);
local without = painted;
painted = 0;
H.command('/zone debug on'); H.frames(1);
check('/zone debug opens the debug window', said('Debug: ON.') and windows['Zone - Debug']);
painted = 0; H.frames(1);
check('with the theme\'s background behind it', painted == without + 1);
backgrounds.Draw = real_background;
H.command('/zone debug');
check('and closes it', said('Debug: OFF.'));
H.command('/zone map');
check('/zone map is gone', not said('Map browser'));
imgui.Begin = begin;

local boxes = {};
local checkbox = imgui.Checkbox;
imgui.Checkbox = function(id, ...) boxes[id] = true; return checkbox(id, ...); end;
show(3);
check('per-line timing offered with Classic Text in use', boxes['##zone.perLineTiming']);
boxes = {}; d.zoneStyle, d.areaStyle = 'titlecard', 'kind'; show(3);
check('and not without it', not boxes['##zone.perLineTiming']);
imgui.Checkbox = checkbox;

for k, f in pairs(real) do imgui[k] = f; end
d.zoneStyle, d.areaStyle = 'classic', 'classic';
H.command('/zone');
H.print(('zone settings layout: %d assertions passed'):format(checks));
