-- Pure map-space geometry and stable transition tracking; no Ashita dependencies.
local M = {};
-- Editor operations replace polygon tables; weak keys release superseded drag previews.
local bounds_cache = setmetatable({}, { __mode = 'k' });
function M.bounds(polygon)
    local bounds = bounds_cache[polygon];
    if bounds then return bounds; end
    bounds = { math.huge, math.huge, -math.huge, -math.huge };
    for _, p in ipairs(polygon) do
        bounds[1], bounds[2] = math.min(bounds[1], p[1]), math.min(bounds[2], p[2]);
        bounds[3], bounds[4] = math.max(bounds[3], p[1]), math.max(bounds[4], p[2]);
    end
    bounds_cache[polygon] = bounds;
    return bounds;
end
local function near_bounds(polygon, x, y, radius)
    local b = M.bounds(polygon);
    return x >= b[1] - radius and x <= b[3] + radius and y >= b[2] - radius and y <= b[4] + radius;
end
local arcs = {};
for i = 0, 63 do
    local a, b = i * math.pi / 32, (i + 1) * math.pi / 32;
    local middle = (a + b) / 2;
    arcs[i + 1] = { math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(middle), math.sin(middle) };
end

function M.finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge;
end

function M.world_to_map(entry, x, y)
    if (not entry or not M.finite(x) or not M.finite(y) or not M.finite(entry.scale)
        or entry.scale == 0 or not M.finite(entry.offset_x) or not M.finite(entry.offset_y)) then
        return nil, nil;
    end
    local factor = math.abs(entry.scale) / 5.0;
    return x * factor - entry.offset_x, -y * factor - entry.offset_y;
end

function M.map_to_world(entry, x, y)
    if (not entry or not M.finite(x) or not M.finite(y) or not M.finite(entry.scale)
        or entry.scale == 0 or not M.finite(entry.offset_x) or not M.finite(entry.offset_y)) then
        return nil, nil;
    end
    local factor = math.abs(entry.scale) / 5.0;
    return (x + entry.offset_x) / factor, -(y + entry.offset_y) / factor;
end

local function segment_distance_squared(x, y, a, b)
    local dx, dy = b[1] - a[1], b[2] - a[2];
    local length = dx * dx + dy * dy;
    local t = length > 0 and ((x - a[1]) * dx + (y - a[2]) * dy) / length or 0;
    t = math.max(0, math.min(1, t));
    local ex, ey = x - (a[1] + t * dx), y - (a[2] + t * dy);
    return ex * ex + ey * ey;
end

