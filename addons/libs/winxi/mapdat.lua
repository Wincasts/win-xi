-- The game's own map pictures, read from its files as a texture to draw.
--
--   mapdat.Root()                   the game's folder, or nil while Ashita cannot say
--   mapdat.Read(dat)                a map's file, by its place under the game's folder ('ROM/283/75.DAT'):
--                                   a buffer and its length, or nil and why not
--   mapdat.Header(buffer, length)   what the picture in a file is: { width, height, kind, bits, at },
--                                   or nil and why not
--   mapdat.Texture(device, buffer, length)   the picture as a texture, or nil and why not
--   mapdat.Load(dat)                the picture of a map's file as a texture and the handle imgui
--                                   draws it by, or nil and why not
--
-- A map is opened by its place under the game's folder, with fopen_s where there is one, as boussole
-- opens its maps and name its area lists: that is the opening pivot turns towards its overlays. With
-- XICombinedMaps among them the picture is the pack's, 2048 pixels across; without, the game's own.
-- Either lines up the same, as where a map is drawn is the client's table of maps, not its picture.
-- A few of the pack's pictures are files of its own, at places the game has none: those are there
-- only with the pack.
--
-- The file is a header of 0x41 bytes, then a bitmap's header of 44: its size (40), width, height,
-- planes, bits to a pixel, and so on to the last 4 bytes, the kind of picture. 'DXT1', '3' or '5'
-- (their bytes the other way round from a DDS's) is compressed blocks, 8 more bytes on; 10 is a
-- bitmap, rows from the bottom up, through a palette of 256 colours where there are 8 bits to a pixel.
local ffi = require('ffi');
local mapdat = {};

local HEADER    = 0x41;
local LARGEST   = 0x2000000; -- no map is near 32 megabytes: more is not one
local DXT1, DXT3, DXT5, BITMAP = 0x44585431, 0x44585433, 0x44585435, 10;
-- D3DFMT_DXT1/3/5 (their FOURCCs), D3DFMT_A8R8G8B8, D3DPOOL_MANAGED
local FORMATS   = { [DXT1] = 0x31545844, [DXT3] = 0x33545844, [DXT5] = 0x35545844 };
local ARGB, MANAGED = 21, 1;

pcall(ffi.cdef, [[
    int    fopen_s(void** file, const char* name, const char* mode);
    int    fclose(void* file);
    int    fseek(void* file, long offset, int origin);
    long   ftell(void* file);
    size_t fread(void* buffer, size_t size, size_t count, void* file);
]]);

----------------------------------------------------------------------------------------------------
-- The file
----------------------------------------------------------------------------------------------------
local root = nil;

-- The game's first file is always ROM\0\0.DAT: what Ashita says is its place, less that, is the folder
function mapdat.Root()
    if root == nil then
        local ok, path = pcall(function() return AshitaCore:GetResourceManager():GetFilePath(0); end);
        if ok and type(path) == 'string' then
            root = path:match('^(.-)[\\/][Rr][Oo][Mm][\\/]0[\\/]0%.[Dd][Aa][Tt]$');
        end
    end
    return root;
end

local function Open(path)
    local handle = ffi.new('void*[1]');
    local ok, failed = pcall(function() return ffi.C.fopen_s(handle, path, 'rb'); end);
    if ok and failed == 0 and handle[0] ~= nil then
        return handle[0];
    end
    return nil;
end

function mapdat.Read(dat)
    local folder = mapdat.Root();
    if folder == nil then
        return nil, 'Ashita did not say where the game is';
    end
    if type(dat) ~= 'string' or dat:find('..', 1, true) then
        return nil, 'not a map file';
    end
    local path = folder .. '\\' .. dat:gsub('/', '\\');
    local file = Open(path);
    if file == nil then
        return nil, 'could not open ' .. dat;
    end
    local buffer, length, why = nil, 0, 'could not read ' .. dat;
    if ffi.C.fseek(file, 0, 2) == 0 then
        length = tonumber(ffi.C.ftell(file));
        if length > HEADER and length <= LARGEST and ffi.C.fseek(file, 0, 0) == 0 then
            buffer = ffi.new('uint8_t[?]', length);
            if tonumber(ffi.C.fread(buffer, 1, length, file)) ~= length then
                buffer = nil;
            end
        end
    end
    ffi.C.fclose(file);
    if buffer == nil then
        return nil, why;
    end
    return buffer, length;
end

----------------------------------------------------------------------------------------------------
-- The picture in it
----------------------------------------------------------------------------------------------------
local function U32(bytes, at)
    return bytes[at] + bytes[at + 1] * 0x100 + bytes[at + 2] * 0x10000 + bytes[at + 3] * 0x1000000;
end

local function U16(bytes, at)
    return bytes[at] + bytes[at + 1] * 0x100;
end

function mapdat.Header(buffer, length)
    if length < HEADER + 44 then
        return nil, 'too short for a picture';
    end
    local bytes = ffi.cast('const uint8_t*', buffer);
    local at = HEADER;
    local size, width, height = U32(bytes, at), U32(bytes, at + 4), U32(bytes, at + 8);
    local bits, kind = U16(bytes, at + 14), U32(bytes, at + 40);
    if size ~= 40 or width < 1 or height < 1 or width > 8192 or height > 8192 then
        return nil, 'not a picture';
    end
    local header = { width = width, height = height, kind = kind, bits = bits };
    if FORMATS[kind] ~= nil then
        local block = kind == DXT1 and 8 or 16;
        header.at = at + 44 + 8;
        header.rows = math.ceil(height / 4);
        header.row = math.ceil(width / 4) * block;
    elseif kind == BITMAP and (bits == 8 or bits == 32) then
        header.at = at + 44;
        header.palette = bits == 8 and header.at or nil;
        header.pixels = header.at + (bits == 8 and 1024 or 0);
        header.rows = height;
        header.row = width * bits / 8;
    else
        return nil, ('a picture of a kind not read (%08X, %d bits)'):format(kind, bits);
    end
    local finish = (header.pixels or header.at) + header.rows * header.row;
    if finish > length then
        return nil, 'the picture is cut short';
    end
    return header;
end

-- Into a texture the device has made and locked: compressed blocks row by row as they are; a bitmap's
-- rows turned the right way up, each pixel its palette's colour where it has one
local function Fill(header, bytes, bits, pitch)
    if header.palette == nil and header.pixels == nil then
        for row = 0, header.rows - 1 do
            ffi.copy(bits + row * pitch, bytes + header.at + row * header.row, header.row);
        end
        return;
    end
    for row = 0, header.rows - 1 do
        local from = bytes + header.pixels + (header.rows - 1 - row) * header.row;
        local to = bits + row * pitch;
        local palette = header.palette and bytes + header.palette or nil;
        for x = 0, header.width - 1 do
            local colour = palette and palette + from[x] * 4 or from + x * 4;
            to[x * 4], to[x * 4 + 1], to[x * 4 + 2] = colour[0], colour[1], colour[2];
            to[x * 4 + 3] = (palette or colour[3] > 0) and 255 or 0;
        end
    end
end

function mapdat.Texture(device, buffer, length)
    local header, why = mapdat.Header(buffer, length);
    if header == nil then
        return nil, why;
    end
    local format = FORMATS[header.kind] or ARGB;
    local made, texture = device:CreateTexture(header.width, header.height, 1, 0, format, MANAGED);
    if made ~= 0 or texture == nil then
        return nil, ('the device made no texture (%08X)'):format(made % 0x100000000);
    end
    local locked, rect = texture:LockRect(0, nil, 0);
    if locked ~= 0 or rect == nil or rect.pBits == nil then
        texture:Release();
        return nil, 'the texture could not be locked';
    end
    local ok, failed = pcall(Fill, header, ffi.cast('const uint8_t*', buffer), ffi.cast('uint8_t*', rect.pBits), rect.Pitch);
    texture:UnlockRect(0);
    if not ok then
        texture:Release();
        return nil, tostring(failed);
    end
    return texture;
end

function mapdat.Load(dat)
    local d3d8 = require('d3d8');
    local device = d3d8.get_device();
    if device == nil then
        return nil, nil, 'no device yet';
    end
    local buffer, length = mapdat.Read(dat);
    if buffer == nil then
        return nil, nil, length;
    end
    local texture, why = mapdat.Texture(device, buffer, length);
    if texture == nil then
        return nil, nil, why;
    end
    texture = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture));
    return texture, tonumber(ffi.cast('uint32_t', texture));
end

return mapdat;
