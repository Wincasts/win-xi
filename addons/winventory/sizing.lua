-- How big each of winventory's windows is drawn: the inventory, the treasure pool, the Tooltip Window and
-- the equipment monitor each have a Scale. The pool and the Tooltip Window attached to the inventory take
-- the inventory's; detached, their own.
--
--   sizing.Begin()            once a frame, before any window: the font size the theme's windows are in
--   sizing.Clamp(value)       a saved scale kept within what is offered, 0.5 to 3
--   sizing.FontSize(scale)    the theme's font size times scale, in pixels, for winxi.window's fontSize;
--                             nil at 1, which leaves the theme's own
local imgui = require('imgui')
local theme = require('winxi.theme')

local sizing = { Least = 0.5, Most = 3 }

local base = 16

function sizing.Begin()
    local size = tonumber(theme.Get().FontSize) or 0
    if size <= 0 then
        size = tonumber(imgui.GetFontSize()) or base -- imgui's own, with no window's font pushed yet
    end
    base = size
end

function sizing.Clamp(value)
    return math.max(sizing.Least, math.min(sizing.Most, tonumber(value) or 1))
end

function sizing.FontSize(scale)
    if scale == nil or scale == 1 then
        return nil
    end
    return math.max(6, math.floor(base * scale + 0.5))
end

return sizing
