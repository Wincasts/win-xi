-- winxi.borders: the theme's window border art, drawn in place of a window's own border.
--
--   borders.Texture(style)        the style's image, or nil for 'theme' or an image that will not load.
--                                 Ask before the window's Begin: its own border is switched off (below)
--                                 only when there is art to take its place.
--   borders.Push(texture, gapped) before Begin: no border of imgui's own, and slightly rounded corners,
--                                 where there is art; returns how many style vars were pushed. gapped
--                                 true for a window whose border is to be broken by its title
--                                 (winxi.titles): its plain border is then drawn here too, not by imgui.
--   borders.Draw(texture, gapLeft, gapRight)
--                                 inside the window, after its content: the art around its edge, faded by
--                                 the theme's Border Opacity. Given a gap, from gapLeft to gapRight across
--                                 the top edge, the border (art or plain) is left out there: drawn
--                                 round it, not clipped, as a clip rect can move what it holds a pixel.
--
-- Only for a window of the game kind (winxi.window's kinds): a settings window keeps the plain border.
--
-- The art is a nine-slice image of libs\winxi\assets\borders, one for each of theme.BorderStyles but
-- 'theme': its corners stay 3 pixels whatever the window's size, and its edges stretch. It keeps the
-- theme's background, so a padding of at least 3 keeps a window's content clear of it.
local ffi = require('ffi');
local d3d = require('d3d8');
local imgui = require('imgui');
local theme = require('winxi.theme');

local borders = {};

local folder = nil;
local handles = {}; -- style -> its handle, or false where it would not load
local kept = {};    -- the textures themselves, held so that they are not let go
local files = {
    silver = true, bronze = true, ffxi = true, crystal = true, royal = true, obsidian = true, obsidian_plain = true,
    royal_silver = true, royal_platinum = true, mythril = true, adaman = true, jade = true, amethyst = true,
};

-- Where the art is: assets\borders beside this file, in libs\winxi or in the copy of winxi an addon
-- released on its own carries in its folder. If this file's place is not known: the addon's own
-- copy's, if it has one, or libs\winxi's.
function borders.Folder()
    local info = debug.getinfo(1, 'S');
    local here = info and info.source and info.source:match('^@(.*[\\/])');
    if here then return here .. 'assets\\borders\\'; end
    local own = type(addon) == 'table' and type(addon.path) == 'string' and (addon.path .. 'winxi\\assets\\borders\\');
    if own and ashita and ashita.fs and ashita.fs.exists(own) then return own; end
    return ('%s\\addons\\libs\\winxi\\assets\\borders\\'):format(AshitaCore:GetInstallPath());
end

-- Loads one of the images: a handle imgui can draw, or false. A field, so the checks can stand in for it.
function borders.Load(style)
    folder = folder or borders.Folder();
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

function borders.Texture(style)
    if not files[style] then
        return nil;
    end
    local handle = handles[style];
    if handle == nil then
        handle = borders.Load(style) or false;
        handles[style] = handle;
    end
    return handle or nil;
end

function borders.Push(texture, gapped)
    if not texture then
        if not gapped then
            return 0;
        end
        imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
        return 1;
    end
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 3);
    return 2;
end

local white = { 1, 1, 1, 1 }; -- its alpha the theme's Border Opacity
local uv = { 0, 8 / 64, 56 / 64, 1 };
local xx, yy = { 0, 0, 0, 0 }, { 0, 0, 0, 0 };
local pointA, pointB, uvA, uvB = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };

-- The plain border, as imgui draws a window's: a line of one pixel through the middle of the pixels
-- at the window's edge, its corners rounded as the window's are. With a gap it is one line that runs
-- from the right of the gap round the window, clockwise, to its left.
local cornerPoint = { 0, 0 };

