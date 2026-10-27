-- The settings' tabs, as described rows (winxi 65): Appearance (Preview first), Behaviour (its sections in
-- order, Timing among them with the per-line timing as sub-sections, the entrance distances greyed while
-- their switch is off) and Visibility (the shell's: Fade In And Out and the rules for hiding).
local imgui = require('imgui');
local p = require('presentation');
local checks = 0;
local function check(label, ok) H.print(label, ok); assert(ok, label); checks = checks + 1; end
H.load(); H.frames(5);
local d = p.app.options.display;

local headers, subheaders, labels, disabled, presses = {}, {}, {}, 0, {};
local real = { TextColored = imgui.TextColored, Button = imgui.Button, BeginDisabled = imgui.BeginDisabled,
    EndDisabled = imgui.EndDisabled, SliderFloat = imgui.SliderFloat, SliderInt = imgui.SliderInt, Checkbox = imgui.Checkbox,
    BeginPopup = imgui.BeginPopup, EndPopup = imgui.EndPopup, Text = imgui.Text, TextDisabled = imgui.TextDisabled };
local inSub = false; -- a sub-section's title is written as a section's is: kept apart
imgui.TextColored = function(color, words)
    -- a title, then its [-] or [+] marker in a text of its own (winxi 65)
    if not inSub and words ~= '[-]' and words ~= '[+]' and words ~= '[Experimental]' then headers[#headers + 1] = words; end
    return real.TextColored(color, words);
end;
local widgets = require('winxi.widgets');
local realsub = widgets.SubHeader;
widgets.SubHeader = function(text, ...)
    subheaders[#subheaders + 1] = text;
    inSub = true;
    local open = realsub(text, ...);
    inSub = false;
    return open;
end;
imgui.Button = function(label) labels[#labels + 1] = label; return presses[label] == true; end;
local greyed, boxes = {}, {};
imgui.BeginDisabled = function() disabled = disabled + 1; end;
imgui.EndDisabled = function() disabled = disabled - 1; end;
imgui.SliderFloat = function(id, ...) greyed[id] = disabled > 0; return real.SliderFloat(id, ...); end;
imgui.SliderInt = function(id, ...) greyed[id] = disabled > 0; return real.SliderInt(id, ...); end;
imgui.Checkbox = function(id, ...) boxes[id] = true; return real.Checkbox(id, ...); end;
-- every row has a sentence under its name: none of the names is written without one
local names, sentences = 0, 0;
local realrow = widgets.BeginRow;
widgets.BeginRow = function(name, sentence, spec)
    names = names + 1;
    if sentence and sentence ~= '' then sentences = sentences + 1; end
    return realrow(name, sentence, spec);
end;

-- Flag And Background Image starts collapsed: opened here, so that its rows are drawn and checked too
local realheader = widgets.Header;
widgets.Header = function(text, first) return realheader(text, first, false); end;
local inputs = {};
local realinput = imgui.InputText;
imgui.InputText = function(id, ...) inputs[id] = true; return realinput(id, ...); end;

local function show(tab)
    headers, subheaders, labels, greyed, boxes, names, sentences = {}, {}, {}, {}, {}, 0, 0;
    if not p.app.showConfig[1] then H.command('/zone'); end
    H.tab(tab); H.frames(1);
end
local function behaviour() show(2); end -- after Appearance
show(1);
local order = table.concat(headers, ', ');
check('Appearance begins with Preview, then the banner\'s look', order:find('Preview, Banner Style', 1, true) == 1);
local buttons = table.concat(labels, ', ');
check('the previews are there, as Preview buttons, and no map button', buttons:find('Preview##zone.previewZoneOnce', 1, true) ~= nil
    and buttons:find('Preview##zone.previewSubzoneOnce', 1, true) ~= nil and buttons:find('Preview##zone.previewWeatherOnce', 1, true) ~= nil
    and not buttons:find('Map', 1, true));
check('every Appearance row has its sentence', names > 10 and sentences == names);
check('the colours are rows, greyed while the theme\'s colour is used', boxes['##zone.themeText'] and d.themeText[1]);
check('the background image rows are drawn, with the file name in a row', inputs['##zone.backgroundFile'] and boxes['##zone.backgroundEnabled']);
behaviour();
order = table.concat(headers, ', ');
check('Behaviour: switches in Announcements, then what the popups say, how long they stay, and where', order:find(
    'Announcements, Zone Entry Popup, Sub-zone Popup, Timing, Detection, Entrances, Location Line', 1, true) == 1);
check('no Weather Popup section of one checkbox', not order:find('Weather Popup', 1, true));
check('no preview or hiding there', not order:find('Preview', 1, true) and not order:find('Hide Banner', 1, true));
check('every Behaviour row has its sentence', names > 20 and sentences == names);
check('distances usable while their entrances are announced', greyed['##zone.entranceYalms'] == false and greyed['##zone.townEntranceYalms'] == false);
d.entrancesEnabled[1] = false; behaviour();
check('a dungeon entrance\'s distance greyed while off', greyed['##zone.entranceYalms'] and not greyed['##zone.townEntranceYalms']);
d.entrancesEnabled[1], d.townEntrancesEnabled[1] = true, false; behaviour();
check('and a town\'s', greyed['##zone.townEntranceYalms'] and not greyed['##zone.entranceYalms']);
d.townEntrancesEnabled[1] = true;

-- Timing: the banner's hold and fades, and with Classic Text in use, Use Per-Line Timing with a
-- sub-section a line once it is on, and none while it is off (32 idle rows otherwise).
behaviour();
check('per-line timing offered with Classic Text in use', boxes['##zone.perLineTiming']);
check('no sub-sections while per-line timing is off', #subheaders == 0 and boxes['##zone.zoneRegionHold'] == nil and greyed['##zone.hold'] == false);
d.perLineTiming[1] = true; behaviour();
check('a sub-section for each line once it is on', #subheaders == 8 and subheaders[1] == 'Zone: Region' and subheaders[8] == 'Sub-zone: Day And Time');
check('and usable', greyed['##zone.zoneRegionHold'] == false);
d.perLineTiming[1] = false;
d.zoneStyle, d.areaStyle = 'titlecard', 'kind'; behaviour();
check('and not without Classic Text', not boxes['##zone.perLineTiming'] and #subheaders == 0 and greyed['##zone.hold'] == false);
d.zoneStyle, d.areaStyle = 'classic', 'classic';

-- Forget Discovered Areas asks first, in a popup.
d.discovered['m:1'], d.discovered['m:2'] = true, true;
behaviour();
check('the forget button is a row\'s, usable with areas discovered', table.concat(labels, ', '):find('Forget##zone.forgetDiscovered', 1, true) ~= nil);
local opened;
imgui.OpenPopup = function(id) opened = id; end;
imgui.BeginPopup = function(id) return id == opened; end;
presses['Forget##zone.forgetDiscovered'] = true;
behaviour();
check('a click opens the popup, forgetting nothing yet', opened == 'Forget Discovered Areas?##zone.forget' and d.discovered['m:1']);
presses['Forget##zone.forgetDiscovered'] = nil;
presses['Forget##zone.forget.confirm'] = true;
behaviour();
check('Forget in the popup forgets them', next(d.discovered) == nil);
presses['Forget##zone.forget.confirm'] = nil;
opened = nil;
imgui.BeginPopup = real.BeginPopup;

show(3);
order = table.concat(headers, ', ');
check('Visibility: the shell\'s one section', order == 'Visibility');
check('with Fade In And Out and the rules for hiding', boxes['##zone.fadeInOut'] and boxes['##winxi.hide.UnderMap'] and boxes['##winxi.hide.DuringEvent']);
check('and no Timing or Hide Banner of the addon\'s own', not boxes['##zone.perLineTiming'] and not order:find('Timing', 1, true));
-- With Fade In And Out off, a banner pops: its fades take no time.
local state = { title = 'West Ronfaure', region = 'Ronfaure', weather = 'Clear', banner_is_area = false };
p.app.options.fadeInOut[1] = false;
p.start(state, 100);
check('Fade In And Out off: a banner pops', state.banner_timing.fadeIn[1] == 0 and state.banner_timing.fadeOut[1] == 0 and state.visible_until == 100 + d.hold[1]);
p.app.options.fadeInOut[1] = true;
p.start(state, 100);
check('on, it fades as Timing says', state.banner_timing.fadeOut[1] == d.fadeOut[1] and state.visible_until == 100 + d.hold[1] + d.fadeOut[1]);

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

for k, f in pairs(real) do imgui[k] = f; end
widgets.BeginRow, widgets.SubHeader, widgets.Header, imgui.InputText = realrow, realsub, realheader, realinput;
d.zoneStyle, d.areaStyle = 'classic', 'classic';
if p.app.showConfig[1] then H.command('/zone'); end
H.print(('zone settings layout: %d assertions passed'):format(checks));
