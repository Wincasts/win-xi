-- zone's banner styles: Title Card, Pennant and Kanji Watermark, drawn on the background draw list.
local imgui = require('imgui');
-- Vana'diel time: Firesday 14:20.
package.loaded['ffxi.time'] = { get_game_time_raw = function() return 0; end, get_game_weekday = function() return 0; end,
    get_game_hours = function() return 14; end, get_game_minutes = function() return 20; end };
local p = require('presentation');
local layout = require('banner_layout');
local styles = require('banner_styles');
local d = p.app.options.display;
local checks = 0;
local function check(label, ok) H.print(label, ok); assert(ok, label); checks = checks + 1; end

-- What the styles draw, as the background draw list is asked to draw it.
local drawn = {};
local list = setmetatable({}, { __index = function(_, k)
    -- points are tables the styles use again, so each is copied as it was
    return function(_, ...)
        local call = { k, ... };
        -- the game's AddText takes only a string for its words, and refuses anything else
        if k == 'AddText' then assert(type(call[4]) == 'string', 'AddText given ' .. type(call[4]) .. ' for its words'); end
        for i = 2, #call do if type(call[i]) == 'table' then call[i] = { call[i][1], call[i][2] }; end end
        drawn[#drawn + 1] = call;
    end;
end });
imgui.GetBackgroundDrawList = function() return list; end;
local depth = 0;
local realpush, realpop = imgui.PushFont, imgui.PopFont;
imgui.PushFont = function(...) depth = depth + 1; return realpush(...); end;
imgui.PopFont = function() depth = depth - 1; return realpop(); end;
local japanese = {};
imgui.AddFontFromFileTTF = function(path) local font = { path = path }; japanese[font] = true; return font; end;
local function count(kind, words)
    local n = 0;
    for _, call in ipairs(drawn) do
        if call[1] == kind and (words == nil or call[4] == words) then n = n + 1; end
    end
    return n;
end
local function texts()
    local found = {};
    for _, call in ipairs(drawn) do if call[1] == 'AddText' then found[call[4]] = (found[call[4]] or 0) + 1; end end
    return found;
end
local function letters(words)
    local found = {};
    for ch in words:gmatch('[%z\1-\127\194-\244][\128-\191]*') do found[#found + 1] = ch; end
    return found;
end

-- Neither day and time nor weather, in a style, from the first popup: no last line, and no error.
d.zoneStyle, d.zoneWeather[1], d.zoneDayTime[1] = 'titlecard', false, false;
local bare = { title = 'Metalworks', region = 'Republic of Bastok', weather = 'Sunshine', banner_is_area = false };
p.start(bare, 50);
drawn = {};
check('a style with no day, time or weather draws', p.draw(bare, nil, 53));
check('without a last line', not texts()['Sunshine']);
d.zoneStyle, d.zoneWeather[1], d.zoneDayTime[1] = 'classic', true, true;

-- Settings: the style names and sizes are kept within what there is.
check('styles start as Classic Text', d.zoneStyle == 'classic' and d.areaStyle == 'classic');
d.zoneStyle, d.areaStyle, d.kanjiSize[1], d.pennantWidth[1] = 'bogus', 7, 1000, 1;
p.complete(p.app.options);
check('an unknown style is Classic Text again', d.zoneStyle == 'classic' and d.areaStyle == 'classic');
check('sizes are kept within their ranges', d.kanjiSize[1] == 320 and d.pennantWidth[1] == 40);
d.kanjiSize[1], d.pennantWidth[1] = 120, 92;

local state = { title = 'West Ronfaure', zone_title = 'West Ronfaure', region = 'Ronfaure', weather = 'Sunshine',
    banner_is_area = false, zone_ja = '西ロンフォール', region_ja = 'ロンフォール', flag = 'sandoria' };

-- Title Card
local fonts_loaded = 0;
local counting = imgui.AddFontFromFileTTF;
imgui.AddFontFromFileTTF = function(...) fonts_loaded = fonts_loaded + 1; return counting(...); end;
d.zoneStyle = 'titlecard';
p.start(state, 100);
drawn = {};
check('title card draws', p.draw(state, nil, 100.5));
local words = texts();
check('the name is written letter by letter', words['W'] and words['R'] and words['f']);
check('the region is written in capitals', words['O'] and words['N'] and not words['Ronfaure']);
check('two rules are drawn, with their shadows', count('AddRectFilledMultiColor') == 4);
check('a diamond between them', count('AddQuad') == 2);
check('fonts are popped', depth == 0);
drawn = {};
p.draw(state, nil, 100.01);
local early = 0;
for _, call in ipairs(drawn) do if call[1] == 'AddRectFilledMultiColor' then early = math.max(early, call[3][1] - call[2][1]); end end
drawn = {};
p.draw(state, nil, 102);
local late = 0;
for _, call in ipairs(drawn) do if call[1] == 'AddRectFilledMultiColor' then late = math.max(late, call[3][1] - call[2][1]); end end
check('the rules grow out', early < late and late > 0);
check('the weather is on the last line once it has faded in', (function()
    for w in pairs(texts()) do if w:find('Sunshine', 1, true) then return true; end end end)());
check('nothing is drawn once the banner has gone', not p.draw(state, nil, 120));
local begun = H.calls.Begin or 0;
p.start(state, 110); p.draw(state, nil, 111);
check('no window is opened for a style', (H.calls.Begin or 0) == begun);
check('Title Card loads no Japanese font', fonts_loaded == 0);
imgui.AddFontFromFileTTF = counting;

-- Pennant
d.zoneStyle = 'pennant';
p.start(state, 200);
drawn = {};
check('pennant draws', p.draw(state, nil, 200.3));
check('its two tails', count('AddTriangleFilled') == 2);
check('its trim', count('AddLine') == 4);
local top_early;
for _, call in ipairs(drawn) do if call[1] == 'AddRectFilledMultiColor' then top_early = call[2][2]; break; end end
drawn = {};
p.draw(state, nil, 203);
local top_late;
for _, call in ipairs(drawn) do if call[1] == 'AddRectFilledMultiColor' then top_late = call[2][2]; break; end end
check('it drops in from above the screen', top_early < 0 and math.abs(top_late) < .001);
words = texts();
check('the name runs down it in capitals', words['W'] and words['E'] and words['S'] and words['T']);
check('the full name is beside it', words['West Ronfaure'] ~= nil);
check('without the flag image, a crystal at its head', count('AddQuadFilled') == 1);
check('the nation colours are used', styles.palettes.sandoria ~= nil);
check('fonts are popped', depth == 0);

-- Kanji Watermark
check('a name in kana and kanji is written vertically', styles.vertical(letters('西ロンフォール')));
check('a [S] zone is written across', not styles.vertical(letters('東ロンフォール〔Ｓ〕')));
check('a name with digits is written across', not styles.vertical(letters('2716号採石場')));
check('a name with a hyphen is written across', not styles.vertical(letters('アビセア-コンシュタット')));
d.zoneStyle, d.kanjiFont = 'kanji', '';
p.start(state, 300);
drawn = {};
check('kanji watermark draws', p.draw(state, nil, 303));
words = texts();
check('the Japanese name is drawn a character at a time', words['西'] and words['ロ'] and words['ォ'] and words['ル']);
check('the long vowel mark is its vertical stroke', not words['ー'] and count('AddRectFilled') == 1);
local stroke = drawn[(function() for i, call in ipairs(drawn) do if call[1] == 'AddRectFilled' then return i; end end end)()];
check('the stroke is tall and thin', (stroke[3][2] - stroke[2][2]) > 8 * (stroke[3][1] - stroke[2][1]));
local xs = {};
for _, call in ipairs(drawn) do if call[1] == 'AddText' and (call[4] == 'ォ' or call[4] == 'フ') then xs[call[4]] = call[2][1]; end end
check('small kana sit to the right of their square', xs['ォ'] > xs['フ']);
check('the region line has its Japanese name', words['ロンフォール  ·  Ronfaure'] ~= nil);
check('the English name is written whole', words['West Ronfaure'] ~= nil);
d.kanjiVertical[1] = false;
drawn = {};
p.draw(state, nil, 303);
check('across, the watermark is written whole', texts()['西ロンフォール'] ~= nil);
d.kanjiVertical[1] = true;
state.zone_ja = '東ロンフォール〔Ｓ〕';
drawn = {};
p.draw(state, nil, 303);
check('a [S] zone is written across even when vertical is chosen', texts()['東ロンフォール〔Ｓ〕'] ~= nil);
state.zone_ja = '西ロンフォール';
imgui.AddFontFromFileTTF = function() return nil; end;
d.kanjiFont = 'missing.ttf';
drawn = {};
p.draw(state, nil, 303);
check('without a Japanese font there is no watermark', not texts()['西'] and texts()['West Ronfaure'] and texts()['Ronfaure']);
check('fonts are popped', depth == 0);
d.kanjiFont = '';

-- A sub-zone popup in a style: the area as the title, the zone above it.
d.areaStyle, d.zoneStyle = 'titlecard', 'classic';
local area = { title = 'Knightwell', zone_title = 'West Ronfaure', region = 'Ronfaure', weather = 'Rain',
    banner_is_area = true, zone_ja = '西ロンフォール', region_ja = 'ロンフォール' };
p.start(area, 400);
drawn = {};
check('a sub-zone popup uses the sub-zone style', p.draw(area, nil, 403));
words = texts();
check('the sub-zone is the name, the zone above it', words['K'] and words['WEST'] == nil and words['V'] == nil and words['O'] ~= nil);

-- The GDI renderer is not used for a style.
d.renderer, d.zoneStyle = 'gdi', 'titlecard';
p.start(state, 500);
drawn = {};
check('a style draws with imgui when GDI is chosen', p.draw(state, nil, 500.5) and #drawn > 0 and package.loaded['gdi_banner'] == nil);
d.renderer = 'imgui';

-- /zone test <style> shows the zone in that style once, without changing the setting.
d.zoneStyle = 'classic';
H.frames(1);
drawn = {};
H.command('/zone test pennant');
H.frames(1);
check('/zone test pennant shows a pennant', count('AddTriangleFilled') == 2 and d.zoneStyle == 'classic');
drawn = {};
H.command('/zone test kanji');
H.frames(1);
check('the client zone has its Japanese name in the watermark', texts()['西'] ~= nil);
local printed = #H.printed;
H.command('/zone test bogus');
check('an unknown style is refused', #H.printed > printed and H.printed[#H.printed]:find('Usage', 1, true));
drawn = {};
H.command('/zone test');
H.frames(1);
check('/zone test alone uses the setting again', count('AddTriangleFilled') == 0 and not texts()['西']);

-- Day and time: a line of its own in Classic Text, on the last line in a style; each popup has its own toggle.
local function keys(rows) local found = {}; for _, row in ipairs(rows) do found[row.key] = row.words; end return found; end
check('day and time start on for zone entry, off for sub-zones', d.zoneDayTime[1] and not d.areaDayTime[1]);
local zone_state = { title = 'West Ronfaure', region = 'Ronfaure', weather = 'Clear', banner_is_area = false };
p.start(zone_state, 600);
check('the popup takes the day and time it starts at', zone_state.vana == 'Firesday 14:20');
check('Classic Text has a day and time line', keys(layout.rows(zone_state, nil, d)).zoneDayTime == 'Firesday 14:20');
d.zoneDayTime[1] = false;
check('which goes when it is turned off', keys(layout.rows(zone_state, nil, d)).zoneDayTime == nil);
local area_state = { title = 'Knightwell', zone_title = 'West Ronfaure', weather = 'Clear', banner_is_area = true, vana = 'Firesday 14:20' };
check('a sub-zone has none to start', keys(layout.rows(area_state, nil, d)).areaDayTime == nil);
d.areaDayTime[1] = true;
check('and has it when turned on', keys(layout.rows(area_state, nil, d)).areaDayTime == 'Firesday 14:20');
local weather_state = { title = 'Weather: Rain', zone_title = 'West Ronfaure', banner_is_weather = true, vana = 'Firesday 14:20' };
check('a weather popup follows the sub-zone toggle', keys(layout.rows(weather_state, nil, d)).areaDayTime == 'Firesday 14:20');
d.zoneStyle, d.renderer = 'titlecard', 'imgui';
p.start(zone_state, 700);
drawn = {};
p.draw(zone_state, nil, 703);
check('a style leaves the day and time out when it is off', texts()['Clear'] ~= nil and not texts()['Firesday 14:20  ·  Clear']);
d.zoneDayTime[1] = true;
drawn = {};
p.draw(zone_state, nil, 703);
check('and has it on its last line when on', texts()['Firesday 14:20  ·  Clear'] ~= nil);
d.areaDayTime[1] = false;

-- Appearance shows the sections for the styles in use.
local headers = {};
local realcolored = imgui.TextColored;
imgui.TextColored = function(color, words) headers[(words:gsub('^%[[-+]%] ', ''))] = true; return realcolored(color, words); end;
local function appearance(zone_style, area_style)
    d.zoneStyle, d.areaStyle = zone_style, area_style;
    headers = {};
    if not p.app.showConfig[1] then H.command('/zone'); end
    H.tab(2); H.frames(1);
    return headers;
end
local shown = appearance('classic', 'classic');
check('Classic Text only: no Pennant or Kanji Watermark sections', shown['Classic Text'] and not shown['Pennant'] and not shown['Kanji Watermark']);
check('every style has Banner Style, Position and Colors', shown['Banner Style'] and shown['Position'] and shown['Colors'] and shown['Fonts']);
shown = appearance('pennant', 'classic');
check('a pennant in use shows its section', shown['Pennant'] and shown['Classic Text'] and not shown['Kanji Watermark']);
shown = appearance('kanji', 'titlecard');
check('no Classic Text in use: no Classic Text or Background Image sections', shown['Kanji Watermark'] and not shown['Classic Text'] and not shown['Background Image']);
H.command('/zone'); H.tab(1);
imgui.TextColored = realcolored;
d.zoneStyle, d.areaStyle = 'classic', 'classic';

H.print(('zone banner styles: %d assertions passed'):format(checks));
