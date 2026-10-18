-- Where the player is on the map: the client's own table of maps, for how a map lies over the zone,
-- and the client's floor for where the player stands, as zone's map_position reads them (Boussole's
-- way). Each read is checked and refuses rather than guessing.
--
--   position.Transform(map)    { scale, offsetX, offsetY } for a map of walkable.lua, or nil and why
--   position.Floor(player)     the client's floor at the player's place, or nil and why
--   position.Player()          { x, y, z, heading }, X and Y across the ground, Z height, or nil
--   position.ToMap(t, player)  the player's place in 512-reference map units
local position = {};

local MAP_TABLE = '8A0D????????5333C05684C95774??8A5424188B7424148B7C2410B9';
local FLOOR_FUNCTION = '8B542408568D4424108BF18B4C2410508B44240C';
local FLOOR_POINTER = '8B7424148B4424108B7C240C8B0D';
local ENTRY = 0x0E;

local function Finite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge;
end

local function Signed(value, size)
    local sign = 2 ^ (size - 1);
    return value >= sign and value - 2 ^ size or value;
end

local function Valid(scale, x, y)
    return Finite(scale) and scale ~= 0 and math.abs(scale) <= 128
        and Finite(x) and math.abs(x) <= 32768 and Finite(y) and math.abs(y) <= 32768;
end

local tablePointer = 0;
local transforms = {};  -- map key -> its transform, read once

function position.Transform(map)
    if transforms[map.key] then return transforms[map.key]; end
    local memory = ashita.memory;
    local ok, found, why = pcall(function()
        if tablePointer == 0 then
            local at = memory.find('FFXiMain.dll', 0, MAP_TABLE, 0, 0);
            if not at or at == 0 then return nil, 'the map table\'s signature was not found'; end
            tablePointer = memory.read_uint32(at + 0x1C) or 0;
            if tablePointer == 0 then return nil, 'the map table\'s pointer is null'; end
        end
        local base = tablePointer + map.index * ENTRY;
        if memory.read_uint16(base) ~= map.zone or memory.read_uint8(base + 2) ~= map.floor then
            return nil, 'the client\'s map entry is not this zone and floor';
        end
        local scale = Signed(memory.read_uint8(base + 5), 8);
        local x, y = Signed(memory.read_uint16(base + 10), 16), Signed(memory.read_uint16(base + 12), 16);
        if not Valid(scale, x, y) then return nil, 'the client\'s map entry has no sense in it'; end
        return { scale = scale, offsetX = x, offsetY = y };
    end);
    if not ok then return nil, 'the map table could not be read'; end
    if found then transforms[map.key] = found; end
    return found, why;
end

local floorFunction, floorPointer, floorRetry = nil, nil, 0;

function position.Floor(player)
    local ok, floor, why = pcall(function()
        if floorFunction == nil then
            if os.clock() < floorRetry then return nil, 'the floor is not known yet'; end
            floorRetry = os.clock() + 5;
            local fn = ashita.memory.find('FFXiMain.dll', 0, FLOOR_FUNCTION, 0, 0);
            local pointer = ashita.memory.find('FFXiMain.dll', 0, FLOOR_POINTER, 0x0E, 0);
            if not fn or fn == 0 or not pointer or pointer == 0 then return nil, 'the floor\'s signatures were not found'; end
            local ffi = require('ffi');
            floorFunction = ffi.cast('int32_t (__thiscall *)(void*, float, float, float)', fn);
            floorPointer = pointer;
        end
        local pointer = ashita.memory.read_uint32(floorPointer);
        if not pointer or pointer == 0 then return nil, 'the floor\'s object is not there'; end
        local object = ashita.memory.read_uint32(pointer);
        if not object or object == 0 then return nil, 'the floor\'s object is null'; end
        return tonumber(floorFunction(require('ffi').cast('void*', object), player.x, player.z, player.y));
    end);
    if not ok then return nil, 'the floor could not be read'; end
    return floor, why;
end

function position.Player()
    local ok, x, y, z, heading = pcall(function()
        local entity = GetPlayerEntity();
        if not entity or not entity.Movement or not entity.Movement.LocalPosition then return nil; end
        local p = entity.Movement.LocalPosition;
        return p.X, p.Y, p.Z, entity.Heading or 0;
    end);
    if not ok or not Finite(x) or not Finite(y) or not Finite(z) then return nil; end
    return { x = x, y = y, z = z, heading = Finite(heading) and heading or 0 };
end

function position.ToMap(t, player)
    local scale = math.abs(t.scale) / 5;
    return player.x * scale - t.offsetX, -player.y * scale - t.offsetY;
end

return position;
