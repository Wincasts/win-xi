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
-- In the game's buff selector, with the plugin loaded, the game's hand (which points at where the
-- game's icons would be) is drawn again at the left of the status the game's cursor is on; a click on an icon then removes it.
-- The controller's confirm (A, or the bottom face button of a DirectInput make) on the status the cursor is on removes it
-- too: the press is left to the game, and if the game has not asked for the status to be removed a moment later, buff asks.
--
-- Anchored to the game's icons' place, with the uihook plugin loaded, the bar is drawn by the
-- plugin where and when the game draws its icons, in their place (hook.lua): the menus the game opens
-- over its icons are drawn over the bar, and it goes when they would. Without the plugin, or not
-- anchored, it is a window of imgui's, over everything.

-- The winxi this addon was made with, or a newer one: each addon is released with its own copy, so an
-- older one may have been put over it (winxi.version)
local winxiNeeded = 57; -- winxi.abi: uihook's block read as plugins/ABI.md promises
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
local tips = require('winxi.tooltip');
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
local anchor = require('winxi.anchor');
local hand = require('winxi.cursor');
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
    lockPosition = T{ false }, -- off, the bar is dragged: anchored, its adjustment; else the window
    iconSize = T{ 40 },       -- an icon's height
    perRow = T{ 16 },         -- how many icons before a new row
    showTimers = T{ true },
    fontFile = '',          -- empty inherits the Winxi theme font
    fontSize = T{ 0 },      -- zero inherits the current font size
    hideGameIcons = T{ true },
    growFrom = 'Left',      -- which way a row grows as statuses come: Left, Right or Middle
    showBackdrop = T{ true }, -- the dragged window's backdrop, border and shadow
    cursorSize = T{ 60 },     -- the selector's hand, as a share of an icon's height, in percent
    controller = T{ true },        -- the controller's confirm in the selector removes the status
    controllerSounds = T{ false },
    controllerType = 'xinput',     -- which DirectInput make, a key of winxi.controller's Layouts
};

-- Grow From: where a row's icons sit across the bar. Anchored, the bar is as wide as a full row of
-- Icons Per Row, from where it is placed: Left keeps them at its left, as the game does, Right at its
-- right and Middle in its middle. The dragged window holds the matching corner of itself still.
local growAligns = { Left = 0, Right = 1, Middle = 0.5 };
local growCorners = { Left = 'TopLeft', Right = 'TopRight', Middle = 'TopCenter' };
local growModes = { 'Left', 'Right', 'Middle' };

local function GrowAlign(options)
    return growAligns[options.growFrom] or 0;
end

-- How wide count cells are, side by side
local function RowWidth(count, cellWidth)
    return count * cellWidth + (count - 1) * gap;
end

-- How far right of the bar's left the row the index-th of count statuses is in starts, in a bar
-- span wide
local function RowShift(index, count, perRow, cellWidth, span, align)
    if align == 0 then
        return 0;
    end
    local first = index - (index - 1) % perRow;
    return math.floor(align * (span - RowWidth(math.min(perRow, count - first + 1), cellWidth)) + 0.5);
end

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
    if tips.Begin() then
        imgui.Text(('%s (%d)'):format(resources:GetString('buffs.names', id) or '?', id));
        if icon ~= nil then
            if icon.Description ~= nil and icon.Description[1] ~= nil then
                imgui.Text(icon.Description[1]);
            end
            if icon.CanCancel ~= 0 then
                imgui.TextDisabled(selecting and 'Click, or confirm, to remove.' or 'Right click to remove.');
            end
        end
        tips.End();
    end
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

local app;

-- Anchored, the bar is dragged with the left button to move it from where the game puts its icons:
-- its Anchor Adjustment. Not in the selector, where a click removes a status, nor with Lock Position.
local dragFrom = nil; -- the mouse and the adjustment as the drag began, while one is going on
local dragStart = { 0, 0, 0, 0 };

