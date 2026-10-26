-- winxi.camera: the camera the namehook plugin (1.44 and newer) places names with, for anything an addon
-- puts over the world: the same view, projection and picture, and lens's warp when it bends the world, so a
-- point lands where a name at it would.
--
--   camera.Get()                   this frame's camera (the plugin's block), or nil and why not
--   camera.Project(x, y, z[, cam]) where the world point (x, y, z) shows: x and y in imgui's pixels across
--                                  the screen, the depth in the picture (0 near to 1 far), and whether it
--                                  is in front of the camera and inside the picture; nil behind the camera
--
-- The plugin readies the camera as the game draws its first name of a frame: a frame with no names (the
-- game's names switched off) leaves last frame's, and Get says nil once it is more than two frames old.
local bit = require('bit');
local ffi = require('ffi');
local abi = require('winxi.abi');
local nameplates = require('winxi.nameplates');
local lens = require('winxi.lens');

ffi.cdef[[
    typedef struct {
        char     Magic[16];
        uint32_t Version;
        uint32_t Size;
        uint32_t Frame;
        uint32_t Valid;
        float    View[16];
        float    Projection[16];
        float    ViewProjection[16];
        float    ViewportX, ViewportY, ViewportWidth, ViewportHeight, ViewportMinZ, ViewportMaxZ;
        uint32_t Lens;
        uint32_t LensMode;
        float    LensStrength, LensTanH, LensTanV;
    } namehook_camera_t;
]];

local camera = {};

local MAGIC = '4E414D45484F4F4B43414D4552410000'; -- "NAMEHOOKCAMERA" and the two 0s after it
local VERSION = 1;
local LOOK_EVERY = 1;
local FRESH = 2; -- frames a camera is good for

local block, blockGeneration, why, lookedAt = nil, nil, 'unloaded', -LOOK_EVERY;

local problems = {
    unloaded = 'The namehook plugin is not loaded: /load namehook',
    old      = 'The namehook plugin does not share its camera: it is older than 1.44.',
    mismatch = 'The namehook plugin shares its camera another way than this addon reads: one of the two is older than the other.',
    stale    = 'The namehook plugin has not placed a name lately (the game\'s names switched off?), so its camera is not this frame\'s.',
};

local function Find()
    local names = nameplates.Hook();
    if (names == nil) then
        block, why, lookedAt = nil, 'unloaded', -LOOK_EVERY;
        return nil;
    end
    local generation = nameplates.Generation();
    if (block ~= nil and blockGeneration ~= generation) then
        block, lookedAt = nil, -LOOK_EVERY;
    end
    if (block == nil) then
        local now = os.clock();
        if (now - lookedAt < LOOK_EVERY) then return nil; end
        lookedAt = now;
        local found = ashita.memory.find(nameplates.Plugin .. '.dll', 0, MAGIC, 0, 0);
        if (found == nil or found == 0) then why = 'old'; return nil; end
        local candidate = ffi.cast('namehook_camera_t*', found);
        if (not abi.Accepts(candidate, 'namehook_camera_t', VERSION)) then why = 'mismatch'; return nil; end
        block, blockGeneration = candidate, generation;
    end
    return block, names;
end

function camera.Get()
    local cam, names = Find();
    if (cam == nil) then return nil, problems[why]; end
    if (cam.Valid == 0 or bit.band(names.Frame - cam.Frame, 0xFFFFFFFF) > FRESH) then return nil, problems.stale; end
    return cam;
end

local imgui = nil;

function camera.Project(x, y, z, cam)
    cam = cam or camera.Get();
    if (cam == nil) then return nil; end
    local m = cam.ViewProjection;
    local w = x * m[3] + y * m[7] + z * m[11] + m[15];
    if (w <= 0.01) then return nil; end
    local depth = (x * m[2] + y * m[6] + z * m[10] + m[14]) / w;
    -- across and down the picture, 0 to 1, as the plugin places a name
    local s = (1 + (x * m[0] + y * m[4] + z * m[8] + m[12]) / w) * 0.5;
    local t = (1 - (x * m[1] + y * m[5] + z * m[9] + m[13]) / w) * 0.5;
    if (cam.Lens ~= 0) then
        s, t = lens.ScreenOf(s, t, cam.LensTanH, cam.LensTanV, tonumber(cam.LensMode), cam.LensStrength);
    end
    -- the picture is stretched over the whole screen
    imgui = imgui or require('imgui');
    local display = imgui.GetIO().DisplaySize;
    local inside = depth >= 0 and depth <= 1 and s >= 0 and s <= 1 and t >= 0 and t <= 1;
    return s * display.x, t * display.y, depth, inside;
end

return camera;
