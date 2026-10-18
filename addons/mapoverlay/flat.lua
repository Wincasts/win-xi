-- A map's walkable ground painted flat: one colour over the ground, another round its rim, nothing
-- off it, as a texture of the mask's size (masks.lua).
--
--   flat.Texture(device, mask, fill, edge)   the texture, or nil and why not; fill and edge { r, g, b }, 0 to 1
--   flat.Load(mask, fill, edge)              the texture and the handle imgui draws it by, or nil, nil and why
local ffi = require('ffi');
local flat = {};

local ARGB, MANAGED = 21, 1; -- D3DFMT_A8R8G8B8, D3DPOOL_MANAGED

local function Byte(v)
    return math.max(0, math.min(255, math.floor(v * 255 + 0.5)));
end

function flat.Texture(device, mask, fill, edge)
    local made, texture = device:CreateTexture(mask.width, mask.height, 1, 0, ARGB, MANAGED);
    if made ~= 0 or texture == nil then
        return nil, ('the device made no texture (%08X)'):format(made % 0x100000000);
    end
    local locked, rect = texture:LockRect(0, nil, 0);
    if locked ~= 0 or rect == nil or rect.pBits == nil then
        texture:Release();
        return nil, 'the texture could not be locked';
    end
    local fr, fg, fb = Byte(fill[1]), Byte(fill[2]), Byte(fill[3]);
    local er, eg, eb = Byte(edge[1]), Byte(edge[2]), Byte(edge[3]);
    local bits, pitch = ffi.cast('uint8_t*', rect.pBits), rect.Pitch;
    local values, rim, width = mask.values, mask.edge, mask.width;
    for y = 0, mask.height - 1 do
        local row, at = bits + y * pitch, y * width;
        for x = 0, width - 1 do
            local onRim = rim[at + x] ~= 0;
            row[x * 4] = onRim and eb or fb;
            row[x * 4 + 1] = onRim and eg or fg;
            row[x * 4 + 2] = onRim and er or fr;
            row[x * 4 + 3] = values[at + x];
        end
    end
    texture:UnlockRect(0);
    return texture;
end

function flat.Load(mask, fill, edge)
    local d3d8 = require('d3d8');
    local device = d3d8.get_device();
    if device == nil then
        return nil, nil, 'no device yet';
    end
    local texture, why = flat.Texture(device, mask, fill, edge);
    if texture == nil then
        return nil, nil, why;
    end
    texture = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture));
    return texture, tonumber(ffi.cast('uint32_t', texture));
end

return flat;
