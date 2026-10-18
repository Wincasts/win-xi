-- The walkable ground of each map, from data/walkable.lua (tools/trace_walkable_maps.py), as a mask:
-- 0 off the ground, 255 on it, the edge softened over a few pixels so it does not show the mask's
-- steps. winxi.mapdat lays it over the map's picture; flat.lua paints it.
--
--   masks.ForZone(zone)   the maps of a zone with ground traced, by floor: { [floor] = map }
--   masks.Get(map)        { width, height, values, edge, grid, bounds = { x0, y0, x1, y1 } in map units }:
--                         edge 255 on the ground's rim, EDGE pixels in from where it ends, 0 elsewhere;
--                         grid the stretches of the game's grid lines on the ground, in map units:
--                         { across = { [k] = { y0, y1, y0, y1, ... } }, down = { [k] = { x0, x1, ... } } }
--                         for the line at masks.GridLine(k), k 0 to 15, across the map (x fixed) or down it
local ffi = require('ffi');
local data = require('data.walkable');

local masks = {};
local SOFTEN = 2;      -- passes of a 3x3 average over the edge
local EDGE = 3;        -- pixels of the ground's rim, a map unit and a half
local GRID_FIRST, GRID_STEP, GRID_LINES = 16, 32, 16; -- the game's grid in map units: A1 is 16 to 48

function masks.GridLine(k)
    return GRID_FIRST + k * GRID_STEP;
end

local byZone = {};
for key, map in pairs(data.maps) do
    map.key = key;
    byZone[map.zone] = byZone[map.zone] or {};
    byZone[map.zone][map.floor] = map;
end

function masks.ForZone(zone)
    return byZone[zone];
end

-- Each pass averages a pixel with the eight round it
local function Soften(values, size)
    local copy = ffi.new('uint8_t[?]', size * size);
    for _ = 1, SOFTEN do
        ffi.copy(copy, values, size * size);
        for y = 1, size - 2 do
            local row = y * size;
            for x = 1, size - 2 do
                local at = row + x;
                local sum = copy[at - size - 1] + copy[at - size] + copy[at - size + 1]
                    + copy[at - 1] + copy[at] + copy[at + 1]
                    + copy[at + size - 1] + copy[at + size] + copy[at + size + 1];
                values[at] = math.floor(sum / 9 + 0.5);
            end
        end
    end
end

-- The ground's rim: what of the ground is within EDGE pixels of where it ends, each pass taking a
-- pixel off the ground wherever one of its four neighbours is off it
local function Rim(values, size)
    local inner = ffi.new('uint8_t[?]', size * size);
    local before = ffi.new('uint8_t[?]', size * size);
    ffi.copy(inner, values, size * size);
    for _ = 1, EDGE do
        ffi.copy(before, inner, size * size);
        for y = 0, size - 1 do
            for x = 0, size - 1 do
                local at = y * size + x;
                if before[at] ~= 0 and (x == 0 or y == 0 or x == size - 1 or y == size - 1
                    or before[at - 1] == 0 or before[at + 1] == 0 or before[at - size] == 0 or before[at + size] == 0) then
                    inner[at] = 0;
                end
            end
        end
    end
    for at = 0, size * size - 1 do
        inner[at] = (values[at] ~= 0 and inner[at] == 0) and 255 or 0;
    end
    return inner;
end

-- Where each grid line crosses the ground: the runs of ground along the mask's column (or row) under it
local function Stretches(values, size)
    local units = 512 / size;
    local grid = { across = {}, down = {} };
    for k = 0, GRID_LINES - 1 do
        local at = math.min(size - 1, math.floor(masks.GridLine(k) / units));
        local column, row = {}, {};
        local inColumn, inRow = nil, nil;
        for i = 0, size do
            local c = i < size and values[i * size + at] ~= 0;
            local r = i < size and values[at * size + i] ~= 0;
            if c and not inColumn then inColumn = i; elseif not c and inColumn then
                column[#column + 1], column[#column + 2], inColumn = inColumn * units, i * units, nil;
            end
            if r and not inRow then inRow = i; elseif not r and inRow then
                row[#row + 1], row[#row + 2], inRow = inRow * units, i * units, nil;
            end
        end
        grid.across[k], grid.down[k] = column, row;
    end
    return grid;
end

local made = {};

function masks.Get(map)
    if made[map.key] then return made[map.key]; end
    local size = data.width;
    local values = ffi.new('uint8_t[?]', size * size);
    local x0, y0, x1, y1 = size, size, -1, -1;
    for y, runs in pairs(map.rows) do
        local x, inside = 0, false;
        for length in runs:gmatch('%d+') do
            length = tonumber(length);
            if inside and length > 0 then
                ffi.fill(values + y * size + x, length, 255);
                x0, x1 = math.min(x0, x), math.max(x1, x + length - 1);
                y0, y1 = math.min(y0, y), math.max(y1, y);
            end
            x, inside = x + length, not inside;
        end
    end
    local edge = Rim(values, size);
    local grid = Stretches(values, size);
    Soften(values, size);
    local units = 512 / size;
    local mask = { width = size, height = size, values = values, edge = edge, grid = grid };
    if x1 >= 0 then
        mask.bounds = { x0 * units, y0 * units, (x1 + 1) * units, (y1 + 1) * units };
    end
    made[map.key] = mask;
    return mask;
end

return masks;
