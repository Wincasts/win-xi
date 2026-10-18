-- winxi.statusicons: a status's icon, as something imgui can draw.
--
--   statusicons.Get(id, useOwn)   the icon's handle, and whether it is one of the set's (a custom icon)
--   statusicons.Own(id)           the chosen set's icon for the status, or nil where it has none
--   statusicons.Has(id)           whether the chosen set has an icon for the status
--   statusicons.Set()             the chosen set, by its folder's name
--   statusicons.Game(id)          the game's icon for it, or nil
--
-- Custom icons come in sets, each a folder of libs\winxi\statusicons holding <status number>.png for
-- the statuses it has an icon for; a status it has none for keeps the game's icon. The theme's
-- StatusIconSet says which folder is used (statusicons.Default, ffxiv, where it is not there), and its
-- StatusIcons whether any is. statusicons.Sets() lists the folders, to choose from; anyone can add
-- one, and it is found the next time the list is opened.
--
-- A set's icons are drawn whole, as wide for how tall as its pictures are, unless the folder has a
-- set.lua saying otherwise:
--     return { name = 'FFXIV', left = 8 / 64, right = 56 / 64, sheet = 'sheet.png' };
-- name is what the set is called where it is chosen (the folder's name where none is given). left
-- and right are how much of a picture's width the icon takes, from its left edge: ffxiv's are 48 by
-- 64 in the middle of a square of 64. The icon is drawn from statusicons.OwnLeft to OwnRight of the
-- picture, statusicons.OwnAspect as wide as it is tall: those change with the set, so they are read
-- as the icon is drawn, not kept.
--
-- For what can draw from only a few pictures at once, a set is put in one picture, a sheet:
--   statusicons.Sheet()           the sheet's handle, or nil while it will not load
--   statusicons.SheetPlace(id)    where the status's icon is in it, { u0, v0, u1, v1 }, or nil where
--                                 the set has no icon for it, or it is not on the sheet yet
-- ffxiv's sheet is made with its icons by tools/build_status_icons.py (set.lua's sheet), each 48 by 64
-- in the place its number gives it. Any other set's is made here, from the icons, a few a frame from
-- the first time it is asked for.
--
-- As party and buff draw them, the set's icon where it has one and the game's where it has not, in
-- one sheet, for what can draw from only a few pictures (name). Made here a few a frame from the first
-- time it is asked for, from the set's sheet or its icons and the game's resources:
--   statusicons.MixedSheet()       the sheet's handle, or nil while it cannot be made
--   statusicons.MixedPlace(id)     where the status's icon is in it, { u0, v0, u1, v1 }, and whether
--                                  it is the set's (statusicons.OwnAspect as wide as it is tall) or
--                                  the game's (square); nil where it has none, or none yet
--
-- The game's own icons are put in one the same way, made here from the game's resources, for
-- whoever prefers them: 32 by 32 each, 32 to a row, in the place the status's number gives it. It
-- is made a few icons a frame, from the first time it is asked for: an icon not yet in it has no place.
--   statusicons.GameSheet()        the sheet's handle, or nil while it cannot be made
--   statusicons.GameSheetPlace(id) where the game's icon for the status is in it, or nil
local ffi = require('ffi');
local d3d = require('d3d8');
local theme = require('winxi.theme');
local statusdat = require('winxi.statusdat');

-- Every game-artwork path uses the same Pivot-aware source. Ashita's cached
-- bitmap is a fallback only when the installed DAT cannot be read or decoded.
local function GameIcon(id, resources)
    return statusdat.Get(id) or resources:GetStatusIconByIndex(id);
end

local statusicons = {};

statusicons.Default = 'ffxiv';
local FFXIV = { left = 8 / 64, right = 56 / 64, aspect = 48 / 64, sheet = 'sheet.png' };
statusicons.OwnLeft, statusicons.OwnRight = 8 / 64, 56 / 64;
statusicons.OwnAspect = 48 / 64;

local root = nil;   -- libs\winxi\statusicons\: worked out once
local setKey = nil; -- the set in use: the theme's StatusIconSet, as it was when last looked at
local folder = nil; -- where its icons are
local present = {}; -- status -> whether the set has an icon for it, looked for once
local own = {};     -- status -> its handle, or false where the set has none
local games = {};   -- the same, for the game's icons
local kept = {};    -- the textures themselves, held so that they are not let go
local ownKept = {}; -- the same, for the set's: let go when another set is chosen
local retired, retiredAt = {}, nil; -- a set's textures no longer used: let go a while later, not while a frame may still draw them
local RETIRE = 5;   -- seconds

