-- The controller's legend: a line or two under the inventory window saying which buttons do what in
-- the window that has the controller: each button as a glyph, drawn as it looks on the kind of
-- controller in use (winxi.controller's Glyph), and what it does in winxi's outlined text (it is over
-- the game).
--
--   legend.Draw(pieces, x, y, width, withCycle)   draws the pieces from x, y, in lines no wider than
--                                                 width; returns how tall it is
--
-- pieces is a list of { button, what }: button a controller.Button, a list of them (LB/RB, side by
-- side), or controller.Dpad; what, what it does. A piece marked cycle = true is the Y of the cycle
-- through the windows, left out when withCycle is false. The lines are laid out again only when the pieces,
-- the kind of controller, the width or the font change.
local imgui = require('imgui')
local controller = require('winxi.controller')
local text = require('winxi.text')

local legend = {}

local gap = 14      -- between pieces on a line, in pixels
local glyphGap = 2  -- between two glyphs of one piece
local whatGap = 4   -- between the glyphs and what they do
local rowGap = 3    -- between lines
local whatColor = { 1.0, 1.0, 1.0, 1.0 }

local laid = { pieces = nil, layout = nil, width = nil, withCycle = nil, lineHeight = nil, height = 0, placed = {} }

-- The buttons of a piece, always as a list
local function Buttons(button)
    if type(button) == 'table' then
        return button
    end
    return { button }
end

-- Each piece's place in its line: its glyphs, then what it does a little after them
local function Lay(pieces, width, withCycle, lineHeight)
    local placed = {}
    local x, y = 0, 0
    for _, piece in ipairs(pieces) do
        if withCycle or not piece.cycle then
            local buttons = Buttons(piece[1])
            local glyphs = { }
            local across = 0
            for index, button in ipairs(buttons) do
                if index > 1 then
                    across = across + glyphGap
                end
                glyphs[index] = { button = button, x = across }
                across = across + controller.GlyphWidth(button, lineHeight)
            end
            local whole = across + whatGap + imgui.CalcTextSize(piece[2])
            if x > 0 and x + gap + whole > width then
                x, y = 0, y + lineHeight + rowGap
            elseif x > 0 then
                x = x + gap
            end
            placed[#placed + 1] = { x = x, y = y, glyphs = glyphs, what = piece[2], whatX = x + across + whatGap }
            x = x + whole
        end
    end
    laid.placed = placed
    laid.height = #placed > 0 and y + lineHeight or 0
end

function legend.Draw(pieces, x, y, width, withCycle)
    local _, lineHeight = imgui.CalcTextSize('A')
    lineHeight = lineHeight or 14
    local layout = controller.GetLayout()
    if laid.pieces ~= pieces or laid.layout ~= layout or laid.width ~= width or laid.withCycle ~= withCycle
        or laid.lineHeight ~= lineHeight then
        laid.pieces, laid.layout, laid.width, laid.withCycle, laid.lineHeight = pieces, layout, width, withCycle, lineHeight
        Lay(pieces, width, withCycle, lineHeight)
    end

    -- behind every window, over the game: it sits under the inventory's, clear of it
    local drawList = imgui.GetBackgroundDrawList()
    for _, piece in ipairs(laid.placed) do
        for _, glyph in ipairs(piece.glyphs) do
            controller.Glyph(drawList, glyph.button, x + piece.x + glyph.x, y + piece.y, lineHeight)
        end
        text.Draw(drawList, x + piece.whatX, y + piece.y, whatColor, piece.what)
    end
    return laid.height
end

return legend
