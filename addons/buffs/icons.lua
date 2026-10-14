-- A status's icon, as something imgui can draw: the one in the icons folder where there is one
-- (FFXIV's, put there by tools/build_status_icons.py), the game's own where there is not.
local ffi = require('ffi');
local d3d = require('d3d8');

local icons = {};

-- An icon of the folder is 48 by 64 in the middle of a square of 64, so that the card has no need
-- to stretch it: this much of the square's width is the icon
icons.OwnLeft, icons.OwnRight = 8 / 64, 56 / 64;
icons.OwnAspect = 48 / 64; -- its width over its height

local own = {};   -- status -> { texture, handle }, or false where the folder has none
local games = {}; -- the same, for the game's icons

local function Keep(pointer)
    local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]));
    return { texture = texture, handle = tonumber(ffi.cast('uint32_t', texture)) };
end

local function LoadOwn(id)
    local path = ('%sicons\\%d.png'):format(addon.path, id);
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
    local kept = cache[id];
    if kept == nil then
        local ok, made = pcall(load, id);
        kept = ok and made or false;
        cache[id] = kept;
    end
    return kept;
end

-- The icon for a status: its handle, and whether it is one of the folder's (and so of that shape).
-- useOwn false asks for the game's icon whatever the folder has. nil where there is no icon at all.
function icons.Get(id, useOwn)
    if useOwn then
        local kept = From(own, LoadOwn, id);
        if kept then
            return kept.handle, true;
        end
    end
    local kept = From(games, LoadGame, id);
    if kept then
        return kept.handle, false;
    end
    return nil, false;
end

return icons;
