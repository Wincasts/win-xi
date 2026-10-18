-- The zone's maps: which there are, how each lies over the zone, which one a place is on, and their
-- pictures.
--
-- data/maps.lua (written by tools/build_atlas_maps.py) lists each zone's maps, a floor to each, with
-- the map's place in the client's own table of maps and its picture. The scale and offsets that turn
-- a place in the zone into a place on the map are read from that table in the client's memory, as
-- zone, mark and boussole read them; which floor a place is on is asked of the client, which can only
-- say for the zone it has loaded. The pictures are the game's own files, read by winxi.mapdat:
-- XICombinedMaps' where pivot has it, the game's own where not.
--
--   maps.Floors(zone)              the zone's maps, each { floor, index, dat }, or nil
--   maps.Floor(zone, floorId)      one of them by its floor's id, or nil
--   maps.Entry(map, zone)          how a map of the zone lies over it, { scale, x, y }, or nil and why
--   maps.ClientFloor(x, y, z)      the client's floor for a place of the loaded zone (y across the
--                                  ground, z its height), or nil and why
--   maps.At(zone, x, y, z)         the map of the loaded zone a place is on, or nil and why
--   maps.ToMap(entry, x, y)        a place on the ground as a place on the map, 0 to 512 each way
--   maps.ToWorld(entry, mx, my)    and back
--   maps.Square(mx, my)            the game's grid square of a place on the map: 'H-7'
--   maps.Texture(map)              the map's picture as a handle imgui draws, or nil and why
local mapdat = require('winxi.mapdat');
local maps = {};

maps.Size = 512; -- a map is this many units across, whatever size its picture is

local catalog = nil;

local function Catalog()
    if catalog == nil then
        local path = ('%sdata/maps.lua'):format(addon.path);
        local chunk = ashita.fs.exists(path) and loadfile(path) or nil;
        local ok, result = pcall(chunk or error);
        catalog = ok and type(result) == 'table' and result or {};
    end
    return catalog;
end

function maps.Floors(zone)
    return Catalog()[zone];
end

function maps.Floor(zone, floorId)
    for _, map in ipairs(Catalog()[zone] or {}) do
        if map.floor == floorId then
            return map;
        end
    end
    return nil;
end

----------------------------------------------------------------------------------------------------
-- The client's table of maps: fourteen bytes to a map, the zone and floor it is of, its scale at
-- byte 5 and its offsets at 10 and 12
----------------------------------------------------------------------------------------------------
local TABLE_SIGNATURE = '8A0D????????5333C05684C95774??8A5424188B7424148B7C2410B9';
local ENTRY_SIZE = 0x0E;
local RETRY = 5; -- seconds before a read that failed is tried again

local tablePointer = 0;
local entries = {}; -- place in the table -> { scale, x, y }
local retryAt = 0;

local function Signed(value, bits)
    local sign = 2 ^ (bits - 1);
    return value >= sign and value - 2 ^ bits or value;
end

local function ReadEntry(zone, map)
    local memory = ashita.memory;
    if tablePointer == 0 then
        local address = memory.find('FFXiMain.dll', 0, TABLE_SIGNATURE, 0, 0);
        if address == nil or address == 0 then
            return nil, 'the map table\'s signature was not found';
        end
        tablePointer = memory.read_uint32(address + 0x1C) or 0;
        if tablePointer == 0 then
            return nil, 'the map table\'s pointer is null';
        end
    end
    local base = tablePointer + map.index * ENTRY_SIZE;
    -- the table is the client's, and may not be the one the data was made against
    if memory.read_uint16(base) ~= zone or memory.read_uint8(base + 2) ~= map.floor then
        return nil, 'the client\'s map entry is not this zone and floor';
    end
    local scale = Signed(memory.read_uint8(base + 5), 8);
    local x, y = Signed(memory.read_uint16(base + 10), 16), Signed(memory.read_uint16(base + 12), 16);
    if scale == 0 or math.abs(x) > 32768 or math.abs(y) > 32768 then
        return nil, 'the client\'s map entry has no sense in it';
    end
    return { scale = math.abs(scale) / 5.0, x = x, y = y };
end

function maps.Entry(map, zone)
    local entry = entries[map.index];
    if entry ~= nil then
        return entry;
    end
    if os.clock() < retryAt then
        return nil, 'the map table could not be read; trying again shortly';
    end
    local ok, found, why = pcall(ReadEntry, zone, map);
    if ok and found ~= nil then
        entries[map.index] = found;
        return found;
    end
    retryAt = os.clock() + RETRY;
    return nil, ok and why or 'the map table could not be read';
