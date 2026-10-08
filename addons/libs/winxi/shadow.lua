-- winxi.shadow: a soft drop shadow behind the window being drawn.
--
-- A dark copy of the window's outline, moved down and to the right and drawn behind every window. The
-- soft edge is a few faint layers, each a little larger than the last. Call shadow.Draw() inside the
-- window, once it has begun. It follows the theme's shadow settings and fades with the window; with
-- the shadow switched off it costs one check.
local theme = require('winxi.theme');

local shadow = {};

local maxLayers = 6; -- however soft the edge: a wider one spaces the layers further apart
local color = { 0, 0, 0, 0 };
local topLeft, bottomRight = { 0, 0 }, { 0, 0 };

function shadow.Draw()
    local current = theme.Get();
    if not current.ShadowEnabled or imgui.GetBackgroundDrawList == nil then
        return;
    end

    local opacity = current.ShadowOpacity / 100;
    if opacity <= 0 then
        return;
    end

    local x, y = imgui.GetWindowPos();
    local w, h = imgui.GetWindowSize();
    local offset = current.ShadowOffset;
    local blur = current.ShadowBlur;
    local layers = math.max(1, math.min(maxLayers, blur));
    local step = blur / layers;

    -- the colour is worked out each time, as it takes in the window's fade; the tables are reused
    local drawList = imgui.GetBackgroundDrawList();
    color[4] = opacity / layers;
    local packed = imgui.GetColorU32(color);

    for layer = 0, layers - 1 do
        local grow = layer * step;
        topLeft[1], topLeft[2] = x + offset - grow, y + offset - grow;
        bottomRight[1], bottomRight[2] = x + w + offset + grow, y + h + offset + grow;
        drawList:AddRectFilled(topLeft, bottomRight, packed, grow + 2);
    end
end

return shadow;