-- The set's sheet: a file of the tool's (SHEET, as tools/build_status_icons.py lays it out), or made
-- here (BUILT: cells as tall as BUILT.Cell and as wide as the icons are for that)
local SHEET = { Width = 2048, Height = 1024, Columns = 42, IconWidth = 48, IconHeight = 64, Retry = 1 };
local BUILT = { Width = 2048, Height = 1024, Cell = 48, MostWidth = 64, Last = 671, PerFrame = 32, Filter = 4 }; -- D3DX_FILTER_TRIANGLE
local sheetFile = nil;   -- the set's sheet file, or nil to make one
local sheet = nil;       -- its handle, once it has loaded or been begun
local sheetTried = nil;  -- when it was last tried for
local places = {};       -- status -> { u0, v0, u1, v1 }, or false where the set has no icon for it
local building = nil;    -- while a sheet is being made: { surface, ids, next, width, columns }
-- The mixed sheet: cells as tall as MIXED.Cell, as wide as the set's icons are for that, in the
-- place each status's number gives it; the game's icons in the corner of theirs, at their own size
local MIXED = { Width = 2048, Cell = 64, Game = 32, PerFrame = 32, Filter = 4, NoFilter = 1, Black = 0xFF000000 };
-- Seconds a frame may spend putting icons on a sheet: each is decoded by D3DX, which can be slow
-- (under Wine above all), so a frame stops at this as well as at the sheet's PerFrame. As a character
-- comes in, a sheet of every icon made at a fixed count a frame held the game up for seconds.
local BUDGET = 0.002;
local mixed = nil;       -- its handle, once begun
local mixedTried = nil;
local mixedPlaces = {};  -- status -> { u0, v0, u1, v1 }, own = whether the set's
local mixing = nil;      -- while it is being made: { surface, next, width, columns, height, copied }

local function Root()
    root = root or ('%s\\addons\\libs\\winxi\\statusicons\\'):format(AshitaCore:GetInstallPath());
    return root;
end

