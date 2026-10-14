-- Maps for mark: which of a zone's maps a place is on, where on it, and the square of its grid.
--
-- data/maps.lua (written by tools/build_mark_data.py) lists each zone's maps, a floor to each, with
-- the map's place in the client's own table of maps and its picture. The scale and offsets that turn
-- a place in the world into a place on the map are read from that table in the client's memory, as
-- zoneinfo and boussole read them; which floor a place is on is asked of the client, which can only
-- say for the zone it has loaded. Native-resolution pictures exported by tools/build_mark_maps.py
-- live in assets\maps; zoneinfo's 512-pixel previews (addons\zoneinfo\assets\maps\all) are a fallback.
--
--   maps.Floors(zone)                  the zone's maps, each { floor, index, image }, or nil
--   maps.FloorAt(zone, here, x, y, z)  the map a place is on: here is the zone the player is in
--   maps.Entry(zone, floor)            a map's { scale, x, y }, or nil while it cannot be read
--   maps.ToMap(entry, x, z)            a place in the world as a place on the map, 0 to 512 each way
--   maps.ToWorld(entry, px, py)        and back
--   maps.Square(px, py)                the grid square of a place on the map: 'H-7'
--   maps.Texture(floor)                the map's picture as a texture handle, or nil
local maps = {};

maps.Size = 512; -- a map is this many units across, whatever size its picture is drawn at

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

----------------------------------------------------------------------------------------------------
-- The client's table of maps: fourteen bytes to a map, the zone and floor it is of, its scale and
-- its offsets
----------------------------------------------------------------------------------------------------
local TABLE_SIGNATURE = '8A0D????????5333C05684C95774??8A5424188B7424148B7C2410B9';
local ENTRY_SIZE = 0x0E;

local tablePointer = 0;
local entries = {};   -- place in the table -> { scale, x, y }
local retryAt = 0;    -- a read that failed is not tried again until then

local function Signed(value, bits)
    local sign = 2 ^ (bits - 1);
    return value >= sign and value - 2 ^ bits or value;
end

local function ReadEntry(zone, floor)
    local memory = ashita.memory;
    if tablePointer == 0 then
        local address = memory.find('FFXiMain.dll', 0, TABLE_SIGNATURE, 0, 0);
        if address == nil or address == 0 then
            return nil;
        end
        tablePointer = memory.read_uint32(address + 0x1C) or 0;
        if tablePointer == 0 then
            return nil;
        end
    end
    local base = tablePointer + floor.index * ENTRY_SIZE;
    -- the table is the client's, and may not be the one the data was made against
    if memory.read_uint16(base) ~= zone or memory.read_uint8(base + 2) ~= floor.floor then
        return nil;
    end
    local scale = Signed(memory.read_uint8(base + 5), 8);
    if scale == 0 then
        return nil;
    end
    return { scale = math.abs(scale) / 5.0, x = Signed(memory.read_uint16(base + 10), 16), y = Signed(memory.read_uint16(base + 12), 16) };
end

function maps.Entry(zone, floor)
    local entry = entries[floor.index];
    if entry ~= nil then
        return entry;
    end
    if os.clock() < retryAt then
        return nil;
    end
    local ok, found = pcall(ReadEntry, zone, floor);
    if ok and found ~= nil then
        entries[floor.index] = found;
        return found;
    end
    retryAt = os.clock() + 5;
    return nil;
end

-- East is more x and to the right; north is more z and up the map
function maps.ToMap(entry, x, z)
    return x * entry.scale - entry.x, -z * entry.scale - entry.y;
end

function maps.ToWorld(entry, px, py)
    return (px + entry.x) / entry.scale, -(py + entry.y) / entry.scale;
end

-- The grid is sixteen squares each way, thirty-two units to a square, set in by half a square
function maps.Square(px, py)
    local column = math.max(0, math.min(25, math.floor((px - 16) / 32)));
    local row = math.floor((py - 16) / 32) + 1;
    return ('%s-%d'):format(string.char(65 + column), row);
end

----------------------------------------------------------------------------------------------------
-- Which floor a place is on: the client's own function, for the zone it has loaded
----------------------------------------------------------------------------------------------------
local floorFunction, floorPointer = nil, nil;
local floorRetryAt = 0;

-- The id of the floor a place of the loaded zone is on, or nil. A function of its own so that it can
-- be stood in for where there is no client.
function maps.ClientFloor(x, y, z)
    local ok, floor = pcall(function()
        local memory = ashita.memory;
        if floorFunction == nil then
            if os.clock() < floorRetryAt then
                return nil;
            end
            floorRetryAt = os.clock() + 5;
            local ffi = require('ffi');
            local fn = memory.find('FFXiMain.dll', 0, '8B542408568D4424108BF18B4C2410508B44240C', 0, 0);
            local pointer = memory.find('FFXiMain.dll', 0, '8B7424148B4424108B7C240C8B0D', 0x0E, 0);
            if fn == nil or fn == 0 or pointer == nil or pointer == 0 then
                return nil;
            end
            floorFunction = ffi.cast('int32_t (__thiscall *)(void*, float, float, float)', fn);
            floorPointer = pointer;
        end
        local holder = memory.read_uint32(floorPointer);
        local object = holder ~= nil and holder ~= 0 and memory.read_uint32(holder) or 0;
        if object == nil or object == 0 then
            return nil;
        end
        return tonumber(floorFunction(require('ffi').cast('void*', object), x, y, z));
    end);
    return ok and floor or nil;
end

-- The map a place is on. A zone of one map has no need to ask; a zone of several can be asked about
-- only while the player is in it. x and z are the level directions and y the height, as the server
-- has them.
function maps.FloorAt(zone, here, x, y, z)
    local floors = maps.Floors(zone);
    if floors == nil then
        return nil;
    end
    if #floors == 1 then
        return floors[1];
    end
    if zone ~= here then
        return nil;
    end
    local id = maps.ClientFloor(x, y, z);
    for _, floor in ipairs(floors) do
        if floor.floor == id then
            return floor;
        end
    end
    return nil;
end

----------------------------------------------------------------------------------------------------
-- The pictures: one kept at a time
----------------------------------------------------------------------------------------------------
local held = { image = nil, texture = nil, handle = nil };

local function Load(image)
    local own = ('%sassets\\maps\\%s'):format(addon.path, image);
    local shared = ('%s\\addons\\zoneinfo\\assets\\maps\\all\\%s'):format(AshitaCore:GetInstallPath(), image);
    local path = ashita.fs.exists(own) and own or (ashita.fs.exists(shared) and shared or nil);
    if path == nil then
        return nil;
    end
    local ffi, d3d = require('ffi'), require('d3d8');
    local device = d3d.get_device();
    if device == nil then
        return nil;
    end
    local pointer = ffi.new('IDirect3DTexture8*[1]');
    if ffi.C.D3DXCreateTextureFromFileA(device, path, pointer) ~= ffi.C.S_OK then
        return nil;
    end
    local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]));
    return texture, tonumber(ffi.cast('uint32_t', texture));
end

function maps.Texture(floor)
    if held.image ~= floor.image then
        held.image, held.texture, held.handle = floor.image, nil, nil;
        local ok, texture, handle = pcall(Load, floor.image);
        if ok and texture ~= nil then
            held.texture, held.handle = texture, handle;
        end
    end
    return held.handle;
end

return maps;
