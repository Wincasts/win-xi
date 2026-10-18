-- winxi.text: text with a dark edge all round it, the way winxi writes anything that goes over a bar,
-- an image or the game itself, where plain text is hard to read.
--
--   text.Draw(drawList, x, y, color, words, edge)   at a place on screen, in the font in use
--   text.Packed(drawList, x, y, color, words, edge, dark)   the same with colours as numbers
--   text.Outlined(words, color)                     in a window, where imgui.Text would put it
--   text.Edge()                                     how thick the edge is, as the theme has it
--   text.EdgeColor()                                its colour, as the theme has it
--
-- color is a table of four, as imgui takes them; left out of text.Outlined it is the theme's text
-- colour. edge is how thick the dark edge is, in pixels: the theme's Text Outline if not given, which
-- is what every addon should leave it at, so that one setting changes them all; 0 is no edge. The
-- edge is the theme's Outline Color (text.EdgeColor), and like the text it fades with the window.
--
-- text.Draw is for an addon that places things itself, on a draw list of its choosing. text.Packed
-- is for one that writes many things a frame: it takes the colour, and the edge's colour, as
-- imgui.GetColorU32 gives them, to be worked out once for them all (text.EdgeColor() for the edge's).
-- text.Outlined takes up the room the words need and moves on, as imgui.Text does.
local imgui = require('imgui');
local theme = require('winxi.theme');

local text = {};

-- The edge's colour as last asked for (text.EdgeColor): the same table each time, recoloured from the
-- theme, for an addon that keeps hold of it
text.OutlineColor = { 0, 0, 0, 0.9 };

local pos = { 0, 0 };
local room = { 0, 0 };

function text.Edge()
    return tonumber(theme.Get().TextOutline) or 1;
end

function text.EdgeColor()
    local from = theme.Get().TextOutlineColor;
    local to = text.OutlineColor;
    if type(from) == 'table' then
        to[1], to[2], to[3], to[4] = from[1], from[2], from[3], from[4];
    end
    return to;
end

function text.Packed(drawList, x, y, color, words, edge, dark)
    edge = edge or text.Edge();

    -- the edge is the words again in the dark, behind themselves, towards each corner
    if edge > 0 then
        dark = dark or imgui.GetColorU32(text.EdgeColor());
        for dx = -edge, edge, 2 * edge do
            for dy = -edge, edge, 2 * edge do
                pos[1], pos[2] = x + dx, y + dy;
                drawList:AddText(pos, dark, words);
            end
        end
    end

    pos[1], pos[2] = x, y;
    drawList:AddText(pos, color, words);
end

function text.Draw(drawList, x, y, color, words, edge)
    text.Packed(drawList, x, y, imgui.GetColorU32(color), words, edge, nil);
end

function text.Outlined(words, color)
    local x, y = imgui.GetCursorScreenPos();
    room[1], room[2] = imgui.CalcTextSize(words);
    imgui.Dummy(room);
    text.Draw(imgui.GetWindowDrawList(), x, y, color or theme.Get().TextColor, words);
end

return text;
