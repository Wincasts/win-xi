-- winxi.clip: a clip rect opened past a window's own, kept on the screen.
--
--   clip.Push(list, min, max)   list:PushClipRect(min, max, false), its rect cut to the screen; returns
--                               whether anything is left, and only then is there a clip to pop
--   clip.Screen(list, min, max) the whole screen as the clip, where what is drawn (min to max) is on it at
--                               all; returns whether it is, and only then is there a clip to pop
--
-- Anything drawn out past its window's edges (a title above it, a shadow beside it, a highlight on its very
-- edge) needs a clip of its own that is not cut to the window's. imgui cuts a window's own clips to the
-- screen, but not one pushed like this, and Ashita draws imgui on Direct3D 8, which has no scissor: each clip
-- becomes a viewport, and a viewport off the screen is refused, leaving the whole screen's, so what was in
-- the clip is stretched over the whole screen. A window dragged to the edge of the screen had its title
-- written across all of it. Every clip opened past a window goes through here, so none reaches off the
-- screen.
--
-- That was not all of it: a title wholly on the screen was still seen stretched, its clip over the whole
-- screen, so something else gives the clip's draws the whole screen's viewport too (Ashita's renderer is not
-- to be read, so what is not known). A clip that is the whole screen is drawn as it is whatever viewport it
-- is given, so what needs no clip of its own, only to reach past its window (a title), uses clip.Screen.
local imgui = require('imgui');

local clip = {};

local low, high = { 0, 0 }, { 0, 0 };
local origin, whole = { 0, 0 }, { 0, 0 };

-- The screen's size, or 0 on a side not yet measured
local function ScreenSize()
    local io = imgui.GetIO and imgui.GetIO();
    local display = io and io.DisplaySize;
    return display and tonumber(display.x or display[1]) or 0, display and tonumber(display.y or display[2]) or 0;
end

-- min to max cut to the screen, in low and high (a side not yet measured cuts nothing); whether anything is left
local function Cut(min, max, width, height)
    low[1], low[2] = math.max(0, min[1]), math.max(0, min[2]);
    high[1] = width > 0 and math.min(width, max[1]) or max[1];
    high[2] = height > 0 and math.min(height, max[2]) or max[2];
    return high[1] > low[1] and high[2] > low[2];
end

function clip.Push(list, min, max)
    if not Cut(min, max, ScreenSize()) then
        return false;
    end
    list:PushClipRect(low, high, false);
    return true;
end

function clip.Screen(list, min, max)
    local width, height = ScreenSize();
    if not Cut(min, max, width, height) then
        return false;
    end
    if width > 0 and height > 0 then
        whole[1], whole[2] = width, height;
        list:PushClipRect(origin, whole, false);
    else
        list:PushClipRect(low, high, false);
    end
    return true;
end

return clip;
