-- A fixed 512-reference viewport. Pan/zoom do not change the cached map geometry.
local view = { Size = 512, MinZoom = 1, MaxZoom = 6 };

function view.Reset(state)
    state.zoom, state.x, state.y = 1, 0, 0;
    state.mouseX, state.mouseY = nil, nil;
end

function view.New()
    local state = {};
    view.Reset(state);
    return state;
end

local function Clamp(state)
    local minimum = view.Size * (1 - state.zoom);
    state.x = math.max(minimum, math.min(0, state.x));
    state.y = math.max(minimum, math.min(0, state.y));
end

-- Anchor is in untransformed viewport units, not world/map coordinates.
function view.Zoom(state, zoom, anchorX, anchorY)
    zoom = math.max(view.MinZoom, math.min(view.MaxZoom, zoom));
    local ratio = zoom / state.zoom;
    state.x = anchorX - (anchorX - state.x) * ratio;
    state.y = anchorY - (anchorY - state.y) * ratio;
    state.zoom = zoom;
    Clamp(state);
end

function view.Pan(state, dx, dy)
    state.x, state.y = state.x + dx, state.y + dy;
    Clamp(state);
end

function view.ToMap(state, x, y)
    return (x - state.x) / state.zoom, (y - state.y) / state.zoom;
end

function view.ToViewport(state, x, y)
    return state.x + x * state.zoom, state.y + y * state.zoom;
end

return view;
