addon.name    = 'buff';
addon.author  = 'win';
addon.version = '1.0';
addon.desc    = 'The statuses you are under, with FFXIV\'s icons and the time each has left.';
addon.link    = 'https://github.com/Wincasts/win-xi';

-- The player's own statuses in a window, in place of the game's row of icons: each with an icon
-- of winxi's (FFXIV's: see winxi.statusicons) or the game's own where winxi has none, and the time it has left under it. After the statustimers addon (heals), which showed
-- how the times are read and how the game's own icons are switched off.
--
--   /buff           shows or hides the window (it only appears while there is a status to show)
--   /buff config    opens or closes the settings

require('common');
local imgui = require('imgui');
local widgets = require('winxi.widgets');
local shell = require('winxi.shell');
local theme = require('winxi.theme');
local text = require('winxi.text');
local fonts = require('winxi.fonts');
local icons = require('winxi.statusicons');
local native = require('native');
local statuses = require('statuses');
local anchoring = require('anchoring');

local windowName = 'winxi.buff';
local gap = 4;      -- between one icon and the next
local timerGap = 1; -- between an icon and its time

-- The settings, kept for each character. The shell adds its own: fading in and out, the rules for
-- hiding, the theme.
local defaults = T{
    isVisible = T{ true },
    pos = T{ 100, 100 }, -- kept separately for free-position mode
    anchorToDefault = T{ true },
    hideWithMenus = T{ true }, -- anchored native menus only; retain the saved setting key
    hide = T{ UnderMap = true },
    -- Separate from obsolete anchorOffset: old absolute (6,6) must not shift this anchor.
    anchorAdjustment = T{ 0, 0 },
    iconSize = T{ 40 },       -- an icon's height
    perRow = T{ 16 },         -- how many icons before a new row
    showTimers = T{ true },
    fontFile = '',          -- empty inherits the Winxi theme font
    fontSize = T{ 0 },      -- zero inherits the current font size
    hideGameIcons = T{ true },
};

-- The time left as the window writes it: seconds under a minute, then minutes, then hours. Each is
-- made once.
local labels = {};

local function Label(seconds)
    local key, format, value;
    if seconds >= 3600 then
        value = math.floor(seconds / 3600);
        key, format = 20000 + value, '%dh';
    elseif seconds >= 60 then
        value = math.floor(seconds / 60);
        key, format = 10000 + value, '%dm';
    else
        key, format, value = seconds, '%d', seconds;
    end
    local label = labels[key];
    if label == nil then
        label = format:format(value);
        labels[key] = label;
    end
    return label;
end

local timerHidden = {}; -- resource flags are static; never keep a borrowed resource pointer
local function HidesTimer(id)
    local hidden = timerHidden[id];
    if hidden == nil then
        local icon = AshitaCore:GetResourceManager():GetStatusIconByIndex(id);
        hidden = icon ~= nil and icon.HideTimer ~= 0;
        -- Retry missing resources rather than caching an early load failure.
        if icon ~= nil then timerHidden[id] = hidden; end
    end
    return hidden;
end

local function Tooltip(id)
    local resources = AshitaCore:GetResourceManager();
    local icon = resources:GetStatusIconByIndex(id);
    imgui.BeginTooltip();
    imgui.Text(('%s (%d)'):format(resources:GetString('buffs.names', id) or '?', id));
    if icon ~= nil then
        if icon.Description ~= nil and icon.Description[1] ~= nil then
            imgui.Text(icon.Description[1]);
        end
        if icon.CanCancel ~= 0 then
            imgui.TextDisabled('Right click to remove.');
        end
    end
    imgui.EndTooltip();
    return icon ~= nil and icon.CanCancel ~= 0;
end

local current = {}; -- the statuses this frame
local cell = { 0, 0 };
local cornerA, cornerB = { 0, 0 }, { 0, 0 };
local uvA, uvB = { 0, 0 }, { 1, 1 };
local white = imgui.GetColorU32({ 1, 1, 1, 1 });
local widest, textHeight, measuredFont, measuredSize;
local labelWidths = {}; -- measured only once per label for the current font and size
local function MeasureTimers()
    local font, size = imgui.GetFont(), imgui.GetFontSize();
    if widest == nil or font ~= measuredFont or size ~= measuredSize then
        measuredFont, measuredSize = font, size;
        widest = imgui.CalcTextSize('00m');
        local _, height = imgui.CalcTextSize('0');
        textHeight = height;
        for label in pairs(labelWidths) do labelWidths[label] = nil; end
    end