local function StartDrag(options)
    if dragFrom ~= nil or selecting or options.lockPosition[1] or not options.anchorToDefault[1]
        or not imgui.IsMouseClicked(ImGuiMouseButton_Left) then
        return;
    end
    dragStart[1], dragStart[2] = imgui.GetMousePos();
    dragStart[3], dragStart[4] = options.anchorAdjustment[1], options.anchorAdjustment[2];
    dragFrom = dragStart;
end

-- Once a frame: the adjustment follows the mouse until the button is let go, and is then saved
local function FollowDrag(options)
    if dragFrom == nil then
        return;
    end
    if not imgui.IsMouseDown(ImGuiMouseButton_Left) or not options.anchorToDefault[1] then
        dragFrom = nil;
        app:Save();
        return;
    end
    local mx, my = imgui.GetMousePos();
    options.anchorAdjustment[1] = math.floor(dragFrom[3] + mx - dragFrom[1] + 0.5);
    options.anchorAdjustment[2] = math.floor(dragFrom[4] + my - dragFrom[2] + 0.5);
end

-- A status is removed with a right click, or in the selector with any click
local function ClickedToRemove()
    return imgui.IsItemClicked(ImGuiMouseButton_Right) or (selecting and imgui.IsItemClicked(ImGuiMouseButton_Left));
end

