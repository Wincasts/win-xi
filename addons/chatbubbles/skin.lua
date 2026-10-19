-- The bubble's look: its skin, its border and the click-through arrow, drawn on an imgui draw list
-- (Draw On Screen) or set out as the plugin's quads (in the world).
--
-- The parchment skin is winxi's FFXI-inspired window look, lighter: a gradient from one colour at the
-- top to another at the bottom, with the theme's fine dark lines over it
-- (libs\winxi\assets\backgrounds\lines.png, a dark row and a clear row). The plain skin is a rounded
-- rectangle in the Background colour. The border is any of the theme's border art
-- (libs\winxi\assets\borders, nine slices with corners of 3 pixels, tinted the Border Colour), a plain
-- line of a pixel in that colour, or none.
--
--   skin.Keys, skin.Labels           the skins: 'plain' and 'parchment'
--   skin.Borders                     the borders, { key, label } each: none, plain, and the theme's art
--   skin.Top, skin.Bottom, skin.Text the parchment's colours to begin with
--   skin.Textures(appearance)        the border's and the lines' textures for this look, as addresses
--                                   the plugin and imgui can draw from, or nil for one not wanted or not
--                                   loaded (tried for again each second)
--   skin.Light(appearance, skinned)  whether what is behind the text is light, for the text's dark edge
--   skin.Screen(list, left, top, width, height, fade, appearance, border, lines)
--                                   the skin and the border on an imgui draw list, faded
--   skin.World(quad, u, v, left, top, width, height, appearance, border, lines)
--                                   the same as the plugin's quads, through quad(x0, y0, x1, y1, u0, v0,
--                                   u1, v1, color, slot); u, v the font's white pixel; border and lines
--                                   the texture slots the two are in, or nil where one is not drawn. The
--                                   fade is the name's (BeginName), not the quads'
--   skin.Quads(width, height, appearance, border, lines)   how many quads World sets out, for the budget
--   skin.ArrowShown(now)             whether the click-through arrow is in its lit half of its flash
--   skin.ArrowSize                   its side, in pixels
--   skin.ArrowScreen(list, right, bottom, color, dark)     the arrow on a draw list, its point at right, bottom
--   skin.ArrowWorld(quad, u, v, right, bottom, color)      the arrow as quads; skin.ArrowQuads of them
--   skin.LoadBorder(style), skin.LoadLines()   load the textures: fields for the checks to stand in for
local imgui = require('imgui');

local skin = {};

skin.Keys = { 'plain', 'parchment' };
skin.Labels = { plain = 'Plain', parchment = 'Parchment' };
skin.Borders = {
    { key = 'none', label = 'None' }, { key = 'plain', label = 'Plain Line' },
    { key = 'silver', label = 'Brushed Silver' }, { key = 'bronze', label = 'Bronze' },
    { key = 'ffxi', label = 'FFXI-inspired' }, { key = 'crystal', label = 'Crystal' },
    { key = 'royal', label = 'Royal Gold' }, { key = 'obsidian', label = 'Obsidian' },
    { key = 'royal_silver', label = 'Royal Silver' }, { key = 'royal_platinum', label = 'Royal Platinum' },
    { key = 'mythril', label = 'Mythril' }, { key = 'adaman', label = 'Adaman' },
    { key = 'jade', label = 'Jade' }, { key = 'amethyst', label = 'Amethyst' },
};
skin.BorderLabels = {};
for _, entry in ipairs(skin.Borders) do skin.BorderLabels[entry.key] = entry.label; end
skin.Top = { 0.93, 0.87, 0.72, 0.96 };
skin.Bottom = { 0.74, 0.62, 0.44, 0.96 };
skin.Text = { 0.22, 0.16, 0.10, 1 };
skin.ArrowSize = 9;

local TILE   = 128;         -- the lines tile's side
local EDGE   = 3;           -- the border art's corners, in pixels, whatever the bubble's size
local STRIPS = 12;          -- the gradient, as the plugin draws it: strips of one colour each
local UV     = { 0, 8 / 64, 56 / 64, 1 }; -- the art's nine slices in its image, as winxi.borders has them
local RETRY  = 1;           -- seconds between one try for a texture and the next
local FLASH  = 0.4;         -- seconds the arrow is lit, and then dark
local ARROW_ROWS = 6;       -- the arrow as the plugin draws it: rows of one quad each
skin.ArrowQuads = ARROW_ROWS;

function skin.LoadBorder(style)
    local ok, borders = pcall(require, 'winxi.borders');
    return ok and borders.Texture(style) or nil;
end

function skin.LoadLines()
    local ok, backgrounds = pcall(require, 'winxi.backgrounds');
    local handle = ok and backgrounds.Load('lines');
    return handle or nil;
