-- The names the game itself has for an area's spawn slots, read from the game's own files.
--
--   names.Read(zone)          { [index] = name } for every slot of the area the game has a name for,
--                             or nil and why not
--   names.Parse(bytes, zone)  the same, of a file already read
--
-- Each area has a file listing its monsters and people: one record of 32 bytes for each, the name in
-- the first 28 and the server id, 0x01000000 + the area * 0x1000 + the index, in the last 4. It is
-- where the game gets the name it writes over a monster's head, so every client of one server has the
-- same list whatever addon data it has, and no server need be asked for its own.
--
-- The list is of every slot the game knows, those a server leaves empty among them, and of the
-- area's people as well as its monsters.
--
-- Ashita is asked where the file is. It is opened with fopen_s where there is one, as boussole opens
-- its maps: that is the opening pivot turns towards its overlays, and a server that keeps its own
-- lists there (Phoenix's EraDATs) has other names in them than the game's own files.
local ffi = require('ffi');
local names = {};

local RECORD, NAME = 32, 28;
local LARGEST      = 0x100000; -- no area's list is near a megabyte: more is not one

pcall(ffi.cdef, [[
    int    fopen_s(void** file, const char* name, const char* mode);
    int    fclose(void* file);
    int    fseek(void* file, long offset, int origin);
    long   ftell(void* file);
    size_t fread(void* buffer, size_t size, size_t count, void* file);
]]);

-- The number of the area's file among the game's: those past 255 are kept elsewhere
local function fileId(zone)
    if (zone < 256) then
        return 6720 + zone;
    end
    return 86491 + (zone - 256);
end

local function throughGame(path)
    local handle = ffi.new('void*[1]');
    if (ffi.C.fopen_s(handle, path, 'rb') ~= 0 or handle[0] == nil) then
        return nil;
    end
    local file, bytes = handle[0], nil;
    if (ffi.C.fseek(file, 0, 2) == 0) then
        local size = ffi.C.ftell(file);
        if (size > 0 and size <= LARGEST and ffi.C.fseek(file, 0, 0) == 0) then
            local buffer = ffi.new('uint8_t[?]', size);
            if (ffi.C.fread(buffer, 1, size, file) == size) then
                bytes = ffi.string(buffer, size);
            end
        end
    end
    ffi.C.fclose(file);
    return bytes;
end

local function slurp(path)
    local ok, bytes = pcall(throughGame, path);
    if (ok and bytes ~= nil) then
        return bytes;
    end
    local file = io.open(path, 'rb');
    if (file == nil) then
        return nil;
    end
    bytes = file:read('*a');
    file:close();
    return bytes;
end

function names.Parse(bytes, zone)
    local roster, count = {}, 0;
    for at = 1, #bytes - RECORD + 1, RECORD do
        local a, b, c, d = bytes:byte(at + NAME, at + NAME + 3);
        local id = a + b * 0x100 + c * 0x10000 + d * 0x1000000;
        local index = id % 0x1000;
        if (index > 0 and math.floor(id / 0x1000) % 0x1000 == zone) then
            local name = bytes:sub(at, at + NAME - 1):match('^[^%z]*');
            if (name ~= '') then
                roster[index] = name;
                count = count + 1;
            end
        end
    end
    if (count == 0) then
        return nil, 'the file has none of this area\'s names';
    end
    return roster;
end

function names.Read(zone)
    if (type(zone) ~= 'number' or zone <= 0) then
        return nil, 'the area is not known';
    end
    local ok, path = pcall(function ()
        return AshitaCore:GetResourceManager():GetFilePath(fileId(zone));
    end);
    if (not ok or type(path) ~= 'string' or path == '') then
        return nil, 'Ashita did not say where the file is';
    end
    local bytes = slurp(path);
    if (bytes == nil or #bytes > LARGEST) then
        return nil, ('%s could not be read'):format(path);
    end
    return names.Parse(bytes, zone);
end

return names;
