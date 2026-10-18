-- The game's own map pictures, read from its files as a texture to draw.
--
--   mapdat.Root()                   the game's folder from resource paths or the loaded FFXiMain.dll
--   mapdat.Read(dat)                a map's file, by its place under the game's folder ('ROM/283/75.DAT'):
--                                   a buffer and its length, or nil and why not
--   mapdat.Header(buffer, length)   what the picture in a file is: { width, height, kind, bits, at },
--                                   or nil and why not
--   mapdat.Texture(device, buffer, length, mask)   the picture as a texture, or nil and why not
--   mapdat.Load(dat, mask)          the picture of a map's file as a texture and the handle imgui
--                                   draws it by, or nil and why not
--
-- A mask, where one is given, is how much of the picture shows at each place: { width, height,
-- values }, values width * height bytes, rows from the top, 0 none of it to 255 all of it, laid over
-- the whole picture whatever its size and read at the nearest of its own pixels. It multiplies the
-- picture's own alpha: a bitmap's, and a DXT3's four bits a pixel. A DXT1 or DXT5 picture cannot
-- take one.
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
local bit = require('bit');
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

-- Unique FFI names avoid conflicting with other addons' Windows declarations.
pcall(ffi.cdef, [[
    void* __stdcall winxi_mapdat_GetModuleHandleA(const char*) __asm__("GetModuleHandleA");
    unsigned long __stdcall winxi_mapdat_GetModuleFileNameA(void*, char*, unsigned long) __asm__("GetModuleFileNameA");
]]);

----------------------------------------------------------------------------------------------------
-- The file
----------------------------------------------------------------------------------------------------
local root = nil;

local function ModuleFolder()
    local ok, folder = pcall(function()
        local kernel = ffi.load('kernel32');
        local module = kernel.winxi_mapdat_GetModuleHandleA('FFXiMain.dll');
        -- Never pass a null handle: that would return the launcher, not the game's DLL.
        if module == nil or module == 0 then return nil; end
        local buffer = ffi.new('char[32768]');
        local length = tonumber(kernel.winxi_mapdat_GetModuleFileNameA(module, buffer, 32768));
        if length == 0 or length >= 32768 then return nil; end
        return ffi.string(buffer, length):match('^(.-)[\\/]%s*[Ff][Ff][Xx][Ii][Mm][Aa][Ii][Nn]%.[Dd][Ll][Ll]$');
    end);
    return ok and folder or nil;
end

-- Some Ashita clients return a relative/empty resource path. In those clients the
-- loaded FFXiMain.dll gives the actual game folder, independent of the launcher's folder.
function mapdat.Root()
    if root == nil then
        local ok, path = pcall(function() return AshitaCore:GetResourceManager():GetFilePath(0); end);
        if ok and type(path) == 'string' and (path:match('^%a:[\\/]') or path:match('^[\\/][\\/]')) then
            root = path:match('^(.-)[\\/][Rr][Oo][Mm]%d*[\\/]%d+[\\/]%d+%.[Dd][Aa][Tt]$');
        end
        root = root or ModuleFolder();
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
        return nil, 'could not locate the game folder from resource paths or FFXiMain.dll';
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

-- The mask's value for the picture's pixel (x, y)
local function Sample(mask, header, x, y)
    local mx = math.floor(x * mask.width / header.width);
    local my = math.floor(y * mask.height / header.height);
    return mask.values[my * mask.width + mx];
end

-- A DXT3 block's alpha, its first 8 bytes, four bits a pixel along each row, multiplied by the mask
local function MaskBlock(block, mask, header, left, top)
    for row = 0, 3 do
        local word = block[row * 2] + block[row * 2 + 1] * 256;
        local out = 0;
        local y = math.min(top + row, header.height - 1);
        for column = 0, 3 do
            local nibble = bit.band(bit.rshift(word, column * 4), 15);
            local x = math.min(left + column, header.width - 1);
            out = bit.bor(out, bit.lshift(math.floor(nibble * Sample(mask, header, x, y) / 255 + 0.5), column * 4));
        end
        block[row * 2], block[row * 2 + 1] = bit.band(out, 255), bit.rshift(out, 8);
    end
end

-- Into a texture the device has made and locked: compressed blocks row by row as they are; a bitmap's
-- rows turned the right way up, each pixel its palette's colour where it has one; then the mask
local function Fill(header, bytes, bits, pitch, mask)
    if header.palette == nil and header.pixels == nil then
        for row = 0, header.rows - 1 do
            ffi.copy(bits + row * pitch, bytes + header.at + row * header.row, header.row);
            if mask ~= nil then
                for block = 0, header.row / 16 - 1 do
                    MaskBlock(bits + row * pitch + block * 16, mask, header, block * 4, row * 4);
                end
            end
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
            local alpha = (palette or colour[3] > 0) and 255 or 0;
            if mask ~= nil and alpha > 0 then
                alpha = Sample(mask, header, x, row);
            end
            to[x * 4 + 3] = alpha;
        end
    end
end

function mapdat.Texture(device, buffer, length, mask)
    local header, why = mapdat.Header(buffer, length);
    if header == nil then
        return nil, why;
    end
    if mask ~= nil and (header.kind == DXT1 or header.kind == DXT5) then
        return nil, 'a DXT1 or DXT5 picture cannot take a mask';
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
    local ok, failed = pcall(Fill, header, ffi.cast('const uint8_t*', buffer), ffi.cast('uint8_t*', rect.pBits), rect.Pitch, mask);
    texture:UnlockRect(0);
    if not ok then
        texture:Release();
        return nil, tostring(failed);
    end
    return texture;
end

function mapdat.Load(dat, mask)
    local d3d8 = require('d3d8');
    local device = d3d8.get_device();
    if device == nil then
        return nil, nil, 'no device yet';
    end
    local buffer, length = mapdat.Read(dat);
    if buffer == nil then
        return nil, nil, length;
    end
    local texture, why = mapdat.Texture(device, buffer, length, mask);
    if texture == nil then
        return nil, nil, why;
    end
    texture = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture));
    return texture, tonumber(ffi.cast('uint32_t', texture));
end

return mapdat;
