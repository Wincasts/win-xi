-- The parchment skin: winxi's FFXI-inspired window look round a bubble, lighter. The background is a
-- gradient from one colour at the top to another at the bottom, with the theme's fine dark lines over
-- it (libs\winxi\assets\backgrounds\lines.png, a dark row and a clear row), and the border is the
-- theme's FFXI-inspired art (libs\winxi\assets\borders\ffxi.png), nine slices with corners of 3 pixels.
--
--   skin.Keys, skin.Labels     the skins there are to choose from: 'plain', today's rounded rectangle,
--                              and 'parchment'
--   skin.Top, skin.Bottom, skin.Text   the parchment's colours to begin with
--   skin.Textures()            the border's and the lines' textures, as addresses the plugin and imgui
--                              can draw from, or nil for either not loaded; tried for again each second
--   skin.Screen(list, left, top, width, height, fade, appearance)
--                              the skin on an imgui draw list, faded
--   skin.World(quad, u, v, left, top, width, height, appearance, border, lines)
--                              the skin as the plugin's quads, through quad(x0, y0, x1, y1, u0, v0, u1,
--                              v1, color, slot); u, v the font's white pixel; border and lines the
--                              texture slots the two are in, or nil where one is not loaded. The fade
--                              is the name's (BeginName), not the quads'
--   skin.Quads(width, height, border, lines)   how many quads World sets out, for the budget
--   skin.Light(appearance, skinned)   whether what is behind the text is light, for the text's dark edge
--   skin.LoadBorder(), skin.LoadLines()   load the two textures, fields for the checks to stand in for
local imgui = require('imgui');

local skin = {};

skin.Keys = { 'plain', 'parchment' };
skin.Labels = { plain = 'Plain', parchment = 'Parchment' };
skin.Top = { 0.93, 0.87, 0.72, 0.96 };
skin.Bottom = { 0.74, 0.62, 0.44, 0.96 };
skin.Text = { 0.22, 0.16, 0.10, 1 };

local TILE   = 128;         -- the lines tile's side
local EDGE   = 3;           -- the border's corners, in pixels, whatever the bubble's size
local STRIPS = 12;          -- the gradient, as the plugin draws it: strips of one colour each
local UV     = { 0, 8 / 64, 56 / 64, 1 }; -- the border's nine slices in its image, as winxi.borders has them
local RETRY  = 1;           -- seconds between one try for a texture and the next

function skin.LoadBorder()
    local ok, borders = pcall(require, 'winxi.borders');
    return ok and borders.Texture('ffxi') or nil;
end

function skin.LoadLines()
    local ok, backgrounds = pcall(require, 'winxi.backgrounds');
    local handle = ok and backgrounds.Load('lines');
    return handle or nil;
end

local border, lines = nil, nil;
local triedAt = -math.huge;

function skin.Textures()
    if (border == nil or lines == nil) then
        local now = os.clock();
        if (now - triedAt >= RETRY) then
            triedAt = now;
            if (border == nil) then border = skin.LoadBorder(); end
            if (lines == nil) then lines = skin.LoadLines(); end
        end
    end
    return border, lines;
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

-- The border's nine slices, less the middle: each(x0, y0, x1, y1, u0, v0, u1, v1) for each
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

function skin.Screen(list, left, top, width, height, fade, appearance)
    local borderTexture, linesTexture = skin.Textures();
    local topColor, bottomColor = packed(appearance.skinTop, fade), packed(appearance.skinBottom, fade);
    a[1], a[2], b[1], b[2] = left, top, left + width, top + height;
    list:AddRectFilledMultiColor(a, b, topColor, topColor, bottomColor, bottomColor);
    tint[4] = fade;
    local white = imgui.GetColorU32(tint);
    if (linesTexture) then
        Tiles(left, top, width, height, function (x0, y0, x1, y1, u1, v1)
            a[1], a[2], b[1], b[2] = x0, y0, x1, y1;
            uvA[1], uvA[2], uvB[1], uvB[2] = 0, 0, u1, v1;
            list:AddImage(linesTexture, a, b, uvA, uvB, white);
        end);
    end
    if (borderTexture) then
        Slices(left, top, width, height, function (x0, y0, x1, y1, u0, v0, u1, v1)
            a[1], a[2], b[1], b[2] = x0, y0, x1, y1;
            uvA[1], uvA[2], uvB[1], uvB[2] = u0, v0, u1, v1;
            list:AddImage(borderTexture, a, b, uvA, uvB, white);
        end);
    end
end

-- A colour as the plugin takes it, 0xAARRGGBB, from a table of four
local function argb(rgba)
    local function byte(value) return math.floor(math.max(0, math.min(1, value)) * 255 + 0.5); end
    return byte(rgba[4]) * 0x1000000 + byte(rgba[1]) * 0x10000 + byte(rgba[2]) * 0x100 + byte(rgba[3]);
end

local mixed = { 0, 0, 0, 0 };

function skin.Quads(width, height, border, lines)
    return STRIPS + (lines and TileCount(width, height) or 0) + (border and 8 or 0);
end

function skin.World(quad, u, v, left, top, width, height, appearance, border, lines)
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
    if (lines) then
        Tiles(left, top, width, height, function (x0, y0, x1, y1, u1, v1)
            quad(x0, y0, x1, y1, 0, 0, u1, v1, 0xFFFFFFFF, lines);
        end);
    end
    if (border) then
        Slices(left, top, width, height, function (x0, y0, x1, y1, u0, v0, u1, v1)
            quad(x0, y0, x1, y1, u0, v0, u1, v1, 0xFFFFFFFF, border);
        end);
    end
end

return skin;