-- The controller's confirm in the selector removes the status its cursor is on. The press is never
-- kept from the game, which may remove it itself: its own request (0xF1) for that status, seen going
-- out within confirmWait, is enough, and buff asks only when none was. XInput's A is always heard;
-- on DirectInput the bottom face button of the make chosen (PlayStation's cross for XInput).
local confirmWait = 0.25;
local confirmed = nil; -- { id, at }: a status confirmed in the selector, not yet asked to be removed

local cancellable = {};
local function CanCancel(id)
    local can = cancellable[id];
    if can == nil then
        local icon = AshitaCore:GetResourceManager():GetStatusIconByIndex(id);
        can = icon ~= nil and icon.CanCancel ~= 0;
        if icon ~= nil then cancellable[id] = can; end
    end
    return can;
end

local function Confirmed()
    local status = cursorIndex ~= nil and current[cursorIndex] or nil;
    if status == nil or not selecting or not app.options.controller[1] or not CanCancel(status.id) then
        return;
    end
    confirmed = { id = status.id, at = os.clock() };
    if app.options.controllerSounds[1] then
        sound.Play('confirm');
    end
end

-- The DirectInput button (DIJOYSTATE's offset) that is the bottom face button of the make chosen
local function DirectConfirm()
    local fallback;
    for _, layout in ipairs(controller.Layouts) do
        if layout.buttons ~= nil then
            for offset, button in pairs(layout.buttons) do
                if button == controller.Button.A then
                    if layout.key == app.options.controllerType then return offset; end
                    if layout.key == 'playstation' then fallback = offset; end
                end
            end
        end
    end
    return fallback;
end

ashita.events.register('xinput_button', 'buff_xinput', function(e)
    if e.button == controller.Button.A and e.state == 1 then Confirmed(); end
end);

ashita.events.register('dinput_button', 'buff_dinput', function(e)
    if e.state == 128 and e.button == DirectConfirm() then Confirmed(); end
end);

-- The game's own request to remove the confirmed status
ashita.events.register('packet_out', 'buff_packet_out', function(e)
    if confirmed == nil or e.id ~= 0xF1 or e.injected then return; end
    local data = e.data;
    if type(data) == 'string' and #data >= 6 and data:byte(5) + data:byte(6) * 256 == confirmed.id then
        confirmed = nil;
    end
end);

-- Once a frame: buff asks for a confirmed status the game has not
local function FollowConfirm()
    if confirmed ~= nil and os.clock() - confirmed.at >= confirmWait then
        statuses.Cancel(confirmed.id);
        confirmed = nil;
    end
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
local handUvA, handUvB = { 0, 0 }, { 0, 0 };

local function GlowColor()
    local color = controller.HighlightColor;
    cursorGlow[1], cursorGlow[2], cursorGlow[3], cursorGlow[4] = color[1], color[2], color[3], color[4] * 0.35;
    return cursorGlow;
end

-- The game's hand, as its menus point with it (the right-pointing anc_s, read from its menu DAT),
-- at the left of the status the selector's cursor is on: its fingertip, the pivot, at the icon's
-- left edge, the hand Cursor Size of the icon's height and in the middle of it. nil where the hand
-- could not be read: the highlight is drawn round the status instead.
local handLeft, handTop, handRight, handBottom = 0, 0, 0, 0;
local function HandAt(x, y, height, percent)
    local handle, frame = hand.Get();
    if handle == nil then
        return nil;
    end
    local corners, scale = frame.corners, height * percent / 100 / frame[6];
    local pivotY = y + (height - (corners[8] + corners[2]) * scale) / 2;
    handLeft, handTop = x + corners[1] * scale, pivotY + corners[2] * scale;
    handRight, handBottom = x + corners[7] * scale, pivotY + corners[8] * scale;
    return handle, frame;
end

local function DrawCursor(drawList, x, y, width, height, percent)
    local handle, frame = HandAt(x, y, height, percent);
    if handle ~= nil then
        cursorMin[1], cursorMin[2], cursorMax[1], cursorMax[2] = handLeft, handTop, handRight, handBottom;
        handUvA[1], handUvA[2], handUvB[1], handUvB[2] = frame[1], frame[2], frame[3], frame[4];
        -- over the window's edge, where it points at a row's first status
        local over = imgui.GetForegroundDrawList ~= nil and imgui.GetForegroundDrawList() or drawList;
        over:AddImage(handle, cursorMin, cursorMax, handUvA, handUvB, white);
        return;
    end
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

local fullSpan = false; -- whether the bar being drawn is anchored: as wide as a full row, for Grow From

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
    local count, align = #current, GrowAlign(options);
    local span = RowWidth(fullSpan and perRow or math.min(count, perRow), cell[1]);
    local left = imgui.GetCursorPosX();
    for index, status in ipairs(current) do
        if index > 1 and (index - 1) % perRow ~= 0 then
            imgui.SameLine(0, gap);
        elseif align ~= 0 then
            imgui.SetCursorPosX(left + RowShift(index, count, perRow, cell[1], span, align));
        end

        local x, y = imgui.GetCursorScreenPos();
        imgui.Dummy(cell);
        if imgui.IsItemHovered() then
            StartDrag(options);
            local canCancel = Tooltip(status.id);
            if canCancel and ClickedToRemove() then
                statuses.Cancel(status.id);
            end
        end
        if index == cursorIndex then
            DrawCursor(drawList, x + (cell[1] - width) / 2, y, width, height, options.cursorSize[1]);
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

-- The bar as the uihook plugin draws it, in the game's icons' place: laid out as the window lays
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

-- The letters of the font in use, by byte, copied out of imgui once each: each field of imgui's is a
-- call into it, and a bar's times read thousands a frame. Where a letter is in the font's texture
-- moves when imgui makes the texture again, so one letter is looked at each frame, and when it has
-- moved, or the font, its size or its texture is another, the letters are looked up afresh.
-- glyphsMade goes up each time, for whoever keeps something made from them.
local PROBE = 48; -- '0', which every time has
local glyphs, glyphsMade = {}, 0;
local glyphFont, glyphSize, glyphTexture = nil, nil, nil;
local probe = { 0, 0, 0, 0 };

local function CheckGlyphs(baked, texture)
    local font, size = imgui.GetFont(), imgui.GetFontSize();
    local found = baked:FindGlyph(PROBE);
    local u0, v0, u1, v1 = 0, 0, 0, 0;
    if found ~= nil then u0, v0, u1, v1 = found.U0, found.V0, found.U1, found.V1; end
    if font ~= glyphFont or size ~= glyphSize or texture ~= glyphTexture
        or u0 ~= probe[1] or v0 ~= probe[2] or u1 ~= probe[3] or v1 ~= probe[4] then
        glyphFont, glyphSize, glyphTexture = font, size, texture;
        probe[1], probe[2], probe[3], probe[4] = u0, v0, u1, v1;
        for byte in pairs(glyphs) do glyphs[byte] = nil; end
        glyphsMade = glyphsMade + 1;
    end
end

-- { x0, y0, x1, y1, u0, v0, u1, v1, advance, visible }, or nil where the font has no such letter
local function Glyph(baked, byte)
    local glyph = glyphs[byte];
    if glyph == nil then
        local found = baked:FindGlyph(byte);
        glyph = found ~= nil and { found.X0, found.Y0, found.X1, found.Y1, found.U0, found.V0, found.U1, found.V1,
            found.AdvanceX, found.Visible ~= 0 and found.Visible ~= false } or false;
        glyphs[byte] = glyph;
    end
    return glyph or nil;
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
                if glyph[10] then
                    hook.Quad((at + glyph[1]) * sx, (top + dy + glyph[2]) * sy, (at + glyph[3]) * sx, (top + dy + glyph[4]) * sy,
                        glyph[5], glyph[6], glyph[7], glyph[8], tint, slot);
                end
                at = at + glyph[9];
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
local layout = { width = 0, height = 0, perRow = 1, align = 0 };

-- Everything the bar handed over is made from, in order, this frame and the last that wrote it. The
-- bar changes as a time does, about once a second: a frame whose are the same as the last's hands
-- over what is there again, and writes nothing.
local made, last = {}, {};
-- each status's icon (the texture, its place on it or nil for the whole, whether it is the set's
-- shape) and its time as written (or false): once a frame
local handles, places, owns, labels = {}, {}, {}, {};

-- A status's icon for the plugin: from winxi's sheet of every icon where it is on it already (the
-- set's with the game's for the rest, or the game's alone with Custom Icons off), so that the bar is
-- drawn from a texture or two; from its own until then, as the sheet is filled a few a frame.
local function BarIcon(id, useOwn, sheet)
    if sheet ~= nil then
        local place, own;
        if useOwn then
            place, own = icons.MixedPlace(id);
        else
            place, own = icons.GameSheetPlace(id), false;
        end
        if place ~= nil then
            return sheet, place, own;
        end
    end
    local handle, own = icons.Get(id, useOwn);
    return handle, nil, own;
end
local madeCount, lastCount = 0, -1;

local function Note(value)
    madeCount = madeCount + 1;
    made[madeCount] = value;
end

local function Unchanged()
    if madeCount ~= lastCount then
        return false;
    end
    for index = 1, madeCount do
        if made[index] ~= last[index] then
            return false;
        end
    end
    return true;
end

-- An empty bar, for the game's icons to stay away while the bar is not shown: written once, then
-- handed over again as it was. It leaves nothing for WriteHooked to compare with.
local emptyHanded = false;

local function HandEmpty(found)
    if emptyHanded and hook.Holds(found) then
        hook.Keep(found);
        return;
    end
    hook.Begin(found);
    hook.Finish();
    emptyHanded, lastCount = true, -1;
end

local function WriteHooked(options, found, alpha)
    local height = options.iconSize[1];
    local width = math.floor(height * icons.OwnAspect + 0.5);
    local showTimers = options.showTimers[1];
    local useOwn = theme.Get().StatusIcons;
    local perRow = math.max(1, options.perRow[1]);
    if showTimers then MeasureTimers(); end
    local cellWidth = showTimers and math.max(width, widest) or width;
    local cellHeight = showTimers and height + timerGap + textHeight or height;
    local align = GrowAlign(options);
    layout.width, layout.height, layout.perRow, layout.align = cellWidth, cellHeight, perRow, align;

    local sx, sy = hook.Scale(found);
    local nudgeX, nudgeY = options.anchorAdjustment[1], options.anchorAdjustment[2];
    local iconColor = ARGB(opaque, alpha);
    local textColor = ARGB(theme.Get().TextColor, alpha);
    local edgeColor = ARGB(text.EdgeColor(), alpha);

    local baked, texture = nil, nil;
    if showTimers then
        baked = imgui.GetFontBaked();
        -- the plugin is given the mark, and reads imgui's font texture itself: which texture it is
        -- (imgui's unique id) is what says the letters may have moved
        local which;
        texture, which = fonts.Texture();
        if texture == nil then which = nil; end
        if baked ~= nil then CheckGlyphs(baked, which); end
    end

    madeCount = 0;
    Note(cellWidth); Note(cellHeight); Note(perRow); Note(width); Note(height); Note(useOwn);
    Note(sx); Note(sy); Note(nudgeX); Note(nudgeY); Note(iconColor); Note(textColor); Note(edgeColor);
    Note(cursorIndex or 0); Note(texture or 0); Note(glyphsMade); Note(baked ~= nil); Note(align);
    -- the hand's frame, as it moves: written afresh with each, while the selector is open
    local handle, handFrame = nil, nil;
    if cursorIndex ~= nil then
        handle, handFrame = hand.Get();
    end
    Note(handFrame or false); Note(options.cursorSize[1]);
    local sheet = useOwn and icons.MixedSheet() or icons.GameSheet();
    for index, status in ipairs(current) do
        Note(status.id);
        local handle, place, own = BarIcon(status.id, useOwn, sheet);
        handles[index], places[index], owns[index] = handle, place, own;
        Note(handle or 0); Note(place or false); Note(own);
        local label = status.seconds ~= nil and showTimers and not HidesTimer(status.id) and Label(status.seconds) or false;
        labels[index] = label;
        Note(label);
    end
    if Unchanged() then
        return false;
    end
    made, last = last, made;
    lastCount, emptyHanded = madeCount, false;

    local fontSlot = hook.Texture(texture);
    local count, span = #current, RowWidth(perRow, cellWidth);
    for index, status in ipairs(current) do
        local x = nudgeX + RowShift(index, count, perRow, cellWidth, span, align) + ((index - 1) % perRow) * (cellWidth + gap);
        local y = nudgeY + math.floor((index - 1) / perRow) * (cellHeight + rowGap);

        local left = x + (cellWidth - width) / 2;
        if index == cursorIndex and handle == nil then
            SolidFrame(left - 4, y - 4, left + width + 4, y + height + 4, 2, ARGB(GlowColor(), alpha), sx, sy);
            SolidFrame(left - 2, y - 2, left + width + 2, y + height + 2, 2, ARGB(controller.HighlightColor, alpha), sx, sy);
        end

        local slot = hook.Texture(handles[index]);
        if slot ~= nil then
            local place, own = places[index], owns[index];
            local u0, v0, u1, v1 = 0, 0, 1, 1;
            if place ~= nil then
                u0, v0, u1, v1 = place[1], place[2], place[3], place[4];
            elseif own then
                u0, u1 = icons.OwnLeft, icons.OwnRight;
            end
            -- the game's icons are square: as wide as the others, in the middle of their height
            local top = own and y or y + (height - width) / 2;
            local bottom = own and y + height or top + width;
            hook.Quad(left * sx, top * sy, (left + width) * sx, bottom * sy, u0, v0, u1, v1, iconColor, slot);
        end

        local label = labels[index];
        if baked ~= nil and fontSlot ~= nil and label then
            local pen = math.floor(x + (cellWidth - LabelWidth(label)) / 2);
            WriteWords(baked, label, pen, y + height + timerGap, sx, sy, textColor, edgeColor, fontSlot);
        end
    end
    -- the hand over the icons, at the left of the cursor's status, over the one before it
    if handle ~= nil and cursorIndex <= count then
        local index = cursorIndex;
        local x = nudgeX + RowShift(index, count, perRow, cellWidth, span, align) + ((index - 1) % perRow) * (cellWidth + gap);
        local y = nudgeY + math.floor((index - 1) / perRow) * (cellHeight + rowGap);
        HandAt(x + (cellWidth - width) / 2, y, height, options.cursorSize[1]);
        hook.Quad(handLeft * sx, handTop * sy, handRight * sx, handBottom * sy,
            handFrame[1], handFrame[2], handFrame[3], handFrame[4], iconColor, hook.Texture(handle));
    end
    return true;
end

-- The rows of the bar handed over, from its first icon's corner: their left, top, right and bottom
local function BarBounds(left, top, count, perRow, cellWidth, cellHeight, span, align)
    local rows = math.ceil(count / perRow);
    local x0, x1 = math.huge, -math.huge;
    for row = 0, rows - 1 do
        local index = row * perRow + 1;
        local rowLeft = left + RowShift(index, count, perRow, cellWidth, span, align);
        x0 = math.min(x0, rowLeft);
        x1 = math.max(x1, rowLeft + RowWidth(math.min(perRow, count - index + 1), cellWidth));
    end
    return x0, top, x1, top + rows * cellHeight + (rows - 1) * rowGap;
end

-- Under the mouse, a status's description, and a right click to remove it: while the game has drawn
-- the bar and no menu of the game's is open, as one may be over it. An invisible window over the
-- cell the mouse is on takes the click, so that the game does not. Between the icons an invisible
-- window over the whole bar takes it instead: anywhere on the bar starts a drag.
local hoverCell = { 0, 0 };
local hoverPos = { 0, 0 };
local noPadding = { 0, 0 };
local hoverFlags = nil;

local function Interact(options, found)
    local left, top = hook.Origin(found);
    if left == nil or #current == 0 then
        return;
    end
    left, top = left + options.anchorAdjustment[1], top + options.anchorAdjustment[2];
    local mx, my = imgui.GetMousePos();
    local perRow, count = layout.perRow, #current;
    local span = RowWidth(perRow, layout.width);
    local x0, y0, x1, y1 = BarBounds(left, top, count, perRow, layout.width, layout.height, span, layout.align);
    if mx < x0 or mx >= x1 or my < y0 or my >= y1 or not hook.Drawn(found) or anchoring.MenuOpen() ~= nil then
        return;
    end

    -- the status under the mouse, if it is on one
    local status, x, y = nil, x0, y0;
    local row = math.floor((my - top) / (layout.height + rowGap));
    if my >= top and row * perRow < count then
        local rowLeft = left + RowShift(row * perRow + 1, count, perRow, layout.width, span, layout.align);
        local column = math.floor((mx - rowLeft) / (layout.width + gap));
        if mx >= rowLeft and column < perRow then
            local cx, cy = rowLeft + column * (layout.width + gap), top + row * (layout.height + rowGap);
            if mx <= cx + layout.width and my <= cy + layout.height then
                status = current[row * perRow + column + 1];
                if status ~= nil then
                    x, y = cx, cy;
                end
            end
        end
    end

    hoverFlags = hoverFlags or bit.bor(style.TitlelessFlags(), ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav or 0);
    hoverPos[1], hoverPos[2] = x, y;
    if status ~= nil then
        hoverCell[1], hoverCell[2] = layout.width, layout.height;
    else
        hoverCell[1], hoverCell[2] = x1 - x0, y1 - y0;
    end
    imgui.SetNextWindowPos(hoverPos, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, noPadding);
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    if imgui.Begin(hoverName, nil, hoverFlags) then
        imgui.Dummy(hoverCell);
        if imgui.IsItemHovered() then
            StartDrag(options);
            if status ~= nil then
                local canCancel = Tooltip(status.id);
                if canCancel and ClickedToRemove() then
                    statuses.Cancel(status.id);
                end
            end
        end
    end
    imgui.End();
    imgui.PopStyleVar(2);
end

local function DrawHooked(options, found)
    local wanted = options.isVisible[1];
    local alpha = wanted and 1 or 0;
    if options.fadeInOut[1] then alpha = fade.Presence(anchoredName, wanted); end
    if alpha <= 0.01 or statuses.Read(current, options.showTimers[1]) == 0 then
        HandEmpty(found);
        return;
    end
    selecting = anchoring.SelectorOpen();
    FindCursor(found);

    -- the window's font: the theme's, then the one chosen for the bar
    local pushedTheme = fonts.Push();
    local face, size = fonts.Get(options.fontFile), options.fontSize[1];
    local pushedOwn = face ~= nil or size > 0;
    if pushedOwn then imgui.PushFont(face, size > 0 and size or imgui.GetFontSize()); end
    -- a plugin loaded again since has nothing of the last bar
    if not hook.Holds(found) then
        lastCount = -1;
    end
    hook.Begin(found);
    local ok, written = pcall(WriteHooked, options, found, alpha);
    local err = written;
    if ok and not written then
        hook.Keep(found);
    else
        hook.Finish();
        if not ok then lastCount = -1; end
    end
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

-- A position as two sliders, X and Y, across the screen: from 0, or from as far the other way for a
-- nudge. Returns whether either was changed.
local sliderIds = {};
local sliderBox = { 0 };
local nudgeSpec = { format = '%d px', parent = true };

local function AxisSlider(values, axis, label, id, low, high, sentence, spec)
    sliderBox[1] = values[axis];
    local changed = widgets.Slider(label, sentence, sliderBox, low, high, id, spec);
    if changed then values[axis] = sliderBox[1]; end
    return changed;
end

local function PositionSliders(values, label, id, signed, sentenceX, sentenceY, spec)
    local display = imgui.GetIO().DisplaySize;
    local width = math.floor(display.x or display[1] or 1920);
    local height = math.floor(display.y or display[2] or 1080);
    local ids = sliderIds[id];
    if ids == nil then
        ids = { label .. ' X', label .. ' Y', id .. 'X', id .. 'Y' };
        sliderIds[id] = ids;
    end
    local changedX = AxisSlider(values, 1, ids[1], ids[3], signed and -width or 0, width, sentenceX, spec);
    local changedY = AxisSlider(values, 2, ids[2], ids[4], signed and -height or 0, height, sentenceY, spec);
    return changedX or changedY;
end

local controllerTip = 'In the game\'s buff selector, confirm (A, or the bottom face button) removes the status its cursor is on, as a click does. Needs the uihook plugin, which says which one that is.\nThe press still reaches the game: buff asks for the status to be removed only when the game has not, a moment later.\nAn XInput controller\'s A is always heard; Controller Type picks the DirectInput make (PlayStation with XInput chosen).';

local lockSpec = { description = 'Keeps the bar where it is. Off, drag it with the mouse to move it.' };
local fontSpec = { description = 'The font for the times and the status tooltips. Theme Font follows the Winxi Theme.' };
local sizeSpec = { description = 'How big the times and tooltips are. Theme Size follows the Winxi Theme.' };

local function DrawSettings(options)
    if widgets.Header('Window', true) then
        widgets.Check('Visible', 'Shows the bar while you are under a status. /buff switches it too.', options.isVisible, '##buff.visible');
        widgets.Check('Anchor To Default Location', 'Puts the bar where the game default status icons are.', options.anchorToDefault, '##buff.anchorToDefault');
        if options.anchorToDefault[1] then
            local problem = hook.Problem();
            if problem ~= nil then
                widgets.Note(problem);
            end
            PositionSliders(options.anchorAdjustment, 'Anchor Adjustment', '##buff.anchorAdjustment', true,
                'How far the bar is moved sideways from the game default icons. Dragging the bar sets it too.',
                'How far the bar is moved up or down from them.', nudgeSpec);
        else
            if PositionSliders(options.pos, 'Position', '##buff.position', false,
                'How far the bar\'s corner is from the left of the screen. Dragging the bar sets it too.',
                'How far the bar\'s corner is from the top of the screen.', widgets.Pixels) then
                imgui.SetWindowPos(windowName, options.pos);
                anchor.Reset(windowName);
            end
        end
        widgets.Lock(options.lockPosition, '##buff.lockPosition', lockSpec);
        widgets.Check('Show Backdrop', 'A background and border behind the bar. Off, the icons sit straight over the game.', options.showBackdrop, '##buff.showBackdrop');
        if widgets.Check('Hide Game Default Icons', 'Hides the game default status icons, since this bar stands in for them.', options.hideGameIcons, '##buff.hideGameIcons') then
            hideFailed = false;
            ApplyGameIcons(options);
        end
    end

    if widgets.Header('Icons') then
        widgets.Slider('Icon Size', 'How tall each icon is. At 32 or 64 they are at their sharpest.', options.iconSize, 16, 96, '##buff.iconSize', widgets.Pixels);
        widgets.Slider('Cursor Size', 'How big the game default pointing hand is in the buff selector, compared with an icon.', options.cursorSize, 25, 100, '##buff.cursorSize', widgets.Percent);
        widgets.Slider('Icons Per Row', 'How many icons sit in a row before a new row starts.', options.perRow, 1, 32, '##buff.perRow');
        local chosen = widgets.Dropdown('Grow From', 'Which way a row fills as statuses come and go.', growModes, options.growFrom, '##buff.growFrom');
        if chosen ~= nil then
            options.growFrom = chosen;
        end
        widgets.Check('Show Time Left', 'Writes under each icon how long the status has left.', options.showTimers, '##buff.showTimers');
        widgets.FontFile(options, 'fontFile', '##buff.fontFile', fontSpec);
        widgets.FontSize(options, 'fontSize', '##buff.fontSize', sizeSpec);
    end

    if widgets.Header('Controller') then
        controller.SetLayout(options.controllerType);
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

local windowExtra = {}; -- for the dragged window: whether it is locked
local clear = { 0, 0, 0, 0 }; -- the dragged window's backdrop and border with Show Backdrop off

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
    FollowConfirm();
    selecting, cursorIndex = false, nil;
    if not app:BeginFrame() then
        -- an empty bar: the game's icons stay away while the bar is hidden
        if found ~= nil then
            HandEmpty(found);
        end
        return;
    end
    FollowDrag(options);
    if found ~= nil and anchored then
        DrawHooked(options, found);
        return;
    end
    if found ~= nil then
        HandEmpty(found);
    end
    -- the window is there only while there is a status to show
    if not options.isVisible[1] and not options.fadeInOut[1] then return; end
    if statuses.Read(current, options.showTimers[1]) == 0 then
        return;
    end
    selecting = anchoring.SelectorOpen();
    FindCursor(found);
    fullSpan = anchored;
    if anchored then
        anchoring.Draw(anchoredName, options, DrawStatuses);
    else
        windowExtra.locked = options.lockPosition[1] or nil;
        local look = app.windowStyle;
        if options.showBackdrop[1] then
            look.background, look.border, look.shadow = nil, nil, nil;
        else
            look.background, look.border, look.shadow = clear, clear, false;
        end
        look.growFrom = growCorners[options.growFrom];
        app:Window(options.isVisible, DrawStatuses, windowExtra);
    end
end);
