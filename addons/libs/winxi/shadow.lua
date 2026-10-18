-- winxi.shadow: a soft drop shadow behind the window being drawn.
--
-- A dark copy of the window's outline, moved down and to the right and drawn behind every window. The
-- soft edge is a few faint layers, each a little larger than the last. Call shadow.Draw() inside the
-- window, once it has begun. It follows the theme's shadow settings and fades with the window; with
-- the shadow switched off it costs one check.
local imgui = require('imgui');
local theme = require('winxi.theme');

local shadow = {};

local maxLayers = 6; -- however soft the edge: a wider one spaces the layers further apart
local color = { 0, 0, 0, 0 };
local topLeft, bottomRight = { 0, 0 }, { 0, 0 };
local clipMin, clipMax = { 0, 0 }, { 0, 0 };

local function Layers(drawList, x, y, w, h, offset, layers, step, packed)
    for layer = 0, layers - 1 do
        local grow = layer * step;
        topLeft[1], topLeft[2] = x + offset - grow, y + offset - grow;
        bottomRight[1], bottomRight[2] = x + w + offset + grow, y + h + offset + grow;
        drawList:AddRectFilled(topLeft, bottomRight, packed, grow + 2);
    end
end

local function Exterior(drawList, left, top, right, bottom, x, y, w, h, offset, layers, step, packed)
    if right <= left or bottom <= top then return; end
    clipMin[1], clipMin[2], clipMax[1], clipMax[2] = left, top, right, bottom;
    -- Replace the content clip: the shadow is deliberately outside the window.
    drawList:PushClipRect(clipMin, clipMax, false);
    Layers(drawList, x, y, w, h, offset, layers, step, packed);
    drawList:PopClipRect();
end

-- captured=true keeps the exterior shadow on this window's list for native HUD replay.
-- rect optionally supplies an attachment's bounds on the current window's captured list.
function shadow.Draw(captured, rect)
    local current = theme.Get();
    if not current.ShadowEnabled or (not captured and imgui.GetBackgroundDrawList == nil) then
        return;
    end

    local opacity = current.ShadowOpacity / 100;
    if opacity <= 0 then
        return;
    end

    local x, y, w, h;
    if rect then x, y, w, h = rect.left, rect.top, rect.width, rect.height;
    else x, y = imgui.GetWindowPos(); w, h = imgui.GetWindowSize(); end
    local offset = current.ShadowOffset;
    local blur = current.ShadowBlur;
    local layers = math.max(1, math.min(maxLayers, blur));
    local step = blur / layers;

    -- the colour is worked out each time, as it takes in the window's fade; the tables are reused
    local drawList = captured and imgui.GetWindowDrawList() or imgui.GetBackgroundDrawList();
    color[4] = opacity / layers;
    local packed = imgui.GetColorU32(color);

    if captured then
        -- Begin has already emitted the window background/border. Four non-overlapping strips
        -- leave that geometry untouched, including translucent backgrounds, while capturing the
        -- same soft exterior silhouette. No shadow escapes onto ImGui's global background list.
        local grow = (layers - 1) * step;
        local left, top = math.min(x, x + offset - grow), math.min(y, y + offset - grow);
        local right, bottom = math.max(x + w, x + w + offset + grow), math.max(y + h, y + h + offset + grow);
        Exterior(drawList, left, top, right, y, x, y, w, h, offset, layers, step, packed);
        Exterior(drawList, left, y + h, right, bottom, x, y, w, h, offset, layers, step, packed);
        Exterior(drawList, left, y, x, y + h, x, y, w, h, offset, layers, step, packed);
        Exterior(drawList, x + w, y, right, y + h, x, y, w, h, offset, layers, step, packed);
    else
        Layers(drawList, x, y, w, h, offset, layers, step, packed);
    end
end

return shadow;
