-- winxi: the Winxi Theme's drop shadow, behind each macro element's frame.
--
-- winxi.shadow draws a window's shadow with imgui: a few faint rounded rectangles, each a little
-- larger than the last, moved down and to the right. The crossbar is drawn with a D3DX sprite, so the
-- same shape is made once into a texture, for each size of frame, and drawn under each frame with
-- one sprite draw. It follows the theme's Shadow settings (on, Opacity, Offset, Blur), made again
-- whenever one of them changes. Without winxi, nothing is drawn.
local d3d8 = require('d3d8');
local ffi = require('ffi');

local ok, theme = pcall(require, 'winxi.theme');
if not ok then theme = nil; end

local frameshadow = {};

local maxLayers = 6; -- as winxi.shadow
local SAMPLES = 2;   -- each pixel is looked at SAMPLES by SAMPLES times, for a smooth edge

local made = {};     -- 'width:height' -> { Texture, Rect, Pad }, or false where it could not be made
local madeFor = nil; -- the theme's shadow settings they were made for
local d3dwhite = d3d8.D3DCOLOR_ARGB(255, 255, 255, 255);
local unit = ffi.new('D3DXVECTOR2', { 1.0, 1.0 });
local vec_position = ffi.new('D3DXVECTOR2', { 0, 0 });

-- The theme's shadow settings as one string, or nil while the shadow is off
local function Settings()
    if theme == nil then return nil; end
    local current = theme.Get();
    if not current.ShadowEnabled or current.ShadowOpacity <= 0 then return nil; end
    return ('%d:%d:%d'):format(current.ShadowOpacity, current.ShadowOffset, current.ShadowBlur);
end

local function PowerOfTwo(n)
    local p = 1;
    while p < n do p = p * 2; end
    return p;
end

-- Whether a point is inside a rectangle with rounded corners
local function Inside(px, py, left, top, right, bottom, radius)
    radius = math.min(radius, (right - left) / 2, (bottom - top) / 2);
    local cx = math.max(left + radius, math.min(right - radius, px));
    local cy = math.max(top + radius, math.min(bottom - radius, py));
    local dx, dy = px - cx, py - cy;
    return px >= left and px <= right and py >= top and py <= bottom and dx * dx + dy * dy <= radius * radius;
end

-- The shadow of a frame width by height, in a texture: the frame's top left at (Pad, Pad) in it
local function Make(width, height)
    local current = theme.Get();
    local offset, blur = current.ShadowOffset, current.ShadowBlur;
    local layers = math.max(1, math.min(maxLayers, blur));
    local step = blur / layers;
    local each = (current.ShadowOpacity / 100) / layers;
    local pad = math.ceil(offset + (layers - 1) * step) + 1;
    local w, h = math.ceil(width) + 2 * pad, math.ceil(height) + 2 * pad;

    local device = d3d8.get_device();
    if device == nil then return false; end
    local result, texture = device:CreateTexture(PowerOfTwo(w), PowerOfTwo(h), 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED);
    if result ~= ffi.C.S_OK or texture == nil then return false; end
    texture = d3d8.gc_safe_release(texture);
    local locked = ffi.new('D3DLOCKED_RECT[1]');
    if texture.lpVtbl.LockRect(texture, 0, locked, nil, 0) ~= ffi.C.S_OK then return false; end
    local pitch = locked[0].Pitch;
    ffi.fill(locked[0].pBits, pitch * PowerOfTwo(h));

    for y = 0, h - 1 do
        local row = ffi.cast('uint32_t*', ffi.cast('uint8_t*', locked[0].pBits) + y * pitch);
        for x = 0, w - 1 do
            local covered = 0;
            for sy = 1, SAMPLES do
                local py = y - pad + (sy - 0.5) / SAMPLES;
                for sx = 1, SAMPLES do
                    local px = x - pad + (sx - 0.5) / SAMPLES;
                    -- each layer over the last, as imgui blends them
                    local through = 1;
                    for layer = 0, layers - 1 do
                        local grow = layer * step;
                        if Inside(px, py, offset - grow, offset - grow, width + offset + grow, height + offset + grow, grow + 2) then
                            through = through * (1 - each);
                        end
                    end
                    covered = covered + (1 - through);
                end
            end
            local alpha = math.floor(covered / (SAMPLES * SAMPLES) * 255 + 0.5);
            row[x] = alpha * 0x1000000; -- black, at that alpha
        end
    end
    texture.lpVtbl.UnlockRect(texture, 0);

    return { Texture = texture, Rect = ffi.new('RECT', { 0, 0, w, h }), Pad = pad };
end

-- Draws the shadow of a frame of the given component (a prepared texture of the layout's) at x, y
function frameshadow.Draw(sprite, component, x, y)
    local key = Settings();
    if key == nil then return; end
    if key ~= madeFor then
        made, madeFor = {}, key;
    end
    local width, height = tonumber(component.Rect.right) * component.Scale.x, tonumber(component.Rect.bottom) * component.Scale.y;
    local size = ('%d:%d'):format(math.floor(width + 0.5), math.floor(height + 0.5));
    local shadow = made[size];
    if shadow == nil then
        local built, result = pcall(Make, width, height);
        shadow = built and result or false;
        made[size] = shadow;
    end
    if not shadow then return; end
    vec_position.x, vec_position.y = x - shadow.Pad, y - shadow.Pad;
    sprite:Draw(shadow.Texture, shadow.Rect, unit, nil, 0.0, vec_position, d3dwhite);
end

return frameshadow;