end

local function DrawStatusesContent(options)
    local height = options.iconSize[1];
    local width = math.floor(height * icons.OwnAspect + 0.5);
    local showTimers = options.showTimers[1];
    local useOwn = theme.Get().StatusIcons;
    local perRow = math.max(1, options.perRow[1]);
    if showTimers then MeasureTimers(); end

    -- a status has one item, as wide as its icon or its time, whichever is wider
    cell[1] = showTimers and math.max(width, widest) or width;
    cell[2] = showTimers and height + timerGap + textHeight or height;

    local drawList = imgui.GetWindowDrawList();
    local textColor = theme.Get().TextColor;
    for index, status in ipairs(current) do
        if index > 1 and (index - 1) % perRow ~= 0 then
            imgui.SameLine(0, gap);
        end

        local x, y = imgui.GetCursorScreenPos();
        imgui.Dummy(cell);
        if imgui.IsItemHovered() then
            local canCancel = Tooltip(status.id);
            if canCancel and imgui.IsItemClicked(ImGuiMouseButton_Right) then
                statuses.Cancel(status.id);
            end
        end

        local handle, own = icons.Get(status.id, useOwn);
        if handle ~= nil then
            local left = x + (cell[1] - width) / 2;
            if own then
                cornerA[1], cornerA[2], cornerB[1], cornerB[2] = left, y, left + width, y + height;
                uvA[1], uvB[1] = icons.OwnLeft, icons.OwnRight;
            else
                -- the game's icons are square: as wide as the others, in the middle of their height
                local top = y + (height - width) / 2;
                cornerA[1], cornerA[2], cornerB[1], cornerB[2] = left, top, left + width, top + width;
                uvA[1], uvB[1] = 0, 1;
            end
            drawList:AddImage(handle, cornerA, cornerB, uvA, uvB, white);
        end

        if showTimers and status.seconds ~= nil and not HidesTimer(status.id) then
            local label = Label(status.seconds);
            local labelWidth = labelWidths[label];
            if labelWidth == nil then
                labelWidth = imgui.CalcTextSize(label);
                labelWidths[label] = labelWidth;
            end
            text.Draw(drawList, x + (cell[1] - labelWidth) / 2, y + height + timerGap, textColor, label);
        end
    end
end

-- One push per bar, not per timer. The existing measurement cache follows the active font.
local function DrawStatuses(options)
    local face = fonts.Get(options.fontFile);
    local size = options.fontSize[1];
    if face == nil and size <= 0 then return DrawStatusesContent(options); end
    imgui.PushFont(face, size > 0 and size or imgui.GetFontSize());
    local ok, err = pcall(DrawStatusesContent, options);
    imgui.PopFont();
    if not ok then error(err, 0); end
end

local hideFailed = false; -- said once, if the game's icons cannot be switched off

local function ApplyGameIcons(options)
    -- Restore map hiding once, including settings migrated by the previous version.
    -- Subsequent manual changes to the shared hiding rules remain respected.
    if not options.anchoredInventoryHideUpdated then
        options.hide.UnderMap = true;
        options.anchoredInventoryHideUpdated = true;
    end
    if not native.Set(options.hideGameIcons[1]) and not hideFailed then
        hideFailed = true;
        print(('\30\81[%s]\30\01 %s'):format(addon.name, 'The game\'s own status icons could not be hidden: another addon may have hidden them already.'));
    end
end

