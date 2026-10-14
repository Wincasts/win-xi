-- winxi.statusicons: a status's icon, as something imgui can draw.
--
--   statusicons.Get(id, useOwn)   the icon's handle, and whether it is one of winxi's own
--   statusicons.Own(id)           winxi's own icon for the status, or nil where it has none
--   statusicons.Game(id)          the game's icon for it, or nil
--
-- winxi's own are the files of libs\winxi\statusicons, <status number>.png: FFXIV's icons, put there
-- by tools/build_status_icons.py from the table of which stands for which FFXI status. A status with
-- no file there has only the game's icon. An icon of winxi's own is 48 by 64 in the middle of a square
-- of 64, so that the card has no need to stretch it: it is drawn from OwnLeft to OwnRight of the
-- square's width, OwnAspect as wide as it is tall. The game's icons are square.
local ffi = require('ffi');
local d3d = require('d3d8');

local statusicons = {};

statusicons.OwnLeft, statusicons.OwnRight = 8 / 64, 56 / 64;
statusicons.OwnAspect = 48 / 64;

local folder = nil; -- where winxi's own icons are: worked out once
local own = {};     -- status -> its handle, or false where the folder has none
local games = {};   -- the same, for the game's icons
local kept = {};    -- the textures themselves, held so that they are not let go

local function Keep(pointer)
    local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]));
    kept[#kept + 1] = texture;
    return tonumber(ffi.cast('uint32_t', texture));
end

local function LoadOwn(id)
    folder = folder or ('%s\\addons\\libs\\winxi\\statusicons\\'):format(AshitaCore:GetInstallPath());
    local path = ('%s%d.png'):format(folder, id);
    local device = d3d.get_device();
    if device == nil or not ashita.fs.exists(path) then
        return false;
    end
    local pointer = ffi.new('IDirect3DTexture8*[1]');
    if ffi.C.D3DXCreateTextureFromFileA(device, path, pointer) ~= ffi.C.S_OK then
        return false;
    end
    return Keep(pointer);
end

local function LoadGame(id)
    local device = d3d.get_device();
    local icon = AshitaCore:GetResourceManager():GetStatusIconByIndex(id);
    if device == nil or icon == nil then
        return false;
    end
    -- the game's icons are bitmaps with black where nothing is
    local pointer = ffi.new('IDirect3DTexture8*[1]');
    if ffi.C.D3DXCreateTextureFromFileInMemoryEx(device, icon.Bitmap, icon.ImageSize, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
            ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000, nil, nil, pointer) ~= ffi.C.S_OK then
        return false;
    end
    return Keep(pointer);
end

local function From(cache, load, id)
    local handle = cache[id];
    if handle == nil then
        local ok, made = pcall(load, id);
        handle = ok and made or false;
        cache[id] = handle;
    end
    return handle or nil;
end

function statusicons.Own(id)
    return From(own, LoadOwn, id);
end

function statusicons.Game(id)
    return From(games, LoadGame, id);
end

-- The icon for a status: its handle, and whether it is one of winxi's own (and so of that shape).
-- useOwn false asks for the game's icon whatever winxi has. nil where there is no icon at all.
function statusicons.Get(id, useOwn)
    local handle = useOwn and statusicons.Own(id) or nil;
    if handle ~= nil then
        return handle, true;
    end
    return statusicons.Game(id), false;
end

return statusicons;