local function Keep(pointer, list)
    local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]));
    list = list or kept;
    list[#list + 1] = texture;
    return tonumber(ffi.cast('uint32_t', texture));
end

-- A set's set.lua, or an empty table
local function About(path)
    local ok, about = pcall(function () return loadfile(path .. 'set.lua')(); end);
    return ok and type(about) == 'table' and about or {};
end

-- Whether the set has an icon for a status: its file is looked for the first time it is asked
local function Present(id)
    local found = present[id];
    if found == nil then
        found = type(id) == 'number' and ashita.fs.exists(('%s%d.png'):format(folder, id)) or false;
        present[id] = found;
    end
    return found;
end

-- The status number of one of a folder's icons, or nil
local function AnyIcon(path)
    local ok, files = pcall(ashita.fs.get_directory, path, '.*\\.png');
    for _, file in ipairs(ok and type(files) == 'table' and files or {}) do
        local id = tonumber(tostring(file):match('^(%d+)%.png$'));
        if id ~= nil then
            return id;
        end
    end
    return nil;
end

-- The width and height of a picture, or nil
local function Size(path)
    local ok, width, height = pcall(function ()
        local info = ffi.new('D3DXIMAGE_INFO[1]');
        if ffi.C.D3DXGetImageInfoFromFileA(path, info) ~= ffi.C.S_OK then
            return nil;
        end
        return tonumber(info[0].Width), tonumber(info[0].Height);
    end);
    if ok and width ~= nil and height ~= nil and width > 0 and height > 0 then
        return width, height;
    end
    return nil;
end

local function StopBuilding()
    if building ~= nil then
        pcall(function () building.surface.lpVtbl.Release(building.surface); end);
        building = nil;
    end
end

local function StopMixing()
    if mixing ~= nil then
        pcall(function () mixing.surface.lpVtbl.Release(mixing.surface); end);
        mixing = nil;
    end
end

-- Takes up the set the theme names: what was loaded of the last is let go (a while later)
local function Use(wanted)
    for _, texture in ipairs(ownKept) do
        retired[#retired + 1] = texture;
    end
    retiredAt = os.clock();
    StopBuilding();
    StopMixing();
    ownKept, own, places, sheet, sheetTried = {}, {}, {}, nil, nil;
    mixed, mixedTried, mixedPlaces = nil, nil, {};

    setKey = wanted;
    local name = type(wanted) == 'string' and wanted ~= '' and not wanted:find('[\\/]') and wanted or statusicons.Default;
    folder = Root() .. name .. '\\';
    if not ashita.fs.exists(folder) then
        folder = Root() .. statusicons.Default .. '\\';
    end
    present = {};

    -- the set winxi comes with is known without its set.lua
    local about = About(folder);
    if folder == Root() .. statusicons.Default .. '\\' then
        about.left, about.right = about.left or FFXIV.left, about.right or FFXIV.right;
        about.sheet, about.aspect = about.sheet or FFXIV.sheet, FFXIV.aspect;
    end
    local left = math.max(0, math.min(1, tonumber(about.left) or 0));
    local right = math.max(left + 0.01, math.min(1, tonumber(about.right) or 1));
    local aspect = about.aspect;
    if aspect == nil then
        -- as wide for how tall as the part of its pictures the icon takes
        local any = AnyIcon(folder);
        local width, height = nil, nil;
        if any ~= nil then
            width, height = Size(('%s%d.png'):format(folder, any));
        end
        aspect = (right - left) * (width ~= nil and width / height or 1);
    end
    statusicons.OwnLeft, statusicons.OwnRight, statusicons.OwnAspect = left, right, aspect;
    sheetFile = type(about.sheet) == 'string' and not about.sheet:find('[\\/]') and about.sheet or nil;
end

-- Whether the theme has since named another set; and what an old set left is let go once it is safe to
local function Current()
    local look = theme.Get();
    local wanted = look ~= nil and look.StatusIconSet or statusicons.Default;
    if wanted ~= setKey or folder == nil then
        Use(wanted);
    elseif retiredAt ~= nil and os.clock() - retiredAt >= RETIRE then
        retired, retiredAt = {}, nil;
    end
end

-- The sets there are to choose from, by folder, as { key, label }: looked for afresh each time
function statusicons.Sets()
    local sets = {};
    local ok, entries = pcall(ashita.fs.get_directory, Root());
    for _, entry in ipairs(ok and type(entries) == 'table' and entries or {}) do
        entry = tostring(entry);
        -- folders alone: a name with no extension, that is a folder
        if not entry:find('%.%w+$') and ashita.fs.exists(Root() .. entry .. '\\') then
            local about = About(Root() .. entry .. '\\');
            sets[#sets + 1] = { key = entry, label = type(about.name) == 'string' and about.name or entry };
        end
    end
    table.sort(sets, function (a, b)
        if (a.key == statusicons.Default) ~= (b.key == statusicons.Default) then
            return a.key == statusicons.Default; -- the one winxi comes with first
        end
        return a.label:lower() < b.label:lower();
    end);
    return sets;
end

-- The set in use, as the theme names it
function statusicons.Set()
    Current();
    return setKey;
end

function statusicons.Has(id)
    Current();
    return Present(id);
end

local function LoadOwn(id)
    if not Present(id) then
        return false;
    end
    local path = ('%s%d.png'):format(folder, id);
    local device = d3d.get_device();
    if device == nil then
        return false;
    end
    local pointer = ffi.new('IDirect3DTexture8*[1]');
    if ffi.C.D3DXCreateTextureFromFileA(device, path, pointer) ~= ffi.C.S_OK then
        return false;
    end
    return Keep(pointer, ownKept);
end

local function LoadGame(id)
    local device = d3d.get_device();
    local icon = GameIcon(id, AshitaCore:GetResourceManager());
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
    Current();
    return From(own, LoadOwn, id);
end

function statusicons.Game(id)
    return From(games, LoadGame, id);
end

local function LoadSheet()
    local device = d3d.get_device();
    local pointer = ffi.new('IDirect3DTexture8*[1]');
    if device ~= nil and ffi.C.D3DXCreateTextureFromFileA(device, folder .. sheetFile, pointer) == ffi.C.S_OK then
        sheet = Keep(pointer, ownKept);
    end
end

-- A sheet made from the set's icons: an empty picture to begin, which they are put on a few a frame
local function StartBuilt()
    local device = d3d.get_device();
    if device == nil then
        return;
    end
    local result, texture = device:CreateTexture(BUILT.Width, BUILT.Height, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED);
    if result ~= ffi.C.S_OK or texture == nil then
        return;
    end
    local surface = ffi.new('IDirect3DSurface8*[1]');
    if texture.lpVtbl.GetSurfaceLevel(texture, 0, surface) ~= ffi.C.S_OK then
        texture:Release();
        return;
    end
    local pitch = ffi.new('D3DLOCKED_RECT[1]');
    if texture.lpVtbl.LockRect(texture, 0, pitch, nil, 0) == ffi.C.S_OK then
        ffi.fill(pitch[0].pBits, pitch[0].Pitch * BUILT.Height);
        texture.lpVtbl.UnlockRect(texture, 0);
    end
    ownKept[#ownKept + 1] = d3d.gc_safe_release(texture);
    sheet = tonumber(ffi.cast('uint32_t', ownKept[#ownKept]));

    -- every status number there is room for: those the set has no icon for are passed over
    local ids = {};
    for id = 0, BUILT.Last do
        ids[#ids + 1] = id;
    end
    -- as wide as the icons are for the cell's height, but no wider than MostWidth
    local width = math.max(1, math.min(BUILT.MostWidth, math.floor(BUILT.Cell * statusicons.OwnAspect + 0.5)));
    building = { surface = surface[0], ids = ids, next = 1, width = width, columns = math.floor(BUILT.Width / width) };
end

local function FillBuilt()
    local rect, from = ffi.new('RECT'), ffi.new('RECT');
    local last = math.min(#building.ids, building.next + BUILT.PerFrame - 1);
    local stop = os.clock() + BUDGET;
    for index = building.next, last do
        if index > building.next and os.clock() >= stop then
            last = index - 1;
            break;
        end
        local id = building.ids[index];
        local path = ('%s%d.png'):format(folder, id);
        local width, height = nil, nil;
        if Present(id) then
            width, height = Size(path);
        end
        local cell = id; -- each in the place its number gives it, as on ffxiv's sheet
        local x, y = cell % building.columns * building.width, math.floor(cell / building.columns) * BUILT.Cell;
        if width ~= nil and y + BUILT.Cell <= BUILT.Height then
            rect.left, rect.top, rect.right, rect.bottom = x, y, x + building.width, y + BUILT.Cell;
            -- only the part of the picture the icon is in
            from.left, from.top = math.floor(width * statusicons.OwnLeft + 0.5), 0;
            from.right, from.bottom = math.floor(width * statusicons.OwnRight + 0.5), height;
            if ffi.C.D3DXLoadSurfaceFromFileA(building.surface, nil, rect, path, from, BUILT.Filter, 0, nil) == ffi.C.S_OK then
                places[id] = { (x + 0.5) / BUILT.Width, (y + 0.5) / BUILT.Height,
                    (x + building.width - 0.5) / BUILT.Width, (y + BUILT.Cell - 0.5) / BUILT.Height };
            end
        end
    end
    building.next = last + 1;
    if building.next > #building.ids then
        StopBuilding();
    end
end

-- A device or a file may not be ready as an addon loads: tried again, but not every frame
function statusicons.Sheet()
    Current();
    if sheet == nil then
        local now = os.clock();
        if sheetTried == nil or now - sheetTried >= SHEET.Retry then
            sheetTried = now;
            pcall(sheetFile ~= nil and LoadSheet or StartBuilt);
        end
    end
    if building ~= nil then
        if not pcall(FillBuilt) then
            building.next = building.next + BUILT.PerFrame; -- past what would not go on, so that the rest still can
            if building.next > #building.ids then
                StopBuilding();
            end
        end
    end
    return sheet;
end

-- The sheet of the game's icons: made a few at a time, so that no frame waits on all of them
local GAME = { Side = 1024, Icon = 32, Columns = 32, PerFrame = 64, Black = 0xFF000000, NoFilter = 1 };
local gameSheet = nil;    -- its handle, once made
local gameSurface = nil;  -- what its icons are put on, while some are still to come
local gameNext = 1;       -- the next status to put on it
local gameTried = nil;
local gamePlaces = {};    -- status -> { u0, v0, u1, v1 }, for those on it

local function StartGameSheet()
    local device = d3d.get_device();
    if device == nil then
        return;
    end
    local result, texture = device:CreateTexture(GAME.Side, GAME.Side, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED);
    if result ~= ffi.C.S_OK or texture == nil then
        return;
    end
    local surface = ffi.new('IDirect3DSurface8*[1]');
    if texture.lpVtbl.GetSurfaceLevel(texture, 0, surface) ~= ffi.C.S_OK then
        texture:Release();
        return;
    end
    -- what is not given an icon stays clear
    local pitch = ffi.new('D3DLOCKED_RECT[1]');
    if texture.lpVtbl.LockRect(texture, 0, pitch, nil, 0) == ffi.C.S_OK then
        ffi.fill(pitch[0].pBits, pitch[0].Pitch * GAME.Side);
        texture.lpVtbl.UnlockRect(texture, 0);
    end
    gameSurface = surface[0];
    kept[#kept + 1] = d3d.gc_safe_release(texture);
    gameSheet = tonumber(ffi.cast('uint32_t', kept[#kept]));
end

local function FillGameSheet()
    local resources = AshitaCore:GetResourceManager();
    local rect = ffi.new('RECT');
    local last = math.min(GAME.Columns * GAME.Columns - 1, gameNext + GAME.PerFrame - 1);
    local stop = os.clock() + BUDGET;
    for id = gameNext, last do
        if id > gameNext and os.clock() >= stop then
            last = id - 1;
            break;
        end
        local icon = GameIcon(id, resources);
        if icon ~= nil and icon.ImageSize > 0 then
            local x, y = id % GAME.Columns * GAME.Icon, math.floor(id / GAME.Columns) * GAME.Icon;
            rect.left, rect.top, rect.right, rect.bottom = x, y, x + GAME.Icon, y + GAME.Icon;
            -- the game's icons are bitmaps with black where nothing is
            if ffi.C.D3DXLoadSurfaceFromFileInMemory(gameSurface, nil, rect, icon.Bitmap, icon.ImageSize, nil, GAME.NoFilter, GAME.Black, nil) == ffi.C.S_OK then
                gamePlaces[id] = { (x + 0.5) / GAME.Side, (y + 0.5) / GAME.Side, (x + GAME.Icon - 0.5) / GAME.Side, (y + GAME.Icon - 0.5) / GAME.Side };
            end
        end
    end
    gameNext = last + 1;
    if gameNext >= GAME.Columns * GAME.Columns then
        gameSurface.lpVtbl.Release(gameSurface);
        gameSurface = nil;
    end
end

function statusicons.GameSheet()
    if gameSheet == nil then
        local now = os.clock();
        if gameTried == nil or now - gameTried >= SHEET.Retry then
            gameTried = now;
            pcall(StartGameSheet);
        end
    end
    if gameSurface ~= nil then
        local ok = pcall(FillGameSheet);
        if not ok then
            gameNext = gameNext + GAME.PerFrame; -- past what would not go on, so that the rest still can
            if gameNext >= GAME.Columns * GAME.Columns then
                pcall(function () gameSurface.lpVtbl.Release(gameSurface); end);
                gameSurface = nil;
            end
        end
    end
    return gameSheet;
end

function statusicons.GameSheetPlace(id)
    return gamePlaces[id];
end

local function StartMixed()
    local device = d3d.get_device();
    if device == nil then
        return;
    end
    local width = math.max(MIXED.Game, math.min(MIXED.Cell, math.floor(MIXED.Cell * statusicons.OwnAspect + 0.5)));
    local columns = math.floor(MIXED.Width / width);
    local rows = math.ceil((BUILT.Last + 1) / columns);
    local height = 1;
    while height < rows * MIXED.Cell do
        height = height * 2;
    end
    local result, texture = device:CreateTexture(MIXED.Width, height, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED);
    if result ~= ffi.C.S_OK or texture == nil then
        return;
    end
    local surface = ffi.new('IDirect3DSurface8*[1]');
    if texture.lpVtbl.GetSurfaceLevel(texture, 0, surface) ~= ffi.C.S_OK then
        texture:Release();
        return;
    end
    local pitch = ffi.new('D3DLOCKED_RECT[1]');
    if texture.lpVtbl.LockRect(texture, 0, pitch, nil, 0) == ffi.C.S_OK then
        ffi.fill(pitch[0].pBits, pitch[0].Pitch * height);
        texture.lpVtbl.UnlockRect(texture, 0);
    end
    ownKept[#ownKept + 1] = d3d.gc_safe_release(texture);
    mixed = tonumber(ffi.cast('uint32_t', ownKept[#ownKept]));
    mixing = { surface = surface[0], next = 0, width = width, columns = columns, height = height, copied = false };

    -- a sheet of the tool's laid out as this one is goes on whole, in one
    if sheetFile ~= nil and width == SHEET.IconWidth and columns == SHEET.Columns and MIXED.Cell == SHEET.IconHeight then
        local rect = ffi.new('RECT');
        rect.left, rect.top, rect.right, rect.bottom = 0, 0, SHEET.Width, SHEET.Height;
        mixing.copied = ffi.C.D3DXLoadSurfaceFromFileA(mixing.surface, nil, rect, folder .. sheetFile, nil, MIXED.NoFilter, 0, nil) == ffi.C.S_OK;
    end
end

local function FillMixed()
    local resources = AshitaCore:GetResourceManager();
    local rect, from = ffi.new('RECT'), ffi.new('RECT');
    local last = math.min(BUILT.Last, mixing.next + MIXED.PerFrame - 1);
    local width, side, tall = mixing.width, MIXED.Width, mixing.height;
    local stop = os.clock() + BUDGET;
    for id = mixing.next, last do
        if id > mixing.next and os.clock() >= stop then
            last = id - 1;
            break;
        end
        local x, y = id % mixing.columns * width, math.floor(id / mixing.columns) * MIXED.Cell;
        local placed = false;
        if Present(id) then
            if mixing.copied then
                placed = true;
            else
                local path = ('%s%d.png'):format(folder, id);
                local w, h = Size(path);
                if w ~= nil then
                    rect.left, rect.top, rect.right, rect.bottom = x, y, x + width, y + MIXED.Cell;
                    -- only the part of the picture the icon is in
                    from.left, from.top = math.floor(w * statusicons.OwnLeft + 0.5), 0;
                    from.right, from.bottom = math.floor(w * statusicons.OwnRight + 0.5), h;
                    placed = ffi.C.D3DXLoadSurfaceFromFileA(mixing.surface, nil, rect, path, from, MIXED.Filter, 0, nil) == ffi.C.S_OK;
                end
            end
            if placed then
                mixedPlaces[id] = { (x + 0.5) / side, (y + 0.5) / tall, (x + width - 0.5) / side, (y + MIXED.Cell - 0.5) / tall, own = true };
            end
        end
        if not placed then
            local icon = GameIcon(id, resources);
            if icon ~= nil and icon.ImageSize > 0 then
                rect.left, rect.top, rect.right, rect.bottom = x, y, x + MIXED.Game, y + MIXED.Game;
                -- the game's icons are bitmaps with black where nothing is
                if ffi.C.D3DXLoadSurfaceFromFileInMemory(mixing.surface, nil, rect, icon.Bitmap, icon.ImageSize, nil, MIXED.NoFilter, MIXED.Black, nil) == ffi.C.S_OK then
                    mixedPlaces[id] = { (x + 0.5) / side, (y + 0.5) / tall, (x + MIXED.Game - 0.5) / side, (y + MIXED.Game - 0.5) / tall, own = false };
                end
            end
        end
    end
    mixing.next = last + 1;
    if mixing.next > BUILT.Last then
        StopMixing();
    end
end

function statusicons.MixedSheet()
    Current();
    if mixed == nil then
        local now = os.clock();
        if mixedTried == nil or now - mixedTried >= SHEET.Retry then
            mixedTried = now;
            pcall(StartMixed);
        end
    end
    if mixing ~= nil then
        if not pcall(FillMixed) then
            mixing.next = mixing.next + MIXED.PerFrame; -- past what would not go on, so that the rest still can
            if mixing.next > BUILT.Last then
                StopMixing();
            end
        end
    end
    return mixed;
end

function statusicons.MixedPlace(id)
    Current();
    local place = mixedPlaces[id];
    if place == nil then
        return nil, false;
    end
    return place, place.own;
end

-- On a sheet of the tool's, a status is there if it has a file of its own: the tool makes the two
-- together. The edges are taken half a pixel in, so that nothing of the icon beside it is drawn. On
-- a sheet made here, it is there once it has been put on.
function statusicons.SheetPlace(id)
    Current();
    if sheetFile == nil then
        return places[id] or nil;
    end
    local place = places[id];
    if place == nil then
        place = false;
        if id >= 0 and id < SHEET.Columns * math.floor(SHEET.Height / SHEET.IconHeight) and Present(id) then
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
