-- winxi.window: a themed window in one call.
--
--   window.Plain(name, open, flags, draw, options)   for text, bars and icons
--   window.Full(name, open, flags, draw, options)    for a window with tabs, tables, buttons or inputs
--
-- name, open and flags are imgui.Begin's. draw is called to draw the content. Both return whether the
-- window was drawn. Anything imgui needs set for the next window (its size, constraints, or a first
-- position) is set by the caller beforehand, as usual.
--
-- options (all optional):
--   padding     a number, in place of the theme's padding
--   background  a colour, in place of the theme's background
--   alpha       0 to 1, for a window that fades (winxi.fade); at 0 the window is not drawn at all
--   shadow      false for a window that should not have the theme's drop shadow
--   growFrom    the corner that stays put as the content changes size (see winxi.anchor); with any
--               corner but TopLeft, draw is called twice a frame, once to measure
local style = require('winxi.style');
local shadow = require('winxi.shadow');
local anchor = require('winxi.anchor');

local window = {};

local function Draw(full, name, open, flags, draw, options)
    local alpha = options and options.alpha;
    if alpha and alpha <= 0.01 then
        return false;
    end

    if full then
        style.PushFull(options);
    else
        style.PushPlain(options);
    end

    local growFrom = options and options.growFrom;
    if growFrom then
        anchor.Measure(name, growFrom, draw);
        anchor.Place(name, growFrom);
    end

    local drawn = imgui.Begin(name, open, flags);
    if drawn then
        if growFrom then
            anchor.Track(name, growFrom);
        end
        if not (options and options.shadow == false) then
            shadow.Draw();
        end
        draw();
    end
    imgui.End();

    style.Pop();
    return drawn;
end

function window.Plain(name, open, flags, draw, options)
    return Draw(false, name, open, flags, draw, options);
end

function window.Full(name, open, flags, draw, options)
    return Draw(true, name, open, flags, draw, options);
end

return window;
