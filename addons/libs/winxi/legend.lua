-- winxi.legend: a line or two under a window that the controller is working, saying which buttons do
-- what: each button a glyph, drawn as it looks on the kind of controller in use (winxi.controller's
-- Glyph), and a word for what it does, in the theme's font, size and text colour, outlined as winxi's
-- text over the game is (winxi.text). Every winxi window worked with a controller shows one, the same.
--
--     local legend = require('winxi.legend');
--     local pieces = { { controller.Dpad, 'Move' }, { controller.Button.A, 'Select' }, { controller.Button.B, 'Back' } };
--     local height = legend.Draw(pieces, x, y, width)   -- each frame it should show: from x, y, in lines
--                                                       -- no wider than width; returns how tall it is
--     legend.Height(pieces, width)                      -- how tall it will be, for one that goes above
--
-- pieces is a list of { button, what }: button a controller.Button, a list of them (LB/RB, side by
-- side), controller.Dpad or controller.LeftStick; what, a word or two. A piece may carry a tag (tag = 'cycle', say), and
-- legend.Draw(pieces, x, y, width, hidden) leaves out those with the tag hidden. Make the lists once:
-- the lines are laid out again only when the list, the kind of controller, the width, the hidden tag
-- or the font change. It is drawn behind every window, over the game, so it goes clear of the window.
local imgui = require('imgui');
local controller = require('winxi.controller');
local text = require('winxi.text');
local fonts = require('winxi.fonts');
local theme = require('winxi.theme');

local legend = {};

legend.GlyphScale = 0.8; -- a glyph's height, against the text's
local gap = 10;           -- between pieces on a line, in pixels
local glyphGap = 2;       -- between two glyphs of one piece
local whatGap = 3;        -- between the glyphs and what they do
local rowGap = 2;         -- between lines

local laid = { pieces = nil, layout = nil, width = nil, hidden = nil, lineHeight = nil, height = 0, placed = {} };

local function Buttons(button)
    if type(button) == 'table' then
        return button;
    end
    return { button };
end

-- Each piece's place in its line: its glyphs, then what it does a little after them
local function Lay(pieces, width, hidden, lineHeight, glyphSize)
    local placed = {};
    local x, y = 0, 0;
    for _, piece in ipairs(pieces) do
        if hidden == nil or piece.tag ~= hidden then
            local glyphs = {};
            local across = 0;
            for index, button in ipairs(Buttons(piece[1])) do
                if index > 1 then
                    across = across + glyphGap;
                end
                glyphs[index] = { button = button, x = across };
                across = across + controller.GlyphWidth(button, glyphSize);
            end
            local whole = across + whatGap + imgui.CalcTextSize(piece[2]);
            if x > 0 and x + gap + whole > width then
                x, y = 0, y + lineHeight + rowGap;
            elseif x > 0 then
                x = x + gap;
            end
            placed[#placed + 1] = { x = x, y = y, glyphs = glyphs, what = piece[2], whatX = x + across + whatGap };
            x = x + whole;
        end
    end
    laid.placed = placed;
    laid.height = #placed > 0 and y + lineHeight or 0;
end

-- Lays the pieces out, if anything has changed, in the font pushed; returns the line's height and the
-- glyphs' size
local function Laid(pieces, width, hidden)
    local _, lineHeight = imgui.CalcTextSize('A');
    lineHeight = lineHeight or 14;
    local glyphSize = math.max(8, math.floor(lineHeight * legend.GlyphScale + 0.5));
    local layout = controller.GetLayout();
    if laid.pieces ~= pieces or laid.layout ~= layout or laid.width ~= width or laid.hidden ~= hidden
        or laid.lineHeight ~= lineHeight then
        laid.pieces, laid.layout, laid.width, laid.hidden, laid.lineHeight = pieces, layout, width, hidden, lineHeight;
        Lay(pieces, width, hidden, lineHeight, glyphSize);
    end
    return lineHeight, glyphSize;
end

function legend.Height(pieces, width, hidden)
    local pushed = fonts.Push(false);
    Laid(pieces, width, hidden);
    fonts.Pop(pushed);
    return laid.height;
end

function legend.Draw(pieces, x, y, width, hidden)
    local pushed = fonts.Push(false);
    local lineHeight, glyphSize = Laid(pieces, width, hidden);

    local drawList = imgui.GetBackgroundDrawList();
    local color = theme.Get().TextColor;
    local down = math.floor((lineHeight - glyphSize) / 2 + 0.5); -- a glyph centred on its line
    for _, piece in ipairs(laid.placed) do
        for _, glyph in ipairs(piece.glyphs) do
            controller.Glyph(drawList, glyph.button, x + piece.x + glyph.x, y + piece.y + down, glyphSize);
        end
        text.Draw(drawList, x + piece.whatX, y + piece.y, color, piece.what);
    end
    fonts.Pop(pushed);
    return laid.height;
end

return legend;
