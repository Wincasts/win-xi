-- winxi.anchor: "grow from". Which corner of a self-sizing window stays where it is as the window's
-- content changes size.
--
-- ImGui's own behaviour is the top left: a window keeps its top left corner and grows to the right and
-- downwards. The other three hold a different corner still, so the window grows away from it:
-- TopRight grows left and down, BottomLeft right and up, BottomRight left and up.
--
-- To place a corner other than the top left the window's size has to be known before it is drawn, and
-- ImGui only learns a self-sizing window's size by drawing it: left to itself the window would be drawn
-- once at its old size, in the wrong place, every time its content changed. So for those corners the
-- content is first laid out in a window kept off screen, purely to measure it, and the real window is
-- then given exactly that size and position. With the top left chosen none of this is done.
--
-- Around a window, with its styles pushed:
--     anchor.Measure(key, mode, drawContent)   -- lays the content out off screen
--     anchor.Place(key, mode)                  -- before Begin
--     anchor.Track(key, mode)                  -- inside the window, once it has begun
-- winxi.window does this for a window given a growFrom option. While the window is dragged it is left
-- alone, and its corner is taken from where it ends up.
local bit = require('bit');
local imgui = require('imgui');
local style = require('winxi.style');

local anchor = {};

anchor.Modes = { 'TopLeft', 'TopRight', 'BottomLeft', 'BottomRight' };
anchor.Labels = { TopLeft = 'Top Left', TopRight = 'Top Right', BottomLeft = 'Bottom Left', BottomRight = 'Bottom Right' };
anchor.Default = 'TopLeft';

-- Where each corner lies within the window: 0 is its left or top edge, 1 its right or bottom
local pivots = {
    TopLeft     = { 0, 0 },
    TopRight    = { 1, 0 },
    BottomLeft  = { 0, 1 },
    BottomRight = { 1, 1 },
};

-- By window: { mode = the corner the point was taken for, x, y = the point, dragging,
--              w, h = the size its content was last measured to need }
local states = {};
local point, size = { 0, 0 }, { 0, 0 };

local measureOpen = { true };
local measurePos = { -20000, -20000 }; -- well off any screen
local measureFlags = nil;

local function Mode(mode)
    return pivots[mode] and mode or anchor.Default;
end

local function GetState(key)
    local state = states[key];
    if state == nil then
        state = { dragging = false };
        states[key] = state;
    end
    return state;
end

-- Forgets a window's corner, for when it is being moved somewhere by other means
function anchor.Reset(key)
    states[key] = nil;
end

function anchor.Measure(key, mode, drawContent)
    mode = Mode(mode);
    if mode == anchor.Default then
        return;
    end

    if measureFlags == nil then
        measureFlags = bit.bor(
            ImGuiWindowFlags_NoDecoration,
            ImGuiWindowFlags_AlwaysAutoResize,
            ImGuiWindowFlags_NoInputs,
            ImGuiWindowFlags_NoSavedSettings,
            ImGuiWindowFlags_NoFocusOnAppearing or 0,
            ImGuiWindowFlags_NoBringToFrontOnFocus or 0);
    end

    local state = GetState(key);
    imgui.SetNextWindowPos(measurePos, ImGuiCond_Always);
    if imgui.Begin('##winxi_measure_' .. key, measureOpen, measureFlags) then
        -- a group's size is that of everything drawn in it
        imgui.BeginGroup();
        drawContent();
        imgui.EndGroup();

        local w, h = imgui.GetItemRectSize();
        local padding = style.Padding();
        state.w, state.h = w + 2 * padding, h + 2 * padding;
    end
    imgui.End();
    measureOpen[1] = true;
end

function anchor.Place(key, mode)
    mode = Mode(mode);
    local state = states[key];

    -- The top left needs no help
    if mode == anchor.Default or state == nil or state.w == nil then
        return;
    end

    -- The size measured for this frame's content, so the window never shows at a stale one
    size[1], size[2] = state.w, state.h;
    imgui.SetNextWindowSize(size, ImGuiCond_Always);

    -- Nothing is placed until a point has been taken for this corner, nor while the window is dragged
    if state.mode ~= mode or state.x == nil or state.dragging then
        return;
    end

    local pivot = pivots[mode];
    point[1], point[2] = state.x - pivot[1] * state.w, state.y - pivot[2] * state.h;
    imgui.SetNextWindowPos(point, ImGuiCond_Always);
end

function anchor.Track(key, mode)
    mode = Mode(mode);
    local state = GetState(key);

    if state.dragging then
        if not imgui.IsMouseDown(0) then
            state.dragging = false;
        end
    elseif imgui.IsWindowHovered() and imgui.IsMouseClicked(0) then
        state.dragging = true;
    end

    -- The point follows the window while it is free to move: always for the top left, while it is
    -- dragged, and when the corner has just been chosen. Otherwise it stays put and holds the window.
    if mode == anchor.Default or state.dragging or state.mode ~= mode or state.x == nil then
        local x, y = imgui.GetWindowPos();
        local w, h = imgui.GetWindowSize();
        local pivot = pivots[mode];
        state.x, state.y = x + pivot[1] * w, y + pivot[2] * h;
        state.mode = mode;
    end
end

return anchor;
