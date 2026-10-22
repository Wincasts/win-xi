-- winxi: a soft black backdrop behind the crossbar.
--
-- Black at Backdrop Opacity in the middle of the panel, fading smoothly to nothing towards its edge:
-- one round gradient made once into a small texture and stretched over the panel with one sprite draw,
-- so it is an ellipse the panel's shape. Backdrop Size is how far it reaches, in parts of the panel.
local d3d8 = require('d3d8');
local ffi = require('ffi');

local backdrop = {};

local SIZE = 128; -- the texture's width and height

local made = nil; -- { Texture, Rect }, or false where it could not be made
local vec_scale = ffi.new('D3DXVECTOR2', { 1.0, 1.0 });
local vec_position = ffi.new('D3DXVECTOR2', { 0, 0 });

-- How dark the backdrop is at r, the distance from the middle (0) to the edge (1): 1 to 0
function backdrop.At(r)
    if r >= 1 then return 0; end
    local t = 1 - r;
    return t * t * (3 - 2 * t); -- smoothstep, so neither the middle nor the edge shows a crease
end

local function Make()
    local device = d3d8.get_device();
    if device == nil then return false; end
    local result, texture = device:CreateTexture(SIZE, SIZE, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED);
    if result ~= ffi.C.S_OK or texture == nil then return false; end
    texture = d3d8.gc_safe_release(texture);
    local locked = ffi.new('D3DLOCKED_RECT[1]');
    if texture.lpVtbl.LockRect(texture, 0, locked, nil, 0) ~= ffi.C.S_OK then return false; end
    local pitch = locked[0].Pitch;
    local half = SIZE / 2;
    for y = 0, SIZE - 1 do
        local row = ffi.cast('uint32_t*', ffi.cast('uint8_t*', locked[0].pBits) + y * pitch);
        local dy = (y + 0.5 - half) / half;
        for x = 0, SIZE - 1 do
            local dx = (x + 0.5 - half) / half;
            row[x] = math.floor(backdrop.At(math.sqrt(dx * dx + dy * dy)) * 255 + 0.5) * 0x1000000; -- black
        end
    end
    texture.lpVtbl.UnlockRect(texture, 0);
    return { Texture = texture, Rect = ffi.new('RECT', { 0, 0, SIZE, SIZE }) };
end

-- Draws the backdrop behind a panel width by height at x, y: opacity percent dark in the middle,
-- reaching size percent of the panel
function backdrop.Draw(sprite, x, y, width, height, opacity, size)
    local alpha = math.floor(math.max(0, math.min(100, tonumber(opacity) or 50)) / 100 * 255 + 0.5);
    if alpha <= 0 then return; end
    if made == nil then
        local built, result = pcall(Make);
        made = built and result or false;
    end
    if not made then return; end
    local reach = math.max(50, math.min(300, tonumber(size) or 130)) / 100;
    local w, h = width * reach, height * reach;
    vec_scale.x, vec_scale.y = w / SIZE, h / SIZE;
    vec_position.x, vec_position.y = x + (width - w) / 2, y + (height - h) / 2;
    sprite:Draw(made.Texture, made.Rect, vec_scale, nil, 0.0, vec_position, d3d8.D3DCOLOR_ARGB(alpha, 255, 255, 255));
end

return backdrop;
