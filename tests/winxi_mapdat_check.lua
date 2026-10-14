-- Run: luajit tests/winxi_mapdat_check.lua
-- winxi.mapdat against made-up files and, where the game is installed here, its own and XICombinedMaps'
-- maps, drawn into a stand-in device; a bitmap's pixels checked against tools/scan_combined_maps.py's.
package.path = 'addons/libs/?.lua;' .. package.path;
local ffi = require('ffi');

local function check(label, ...)
    print(label, ...);
    for i = 1, select('#', ...) do assert(select(i, ...), label); end
end

local GAME = os.getenv('FFXI_DIR') or (os.getenv('HOME') .. '/Games/PhoenixXI/SquareEnix/FINAL FANTASY XI');
local PACK = os.getenv('HOME') .. '/Games/PhoenixXI/polplugins/DATs/XICombinedMaps-2048';

local asked = nil;
AshitaCore = { GetResourceManager = function() return { GetFilePath = function(_, id)
    asked = id;
    return 'X:\\Games\\PhoenixXI\\SquareEnix\\FINAL FANTASY XI\\ROM\\0\\0.DAT';
end }; end };
package.preload['d3d8'] = function() return { get_device = function() return nil; end }; end;
local mapdat = require('winxi.mapdat');

check('the game folder is file 0\'s, less ROM\\0\\0.DAT', mapdat.Root() == 'X:\\Games\\PhoenixXI\\SquareEnix\\FINAL FANTASY XI', asked == 0);
check('a place out of the game folder is refused', select(2, mapdat.Read('../../secret.DAT')) == 'not a map file');
check('no device, no texture', select(3, mapdat.Load('ROM/17/24.DAT')) == 'no device yet');

