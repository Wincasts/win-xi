-- winxi: one of the Winxi Theme's border styles, round each macro element.
--
-- winxi.borders draws a window's border art with imgui, as nine slices of a 64 by 64 image: its
-- corners 3 pixels on screen whatever the size, its edges stretched between them. The crossbar is
-- drawn with a D3DX sprite, so the same nine slices are drawn here with sprite draws, each its own
-- part of the image scaled to its place. The image is winxi.borders' own, loaded once there.
--
-- Frame Border (Components tab) is 'none', 'theme' (whichever art the theme's Window Border is; none
-- while that is the plain border) or one of theme.BorderStyles' art by its key. Faded by the theme's
-- Border Opacity. Without winxi, nothing is drawn.
local d3d8 = require('d3d8');
local ffi = require('ffi');

local okTheme, theme = pcall(require, 'winxi.theme');
local okBorders, borders = pcall(require, 'winxi.borders');
if not (okTheme and okBorders) then theme, borders = nil, nil; end

local frameborder = {};

local EDGE = 3;                -- each corner's size on screen, as winxi.borders
local cuts = { 0, 8, 56, 64 }; -- the nine slices' edges in the image, as winxi.borders' uv
local rects = {};              -- the nine source rects, row by row; nil in the middle
for row = 1, 3 do
    for col = 1, 3 do
        if row ~= 2 or col ~= 2 then
            rects[(row - 1) * 3 + col] = ffi.new('RECT', { cuts[col], cuts[row], cuts[col + 1], cuts[row + 1] });
        end
    end
end
local textures = {};           -- handle -> the texture it is
local scale = ffi.new('D3DXVECTOR2', { 1.0, 1.0 });
local vec_position = ffi.new('D3DXVECTOR2', { 0, 0 });
local xx, yy = { 0, 0, 0, 0 }, { 0, 0, 0, 0 };

-- The choices, as { key, label }: none, the theme's own, then each art of theme.BorderStyles
function frameborder.Choices()
    local choices = { { key = 'none', label = 'None' }, { key = 'theme', label = 'Window Border' } };
    if theme then
        for index = 2, #theme.BorderStyles do
            choices[#choices + 1] = theme.BorderStyles[index];
        end
    end
    return choices;
end

function frameborder.Label(key)
    for _, choice in ipairs(frameborder.Choices()) do
        if choice.key == key then return choice.label; end
    end
    return 'None';
end

-- The texture of a choice, or nil for none
local function Texture(style)
    if borders == nil or style == nil or style == 'none' then return nil; end
    if style == 'theme' then style = theme.Get().BorderStyle; end
    local handle = borders.Texture(style);
    if handle == nil then return nil; end
    local texture = textures[handle];
    if texture == nil then
        texture = ffi.cast('IDirect3DTexture8*', handle);
        textures[handle] = texture;
    end
    return texture;
end

-- Draws the chosen border round a rect width by height at x, y
function frameborder.Draw(sprite, style, x, y, width, height)
    local texture = Texture(style);
    if texture == nil or width <= 0 or height <= 0 then return; end
    local opacity = (tonumber(theme.Get().BorderOpacity) or 100) / 100;
    local alpha = math.floor(math.max(0, math.min(1, opacity)) * 255 + 0.5);
    if alpha <= 0 then return; end
    local tint = d3d8.D3DCOLOR_ARGB(alpha, 255, 255, 255);
    local edge = math.min(EDGE, width / 2, height / 2);
    xx[1], xx[2], xx[3], xx[4] = x, x + edge, x + width - edge, x + width;
    yy[1], yy[2], yy[3], yy[4] = y, y + edge, y + height - edge, y + height;
    for row = 1, 3 do
        for col = 1, 3 do
            local rect = rects[(row - 1) * 3 + col];
            local w, h = xx[col + 1] - xx[col], yy[row + 1] - yy[row];
            if rect and w > 0 and h > 0 then
                scale.x = w / (cuts[col + 1] - cuts[col]);
                scale.y = h / (cuts[row + 1] - cuts[row]);
                vec_position.x, vec_position.y = xx[col], yy[row];
                sprite:Draw(texture, rect, scale, nil, 0.0, vec_position, tint);
            end
        end
    end
end

return frameborder;
