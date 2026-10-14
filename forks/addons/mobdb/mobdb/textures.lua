local function LoadTexture(filePath)
    local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    if (ffi.C.D3DXCreateTextureFromFileA(d3d8_device, filePath, dx_texture_ptr) == ffi.C.S_OK) then
        return d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]));
    end
    return nil;
end

local textures = {};

textures.Initialize = function(self)
    if self.Cache then
        return;
    end

    self.Cache = {};
    self.Handles = {}; -- each texture as the number imgui takes, worked out once here rather than per draw
    local directory = string.format('%saddons/mobdb/icons/', AshitaCore:GetInstallPath());
    local contents = ashita.fs.get_directory(directory, '.*');
    for _,file in pairs(contents) do
        local index = string.find(file, '%.');        
        local key = string.sub(file, 1, index - 1);
        local texture = LoadTexture(string.format('%saddons/mobdb/icons/%s', AshitaCore:GetInstallPath(), file));
        self.Cache[key] = texture;
        if texture ~= nil then
            self.Handles[key] = tonumber(ffi.cast('uint32_t', texture));
        end
    end
end

-- The tables every icon is drawn with, shared rather than made afresh for each one
local uvMin, uvMax = { 0, 0 }, { 1, 1 };
local tint, border = { 1, 1, 1, 1 }, { 0, 0, 0, 0 };
local sizeTable, sizeValue = { 0, 0 }, nil;

-- Draws an icon as a square of the given size. Returns false, drawing nothing, if there is no such icon.
textures.Draw = function(self, key, size)
    local handle = self.Handles[key];
    if handle == nil then
        return false;
    end

    if size ~= sizeValue then
        sizeTable[1], sizeTable[2] = size, size;
        sizeValue = size;
    end
    imgui.Image(handle, sizeTable, uvMin, uvMax, tint, border);
    return true;
end

textures.Release = function(self)

end


return textures;