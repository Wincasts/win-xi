-- winxi.backgrounds: the theme's window background, drawn in place of a window's own flat one.
--
--   backgrounds.For(options)   before Begin: what the window's background is to be, or nil for imgui's
--                              own flat one ('plain', a settings window, or a tile that will not load).
--                              Where it is not nil the window's own background is pushed clear
--                              (winxi.style does this), so that this is the only one.
--   backgrounds.Draw(chosen, color)
--                              inside the window, before its content: the background, in color (the
--                              window's background colour, alpha and all)
--
-- Only for a window of the game kind (winxi.window's kinds): a settings window keeps the plain one.
--
-- 'gradient' is the colour, lighter at the top and darker at the bottom; 'ffxi' is that, with a fine
-- dark line on every other row, after the look of the game's own windows: the lines are a tile of
-- their own (lines.png, a dark row and a clear row down it), laid over the gradient, in place of a
-- rectangle for every other row of the window, which was a few hundred a window. The rest are
-- greyscale tiles of libs\winxi\assets\backgrounds, near white, tinted the background colour. Every
-- tile is drawn at its own size, side by side, so that it is never stretched, and every background
-- fades with the window.
local ffi = require('ffi');
local d3d = require('d3d8');
local imgui = require('imgui');
local theme = require('winxi.theme');

local backgrounds = {};

local tileSize = 128;
local tiles = { grain = true, marble = true, weave = true, brushed = true };
local drawn = { gradient = true, ffxi = true };

local folder = nil;
local handles = {}; -- style -> its handle, or false where it would not load
local kept = {};    -- the textures themselves, held so that they are not let go

-- Where the art is: assets\backgrounds beside this file, in libs\winxi or in the copy of winxi an addon
-- released on its own carries in its folder. If this file's place is not known: the addon's own
-- copy's, if it has one, or libs\winxi's.
function backgrounds.Folder()
    local info = debug.getinfo(1, 'S');
    local here = info and info.source and info.source:match('^@(.*[\\/])');
    if here then return here .. 'assets\\backgrounds\\'; end
    local own = type(addon) == 'table' and type(addon.path) == 'string' and (addon.path .. 'winxi\\assets\\backgrounds\\');
    if own and ashita and ashita.fs and ashita.fs.exists(own) then return own; end
    return ('%s\\addons\\libs\\winxi\\assets\\backgrounds\\'):format(AshitaCore:GetInstallPath());
end

-- Loads one of the tiles: a handle imgui can draw, or false. A field, so the checks can stand in for it.
function backgrounds.Load(style)
    folder = folder or backgrounds.Folder();
    local device = d3d.get_device();
    if device == nil then
        return false;
    end
    local pointer = ffi.new('IDirect3DTexture8*[1]');
    if ffi.C.D3DXCreateTextureFromFileA(device, folder .. style .. '.png', pointer) ~= ffi.C.S_OK then
        return false;
    end
    local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]));
    kept[#kept + 1] = texture;
    return tonumber(ffi.cast('uint32_t', texture));
end

local chosen = {}; -- style -> { style, texture, lines, linesTried }, made once each

-- The lines of 'ffxi' are a tile as well. Where it will not load (no device yet, or no file) the rows
-- are drawn one by one as before, and the tile is tried for again now and then.
local LINES, linesRetry = 'lines', 2; -- the tile, and seconds between one try for it and the next

function backgrounds.For(options)
    if options ~= nil and options.kind == 'settings' then
        return nil;
    end
    local style = theme.Get().BackgroundStyle;
    if not drawn[style] and not tiles[style] then
        return nil;
    end
    local entry = chosen[style];
    if entry == nil then
        local texture = nil;
        if tiles[style] then
            texture = backgrounds.Load(style) or false;
        end
        entry = texture ~= false and { style = style, texture = texture } or false;
        chosen[style] = entry;
    end
    if entry and style == 'ffxi' and entry.lines == nil then
        local now = os.clock();
        if entry.linesTried == nil or now - entry.linesTried >= linesRetry then
            entry.linesTried = now;
            entry.lines = backgrounds.Load(LINES) or nil;
        end
    end
    return entry or nil;
end

local topLeft, bottomRight = { 0, 0 }, { 0, 0 };
local uvA, uvB = { 0, 0 }, { 0, 0 };
local light, dark, line = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0.14 };
local lineTint = { 1, 1, 1, 1 }; -- the lines tile as it is, at the colour's alpha

-- A tile over the window, side by side at its own size, the last column and row cut to what is left
local function Tiles(list, texture, tint, x, y, width, height)
    for top = y, y + height - 1, tileSize do
        local h = math.min(tileSize, y + height - top);
        for left = x, x + width - 1, tileSize do
            local w = math.min(tileSize, x + width - left);
            topLeft[1], topLeft[2], bottomRight[1], bottomRight[2] = left, top, left + w, top + h;
            uvB[1], uvB[2] = w / tileSize, h / tileSize;
            list:AddImage(texture, topLeft, bottomRight, uvA, uvB, tint);
        end
    end
end

-- color, its brightness changed by amount and its alpha kept, into into
local function Shade(into, color, amount)
    for channel = 1, 3 do
        into[channel] = math.min(1, color[channel] * amount);
    end
    into[4] = color[4];
    return into;
end

-- rect optionally draws an attachment on the current window's list without changing its layout.
function backgrounds.Draw(entry, color, rect)
    if entry == nil or color == nil or color[4] <= 0 then
        return;
    end
    local x, y, width, height;
    if rect then x, y, width, height = rect.left, rect.top, rect.width, rect.height;
    else x, y = imgui.GetWindowPos(); width, height = imgui.GetWindowSize(); end
    if width <= 0 or height <= 0 then
        return;
    end
    local list = imgui.GetWindowDrawList();
    -- GetColorU32 takes in the window's Alpha, and so a fading window's fade
    if entry.texture then
        Tiles(list, entry.texture, imgui.GetColorU32(color), x, y, width, height);
        return;
    end

    local top, bottom = imgui.GetColorU32(Shade(light, color, 1.45)), imgui.GetColorU32(Shade(dark, color, 0.75));
    topLeft[1], topLeft[2], bottomRight[1], bottomRight[2] = x, y, x + width, y + height;
    list:AddRectFilledMultiColor(topLeft, bottomRight, top, top, bottom, bottom);
    if entry.style == 'ffxi' then
        if entry.lines then
            -- the tile's dark rows are black at the lines' strength already: drawn as they are, at the
            -- colour's alpha, so that they fade with it
            lineTint[4] = color[4];
            Tiles(list, entry.lines, imgui.GetColorU32(lineTint), x, y, width, height);
        else
            line[4] = 0.14 * color[4];
            local packed = imgui.GetColorU32(line);
            for row = y, y + height - 1, 2 do
                topLeft[2], bottomRight[2] = row, row + 1;
                list:AddRectFilled(topLeft, bottomRight, packed);
            end
        end
    end
end

return backgrounds;
