-- Whether something solid lies between two points in the world, asked of the game itself.
--
--   sight.Find()                          once, on loading: where the game's own test is
--   sight.Blocked(ax, ay, az, bx, by, bz) whether the way from a to b is blocked
--   sight.Done()                          each frame, after the last of them
--
-- The game keeps its camera out of walls by asking whether the line from the character to where the
-- camera would be runs into the map: the walls and the ground, and things that stand in the way as
-- they do, a closed door among them. Characters do not. This asks the same of the same function.
--
-- The function leaves a note of what it last ran into, for whoever asked. What was there before the
-- first question of a frame is put back by sight.Done, so that the game finds its own note and not
-- one of these.
local ffi = require('ffi');

local sight = {};

-- The camera's own call: the map's collision is fetched, three points are pushed, the test is called
local CALL_PATTERN  = '8B0D????????8D94248C0000008D6F44528D4424605550E8????????84C0';
local MAP_OFFSET    = 2;  -- where the map's collision is kept
local CALL_OFFSET   = 23; -- the call, whose four bytes after the first say how far off the function is

-- What the function writes, from the object it is called on: where its note of the last thing run
-- into is, and what it noted of it. The function itself works 0x178 into that object.
local WORKS_AT      = 0x178;
local NOTE_POINTER  = WORKS_AT + 0x1807C;
local NOTE          = WORKS_AT + 0x34148;
local NOTE_SIZE     = 0x18;

local mapPointer = 0;   -- where the game keeps its pointer to the map's collision
local test       = nil; -- the game's function

local from, to, hit = ffi.new('float[3]'), ffi.new('float[3]'), ffi.new('float[3]');

local kept        = ffi.new('uint8_t[?]', NOTE_SIZE);
local keptPointer = 0;
local keptOf      = 0; -- the object the note was kept from this frame, or 0 if no question has been asked

function sight.Find()
    local found = ashita.memory.find('FFXiMain.dll', 0, CALL_PATTERN, 0, 0);
    if (found == 0) then
        return false;
    end

    mapPointer = ashita.memory.read_uint32(found + MAP_OFFSET);
    local call = found + CALL_OFFSET;
    local target = call + 5 + ashita.memory.read_int32(call + 1);

    test = ffi.cast('bool (__thiscall*)(void*, const float*, const float*, float*)', target);
    return mapPointer ~= 0;
end

function sight.Found()
    return test ~= nil;
end

function sight.Blocked(ax, ay, az, bx, by, bz)
    if (test == nil) then
        return false;
    end

    local map = ashita.memory.read_uint32(mapPointer);
    if (map == 0) then
        return false;
    end

    if (keptOf ~= map) then
        sight.Done();
        keptPointer = ashita.memory.read_uint32(map + NOTE_POINTER);
        ffi.copy(kept, ffi.cast('const uint8_t*', map + NOTE), NOTE_SIZE);
        keptOf = map;
    end

    from[0], from[1], from[2] = ax, ay, az;
    to[0], to[1], to[2] = bx, by, bz;
    return test(ffi.cast('void*', map), from, to, hit);
end

function sight.Done()
    if (keptOf ~= 0) then
        ashita.memory.write_uint32(keptOf + NOTE_POINTER, keptPointer);
        ffi.copy(ffi.cast('uint8_t*', keptOf + NOTE), kept, NOTE_SIZE);
        keptOf = 0;
    end
end

return sight;
