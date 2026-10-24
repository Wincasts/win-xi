-- The Behaviour tab's layout: its sections in order, Open Map Browser, and the entrance distances
-- greyed while their switch is off.
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

local function behaviour()
    headers, labels, greyed = {}, {}, {};
    if not p.app.showConfig[1] then H.command('/zone'); end
    H.tab(2); H.frames(1); -- Behaviour, after Appearance
end
behaviour();
local order = table.concat(headers, ', ');
check('the sections, Preview first, switches in Announcements', order:find(
    'Preview, Announcements, Zone Entry Popup, Sub-zone Popup, Detection, Entrances, Location Line, Timing, Hide Banner', 1, true) == 1);
check('no Weather Popup section of one checkbox', not order:find('Weather Popup', 1, true));
local buttons = table.concat(labels, ', ');
check('Open Map Browser is a button', buttons:find('Open Map Browser', 1, true) ~= nil);
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
presses['Open Map Browser'] = true; behaviour(); presses['Open Map Browser'] = nil;
H.frames(1);
check('Open Map Browser opens it', said('Map browser: open.') and windows['Zone - Map Browser']);
H.command('/zone map');
check('/zone map closes it again', said('Map browser: closed.'));
imgui.Begin = begin;

local boxes = {};
local checkbox = imgui.Checkbox;
imgui.Checkbox = function(id, ...) boxes[id] = true; return checkbox(id, ...); end;
behaviour();
check('per-line timing offered with Classic Text in use', boxes['##zone.perLineTiming']);
boxes = {}; d.zoneStyle, d.areaStyle = 'titlecard', 'kind'; behaviour();
check('and not without it', not boxes['##zone.perLineTiming']);
imgui.Checkbox = checkbox;

for k, f in pairs(real) do imgui[k] = f; end
d.zoneStyle, d.areaStyle = 'classic', 'classic';
H.command('/zone');
H.print(('zone settings layout: %d assertions passed'):format(checks));
