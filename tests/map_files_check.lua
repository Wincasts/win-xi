-- Run: luajit tests/map_files_check.lua
-- Every map mark and zoneinfo draw, found where pivot would find it (XICombinedMaps-2048, then the
-- game's own folder) and read by winxi.mapdat as a picture of 512 or 2048 across. Without the pack only
-- the game's own are looked for, and those only the pack has are counted. Not run where the game is not.
package.path = 'addons/libs/?.lua;' .. package.path;
local ffi = require('ffi');
local mapdat = require('winxi.mapdat');

local function check(label, ...)
    print(label, ...);
    for i = 1, select('#', ...) do assert(select(i, ...), label); end
end

local HOME = os.getenv('HOME');
local GAME = os.getenv('FFXI_DIR') or (HOME .. '/Games/PhoenixXI/SquareEnix/FINAL FANTASY XI');
local PACK = HOME .. '/Games/PhoenixXI/polplugins/DATs/XICombinedMaps-2048';

local function Slurp(path)
    local file = io.open(path, 'rb');
    if file == nil then return nil; end
    local bytes = file:read('*a');
    file:close();
    return bytes;
end

if Slurp(GAME .. '/FTABLE.DAT') == nil then
    print('the game is not installed here: map files not checked');
    return;
end
local packed = Slurp(PACK .. '/ROM/283/76.DAT') ~= nil;
print(packed and 'with XICombinedMaps-2048' or 'without XICombinedMaps-2048: the game\'s own maps only');

local function Picture(dat)
    local bytes = packed and Slurp(PACK .. '/' .. dat) or nil;
    local own = bytes == nil;
    bytes = bytes or Slurp(GAME .. '/' .. dat);
    if bytes == nil then return nil, 'missing'; end
    local buffer = ffi.new('uint8_t[?]', #bytes);
    ffi.copy(buffer, bytes, #bytes);
    local header, why = mapdat.Header(buffer, #bytes);
    if header == nil then return nil, why; end
    return header, own;
end

local function Survey(label, dats)
    local read, onlyPack, sizes, bad = 0, 0, {}, {}; -- onlyPack: not among the game's own files
    for _, dat in ipairs(dats) do
        local header, why = Picture(dat);
        if header ~= nil then
            read = read + 1;
            sizes[header.width] = (sizes[header.width] or 0) + 1;
            if header.width ~= header.height or (header.width ~= 512 and header.width ~= 2048) then bad[#bad + 1] = dat .. ' ' .. header.width; end
        elseif packed or why ~= 'missing' then
            bad[#bad + 1] = dat .. ' ' .. tostring(why);
        end
        local file = io.open(GAME .. '/' .. dat, 'rb');
        if file then file:close(); else onlyPack = onlyPack + 1; end
    end
    print(('%s: %d maps, %d read (%d at 512, %d at 2048), %d only in the pack'):format(label, #dats, read,
        sizes[512] or 0, sizes[2048] or 0, onlyPack));
    if #bad > 0 then print('  not right: ' .. table.concat(bad, ', ', 1, math.min(#bad, 5))); end
    return read, onlyPack, #bad;
end

-- mark: every map's file, and each one the game has, as mark has to show a map without the pack too
local markDats = {};
for _, floors in pairs(dofile('addons/mark/data/maps.lua')) do
    for _, floor in ipairs(floors) do markDats[#markDats + 1] = floor.dat; end
end
local read, onlyPack, bad = Survey('mark', markDats);
check('mark: every map read, none the pack\'s alone', read == #markDats, onlyPack == 0, bad == 0);

-- zoneinfo: every map in the browser; those the pack alone has are its own other pictures of a map,
-- blank in the browser without it
local zoneDats = {};
for _, map in ipairs(dofile('addons/zoneinfo/data/all_maps.lua')) do zoneDats[#zoneDats + 1] = map.dat; end
local poc = dofile('addons/zoneinfo/data/poc_areas.lua');
for _, map in pairs(poc) do if type(map) == 'table' and map.dat then zoneDats[#zoneDats + 1] = map.dat; end end
read, onlyPack, bad = Survey('zoneinfo', zoneDats);
check('zoneinfo: every map read; the few the pack alone has read only with it', bad == 0,
    read == (packed and #zoneDats or #zoneDats - onlyPack));

print('map files: passed');