function M.contains(polygon, x, y)
    if (not M.finite(x) or not M.finite(y) or not polygon or #polygon < 3) then
        return false;
    end
    if not near_bounds(polygon, x, y, 0.00001) then return false; end
    local inside = false;
    local previous = polygon[#polygon];
    for _, point in ipairs(polygon) do
        -- Treat the boundary as inside, including horizontal and zero-length edges.
        if (segment_distance_squared(x, y, previous, point) < 0.0000000001) then
            return true;
        end
        if ((point[2] > y) ~= (previous[2] > y)) then
            local cross_x = (previous[1] - point[1]) * (y - point[2]) / (previous[2] - point[2]) + point[1];
            if (x < cross_x) then inside = not inside; end
        end
        previous = point;
    end
    return inside;
end

local function edge_distance_squared(polygon, x, y)
    local distance = math.huge;
    local previous = polygon[#polygon];
    for _, point in ipairs(polygon) do
        distance = math.min(distance, segment_distance_squared(x, y, previous, point));
        previous = point;
    end
    return distance;
end
function M.edge_distance(polygon, x, y)
    return math.sqrt(edge_distance_squared(polygon, x, y));
end

-- An area may be limited to a band of elevation (z_min/z_max, in yalms as the client reports Z).
-- Without a sampled height, or without limits, an area has every height.
local HEIGHT_SLACK = 1.0; -- Kept by the current area, so a jump or a step does not leave it.
function M.in_height(area, z, slack)
    if (z == nil or (area.z_min == nil and area.z_max == nil)) then return true; end
    slack = slack or 0;
    return (area.z_min == nil or z >= area.z_min - slack) and (area.z_max == nil or z <= area.z_max + slack);
end

-- The size of a polygon, kept as its bounds are: a shop inside a square is the smaller of the two.
local size_cache = setmetatable({}, { __mode = 'k' });
function M.size(polygon)
    local size = size_cache[polygon];
    if size then return size; end
    size = 0;
    local previous = polygon[#polygon];
    for _, point in ipairs(polygon) do
        size = size + previous[1] * point[2] - point[1] * previous[2];
        previous = point;
    end
    size = math.abs(size) / 2;
    size_cache[polygon] = size;
    return size;
end

-- An exact area (a building) is entered by stepping inside it: it has no approach distance, and
-- only a sliver of slack on the way out.
local EXACT_MARGIN = 0.5;
function M.classify(areas, x, y, current_id, margin, approach, z)
    if (not M.finite(x) or not M.finite(y)) then return nil; end
    if (z ~= nil and not M.finite(z)) then z = nil; end
    approach = math.max(0, approach or 0);
    -- The actual feature wins over a neighbouring feature's overlapping approach buffer, and of two
    -- features one inside the other, the smaller: the shop, not the street it stands in.
    local inside;
    for _, area in ipairs(areas) do
        if (area.enabled ~= false and M.in_height(area, z, area.id == current_id and HEIGHT_SLACK or 0)
            and M.contains(area.polygon, x, y)
            and (inside == nil or M.size(area.polygon) < M.size(inside.polygon))) then inside = area; end
    end
    if inside then return inside; end
    -- Retain the current approach area through small boundary excursions.
    for _, area in ipairs(areas) do
        local exit_radius = area.exact and math.min(margin or 0, EXACT_MARGIN) or (approach + (margin or 0));
        if (area.enabled ~= false and area.id == current_id and exit_radius >= 0
            and M.in_height(area, z, HEIGHT_SLACK)
            and near_bounds(area.polygon, x, y, exit_radius)
            and edge_distance_squared(area.polygon, x, y) <= exit_radius * exit_radius) then
            return area;
        end
    end
    -- In overlapping buffers choose the nearest feature, not the first table entry.
    local nearest, distance = nil, math.huge;
    for _, area in ipairs(areas) do
        if area.enabled ~= false and not area.exact and M.in_height(area, z) and near_bounds(area.polygon, x, y, approach) then
            local d = edge_distance_squared(area.polygon, x, y);
            if d <= approach * approach and d < distance then nearest, distance = area, d; end
        end
    end
    return nearest; -- Beyond the finite approach distance, terrain stays unlabelled.
end

-- Sample the exposed boundary of the polygon's rounded buffer for the debug overlay.
-- Membership above uses exact segment distance, not this approximate rendering.
function M.approach_outline(polygon, radius)
    local lines = {};
    if (radius <= 0) then return lines; end
    local function exposed(x, y)
        return not M.contains(polygon, x, y) and M.edge_distance(polygon, x, y) >= radius - 0.00001;
    end
    local previous = polygon[#polygon];
    for _, point in ipairs(polygon) do
        local dx, dy = point[1] - previous[1], point[2] - previous[2];
        local length = math.sqrt(dx * dx + dy * dy);
        if (length > 0) then
            local steps = math.max(1, math.ceil(length / 2));
            for side = -1, 1, 2 do
                local ox, oy = side * dy * radius / length, -side * dx * radius / length;
                for i = 0, steps - 1 do
                    local middle = (i + 0.5) / steps;
                    if (exposed(previous[1] + dx * middle + ox, previous[2] + dy * middle + oy)) then
                        lines[#lines + 1] = {
                            { previous[1] + dx * i / steps + ox, previous[2] + dy * i / steps + oy },
                            { previous[1] + dx * (i + 1) / steps + ox, previous[2] + dy * (i + 1) / steps + oy },
                        };
                    end
                end
            end
        end
        for _, arc in ipairs(arcs) do
            if (exposed(point[1] + radius * arc[5], point[2] + radius * arc[6])) then
                lines[#lines + 1] = {
                    { point[1] + radius * arc[1], point[2] + radius * arc[2] },
                    { point[1] + radius * arc[3], point[2] + radius * arc[4] },
                };
            end
        end
        previous = point;
    end
    return lines;
end

function M.new_tracker(delay)
    return { delay = delay or 1.0, initialized = false, current = nil, pending = nil, pending_since = 0 };
end

function M.reset(tracker)
    tracker.initialized, tracker.current, tracker.pending, tracker.pending_since = false, nil, nil, 0;
end

-- delay, if given, stands in for the tracker's own for this sample.
function M.update(tracker, candidate, now, delay)
    if (not tracker.initialized) then
        tracker.initialized, tracker.current = true, candidate;
        tracker.pending, tracker.pending_since = candidate, now;
        return false, candidate; -- Seed without announcing on addon load/zone entry/recovery.
    end
    if (candidate == tracker.current) then
        tracker.pending, tracker.pending_since = candidate, now;
        return false, tracker.current;
    end
    if (candidate ~= tracker.pending) then
        tracker.pending, tracker.pending_since = candidate, now;
        return false, tracker.current;
    end
    if (now - tracker.pending_since >= (delay or tracker.delay)) then
        tracker.current = candidate;
        return true, candidate; -- Includes a stable exit to nil.
    end
    return false, tracker.current;
end

return M;