end

-- East is more x and to the right; north is more y and up the map
function maps.ToMap(entry, x, y)
    return x * entry.scale - entry.x, -y * entry.scale - entry.y;
end

function maps.ToWorld(entry, mx, my)
    return (mx + entry.x) / entry.scale, -(my + entry.y) / entry.scale;
end

-- The grid is fifteen squares each way, thirty-two units to a square, set in by half a square
function maps.Square(mx, my)
    local column = math.max(0, math.min(25, math.floor((mx - 16) / 32)));
    local row = math.floor((my - 16) / 32) + 1;
    return ('%s-%d'):format(string.char(65 + column), row);
end

----------------------------------------------------------------------------------------------------
-- Which floor a place is on: the client's own function, for the zone it has loaded
----------------------------------------------------------------------------------------------------
local FLOOR_FUNCTION = '8B542408568D4424108BF18B4C2410508B44240C';
local FLOOR_POINTER = '8B7424148B4424108B7C240C8B0D';

local floorFunction, floorPointer, floorRetryAt = nil, nil, 0;

function maps.ClientFloor(x, y, z)
    local ok, floor, why = pcall(function()
        local memory = ashita.memory;
        if floorFunction == nil then
            if os.clock() < floorRetryAt then
                return nil, 'the floor is not known yet';
            end
            floorRetryAt = os.clock() + RETRY;
            local fn = memory.find('FFXiMain.dll', 0, FLOOR_FUNCTION, 0, 0);
            local pointer = memory.find('FFXiMain.dll', 0, FLOOR_POINTER, 0x0E, 0);
            if fn == nil or fn == 0 or pointer == nil or pointer == 0 then
                return nil, 'the floor\'s signatures were not found';
            end
            floorFunction = require('ffi').cast('int32_t (__thiscall *)(void*, float, float, float)', fn);
            floorPointer = pointer;
        end
        local holder = memory.read_uint32(floorPointer);
        local object = holder ~= nil and holder ~= 0 and memory.read_uint32(holder) or 0;
        if object == nil or object == 0 then
            return nil, 'the floor\'s object is not there';
        end
        -- the client's order: across, height, then the other way across
        return tonumber(floorFunction(require('ffi').cast('void*', object), x, z, y));
    end);
    if not ok then
        return nil, 'the floor could not be read';
    end
    return floor, why;
end

-- The map a place of the loaded zone is on. A zone of one map has no need to ask.
function maps.At(zone, x, y, z)
    local floors = maps.Floors(zone);
    if floors == nil then
        return nil, 'no map is known for this zone';
    end
    if #floors == 1 then
        return floors[1];
    end
    local id, why = maps.ClientFloor(x, y, z);
    if id == nil then
        return nil, why;
    end
    local map = maps.Floor(zone, id);
    if map == nil then
        return nil, ('floor %d has no map'):format(id);
    end
    return map;
end

----------------------------------------------------------------------------------------------------
-- The pictures: a few kept, for going back to a floor without reading it again
----------------------------------------------------------------------------------------------------
local KEEP = 4;
local held = {}; -- dat -> { texture, handle, why, used, retryAt }
local clock = 0;

function maps.Texture(map)
    clock = clock + 1;
    local kept = held[map.dat];
    if kept ~= nil and (kept.handle ~= nil or os.clock() < kept.retryAt) then
        kept.used = clock;
        return kept.handle, kept.why;
    end
    if kept == nil then
        local count, oldest = 0, nil;
        for dat, other in pairs(held) do
            count = count + 1;
            if oldest == nil or other.used < held[oldest].used then oldest = dat; end
        end
        if count >= KEEP then held[oldest] = nil; end
    end
    local ok, texture, handle, why = pcall(mapdat.Load, map.dat);
    if not ok then
        texture, handle, why = nil, nil, 'the picture could not be read';
    end
    if why == 'no device yet' then
        return nil, why;
    end
    -- a file not there is not there: not tried again for a while
    held[map.dat] = { texture = texture, handle = handle, why = handle == nil and (why or 'no picture') or nil,
        used = clock, retryAt = os.clock() + RETRY };
    return handle, held[map.dat].why;
end

return maps;
