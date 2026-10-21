-- A map drawn into a square on the screen: its picture, the part of it shown, and who is where on it.
--
-- The view knows nothing of the window it is in: it is given a draw list and a square, and draws the
-- map there. Atlas's own window gives it one; a square where the game draws its own map can be given
-- it later, without anything here changing.
--
--   view.New()                                 a view of the whole map, following the player
--   view.Zoom(state, zoom, mx, my)             nearer or further, the place mx, my on the map kept
--                                              where it is on the screen
--   view.Pan(state, dx, dy)                    moved by so many map units; no longer following
--   view.Follow(state, on)                     kept with the player at its middle, or not
--   view.Reset(state)                          the whole map again, following the player
--   view.Input(state, x, y, size, hovered, active)   the mouse over the square: the wheel zooms
--                                              round the place under it, a drag pans
--   view.Track(state, mx, my)                  the player's place on the map, kept at the middle while
--                                              following
--   view.Draw(drawList, state, x, y, size, scene, options, alpha)   the map in the square at x, y;
--                                              scene is { picture, markers = { { kind, mx, my,
--                                              heading, name, near } }, waypoint = { mx, my } or nil,
--                                              cursor = { mx, my } or nil }, places in map units;
--                                              returns the place on the map under the mouse, or nil
local imgui = require('imgui');
local text = require('winxi.text');
local view = {};

view.Size = 512;    -- map units across a map
view.MinZoom, view.MaxZoom = 1, 8;
local WHEEL_STEP = 1.25;

-- The middle of what is shown, kept so that nothing past the map's edge is
local function Clamp(state)
    local half = view.Size / 2 / state.zoom;
    state.cx = math.max(half, math.min(view.Size - half, state.cx));
    state.cy = math.max(half, math.min(view.Size - half, state.cy));
end

function view.New()
    local state = {};
    view.Reset(state);
    return state;
end

function view.Reset(state)
    state.zoom, state.cx, state.cy, state.follow = 1, view.Size / 2, view.Size / 2, true;
    state.mouseX, state.mouseY = nil, nil;
end

function view.Zoom(state, zoom, mx, my)
    zoom = math.max(view.MinZoom, math.min(view.MaxZoom, zoom));
    local ratio = state.zoom / zoom;
    if mx ~= nil and not state.follow then
        state.cx = mx - (mx - state.cx) * ratio;
        state.cy = my - (my - state.cy) * ratio;
    end
    state.zoom = zoom;
    Clamp(state);
end

function view.Pan(state, dx, dy)
    state.cx, state.cy = state.cx + dx, state.cy + dy;
    state.follow = false;
    Clamp(state);
end

function view.Follow(state, on)
    state.follow = on and true or false;
end

-- The part of the map shown: its top left corner and how far across, in map units
local function Region(state)
    local span = view.Size / state.zoom;
    return state.cx - span / 2, state.cy - span / 2, span;
end

function view.Input(state, x, y, size, hovered, active)
    local mouseX, mouseY = imgui.GetMousePos();
    if mouseX == nil or mouseY == nil then
        return;
    end
    local left, top, span = Region(state);
    local unit = size / span; -- pixels to a map unit
    if hovered then
        local wheel = imgui.GetIO().MouseWheel or 0;
        if wheel ~= 0 then
            view.Zoom(state, state.zoom * WHEEL_STEP ^ wheel, left + (mouseX - x) / unit, top + (mouseY - y) / unit);
        end
    end
    if active and imgui.IsMouseDown(0) then
        if state.mouseX ~= nil and (mouseX ~= state.mouseX or mouseY ~= state.mouseY) then
            view.Pan(state, (state.mouseX - mouseX) / unit, (state.mouseY - mouseY) / unit);
        end
        state.mouseX, state.mouseY = mouseX, mouseY;
    else
        state.mouseX, state.mouseY = nil, nil;
    end
end

-- Drawing

local cornerA, cornerB, uvA, uvB = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
local p1, p2, p3, p4 = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
local white, blank, shade, colour = { 1, 1, 1, 1 }, { 0.10, 0.10, 0.12, 1 }, { 0, 0, 0, 0.85 }, { 1, 1, 1, 1 };

local function Packed(c, alpha)
    colour[1], colour[2], colour[3], colour[4] = c[1], c[2], c[3], (c[4] or 1) * alpha;
    return imgui.GetColorU32(colour);
end

local function Point(point, x, y, angle, reach)
    point[1], point[2] = x + math.cos(angle) * reach, y + math.sin(angle) * reach;
end

-- An arrow pointing the way the heading is, with a dark edge
local function Arrow(drawList, x, y, heading, size, fill, edge)
    Point(p1, x, y, heading, size * 0.75); Point(p2, x, y, heading + 2.4, size * 0.6); Point(p3, x, y, heading - 2.4, size * 0.6);
    drawList:AddTriangleFilled(p1, p2, p3, edge);
    Point(p1, x, y, heading, size * 0.6); Point(p2, x, y, heading + 2.4, size * 0.45); Point(p3, x, y, heading - 2.4, size * 0.45);
    drawList:AddTriangleFilled(p1, p2, p3, fill);
end

local function Dot(drawList, x, y, size, fill, edge, hollow)
    p1[1], p1[2] = x, y;
    drawList:AddCircleFilled(p1, size / 2 + 1.5, edge, 12);
    if hollow then
        drawList:AddCircle(p1, size / 2 - 1, fill, 12, 2);
    else
        drawList:AddCircleFilled(p1, size / 2, fill, 12);
    end
