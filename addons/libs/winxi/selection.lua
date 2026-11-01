-- winxi.selection: the box round the thing a controller's highlight is on (an item, a slot, a button),
-- in the theme's Selection Style and Selection Color, the same in every addon.
--
--     selection.Draw(drawList, x1, y1, x2, y2)   round the rectangle x1, y1 to x2, y2 (the thing itself)
--
-- It reaches at most selection.Room pixels outside the rectangle, for an addon that clips round it.
-- Drawn inside a window, it fades with the window. The styles (theme.SelectionStyles):
--
--   outline   two thin lines just outside, as winxi always drew it
--   glow      a soft light fading outward, and a faint wash over the thing
--   bevel     a raised frame, lit along the top and left and shaded along the bottom and right, over a
--             light wash brighter at the top
--   glass     a light rim over a gloss, bright across the top half and clear below, with a fine shine
--   satin, brushed   the tab texture of that name (libs\winxi\assets\tabs) in the colour, under a rim
local imgui = require('imgui');
local theme = require('winxi.theme');

local selection = {};

selection.Room = 3;

local a, b = { 0, 0 }, { 0, 0 };
local uv0, uv1 = { 0, 0 }, { 1, 1 };
local tint = { 0, 0, 0, 0 };

-- The colour mixed toward white (light > 0) or black (light < 0), at an opacity, packed
local function Shade(color, light, alpha)
    local r, g, b2 = color[1], color[2], color[3];
    if light > 0 then
        r, g, b2 = r + (1 - r) * light, g + (1 - g) * light, b2 + (1 - b2) * light;
    elseif light < 0 then
        r, g, b2 = r * (1 + light), g * (1 + light), b2 * (1 + light);
    end
    tint[1], tint[2], tint[3], tint[4] = r, g, b2, (color[4] or 1) * alpha;
    return imgui.GetColorU32(tint);
end

local function Rect(list, x1, y1, x2, y2, color, thickness)
    a[1], a[2], b[1], b[2] = x1, y1, x2, y2;
    list:AddRect(a, b, color, 0.0, 0, thickness or 1);
end

local function Fill(list, x1, y1, x2, y2, color)
    a[1], a[2], b[1], b[2] = x1, y1, x2, y2;
    list:AddRectFilled(a, b, color);
end

-- top to bottom, from one colour to another
local function Gradient(list, x1, y1, x2, y2, top, bottom)
    a[1], a[2], b[1], b[2] = x1, y1, x2, y2;
    list:AddRectFilledMultiColor(a, b, top, top, bottom, bottom);
end

local styles = {};

function styles.outline(list, x1, y1, x2, y2, color)
    local line = Shade(color, 0, 1);
    Rect(list, x1 - 2, y1 - 2, x2 + 2, y2 + 2, line);
    Rect(list, x1 - 3, y1 - 3, x2 + 3, y2 + 3, line);
end

function styles.glow(list, x1, y1, x2, y2, color)
    Fill(list, x1, y1, x2, y2, Shade(color, 0.3, 0.12));
    Rect(list, x1 - 1, y1 - 1, x2 + 1, y2 + 1, Shade(color, 0.4, 0.95));
    Rect(list, x1 - 2, y1 - 2, x2 + 2, y2 + 2, Shade(color, 0.2, 0.5));
    Rect(list, x1 - 3, y1 - 3, x2 + 3, y2 + 3, Shade(color, 0, 0.2));
end

function styles.bevel(list, x1, y1, x2, y2, color)
    Gradient(list, x1, y1, x2, y2, Shade(color, 0.5, 0.24), Shade(color, 0, 0.04));
    -- the frame, two pixels, from 3 outside to 1 outside: lit top and left, shaded bottom and right
    local lit, shaded = Shade(color, 0.55, 1), Shade(color, -0.45, 1);
    local l, t, r, bt = x1 - 3, y1 - 3, x2 + 3, y2 + 3;
    Fill(list, l, t, r, t + 2, lit);             -- top
    Fill(list, l, t, l + 2, bt, lit);            -- left
    Fill(list, l + 1, bt - 2, r, bt, shaded);    -- bottom
    Fill(list, r - 2, t + 1, r, bt, shaded);     -- right
    -- a fine dark line inside the frame, so it stands off what it holds
    Rect(list, x1 - 1, y1 - 1, x2 + 1, y2 + 1, Shade(color, -0.7, 0.6));
end

function styles.glass(list, x1, y1, x2, y2, color)
    local middle = y1 + (y2 - y1) * 0.5;
    Gradient(list, x1, y1, x2, middle, Shade(color, 0.85, 0.38), Shade(color, 0.6, 0.08));
    Gradient(list, x1, middle, x2, y2, Shade(color, 0, 0.0), Shade(color, 0, 0.14));
    Rect(list, x1 - 2, y1 - 2, x2 + 2, y2 + 2, Shade(color, 0.35, 1), 1.5);
    Rect(list, x1 - 3, y1 - 3, x2 + 3, y2 + 3, Shade(color, -0.5, 0.5));
    Fill(list, x1, y1, x2, y1 + 1, Shade(color, 0.9, 0.7)); -- the shine along the top
end

-- The tab textures, loaded once through winxi.tabs
local images = {};
local function Image(name)
    local image = images[name];
    if image == nil then
        local ok, tabs = pcall(require, 'winxi.tabs');
        image = ok and tabs.Image and tabs.Image(name) or false;
        images[name] = image;
    end
    return image or nil;
end

local function Textured(name)
    return function(list, x1, y1, x2, y2, color)
        Gradient(list, x1, y1, x2, y2, Shade(color, 0.4, 0.3), Shade(color, 0, 0.12));
        local image = Image(name);
        if image ~= nil then
            a[1], a[2], b[1], b[2] = x1, y1, x2, y2;
            list:AddImage(image, a, b, uv0, uv1, Shade(color, 0.6, 0.9));
        end
        Rect(list, x1 - 2, y1 - 2, x2 + 2, y2 + 2, Shade(color, 0.3, 1), 2);
        Rect(list, x1 - 3, y1 - 3, x2 + 3, y2 + 3, Shade(color, -0.5, 0.45));
    end
end
styles.satin = Textured('satin');
styles.brushed = Textured('brushed');

function selection.Draw(list, x1, y1, x2, y2)
    local current = theme.Get();
    local draw = styles[current.SelectionStyle] or styles.bevel;
    draw(list, x1, y1, x2, y2, current.SelectionColor or theme.Defaults.SelectionColor);
end

return selection;
