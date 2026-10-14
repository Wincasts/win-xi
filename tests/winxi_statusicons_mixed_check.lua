-- winxi.statusicons: the mixed sheet, as name draws from it. The set's icon where it has one and the
-- game's where it has not, as party and buff draw them, all in one picture: a sheet of the tool's
-- goes on whole, any other set's icons one by one, and the game's into the cells the set leaves.
local ffi = require('ffi')
for _, def in ipairs({
    'typedef struct IDirect3DSurface8 IDirect3DSurface8;',
    'typedef struct { long left, top, right, bottom; } RECT;',
    'typedef struct { int Pitch; void* pBits; } D3DLOCKED_RECT;',
    'typedef struct { unsigned Width, Height; } D3DXIMAGE_INFO;',
}) do pcall(ffi.cdef, def) end

-- the device: a picture of the size asked for, and a surface to put icons on
local made, surfaceAt = {}, ffi.cast('IDirect3DSurface8*', 0x6000)
local d3d = require('d3d8')
d3d.get_device = function() return {
    CreateTexture = function(_, width, height)
        local texture = { width = width, height = height }
        texture.lpVtbl = {
            GetSurfaceLevel = function(_, _, out) out[0] = surfaceAt return 0 end,
            LockRect = function() return -1 end, UnlockRect = function() end,
        }
        texture.Release = function() end
        made[#made + 1] = texture
        return 0, texture
    end,
} end
d3d.gc_safe_release = function() return ffi.cast('void*', 0x5000 + #made) end

-- what is put on it: whole files, the set's icons and the game's
local loads, memoryLoads = {}, {}
local originalC = ffi.C
ffi.C = setmetatable({
    S_OK = 0, D3DFMT_A8R8G8B8 = 21, D3DPOOL_MANAGED = 1,
    D3DXLoadSurfaceFromFileA = function(surface, _, rect, path, from)
        loads[#loads + 1] = { path = path, left = rect.left, top = rect.top, right = rect.right, bottom = rect.bottom, cropped = from ~= nil }
        return 0
    end,
    D3DXLoadSurfaceFromFileInMemory = function(surface, _, rect)
        memoryLoads[#memoryLoads + 1] = { left = rect.left, top = rect.top, right = rect.right, bottom = rect.bottom }
        return 0
    end,
    D3DXGetImageInfoFromFileA = function(_, info) info[0].Width, info[0].Height = 64, 64 return 0 end,
}, { __index = originalC })

-- the set has icons for 1 to 3 alone; the game has one for every status but 7
local setHas = { [1] = true, [2] = true, [3] = true }
ashita.fs.exists = function(path)
    local id = tonumber(path:match('\\(%d+)%.png$'))
    if id ~= nil then return setHas[id] == true end
    return true
end
ashita.fs.get_directory = function() return { '1.png' } end
local manager = AshitaCore.GetResourceManager()
manager.GetStatusIconByIndex = function(_, id) return id ~= 7 and { Bitmap = 0, ImageSize = 1 } or nil end
AshitaCore.GetResourceManager = function() return manager end

local statusicons = require('winxi.statusicons')
local look = require('winxi.theme').Get()
local function close(a, b) return math.abs(a - b) < 1e-6 end

-- FFXIV: its sheet goes on whole, laid out as this one is, 48 by 64 a status
local handle = statusicons.MixedSheet()
local frames = 1
-- until a frame puts nothing more on
local count = -1
while #loads + #memoryLoads ~= count and frames < 100 do count = #loads + #memoryLoads; statusicons.MixedSheet(); frames = frames + 1 end
frames = frames - 1
local sheet = made[1]
H.print('ffxiv: a picture of', sheet.width, 'by', sheet.height, '| its sheet put on whole', loads[1] ~= nil and loads[1].path:match('sheet%.png$') ~= nil and loads[1].right == 2048 and loads[1].bottom == 1024,
    '| no icon of the set\'s one by one', #loads == 1)
local place, own = statusicons.MixedPlace(2)
H.print('one the set has: its own, from its cell', own, close(place[1], (2 * 48 + 0.5) / 2048), close(place[3], (3 * 48 - 0.5) / 2048), close(place[4], 63.5 / 1024))
place, own = statusicons.MixedPlace(5)
H.print('one it has not: the game\'s, in the corner of its cell, 32 square', own == false, close(place[1], (5 * 48 + 0.5) / 2048), close(place[3], (5 * 48 + 31.5) / 2048), close(place[4], 31.5 / 1024))
H.print('one neither has: none', statusicons.MixedPlace(7) == nil, '| the game\'s put on for all but the set\'s and that one', #memoryLoads == 672 - 3 - 1)
local before = #loads + #memoryLoads
statusicons.MixedSheet(); statusicons.MixedSheet()
H.print('made once: the same handle, nothing more put on', statusicons.MixedSheet() == handle, #loads + #memoryLoads == before, '| made over', frames, 'frames, 32 statuses a frame')

-- another set, with no sheet: its icons one by one, as wide as they are for 64 high
look.StatusIconSet = 'square'
loads, memoryLoads = {}, {}
statusicons.MixedSheet()
for _ = 1, 40 do statusicons.MixedSheet() end
local square = made[#made]
H.print('a square set: a picture of', square.width, 'by', square.height, '| its icons put on one by one, cropped', #loads == 3 and loads[1].cropped, '| each 64 across', loads[2].right - loads[2].left == 64)
place, own = statusicons.MixedPlace(3)
H.print('its icon in a cell of 64', own, close(place[1], (3 * 64 + 0.5) / 2048), '| the game\'s beside it', select(2, statusicons.MixedPlace(4)) == false)
look.StatusIconSet = 'ffxiv'

ffi.C = originalC
