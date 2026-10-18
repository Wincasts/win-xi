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
local layout = require('banner_layout');
local background = require('banner_background');
local background_cache = background.new();
local M = { preview = { false } };
local dirty = false;
local gdi_backend;

-- Settings defaults and validation.
local lines = { { 'zoneRegion', 'Zone: Region' }, { 'zoneTitle', 'Zone: Title' }, { 'zoneWeather', 'Zone: Weather' },
    { 'areaTitle', 'Sub-zone: Title' }, { 'areaContext', 'Sub-zone: Zone Context' }, { 'areaWeather', 'Sub-zone: Weather' } };
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
        outline = T{ 1 }, outlineColor = T{ 0, 0, 0, .9 },
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
    opacity = { 0, 1 }, outline = { 0, 3 }, approachYalms = { 0, 100 }, locationSize = { 10, 40 } };
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
        'locationSize', 'approachYalms' }) do
        d[key][1] = math.floor(d[key][1] + .5);
    end
    for _, key in ipairs({ 'titleColor', 'detailColor', 'outlineColor' }) do
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
local function font_choice(d, label, key)
    if not font_files then
        font_files = { '' };
        local ok, files = pcall(function() return ashita.fs.get_directory('C:\\Windows\\Fonts\\', '.*\\.ttf'); end);
        if ok and type(files) == 'table' then
            for _, file in pairs(files) do font_files[#font_files + 1] = file; end
            table.sort(font_files);
        end
    end
    widgets.Label(label);
    if imgui.BeginCombo('##zone.' .. key, d[key] == '' and 'Default' or d[key]) then
        for _, file in ipairs(font_files) do
            if imgui.Selectable(file == '' and 'Default' or file, d[key] == file) then d[key] = file; changed(true); end
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
    end
    widgets.Gap();
    if widgets.Header('Sub-zone Popup') then
        checkbox(d, 'Show Sub-zone Popups', 'areaEnabled');
        checkbox(d, 'Show Zone Context', 'areaZoneContext'); checkbox(d, 'Show Weather', 'areaWeather');
        checkbox(d, 'Show Experimental Label', 'areaExperimental');
        widgets.PushControlWidth();
        slider(d, 'Approach Distance', 'approachYalms', '%.0f yalms');
        widgets.PopControlWidth();
        tips.Hover('How near a feature is announced, measured from its outline. 0 announces only inside it.');
    end
    widgets.Gap();
    if widgets.Header('Weather Popup') then
        checkbox(d, 'Show Weather Popups', 'weatherEnabled');
    end
    widgets.Gap();
    if widgets.Header('Location Line') then
        checkbox(d, 'Show Location Line', 'locationEnabled');
        checkbox(d, 'Lock Position', 'locationLocked');
        widgets.Label('Position (X, Y)');
        if imgui.InputInt2('##zone.locationPosition', d.locationPosition) then changed(true); location_place = true; end
        widgets.PushControlWidth();
        slider(d, 'Text Size', 'locationSize', '%.0f px');
        widgets.PopControlWidth();
        imgui.Text('The zone and sub-zone you are in, always shown. Drag it while unlocked.');
    end
    widgets.Gap();
    if widgets.Header('Banner Position') then
        checkbox(d, 'Centered On Screen', 'centered');
        widgets.Label('Position / Offset (X, Y)'); changed(imgui.InputInt2('##zone.settingsPosition', d.position));
        choice(d, 'Text Alignment', 'alignment', { 'left', 'center', 'right' });
        imgui.Text('Centered: X offsets screen center. Otherwise X/Y are absolute pixels.');
    end
    widgets.Gap();
    if widgets.Header('Timing') then
        widgets.PushControlWidth();
        slider(d, 'Hold Seconds', 'hold'); slider(d, 'Fade In Seconds', 'fadeIn'); slider(d, 'Fade Out Seconds', 'fadeOut');
        slider(d, 'Opacity', 'opacity', '%.2f');
        checkbox(d, 'Use Per-Line Timing', 'perLineTiming');
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
local function draw_appearance(options)
    local d = options.display;
    widgets.PushControlWidth();
    choice(d, 'Text Renderer', 'renderer', { 'imgui', 'gdi' });
    if d.renderer == 'gdi' then
        imgui.Text('Experimental native DLL. Banner text bypasses the ImGui font atlas.');
        imgui.Text('GDI uses floating text only; Themed Panel is not applied.');
        for _, field in ipairs({ { 'zoneTitleGdiFamily', 'Zone Title Family' }, { 'zoneDetailGdiFamily', 'Zone Detail Family' },
            { 'areaTitleGdiFamily', 'Sub-zone Title Family' }, { 'areaDetailGdiFamily', 'Sub-zone Detail Family' } }) do
            gdi_family_choice(d, field[2], field[1]);
        end
        local families, problem = require('gdi_families').List();
        if #families == 0 then imgui.Text('Windows font families could not be listed; saved selections are retained.'); end
        if problem then imgui.Text('Font enumeration error: ' .. problem); end
        checkbox(d, 'Bold Titles', 'gdiTitleBold'); checkbox(d, 'Bold Details', 'gdiDetailBold');
    else
        choice(d, 'Display Style', 'mode', { 'floating', 'panel' });
    end
    choice(d, 'Text Alignment', 'alignment', { 'left', 'center', 'right' });
    checkbox(d, 'Centered On Screen', 'centered');
    widgets.Label('Position / Offset'); changed(imgui.InputInt2('##zone.position', d.position));
    tips.Hover('With Centered On Screen on: X is an offset from screen center; Y is from the top. Otherwise X/Y are absolute pixels. Alignment anchors the whole banner at this position.');
    if widgets.Header('Zone Entry Text', true) then
        slider(d, 'Zone Title Size', 'zoneTitleSize', '%.0f px'); slider(d, 'Zone Detail Size', 'zoneDetailSize', '%.0f px');
        if d.renderer == 'imgui' then
            font_choice(d, 'Zone Title Font', 'zoneTitleFont'); font_choice(d, 'Zone Detail Font', 'zoneDetailFont');
        end
    end
    widgets.Gap();
    if widgets.Header('Sub-zone Text') then
        slider(d, 'Sub-zone Title Size', 'areaTitleSize', '%.0f px'); slider(d, 'Sub-zone Detail Size', 'areaDetailSize', '%.0f px');
        if d.renderer == 'imgui' then
            font_choice(d, 'Sub-zone Title Font', 'areaTitleFont'); font_choice(d, 'Sub-zone Detail Font', 'areaDetailFont');
        end
    end
    widgets.Gap();
    if widgets.Header('Background Image') then
        checkbox(d, 'Use Region Flags', 'backgroundFlags');
        imgui.Text('A nation\'s own regions show its flag, fitted inside Image Size, in place of the image.');
        checkbox(d, 'Show Background Image', 'backgroundEnabled');
        widgets.Label('Image Filename');
        changed(imgui.InputText('##zone.backgroundFile', d.backgroundFile, 256));
        imgui.Text('Place PNG/JPG/BMP images in zone/assets/backgrounds/.');
        widgets.Label('Image Size (Width, Height)');
        changed(imgui.InputInt2('##zone.backgroundSize', d.backgroundSize));
        widgets.Label('Image Offset (X, Y)');
        changed(imgui.InputInt2('##zone.backgroundOffset', d.backgroundOffset));
        widgets.Label('Image Opacity');
        changed(imgui.SliderFloat('##zone.backgroundOpacity', d.backgroundOpacity, 0, 1, '%.2f'));
        imgui.Text('Image stretches to this size and follows banner alignment and fade.');
        if background_cache.error then imgui.Text(background_cache.error); end
        if imgui.Button('Reload Background Image') then background_cache:clear(); end
    end

    widgets.Gap();
    if widgets.Header('Shared Text') then
        slider(d, 'Line Spacing', 'spacing', '%.0f px');
        checkbox(d, 'Use Theme Text Color', 'themeText');
        if not d.themeText[1] then
            widgets.Label('Title Color'); changed(imgui.ColorEdit4('##zone.titleColor', d.titleColor));
            widgets.Label('Detail Color'); changed(imgui.ColorEdit4('##zone.detailColor', d.detailColor));
        end
        slider(d, 'Outline Width', 'outline', '%.1f px');
        widgets.Label('Outline Color'); changed(imgui.ColorEdit4('##zone.outlineColor', d.outlineColor));
    end
    widgets.PopControlWidth();
    if d.renderer == 'gdi' then
        imgui.Text('Select an installed Windows font family from each dropdown.');
        imgui.Text('Unavailable GDI families fall back to Arial. Native DLL failures may crash the client.');
    else
        imgui.Text('Floating Text uses winxi outlines; Themed Panel also uses theme background, border and shadow.');
        imgui.Text('Fonts are loaded from C:\\Windows\\Fonts. Unavailable fonts fall back to Default.');
    end
    commit(options);
end
M.app = shell.New({
    defaults = defaults(), configTitle = 'Zone Settings', drawSettings = draw_settings,
    drawAppearance = draw_appearance,
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
function M.start(state, now)
    local d = M.app.options.display;
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
    zone_title = 'West Ronfaure', banner_is_area = false };
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
        or c.show_region ~= region or c.show_weather ~= weather or c.context ~= context or c.experimental ~= experimental then
        c.rows = layout.rows(content, tracking, d);
        c.title, c.zone = content.title, content.zone_title;
        c.region, c.weather, c.area = content.region, content.weather, content.banner_is_area;
        c.is_weather = content.banner_is_weather or false;
        c.show_region, c.show_weather, c.context, c.experimental = region, weather, context, experimental;
    end
    return c.rows;
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
    local rows = cached_rows(content, tracking, d);
    -- A weather popup is styled as a sub-zone popup is.
    local area_style = content.banner_is_area or content.banner_is_weather or false;
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
    return window.Plain('##zone_banner', open, flags, function()
        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 0, 0 });
        local font_pushed = false;
        local ok, err = pcall(function()
            if image then background.draw_imgui(image, d, width); end
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
                    font_pushed = true;
                    local width, height = imgui.CalcTextSize(row.words);
                    imgui.PopFont();
                    font_pushed = false;
                    -- Commit only successful measurements so failures retry next frame.
                    row.width, row.height = width, height;
                    row.measured_font, row.measured_size = row.font, row.size;
                end
                maximum = math.max(maximum, row.width);
            end

            local x, y = imgui.GetCursorScreenPos();
            local draw = imgui.GetWindowDrawList();
            local edge = d.outline[1];
            for i, row in ipairs(rows) do
                if row.alpha > .01 then
                    imgui.PushFont(row.font, row.size);
                    font_pushed = true;
                    local offset = d.alignment == 'left' and 0
                        or (d.alignment == 'right' and maximum - row.width or (maximum - row.width) / 2);
                    local color = d.themeText[1] and theme.Get().TextColor
                        or (row.title and d.titleColor or d.detailColor);
                    local ratio = row.alpha / alpha;
                    local packed = imgui.GetColorU32({ color[1], color[2], color[3], color[4] * ratio });
                    local outline = d.outlineColor;
                    local dark = imgui.GetColorU32({ outline[1], outline[2], outline[3], outline[4] * ratio });
                    if edge > 0 then
                        text.Packed(draw, x + edge + offset, y + edge, packed, row.words, edge, dark);
                    else
                        draw:AddText({ x + offset, y }, packed, row.words);
                    end
                    imgui.PopFont();
                    font_pushed = false;
                end

                -- Keep delayed/expired lines' layout space without font/color work.
                local height = row.height + edge * 2;
                imgui.Dummy({ maximum + edge * 2, height });
                y = y + height;
                if i < #rows then
                    imgui.Dummy({ 0, d.spacing[1] });
                    y = y + d.spacing[1];
                end
            end
        end);
        -- Restore stacks even if measurement or drawing raises an error.
        if font_pushed then imgui.PopFont(); end
        imgui.PopStyleVar();
        if not ok then error(err, 0); end
    end, window_options);