local function DrawSettings(options)
    widgets.Label('Visible');
    imgui.Checkbox('##buff.visible', options.isVisible);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Whether the window shows while you are under a status. /buff switches this.');
    end
    widgets.Label('Hide Anchored Buffs With Menus');
    imgui.Checkbox('##buff.hideWithMenus', options.hideWithMenus);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Immediately hides the anchored bar while any native menu or macro palette is open, except the buff selector and normal chat input.\nDoes not apply in draggable mode. Expanded chat and draggable map hiding use the rules below.');
    end
    widgets.Label('Anchor To Default Location');
    imgui.Checkbox('##buff.anchorToDefault', options.anchorToDefault);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Places the bar below the help strip at the screenshot-calibrated default buff location.\nAutomatically applies the game\'s menu-to-screen scale, without a background or border.\nThis does not read live native buff coordinates or clip beneath native menus.');
    end
    if options.anchorToDefault[1] then
        widgets.Label('Anchor Adjustment');
        imgui.InputInt2('##buff.anchorAdjustment', options.anchorAdjustment);
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Optional pixel nudge from the automatic native-HUD anchor. Zero uses the default location.\nThe nudge is in screen pixels, independent of native UI scaling.');
        end
    else
        widgets.Label('Position');
        if imgui.InputInt2('##buff.position', options.pos) then
            imgui.SetWindowPos(windowName, options.pos);
        end
    end

    widgets.Gap();
    widgets.Label('Icon Size');
    widgets.PushControlWidth();
    imgui.SliderInt('##buff.iconSize', options.iconSize, 16, 96);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('How tall an icon is, in pixels. The icons are 64 tall as made: at 64, or 32, they are at their sharpest.');
    end
    widgets.Label('Icons Per Row');
    imgui.SliderInt('##buff.perRow', options.perRow, 1, 32);
    widgets.PopControlWidth();
    widgets.Label('Show Time Left');
    imgui.Checkbox('##buff.showTimers', options.showTimers);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Writes under each icon how long the status has left: seconds, then minutes (m), then hours (h).');
    end

    widgets.Label('Font');
    local file = options.fontFile;
    local opened = imgui.BeginCombo('##buff.fontFile', file ~= '' and file or 'Theme Font');
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Font for countdowns and status tooltips. Theme Font follows Winxi Theme.');
    end
    if opened then
        if imgui.Selectable('Theme Font##buff.font.theme', file == '') then options.fontFile = ''; end
        for _, choice in ipairs(fonts.Files()) do
            if imgui.Selectable(choice .. '##buff.font.' .. choice, file == choice) then
                options.fontFile = choice;
            end
        end
        imgui.EndCombo();
    end
    widgets.Label('Font Size');
    imgui.SliderInt('##buff.fontSize', options.fontSize, 0, theme.MaxFontSize,
        options.fontSize[1] > 0 and '%d px' or 'Theme Size');
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Countdown and tooltip font size in pixels. Zero inherits the theme size.\nDoes not resize the icons.');
    end

    widgets.Gap();
    widgets.Label('Hide Game\'s Icons');
    if imgui.Checkbox('##buff.hideGameIcons', options.hideGameIcons) then
        hideFailed = false;
        ApplyGameIcons(options);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Stops the game drawing its own row of status icons, which this window stands in for.\nThey come back when this is switched off, or the addon is unloaded.');
    end
end

local app = shell.New({
    defaults = defaults,
    window = windowName,
    configTitle = 'Buff Settings',
    command = '/buff',
    help = '/buff shows or hides the window; /buff config opens or closes the settings.',
    drawSettings = DrawSettings,
    onSettings = ApplyGameIcons,
});

ashita.events.register('unload', 'buff_unload', function()
    native.Set(false);
end);

ashita.events.register('d3d_present', 'buff_present', function()
    if not app:BeginFrame() then
        return;
    end
    -- Native menu/palette hiding is an explicit preference for anchored positioning only.
    if anchoring.HideForMenu(app.options) then return; end
    -- the window is there only while there is a status to show
    if not app.options.isVisible[1] and not app.options.fadeInOut[1] then return; end
    if statuses.Read(current, app.options.showTimers[1]) == 0 then
        return;
    end
    if app.options.anchorToDefault[1] then
        anchoring.Draw(windowName .. '.anchored', app.options, DrawStatuses, true);
    else
        app:Window(app.options.isVisible, DrawStatuses);
    end
end);
