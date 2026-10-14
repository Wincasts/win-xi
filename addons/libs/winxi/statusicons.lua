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
--
-- For what can draw from only a few pictures at once, the same tool puts winxi's own in one,
-- sheet.png, each 48 by 64 in the place its number gives it:
--   statusicons.Sheet()           the sheet's handle, or nil while it will not load
--   statusicons.SheetPlace(id)    where the status's icon is in it, { u0, v0, u1, v1 }, or nil where
--                                 winxi has no icon for the status
local ffi = require('ffi');
local d3d = require('d3d8');

local statusicons = {};

statusicons.OwnLeft, statusicons.OwnRight = 8 / 64, 56 / 64;
statusicons.OwnAspect = 48 / 64;

local folder = nil; -- where winxi's own icons are: worked out once
local own = {};     -- status -> its handle, or false where the folder has none
local games = {};   -- the same, for the game's icons
local kept = {};    -- the textures themselves, held so that they are not let go

-- sheet.png as tools/build_status_icons.py lays it out
local SHEET = { Width = 2048, Height = 1024, Columns = 42, IconWidth = 48, IconHeight = 64, Retry = 1 };
local sheet = nil;       -- its handle, once it has loaded
local sheetTried = nil;  -- when it was last tried for
local places = {};       -- status -> { u0, v0, u1, v1 }, or false where the folder has no icon for it

local function Folder()
    folder = folder or ('%s\\addons\\libs\\winxi\\statusicons\\'):format(AshitaCore:GetInstallPath());
    return folder;
end

local function Keep(pointer)
    local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]));
    kept[#kept + 1] = texture;
    return tonumber(ffi.cast('uint32_t', texture));
end

local function LoadOwn(id)
    local path = ('%s%d.png'):format(Folder(), id);
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

local function LoadSheet()
    local device = d3d.get_device();
    local pointer = ffi.new('IDirect3DTexture8*[1]');
    if device ~= nil and ffi.C.D3DXCreateTextureFromFileA(device, Folder() .. 'sheet.png', pointer) == ffi.C.S_OK then
        sheet = Keep(pointer);
    end
end

-- A device or a file may not be ready as an addon loads: tried again, but not every frame
function statusicons.Sheet()
    if sheet == nil then
        local now = os.clock();
        if sheetTried == nil or now - sheetTried >= SHEET.Retry then
            sheetTried = now;
            pcall(LoadSheet);
        end
    end
    return sheet;
end

-- A status is in the sheet if it has a file of its own: the tool makes the two together. The edges
-- are taken half a pixel in, so that nothing of the icon beside it is drawn.
function statusicons.SheetPlace(id)
    local place = places[id];
    if place == nil then
        place = false;
        if id >= 0 and id < SHEET.Columns * math.floor(SHEET.Height / SHEET.IconHeight) and ashita.fs.exists(('%s%d.png'):format(Folder(), id)) then
            local x, y = id % SHEET.Columns * SHEET.IconWidth, math.floor(id / SHEET.Columns) * SHEET.IconHeight;
            place = { (x + 0.5) / SHEET.Width, (y + 0.5) / SHEET.Height,
                (x + SHEET.IconWidth - 0.5) / SHEET.Width, (y + SHEET.IconHeight - 0.5) / SHEET.Height };
        end
        places[id] = place;
    end
    return place or nil;
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
