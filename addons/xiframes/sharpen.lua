-- sharpen: makes a status icon of the game's own crisper. Those icons are soft, small paintings, and
-- beside icons that have been drawn again (an icon set such as XiView redraws some and leaves the
-- rest) they look blurred. Each pixel is moved away from the average of itself and those round it,
-- which is what makes an edge an edge.
--
--     sharpen.IsGames(bytes, first)    whether an icon is one of the game's own
--     sharpen.Icon(bytes, first)       sharpens it, in place
--
-- bytes is the icon's bitmap as a list of numbers, and first where its pixels start in that: 32 rows
-- of 32, four bytes each, blue, green, red and alpha. A pixel with no alpha is left alone, and is not
-- counted among another's neighbours.
--
-- One of the game's own is known by its alpha: the game counts 128 as solid, so none of its icons
-- has more, where an icon drawn again is solid at 255. Those are sharp already and are left as they are.
local sharpen = { }

local side = 32
local gamesSolid = 136 -- the most alpha one of the game's icons has, with a little to spare
local amount = 1.5     -- how far a pixel is moved from the average round it

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

return sharpen