end

local function Diamond(drawList, x, y, size, fill, edge)
    local r = size / 2 + 1.5;
    p1[1], p1[2], p2[1], p2[2], p3[1], p3[2], p4[1], p4[2] = x, y - r, x + r, y, x, y + r, x - r, y;
    drawList:AddQuadFilled(p1, p2, p3, p4, edge);
    r = size / 2;
    p1[1], p1[2], p2[1], p2[2], p3[1], p3[2], p4[1], p4[2] = x, y - r, x + r, y, x, y + r, x - r, y;
    drawList:AddQuadFilled(p1, p2, p3, p4, fill);
end

local WAYPOINT = { 0.95, 0.45, 0.95, 1 };
local CURSOR = { 1, 1, 1, 0.9 };

-- The waypoint: a dot in a ring, with a dark edge
local function Waypoint(drawList, x, y, size, fill, edge)
    p1[1], p1[2] = x, y;
    drawList:AddCircle(p1, size * 0.9, edge, 16, 4);
    drawList:AddCircle(p1, size * 0.9, fill, 16, 2);
    drawList:AddCircleFilled(p1, size * 0.3 + 1.5, edge, 12);
    drawList:AddCircleFilled(p1, size * 0.3, fill, 12);
end

-- The cursor: a ring with four ticks pointing in at its middle, with a dark edge
local function Cursor(drawList, x, y, size, fill, edge)
    local r = size;
    p1[1], p1[2] = x, y;
    drawList:AddCircle(p1, r, edge, 20, 3);
    drawList:AddCircle(p1, r, fill, 20, 1.5);
    for i = 0, 3 do
        local angle = i * math.pi / 2;
        Point(p2, x, y, angle, r * 1.5);
        Point(p3, x, y, angle, r * 0.5);
        drawList:AddLine(p2, p3, edge, 3);
        drawList:AddLine(p2, p3, fill, 1.5);
    end
end

local colourOf = { player = 'playerColor', party = 'partyColor', alliance = 'allianceColor', target = 'targetColor' };
local shownOf = { player = 'showPlayer', party = 'showParty', alliance = 'showAlliance', target = 'showTarget' };
-- drawn in this order, so the player is on top of the rest
local order = { 'target', 'alliance', 'party', 'player' };

function view.Draw(drawList, state, x, y, size, scene, options, alpha)
    alpha = alpha or 1;
    local left, top, span = Region(state);
    local unit = size / span;
    cornerA[1], cornerA[2], cornerB[1], cornerB[2] = x, y, x + size, y + size;
    blank[4] = alpha;
    drawList:AddRectFilled(cornerA, cornerB, imgui.GetColorU32(blank), 0);
    if scene.picture ~= nil then
        uvA[1], uvA[2] = left / view.Size, top / view.Size;
        uvB[1], uvB[2] = (left + span) / view.Size, (top + span) / view.Size;
        white[4] = alpha;
        drawList:AddImage(scene.picture, cornerA, cornerB, uvA, uvB, imgui.GetColorU32(white));
    end

    drawList:PushClipRect(cornerA, cornerB, true);
    shade[4] = 0.85 * alpha;
    local edge = imgui.GetColorU32(shade);
    local markerSize = options.markerSize[1];
    local showNames = options.showNames[1];
    local dark = Packed(text.EdgeColor(), alpha);
    for _, kind in ipairs(order) do
        if options[shownOf[kind]][1] then
            local fill = Packed(options[colourOf[kind]], alpha);
            for _, marker in ipairs(scene.markers) do
                if marker.kind == kind then
                    local sx, sy = x + (marker.mx - left) * unit, y + (marker.my - top) * unit;
                    if kind == 'player' then
                        Arrow(drawList, sx, sy, marker.heading or 0, markerSize * 1.6, fill, edge);
                    elseif kind == 'target' then
                        Diamond(drawList, sx, sy, markerSize, fill, edge);
                    else
                        -- a member placed by the server's word alone is drawn hollow
                        Dot(drawList, sx, sy, markerSize, fill, edge, not marker.near);
                    end
                    if showNames and kind ~= 'player' and marker.name ~= nil and marker.name ~= '' then
                        text.Packed(drawList, sx + markerSize / 2 + 4, sy - imgui.GetFontSize() / 2, fill, marker.name, nil, dark);
                    end
                end
            end
        end
    end
    if scene.waypoint ~= nil then
        local w = scene.waypoint;
        Waypoint(drawList, x + (w.mx - left) * unit, y + (w.my - top) * unit, markerSize, Packed(WAYPOINT, alpha), edge);
    end
    if scene.cursor ~= nil then
        local c = scene.cursor;
        Cursor(drawList, x + (c.mx - left) * unit, y + (c.my - top) * unit, markerSize, Packed(CURSOR, alpha), edge);
    end
    drawList:PopClipRect();

    local mouseX, mouseY = imgui.GetMousePos();
    if mouseX ~= nil and mouseY ~= nil and mouseX >= x and mouseX < x + size and mouseY >= y and mouseY < y + size then
        return left + (mouseX - x) / unit, top + (mouseY - y) / unit;
    end
    return nil;
end

-- Kept with the player at its middle, while it is following
function view.Track(state, mx, my)
    if state.follow and mx ~= nil then
        state.cx, state.cy = mx, my;
        Clamp(state);
    end
end

return view;
