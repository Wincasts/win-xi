-- Game status artwork must be read through Pivot, not Ashita's separately cached resources.
-- mapdat.Read uses the fopen_s hook (Pivot's redirect_fopens must be enabled).
-- Explicit custom icon sets are selected by statusicons, not by this reader.
local ffi = require('ffi');
local mapdat = require('winxi.mapdat');
local statusdat = {};
local loaded, buffer, length, stride = false, nil, nil, nil;
local icons = {};

local function u16(p, at) return tonumber(p[at]) + tonumber(p[at + 1]) * 256; end
local function u32(p, at) return u16(p, at) + u16(p, at + 2) * 65536; end
local function put32(p, at, value)
    for i = 0, 3 do p[at + i] = value % 256; value = math.floor(value / 256); end
end

-- A status record contains description/flags, then an image at 0x284. Current
-- records are 0x1800 bytes; older clients used 0xC00 with indexed artwork.
-- Produce a normal BMP for the same D3DX decoders used by every statusicons path.
function statusdat.Decode(data, size, index, recordSize)
    if type(index) ~= 'number' or index < 0 or index % 1 ~= 0 then return nil; end
    recordSize = recordSize or 0x1800;
    if recordSize ~= 0x1800 and recordSize ~= 0xC00 then return nil; end
    local base = index * recordSize;
    if data == nil or base + recordSize > size then return nil; end
    local p = ffi.cast('const uint8_t*', data) + base;
    local imageSize = u32(p, 0x280);
    if imageSize < 57 or imageSize > recordSize - 0x284 then return nil; end
    local image = p + 0x284;
    if image[0] ~= 0x91 and image[0] ~= 0xB1 then return nil; end
    local dib = image + 17;
    local width, height, bits = u32(dib, 4), u32(dib, 8), u16(dib, 14);
    if u32(dib, 0) ~= 40 or width ~= 32 or height ~= 32 or u16(dib, 12) ~= 1
        or u32(dib, 16) ~= 0 or (bits ~= 8 and bits ~= 24 and bits ~= 32) then return nil; end
    local palette = bits == 8 and 1024 or 0;
    local pixels = width * height * bits / 8;
    local extra = image[0] == 0xB1 and 4 or 0;
    if 57 + extra + palette + pixels > imageSize then return nil; end
    local bmpSize = 54 + palette + pixels;
    local bmp = ffi.new('uint8_t[?]', bmpSize);
    bmp[0], bmp[1] = 0x42, 0x4D;
    put32(bmp, 2, bmpSize);
    put32(bmp, 10, 54 + palette);
    ffi.copy(bmp + 14, dib, 40);
    put32(bmp, 34, pixels);
    if bits == 8 then put32(bmp, 46, 256); end
    ffi.copy(bmp + 54, dib + 40 + extra, palette + pixels);
    -- DAT alpha uses 0x80 for fully opaque; BMP/D3DX uses 0xFF.
    if bits == 32 or bits == 8 then
        local last = bits == 8 and 54 + palette or bmpSize;
        for at = 57, last - 1, 4 do bmp[at] = math.min(255, tonumber(bmp[at]) * 2); end
    end
    return { Bitmap = bmp, ImageSize = bmpSize };
end

local function Load()
    loaded = true;
    -- File id 87 is the English status table. Honour the installed client's
    -- FTABLE mapping rather than treating ROM/119/57.DAT as authoritative.
    local path = 'ROM/119/57.DAT';
    local ok, mapped = pcall(function() return AshitaCore:GetResourceManager():GetFilePath(87); end);
    if ok and type(mapped) == 'string' then
        path = mapped:match('([Rr][Oo][Mm]%d*[\\/]%d+[\\/]%d+%.[Dd][Aa][Tt])$') or path;
    end
    buffer, length = mapdat.Read(path);
    if buffer == nil then return; end
    for _, candidate in ipairs({ 0x1800, 0xC00 }) do
        if length % candidate == 0 and statusdat.Decode(buffer, length, 0, candidate)
            and statusdat.Decode(buffer, length, 1, candidate) then
            stride = candidate;
            return;
        end
    end
    buffer, length = nil, nil;
end

function statusdat.Get(index)
    if type(index) ~= 'number' or index < 0 or index % 1 ~= 0 then return nil; end
    if not loaded then pcall(Load); end
    if stride == nil then return nil; end
    if icons[index] == nil then
        icons[index] = statusdat.Decode(buffer, length, index, stride) or false;
    end
    return icons[index] or nil;
end

return statusdat;
