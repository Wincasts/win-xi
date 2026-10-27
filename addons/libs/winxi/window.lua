-- winxi.window: a themed window in one call.
--
--   window.Plain(name, open, flags, draw, options)   for text, bars and icons
--   window.Full(name, open, flags, draw, options)    for a window with tabs, tables, buttons or inputs
--
-- name, open and flags are imgui.Begin's. draw is called to draw the content. Both return whether the
-- window was drawn. Anything imgui needs set for the next window (its size, constraints, or a first
-- position) is set by the caller beforehand, as usual.
--
-- Every window is one of two kinds, which the addon says with options.kind:
--   window.Game      'game', what is drawn on the screen as the game is played: the theme's window
--                    background (winxi.backgrounds) and border art (winxi.borders), if it has any, in place of imgui's own border, and
--                    the theme's font at the theme's size (winxi.fonts). The kind of a window that
--                    does not say.
--   window.Settings  'settings', a settings window and anything else for changing how things are set:
--                    the theme's values for settings windows (winxi.theme's Settings keys): their own
--                    colours, padding, font and font size, a plain border and no shadow, so that what
--                    is set for the game's windows does not change the window it is set in.
-- A settings window can be resized, whatever flags it is given. It fits its content, as it changes,
-- until it is resized by a grip or an edge; from then it keeps the size it was given, its controls
-- narrowing to fit it (winxi.widgets) and its content scrolling where it is still too big. A
-- double-click on a grip or an edge fits it to its content again. A fitted window is never taller than
-- window.FitHeightShare of the screen (three quarters), its content scrolling below that. With the
-- theme's Starting Height set (SettingsWindowHeight, winxisettings' Settings Windows tab), a fitted
-- window is that tall rather than as tall as its content; its width still fits. Fitted or not, it is never bigger
-- than the screen. window.IsResized() says, while a window's content is drawn, whether it is a
-- settings window that has been resized; window.DrawnSize() how big the settings window being drawn is.
--
-- Either way the font is pushed around the window, so it is what the window is written in unless draw
-- pushes a font or size of its own.
--
-- options (all optional):
--   padding     a number, in place of the theme's padding
--   fontSize    pixels, overriding the theme's font size for this window only (typeface unchanged)
--   background  a colour, in place of the theme's background
--   alpha       0 to 1, for a window that fades (winxi.fade); at 0 the window is not drawn at all
--   shadow      false for a window that should not have the theme's drop shadow
--   kind        window.Game (the default) or window.Settings, as above
--   controller  a binding of winxi.controller: the window is marked while that binding has the
--               controller (see controller.Highlight)
--   title       words for the top edge of a window of the game kind (winxi.titles), as the theme draws
--               them; a settings window has imgui's own title
--   capture     optional callback after content AND border/title art, before End; for native-hook
--               capture of the complete window. Not called during anchor measurement. Such a
--               window's shadow is drawn on its own list (shadow.Draw(true)), so it is captured too.
--   growFrom    the corner that stays put as the content changes size (see winxi.anchor); with any
--               corner but TopLeft, draw is called twice a frame, once to measure
--   locked      true for a window held where it is (imgui's NoMove), as an addon's Lock Window
--               setting (widgets.Lock) has it
--   clickThrough true for a window the mouse goes through to the game (imgui's NoInputs); with locked,
--               what Lock Window means for a window drawn over the game
local bit = require('bit');
local imgui = require('imgui');
local style = require('winxi.style');
local shadow = require('winxi.shadow');
local anchor = require('winxi.anchor');
local controller = require('winxi.controller');
local theme = require('winxi.theme');
local borders = require('winxi.borders');
local fonts = require('winxi.fonts');
local backgrounds = require('winxi.backgrounds');
local titles = require('winxi.titles');

local window = {};

window.Game = 'game';
window.Settings = 'settings';

-- Whether a window's options make it a settings window
function window.IsSettings(options)
    return options ~= nil and options.kind == window.Settings;
end

-- Each settings window's last place and size, and whether it has been resized: by its name
local settingsState = {};
local resized = false; -- the window being drawn is a settings window that has been resized
local drawnWidth, drawnHeight = nil, nil; -- the size of the settings window being drawn
local fitSize = { 0, 0 };  -- a size of 0 fits the window to its content, on each side
local startSize = { 0, 0 }; -- the width fitted, the height the theme's Starting Height
local fitMost = { 0, 0 };   -- the most a fitted window may be: the screen's width, a share of its height
window.FitHeightShare = 0.75;
local screenSize = { 0, 0 };
local edgeReach = 4;       -- how far either side of an edge it can be taken hold of, as imgui has it

function window.IsResized()
    return resized;
end

function window.DrawnSize()
    return drawnWidth, drawnHeight;
end

-- Whether the mouse is where the window's edges or its bottom corners' grips can be taken hold of,
-- as it was last drawn
local function OnEdge(state)
    if state.w == nil then
        return false;
    end
    local mx, my = imgui.GetMousePos();
    if mx == nil or my == nil then
        return false;
    end
    local left, top, right, bottom = state.x, state.y, state.x + state.w, state.y + state.h;
    if mx < left - edgeReach or mx > right + edgeReach or my < top - edgeReach or my > bottom + edgeReach then
        return false;
    end
    if mx <= left + edgeReach or mx >= right - edgeReach or my <= top + edgeReach or my >= bottom - edgeReach then
        return true;
    end
    local grip = math.max((imgui.GetFontSize() or 13) * 1.35, 12);
    return my >= bottom - grip and (mx >= right - grip or mx <= left + grip);
end

local fixedFlags = nil; -- what a settings window may not have: sizing itself, or not being resized

-- Before a settings window's Begin: its flags, and its size if it is fitting its content
local function BeginSettings(name, flags)
    local state = settingsState[name];
    if state == nil then
        state = { resized = false };
        settingsState[name] = state;
    end
    if imgui.IsMouseDoubleClicked(0) and OnEdge(state) then
        state.resized = false;
    elseif imgui.IsMouseClicked(0) and OnEdge(state) then
        state.resized = true;
    end

    if not state.resized then
        local height = tonumber(theme.Get().SettingsWindowHeight) or 0;
        local io = imgui.GetIO();
        local display = io and io.DisplaySize;
        if height > 0 then
            if display and display.y then height = math.min(height, display.y); end
            startSize[2] = height;
            imgui.SetNextWindowSize(startSize, ImGuiCond_Always);
        else
            -- fitted to its content, but never taller than most of the screen: the rest scrolls
            if display and display.x and display.y and imgui.SetNextWindowSizeConstraints ~= nil then
                fitMost[1], fitMost[2] = display.x, display.y * window.FitHeightShare;
                imgui.SetNextWindowSizeConstraints(fitSize, fitMost);
            end
            imgui.SetNextWindowSize(fitSize, ImGuiCond_Always);
        end
    else
        -- resized, but no bigger than the screen
        local io = imgui.GetIO();
        local display = io and io.DisplaySize;
        if display and state.w and (state.w > display.x or state.h > display.y) then
            screenSize[1], screenSize[2] = math.min(state.w, display.x), math.min(state.h, display.y);
            imgui.SetNextWindowSize(screenSize, ImGuiCond_Always);
        end
    end

    fixedFlags = fixedFlags or bit.bor(ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoResize);
    flags = bit.band(flags or 0, bit.bnot(fixedFlags));
    if state.resized then
        flags = bit.bor(flags, ImGuiWindowFlags_HorizontalScrollbar);
    end
    return flags, state;
end

-- The window itself, from its Begin to the end of its content, run under pcall so that a failed draw
-- cannot leave a window or a fading Alpha on the shared imgui context. What it is given and what it got
-- done go in a job table, one for each depth of nesting (a window drawn inside another's content),
-- reused frame after frame: no closure is made for it.
local jobs, depth = {}, 0;

local function Body(job)
    local name, open, flags, draw, options = job.name, job.open, job.flags, job.draw, job.options;
    local settingsKind, state, title, border = job.settingsKind, job.state, job.title, job.border;
    local growFrom = options and options.growFrom;
    if growFrom then
        anchor.Measure(name, growFrom, draw);
        anchor.Place(name, growFrom);
    end

    job.bordered = borders.Push(border, titles.Breaks(title) or (options and options.border ~= nil));
    local drawn = imgui.Begin(name, open, flags);
    job.drawn, job.begun = drawn, true;
    imgui.PopStyleVar(job.bordered);
    job.bordered = 0;
    if drawn then
        if growFrom then anchor.Track(name, growFrom); end
        if not settingsKind and not (options and options.shadow == false) then shadow.Draw(options ~= nil and options.capture ~= nil); end
        backgrounds.Draw(job.background, options and options.background or theme.Get().BackgroundColor);
        if state ~= nil then
            state.x, state.y = imgui.GetWindowPos();
            state.w, state.h = imgui.GetWindowSize();
            resized = state.resized;
            drawnWidth, drawnHeight = state.w, state.h;
        end
        draw();
        resized = false;
        drawnWidth, drawnHeight = nil, nil;
        local gapLeft, gapRight = titles.Gap(title);
        borders.Draw(border, gapLeft, gapRight, options and options.border);
        titles.Draw(title, options);
        if options and options.controller then controller.Highlight(options.controller); end
        if options and options.capture then options.capture(); end
    end
end

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
    local background = style.Background();

    if options ~= nil then
        if options.locked then flags = bit.bor(flags or 0, ImGuiWindowFlags_NoMove); end
        if options.clickThrough then flags = bit.bor(flags or 0, ImGuiWindowFlags_NoInputs); end
    end

    local settingsKind = window.IsSettings(options);
    local state = nil;
    if settingsKind then
        flags, state = BeginSettings(name, flags);
    end
    local font = fonts.Push(settingsKind, options and options.fontSize);

    depth = depth + 1;
    local job = jobs[depth];
    if job == nil then
        job = {};
        jobs[depth] = job;
    end
    job.name, job.open, job.flags, job.draw, job.options = name, open, flags, draw, options;
    job.settingsKind, job.state, job.background = settingsKind, state, background;
    job.border = not settingsKind and borders.Texture(theme.Get().BorderStyle) or nil;
    job.title = not settingsKind and options and options.title or nil;
    job.begun, job.drawn, job.bordered = false, false, 0;
    local ok, err = pcall(Body, job);
    local begun, drawn, bordered = job.begun, job.drawn, job.bordered;
    -- what the job held is let go of, so that nothing of the window's is kept alive by it
    job.open, job.draw, job.options, job.state, job.background = nil, nil, nil, nil, nil;
    depth = depth - 1;

    -- A failed draw must not leave a window or fading Alpha on the shared ImGui context.
    -- Callers still own any font/style stacks they push inside their callbacks.
    if bordered > 0 then imgui.PopStyleVar(bordered); end
    local ended, end_error = true, nil;
    if begun then ended, end_error = pcall(imgui.End); end
    resized = false;
    fonts.Pop(font);
    style.Pop();
    if not ok then error(err, 0); end
    if not ended then error(end_error, 0); end
    return drawn;
end

function window.Plain(name, open, flags, draw, options)
    return Draw(false, name, open, flags, draw, options);
end

function window.Full(name, open, flags, draw, options)
    return Draw(true, name, open, flags, draw, options);
end

return window;
