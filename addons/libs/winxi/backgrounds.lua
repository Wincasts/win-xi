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
-- dark line on every other row, after the look of the game's own windows. The rest are greyscale tiles
-- of libs\winxi\assets\backgrounds, near white, tinted the background colour: each drawn at its own
-- size, side by side, so that it is never stretched. Every one fades with the window.
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

-- Loads one of the tiles: a handle imgui can draw, or false. A field, so the checks can stand in for it.
function backgrounds.Load(style)
    folder = folder or ('%s\\addons\\libs\\winxi\\assets\\backgrounds\\'):format(AshitaCore:GetInstallPath());
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

local chosen = {}; -- style -> { style, texture }, made once each

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
    return entry or nil;
end

local topLeft, bottomRight = { 0, 0 }, { 0, 0 };
local uvA, uvB = { 0, 0 }, { 0, 0 };
local light, dark, line = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0.14 };

-- color, its brightness changed by amount and its alpha kept, into into
local function Shade(into, color, amount)
    for channel = 1, 3 do
        into[channel] = math.min(1, color[channel] * amount);
    end
    into[4] = color[4];
    return into;
end

function backgrounds.Draw(entry, color)
    if entry == nil or color == nil or color[4] <= 0 then
        return;
    end
    local x, y = imgui.GetWindowPos();
    local width, height = imgui.GetWindowSize();
    if width <= 0 or height <= 0 then
        return;
    end
    local list = imgui.GetWindowDrawList();
    -- GetColorU32 takes in the window's Alpha, and so a fading window's fade
    if entry.texture then
        local tint = imgui.GetColorU32(color);
        for top = y, y + height - 1, tileSize do
            local h = math.min(tileSize, y + height - top);
            for left = x, x + width - 1, tileSize do
                local w = math.min(tileSize, x + width - left);
                topLeft[1], topLeft[2], bottomRight[1], bottomRight[2] = left, top, left + w, top + h;
                uvB[1], uvB[2] = w / tileSize, h / tileSize;
                list:AddImage(entry.texture, topLeft, bottomRight, uvA, uvB, tint);
            end
        end
        return;
    end

    local top, bottom = imgui.GetColorU32(Shade(light, color, 1.45)), imgui.GetColorU32(Shade(dark, color, 0.75));
    topLeft[1], topLeft[2], bottomRight[1], bottomRight[2] = x, y, x + width, y + height;
    list:AddRectFilledMultiColor(topLeft, bottomRight, top, top, bottom, bottom);
    if entry.style == 'ffxi' then
        line[4] = 0.14 * color[4];
        local packed = imgui.GetColorU32(line);
        for row = y, y + height - 1, 2 do
            topLeft[2], bottomRight[2] = row, row + 1;
            list:AddRectFilled(topLeft, bottomRight, packed);
        end
    end
end

return backgrounds;
