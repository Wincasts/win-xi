-- Banner settings and timing, with winxi/ImGui and experimental GDI renderers.
local imgui = require('imgui');
local bit = require('bit');
local settings = require('settings');
local shell = require('winxi.shell');
local widgets = require('winxi.widgets');
local window = require('winxi.window');
local style = require('winxi.style');
local theme = require('winxi.theme');
local text = require('winxi.text');
local game = require('winxi.game');
local fonts_lib = require('winxi.fonts');
local layout = require('banner_layout');
local background = require('banner_background');
local styles = require('banner_styles');
local background_cache = background.new();
local flag_cache; -- the pennant's and the seal's flag, whether or not flags are shown behind Classic Text: made when first wanted
local mapdat = require('winxi.mapdat');
local atlas_picture = { dat = nil, handle = nil, kept = nil, retry = 0 }; -- the Atlas Cartouche's map, one at a time
local M = { preview = { false } };
local dirty = false;
local gdi_backend;

-- Settings defaults and validation.
local lines = { { 'zoneRegion', 'Zone: Region' }, { 'zoneTitle', 'Zone: Title' }, { 'zoneWeather', 'Zone: Weather' },
    { 'zoneDayTime', 'Zone: Day And Time' }, { 'areaTitle', 'Sub-zone: Title' }, { 'areaContext', 'Sub-zone: Zone Context' },
    { 'areaWeather', 'Sub-zone: Weather' }, { 'areaDayTime', 'Sub-zone: Day And Time' } };
local function defaults()
    local result = T{ display = T{
        enabled = T{ true }, chat = T{ true },
        zoneRegion = T{ true }, zoneWeather = T{ true },
        areaEnabled = T{ true }, areaZoneContext = T{ true }, areaWeather = T{ true },
        centered = T{ true }, position = T{ 0, 110 }, alignment = 'center', mode = 'floating',
        zoneTitleSize = T{ 32 }, zoneDetailSize = T{ 16 },
        areaTitleSize = T{ 32 }, areaDetailSize = T{ 16 }, spacing = T{ 4 },
        renderer = 'imgui',
        weatherEnabled = T{ true },
        fieldApproach = T{ 50 }, townApproach = T{ 10 }, dungeonApproach = T{ 15 },
        entrancesEnabled = T{ true }, entranceYalms = T{ 20 }, townEntrancesEnabled = T{ true }, townEntranceYalms = T{ 40 },
        reannounceSeconds = T{ 10 }, areaDiscovery = T{ true }, discovered = T{ }, locationStyle = 'plain',
        liveMaps = T{ },
        locationEnabled = T{ false }, locationLocked = T{ false }, locationPosition = T{ 20, 300 }, locationSize = T{ 16 },
        backgroundEnabled = T{ false }, backgroundFile = T{ '' }, backgroundFlags = T{ true },
        backgroundSize = T{ 640, 140 }, backgroundOffset = T{ 0, -16 }, backgroundOpacity = T{ .6 },
        zoneTitleFont = '', zoneDetailFont = '', areaTitleFont = '', areaDetailFont = '',
        zoneTitleGdiFamily = T{ 'Arial' }, zoneDetailGdiFamily = T{ 'Arial' },
        areaTitleGdiFamily = T{ 'Arial' }, areaDetailGdiFamily = T{ 'Arial' },
        gdiTitleBold = T{ true }, gdiDetailBold = T{ false },
        perLineTiming = T{ false },
        hold = T{ 5 }, fadeIn = T{ .2 }, fadeOut = T{ 1 }, opacity = T{ 1 },
        themeText = T{ true }, titleColor = T{ 1, 1, 1, 1 }, detailColor = T{ 1, 1, 1, 1 },
        zoneStyle = 'classic', areaStyle = 'classic',
        styleTitleSize = T{ 52 }, styleDetailSize = T{ 18 }, zoneDayTime = T{ true }, areaDayTime = T{ false },
        pennantWidth = T{ 92 }, pennantLength = T{ 380 }, pennantLetterSize = T{ 30 },
        kanjiFont = '', kanjiSize = T{ 120 }, kanjiOpacity = T{ .3 }, kanjiVertical = T{ true },
        backdrop = T{ true }, backdropOpacity = T{ .5 }, backdropSoftness = T{ 32 },
    } };
    for _, line in ipairs(lines) do
        result.display[line[1] .. 'Delay'] = T{ 0 };
        result.display[line[1] .. 'Hold'] = T{ 5 };
        result.display[line[1] .. 'FadeIn'] = T{ .2 };
        result.display[line[1] .. 'FadeOut'] = T{ 1 };
    end
    return result;
end
local ranges = { zoneTitleSize = { 14, 96 },
    zoneDetailSize = { 10, 40 }, areaTitleSize = { 14, 96 }, areaDetailSize = { 10, 40 },
    spacing = { 0, 30 }, hold = { .1, 60 }, fadeIn = { 0, 3 }, fadeOut = { 0, 10 },
    opacity = { 0, 1 }, fieldApproach = { 0, 100 }, townApproach = { 0, 100 }, dungeonApproach = { 0, 100 },
    entranceYalms = { 5, 50 }, townEntranceYalms = { 5, 100 }, reannounceSeconds = { 0, 60 }, locationSize = { 10, 40 },
    styleTitleSize = { 16, 120 }, styleDetailSize = { 10, 48 },
    pennantWidth = { 40, 240 }, pennantLength = { 120, 1200 }, pennantLetterSize = { 10, 80 },
    kanjiSize = { 32, 320 }, kanjiOpacity = { 0, 1 }, backdropOpacity = { 0, 1 }, backdropSoftness = { 0, 120 } };
for _, line in ipairs(lines) do
    ranges[line[1] .. 'Delay'] = { 0, 60 };
    ranges[line[1] .. 'Hold'] = { .1, 60 };
    ranges[line[1] .. 'FadeIn'] = { 0, 3 };
    ranges[line[1] .. 'FadeOut'] = { 0, 10 };
