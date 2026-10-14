-- Drawing on one of imgui's draw lists: images, circles and text at places on screen, in pixels. What
-- the frames and the icons beside them are both drawn with.
--
--     draw.Use(list)                         the draw list the calls after it draw on
--     draw.Packed(color, alpha)              a colour as the list takes it, with the window's fade in it
--     draw.Image(texture, x1, y1, x2, y2, packed, u1, v1, u2, v2)     the whole image, or the part of it given (0 to 1)
--     draw.Circle(x, y, radius, packed, sides)          filled; of 12 sides unless told, enough for a small one
--     draw.Ring(x, y, radius, packed, thick, sides)     a circle's line, thick pixels thick, about that radius
--     draw.Text(x, y, packed, words, edge, dark)        with winxi's dark edge if edge is given
--     draw.Texture(file)                     an image of the addon's, loaded the first time it is asked for
--
-- Nothing is made afresh for a call: the points a list is given are kept and filled in again.
local ffi = require('ffi')
local d3d8 = require('d3d8')
local imgui = require('imgui')
local outlinedText = require('winxi.text')

local draw = { }

local list = nil
local pointA, pointB = { 0, 0 }, { 0, 0 }
local uvA, uvB = { 0, 0 }, { 1, 1 }
local tint = { 1, 1, 1, 1 }

-- The draw list in use. A colour packed for one is not kept for the next: the fade may differ, and a
-- colour's table may have been changed in place since.
local lastColor, lastAlpha, lastPacked = nil, nil, nil

function draw.Use(drawList)
    list = drawList
    lastColor = nil
end

-- Things are drawn a layer at a time, so one colour is asked for many times running: the last is kept
function draw.Packed(color, alpha)
    if color ~= lastColor or alpha ~= lastAlpha then
        tint[1], tint[2], tint[3], tint[4] = color[1], color[2], color[3], color[4] * alpha
        lastPacked = imgui.GetColorU32(tint)
        lastColor, lastAlpha = color, alpha
    end
    return lastPacked
end

function draw.Image(texture, x1, y1, x2, y2, packed, u1, v1, u2, v2)
    pointA[1], pointA[2], pointB[1], pointB[2] = x1, y1, x2, y2
    uvA[1], uvA[2], uvB[1], uvB[2] = u1 or 0, v1 or 0, u2 or 1, v2 or 1
    list:AddImage(texture, pointA, pointB, uvA, uvB, packed)
end

function draw.Circle(x, y, radius, packed, sides)
    pointA[1], pointA[2] = x, y
    list:AddCircleFilled(pointA, radius, packed, sides or 12)
end

function draw.Ring(x, y, radius, packed, thick, sides)
    pointA[1], pointA[2] = x, y
    list:AddCircle(pointA, radius, packed, sides or 12, thick)
end

function draw.Text(x, y, packed, words, edge, dark)
    if edge ~= nil then
        outlinedText.Packed(list, x, y, packed, words, edge, dark)
    else
        pointA[1], pointA[2] = x, y
        list:AddText(pointA, packed, words)
    end
end

-- The images, each loaded the first time it is wanted. A texture is kept for as long as the addon is
-- loaded; imgui takes it as a number.
local handles = { } -- file -> the number, or false where the image could not be loaded
local kept = { }

function draw.Texture(file)
    local handle = handles[file]
    if handle == nil then
        handle = false
        local device = d3d8.get_device()
        if device ~= nil then
            local pointer = ffi.new('IDirect3DTexture8*[1]')
            local path = string.format('%sassets/%s', addon.path, file)
            if ffi.C.D3DXCreateTextureFromFileA(device, path, pointer) == ffi.C.S_OK then
                local texture = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]))
                kept[#kept + 1] = texture
                handle = tonumber(ffi.cast('uint32_t', texture))
            end
        end
        handles[file] = handle
    end
    return handle
end

return draw
