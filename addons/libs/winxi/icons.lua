-- winxi.icons: loading image files as textures, and drawing them cheaply.
--
-- A loaded icon is { texture, handle }: the texture itself, which must be kept for as long as the icon
-- is drawn, and the number imgui takes for it, worked out once rather than on every draw.
local ffi = require('ffi');
local d3d8 = require('d3d8');

local icons = {};

local device = nil;

-- Loads one image file. Returns nil if it cannot be loaded.
function icons.Load(path)
    device = device or d3d8.get_device();

    local pointer = ffi.new('IDirect3DTexture8*[1]');
    if ffi.C.D3DXCreateTextureFromFileA(device, path, pointer) ~= ffi.C.S_OK then
        return nil;
    end

    local texture = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]));
    return { texture = texture, handle = tonumber(ffi.cast('uint32_t', texture)) };
end

-- Loads every file in a folder (its path ending in a slash), by file name without its extension
function icons.LoadFolder(directory)
    local loaded = {};
    for _, file in pairs(ashita.fs.get_directory(directory, '.*') or {}) do
        local dot = string.find(file, '%.');
        if dot and dot > 1 then
            loaded[string.sub(file, 1, dot - 1)] = icons.Load(directory .. file);
        end
    end
    return loaded;
end

-- The tables every icon is drawn with, shared rather than made afresh for each one
local uvMin, uvMax = { 0, 0 }, { 1, 1 };
local tint, border = { 1, 1, 1, 1 }, { 0, 0, 0, 0 };
local sizeTable, sizeValue = { 0, 0 }, nil;

-- Draws a loaded icon as a square of the given size. Returns false, drawing nothing, for nil.
function icons.Draw(icon, size)
    if icon == nil then
        return false;
    end

    if size ~= sizeValue then
        sizeTable[1], sizeTable[2] = size, size;
        sizeValue = size;
    end
    imgui.Image(icon.handle, sizeTable, uvMin, uvMax, tint, border);
    return true;
end

return icons;