end

local borders = {}; -- style -> its texture, while loaded
local lines = nil;
local triedAt = {};

local function Retry(key)
    local now = os.clock();
    if (now - (triedAt[key] or -math.huge) < RETRY) then return false; end
    triedAt[key] = now;
    return true;
end

-- Whether the border is one of the art, and not none or the plain line
local function Art(style)
    return style ~= nil and style ~= 'none' and style ~= 'plain' and skin.BorderLabels[style] ~= nil;
end

function skin.Textures(appearance)
    local style = appearance.border ~= nil and appearance.border[1] or 'none';
    local border = nil;
    if (Art(style)) then
        border = borders[style];
        if (border == nil and Retry(style)) then
            border = skin.LoadBorder(style);
            borders[style] = border;
        end
    end
    local wantsLines = appearance.skin ~= nil and appearance.skin[1] == 'parchment';
    if (wantsLines and lines == nil and Retry('lines')) then
        lines = skin.LoadLines();
    end
    return border, wantsLines and lines or nil;
end

-- The lines tile over the bubble, side by side at its own size, the last column and row cut to what
-- is left: each(x0, y0, x1, y1, u1, v1) for each
local function Tiles(x, y, width, height, each)
    for top = y, y + height - 1, TILE do
        local h = math.min(TILE, y + height - top);
        for left = x, x + width - 1, TILE do
            local w = math.min(TILE, x + width - left);
            each(left, top, left + w, top + h, w / TILE, h / TILE);
        end
    end
end

local function TileCount(width, height)
    return math.ceil(width / TILE) * math.ceil(height / TILE);
end

-- The border art's nine slices, less the middle: each(x0, y0, x1, y1, u0, v0, u1, v1) for each
local xx, yy = { 0, 0, 0, 0 }, { 0, 0, 0, 0 };
local function Slices(x, y, width, height, each)
    local edge = math.min(EDGE, width / 2, height / 2);
    xx[1], xx[2], xx[3], xx[4] = x, x + edge, x + width - edge, x + width;
    yy[1], yy[2], yy[3], yy[4] = y, y + edge, y + height - edge, y + height;
    for row = 1, 3 do
        for col = 1, 3 do
            if (row ~= 2 or col ~= 2) then
                each(xx[col], yy[row], xx[col + 1], yy[row + 1], UV[col], UV[row], UV[col + 1], UV[row + 1]);
            end
        end
    end
end

-- Whether the colour behind the text is light, so that a game colour wants a dark edge: the plain
-- skin's background, or the parchment's two colours taken together
local function luminance(rgba)
    return rgba[1] * 0.2126 + rgba[2] * 0.7152 + rgba[3] * 0.0722;
end

function skin.Light(appearance, skinned)
    if (skinned) then
        return (luminance(appearance.skinTop) + luminance(appearance.skinBottom)) / 2 > 0.6;
    end
    return luminance(appearance.background) > 0.6;
end

local a, b, uvA, uvB = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
local tint = { 1, 1, 1, 1 };

local function packed(rgba, fade)
    return imgui.GetColorU32({ rgba[1], rgba[2], rgba[3], rgba[4] * fade });
end

function skin.Screen(list, left, top, width, height, fade, appearance, border, linesTexture)
    local style = appearance.border ~= nil and appearance.border[1] or 'none';
    a[1], a[2], b[1], b[2] = left, top, left + width, top + height;
    if (appearance.skin ~= nil and appearance.skin[1] == 'parchment') then
        local topColor, bottomColor = packed(appearance.skinTop, fade), packed(appearance.skinBottom, fade);
        list:AddRectFilledMultiColor(a, b, topColor, topColor, bottomColor, bottomColor);
        if (linesTexture) then
            tint[4] = fade;
            local white = imgui.GetColorU32(tint);
            Tiles(left, top, width, height, function (x0, y0, x1, y1, u1, v1)
                a[1], a[2], b[1], b[2] = x0, y0, x1, y1;
                uvA[1], uvA[2], uvB[1], uvB[2] = 0, 0, u1, v1;
                list:AddImage(linesTexture, a, b, uvA, uvB, white);
            end);
        end
    else
        -- the corners rounded as the art's are where there is art, and as before where there is none
        list:AddRectFilled(a, b, packed(appearance.background, fade), border and 3 or 6);
    end
    if (border) then
        local color = packed(appearance.borderColor, fade);
        Slices(left, top, width, height, function (x0, y0, x1, y1, u0, v0, u1, v1)
            a[1], a[2], b[1], b[2] = x0, y0, x1, y1;
            uvA[1], uvA[2], uvB[1], uvB[2] = u0, v0, u1, v1;
            list:AddImage(border, a, b, uvA, uvB, color);
        end);
    elseif (style == 'plain') then
        a[1], a[2], b[1], b[2] = left, top, left + width, top + height;
        list:AddRect(a, b, packed(appearance.borderColor, fade), 6, 0, 1);
    end
