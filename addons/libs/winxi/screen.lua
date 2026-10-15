-- winxi.screen: keeps a window on the screen.
--
--   screen.Keep(name)   inside a window, straight after its Begin: if any of the window is off the
--                       screen it is moved back on, against the edge it went over, and true is
--                       returned. A window bigger than the screen is put at its top left.
--
-- Where a window was put stays the addon's: a corner it is held by (winxi.anchor), a place worked out
-- from another window, or a place saved for a screen of another size. The window is only drawn where
-- it can be seen, each frame, so it comes back to its own place when that is on the screen again, and
-- a window dragged against an edge stays at it. An addon that saves its window's place from
-- GetWindowPos after this saves the place it was moved to.
--
-- Call it before anything reads the window's place for the frame (anchor.Track, organize.Track, the
-- shadow), so that all of them have the place it is drawn at.
local imgui = require('imgui');

local screen = {};

local place = { 0, 0 };

function screen.Keep(name)
    local io = imgui.GetIO();
    local display = io and io.DisplaySize;
    if display == nil or not (display.x > 0 and display.y > 0) then
        return false;
    end
    local x, y = imgui.GetWindowPos();
    local w, h = imgui.GetWindowSize();
    if x == nil or y == nil or w == nil or h == nil then
        return false;
    end

    local left = math.max(0, math.min(x, display.x - w));
    local top = math.max(0, math.min(y, display.y - h));
    if left == x and top == y then
        return false;
    end
    place[1], place[2] = left, top;
    imgui.SetWindowPos(name, place);
    return true;
end

return screen;
