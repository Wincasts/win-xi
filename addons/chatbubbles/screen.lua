-- The bubbles drawn on the screen by imgui, over everything, as chatbubbles drew them up to 0.3:
-- Draw On Screen, for whoever would sooner see a bubble through a wall than lose it behind one.
--
--   screen.Draw(name, message, now, x, y, display, appearance)
--       the bubble for a message over the name at x, y on the screen (nameplates.Screen), on imgui's
--       background draw list; false if it would not fit on the screen
--
-- The layout is the world renderer's: text wrapped at 280 pixels, 10 pixels of padding, a pointer
-- down to the name, fading over the last 0.6 seconds. It is the screen's size whatever the distance.
local imgui = require('imgui');
local bubbles = require('bubbles');
local colors = require('colors');
local text = require('winxi.text');

local M = {};

local WRAP   = 280; -- pixels the text wraps at, at most
local MARGIN = 4;   -- pixels kept between a bubble and the screen's edge
local RISE   = 30;  -- pixels from the name's point to the bubble's foot
local FADE   = 0.6; -- seconds a bubble takes to go

-- imgui's packed colour for a table of four, faded
local function packed(rgba, fade)
    return imgui.GetColorU32({ rgba[1], rgba[2], rgba[3], rgba[4] * fade });
end

-- and for a colour as the world renderer has it, 0xAARRGGBB, faded
local function repacked(argb, fade)
    local a = math.floor(argb / 0x1000000) % 256;
    local r, g, b = math.floor(argb / 0x10000) % 256, math.floor(argb / 0x100) % 256, argb % 256;
    return imgui.GetColorU32({ r / 255, g / 255, b / 255, a / 255 * fade });
end

local function measure(words)
    return imgui.CalcTextSize(words);
end

function M.Draw(name, message, now, x, y, display, appearance)
    local font, fontSize = imgui.GetFont(), imgui.GetFontSize();
    local lineHeight = imgui.GetTextLineHeight();
    local maxWidth = math.min(WRAP, display.x - 2 * MARGIN - 20);
    -- the lines are kept with the message, wrapped again as the font or the room changes
    if (message.screenFont ~= font or message.screenSize ~= fontSize or message.screenWidth ~= maxWidth) then
        message.screenLines = bubbles.Wrap(message.text, maxWidth, measure);
        message.screenWide = 0;
        for _, line in ipairs(message.screenLines) do
            message.screenWide = math.max(message.screenWide, (measure(line)));
        end
        message.screenFont, message.screenSize, message.screenWidth = font, fontSize, maxWidth;
    end
    local lines = message.screenLines;
    local width = message.screenWide + 20;
    local height = #lines * lineHeight + 16;
    local left = math.max(MARGIN, math.min(display.x - width - MARGIN, x - width / 2));
    local bottom = y - RISE;
    local top = bottom - height;
    -- a bubble that would not fit above the name is not drawn clipped over the rest
    if (top < MARGIN) then return false; end

    local fade = math.min(1, math.max(0, (message.expires - now) / FADE));
    local background = packed(appearance.background, fade);
    local gameColor = colors.ForMessage(message, appearance);
    local foreground = gameColor and repacked(gameColor, fade) or packed(appearance.text, fade);
    -- a game colour over a light background keeps its RGB and gets a dark edge, as in the world
    local outline = gameColor ~= nil and (appearance.background[1] * 0.2126
        + appearance.background[2] * 0.7152 + appearance.background[3] * 0.0722) > 0.6;

    local draw = imgui.GetBackgroundDrawList();
    draw:AddRectFilled({ left, top }, { left + width, bottom }, background, 6);
    local tip = math.max(left + 9, math.min(left + width - 9, x));
    draw:AddTriangleFilled({ tip - 6, bottom - 1 }, { tip + 6, bottom - 1 }, { x, bottom + 10 }, background);
    local dark = outline and imgui.GetColorU32({ 0, 0, 0, 0.8 * fade }) or nil;
    for i, line in ipairs(lines) do
        text.Packed(draw, left + 10, top + 8 + (i - 1) * lineHeight, foreground, line, outline and 1 or 0, dark);
    end
    return true;
end

return M;
