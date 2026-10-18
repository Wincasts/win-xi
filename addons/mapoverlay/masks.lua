-- The walkable ground of each map, from data/walkable.lua (tools/trace_walkable_maps.py), as a mask:
-- 0 off the ground, 255 on it, the edge softened over a few pixels so it does not show the mask's
-- steps. winxi.mapdat lays it over the map's picture; flat.lua paints it.
--
--   masks.ForZone(zone)   the maps of a zone with ground traced, by floor: { [floor] = map }
--   masks.Get(map)        { width, height, values, edge, bounds = { x0, y0, x1, y1 } in map units }:
--                         edge 255 on the ground's rim, EDGE pixels in from where it ends, 0 elsewhere
local ffi = require('ffi');
local data = require('data.walkable');

local masks = {};
local SOFTEN = 2;      -- passes of a 3x3 average over the edge
local EDGE = 3;        -- pixels of the ground's rim, a map unit and a half

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
    Soften(values, size);
    local units = 512 / size;
    local mask = { width = size, height = size, values = values, edge = edge };
    if x1 >= 0 then
        mask.bounds = { x0 * units, y0 * units, (x1 + 1) * units, (y1 + 1) * units };
    end
    made[map.key] = mask;
    return mask;
end

return masks;
