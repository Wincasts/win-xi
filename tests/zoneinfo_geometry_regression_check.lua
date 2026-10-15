-- Compare optimized membership with an uncached reference, including boundary tolerances.
package.path = 'addons/zone/?.lua;' .. package.path;
local g = require('area_geometry');
local catalog = require('map_catalog');
local function distance(p, x, y)
    local best, a = math.huge, p[#p];
    for _, b in ipairs(p) do
        local dx, dy = b[1] - a[1], b[2] - a[2];
        local length = dx * dx + dy * dy;
        local t = length > 0 and ((x - a[1]) * dx + (y - a[2]) * dy) / length or 0;
        t = math.max(0, math.min(1, t));
        local ex, ey = x - (a[1] + t * dx), y - (a[2] + t * dy);
        best = math.min(best, math.sqrt(ex * ex + ey * ey)); a = b;
    end
    return best;
end
local function contains(p, x, y)
    if distance(p, x, y) < .00001 then return true; end
    local inside, a = false, p[#p];
    for _, b in ipairs(p) do
        if (b[2] > y) ~= (a[2] > y) and x < (a[1] - b[1]) * (y - b[2]) / (a[2] - b[2]) + b[1] then inside = not inside; end
        a = b;
    end
    return inside;
end
local function size(p)
    local total, a = 0, p[#p];
    for _, b in ipairs(p) do total = total + a[1] * b[2] - b[1] * a[2]; a = b; end
    return math.abs(total) / 2;
end
local function reference(areas, x, y, current, margin, radius)
    -- Of the features a point is inside, the smallest; an exact one (a building) has no approach.
    local inside;
    for _, a in ipairs(areas) do
        if a.enabled ~= false and contains(a.polygon, x, y) and (not inside or size(a.polygon) < size(inside.polygon)) then inside = a; end
    end
    if inside then return inside; end
    for _, a in ipairs(areas) do
        local reach = a.exact and math.min(margin, .5) or radius + margin;
        if a.enabled ~= false and a.id == current and distance(a.polygon, x, y) <= reach then return a; end
    end
    local nearest, best = nil, math.huge;
    for _, a in ipairs(areas) do
        local d = distance(a.polygon, x, y);
        if a.enabled ~= false and not a.exact and d <= radius and d < best then nearest, best = a, d; end
    end
    return nearest;
end
local checks = 0;
local function compare(map, x, y, current, margin, radius)
    local expected = reference(map.areas, x, y, current, margin, radius);
    local actual = g.classify(map.areas, x, y, current, margin, radius);
    assert(actual == expected, ('membership changed: %s at %.12f, %.12f radius=%g'):format(map.key, x, y, radius));
    checks = checks + 1;
    return actual and actual.id;
end
for _, map in ipairs(catalog.list) do
    local current;
    for i = 0, 119 do current = compare(map, i * 17 % 512, i * 31 % 512, current, 3, 30); end
    for _, a in ipairs(map.areas) do
        for _, p in ipairs(a.polygon) do
            for _, delta in ipairs({ 0, .000001, -.000001, .00001, -.00001, 29.99999, 30, 30.00001, 33 }) do
                compare(map, p[1] + delta, p[2], a.id, 3, 30);
            end
        end
    end
end
local square = { { 0, 0 }, { 10, 0 }, { 10, 10 }, { 0, 10 } };
assert(g.contains(square, -.000001, 5), 'bounds reject tolerant edge containment');
assert(not g.contains(square, -.001, 5), 'bounds enlarge containment');
local edited = { { 100, 100 }, { 110, 100 }, { 110, 110 }, { 100, 110 } };
assert(not g.contains(edited, 5, 5) and g.contains(edited, 105, 105), 'replacement polygon has fresh bounds');
print(('zoneinfo geometry equivalence: %d comparisons passed'):format(checks));
