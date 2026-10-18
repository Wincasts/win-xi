-- The walkable ground of each map, from data/walkable.lua (tools/trace_walkable_maps.py), as a mask
-- winxi.mapdat lays over the map's picture: 0 off the ground, 255 on it, the edge softened over a
-- few pixels so it does not show the mask's steps.
--
--   masks.ForZone(zone)   the maps of a zone with ground traced, by floor: { [floor] = map }
--   masks.Get(map)        { width, height, values, bounds = { x0, y0, x1, y1 } in map units }
local ffi = require('ffi');
local data = require('data.walkable');

local masks = {};
local SOFTEN = 2;      -- passes of a 3x3 average over the edge

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
    Soften(values, size);
    local units = 512 / size;
    local mask = { width = size, height = size, values = values };
    if x1 >= 0 then
        mask.bounds = { x0 * units, y0 * units, (x1 + 1) * units, (y1 + 1) * units };
    end
    made[map.key] = mask;
    return mask;
end

return masks;