local function PlainEdge(list, tint, x, y, width, height, gapA, gapB)
    local style = imgui.GetStyle();
    local rounding = style and tonumber(style.WindowRounding) or 0;
    -- a gap clear of the top edge's straight part leaves it whole
    if gapA ~= nil and (gapB <= x + rounding or gapA >= x + width - rounding) then
        gapA = nil;
    end
    if gapA == nil then
        pointA[1], pointA[2], pointB[1], pointB[2] = x, y, x + width, y + height;
        list:AddRect(pointA, pointB, tint, rounding, 0, 1);
        return;
    end
    local left, top, right, bottom = x + 0.5, y + 0.5, x + width - 0.5, y + height - 0.5;
    local r = math.max(0, math.min(rounding, (right - left) / 2, (bottom - top) / 2));
    local function Point(px, py)
        cornerPoint[1], cornerPoint[2] = px, py;
        list:PathLineTo(cornerPoint);
    end
    -- each corner: a quarter circle, from the angle (in twelfths of a turn, 0 to the right, 3 down)
    -- the path comes in at to the one it leaves by
    local function Corner(cx, cy, from, to)
        if r > 0 then
            cornerPoint[1], cornerPoint[2] = cx, cy;
            list:PathArcToFast(cornerPoint, r, from, to);
        else
            Point(cx, cy);
        end
    end
    Point(math.max(math.min(gapB, right - r), left + r), top);
    Corner(r > 0 and right - r or right, r > 0 and top + r or top, 9, 12);
    Corner(r > 0 and right - r or right, r > 0 and bottom - r or bottom, 0, 3);
    Corner(r > 0 and left + r or left, r > 0 and bottom - r or bottom, 3, 6);
    Corner(r > 0 and left + r or left, r > 0 and top + r or top, 6, 9);
    Point(math.min(math.max(gapA, left + r), right - r), top);
    list:PathStroke(tint, 0, 1);
end

-- The art all round the window, as nine slices: its corners as they are, its edges stretched. With
-- a gap, the top edge is two pieces, either side of it, each showing its own part of the image.
local function ArtEdge(list, texture, tint, x, y, width, height, gapA, gapB)
    local edge = math.min(3, width / 2, height / 2);
    xx[1], xx[2], xx[3], xx[4] = x, x + edge, x + width - edge, x + width;
    yy[1], yy[2], yy[3], yy[4] = y, y + edge, y + height - edge, y + height;
    for row = 1, 3 do
        for col = 1, 3 do
            if row ~= 2 or col ~= 2 then
                pointA[1], pointA[2], pointB[1], pointB[2] = xx[col], yy[row], xx[col + 1], yy[row + 1];
                uvA[1], uvA[2], uvB[1], uvB[2] = uv[col], uv[row], uv[col + 1], uv[row + 1];
                if row == 1 and col == 2 and gapA ~= nil then
                    -- the stretch of the top edge left of the gap, then right of it
                    local from, to = xx[2], xx[3];
                    local a, b = math.max(from, math.min(to, gapA)), math.max(from, math.min(to, gapB));
                    local span = to - from;
                    if a > from then
                        pointB[1] = a;
                        uvB[1] = uv[2] + (uv[3] - uv[2]) * (a - from) / span;
                        list:AddImage(texture, pointA, pointB, uvA, uvB, tint);
                    end
                    if b < to then
                        pointA[1], pointB[1] = b, to;
                        uvA[1], uvB[1] = uv[2] + (uv[3] - uv[2]) * (b - from) / span, uv[3];
                        list:AddImage(texture, pointA, pointB, uvA, uvB, tint);
                    end
                else
                    list:AddImage(texture, pointA, pointB, uvA, uvB, tint);
                end
            end
        end
    end
end

-- rect optionally draws a frame attachment; plain borders are then drawn explicitly too.
function borders.Draw(texture, gapLeft, gapRight, override, rect)
    if not texture and not gapLeft and not override and not rect then
        return;
    end
    local x, y, width, height;
    if rect then x, y, width, height = rect.left, rect.top, rect.width, rect.height;
    else x, y = imgui.GetWindowPos(); width, height = imgui.GetWindowSize(); end
    if width <= 0 or height <= 0 then
        return;
    end
    local list = imgui.GetWindowDrawList();
    -- GetColorU32 takes in the window's Alpha, and so a fading window's fade. No clip rect is used
    -- for the gap: the game's Direct3D 8 has no scissor test, and what it does in its place moved the
    -- part of the border under a clipped gap by a pixel.
    if texture then
        white[4] = (tonumber(theme.Get().BorderOpacity) or 100) / 100;
        local tint = override or white;
        if tint[4] <= 0 then
            return;
        end
        ArtEdge(list, texture, imgui.GetColorU32(tint), x, y, width, height, gapLeft, gapRight);
    else
        local color = override or theme.GameBorderColor();
        if color[4] <= 0 then
            return;
        end
        PlainEdge(list, imgui.GetColorU32(color), x, y, width, height, gapLeft, gapRight);
    end
end

return borders;
