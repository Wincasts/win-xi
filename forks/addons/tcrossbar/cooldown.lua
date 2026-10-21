-- winxi: the cooldown swipe and the low MP and low TP tints over each macro element's icon.
--
-- The swipe darkens the part of the icon still to come back: a wedge from 12 o'clock that shrinks
-- clockwise as the recast runs down, gone when it is ready. The crossbar is drawn with a D3DX sprite,
-- so the wedge is made into a texture for each of STEPS steps of the turn, for each size of icon, as
-- each is first wanted, and the nearest step drawn with one sprite draw, faded by Swipe Opacity.
--
-- A tint is a colour over the whole icon, one plain white texture drawn in the colour: Low MP Color
-- over a spell or ability whose MP cost is not met, Low TP Color over a weapon skill or ability whose
-- TP cost is not met.
local d3d8 = require('d3d8');
local ffi = require('ffi');

local cooldown = {};

cooldown.STEPS = 60;  -- steps of the turn the swipe is drawn in
local SAMPLES = 3;    -- each pixel is looked at SAMPLES by SAMPLES times, for a smooth edge

local wedges = {};    -- 'width:height' -> { [step] = { Texture, Rect } or false }
local white = nil;    -- the plain texture for the tints, or false where it could not be made
local WHITE_SIZE = 8;
local scale = ffi.new('D3DXVECTOR2', { 1.0, 1.0 });
local unit = ffi.new('D3DXVECTOR2', { 1.0, 1.0 });
local vec_position = ffi.new('D3DXVECTOR2', { 0, 0 });

local function PowerOfTwo(n)
    local p = 1;
    while p < n do p = p * 2; end
    return p;
end

-- A texture w by h, each pixel's colour (ARGB) from Pixel(x, y); false where it could not be made
local function Make(w, h, Pixel)
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
            row[x] = Pixel(x, y);
        end
    end
    texture.lpVtbl.UnlockRect(texture, 0);
    return { Texture = texture, Rect = ffi.new('RECT', { 0, 0, w, h }) };
end

-- How far round a point is from 12 o'clock, clockwise, 0 to 1, about the middle of a w by h icon
local function Turn(px, py, w, h)
    local angle = math.atan2(px - w / 2, h / 2 - py); -- 0 straight up, growing clockwise
    if angle < 0 then angle = angle + 2 * math.pi; end
    return angle / (2 * math.pi);
end

-- Whether a point is under the wedge with left (0 to 1) of the turn still to come back: the part
-- of the turn from 1 - left round to 12 o'clock
function cooldown.Covered(px, py, w, h, left)
    if left >= 1 then return true; end
    if left <= 0 then return false; end
    return Turn(px, py, w, h) >= 1 - left;
end

-- The step of the turn drawn for left of it still to come back: 0 for none, STEPS for all
function cooldown.Step(left)
    if left <= 0 then return 0; end
    return math.max(1, math.min(cooldown.STEPS, math.ceil(left * cooldown.STEPS - 1e-9)));
end

local function MakeWedge(w, h, step)
    local left = step / cooldown.STEPS;
    return Make(w, h, function(x, y)
        local covered = 0;
        for sy = 1, SAMPLES do
            local py = y + (sy - 0.5) / SAMPLES;
            for sx = 1, SAMPLES do
                if cooldown.Covered(x + (sx - 0.5) / SAMPLES, py, w, h, left) then covered = covered + 1; end
            end
        end
        return math.floor(covered / (SAMPLES * SAMPLES) * 255 + 0.5) * 0x1000000; -- black, at that alpha
    end);
end

local function Alpha(percent)
    return math.floor(math.max(0, math.min(100, tonumber(percent) or 0)) / 100 * 255 + 0.5);
end

-- Draws the swipe over an icon width by height at x, y: left (0 to 1) of the recast still to run,
-- at opacity percent
function cooldown.DrawSwipe(sprite, x, y, width, height, left, opacity)
    local step = cooldown.Step(left);
    local alpha = Alpha(opacity);
    if step == 0 or alpha <= 0 then return; end
    local w, h = math.max(1, math.floor(width + 0.5)), math.max(1, math.floor(height + 0.5));
    local size = ('%d:%d'):format(w, h);
    local steps = wedges[size];
    if steps == nil then
        steps = {};
        wedges[size] = steps;
    end
    local wedge = steps[step];
    if wedge == nil then
        local built, result = pcall(MakeWedge, w, h, step);
        wedge = built and result or false;
        steps[step] = wedge;
    end
    if not wedge then return; end
    vec_position.x, vec_position.y = x, y;
    sprite:Draw(wedge.Texture, wedge.Rect, unit, nil, 0.0, vec_position, d3d8.D3DCOLOR_ARGB(alpha, 255, 255, 255));
end

-- Draws a colour ({ r, g, b, a }, 0 to 1) over an icon width by height at x, y
function cooldown.DrawTint(sprite, x, y, width, height, color)
    if type(color) ~= 'table' then return; end
    local alpha = math.floor(math.max(0, math.min(1, tonumber(color[4]) or 0)) * 255 + 0.5);
    if alpha <= 0 then return; end
    if white == nil then
        local built, result = pcall(Make, WHITE_SIZE, WHITE_SIZE, function() return 0xFFFFFFFF; end);
        white = built and result or false;
    end
    if not white then return; end
    local function Channel(value) return math.floor(math.max(0, math.min(1, tonumber(value) or 0)) * 255 + 0.5); end
    scale.x, scale.y = width / WHITE_SIZE, height / WHITE_SIZE;
    vec_position.x, vec_position.y = x, y;
    sprite:Draw(white.Texture, white.Rect, scale, nil, 0.0, vec_position,
        d3d8.D3DCOLOR_ARGB(alpha, Channel(color[1]), Channel(color[2]), Channel(color[3])));
end

return cooldown;
