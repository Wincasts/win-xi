addon.name    = 'damage';
addon.author  = 'win';
addon.version = '0.1';
addon.desc    = 'Draws the damage numbers the game pops up over whoever was hit in winxi\'s style, through the namehook plugin.';

local winxiNeeded = 54;
do
    local ok, found = pcall(require, 'winxi.version');
    local number = ok and type(found) == 'table' and found.Number or 0;
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number);
        print('[damage] ' .. text);
        error(text, 0);
    end
end

require('common');
local bit = require('bit');
local imgui = require('imgui');
local fonts = require('winxi.fonts');
local outlined = require('winxi.text');
local popups = require('winxi.popups');
local theme = require('winxi.theme');

local SIZE = 26;      -- a number's height on the screen, in pixels, at the game's full size for it
local FONT_SLOT = 0;

local enabled = true;
local problemSaid = nil;

local function say(words)
    print(('\30\81[\30\06damage\30\81]\30\01 %s'):format(words));
end

-- The game's colour is 0xAARRGGBB with 0x80 for full: its alpha doubled, its colour as it is
local function gameColor(color)
    local alpha = math.min(0xFF, bit.rshift(color, 24) * 2);
    return alpha * 0x1000000 + color % 0x1000000;
end

-- {r, g, b, a} from 0 to 1, as the theme keeps a colour, as 0xAARRGGBB
local function packed(color)
    local function byte(value) return math.floor(math.max(0, math.min(1, value or 1)) * 255 + 0.5); end
    return byte(color[4]) * 0x1000000 + byte(color[1]) * 0x10000 + byte(color[2]) * 0x100 + byte(color[3]);
end

-- One hit's number, in the theme's font, centred on the game's point. size is its height on the
-- screen; scale the game's picture's pixels to one of the screen's.
local function drawNumber(popup, words, size, scale, font, edge, edgeColor)
    imgui.PushFont(font, size);
    local baked = imgui.GetFontBaked();
    if (baked == nil) then
        imgui.PopFont();
        return;
    end

    local width = 0;
    for at = 1, #words do
        local glyph = baked:FindGlyph(words:byte(at));
        if (glyph ~= nil) then
            width = width + glyph.AdvanceX;
        end
    end

    if (popups.BeginPopup(popup, 1, edge * scale, edgeColor, false)) then
        local color = gameColor(popup.Color);
        local pen, top = -width / 2, -size / 2;
        for at = 1, #words do
            local glyph = baked:FindGlyph(words:byte(at));
            if (glyph ~= nil) then
                if (glyph.Visible ~= 0 and glyph.Visible ~= false) then
                    popups.Quad((pen + glyph.X0) * scale, (top + glyph.Y0) * scale, (pen + glyph.X1) * scale, (top + glyph.Y1) * scale,
                        glyph.U0, glyph.V0, glyph.U1, glyph.V1, color, FONT_SLOT, true);
                end
                pen = pen + glyph.AdvanceX;
            end
        end
        popups.EndPopup();
    end
    imgui.PopFont();
end

local function frame()
    local hook = popups.Hook();
    if (hook == nil or hook.Hooked == 0) then
        local problem = popups.Problem();
        if (problem ~= problemSaid) then
            problemSaid = problem;
            if (problem ~= nil) then say(problem); end
        end
        return;
    end
    problemSaid = nil;

    local texture = fonts.Texture();
    local scale = texture ~= nil and popups.BeginDrawing(hook) or nil;
    if (scale == nil) then
        return; -- the game draws them this frame
    end
    popups.Claim(hook);
    popups.SetTexture(FONT_SLOT, texture);

    local font = fonts.Get(theme.For('FontFile'));
    local edge = outlined.Edge();
    local edgeColor = packed(outlined.EdgeColor());
    for popup in popups.Hits(hook) do
        local size = math.max(1, math.floor(SIZE * popup.Scale + 0.5));
        drawNumber(popup, popups.Text(popup), size, scale, font, edge, edgeColor);
    end
end

ashita.events.register('d3d_present', 'damage_present', function ()
    if (enabled) then
        frame();
    end
end);

ashita.events.register('unload', 'damage_unload', function ()
    popups.Release();
end);

ashita.events.register('command', 'damage_command', function (e)
    local args = e.command:args();
    if (#args == 0 or args[1]:lower() ~= '/damage') then
        return;
    end
    e.blocked = true;

    local word = args[2] and args[2]:lower() or '';
    if (word == 'on' or word == 'off') then
        enabled = word == 'on';
        if (not enabled) then
            popups.Release();
        end
        say(enabled and 'Damage numbers are drawn in winxi\'s style.' or 'The game draws its own damage numbers.');
    else
        say('/damage on | off: draw the damage numbers in winxi\'s style, or leave them to the game. They are ' .. (enabled and 'on.' or 'off.'));
    end
end);
