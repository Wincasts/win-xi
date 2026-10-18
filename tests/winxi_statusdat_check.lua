-- Synthetic DATs: no copyrighted artwork and no Windows runtime required.
package.path = 'addons/libs/?.lua;' .. package.path
local ffi = require('ffi')
local reads, asked = 0
local data = ffi.new('uint8_t[?]', 0x3000)
local function put(p, at, value, count)
    for i = 0, (count or 4) - 1 do p[at + i] = value % 256; value = math.floor(value / 256) end
end
local function record(buffer, base, bits, marker)
    local palette = bits == 8 and 1024 or 0
    local imageSize = 57 + palette + 32 * 32 * bits / 8
    put(buffer, base + 0x280, imageSize)
    buffer[base + 0x284] = 0x91
    local dib = base + 0x295
    put(buffer, dib, 40); put(buffer, dib + 4, 32); put(buffer, dib + 8, 32)
    put(buffer, dib + 12, 1, 2); put(buffer, dib + 14, bits, 2)
    buffer[dib + 40] = marker
    buffer[dib + 43] = 0x80
end
record(data, 0, 32, 11)
record(data, 0x1800, 32, 22)
package.loaded['winxi.mapdat'] = { Read = function(path)
    reads, asked = reads + 1, path
    return data, 0x3000
end }
AshitaCore = { GetResourceManager = function() return {
    GetFilePath = function(_, id) assert(id == 87); return 'C:\\FFXI\\ROM2\\9\\12.DAT' end,
} end }
local dat = require('winxi.statusdat')
local one = assert(dat.Get(1))
assert(reads == 1 and asked == 'ROM2\\9\\12.DAT', 'must read FTABLE-selected file through Pivot-aware reader')
assert(one.Bitmap[0] == 66 and one.Bitmap[1] == 77 and one.Bitmap[54] == 22, 'must select the requested record and create BMP')
assert(one.Bitmap[57] == 255, 'DAT alpha must be expanded for D3DX')
assert(one.ImageSize == 54 + 4096)
assert(dat.Get(1) == one and reads == 1, 'must cache DAT and decoded icons')
assert(dat.Get(2) == nil and dat.Get(-1) == nil and dat.Get(0.5) == nil and dat.Get(nil) == nil)
assert(dat.Decode(data, 0x1800 - 1, 0) == nil, 'truncated record must be rejected')
put(data, 0x280, 0x1800)
assert(dat.Decode(data, 0x3000, 0) == nil, 'oversized image must be rejected')
record(data, 0, 32, 11)
put(data, 0x295 + 4, 4096)
assert(dat.Decode(data, 0x3000, 0) == nil, 'invalid dimensions must be rejected')
local old = ffi.new('uint8_t[?]', 0x1800)
record(old, 0, 8, 33); record(old, 0xC00, 8, 44)
local indexed = assert(dat.Decode(old, 0x1800, 1, 0xC00))
assert(indexed.ImageSize == 54 + 1024 + 1024 and indexed.Bitmap[54] == 44)
-- Failure leaves statusicons free to use its resource-manager fallback.
package.loaded['winxi.statusdat'] = nil
package.loaded['winxi.mapdat'].Read = function() return nil, 'unavailable' end
assert(require('winxi.statusdat').Get(0) == nil)
-- Optional local validation against a real installed/overlay table.
if arg[1] then
    local file = assert(io.open(arg[1], 'rb')); local bytes = file:read('*a'); file:close()
    local count = #bytes / 0x1800
    for id = 0, count - 1 do assert(dat.Decode(bytes, #bytes, id), 'failed real record ' .. id) end
    print('real DAT records decoded: ' .. count)
end
print('statusdat: mapped Pivot-aware read, BMP conversion, alpha, caching, legacy indexed data and malformed/fallback checks passed')
