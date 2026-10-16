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
--
-- Anchored to the game's icons' place, with the buffhook plugin loaded, the bar is drawn by the
-- plugin where and when the game draws its icons, in their place (hook.lua): the menus the game opens
-- over its icons are drawn over the bar, and it goes when they would. Without the plugin, or not
-- anchored, it is a window of imgui's, over everything.

-- The winxi this addon was made with, or a newer one: each addon is released with its own copy, so an
-- older one may have been put over it (winxi.version)
local winxiNeeded = 1;
do
    local ok, found = pcall(require, 'winxi.version');
    local number = ok and type(found) == 'table' and found.Number or 0;
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number);
        print(('\30\68[%s]\30\01 %s'):format(addon.name, text));
        error(text, 0);
    end
end

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
local hook = require('hook');
local fade = require('winxi.fade');
local style = require('winxi.style');
local bit = require('bit');

local windowName = 'winxi.buff';
local gap = 4;      -- between one icon and the next
local timerGap = 1; -- between an icon and its time

-- The settings, kept for each character. The shell adds its own: fading in and out, the rules for
-- hiding, the theme.
local defaults = T{
    isVisible = T{ true },
    pos = T{ 100, 100 }, -- kept separately for free-position mode
    anchorToDefault = T{ true },
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

-- The bar as the buffhook plugin draws it, in the game's icons' place: laid out as the window lays
-- it out, in imgui's pixels, and handed over in the game's. The times are in the same font as the
-- window's, a rectangle of imgui's font texture for each letter, with the same dark edge.
local rowGap = 4; -- between one row and the next, as the anchored window has it

-- A colour of imgui's, { r, g, b, a } from 0 to 1, as 0xAARRGGBB, faded by alpha
local function ARGB(color, alpha)
    local function byte(value)
        return math.floor(math.max(0, math.min(1, value)) * 255 + 0.5);
    end
    return byte((color[4] or 1) * alpha) * 0x1000000 + byte(color[1]) * 0x10000 + byte(color[2]) * 0x100 + byte(color[3]);
end

-- The font's texture as Direct3D has it, or nil while it has none: for a moment after letters of a
-- new size have been put in it
local function AskFontTexture()
    local atlas = imgui.GetFont().ContainerAtlas;
    local id = atlas.TexRef:GetTexID();
    if id == nil or id == 0 then
        id = atlas.TexData:GetTexID();
    end
    return id;
end

local function FontTexture()
    local ok, id = pcall(AskFontTexture);
    if ok and type(id) == 'number' and id ~= 0 then
        return id;
    end
    return nil;
end

-- The letters looked up this frame, by byte: where they are in the font's texture moves when it is
-- made again, so none is kept from one frame to the next
local frameGlyphs = {};

local function Glyph(baked, byte)
    local glyph = frameGlyphs[byte];
    if glyph == nil then
        glyph = baked:FindGlyph(byte) or false;
        frameGlyphs[byte] = glyph;
    end
    return glyph or nil;
end

local function WordsWidth(baked, words)
    local width = 0;
    for at = 1, #words do
        local glyph = Glyph(baked, words:byte(at));
        if glyph ~= nil then width = width + glyph.AdvanceX; end
    end
    return width;
end

local opaque = { 1, 1, 1, 1 };

-- The words at pen, top, in imgui's pixels: first the dark edge, the words again towards each corner,
-- then the words
local function WriteWords(baked, words, pen, top, sx, sy, color, edge, slot)
    for pass = 1, 5 do
        local dx, dy, tint = 0, 0, color;
        if pass <= 4 then
            dx, dy, tint = (pass % 2 == 1) and -1 or 1, (pass <= 2) and -1 or 1, edge;
        end
        local at = pen + dx;
        for index = 1, #words do
            local glyph = Glyph(baked, words:byte(index));
            if glyph ~= nil then
                if glyph.Visible ~= 0 and glyph.Visible ~= false then
                    hook.Quad((at + glyph.X0) * sx, (top + dy + glyph.Y0) * sy, (at + glyph.X1) * sx, (top + dy + glyph.Y1) * sy,
                        glyph.U0, glyph.V0, glyph.U1, glyph.V1, tint, slot);
                end
                at = at + glyph.AdvanceX;
            end
        end
    end
end

-- Where the bar's cells are, this frame, for the mouse: in imgui's pixels from the bar's corner
local layout = { width = 0, height = 0, perRow = 1 };

local function WriteHooked(options, found, alpha)
    local height = options.iconSize[1];
    local width = math.floor(height * icons.OwnAspect + 0.5);
    local showTimers = options.showTimers[1];
    local useOwn = theme.Get().StatusIcons;
    local perRow = math.max(1, options.perRow[1]);
    if showTimers then MeasureTimers(); end
    local cellWidth = showTimers and math.max(width, widest) or width;
    local cellHeight = showTimers and height + timerGap + textHeight or height;
    layout.width, layout.height, layout.perRow = cellWidth, cellHeight, perRow;

    local sx, sy = hook.Scale(found);
    local nudgeX, nudgeY = options.anchorAdjustment[1], options.anchorAdjustment[2];
    local iconColor = ARGB(opaque, alpha);
    local textColor = ARGB(theme.Get().TextColor, alpha);
    local edgeColor = ARGB(text.OutlineColor, alpha);

    local baked, fontSlot = nil, nil;
    if showTimers then
        frameGlyphs = {};
        baked = imgui.GetFontBaked();
        fontSlot = hook.Texture(FontTexture());
    end

    for index, status in ipairs(current) do
        local x = nudgeX + ((index - 1) % perRow) * (cellWidth + gap);
        local y = nudgeY + math.floor((index - 1) / perRow) * (cellHeight + rowGap);

        local handle, own = icons.Get(status.id, useOwn);
        local slot = hook.Texture(handle);
        if slot ~= nil then
            local left = x + (cellWidth - width) / 2;
            if own then
                hook.Quad(left * sx, y * sy, (left + width) * sx, (y + height) * sy,
                    icons.OwnLeft, 0, icons.OwnRight, 1, iconColor, slot);
            else
                -- the game's icons are square: as wide as the others, in the middle of their height
                local top = y + (height - width) / 2;
                hook.Quad(left * sx, top * sy, (left + width) * sx, (top + width) * sy, 0, 0, 1, 1, iconColor, slot);
            end
        end

        if baked ~= nil and fontSlot ~= nil and status.seconds ~= nil and not HidesTimer(status.id) then
            local label = Label(status.seconds);
            local pen = math.floor(x + (cellWidth - WordsWidth(baked, label)) / 2);
            WriteWords(baked, label, pen, y + height + timerGap, sx, sy, textColor, edgeColor, fontSlot);
        end
    end
end

-- Under the mouse, a status's description, and a right click to remove it: while the game has drawn
-- the bar and no menu of the game's is open, as one may be over it. An invisible window over the
-- cell the mouse is on takes the click, so that the game does not.
local hoverCell = { 0, 0 };
local hoverPos = { 0, 0 };
local hoverFlags = nil;

local function Interact(options, found)
    if not hook.Drawn(found) or anchoring.MenuOpen() ~= nil then
        return;
    end
    local left, top = hook.Origin(found);
    if left == nil then
        return;
    end
    left, top = left + options.anchorAdjustment[1], top + options.anchorAdjustment[2];
    local mx, my = imgui.GetMousePos();
    local column = math.floor((mx - left) / (layout.width + gap));
    local row = math.floor((my - top) / (layout.height + rowGap));
    if column < 0 or row < 0 or column >= layout.perRow then
        return;
    end
    local x, y = left + column * (layout.width + gap), top + row * (layout.height + rowGap);
    if mx > x + layout.width or my > y + layout.height then
        return;
    end
    local status = current[row * layout.perRow + column + 1];
    if status == nil then
        return;
    end

    hoverFlags = hoverFlags or bit.bor(style.TitlelessFlags(), ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav or 0);
    hoverPos[1], hoverPos[2] = x, y;
    hoverCell[1], hoverCell[2] = layout.width, layout.height;
    imgui.SetNextWindowPos(hoverPos, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    if imgui.Begin(windowName .. '.hooked', nil, hoverFlags) then
        imgui.Dummy(hoverCell);
        if imgui.IsItemHovered() then
            local canCancel = Tooltip(status.id);
            if canCancel and imgui.IsItemClicked(ImGuiMouseButton_Right) then
                statuses.Cancel(status.id);
            end
        end
    end
    imgui.End();
    imgui.PopStyleVar(2);
end

local function DrawHooked(options, found)
    hook.Begin(found);
    local wanted = options.isVisible[1];
    local alpha = wanted and 1 or 0;
    if options.fadeInOut[1] then alpha = fade.Presence(windowName .. '.anchored', wanted); end
    if alpha <= 0.01 or statuses.Read(current, options.showTimers[1]) == 0 then
        hook.Finish();
        return;
    end

    -- the window's font: the theme's, then the one chosen for the bar
    local pushedTheme = fonts.Push();
    local face, size = fonts.Get(options.fontFile), options.fontSize[1];
    local pushedOwn = face ~= nil or size > 0;
    if pushedOwn then imgui.PushFont(face, size > 0 and size or imgui.GetFontSize()); end
    local ok, err = pcall(WriteHooked, options, found, alpha);
    hook.Finish();
    if ok and wanted then ok, err = pcall(Interact, options, found); end
    if pushedOwn then imgui.PopFont(); end
    fonts.Pop(pushedTheme);
    if not ok then error(err, 0); end
end

local hideFailed = false; -- said once, if the game's icons cannot be switched off
local hiddenRow, hiddenOther = nil, nil; -- as the game's icons were last set

-- The game's row of icons is hidden by changing its code, unless the plugin is drawing the bar in
-- its place; the rest of its status icons as the setting says. Set again only when that changes.
local function UpdateGameIcons(options, hooked)
    local hide = options.hideGameIcons[1];
    local row = hide and not hooked;
    if row == hiddenRow and hide == hiddenOther then
        return;
    end
    hiddenRow, hiddenOther = row, hide;
    if not native.Set(row, hide) and not hideFailed then
        hideFailed = true;
        print(('\30\81[%s]\30\01 %s'):format(addon.name, 'The game\'s own status icons could not be hidden: another addon may have hidden them already.'));
    end
end

local function ApplyGameIcons(options)
    -- Restore map hiding once, including settings migrated by the previous version.
    -- Subsequent manual changes to the shared hiding rules remain respected.
    if not options.anchoredInventoryHideUpdated then
        options.hide.UnderMap = true;
        options.anchoredInventoryHideUpdated = true;
    end
    hiddenRow, hiddenOther = nil, nil;
end

local app;

local function DrawSettings(options)
    widgets.Label('Visible');
    imgui.Checkbox('##buff.visible', options.isVisible);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Whether the window shows while you are under a status. /buff switches this.');
    end
    widgets.Label('Anchor To Default Location');
    imgui.Checkbox('##buff.anchorToDefault', options.anchorToDefault);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Puts the bar where the game puts its own status icons, in their place.\nWith the buffhook plugin loaded, the game draws its menus over the bar as it does over its icons, and the bar goes when they would.\nWithout it the bar is drawn over everything.');
    end
    if options.anchorToDefault[1] then
        local problem = hook.Problem();
        if problem ~= nil then
            imgui.PushTextWrapPos(0);
            imgui.TextDisabled(problem);
            imgui.PopTextWrapPos();
        end
        widgets.Label('Anchor Adjustment');
        imgui.InputInt2('##buff.anchorAdjustment', options.anchorAdjustment);
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Optional pixel nudge from where the game puts its first icon. Zero puts the bar there.\nThe nudge is in screen pixels, independent of native UI scaling.');
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
        imgui.SetTooltip('Stops the game drawing its own status icons, which this window stands in for.\nThey come back when this is switched off, or the addon is unloaded.\nAnchored with the buffhook plugin, the bar takes the place of the game\'s row of icons whatever this says.');
    end
end

app = shell.New({
    defaults = defaults,
    window = windowName,
    configTitle = 'Buff Settings',
    command = '/buff',
    help = '/buff shows or hides the window; /buff config opens or closes the settings.',
    drawSettings = DrawSettings,
    onSettings = ApplyGameIcons,
});

ashita.events.register('unload', 'buff_unload', function()
    native.Set(false, false);
end);

ashita.events.register('d3d_present', 'buff_present', function()
    local options = app.options;
    -- anchored, with the plugin to draw it in the game's icons' place
    local found = options.anchorToDefault[1] and hook.Block() or nil;
    UpdateGameIcons(options, found ~= nil);
    if not app:BeginFrame() then
        -- an empty bar: the game's icons stay away while the bar is hidden
        if found ~= nil then
            hook.Begin(found);
            hook.Finish();
        end
        return;
    end
    if found ~= nil then
        DrawHooked(options, found);
        return;
    end
    -- the window is there only while there is a status to show
    if not options.isVisible[1] and not options.fadeInOut[1] then return; end
    if statuses.Read(current, options.showTimers[1]) == 0 then
        return;
    end
    if options.anchorToDefault[1] then
        anchoring.Draw(windowName .. '.anchored', options, DrawStatuses);
    else
        app:Window(options.isVisible, DrawStatuses);
    end
end);