end

-- The location line: where the player is, always shown, in a window of its own that can be dragged.
local location_open = { true };
local location_options = { alpha = 1, background = transparent, padding = 0, shadow = false };
function M.draw_location(words)
    local options, d = M.app.options, M.app.options.display;
    if not d.locationEnabled[1] or not words or words == '' or game.IsHidden(options.hide) then return false; end
    local locked = d.locationLocked[1];
    local flags = bit.bor(style.TitlelessFlags(), ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoFocusOnAppearing);
    if locked then flags = bit.bor(flags, ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoInputs); end
    imgui.SetNextWindowPos(d.locationPosition, (locked or location_place) and ImGuiCond_Always or ImGuiCond_FirstUseEver);
    location_place = false;
    return window.Plain('##zone_location', location_open, flags, function()
        imgui.PushFont(nil, d.locationSize[1]);
        local ok, err = pcall(function()
            local width, height = imgui.CalcTextSize(words);
            local x, y = imgui.GetCursorScreenPos();
            -- Over the game itself: winxi's outlined text.
            text.Draw(imgui.GetWindowDrawList(), x + 1, y + 1, theme.Get().TextColor, words, 1);
            imgui.Dummy({ width + 2, height + 2 });
            if not locked then
                -- Where it has been dragged to is kept, and saved with the other settings.
                local wx, wy = imgui.GetWindowPos();
                d.locationPosition[1], d.locationPosition[2] = math.floor(wx + .5), math.floor(wy + .5);
            end
        end);
        imgui.PopFont();
        if not ok then error(err, 0); end
    end, location_options);
end
return M;