end

-- A colour as the plugin takes it, 0xAARRGGBB, from a table of four
local function argb(rgba)
    local function byte(value) return math.floor(math.max(0, math.min(1, value)) * 255 + 0.5); end
    return byte(rgba[4]) * 0x1000000 + byte(rgba[1]) * 0x10000 + byte(rgba[2]) * 0x100 + byte(rgba[3]);
end

local mixed = { 0, 0, 0, 0 };

function skin.Quads(width, height, appearance, border, linesSlot)
    local style = appearance.border ~= nil and appearance.border[1] or 'none';
    local count = appearance.skin ~= nil and appearance.skin[1] == 'parchment'
        and (STRIPS + (linesSlot and TileCount(width, height) or 0)) or 1;
    if (border) then count = count + 8; elseif (style == 'plain') then count = count + 4; end
    return count;
end

function skin.World(quad, u, v, left, top, width, height, appearance, border, linesSlot)
    local style = appearance.border ~= nil and appearance.border[1] or 'none';
    if (appearance.skin ~= nil and appearance.skin[1] == 'parchment') then
        local above, below = appearance.skinTop, appearance.skinBottom;
        for strip = 0, STRIPS - 1 do
            local share = (strip + 0.5) / STRIPS;
            for channel = 1, 4 do
                mixed[channel] = above[channel] + (below[channel] - above[channel]) * share;
            end
            local y0 = top + height * strip / STRIPS;
            local y1 = top + height * (strip + 1) / STRIPS;
            quad(left, y0, left + width, y1, u, v, u, v, argb(mixed), 0);
        end
        if (linesSlot) then
            Tiles(left, top, width, height, function (x0, y0, x1, y1, u1, v1)
                quad(x0, y0, x1, y1, 0, 0, u1, v1, 0xFFFFFFFF, linesSlot);
            end);
        end
    else
        quad(left, top, left + width, top + height, u, v, u, v, argb(appearance.background), 0);
    end
    if (border) then
        local color = argb(appearance.borderColor);
        Slices(left, top, width, height, function (x0, y0, x1, y1, u0, v0, u1, v1)
            quad(x0, y0, x1, y1, u0, v0, u1, v1, color, border);
        end);
    elseif (style == 'plain') then
        local color = argb(appearance.borderColor);
        quad(left, top, left + width, top + 1, u, v, u, v, color, 0);
        quad(left, top + height - 1, left + width, top + height, u, v, u, v, color, 0);
        quad(left, top + 1, left + 1, top + height - 1, u, v, u, v, color, 0);
        quad(left + width - 1, top + 1, left + width, top + height - 1, u, v, u, v, color, 0);
    end
end

-- The click-through arrow, as the game's dialogue cursor: a small triangle pointing down, lit and
-- dark by turns
function skin.ArrowShown(now)
    return math.floor(now / FLASH) % 2 == 0;
end

local p1, p2, p3 = { 0, 0 }, { 0, 0 }, { 0, 0 };

function skin.ArrowScreen(list, right, bottom, color, dark)
    local size = skin.ArrowSize;
    local left, top = right - size, bottom - size;
    p1[1], p1[2], p2[1], p2[2], p3[1], p3[2] = left, top, right, top, left + size / 2, bottom;
    if (dark) then
        -- the dark edge: the same triangle, a pixel out each way
        for dx = -1, 1, 2 do
            for dy = -1, 1, 2 do
                p1[1], p1[2], p2[1], p2[2], p3[1], p3[2] = left + dx, top + dy, right + dx, top + dy, left + size / 2 + dx, bottom + dy;
                list:AddTriangleFilled(p1, p2, p3, dark);
            end
        end
        p1[1], p1[2], p2[1], p2[2], p3[1], p3[2] = left, top, right, top, left + size / 2, bottom;
    end
    list:AddTriangleFilled(p1, p2, p3, color);
end

function skin.ArrowWorld(quad, u, v, right, bottom, color)
    local size = skin.ArrowSize;
    local top = bottom - size;
    for row = 0, ARROW_ROWS - 1 do
        local half = size / 2 * (1 - row / ARROW_ROWS);
        local middle = right - size / 2;
        quad(middle - half, top + size * row / ARROW_ROWS, middle + half, top + size * (row + 1) / ARROW_ROWS, u, v, u, v, color, 0);
    end
end

return skin;
