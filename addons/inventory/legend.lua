-- The controller's legend: a line or two under the inventory window saying which buttons do what in
-- the window that has the controller, in winxi's outlined text (it is over the game), each button
-- named as it is printed on the kind of controller in use (winxi.controller's ButtonName).
--
--   legend.Draw(pieces, x, y, width, withCycle)   draws the pieces from x, y, in lines no wider than
--                                                 width; returns how tall it is
--
-- pieces is a list of { button, what }: button a controller.Button, a list of them (LB/RB), or words
-- of its own ('D-pad'); what, what it does. A piece marked cycle = true is the Y of the cycle through
-- the windows, left out when withCycle is false. The lines are laid out again only when the pieces,
-- the kind of controller, the width or the font change.
local imgui = require('imgui')
local controller = require('winxi.controller')
local text = require('winxi.text')

local legend = {}

local gap = 14 -- between pieces on a line, in pixels
local buttonColor = { 1.0, 0.85, 0.3, 1.0 }
local whatColor = { 1.0, 1.0, 1.0, 1.0 }

local laid = { pieces = nil, layout = nil, width = nil, withCycle = nil, lineHeight = nil, height = 0, placed = {} }

local function Name(button)
    if type(button) == 'number' then
        return controller.ButtonName(button)
    elseif type(button) == 'table' then
        local names = {}
        for index, each in ipairs(button) do
            names[index] = controller.ButtonName(each)
        end
        return table.concat(names, '/')
    end
    return button
end

-- Each piece's place in its line: the button's name, then what it does a space after it
local function Lay(pieces, width, withCycle, lineHeight)
    local placed = {}
    local x, y = 0, 0
    for _, piece in ipairs(pieces) do
        if withCycle or not piece.cycle then
            local name = Name(piece[1])
            local what = ' ' .. piece[2]
            local nameWidth = imgui.CalcTextSize(name)
            local whole = nameWidth + imgui.CalcTextSize(what)
            if x > 0 and x + gap + whole > width then
                x, y = 0, y + lineHeight
            elseif x > 0 then
                x = x + gap
            end
            placed[#placed + 1] = { x = x, y = y, name = name, what = what, whatX = x + nameWidth }
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
        text.Draw(drawList, x + piece.x, y + piece.y, buttonColor, piece.name)
        text.Draw(drawList, x + piece.whatX, y + piece.y, whatColor, piece.what)
    end
    return laid.height
end

return legend
