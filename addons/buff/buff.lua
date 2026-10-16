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
-- In the game's buff selector, with the plugin loaded, the status the game's cursor is on has
-- winxi's highlight round it in place of the game's hand, which points at where the game's icons would
-- be; a click on an icon then removes it, as does the controller's A (confirm) on the one the cursor
-- is on, with Controller Navigation on.
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
local controller = require('winxi.controller');
local sound = require('winxi.sound');
local bit = require('bit');

local windowName = 'winxi.buff';
local selecting = false; -- whether the game's buff selector is open, this frame
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
    controller = T{ true },        -- A removes the status the buff selector's cursor is on
    controllerSounds = T{ false },
    controllerType = 'xinput',     -- which kind: a key of winxi.controller's Layouts
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

local cancellable = {}; -- the same, for whether a status can be removed
local function CanCancel(id)
    local can = cancellable[id];
    if can == nil then
        local icon = AshitaCore:GetResourceManager():GetStatusIconByIndex(id);
        can = icon ~= nil and icon.CanCancel ~= 0;
        if icon ~= nil then cancellable[id] = can; end
    end
    return can;
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
            imgui.TextDisabled(selecting and 'Click, or A, to remove.' or 'Right click to remove.');
        end
    end
    imgui.EndTooltip();
    return icon ~= nil and icon.CanCancel ~= 0;
end

local current = {}; -- the statuses this frame

-- The game's buff selector, this frame: whether it is open, and which of the statuses its cursor is
-- on, by its place in current (nil without the plugin to say)
local cursorIndex = nil;

local function FindCursor(found)
    cursorIndex = nil;
    if not selecting or found == nil then
        return;
    end
    local status = hook.CursorStatus(found);
    for index, entry in ipairs(current) do
        if entry.id == status then
            cursorIndex = index;
            return;
        end
    end
end

-- The controller's A, in the selector, removes the status its cursor is on: taken from the game only
-- then, and only for a status that can be removed. The game's own A does not remove one.
local app;

local function CursorStatus()
    local status = cursorIndex ~= nil and current[cursorIndex] or nil;
    if status ~= nil and selecting and app.options.controller[1] and CanCancel(status.id) then
        return status;
    end
    return nil;
end

controller.Bind({
    active = function() return CursorStatus() ~= nil; end,
    actions = { [controller.Button.A] = 'confirm' },
    press = function()
        local status = CursorStatus();
        if status ~= nil then
            statuses.Cancel(status.id);
            sound.Play('confirm');
        end
    end,
});

-- A status is removed with a right click, or in the selector with any click
local function ClickedToRemove()
    return imgui.IsItemClicked(ImGuiMouseButton_Right) or (selecting and imgui.IsItemClicked(ImGuiMouseButton_Left));
end
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

-- winxi's highlight round the status the selector's cursor is on, as the controller draws it round
-- a window: a line, and a fainter one just outside it
local cursorGlow = { 0, 0, 0, 0 };
local cursorMin, cursorMax = { 0, 0 }, { 0, 0 };

local function GlowColor()
    local color = controller.HighlightColor;
    cursorGlow[1], cursorGlow[2], cursorGlow[3], cursorGlow[4] = color[1], color[2], color[3], color[4] * 0.35;
    return cursorGlow;
end

local function DrawCursor(drawList, x, y, width, height)
    cursorMin[1], cursorMin[2], cursorMax[1], cursorMax[2] = x - 2, y - 2, x + width + 2, y + height + 2;
    drawList:AddRect(cursorMin, cursorMax, imgui.GetColorU32(GlowColor()), 2, 0, 2);
    cursorMin[1], cursorMin[2], cursorMax[1], cursorMax[2] = x, y, x + width, y + height;
    drawList:AddRect(cursorMin, cursorMax, imgui.GetColorU32(controller.HighlightColor), 0, 0, 2);
end

-- A label's width in the font in use: measured once each, for as long as the font stays the same
local function LabelWidth(label)
    local width = labelWidths[label];
    if width == nil then
        width = imgui.CalcTextSize(label);
        labelWidths[label] = width;
    end
    return width;
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
            if canCancel and ClickedToRemove() then
                statuses.Cancel(status.id);
            end
        end
        if index == cursorIndex then
            DrawCursor(drawList, x + (cell[1] - width) / 2, y, width, height);
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
            text.Draw(drawList, x + (cell[1] - LabelWidth(label)) / 2, y + height + timerGap, textColor, label);
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
local anchoredName, hoverName = windowName .. '.anchored', windowName .. '.hooked';

local function Byte(value)
    return math.floor(math.max(0, math.min(1, value)) * 255 + 0.5);
end

-- A colour of imgui's, { r, g, b, a } from 0 to 1, as 0xAARRGGBB, faded by alpha
local function ARGB(color, alpha)
    return Byte((color[4] or 1) * alpha) * 0x1000000 + Byte(color[1]) * 0x10000 + Byte(color[2]) * 0x100 + Byte(color[3]);
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

-- The letters looked up this frame, by byte, each with the frame it was looked up in: where they
-- are in the font's texture moves when it is made again, so none is kept from one frame to the next
local glyphs, glyphFrames, glyphFrame = {}, {}, 0;

local function Glyph(baked, byte)
    if glyphFrames[byte] ~= glyphFrame then
        glyphs[byte] = baked:FindGlyph(byte) or false;
        glyphFrames[byte] = glyphFrame;
    end
    return glyphs[byte] or nil;
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

