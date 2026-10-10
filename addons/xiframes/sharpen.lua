-- sharpen: makes a status icon firmer. The game's own icons are soft, small paintings, and beside
-- icons that have been drawn again (an icon set such as XiView redraws some and leaves the rest) they
-- look blurred. Each pixel of one is moved away from the average of itself and those round it, which
-- is what makes an edge an edge. And every icon, the game's or not, is given a dark line round it.
--
--     sharpen.IsGames(bytes, first)    whether an icon is one of the game's own
--     sharpen.Icon(bytes, first)       sharpens it, in place
--     sharpen.Outline(bytes, first)    gives it a dark line round its edge, in place
--
-- bytes is the icon's bitmap as a list of numbers, and first where its pixels start in that: 32 rows
-- of 32, four bytes each, blue, green, red and alpha. A pixel with no alpha is left alone, and is not
-- counted among another's neighbours.
--
-- One of the game's own is known by its alpha: the game counts 128 as solid, so none of its icons
-- has more, where an icon drawn again is solid at 255. Those are sharp already and are left as they are.
--
-- The line is the icon's own outermost pixels, darkened nearly to black: it is not added round the
-- icon, so the icon stays its size. A pixel fainter than faintest (as a part of the icon's most
-- alpha) is the soft fringe of a painting and is taken away, which leaves the line a clean one. A
-- pixel is only darkened where it has the icon's inside beside it: a part too thin to have an inside,
-- a limb or a stroke two pixels wide, is left in its colours, or it would be all line.
local sharpen = { }

local side = 32
local gamesSolid = 136 -- the most alpha one of the game's icons has, with a little to spare
local amount = 1.5     -- how far a pixel is moved from the average round it
local faintest = 48 / 128 -- of the icon's most alpha: fainter than this is not part of the icon
local lineKeeps = 0.1  -- how much of its colour a pixel of the line is left with

function sharpen.IsGames(bytes, first)
    for pixel = 0, side * side - 1 do
        if bytes[first + pixel * 4 + 3] > gamesSolid then
            return false
        end
    end
    return true
end

function sharpen.Icon(bytes, first)
    -- the icon as it was: what each pixel is measured against
    local was = { }
    for index = 0, side * side * 4 - 1 do
        was[index] = bytes[first + index]
    end

    for y = 0, side - 1 do
        for x = 0, side - 1 do
            local at = (y * side + x) * 4
            if was[at + 3] > 0 then
                -- the average round it, the pixel itself and those beside it counting for more than
                -- those at its corners; a neighbour off the icon or with no alpha is taken as the pixel itself
                local blue, green, red, weights = 0, 0, 0, 0
                for dy = -1, 1 do
                    for dx = -1, 1 do
                        local nx, ny = x + dx, y + dy
                        local near = at
                        if nx >= 0 and nx < side and ny >= 0 and ny < side then
                            local there = (ny * side + nx) * 4
                            if was[there + 3] > 0 then
                                near = there
                            end
                        end
                        local weight = (dx == 0 and 2 or 1) * (dy == 0 and 2 or 1)
                        blue, green, red = blue + was[near] * weight, green + was[near + 1] * weight, red + was[near + 2] * weight
                        weights = weights + weight
                    end
                end
                for channel, sum in ipairs({ blue, green, red }) do
                    local value = was[at + channel - 1]
                    value = math.floor(value + amount * (value - sum / weights) + 0.5)
                    bytes[first + at + channel - 1] = math.max(0, math.min(255, value))
                end
            end
        end
    end
end

function sharpen.Outline(bytes, first)
    local most = 0
    for pixel = 0, side * side - 1 do
        most = math.max(most, bytes[first + pixel * 4 + 3])
    end
    local least = math.floor(most * faintest + 0.5)

    -- which pixels are the icon, and of those which are its edge: one with a side not on the icon
    local solid, edge = { }, { }
    local function Solid(x, y)
        return x >= 0 and x < side and y >= 0 and y < side and solid[y * side + x]
    end
    for pixel = 0, side * side - 1 do
        solid[pixel] = bytes[first + pixel * 4 + 3] >= least and least > 0
    end
    for y = 0, side - 1 do
        for x = 0, side - 1 do
            edge[y * side + x] = solid[y * side + x]
                and not (Solid(x - 1, y) and Solid(x + 1, y) and Solid(x, y - 1) and Solid(x, y + 1))
        end
    end

    for y = 0, side - 1 do
        for x = 0, side - 1 do
            local pixel = y * side + x
            local at = first + pixel * 4
            if not solid[pixel] then
                bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3] = 0, 0, 0, 0
            elseif edge[pixel] then
                local inside = false
                for dy = -1, 1 do
                    for dx = -1, 1 do
                        if Solid(x + dx, y + dy) and not edge[(y + dy) * side + x + dx] then
                            inside = true
                        end
                    end
                end
                if inside then
                    for channel = 0, 2 do
                        bytes[at + channel] = math.floor(bytes[at + channel] * lineKeeps + 0.5)
                    end
                end
            end
        end
    end
end

return sharpen
