-- winxi.clip: a clip rect opened past a window's own, kept on the screen.
--
--   clip.Push(list, min, max)   list:PushClipRect(min, max, false), its rect cut to the screen; returns
--                               whether anything is left, and only then is there a clip to pop
--
-- Anything drawn out past its window's edges (a title above it, a shadow beside it, a highlight on its very
-- edge) needs a clip of its own that is not cut to the window's. imgui cuts a window's own clips to the
-- screen, but not one pushed like this, and Ashita draws imgui on Direct3D 8, which has no scissor: each clip
-- becomes a viewport, and a viewport off the screen is refused, leaving the whole screen's, so what was in
-- the clip is stretched over the whole screen. A window dragged to the edge of the screen had its title
-- written across all of it. Every clip opened past a window goes through here, so none reaches off the
-- screen.
local imgui = require('imgui');

local clip = {};

local low, high = { 0, 0 }, { 0, 0 };

function clip.Push(list, min, max)
    local io = imgui.GetIO and imgui.GetIO();
    local display = io and io.DisplaySize;
    -- a screen not yet measured cuts nothing at the far side
    local width = display and tonumber(display.x or display[1]) or 0;
    local height = display and tonumber(display.y or display[2]) or 0;
    low[1], low[2] = math.max(0, min[1]), math.max(0, min[2]);
    high[1] = width > 0 and math.min(width, max[1]) or max[1];
    high[2] = height > 0 and math.min(height, max[2]) or max[2];
    if high[1] <= low[1] or high[2] <= low[2] then
        return false;
    end
    list:PushClipRect(low, high, false);
    return true;
end

return clip;