end
local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge; end
function M.complete(options)
    local fallback = defaults().display;
    if type(options.display) ~= 'table' then options.display = fallback; end
    local d = options.display;
    -- Settings of earlier versions: one approach distance for every zone, the experimental label, and
    -- one region, weather, context and size for both popups.
    for _, key in ipairs({ 'approachYalms', 'areaExperimental', 'experimental', 'region', 'weather', 'zoneContext',
        'titleSize', 'detailSize' }) do d[key] = nil; end
    for key, value in pairs(fallback) do
        if type(value) == 'table' then
            if type(d[key]) ~= 'table' then d[key] = value; end
            for i, default in ipairs(value) do
                if type(d[key][i]) ~= type(default) or (type(default) == 'number' and not finite(d[key][i])) then d[key][i] = default; end
            end
        elseif type(d[key]) ~= type(value) then d[key] = value; end
    end
    for key, range in pairs(ranges) do d[key][1] = math.max(range[1], math.min(range[2], d[key][1])); end
    -- The sizes are whole numbers: one saved as a fraction (an earlier version's slider) is rounded,
    -- or fractional sizes would bake new fonts continuously while dragging, churning the shared atlas.
    for _, key in ipairs({ 'zoneTitleSize', 'zoneDetailSize', 'areaTitleSize', 'areaDetailSize',
        'locationSize', 'fieldApproach', 'townApproach', 'dungeonApproach', 'entranceYalms', 'townEntranceYalms', 'reannounceSeconds', 'styleTitleSize', 'styleDetailSize', 'pennantWidth', 'pennantLength',
        'pennantLetterSize', 'kanjiSize', 'backdropSoftness' }) do
        d[key][1] = math.floor(d[key][1] + .5);
    end
    for _, key in ipairs({ 'titleColor', 'detailColor' }) do
        for i = 1, 4 do d[key][i] = math.max(0, math.min(1, d[key][i])); end
    end
    for i = 1, 2 do
        d.position[i] = math.max(-10000, math.min(10000, d.position[i]));
        d.locationPosition[i] = math.floor(math.max(-10000, math.min(10000, d.locationPosition[i])) + .5);
    end
    -- The map chosen for live detection in each zone: 'z<zone id>' = a map key. Checked against the
    -- catalogue where it is used; here only its shape.
    for key, value in pairs(d.liveMaps) do
        if type(key) ~= 'string' or not key:match('^z%d+$') or type(value) ~= 'string' or #value > 128 then d.liveMaps[key] = nil; end
    end
    if d.alignment ~= 'left' and d.alignment ~= 'center' and d.alignment ~= 'right' then d.alignment = 'center'; end
    if d.locationStyle ~= 'plain' and d.locationStyle ~= 'breadcrumb' then d.locationStyle = 'plain'; end
    -- The areas come to, each '<map key>:<area id>' = true; anything else is let go.
    for key, value in pairs(d.discovered) do
        if type(key) ~= 'string' or #key > 160 or value ~= true then d.discovered[key] = nil; end
    end
    if d.mode ~= 'floating' and d.mode ~= 'panel' then d.mode = 'floating'; end
    if d.renderer ~= 'imgui' and d.renderer ~= 'gdi' then d.renderer = 'imgui'; end
    if not styles.valid(d.zoneStyle) then d.zoneStyle = 'classic'; end
    if not styles.valid(d.areaStyle) then d.areaStyle = 'classic'; end
    if #d.kanjiFont > 255 or d.kanjiFont:find('[/\\:]') then d.kanjiFont = ''; end
    for i = 1, 2 do
        d.backgroundSize[i] = math.max(1, math.min(4096, d.backgroundSize[i]));
        d.backgroundOffset[i] = math.max(-4096, math.min(4096, d.backgroundOffset[i]));
    end
    d.backgroundOpacity[1] = math.max(0, math.min(1, d.backgroundOpacity[1]));
    if d.backgroundFile[1] ~= '' and not background.valid_file(d.backgroundFile[1]) then d.backgroundFile[1] = ''; end
    for _, key in ipairs({ 'zoneTitleGdiFamily', 'zoneDetailGdiFamily', 'areaTitleGdiFamily', 'areaDetailGdiFamily' }) do
        if d[key][1] == '' or #d[key][1] > 255 then d[key][1] = 'Arial'; end
    end
end

-- Settings: described rows (winxi 65), each a name, a sentence and its control. Every id is
-- '##zone.<key>'; the spec tables are made once, their parents set as they are drawn.
local function changed(value) dirty = dirty or value or false; end
local ids = setmetatable({}, { __index = function(t, key) local id = '##zone.' .. key; t[key] = id; return id; end });
local function slider(d, name, sentence, key, spec)
    local range = ranges[key];
    changed(widgets.Slider(name, sentence, d[key], range[1], range[2], ids[key], spec));
end
local function check(d, name, sentence, key, spec)
    changed(widgets.Check(name, sentence, d[key], ids[key], spec));
end
-- A choice kept as a string (d.zoneStyle), not in a box
local function dropdown(d, name, sentence, key, choices, spec)
    local chosen = widgets.Dropdown(name, sentence, choices, d[key], ids[key], spec);
    if chosen ~= nil then d[key] = chosen; changed(true); end
end
local yalms = { format = '%d yalms' };
local seconds = { float = true, format = '%.1f s' };
local fraction = { float = true, format = '%.2f' };
local entranceYalms, townEntranceYalms = { format = '%d yalms' }, { format = '%d yalms' };
local lineSeconds = { float = true, format = '%.1f s' }; -- the per-line timing, under Use Per-Line Timing
local forgetSpec = { indent = false };                   -- greyed, not indented, while there is nothing to forget
local forgetWords = { count = -1, words = '' };
local locationLock = { label = 'Lock Position', description = 'Keeps the line where it is, and lets clicks through it to the game. Off, it can be dragged.' };
local locationDependent, locationPixels = {}, { format = '%d px' };
local rendererSpec = {};
local colorSpec = {};
local backdropOpacity, backdropSoftness = { float = true, format = '%.2f' }, { format = '%d px' };
local imageDependent, imageOpacity = {}, { float = true, format = '%.2f' };
local kanjiFontSpec = { label = 'Japanese Font', theme = 'Automatic',
    description = 'The font the name is written in. Automatic picks a Mincho font Windows has.' };
local fontSpecs = {
    { 'zoneTitleFont', { label = 'Zone Title Font', description = 'The font of the zone\'s name. Theme Font follows the Winxi Theme.' } },
    { 'zoneDetailFont', { label = 'Zone Detail Font', description = 'The font of the zone popup\'s other lines.' } },
    { 'areaTitleFont', { label = 'Sub-zone Title Font', description = 'The font of a sub-zone\'s name.' } },
    { 'areaDetailFont', { label = 'Sub-zone Detail Font', description = 'The font of a sub-zone popup\'s other lines.' } },
};
local gdiFields = {
    { 'zoneTitleGdiFamily', 'Zone Title Family', 'The Windows font family of the zone\'s name, in GDI Fonts.' },
    { 'zoneDetailGdiFamily', 'Zone Detail Family', 'The family of the zone popup\'s other lines.' },
    { 'areaTitleGdiFamily', 'Sub-zone Title Family', 'The family of a sub-zone\'s name.' },
    { 'areaDetailGdiFamily', 'Sub-zone Detail Family', 'The family of a sub-zone popup\'s other lines.' },
};
local style_choices = {};
for _, id in ipairs(styles.ids) do style_choices[#style_choices + 1] = { key = id, label = styles.labels[id] or id }; end
local renderers = { { key = 'imgui', label = 'ImGui (Default)' }, { key = 'gdi', label = 'GDI Fonts' } };
local modes = { { key = 'floating', label = 'Floating Text' }, { key = 'panel', label = 'Themed Panel' } };
local alignments = { { key = 'left', label = 'Left' }, { key = 'center', label = 'Center' }, { key = 'right', label = 'Right' } };
local location_styles = { { key = 'plain', label = 'Plain' }, { key = 'breadcrumb', label = 'Breadcrumb' } };
local location_place = true; -- The location line is put where the settings say on its next frame.
local fonts = {};
local function get_font(file)
    if file == '' then return nil; end
    if fonts[file] == nil then
        local ok, font = pcall(function() return imgui.AddFontFromFileTTF('C:\\Windows\\Fonts\\' .. file, 16); end);
        fonts[file] = (ok and font) or false;
    end
    return fonts[file] or nil;
end
-- The Japanese font for the Kanji Watermark: the one chosen, or the first of these in C:\Windows\Fonts.
-- IPA Mincho comes with Wine's Japanese fonts, Yu Mincho and MS Mincho with Windows. Every Japanese
-- zone and region name is in each of them.
local kanji_candidates = { 'ipam-mona.ttf', 'ipamp-mona.ttf', 'yumin.ttf', 'msmincho.ttc' };
local kanji_found;
local function kanji_file(d)
    if d.kanjiFont ~= '' then return d.kanjiFont; end
    if kanji_found == nil then
        kanji_found = false;
        for _, file in ipairs(kanji_candidates) do
            local ok, there = pcall(function() return ashita.fs.exists('C:\\Windows\\Fonts\\' .. file); end);
            if ok and there then kanji_found = file; break; end
        end
    end
    return kanji_found or nil;
end
local function commit(options)
    if dirty then M.complete(options); end
    if dirty and not imgui.IsMouseDown(0) then dirty = false; M.app:Save(); end
end
local function uses(d, id) return d.zoneStyle == id or d.areaStyle == id; end
-- Behaviour: what the banners say and when, the location line, and how long a banner stays up.
local function draw_settings(options)
    local d = options.display;
    if widgets.Header('Announcements', true) then
        check(d, 'Show Banner', 'Shows a banner as you enter a zone. Off, no banners at all.', 'enabled');
        check(d, 'Show Sub-zone Popups', 'A smaller banner as you reach a named part of a zone. /zone subzones switches it too.', 'areaEnabled');
        check(d, 'Show Weather Popups', 'A popup when the weather changes, in the sub-zone style.', 'weatherEnabled');
        check(d, 'Chat Announcements', 'Writes each banner to the chat log too.', 'chat');
    end
    if widgets.Header('Zone Entry Popup') then
        check(d, 'Show Region', 'Writes the zone\'s region over its name.', 'zoneRegion');
        check(d, 'Show Weather', 'Writes the weather under the name.', 'zoneWeather');
        check(d, 'Show Day And Time', 'Writes the Vana\'diel day and time you arrived, such as Firesday 14:20.', 'zoneDayTime');
    end
    if widgets.Header('Sub-zone Popup') then
        check(d, 'Show Zone Name', 'Writes the zone under the sub-zone\'s name.', 'areaZoneContext');
        check(d, 'Show Weather', 'Writes the weather under the name.', 'areaWeather');
        check(d, 'Show Day And Time', 'Writes the Vana\'diel day and time you came to it, such as Firesday 14:20.', 'areaDayTime');
        check(d, 'Celebrate New Areas', 'The first visit to an area gets a bigger moment, with how many you have found.', 'areaDiscovery');
        slider(d, 'Re-announce After', 'How long you must be away before an area is announced again. 0 announces every return.', 'reannounceSeconds', widgets.Seconds);
        local found = 0;
        for _ in pairs(d.discovered) do found = found + 1; end
        if forgetWords.count ~= found then
            forgetWords.count = found;
            forgetWords.words = ('%d area%s discovered on this character. Forgetting them makes every area new again.'):format(found, found == 1 and '' or 's');
        end
        forgetSpec.parent = found > 0;
        if widgets.Action('Forget Discovered Areas', forgetWords.words, 'Forget##zone.forgetDiscovered', forgetSpec) then
            imgui.OpenPopup('Forget Discovered Areas?##zone.forget');
        end
        if imgui.BeginPopup('Forget Discovered Areas?##zone.forget') then
            imgui.Text('Every area is new again on this character.');
            imgui.Separator();
            if imgui.Button('Forget##zone.forget.confirm') then
                for key in pairs(d.discovered) do d.discovered[key] = nil; end
                changed(true);
                imgui.CloseCurrentPopup();
            end
            imgui.SameLine();
            if imgui.Button('Cancel##zone.forget.cancel') then imgui.CloseCurrentPopup(); end
            imgui.EndPopup();
        end
    end
    if widgets.Header('Timing') then
        slider(d, 'Hold', 'How long a banner stays up.', 'hold', seconds);
        slider(d, 'Fade In', 'How long it takes to appear.', 'fadeIn', seconds);
        slider(d, 'Fade Out', 'How long it takes to go, after the hold.', 'fadeOut', seconds);
        -- Each line its own timing is Classic Text's alone: with no Classic Text in use the rows are left out.
        if uses(d, 'classic') then
            check(d, 'Use Per-Line Timing', 'Each line of Classic Text gets its own timing, set below.', 'perLineTiming');
            lineSeconds.parent = d.perLineTiming;
            -- the eight lines' sub-sections only while they are in use: 32 idle rows otherwise
            for _, line in ipairs(d.perLineTiming[1] and lines or {}) do
                if widgets.SubHeader(line[2]) then
                    slider(d, 'Start Delay', 'How long after the popup starts the line appears.', line[1] .. 'Delay', lineSeconds);
                    slider(d, 'Hold', 'How long the line stays up.', line[1] .. 'Hold', lineSeconds);
                    slider(d, 'Fade In', 'How long it takes to appear.', line[1] .. 'FadeIn', lineSeconds);
                    slider(d, 'Fade Out', 'How long it takes to go, after the hold.', line[1] .. 'FadeOut', lineSeconds);
                end
            end
        end
    end
    if widgets.Header('Detection') then
        slider(d, 'Field Approach Distance', 'How near a feature in open country is announced. 0 announces only inside it. /zone approach sets it too.', 'fieldApproach', yalms);
        slider(d, 'Town Approach Distance', 'The same in a city. Shops and guilds are announced only inside.', 'townApproach', yalms);
        slider(d, 'Dungeon Approach Distance', 'The same in a dungeon or a beastmen stronghold.', 'dungeonApproach', yalms);
    end
    if widgets.Header('Entrances') then
        check(d, 'Announce Dungeon Entrances', 'Names a dungeon\'s entrance as you come to it, such as Quicksand Caves Entrance 7.', 'entrancesEnabled');
        entranceYalms.parent = d.entrancesEnabled;
        slider(d, 'Dungeon Entrance Distance', 'How near the entrance is announced, from where it leads into the dungeon.', 'entranceYalms', entranceYalms);
        check(d, 'Announce Town Entrances', 'Names a town as you come up to its gates, such as Southern San d\'Oria Entrance.', 'townEntrancesEnabled');
        townEntranceYalms.parent = d.townEntrancesEnabled;
        slider(d, 'Town Entrance Distance', 'How near the gates are announced, from where they lead into the town.', 'townEntranceYalms', townEntranceYalms);
    end
    if widgets.Header('Location Line') then
        check(d, 'Show Location Line', 'Writes the zone and sub-zone you are in on the screen, all the time.', 'locationEnabled');
        locationLock.parent, locationDependent.parent, locationPixels.parent = d.locationEnabled, d.locationEnabled, d.locationEnabled;
        changed(widgets.Lock(d.locationLocked, '##zone.locationLocked', locationLock));
        if widgets.Numbers('Position', 'Where the line\'s top left corner is on the screen. Dragging it sets it too.', d.locationPosition, '##zone.locationPosition', locationDependent) then
            changed(true); location_place = true;
        end
        dropdown(d, 'Line Style', 'Breadcrumb shows region, zone and sub-zone on a dark chip, with the weather, moon and time.', 'locationStyle', location_styles, locationDependent);
        slider(d, 'Text Size', 'How tall the line\'s text is.', 'locationSize', locationPixels);
    end
    commit(options);
end
-- Appearance: how the banner looks. A style's own rows are there only while it is in use.
local function draw_appearance(options)
    local d = options.display;
    local styled = d.zoneStyle ~= 'classic' or d.areaStyle ~= 'classic';
    local classic = uses(d, 'classic');
    if widgets.Header('Preview', true) then
        widgets.Check('Preview While Configuring', 'Keeps a banner up while these settings are open, to see each change.', M.preview, '##zone.preview');
        if widgets.Action('Preview Zone Once', 'Shows the zone entry banner once. /zone test does the same.', 'Preview##zone.previewZoneOnce') and M.on_preview then M.on_preview(); end
        if widgets.Action('Preview Sub-zone Once', 'Shows a sub-zone popup once.', 'Preview##zone.previewSubzoneOnce') and M.on_area_preview then M.on_area_preview(); end
        if widgets.Action('Preview Weather Once', 'Shows a weather popup once.', 'Preview##zone.previewWeatherOnce') and M.on_weather_preview then M.on_weather_preview(); end
    end
    if widgets.Header('Banner Style') then
        dropdown(d, 'Zone Entry Style', 'How the banner looks as you enter a zone.', 'zoneStyle', style_choices);
        dropdown(d, 'Sub-zone Style', 'How a sub-zone popup looks. Weather popups use it too.', 'areaStyle', style_choices);
        slider(d, 'Opacity', 'How solid the whole banner is, text and all.', 'opacity', fraction);
    end
    if uses(d, 'pennant') and widgets.Header('Pennant') then
        slider(d, 'Pennant Width', 'How wide the pennant is.', 'pennantWidth', widgets.Pixels);
        slider(d, 'Pennant Length', 'How far it hangs down from the top of the screen.', 'pennantLength', widgets.Pixels);
        slider(d, 'Largest Letter Size', 'How big the letters down it are at most. Long names are written smaller.', 'pennantLetterSize', widgets.Pixels);
    end
    if uses(d, 'kanji') and widgets.Header('Kanji Watermark') then
        changed(widgets.FontFile(d, 'kanjiFont', '##zone.kanjiFont', kanjiFontSpec));
        if not kanji_file(d) then widgets.Note('No Japanese font was found: the watermark is left out.'); end
        slider(d, 'Watermark Size', 'How tall the characters are.', 'kanjiSize', widgets.Pixels);
        slider(d, 'Watermark Opacity', 'How solid the watermark is behind the name.', 'kanjiOpacity', fraction);
        check(d, 'Vertical Text', 'Writes the name down the screen. Names with Latin letters are written across.', 'kanjiVertical');
    end
    if classic and widgets.Header('Classic Text') then
        rendererSpec.experimental = d.renderer == 'gdi';
        dropdown(d, 'Text Renderer', 'GDI Fonts draws the text with Windows instead of ImGui. A failure in it can crash the game.', 'renderer', renderers, rendererSpec);
        -- GDI Fonts has no panel: the row means nothing there
        if d.renderer ~= 'gdi' then
            dropdown(d, 'Display Style', 'Themed Panel puts a Winxi Theme panel behind the text. Floating Text is the words alone.', 'mode', modes);
        end
    end
    if widgets.Header('Text') then
        if styled then
            slider(d, 'Style Title Size', 'How tall the name is, in every style but Classic Text.', 'styleTitleSize', widgets.Pixels);
            slider(d, 'Style Detail Size', 'How tall the other lines are in those styles.', 'styleDetailSize', widgets.Pixels);
        end
        if classic then
            slider(d, 'Zone Title Size', 'How tall the zone\'s name is in Classic Text.', 'zoneTitleSize', widgets.Pixels);
            slider(d, 'Zone Detail Size', 'How tall its other lines are.', 'zoneDetailSize', widgets.Pixels);
            slider(d, 'Sub-zone Title Size', 'How tall a sub-zone\'s name is in Classic Text.', 'areaTitleSize', widgets.Pixels);
            slider(d, 'Sub-zone Detail Size', 'How tall its other lines are.', 'areaDetailSize', widgets.Pixels);
            slider(d, 'Line Spacing', 'The gap between one line and the next.', 'spacing', widgets.Pixels);
        end
        if classic and d.renderer == 'gdi' then
            local families, problem = require('gdi_families').List();
            for _, field in ipairs(gdiFields) do
                local chosen = widgets.Dropdown(field[2], field[3], families, d[field[1]][1], ids[field[1]]);
                if chosen ~= nil then d[field[1]][1] = chosen; changed(true); end
            end
            if #families == 0 then widgets.Note('Windows font families could not be listed. The families saved are kept.'); end
            if problem then widgets.Note('Font families: ' .. problem); end
            check(d, 'Bold Titles', 'Writes the names in bold.', 'gdiTitleBold');
            check(d, 'Bold Details', 'Writes the other lines in bold.', 'gdiDetailBold');
        end
        if styled or d.renderer == 'imgui' then
            for _, font in ipairs(fontSpecs) do changed(widgets.FontFile(d, font[1], ids[font[1]], font[2])); end
        end
        check(d, 'Use Theme Text Color', 'Writes the text in the Winxi Theme text colour. Off, the colours below.', 'themeText');
        colorSpec.parent = not d.themeText[1];
        changed(widgets.Color('Title Color', 'The colour of the names.', d.titleColor, '##zone.titleColor', colorSpec));
        changed(widgets.Color('Detail Color', 'The colour of the other lines.', d.detailColor, '##zone.detailColor', colorSpec));
    end
    if widgets.Header('Position') then
        check(d, 'Centered On Screen', 'Puts the banner in the middle of the screen, left to right.', 'centered');
        changed(widgets.Numbers('Position', 'Where the banner is. Centered, X is measured from the middle of the screen.', d.position, '##zone.position'));
        dropdown(d, 'Text Alignment', 'How the lines line up when they differ in length.', 'alignment', alignments);
    end
    if widgets.Header('Backdrop') then
        check(d, 'Show Backdrop', 'A soft shadow behind the banner, so it stands out from a bright scene.', 'backdrop');
        backdropOpacity.parent, backdropSoftness.parent = d.backdrop, d.backdrop;
        slider(d, 'Backdrop Opacity', 'How dark the shadow is.', 'backdropOpacity', backdropOpacity);
        slider(d, 'Backdrop Softness', 'How far it fades out round the words.', 'backdropSoftness', backdropSoftness);
    end
    if classic and widgets.Header('Flag And Background Image', false, true) then
        check(d, 'Use Region Flags', 'Shows a nation\'s flag behind the banner in its regions, instead of the picture.', 'backgroundFlags');
        check(d, 'Show Background Image', 'Shows a picture of your own behind the banner.', 'backgroundEnabled');
        imageDependent.parent, imageOpacity.parent = d.backgroundEnabled, d.backgroundEnabled;
        widgets.BeginRow('Image Filename', 'A PNG, JPG or BMP file in the addon\'s assets\\backgrounds folder.', imageDependent);
        changed(imgui.InputText('##zone.backgroundFile', d.backgroundFile, 256));
        widgets.EndRow();
        changed(widgets.Numbers('Image Size', 'How wide and how tall the picture is drawn.', d.backgroundSize, '##zone.backgroundSize', imageDependent));
        changed(widgets.Numbers('Image Offset', 'How far the picture is moved from the banner, across and down.', d.backgroundOffset, '##zone.backgroundOffset', imageDependent));
        changed(widgets.Slider('Image Opacity', 'How solid the picture is.', d.backgroundOpacity, 0, 1, '##zone.backgroundOpacity', imageOpacity));
        if background_cache.error then widgets.Note(background_cache.error); end
        if widgets.Action('Reload Background Image', 'Reads the picture from its file again, after it has been changed.', 'Reload##zone.reloadBackground', imageDependent) then background_cache:clear(); end
    end
    commit(options);
end
M.app = shell.New({
    defaults = defaults(), configTitle = 'Zone Settings', drawSettings = draw_settings, settingsLabel = 'Behaviour',
    leadingTabs = { { label = 'Appearance', draw = draw_appearance } }, hideAppearance = true,
    -- The shell's Visibility tab (Fade In And Out and the rules for hiding) comes with a window named; the
    -- banner is drawn by M.draw, never through app:Window, and the command is zone.lua's.
    window = 'winxi.zone',
    onSettings = function(options)
        M.complete(options); dirty = false; M.preview[1] = false;
        background_cache:clear();
        location_place = true;
        if M.on_settings then M.on_settings(); end
    end,
}); -- Commands are handled by zone.lua: /zone toggles settings; /zone test previews the banner.

-- Capture timing at popup creation; appearance and opacity remain live. With the shell's Fade In And
-- Out off (the Visibility tab), a banner pops: its fades take no time.
local function fades() return M.app.options.fadeInOut[1] and true or false; end
local function row_timing(d, key, fading)
    return { delay = d[key .. 'Delay'][1], hold = { d[key .. 'Hold'][1] },
        fadeIn = { fading and d[key .. 'FadeIn'][1] or 0 }, fadeOut = { fading and d[key .. 'FadeOut'][1] or 0 }, opacity = d.opacity };
end
function M.total()
    local d = M.app.options.display; return d.hold[1] + (fades() and d.fadeOut[1] or 0);
end
-- The Vana'diel day and time a popup starts at, for the styles' last line: 'Firesday 14:20'.
local days = { 'Firesday', 'Earthsday', 'Watersday', 'Windsday', 'Iceday', 'Lightningday', 'Lightsday', 'Darksday' };
local function vana_words()
    local ok, words = pcall(function()
        local time = require('ffxi.time');
        local raw = time.get_game_time_raw();
        return ('%s %d:%02d'):format(days[tonumber(time.get_game_weekday(raw)) + 1],
            time.get_game_hours(raw), time.get_game_minutes(raw));
    end);
    return ok and words or nil;
end
function M.start(state, now)
    local d = M.app.options.display;
    state.vana = vana_words();
    state.started_at, state.visible_until = now, now + M.total();
    local fading = fades();
    state.banner_timing = { hold = { d.hold[1] }, fadeIn = { fading and d.fadeIn[1] or 0 }, fadeOut = { fading and d.fadeOut[1] or 0 }, opacity = d.opacity };
    state.line_timing = nil;
    if d.perLineTiming[1] then
        state.line_timing = {};
        state.visible_until = now;
        for _, row in ipairs(layout.rows(state, nil, d)) do
            local timing = row_timing(d, row.key, fading);
            state.line_timing[row.key] = timing;
            state.visible_until = math.max(state.visible_until, now + timing.delay + timing.hold[1] + timing.fadeOut[1]);
        end
    end
end
function M.valid_style(id) return styles.valid(id); end
function M.style_ids() return styles.ids; end
function M.chat_enabled() return M.app.options.display.chat[1]; end
function M.area_enabled() return M.app.options.display.areaEnabled[1]; end
function M.weather_enabled() return M.app.options.display.weatherEnabled[1]; end
function M.location_enabled() return M.app.options.display.locationEnabled[1]; end
function M.display() return M.app.options.display; end
function M.save() M.app:Save(); end
function M.begin_frame() M.app:BeginFrame(); end
function M.toggle_config()
    if M.app.showConfig[1] then M.complete(M.app.options); dirty = false; M.app:Save(); end
    M.app:ToggleConfig();
end
function M.shutdown()
    background_cache:clear();
    if flag_cache then flag_cache:clear(); end
    atlas_picture.dat, atlas_picture.handle, atlas_picture.kept = nil, nil, nil;
    if gdi_backend then gdi_backend:shutdown(); gdi_backend = nil; end
end
function M.reload()
    if type(settings.reload) ~= 'function' then return false; end
    settings.reload(); return true;
end

-- Reusable render state and current-content cache.
local transparent = { 0, 0, 0, 0 };
local open = { true };
local sample = { title = 'West Ronfaure', region = 'Ronfaure', weather = 'Clear',
    zone_title = 'West Ronfaure', banner_is_area = false, zone_ja = '西ロンフォール', region_ja = 'ロンフォール',
    flag = 'sandoria', vana = 'Firesday 14:20', weather_id = 0, kind = 'outdoors' };
local window_options = {};
local pivot, position = { .5, 0 }, { 0, 0 };
-- One bounded cache for the current banner/preview. Compare live scalar values so
-- settings edits invalidate immediately, without allocating a signature per frame.
local row_cache = {};
local function cached_rows(content, tracking, d)
    local c = row_cache;
    local region = d.zoneRegion[1];
    local weather = (content.banner_is_area and d.areaWeather or d.zoneWeather)[1];
    local context = d.areaZoneContext[1];
    if not c.rows or c.title ~= content.title or c.zone ~= content.zone_title
        or c.region ~= content.region or c.weather ~= content.weather or c.area ~= content.banner_is_area
        or c.is_weather ~= (content.banner_is_weather or false)
        or c.show_region ~= region or c.show_weather ~= weather or c.context ~= context
        or c.vana ~= content.vana or c.zone_day ~= d.zoneDayTime[1] or c.area_day ~= d.areaDayTime[1] then
        c.rows = layout.rows(content, tracking, d);
        c.title, c.zone = content.title, content.zone_title;
        c.region, c.weather, c.area = content.region, content.weather, content.banner_is_area;
        c.is_weather = content.banner_is_weather or false;
        c.show_region, c.show_weather, c.context = region, weather, context;
        c.vana, c.zone_day, c.area_day = content.vana, d.zoneDayTime[1], d.areaDayTime[1];
    end
    return c.rows;
end

-- A style other than Classic Text: everything it draws from, in one table kept for it.
local style_context = {};
local flag_only = { backgroundFlags = { true }, backgroundEnabled = { false }, backgroundFile = { '' } };
local meta_cache = { words = '' }; -- neither day and time nor weather: no last line
local function meta_words(vana, weather)
    local m = meta_cache;
    if m.vana ~= vana or m.weather ~= weather then
        m.vana, m.weather = vana, weather;
        m.words = (vana and weather) and (vana .. '  ·  ' .. weather) or (vana or weather or '');
    end
    return m.words;
end
-- The Atlas Cartouche's inset: the map the player is on, the part of it round the area come to (or
-- round the player, on zone entry), and the area's outline. Its picture is kept, one at a time.
local atlas_view = {};
local function atlas_of(tracking, area_style, title, now)
    local map, entry = tracking and tracking.definition, tracking and tracking.entry;
    if not map or not entry or not map.dat then return nil; end
    local picture = atlas_picture;
    if picture.dat ~= map.dat or (picture.handle == nil and now >= picture.retry) then
        picture.dat, picture.handle, picture.kept = map.dat, nil, nil;
        local ok, kept, handle = pcall(mapdat.Load, map.dat);
        if ok and handle then picture.kept, picture.handle = kept, handle; else picture.retry = now + 5; end
    end
    if not picture.handle then return nil; end
    local v = atlas_view;
    v.handle, v.px, v.py, v.polygon = picture.handle, tracking.map_x, tracking.map_y, nil;
    local area = area_style and tracking.area or nil;
    local cx, cy, span;
    if area and area.name == title and area.polygon then
        local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge;
        for _, point in ipairs(area.polygon) do
            x0, y0 = math.min(x0, point[1]), math.min(y0, point[2]);
            x1, y1 = math.max(x1, point[1]), math.max(y1, point[2]);
        end
        cx, cy, span = (x0 + x1) / 2, (y0 + y1) / 2, math.max(x1 - x0, y1 - y0) * 1.6;
        v.polygon = area.polygon;
    elseif v.px then
        cx, cy, span = v.px, v.py, 128;
    else
        return nil;
    end
    span = math.max(48, math.min(256, span));
    v.span = span;
    v.left = math.max(0, math.min(512 - span, cx - span / 2));
    v.top = math.max(0, math.min(512 - span, cy - span / 2));
    v.u0, v.v0, v.u1, v.v1 = v.left / 512, v.top / 512, (v.left + span) / 512, (v.top + span) / 512;
    return v;
end
local function draw_style(id, state, content, area_style, d, now, preview, timing, tracking)
    local alpha = preview and d.opacity[1] or layout.alpha(state.started_at, now, timing);
    if alpha <= .01 then return false; end
    local c = style_context;
    local io = imgui.GetIO();
    c.alpha = alpha;
    -- Entrances play while a popup is up; a preview kept up while configuring is shown as it ends.
    c.age = (state.started_at and state.visible_until > now) and (now - state.started_at) or 1000;
    c.x = (d.centered[1] and (io.DisplaySize.x or io.DisplaySize[1] or 0) / 2 or 0) + d.position[1];
    c.y, c.alignment = d.position[2], d.alignment;
    c.title = content.title or '';
    local weather = content.weather ~= nil and content.weather ~= '' and content.weather or nil;
    if area_style then
        c.upper = d.areaZoneContext[1] and content.zone_title or '';
        c.upper_ja = content.zone_ja;
        if content.banner_is_weather or not d.areaWeather[1] then weather = nil; end
    else
        c.upper = d.zoneRegion[1] and content.region or '';
        c.upper_ja = content.region_ja;
        if not d.zoneWeather[1] then weather = nil; end
    end
    c.upper = c.upper or '';
    local vana = d[area_style and 'areaDayTime' or 'zoneDayTime'][1] and content.vana or nil;
    c.meta = meta_words(vana, weather);
    -- Elemental Weather has the day and the weather apart, and the weather's element even when its
    -- words are left out of a weather popup, whose title says it.
    c.vana, c.weather = vana, weather;
    c.weather_id = (weather or content.banner_is_weather) and content.weather_id or nil;
    c.kind = content.kind;
    c.zone_ja, c.flag = content.zone_ja, content.flag;
    local flagged = (id == 'pennant' or id == 'seal') and content.flag;
    if flagged then flag_cache = flag_cache or background.new(); end
    c.flag_image = flagged and flag_cache:get(flag_only, now, content.flag) or nil;
    c.screen_w = io.DisplaySize.x or io.DisplaySize[1] or 0;
    c.toast_label = content.banner_is_weather and 'Weather' or 'Entering';
    c.left = (not content.banner_is_weather) and content.left_title or nil;
    c.atlas = id == 'atlas' and atlas_of(tracking, area_style, c.title, now) or nil;
    c.discovery = content.discovery;
    local kind = area_style and 'area' or 'zone';
    local theme_font = fonts_lib.Get(theme.Get().FontFile);
    c.title_font = get_font(d[kind .. 'TitleFont']) or theme_font;
    c.detail_font = get_font(d[kind .. 'DetailFont']) or theme_font;
    c.title_size, c.detail_size = d.styleTitleSize[1], d.styleDetailSize[1];
    c.title_color = d.themeText[1] and theme.Get().TextColor or d.titleColor;
    c.detail_color = d.themeText[1] and theme.Get().TextColor or d.detailColor;
    c.edge, c.outline = text.Edge(), text.EdgeColor();
    c.pennant_width, c.pennant_length, c.pennant_letter = d.pennantWidth[1], d.pennantLength[1], d.pennantLetterSize[1];
    -- The Japanese font (some 4 MB) is loaded only for the style that writes Japanese.
    local file = id == 'kanji' and kanji_file(d) or nil;
    c.kanji_font = file and get_font(file) or nil;
    c.kanji_size, c.kanji_opacity, c.kanji_vertical = d.kanjiSize[1], d.kanjiOpacity[1], d.kanjiVertical[1];
    c.backdrop, c.backdrop_opacity, c.backdrop_soft = d.backdrop[1], d.backdropOpacity[1], d.backdropSoftness[1];
    return styles.draw(id, imgui.GetBackgroundDrawList(), c);
end

-- Classic Text's window: what it draws is put in `classic` and the functions are made once, so that
-- a frame with the banner up makes no functions or tables of its own.
local classic = { font_pushed = false };
local no_spacing, room, at_pos = { 0, 0 }, { 0, 0 }, { 0, 0 };
local row_color, row_dark = { 0, 0, 0, 0 }, { 0, 0, 0, 0 };
local function classic_rows()
    local rows, d, area_style, alpha = classic.rows, classic.d, classic.area_style, classic.alpha;
    if classic.image then background.draw_imgui(classic.image, d, classic.width); end
    local maximum = 0;
    for _, row in ipairs(rows) do
        if row.title then
            row.size = area_style and d.areaTitleSize[1] or d.zoneTitleSize[1];
        else
            row.size = area_style and d.areaDetailSize[1] or d.zoneDetailSize[1];
        end
        row.size = math.floor(row.size + .5);
        if row.measured_font ~= row.font or row.measured_size ~= row.size or row.width == nil then
            imgui.PushFont(row.font, row.size);
            classic.font_pushed = true;
            local width, height = imgui.CalcTextSize(row.words);
            imgui.PopFont();
            classic.font_pushed = false;
            -- Commit only successful measurements so failures retry next frame.
            row.width, row.height = width, height;
            row.measured_font, row.measured_size = row.font, row.size;
        end
        maximum = math.max(maximum, row.width);
    end

    local x, y = imgui.GetCursorScreenPos();
    local draw = imgui.GetWindowDrawList();
    local edge = text.Edge(); -- the theme's Text Outline
    -- Floating Text's backdrop, under every window so that a background image stays over it. Themed
    -- Panel has its panel instead.
    if d.backdrop[1] and d.mode == 'floating' then
        local height = 0;
        for i, row in ipairs(rows) do height = height + row.height + edge * 2 + (i < #rows and d.spacing[1] or 0); end
        local pad = (area_style and d.areaDetailSize[1] or d.zoneDetailSize[1]);
        styles.backdrop(imgui.GetBackgroundDrawList(), x - pad, y - pad * .5, x + maximum + edge * 2 + pad, y + height + pad * .5,
            d.backdropSoftness[1], alpha * d.backdropOpacity[1]);
    end
    local outline = text.EdgeColor();
    for i, row in ipairs(rows) do
        if row.alpha > .01 then
            imgui.PushFont(row.font, row.size);
            classic.font_pushed = true;
            local offset = d.alignment == 'left' and 0
                or (d.alignment == 'right' and maximum - row.width or (maximum - row.width) / 2);
            local color = d.themeText[1] and theme.Get().TextColor
                or (row.title and d.titleColor or d.detailColor);
            local ratio = row.alpha / alpha;
            row_color[1], row_color[2], row_color[3], row_color[4] = color[1], color[2], color[3], color[4] * ratio;
            row_dark[1], row_dark[2], row_dark[3], row_dark[4] = outline[1], outline[2], outline[3], outline[4] * ratio;
            local packed = imgui.GetColorU32(row_color);
            local dark = imgui.GetColorU32(row_dark);
            if edge > 0 then
                text.Packed(draw, x + edge + offset, y + edge, packed, row.words, edge, dark);
            else
                at_pos[1], at_pos[2] = x + offset, y;
                draw:AddText(at_pos, packed, row.words);
            end
            imgui.PopFont();
            classic.font_pushed = false;
        end

        -- Keep delayed/expired lines' layout space without font/color work.
        local height = row.height + edge * 2;
        room[1], room[2] = maximum + edge * 2, height;
        imgui.Dummy(room);
        y = y + height;
        if i < #rows then
            room[1], room[2] = 0, d.spacing[1];
            imgui.Dummy(room);
            y = y + d.spacing[1];
        end
    end
end
local function classic_window()
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, no_spacing);
    classic.font_pushed = false;
    local ok, err = pcall(classic_rows);
    -- Restore stacks even if measurement or drawing raises an error.
    if classic.font_pushed then imgui.PopFont(); end
    imgui.PopStyleVar();
    if not ok then error(err, 0); end
end

function M.draw(state, tracking, now)
    local options, d = M.app.options, M.app.options.display;
    local preview = M.app.showConfig[1] and M.preview[1];
    -- Release the native backend before the idle return when switching renderers.
    if d.renderer ~= 'gdi' and gdi_backend then M.shutdown(); end
    if not background.wanted(d, state.flag) then background_cache:clear(); end
    if not d.enabled[1] or (not preview and (not state.started_at or state.visible_until <= now)) then
        return false;
    end
    local timing = state.banner_timing or d;
    if state.banner_timing then timing.opacity = d.opacity; end
    if game.IsHidden(options.hide) then return false; end
    local content = preview and (state.title ~= '' and state or sample) or state;
    -- A weather popup is styled as a sub-zone popup is.
    local area_style = content.banner_is_area or content.banner_is_weather or false;
    local style_id = state.style_override or (area_style and d.areaStyle or d.zoneStyle);
    -- An area come to for the first time is Discovery's, whatever the sub-zone style.
    if content.banner_is_area and content.discovery and d.areaDiscovery[1] and not state.style_override then
        if gdi_backend then M.shutdown(); end
        return draw_style('discovery', state, content, area_style, d, now, preview, timing, tracking);
    end
    if style_id ~= 'classic' and styles.valid(style_id) then
        if gdi_backend then M.shutdown(); end
        return draw_style(style_id, state, content, area_style, d, now, preview, timing, tracking);
    end
    local rows = cached_rows(content, tracking, d);
    local alpha = 0;
    for _, row in ipairs(rows) do
        local line = state.line_timing and state.line_timing[row.key];
        if line then line.opacity = d.opacity; end
        local started = state.started_at;
        if line and started then started = started + line.delay; end
        row.alpha = preview and d.opacity[1] or ((state.visible_until > now and started and now >= started)
            and layout.alpha(started, now, line or timing) or 0);
        alpha = math.max(alpha, row.alpha);
    end
    if #rows == 0 or alpha <= .01 then return false; end

    local io = imgui.GetIO();
    local width = io.DisplaySize.x or io.DisplaySize[1] or 0;
    local image = background_cache:get(d, now, state.flag);
    if d.renderer == 'gdi' then
        gdi_backend = gdi_backend or require('gdi_banner').new();
        for _, row in ipairs(rows) do
            local key = (area_style and 'area' or 'zone') .. (row.title and 'TitleSize' or 'DetailSize');
            row.size = math.floor(d[key][1] + .5);
        end
        local title_color = d.themeText[1] and theme.Get().TextColor or d.titleColor;
        local detail_color = d.themeText[1] and theme.Get().TextColor or d.detailColor;
        return gdi_backend:draw(rows, d, width, title_color, detail_color, area_style, image, alpha);
    end

    position[1], position[2] = (d.centered[1] and width / 2 or 0) + d.position[1], d.position[2];
    pivot[1] = d.alignment == 'left' and 0 or (d.alignment == 'right' and 1 or .5);
    imgui.SetNextWindowPos(position, ImGuiCond_Always, pivot);
    local flags = bit.bor(style.TitlelessFlags(), ImGuiWindowFlags_NoSavedSettings,
        ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoInputs, ImGuiWindowFlags_NoFocusOnAppearing);
    local floating = d.mode == 'floating';
    if floating then flags = bit.bor(flags, ImGuiWindowFlags_NoBackground); end
    window_options.alpha, window_options.background = alpha, floating and transparent or nil;
    window_options.padding = floating and 0 or nil;
    if floating then window_options.shadow = false; else window_options.shadow = nil; end
    -- Resolve fonts before opening the window: adding a font can update the shared atlas.
    for _, row in ipairs(rows) do
        local font_key = (area_style and 'area' or 'zone') .. (row.title and 'TitleFont' or 'DetailFont');
        row.font = get_font(d[font_key]);
    end
    -- Window alpha applies the shared fade; row colors apply only relative opacity.
    classic.rows, classic.d, classic.image, classic.width = rows, d, image, width;
    classic.area_style, classic.alpha = area_style, alpha;
    return window.Plain('##zone_banner', open, flags, classic_window, window_options);
end

-- The location line: where the player is, always shown, in a window of its own that can be dragged.
local location_open = { true };
local location_options = { alpha = 1, background = transparent, padding = 0, shadow = false };
-- Its window's body, made once: the words and whether it is locked are put in `location`.
local location = {};
local function location_text()
    local words, d = location.words, location.d;
    local width, height = imgui.CalcTextSize(words);
    local x, y = imgui.GetCursorScreenPos();
    -- Over the game itself: winxi's outlined text, its edge the theme's Text Outline.
    local edge = text.Edge();
    text.Draw(imgui.GetWindowDrawList(), x + edge, y + edge, theme.Get().TextColor, words);
    room[1], room[2] = width + 2 * edge, height + 2 * edge;
    imgui.Dummy(room);
    if not location.locked then
        -- Where it has been dragged to is kept, and saved with the other settings.
        local wx, wy = imgui.GetWindowPos();
        d.locationPosition[1], d.locationPosition[2] = math.floor(wx + .5), math.floor(wy + .5);
    end
end
local function location_window()
    imgui.PushFont(nil, location.d.locationSize[1]);
    local ok, err = pcall(location_text);
    imgui.PopFont();
    if not ok then error(err, 0); end
end
-- Breadcrumb: a dark chip with a picture of the kind of zone, region › zone › sub-zone (the sub-zone
-- in gold, sliding in as it changes), and under them the weather's crystal and name, the moon and the
-- Vana'diel day and time. The moon and the time are read once a second.
local crumb = { area = nil, since = 0, next_read = 0, moon = nil, vana = nil };
local crumb_colors = { chip = { .04, .05, .08, .78 }, dim = { .62, .64, .70, 1 }, sep = { .42, .44, .53, 1 },
    here = { 1, .89, .63, 1 }, outdoors = { .62, .82, .65, 1 }, city = { .85, .78, .62, 1 }, dungeon = { .72, .62, .52, 1 } };
local function read_sky(now)
    if now < crumb.next_read then return; end
    crumb.next_read = now + 1;
    local ok = pcall(function()
        local time = require('ffxi.time');
        local raw = time.get_game_time_raw();
        local moon = tonumber(time.get_game_moon_percent(raw)) or 0;
        local tomorrow = tonumber(time.get_game_moon_percent(raw + 3456)) or moon;
        local calendar = require('winxi.infopanel.calendar');
        crumb.moon = ('%s %d%%'):format(calendar.Phase(moon, tomorrow > moon or (tomorrow == moon and moon < 50)), moon);
    end);
    if not ok then crumb.moon = nil; end
    crumb.vana = vana_words();
end
local cp1, cp2, cp3, cp4 = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
local function pt(p, x, y) p[1], p[2] = x, y; return p; end
local crumb_scratch = { 0, 0, 0, 0 };
local function crumb_color(color, alpha)
    crumb_scratch[1], crumb_scratch[2], crumb_scratch[3], crumb_scratch[4] = color[1], color[2], color[3], (color[4] or 1) * alpha;
    return imgui.GetColorU32(crumb_scratch);
end
-- The picture of the kind of zone: hills for open country, towers for a city, an arch for a dungeon.
local function kind_icon(list, kind, x, y, s)
    local color = crumb_color(crumb_colors[kind] or crumb_colors.outdoors, 1);
    if kind == 'city' then
        list:AddRectFilled(pt(cp1, x + s * .1, y + s * .35), pt(cp2, x + s * .4, y + s), color);
        list:AddRectFilled(pt(cp1, x + s * .45, y + s * .1), pt(cp2, x + s * .75, y + s), color);
        list:AddTriangleFilled(pt(cp1, x + s * .45, y + s * .1), pt(cp2, x + s * .6, y - s * .1), pt(cp3, x + s * .75, y + s * .1), color);
        list:AddRectFilled(pt(cp1, x + s * .8, y + s * .5), pt(cp2, x + s, y + s), color);
    elseif kind == 'dungeon' then
        list:AddCircleFilled(pt(cp1, x + s / 2, y + s * .45), s * .45, color, 16);
        list:AddRectFilled(pt(cp1, x + s * .05, y + s * .45), pt(cp2, x + s * .95, y + s), color);
        local hole = crumb_color(crumb_colors.chip, 1);
        list:AddCircleFilled(pt(cp1, x + s / 2, y + s * .55), s * .22, hole, 12);
        list:AddRectFilled(pt(cp1, x + s * .28, y + s * .55), pt(cp2, x + s * .72, y + s), hole);
    else
        list:AddTriangleFilled(pt(cp1, x, y + s), pt(cp2, x + s * .4, y + s * .15), pt(cp3, x + s * .75, y + s), color);
        list:AddTriangleFilled(pt(cp1, x + s * .45, y + s), pt(cp2, x + s * .72, y + s * .4), pt(cp3, x + s, y + s), color);
    end
end
local crumb_parts = {};
local function breadcrumb_body()
    local info, d, now = location.info, location.d, location.now;
    local list = imgui.GetWindowDrawList();
    local x, y = imgui.GetCursorScreenPos();
    local size = d.locationSize[1];
    local small = math.floor(size * .8 + .5);
    local edge = text.Edge();
    local outline = text.EdgeColor();
    local pad, gap = size * .45, size * .45;
    local text_color = theme.Get().TextColor;
    -- The first row's parts, the sub-zone last.
    local parts = crumb_parts;
    for i = #parts, 1, -1 do parts[i] = nil; end
    if info.region and info.region ~= '' then parts[#parts + 1] = info.region; end
    parts[#parts + 1] = info.zone or '';
    if info.area then parts[#parts + 1] = info.area; end
    if info.area ~= crumb.area then crumb.area, crumb.since = info.area, now; end
    local sep = ' › ';
    local sep_w = imgui.CalcTextSize(sep);
    local w1, h1 = size * 1.2, 0;
    for i, part in ipairs(parts) do
        local w, h = imgui.CalcTextSize(part);
        w1, h1 = w1 + w + (i > 1 and sep_w or 0), math.max(h1, h);
    end
    -- The second row: weather, moon and time, at four fifths the size.
    read_sky(now);
    imgui.PushFont(nil, small);
    -- Made again only when one of its parts changes.
    if crumb.weather ~= info.weather or crumb.moon_was ~= crumb.moon or crumb.vana_was ~= crumb.vana then
        crumb.weather, crumb.moon_was, crumb.vana_was = info.weather, crumb.moon, crumb.vana;
        local second = info.weather or '';
        if crumb.moon then second = second ~= '' and (second .. '  ·  ' .. crumb.moon) or crumb.moon; end
        if crumb.vana then second = second ~= '' and (second .. '  ·  ' .. crumb.vana) or crumb.vana; end
        crumb.second = second;
    end
    local second = crumb.second;
    local element, count = styles.weather_element(info.weather_id);
    local gem = small * .3;
    local gems_w = element and (count * gem * 2.4 + small * .3) or 0;
    local w2, h2 = imgui.CalcTextSize(second);
    imgui.PopFont();
    w2 = w2 + gems_w;
    local width = math.max(w1, w2) + pad * 2 + edge * 2;
    local height = pad * 1.4 + h1 + (second ~= '' and (h2 + size * .2) or 0) + edge * 2;

    -- The chip: dark at the left, clear by the right.
    local dark, clear = crumb_color(crumb_colors.chip, 1), crumb_color(crumb_colors.chip, 0);
    local mid = x + width * .75;
    list:AddRectFilled(pt(cp1, x, y), pt(cp2, mid, y + height), dark, size * .25);
    list:AddRectFilledMultiColor(pt(cp1, mid, y), pt(cp2, x + width + pad * 2, y + height), dark, clear, clear, dark);

    local tx, ty = x + pad, y + pad * .7;
    kind_icon(list, info.kind, tx, ty + h1 * .15, h1 * .75);
    tx = tx + size * 1.2;
    local dim, sep_color = crumb_color(crumb_colors.dim, 1), crumb_color(crumb_colors.sep, 1);
    local plain, gold, black = crumb_color(text_color, 1), crumb_color(crumb_colors.here, 1), crumb_color(outline, 1);
    for i, part in ipairs(parts) do
        if i > 1 then
            text.Packed(list, tx, ty, sep_color, sep, edge, black);
            tx = tx + sep_w;
        end
        local last = i == #parts and info.area ~= nil;
        if last then
            -- The newest part slides in from the left as it changes.
            local t = math.min(1, math.max(0, (now - crumb.since) / .6));
            local shown = 1 - (1 - t) ^ 3;
            text.Packed(list, tx - size * (1 - shown), ty, crumb_color(crumb_colors.here, shown), part, edge, crumb_color(outline, shown));
        else
            text.Packed(list, tx, ty, i == 1 and #parts > 2 and dim or plain, part, edge, black);
        end
        tx = tx + imgui.CalcTextSize(part);
    end
    if second ~= '' then
        local sy = ty + h1 + size * .2;
        local sx = x + pad + edge;
        if element then
            for j = 1, count do
                styles.crystal(list, sx + gem, sy + h2 / 2, gem * .8, gem * 1.2, 0, styles.elements[element], 1, outline);
                sx = sx + gem * 2.4;
            end
            sx = sx + small * .3;
        end
        imgui.PushFont(nil, small);
        text.Packed(list, sx, sy, dim, second, edge, black);
        imgui.PopFont();
    end
    room[1], room[2] = width + pad * 2, height;
    imgui.Dummy(room);
    if not location.locked then
        local wx, wy = imgui.GetWindowPos();
        d.locationPosition[1], d.locationPosition[2] = math.floor(wx + .5), math.floor(wy + .5);
    end
end
local function breadcrumb_window()
    imgui.PushFont(nil, location.d.locationSize[1]);
    local ok, err = pcall(breadcrumb_body);
    imgui.PopFont();
    if not ok then error(err, 0); end
end
function M.draw_location(words, info, now)
    local options, d = M.app.options, M.app.options.display;
    if not d.locationEnabled[1] or not words or words == '' or game.IsHidden(options.hide) then return false; end
    local locked = d.locationLocked[1];
    local flags = bit.bor(style.TitlelessFlags(), ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoFocusOnAppearing);
    location_options.locked, location_options.clickThrough = locked, locked; -- Lock Position
    imgui.SetNextWindowPos(d.locationPosition, (locked or location_place) and ImGuiCond_Always or ImGuiCond_FirstUseEver);
    location_place = false;
    location.words, location.d, location.locked = words, d, locked;
    location.info, location.now = info, now or os.clock();
    local body = (d.locationStyle == 'breadcrumb' and info) and breadcrumb_window or location_window;
    return window.Plain('##zone_location', location_open, flags, body, location_options);
end
return M;
