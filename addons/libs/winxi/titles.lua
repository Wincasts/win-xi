-- winxi.titles: a window's title, on its top edge.
--
--   titles.Breaks(words)   before Begin: whether the window's border is to be broken by its title,
--                          for winxi.borders.Push
--   titles.Gap(words)      inside the window: where the border is to be broken, left and right, or
--                          nothing, for winxi.borders.Draw
--   titles.Draw(words)     inside the window, after its content and border: words sit across the top
--                          edge, half over the window and half above it, at its right
--
-- Gap and Draw take a rect ({ left, top, width, height }, as winxi.frame's) for a frame drawn inside a window
-- that is not its own (Gap(words, rect), Draw(words, { rect = rect })): the title goes on that frame's edge.
--
-- It follows the theme: Frame Titles switches every title on or off, Title Style is how it is drawn,
-- Title Color its colour, Title Font and Title Size its font and size in pixels (the window's own where
-- unset), Title Position X how far in from the window's right edge the words end, Title Position Y how
-- far down from the edge they are moved (up, below 0), and Title Shadow a soft dark copy of the words
-- down and to the right of them, at Title Shadow Offset and Title Shadow Opacity. Title All Caps writes
-- every title in capitals. The styles:
--   outline   the words alone, over the border, with winxi.text's dark edge
--   break     the same, with the border broken behind the words, as a legend breaks a frame's line
--   breakshadow   the break, with a soft dark haze behind the words and a slight drop under them
--   plate     the words on a small plate of the background, edged in the border's colour
-- The words fade with the window. A settings window has imgui's own
-- title, and none of these.
local imgui = require('imgui');
local theme = require('winxi.theme');
local text = require('winxi.text');
local fonts = require('winxi.fonts');
local clip = require('winxi.clip');

local titles = {};

local margin = 4; -- either side of the words, in the break and the plate

local function Shown(words)
    return theme.Get().FrameTitles and type(words) == 'string' and words ~= '';
end

-- The words as they are written: in capitals, with Title All Caps, made once for each title
local capitals = {};

local function Written(words)
    if not theme.Get().TitleAllCaps then
        return words;
    end
    local upper = capitals[words];
    if upper == nil then
        upper = words:upper();
        capitals[words] = upper;
    end
    return upper;
end

-- The title's font and size, where either is set; returns whether anything was pushed
local function PushSize()
    local current = theme.Get();
    local font = fonts.Get(current.TitleFontFile);
    local size = tonumber(current.TitleSize) or 0;
    if font == nil and size <= 0 then
        return false;
    end
    imgui.PushFont(font, size);
    return true;
end

-- Where the words go in the window being drawn, or on rect where one is given: left, top, width, height; or nothing
local function Place(words, rect)
    local x, y, width;
    if rect then
        x, y, width = rect.left, rect.top, rect.width;
    else
        x, y = imgui.GetWindowPos();
        width = imgui.GetWindowSize();
    end
    if x == nil or width == nil or width <= 0 then
        return nil;
    end
    local w, h = imgui.CalcTextSize(words);
    w, h = w or 0, h or 0;
    local current = theme.Get();
    local left = math.floor(x + width - (tonumber(current.TitleOffsetX) or 0) - w + 0.5);
    return left, math.floor(y - h / 2 + (tonumber(current.TitleOffsetY) or 0) + 0.5), w, h;
end

function titles.Breaks(words)
    local titleStyle = theme.Get().TitleStyle;
    return Shown(words) and (titleStyle == 'break' or titleStyle == 'breakshadow') or false;
end

function titles.Gap(words, rect)
    if not titles.Breaks(words) then
        return nil;
    end
    local pushed = PushSize();
    local left, _, w = Place(Written(words), rect);
    if pushed then
        imgui.PopFont();
    end
    if left == nil then
        return nil;
    end
    -- on whole pixels, as every clip rect is (see winxi.borders)
    return math.floor(left - margin), math.ceil(left + w + margin);
end

local clipMin, clipMax = { 0, 0 }, { 0, 0 };
local plateMin, plateMax = { 0, 0 }, { 0, 0 };
local fill = { 0, 0, 0, 0 };
local shade = { 0, 0, 0, 0 };
local haze = 3; -- layers of the haze behind a Break With Shadow title, each a pixel or two wider
local spot = { 0, 0 };

function titles.Draw(words, options)
    if not Shown(words) then
        return;
    end
    words = Written(words);
    local pushed = PushSize();
    local left, top, w, h = Place(words, options and options.rect);
    if left == nil then
        if pushed then imgui.PopFont(); end
        return;
    end
    local current = theme.Get();

    -- the window's own list, so that the title sits with the window among the others, opened up to
    -- take in what is above the window
    local list = imgui.GetWindowDrawList();
    local drop = current.TitleShadow and (tonumber(current.TitleShadowOffset) or 0) or 0;
    local hazed = current.TitleStyle == 'breakshadow';
    local reach = hazed and 2 * haze or 0;
    -- on whole pixels: see winxi.borders
    clipMin[1], clipMin[2] = math.floor(left - margin - 2 - reach), math.floor(top - 2 - reach);
    clipMax[1], clipMax[2] = math.ceil(left + w + margin + 2 + math.max(drop, reach)), math.ceil(top + h + 2 + math.max(drop, reach));
    -- kept on the screen (winxi.clip): a title pushed off it is not stretched over all of it
    if not clip.Push(list, clipMin, clipMax) then
        if pushed then imgui.PopFont(); end
        return;
    end

    if current.TitleStyle == 'plate' then
        -- the background, near solid, so that the border does not show through it
        local background = options and options.background or current.BackgroundColor;
        fill[1], fill[2], fill[3] = background[1], background[2], background[3];
        fill[4] = math.max(background[4], 0.95);
        plateMin[1], plateMin[2] = left - margin, top;
        plateMax[1], plateMax[2] = left + w + margin, top + h;
        list:AddRectFilled(plateMin, plateMax, imgui.GetColorU32(fill), 3);
        list:AddRect(plateMin, plateMax, imgui.GetColorU32(options and options.border or theme.GameBorderColor()), 3);
    end
    if hazed then
        -- a soft dark haze, rounded, fading outward, over the gap in the border
        shade[4] = 0.16;
        local color = imgui.GetColorU32(shade);
        for layer = 0, haze - 1 do
            plateMin[1], plateMin[2] = left - margin - 2 * layer, top + 1 - layer;
            plateMax[1], plateMax[2] = left + w + margin + 2 * layer, top + h - 1 + layer;
            list:AddRectFilled(plateMin, plateMax, color, h / 2 + layer);
        end
        -- and the words dropped a pixel, where Title Shadow has not given them a shadow of its own
        if drop == 0 then
            shade[4] = 0.6;
            spot[1], spot[2] = left + 1, top + 1;
            list:AddText(spot, imgui.GetColorU32(shade), words);
        end
    end
    if drop > 0 then
        -- soft: the words in the dark at the offset, half as strong, and again a pixel short of it
        local opacity = (tonumber(current.TitleShadowOpacity) or 0) / 100;
        for step = drop, math.max(1, drop - 1), -1 do
            shade[4] = opacity * ((step == drop and drop > 1) and 0.5 or 1);
            spot[1], spot[2] = left + step, top + step;
            list:AddText(spot, imgui.GetColorU32(shade), words);
        end
    end
    text.Draw(list, left, top, options and options.titleColor or current.TitleColor, words);

    list:PopClipRect();
    if pushed then
        imgui.PopFont();
    end
end

return titles;
