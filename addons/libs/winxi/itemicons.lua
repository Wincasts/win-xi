-- winxi.itemicons: the game's item icons, on one sheet.
--
--   itemicons.Frame()      once a frame, before any icon is asked for: the sheet's handle, or nil while
--                          it cannot be made (no device yet)
--   itemicons.Place(id)    where an item's icon is on the sheet, as { u0, v0, u1, v1 } for imgui's
--                          Image and AddImage; or nil while it is still to come, or if it has none
--
-- Every icon drawn from the one sheet is drawn by imgui in one go, where a texture for each would be a
-- draw of its own: a window of items is then a single draw however many it shows. An icon is put on
-- the sheet the first time it is asked for, from the game's own picture of it, and no more than
-- PerFrame of them in a frame: the rest come over the next few, rather than all at once in one long
-- frame as a window full of items opens. The sheet has room for 1024. Once it is full, the icon drawn
-- least lately gives up its place to the one asked for.
local ffi = require('ffi');
local d3d = require('d3d8');

local itemicons = {};

local SHEET = { Side = 1024, Icon = 32, PerFrame = 48, Retry = 2, Black = 0xFF000000, NoFilter = 1 };
local columns = SHEET.Side / SHEET.Icon;
local cells = columns * columns;

local kept = nil;      -- the sheet's texture, kept from being let go
local sheet = nil;     -- its handle
local surface = nil;   -- what the icons are put on
local tried = nil;     -- when making it was last tried
local frame = 0;
local placedThisFrame = 0;

local places = {};     -- item -> { u0, v0, u1, v1 }, or false where it has no icon
local cellOf = {};     -- item -> its cell
local itemIn = {};     -- cell -> the item there
local usedIn = {};     -- cell -> the frame it was last drawn in
local nextCell = 0;    -- the first cell never yet used
local rect = nil;

local function Start()
    local device = d3d.get_device();
    if device == nil then
        return;
    end
    local result, texture = device:CreateTexture(SHEET.Side, SHEET.Side, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED);
    if result ~= ffi.C.S_OK or texture == nil then
        return;
    end
    local level = ffi.new('IDirect3DSurface8*[1]');
    if texture.lpVtbl.GetSurfaceLevel(texture, 0, level) ~= ffi.C.S_OK then
        texture:Release();
        return;
    end
    -- what is not given an icon stays clear
    local locked = ffi.new('D3DLOCKED_RECT[1]');
    if texture.lpVtbl.LockRect(texture, 0, locked, nil, 0) == ffi.C.S_OK then
        ffi.fill(locked[0].pBits, locked[0].Pitch * SHEET.Side);
        texture.lpVtbl.UnlockRect(texture, 0);
    end
    surface = level[0];
    kept = d3d.gc_safe_release(texture);
    sheet = tonumber(ffi.cast('uint32_t', kept));
    rect = ffi.new('RECT');
end

function itemicons.Frame()
    frame = frame + 1;
    placedThisFrame = 0;
    if sheet == nil then
        local now = os.clock();
        if tried == nil or now - tried >= SHEET.Retry then
            tried = now;
            pcall(Start);
        end
    end
    return sheet;
end

-- A cell for an icon: one never used, or else the one drawn least lately (but not this frame)
local function FreeCell()
    if nextCell < cells then
        nextCell = nextCell + 1;
        return nextCell - 1;
    end
    local oldest, oldestFrame = nil, frame;
    for cell = 0, cells - 1 do
        local used = usedIn[cell] or 0;
        if used < oldestFrame then
            oldest, oldestFrame = cell, used;
        end
    end
    if oldest ~= nil and itemIn[oldest] ~= nil then
        local gone = itemIn[oldest];
        places[gone], cellOf[gone] = nil, nil;
    end
    return oldest;
end

local function Put(id)
    local item = AshitaCore:GetResourceManager():GetItemById(id);
    if item == nil or item.ImageSize == nil or item.ImageSize <= 0 then
        places[id] = false;
        return nil;
    end
    local cell = FreeCell();
    if cell == nil then
        return nil;
    end
    local x, y = cell % columns * SHEET.Icon, math.floor(cell / columns) * SHEET.Icon;
    rect.left, rect.top, rect.right, rect.bottom = x, y, x + SHEET.Icon, y + SHEET.Icon;
    -- the game's icons are bitmaps with black where nothing is
    if ffi.C.D3DXLoadSurfaceFromFileInMemory(surface, nil, rect, item.Bitmap, item.ImageSize, nil, SHEET.NoFilter, SHEET.Black, nil) ~= ffi.C.S_OK then
        places[id] = false;
        if nextCell == cell + 1 then
            nextCell = cell; -- not taken after all
        end
        itemIn[cell] = nil;
        return nil;
    end
    local place = { (x + 0.5) / SHEET.Side, (y + 0.5) / SHEET.Side, (x + SHEET.Icon - 0.5) / SHEET.Side, (y + SHEET.Icon - 0.5) / SHEET.Side };
    places[id], cellOf[id], itemIn[cell] = place, cell, id;
    return place;
end

function itemicons.Place(id)
    local place = places[id];
    if place then
        usedIn[cellOf[id]] = frame;
        return place;
    end
    if place == false or surface == nil or placedThisFrame >= SHEET.PerFrame then
        return nil;
    end
    placedThisFrame = placedThisFrame + 1;
    local ok, placed = pcall(Put, id);
    if not ok then
        places[id] = false;
        return nil;
    end
    if placed then
        usedIn[cellOf[id]] = frame;
    end
    return placed;
end

ashita.events.register('unload', 'winxi_itemicons_unload', function()
    if surface ~= nil then
        pcall(function() surface.lpVtbl.Release(surface); end);
        surface = nil;
    end
end);

return itemicons;
