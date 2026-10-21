-- winxi: a glossy light over each macro element's icon.
--
-- The light of a glass button: white over the upper part of the icon, brightest at the top and fading
-- down to a curved lower edge, lowest in the middle; and a faint shade of black rising towards the
-- foot. The crossbar is drawn with a D3DX sprite, so the shape is made once into a texture for each
-- size of icon, as frameshadow.lua makes its shadow, and drawn over each icon with one sprite draw.
local d3d8 = require('d3d8');
local ffi = require('ffi');

local gloss = {};

local SAMPLES = 2;                 -- each pixel is looked at SAMPLES by SAMPLES times, for a smooth edge
local LIGHT_TOP, LIGHT_EDGE = 0.45, 0.10; -- the white's alpha at the top, and at the curved edge
local CENTRE_Y, RADIUS_X, RADIUS_Y = -0.35, 0.95, 0.85; -- the light's ellipse, in parts of the icon
local SHADE_FROM, SHADE = 0.70, 0.18; -- the shade starts this far down, and is this dark at the foot

local made = {};                   -- 'width:height' -> { Texture, Rect }, or false where it could not be made
local d3dwhite = d3d8.D3DCOLOR_ARGB(255, 255, 255, 255);
local unit = ffi.new('D3DXVECTOR2', { 1.0, 1.0 });
local vec_position = ffi.new('D3DXVECTOR2', { 0, 0 });

local function PowerOfTwo(n)
    local p = 1;
    while p < n do p = p * 2; end
    return p;
end

-- The light (white's alpha) and shade (black's alpha) at a point, u and v from 0 to 1 across the icon
function gloss.At(u, v)
    local dx, dy = (u - 0.5) / RADIUS_X, (v - CENTRE_Y) / RADIUS_Y;
    if dx * dx + dy * dy <= 1 then
        -- from the top down to the ellipse's edge below this point
        local edge = CENTRE_Y + RADIUS_Y * math.sqrt(math.max(0, 1 - dx * dx));
        local t = math.max(0, math.min(1, v / edge));
        return LIGHT_TOP + (LIGHT_EDGE - LIGHT_TOP) * t, 0;
    end
    if v > SHADE_FROM then
        return 0, SHADE * (v - SHADE_FROM) / (1 - SHADE_FROM);
    end
    return 0, 0;
end

-- The gloss of an icon width by height, in a texture
local function Make(width, height)
    local w, h = math.max(1, math.floor(width + 0.5)), math.max(1, math.floor(height + 0.5));
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
            local light, shade = 0, 0;
            for sy = 1, SAMPLES do
                local v = (y + (sy - 0.5) / SAMPLES) / h;
                for sx = 1, SAMPLES do
                    local l, s = gloss.At((x + (sx - 0.5) / SAMPLES) / w, v);
                    light, shade = light + l, shade + s;
                end
            end
            light, shade = light / (SAMPLES * SAMPLES), shade / (SAMPLES * SAMPLES);
            -- white where there is light, black where there is shade; the two never meet
            if light > 0 then
                row[x] = math.floor(light * 255 + 0.5) * 0x1000000 + 0xFFFFFF;
            else
                row[x] = math.floor(shade * 255 + 0.5) * 0x1000000;
            end
        end
    end
    texture.lpVtbl.UnlockRect(texture, 0);

    return { Texture = texture, Rect = ffi.new('RECT', { 0, 0, w, h }) };
end

-- Draws the gloss over an icon width by height at x, y
function gloss.Draw(sprite, x, y, width, height)
    local size = ('%d:%d'):format(math.floor(width + 0.5), math.floor(height + 0.5));
    local shine = made[size];
    if shine == nil then
        local built, result = pcall(Make, width, height);
        shine = built and result or false;
        made[size] = shine;
    end
    if not shine then return; end
    vec_position.x, vec_position.y = x, y;
    sprite:Draw(shine.Texture, shine.Rect, unit, nil, 0.0, vec_position, d3dwhite);
end

return gloss;