-- A device that makes textures of memory, a row's pitch longer than the row, as a real one's can be
local function Device()
    local device = { made = {} };
    function device:CreateTexture(width, height, levels, usage, format, pool)
        local compressed = format ~= 21;
        local row = compressed and math.ceil(width / 4) * (format == 0x31545844 and 8 or 16) or width * 4;
        local rows = compressed and math.ceil(height / 4) or height;
        local texture = { width = width, height = height, format = format, pool = pool, levels = levels,
            pitch = row + 16, row = row, rows = rows, released = false };
        texture.bits = ffi.new('uint8_t[?]', texture.pitch * rows);
        function texture:LockRect() self.locked = true; return 0, { pBits = self.bits, Pitch = self.pitch }; end
        function texture:UnlockRect() self.locked = false; end
        function texture:Release() self.released = true; end
        self.made[#self.made + 1] = texture;
        return 0, texture;
    end
    return device;
end

local function File(bytes)
    local buffer = ffi.new('uint8_t[?]', #bytes);
    ffi.copy(buffer, bytes, #bytes);
    return buffer, #bytes;
end

local function U32(n) return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256); end
local function Picture(width, height, bits, kind, body)
    return string.rep('\0', 0x41) .. U32(40) .. U32(width) .. U32(height) .. string.char(1, 0, bits, 0)
        .. string.rep('\0', 24) .. U32(kind) .. body;
end

-- A 4x2 bitmap of 8 bits: palette entry i is (b, g, r) = (i, 2i, 3i); its rows from the bottom up
local palette = {};
for i = 0, 255 do palette[#palette + 1] = string.char(i, (2 * i) % 256, (3 * i) % 256, 0); end
local bitmap = Picture(4, 2, 8, 10, table.concat(palette) .. string.char(1, 2, 3, 4, 5, 6, 7, 8));
local device = Device();
local texture = mapdat.Texture(device, File(bitmap));
local made = device.made[1];
check('a bitmap is made A8R8G8B8, managed, one level', texture == made, made.format == 21, made.pool == 1, made.levels == 1);
local function Pixel(t, x, y) local at = y * t.pitch + x * 4; return t.bits[at], t.bits[at + 1], t.bits[at + 2], t.bits[at + 3]; end
local b, g, r, a = Pixel(made, 0, 0);
check('its top row is the file\'s last, through the palette', b == 5, g == 10, r == 15, a == 255);
b, g, r, a = Pixel(made, 3, 1);
check('its bottom row the file\'s first', b == 4, g == 8, r == 12, a == 255);
check('the texture is left unlocked', made.locked == false);

-- DXT3 of 8x4: two blocks of 16 bytes, after 8 bytes the format has before them
local blocks = {};
for i = 1, 32 do blocks[i] = string.char(i); end
local dxt = Picture(8, 4, 8, 0x44585433, string.rep('\255', 8) .. table.concat(blocks));
device = Device();
mapdat.Texture(device, File(dxt));
made = device.made[1];
local same = true;
for i = 0, 31 do same = same and made.bits[i] == i + 1; end
check('DXT3 is made DXT3, its blocks copied as they are', made.format == 0x33545844, same);

check('a picture cut short is refused, with no texture made', select(2, mapdat.Texture(Device(), File(dxt:sub(1, -2)))) == 'the picture is cut short');
check('a kind not read is refused', (select(2, mapdat.Header(File(Picture(4, 4, 16, 10, string.rep('\0', 32))))) or ''):find('not read') ~= nil);
check('nonsense is refused', select(2, mapdat.Header(File(string.rep('x', 200)))) == 'not a picture');

-- The real maps, where they are here
local function Slurp(path)
    local file = io.open(path, 'rb');
    if file == nil then return nil; end
    local bytes = file:read('*a');
    file:close();
    return bytes;
end

local function Python(path, points)
    local command = ('python3 -c "import sys; sys.path.insert(0, \'tools\'); from scan_combined_maps import decode; '
        .. 'i = decode(open(sys.argv[1], \'rb\').read()); print(i.size[0], i.size[1]); '
        .. '[print(*i.getpixel((int(x), int(y)))) for x, y in zip(sys.argv[2::2], sys.argv[3::2])]" "%s" %s'):format(path, points);
    local pipe = io.popen(command);
    local out = pipe:read('*a');
    pipe:close();
    return out;
end

local cases = {
    { GAME .. '/ROM/17/24.DAT', 'the game\'s own bitmap map (East Ronfaure)', 512 },
    { PACK .. '/ROM/17/48.DAT', 'XICombinedMaps\' bitmap map, 2048 across', 2048 },
};
for _, case in ipairs(cases) do
    local bytes = Slurp(case[1]);
    if bytes == nil then
        print('not here, so not checked:', case[2]);
    else
        device = Device();
        mapdat.Texture(device, File(bytes));
        made = device.made[1];
        local points, list = { { 0, 0 }, { 100, 37 }, { case[3] - 1, case[3] - 1 }, { case[3] / 2, math.floor(case[3] / 3) } }, {};
        for _, p in ipairs(points) do list[#list + 1] = p[1] .. ' ' .. p[2]; end
        local lines = {};
        for line in Python(case[1], table.concat(list, ' ')):gmatch('[^\n]+') do lines[#lines + 1] = line; end
        local matches = lines[1] == made.width .. ' ' .. made.height;
        for i, p in ipairs(points) do
            local pb, pg, pr = Pixel(made, p[1], p[2]);
            matches = matches and lines[i + 1] == ('%d %d %d'):format(pr, pg, pb);
        end
        check(case[2] .. ': the same pixels as the Python decoder', made.width == case[3], matches);
    end
end

local packed = Slurp(PACK .. '/ROM/283/76.DAT');
if packed == nil then
    print('not here, so not checked: XICombinedMaps\' DXT3 map');
else
    device = Device();
    mapdat.Texture(device, File(packed));
    made = device.made[1];
    local header = mapdat.Header(File(packed));
    local same = true;
    for _, row in ipairs({ 0, 1, made.rows - 1 }) do
        local want = packed:sub(header.at + row * header.row + 1, header.at + (row + 1) * header.row);
        same = same and ffi.string(made.bits + row * made.pitch, made.row) == want;
    end
    check('XICombinedMaps\' DXT3 map: 2048 across, its rows of blocks as in the file', made.width == 2048, made.format == 0x33545844, same);
end

print('winxi.mapdat: passed');