-- A frame of colour alone round x0, y0 to x1, y1, thickness wide, inside it; in imgui's pixels
local function SolidFrame(x0, y0, x1, y1, thickness, color, sx, sy)
    local solid = hook.Solid;
    hook.Quad(x0 * sx, y0 * sy, x1 * sx, (y0 + thickness) * sy, 0, 0, 0, 0, color, solid);
    hook.Quad(x0 * sx, (y1 - thickness) * sy, x1 * sx, y1 * sy, 0, 0, 0, 0, color, solid);
    hook.Quad(x0 * sx, (y0 + thickness) * sy, (x0 + thickness) * sx, (y1 - thickness) * sy, 0, 0, 0, 0, color, solid);
    hook.Quad((x1 - thickness) * sx, (y0 + thickness) * sy, x1 * sx, (y1 - thickness) * sy, 0, 0, 0, 0, color, solid);
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
        glyphFrame = glyphFrame + 1;
        baked = imgui.GetFontBaked();
        fontSlot = hook.Texture(FontTexture());
    end

    for index, status in ipairs(current) do
        local x = nudgeX + ((index - 1) % perRow) * (cellWidth + gap);
        local y = nudgeY + math.floor((index - 1) / perRow) * (cellHeight + rowGap);

        local left = x + (cellWidth - width) / 2;
        if index == cursorIndex then
            SolidFrame(left - 4, y - 4, left + width + 4, y + height + 4, 2, ARGB(GlowColor(), alpha), sx, sy);
            SolidFrame(left - 2, y - 2, left + width + 2, y + height + 2, 2, ARGB(controller.HighlightColor, alpha), sx, sy);
        end

        local handle, own = icons.Get(status.id, useOwn);
        local slot = hook.Texture(handle);
        if slot ~= nil then
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
            local pen = math.floor(x + (cellWidth - LabelWidth(label)) / 2);
            WriteWords(baked, label, pen, y + height + timerGap, sx, sy, textColor, edgeColor, fontSlot);
        end
    end
end

-- Under the mouse, a status's description, and a right click to remove it: while the game has drawn
-- the bar and no menu of the game's is open, as one may be over it. An invisible window over the
-- cell the mouse is on takes the click, so that the game does not.
local hoverCell = { 0, 0 };
local hoverPos = { 0, 0 };
local noPadding = { 0, 0 };
local hoverFlags = nil;

local function Interact(options, found)
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
    if status == nil or not hook.Drawn(found) or anchoring.MenuOpen() ~= nil then
        return;
    end

    hoverFlags = hoverFlags or bit.bor(style.TitlelessFlags(), ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav or 0);
    hoverPos[1], hoverPos[2] = x, y;
    hoverCell[1], hoverCell[2] = layout.width, layout.height;
    imgui.SetNextWindowPos(hoverPos, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, noPadding);
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    if imgui.Begin(hoverName, nil, hoverFlags) then
        imgui.Dummy(hoverCell);
        if imgui.IsItemHovered() then
            local canCancel = Tooltip(status.id);
            if canCancel and ClickedToRemove() then
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
    if options.fadeInOut[1] then alpha = fade.Presence(anchoredName, wanted); end
    if alpha <= 0.01 or statuses.Read(current, options.showTimers[1]) == 0 then
        hook.Finish();
        return;
    end
    selecting = anchoring.SelectorOpen();
    FindCursor(found);

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

local controllerTip = 'In the game\'s buff selector, A (confirm) removes the status its cursor is on, as a click does. Needs the buffhook plugin, which says which one that is.\nThe game keeps the rest of the controller: A is taken only while the cursor is on a status that can be removed.';

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

    if widgets.Header('Controller') then
        shell.ControllerSettings(options, controllerTip);
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
    -- With the plugin, the game's icons are its to stand in for: anchored, it draws the bar in their
    -- place; dragged elsewhere with them hidden, it draws nothing there, and the game's hand with them
    local found = hook.Block();
    local anchored = options.anchorToDefault[1];
    if found ~= nil and not anchored and not options.hideGameIcons[1] then
        found = nil;
    end
    UpdateGameIcons(options, found ~= nil);
    selecting, cursorIndex = false, nil;
    -- the kind of controller, and its sounds, from the settings (a key winxi does not know leaves it)
    if options.controllerType ~= controller.GetLayout() then
        controller.SetLayout(options.controllerType);
    end
    sound.SetEnabled(options.controllerSounds[1]);
    if not app:BeginFrame() then
        -- an empty bar: the game's icons stay away while the bar is hidden
        if found ~= nil then
            hook.Begin(found);
            hook.Finish();
        end
        return;
    end
    if found ~= nil and anchored then
        DrawHooked(options, found);
        return;
    end
    if found ~= nil then
        hook.Begin(found);
        hook.Finish();
    end
    -- the window is there only while there is a status to show
    if not options.isVisible[1] and not options.fadeInOut[1] then return; end
    if statuses.Read(current, options.showTimers[1]) == 0 then
        return;
    end
    selecting = anchoring.SelectorOpen();
    FindCursor(found);
    if anchored then
        anchoring.Draw(anchoredName, options, DrawStatuses);
    else
        app:Window(options.isVisible, DrawStatuses);
    end
end);
