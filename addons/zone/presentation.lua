-- Banner settings and timing, with winxi/ImGui and experimental GDI renderers.
local imgui = require('imgui');
local bit = require('bit');
local settings = require('settings');
local shell = require('winxi.shell');
local widgets = require('winxi.widgets');
local tips = require('winxi.tooltip');
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
local flag_cache; -- the pennant's flag, whether or not flags are shown behind Classic Text: made when first wanted
local M = { preview = { false } };
local dirty = false;
local gdi_backend;

-- Settings defaults and validation.
local lines = { { 'zoneRegion', 'Zone: Region' }, { 'zoneTitle', 'Zone: Title' }, { 'zoneWeather', 'Zone: Weather' },
    { 'zoneDayTime', 'Zone: Day And Time' }, { 'areaTitle', 'Sub-zone: Title' }, { 'areaContext', 'Sub-zone: Zone Context' },
    { 'areaWeather', 'Sub-zone: Weather' }, { 'areaDayTime', 'Sub-zone: Day And Time' } };
local function defaults()
    local result = T{ display = T{
        enabled = T{ true }, chat = T{ true }, region = T{ true }, weather = T{ true },
        zoneContext = T{ true }, experimental = T{ true },
        zoneRegion = T{ true }, zoneWeather = T{ true },
        areaEnabled = T{ true }, areaZoneContext = T{ true }, areaWeather = T{ true }, areaExperimental = T{ true },
        centered = T{ true }, position = T{ 0, 110 }, alignment = 'center', mode = 'floating',
        titleSize = T{ 32 }, detailSize = T{ 16 }, zoneTitleSize = T{ 32 }, zoneDetailSize = T{ 16 },
        areaTitleSize = T{ 32 }, areaDetailSize = T{ 16 }, spacing = T{ 4 },
        renderer = 'imgui',
        weatherEnabled = T{ true },
        approachYalms = T{ 30 }, liveMaps = T{ },
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
local ranges = { titleSize = { 14, 96 }, detailSize = { 10, 40 }, zoneTitleSize = { 14, 96 },
    zoneDetailSize = { 10, 40 }, areaTitleSize = { 14, 96 }, areaDetailSize = { 10, 40 },
    spacing = { 0, 30 }, hold = { .1, 60 }, fadeIn = { 0, 3 }, fadeOut = { 0, 10 },
    opacity = { 0, 1 }, approachYalms = { 0, 100 }, locationSize = { 10, 40 },
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
    for key, value in pairs(fallback) do
        if type(value) == 'table' then
            if type(d[key]) ~= 'table' then d[key] = value; end
            for i, default in ipairs(value) do
                if type(d[key][i]) ~= type(default) or (type(default) == 'number' and not finite(d[key][i])) then d[key][i] = default; end
            end
        elseif type(d[key]) ~= type(value) then d[key] = value; end
    end
    for key, range in pairs(ranges) do d[key][1] = math.max(range[1], math.min(range[2], d[key][1])); end
    -- SliderFloat's %.0f label does not round its value. Fractional sizes otherwise
    -- create new baked fonts continuously while dragging, churning the shared atlas.
    for _, key in ipairs({ 'titleSize', 'detailSize', 'zoneTitleSize', 'zoneDetailSize', 'areaTitleSize', 'areaDetailSize',
        'locationSize', 'approachYalms', 'styleTitleSize', 'styleDetailSize', 'pennantWidth', 'pennantLength',
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

-- Settings controls and font selection.
local function changed(value) dirty = dirty or value or false; end
local function checkbox(d, label, key)
    widgets.Label(label); changed(imgui.Checkbox('##zone.' .. key, d[key]));
end
local function slider(d, label, key, format)
    widgets.Label(label);
    local range = ranges[key]; changed(imgui.SliderFloat('##zone.' .. key, d[key], range[1], range[2], format or '%.1f'));
end
local function choice(d, label, key, values)
    widgets.Label(label);
    local labels = { floating = 'Floating Text', panel = 'Themed Panel', left = 'Left', center = 'Center', right = 'Right',
        imgui = 'ImGui (Default)', gdi = 'GDI Fonts (Experimental)' };
    for id, name in pairs(styles.labels) do labels[id] = name; end
    if imgui.BeginCombo('##zone.' .. key, labels[d[key]] or d[key]) then
        for _, value in ipairs(values) do
            if imgui.Selectable(labels[value] or value, d[key] == value) then d[key] = value; changed(true); end
        end
        imgui.EndCombo();
    end
end
local location_place = true; -- The location line is put where the settings say on its next frame.
local fonts, font_files = {}, nil;
local function get_font(file)
    if file == '' then return nil; end
    if fonts[file] == nil then
        local ok, font = pcall(function() return imgui.AddFontFromFileTTF('C:\\Windows\\Fonts\\' .. file, 16); end);
        fonts[file] = (ok and font) or false;
    end
    return fonts[file] or nil;
end
local function font_choice(d, label, key, default_label)
    if not font_files then
        font_files = { '' };
        local ok, files = pcall(function() return ashita.fs.get_directory('C:\\Windows\\Fonts\\', '.*\\.ttf'); end);
        if ok and type(files) == 'table' then
            for _, file in pairs(files) do font_files[#font_files + 1] = file; end
            table.sort(font_files);
        end
    end
    widgets.Label(label);
    default_label = default_label or 'Default';
    if imgui.BeginCombo('##zone.' .. key, d[key] == '' and default_label or d[key]) then
        for _, file in ipairs(font_files) do
            if imgui.Selectable(file == '' and default_label or file, d[key] == file) then d[key] = file; changed(true); end
        end
        imgui.EndCombo();
    end
end
local function gdi_family_choice(d, label, key)
    local families, problem = require('gdi_families').List();
    widgets.Label(label);
    if imgui.BeginCombo('##zone.' .. key, d[key][1]) then
        for _, family in ipairs(families) do
            if imgui.Selectable(family, d[key][1] == family) then d[key][1] = family; changed(true); end
        end
        imgui.EndCombo();
    end
    if problem then tips.Hover('Font family enumeration failed: ' .. problem); end
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
local function draw_settings(options)
    local d = options.display;
    if widgets.Header('Announcements', true) then
        checkbox(d, 'Show Banner', 'enabled'); checkbox(d, 'Chat Announcements', 'chat');
    end
    widgets.Gap();
    if widgets.Header('Zone Entry Popup') then
        checkbox(d, 'Show Region', 'zoneRegion'); checkbox(d, 'Show Weather', 'zoneWeather');
        checkbox(d, 'Show Day And Time', 'zoneDayTime');
        tips.Hover('The Vana\'diel day and time you arrived, such as Firesday 14:20.');
    end
    widgets.Gap();
    if widgets.Header('Sub-zone Popup') then
        checkbox(d, 'Show Sub-zone Popups', 'areaEnabled');
        checkbox(d, 'Show Zone Context', 'areaZoneContext'); checkbox(d, 'Show Weather', 'areaWeather');
        checkbox(d, 'Show Day And Time', 'areaDayTime');
        tips.Hover('The Vana\'diel day and time you came to it, such as Firesday 14:20.');
        checkbox(d, 'Show Experimental Label', 'areaExperimental');
        widgets.PushControlWidth();
        slider(d, 'Approach Distance', 'approachYalms', '%.0f yalms');
        widgets.PopControlWidth();
        tips.Hover('How near a feature is announced, measured from its outline. 0 announces only inside it.');
    end
    widgets.Gap();
    if widgets.Header('Weather Popup') then
        checkbox(d, 'Show Weather Popups', 'weatherEnabled');
        tips.Hover('A popup when the weather changes. It looks like a sub-zone popup and has its Zone Context and Day And Time.');
    end
    widgets.Gap();
    if widgets.Header('Location Line') then
        checkbox(d, 'Show Location Line', 'locationEnabled');
        tips.Hover('The zone and sub-zone you are in, always shown. Drag it while unlocked.');
        changed(widgets.Lock(d.locationLocked, '##zone.locationLocked', { label = 'Lock Position',
            tooltip = 'Keeps the line where it is, and lets the mouse through it to the game. Off, it can be dragged.' }));
        widgets.Label('Position (X, Y)');
        if imgui.InputInt2('##zone.locationPosition', d.locationPosition) then changed(true); location_place = true; end
        widgets.PushControlWidth();
        slider(d, 'Text Size', 'locationSize', '%.0f px');
        widgets.PopControlWidth();
    end
    widgets.Gap();
    if widgets.Header('Timing') then
        widgets.PushControlWidth();
        slider(d, 'Hold Seconds', 'hold'); slider(d, 'Fade In Seconds', 'fadeIn'); slider(d, 'Fade Out Seconds', 'fadeOut');
        slider(d, 'Opacity', 'opacity', '%.2f');
        checkbox(d, 'Use Per-Line Timing', 'perLineTiming');
        tips.Hover('Classic Text only: each line its own delay, hold and fades. The other styles use the timing above.');
        if d.perLineTiming[1] then
            for _, line in ipairs(lines) do
                widgets.Gap();
                if widgets.Header(line[2]) then
                    slider(d, 'Start Delay', line[1] .. 'Delay');
                    slider(d, 'Hold Seconds', line[1] .. 'Hold');
                    slider(d, 'Fade In Seconds', line[1] .. 'FadeIn');
                    slider(d, 'Fade Out Seconds', line[1] .. 'FadeOut');
                end
            end
        end
        widgets.PopControlWidth();
    end
    widgets.Gap();
    if widgets.Header('Preview') then
        widgets.Label('Preview While Configuring'); imgui.Checkbox('##zone.preview', M.preview);
        if imgui.Button('Preview Zone Once') and M.on_preview then M.on_preview(); end
        if imgui.Button('Preview Sub-zone Once') and M.on_area_preview then M.on_area_preview(); end
        if imgui.Button('Preview Weather Once') and M.on_weather_preview then M.on_weather_preview(); end
    end
    widgets.Gap();
    if widgets.Header('Hide Banner') then widgets.Hide(options.hide, M.app.save); end
    commit(options);
end
local function uses(d, id) return d.zoneStyle == id or d.areaStyle == id; end
local function draw_appearance(options)
    local d = options.display;
    local styled = d.zoneStyle ~= 'classic' or d.areaStyle ~= 'classic';
    widgets.PushControlWidth();
    if widgets.Header('Banner Style', true) then
        choice(d, 'Zone Entry Style', 'zoneStyle', styles.ids);
        tips.Hover('/zone test and a style (' .. table.concat(styles.ids, ', ') .. ') shows the zone once in that style.');
        choice(d, 'Sub-zone Style', 'areaStyle', styles.ids);
        tips.Hover('Weather popups use this style too.');
        if styled then
            slider(d, 'Style Title Size', 'styleTitleSize', '%.0f px');
            slider(d, 'Style Detail Size', 'styleDetailSize', '%.0f px');
            tips.Hover('Sizes for every style but Classic Text, which has its own below.');
        end
    end
    if uses(d, 'pennant') then
        widgets.Gap();
        if widgets.Header('Pennant') then
            slider(d, 'Pennant Width', 'pennantWidth', '%.0f px');
            slider(d, 'Pennant Length', 'pennantLength', '%.0f px');
            tips.Hover('It hangs from the top of the screen; the words beside it are at the banner position.');
            slider(d, 'Largest Letter Size', 'pennantLetterSize', '%.0f px');
            tips.Hover('Long names are written smaller, to fit.');
        end
    end
    if uses(d, 'kanji') then
        widgets.Gap();
        if widgets.Header('Kanji Watermark') then
            font_choice(d, 'Japanese Font', 'kanjiFont', 'Automatic');
            local file = kanji_file(d);
            tips.Hover(file and ('Writing Japanese in ' .. file .. '.')
                or 'No Japanese font was found (IPA Mincho, Yu Mincho, MS Mincho): the watermark is left out.');
            if not file then imgui.TextDisabled('No Japanese font found: the watermark is left out.'); end
            slider(d, 'Watermark Size', 'kanjiSize', '%.0f px'); slider(d, 'Watermark Opacity', 'kanjiOpacity', '%.2f');
            checkbox(d, 'Vertical Text', 'kanjiVertical');
            tips.Hover('Names with Latin letters, digits or brackets, such as the [S] zones, are written across.');
        end
    end
    if uses(d, 'classic') then
        widgets.Gap();
        if widgets.Header('Classic Text') then
            choice(d, 'Text Renderer', 'renderer', { 'imgui', 'gdi' });
            tips.Hover('GDI draws the text with a native DLL, outside the ImGui font atlas. A failure in it can crash the client.');
            if d.renderer == 'gdi' then
                for _, field in ipairs({ { 'zoneTitleGdiFamily', 'Zone Title Family' }, { 'zoneDetailGdiFamily', 'Zone Detail Family' },
                    { 'areaTitleGdiFamily', 'Sub-zone Title Family' }, { 'areaDetailGdiFamily', 'Sub-zone Detail Family' } }) do
                    gdi_family_choice(d, field[2], field[1]);
                end
                local families, problem = require('gdi_families').List();
                if #families == 0 then imgui.Text('Windows font families could not be listed; saved selections are kept.'); end
                if problem then imgui.Text('Font enumeration error: ' .. problem); end
                checkbox(d, 'Bold Titles', 'gdiTitleBold'); checkbox(d, 'Bold Details', 'gdiDetailBold');
            else
                choice(d, 'Display Style', 'mode', { 'floating', 'panel' });
                tips.Hover('Themed Panel puts the theme\'s background, border and shadow behind the text.');
            end
            slider(d, 'Zone Title Size', 'zoneTitleSize', '%.0f px'); slider(d, 'Zone Detail Size', 'zoneDetailSize', '%.0f px');
            slider(d, 'Sub-zone Title Size', 'areaTitleSize', '%.0f px'); slider(d, 'Sub-zone Detail Size', 'areaDetailSize', '%.0f px');
            slider(d, 'Line Spacing', 'spacing', '%.0f px');
        end
    end
    if styled or d.renderer == 'imgui' then
        widgets.Gap();
        if widgets.Header('Fonts') then
            font_choice(d, 'Zone Title Font', 'zoneTitleFont'); font_choice(d, 'Zone Detail Font', 'zoneDetailFont');
            font_choice(d, 'Sub-zone Title Font', 'areaTitleFont'); font_choice(d, 'Sub-zone Detail Font', 'areaDetailFont');
            tips.Hover('From C:\\Windows\\Fonts. Default is the theme\'s font.');
        end
    end
    widgets.Gap();
    if widgets.Header('Position') then
        checkbox(d, 'Centered On Screen', 'centered');
        widgets.Label('Position / Offset (X, Y)'); changed(imgui.InputInt2('##zone.position', d.position));
        tips.Hover('Centered: X is an offset from the middle of the screen and Y is from the top. Otherwise both are screen pixels.');
        choice(d, 'Text Alignment', 'alignment', { 'left', 'center', 'right' });
    end
    widgets.Gap();
    if widgets.Header('Colors') then
        checkbox(d, 'Use Theme Text Color', 'themeText');
        tips.Hover('The dark edge round the text is Winxi Theme\'s Text Outline and Outline Color, in winxisettings.');
        if not d.themeText[1] then
            widgets.Label('Title Color'); changed(imgui.ColorEdit4('##zone.titleColor', d.titleColor));
            widgets.Label('Detail Color'); changed(imgui.ColorEdit4('##zone.detailColor', d.detailColor));
        end
    end
    widgets.Gap();
    if widgets.Header('Backdrop') then
        checkbox(d, 'Show Backdrop', 'backdrop');
        tips.Hover('A soft shadow behind the banner, so it stands out from a bright scene. Every style, and Classic Text\'s Floating Text.');
        if d.backdrop[1] then
            slider(d, 'Backdrop Opacity', 'backdropOpacity', '%.2f');
            slider(d, 'Backdrop Softness', 'backdropSoftness', '%.0f px');
            tips.Hover('How far it fades out round the words.');
        end
    end
    if uses(d, 'classic') then
        widgets.Gap();
        if widgets.Header('Background Image', false, true) then
            checkbox(d, 'Use Region Flags', 'backgroundFlags');
            tips.Hover('A nation\'s own regions show its flag, fitted inside Image Size, in place of the image.');
            checkbox(d, 'Show Background Image', 'backgroundEnabled');
            widgets.Label('Image Filename');
            changed(imgui.InputText('##zone.backgroundFile', d.backgroundFile, 256));
            tips.Hover('A PNG, JPG or BMP in zone/assets/backgrounds/.');
            widgets.Label('Image Size (Width, Height)');
            changed(imgui.InputInt2('##zone.backgroundSize', d.backgroundSize));
            widgets.Label('Image Offset (X, Y)');
            changed(imgui.InputInt2('##zone.backgroundOffset', d.backgroundOffset));
            widgets.Label('Image Opacity');
            changed(imgui.SliderFloat('##zone.backgroundOpacity', d.backgroundOpacity, 0, 1, '%.2f'));
            if background_cache.error then imgui.Text(background_cache.error); end
            if imgui.Button('Reload Background Image') then background_cache:clear(); end
        end
    end
    widgets.PopControlWidth();
    commit(options);
end
M.app = shell.New({
    defaults = defaults(), configTitle = 'Zone Settings', drawSettings = draw_settings, settingsLabel = 'Behaviour',
    leadingTabs = { { label = 'Appearance', draw = draw_appearance } }, hideAppearance = true,
    onSettings = function(options)
        M.complete(options); dirty = false; M.preview[1] = false;
        background_cache:clear();
        location_place = true;
        if M.on_settings then M.on_settings(); end
    end,
}); -- Commands are handled by zone.lua: /zone toggles settings; /zone test previews the banner.

-- Capture timing at popup creation; appearance and opacity remain live.
local function row_timing(d, key)
    return { delay = d[key .. 'Delay'][1], hold = { d[key .. 'Hold'][1] },
        fadeIn = { d[key .. 'FadeIn'][1] }, fadeOut = { d[key .. 'FadeOut'][1] }, opacity = d.opacity };
end
function M.total()
    local d = M.app.options.display; return d.hold[1] + d.fadeOut[1];
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
    state.banner_timing = { hold = { d.hold[1] }, fadeIn = { d.fadeIn[1] }, fadeOut = { d.fadeOut[1] }, opacity = d.opacity };
    state.line_timing = nil;
    if d.perLineTiming[1] then
        state.line_timing = {};
        state.visible_until = now;
        for _, row in ipairs(layout.rows(state, nil, d)) do
            local timing = row_timing(d, row.key);
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
    local region = (d.zoneRegion or d.region)[1];
    local weather = (content.banner_is_area and (d.areaWeather or d.weather)
        or (d.zoneWeather or d.weather))[1];
    local context = (d.areaZoneContext or d.zoneContext)[1];
    local experimental = (d.areaExperimental or d.experimental)[1];
    if not c.rows or c.title ~= content.title or c.zone ~= content.zone_title
        or c.region ~= content.region or c.weather ~= content.weather or c.area ~= content.banner_is_area
        or c.is_weather ~= (content.banner_is_weather or false)
        or c.show_region ~= region or c.show_weather ~= weather or c.context ~= context or c.experimental ~= experimental
        or c.vana ~= content.vana or c.zone_day ~= d.zoneDayTime[1] or c.area_day ~= d.areaDayTime[1] then
        c.rows = layout.rows(content, tracking, d);
        c.title, c.zone = content.title, content.zone_title;
        c.region, c.weather, c.area = content.region, content.weather, content.banner_is_area;
        c.is_weather = content.banner_is_weather or false;
        c.show_region, c.show_weather, c.context, c.experimental = region, weather, context, experimental;
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
local function draw_style(id, state, content, area_style, d, now, preview, timing)
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
    if id == 'pennant' and content.flag then flag_cache = flag_cache or background.new(); end
    c.flag_image = (id == 'pennant' and content.flag) and flag_cache:get(flag_only, now, content.flag) or nil;
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
    if style_id ~= 'classic' and styles.valid(style_id) then
        if gdi_backend then M.shutdown(); end
        return draw_style(style_id, state, content, area_style, d, now, preview, timing);
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
function M.draw_location(words)
    local options, d = M.app.options, M.app.options.display;
    if not d.locationEnabled[1] or not words or words == '' or game.IsHidden(options.hide) then return false; end
    local locked = d.locationLocked[1];
    local flags = bit.bor(style.TitlelessFlags(), ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoFocusOnAppearing);
    location_options.locked, location_options.clickThrough = locked, locked; -- Lock Position
    imgui.SetNextWindowPos(d.locationPosition, (locked or location_place) and ImGuiCond_Always or ImGuiCond_FirstUseEver);
    location_place = false;
    location.words, location.d, location.locked = words, d, locked;
    return window.Plain('##zone_location', location_open, flags, location_window, location_options);
end
return M;
