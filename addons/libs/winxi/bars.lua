-- winxi.bars: a bar in the theme's Bar Texture, at any size, on any draw list.
--
--   bars.Draw(list, x, y, width, height, fraction, color)
--                                 the back, the fill (fraction of it, 0 to 1) and the front, each tinted
--                                 color, in the theme's Bar Texture; false where the art would not load
--   bars.Textures(set)            the set's three images ({ back, fill, front }), or nil
--
-- The theme's Fill End Glow lights the end of the fill (assets\bars\glow.png, in white), and with
-- Custom Bar Backdrop the empty part of the bar is in Bar Backdrop Color.
--
-- The art is party's HP bar of each set (addons/party/assets/bars, made by tools/generate_party_bars.py
-- from XivParty's; LICENSE.txt in the folder), in libs\winxi\assets\bars\<set>\: a back, a fill and a
-- front, 28 pixels high. Its ends keep their shape whatever the bar's length (the image's first and last
-- few pixels are drawn at the height's scale and the middle stretched), and the fill lies inside them.
local ffi = require('ffi');
local d3d = require('d3d8');
local imgui = require('imgui');
local theme = require('winxi.theme');

local bars = {};

local folder = nil;
local sets = {};   -- set -> { back, fill, front }, or false where one of them would not load
local kept = {};   -- the textures themselves, held so that they are not let go
local known = {};
for _, set in ipairs(theme.BarTextures) do known[set.key] = true; end

-- The images' measures, in their own pixels: the back and front 220 wide (the front's image 226, its last
-- six the bookend, not drawn here), the fill 204 wide from 8 in; all 28 high
local artHeight, artWidth, frontWidth = 28, 220, 226;
local inset = 8;   -- where the fill starts and ends, from each end
local fillTop, fillBottom = 6, 22; -- the rows of the images the fill covers
local glowLength = 0.55; -- the light at the fill's end, as long as this much of the bar's height
local glow = nil;  -- its image, once loaded (false if it would not)
local glowTint = { 1, 1, 1, 1 };
local slice = 12;  -- how much of each end keeps its shape

-- Where the art is: assets\bars beside this file, as winxi.borders finds its own
function bars.Folder()
    local info = debug.getinfo(1, 'S');
    local here = info and info.source and info.source:match('^@(.*[\\/])');
    if here then return here .. 'assets\\bars\\'; end
    local own = type(addon) == 'table' and type(addon.path) == 'string' and (addon.path .. 'winxi\\assets\\bars\\');
    if own and ashita and ashita.fs and ashita.fs.exists(own) then return own; end
    return ('%s\\addons\\libs\\winxi\\assets\\bars\\'):format(AshitaCore:GetInstallPath());
end

-- Loads one image: a handle imgui can draw, or false. A field, so the checks can stand in for it.
function bars.Load(file)
    folder = folder or bars.Folder();
    local device = d3d.get_device();
    if device == nil then
        return false;
    end
    local pointer = ffi.new('IDirect3DTexture8*[1]');
    if ffi.C.D3DXCreateTextureFromFileA(device, folder .. file, pointer) ~= ffi.C.S_OK then
        return false;
    end
    local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]));
    kept[#kept + 1] = texture;
    return tonumber(ffi.cast('uint32_t', texture));
end

function bars.Textures(set)
    if not known[set] then set = 'original'; end
    local found = sets[set];
    if found == nil then
        found = { back = bars.Load(set .. '\\back.png'), fill = bars.Load(set .. '\\fill.png'), front = bars.Load(set .. '\\front.png') };
        if not (found.back and found.fill and found.front) then found = false; end
        sets[set] = found;
    end
    return found or nil;
end

local pointA, pointB, uvA, uvB = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 1, 1 };

local function Image(list, texture, x1, y1, x2, y2, u1, u2, packed)
    if x2 <= x1 then return; end
    pointA[1], pointA[2], pointB[1], pointB[2] = x1, y1, x2, y2;
    uvA[1], uvB[1] = u1, u2;
    list:AddImage(texture, pointA, pointB, uvA, uvB, packed);
end

-- An image in three: its ends (slice of its pixels each, of imageWidth across, used to used) kept to
-- the height's scale, the middle stretched between
local function Sliced(list, texture, x, y, width, height, imageWidth, used, packed)
    local scale = height / artHeight;
    local ends = math.min(slice * scale, width / 2);
    local u1, u2 = slice / imageWidth, (used - slice) / imageWidth;
    Image(list, texture, x, y, x + ends, y + height, 0, u1, packed);
    Image(list, texture, x + ends, y, x + width - ends, y + height, u1, u2, packed);
    Image(list, texture, x + width - ends, y, x + width, y + height, u2, used / imageWidth, packed);
end

-- texture is an optional per-bar override; nil follows the shared theme.
function bars.Draw(list, x, y, width, height, fraction, color, texture)
    local art = bars.Textures(texture or theme.Get().BarTexture);
    if art == nil or width <= 0 or height <= 0 then
        return false;
    end
    local packed = imgui.GetColorU32(color);
    Sliced(list, art.back, x, y, width, height, artWidth, artWidth, packed);
    local look = theme.Get();
    local edge = math.min(inset * height / artHeight, width / 2);
    local left = x + edge;
    if look.BarBackdrop then
        pointA[1], pointA[2] = left, y + fillTop * height / artHeight;
        pointB[1], pointB[2] = x + width - edge, y + fillBottom * height / artHeight;
        list:AddRectFilled(pointA, pointB, imgui.GetColorU32(look.BarBackdropColor));
    end
    fraction = math.max(0, math.min(1, fraction or 0));
    if fraction > 0 then
        -- the whole fill image, squeezed to how far it goes, as party draws it
        local length = (width - 2 * edge) * fraction;
        Image(list, art.fill, left, y, left + length, y + height, 0, 1, packed);
        local strength = (tonumber(look.BarGlow) or 0) / 100;
        if strength > 0 then
            if glow == nil then glow = bars.Load('glow.png'); end
            if glow then
                -- all of the light where the fill is longer than it, and its right end where it is not
                local full = height * glowLength;
                local shown = math.min(length, full);
                glowTint[4] = strength;
                Image(list, glow, left + length - shown, y, left + length, y + height, 1 - shown / full, 1, imgui.GetColorU32(glowTint));
            end
        end
    end
    Sliced(list, art.front, x, y, width, height, frontWidth, artWidth, packed);
    return true;
end

return bars;
