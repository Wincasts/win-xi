-- winxi.camera against namehook 1.44's camera block: a point placed as the plugin places a name (the view and
-- projection together, the picture stretched over the screen), through lens's warp when it bends the world;
-- nothing behind the camera; none from a camera more than two frames old, an older namehook or none at all.
package.path = 'addons/libs/?.lua;' .. package.path
local ffi = require('ffi')

local failures = 0
local function check(ok, what) if not ok then failures = failures + 1; print('FAILED: ' .. what) end end
local function near(a, b) return a ~= nil and math.abs(a - b) < 1e-4 end

package.loaded.imgui = { GetIO = function() return { DisplaySize = { x = 1920, y = 1080 } } end }
local loaded, clock = { namehook = true }, 0
os.clock = function() clock = clock + 2; return clock end
local addresses = {}
AshitaCore = { GetPluginManager = function() return { IsLoaded = function(_, name) return loaded[name] == true end } end }
ashita = { memory = { find = function(module, _, magic) return addresses[module .. ':' .. magic] or 0 end } }

local nameplates = require('winxi.nameplates')
nameplates.Module = function() return 1, 0, 0 end
local camera = require('winxi.camera')
local lens = require('winxi.lens')

local names = ffi.new('namehook_t')
names.Version, names.Size, names.NameSize, names.Hooked, names.Frame = 3, ffi.sizeof(names), ffi.sizeof('namehook_name_t'), 1, 100
addresses['namehook.dll:4E414D45484F4F4B0000000000000000'] = tonumber(ffi.cast('uintptr_t', ffi.cast('void*', names)))

check(camera.Get() == nil, 'no camera block (an older namehook): none')
check(select(2, camera.Get()):find('1.44', 1, true) ~= nil, '... and it says which namehook is needed')

local cam = ffi.new('namehook_camera_t')
cam.Version, cam.Size, cam.Frame, cam.Valid = 1, ffi.sizeof(cam), 100, 1
-- a camera that maps x and y straight across the picture and z to the depth: ndc (x, y), depth z
for i = 0, 15 do cam.ViewProjection[i] = 0 end
cam.ViewProjection[0], cam.ViewProjection[5], cam.ViewProjection[10], cam.ViewProjection[15] = 1, 1, 1, 1
addresses['namehook.dll:4E414D45484F4F4B43414D4552410000'] = tonumber(ffi.cast('uintptr_t', ffi.cast('void*', cam)))

check(camera.Get() ~= nil, 'this frame\'s camera')
local x, y, depth, inside = camera.Project(0, 0, 0.5)
check(near(x, 960) and near(y, 540) and near(depth, 0.5) and inside, 'the middle of the world in the middle of the screen')
x, y = camera.Project(0.5, 0.5, 0.5)
check(near(x, 1440) and near(y, 270), 'up and right: three quarters across, a quarter down')
local _, _, _, outside = camera.Project(2, 0, 0.5)
check(outside == false, 'beyond the picture: placed, but not inside')
cam.ViewProjection[15] = 0; cam.ViewProjection[11] = 1 -- w from z: z of 0 is the camera's own plane
check(camera.Project(0, 0, 0) == nil, 'nothing behind the camera')
cam.ViewProjection[15] = 1; cam.ViewProjection[11] = 0

-- lens warping: the point where lens's warp shows it
cam.Lens, cam.LensMode, cam.LensStrength, cam.LensTanH, cam.LensTanV = 1, 0, 0.5, 2, 1
local s, t = lens.ScreenOf(0.75, 0.25, 2, 1, 0, 0.5)
x, y = camera.Project(0.5, 0.5, 0.5)
check(near(x, s * 1920) and near(y, t * 1080) and not near(x, 1440), 'under lens: where its warp shows the point')

names.Frame = 103
check(camera.Get() == nil and select(2, camera.Get()):find('lately', 1, true) ~= nil, 'three frames old: none, and why')
names.Frame = 102
check(camera.Get() ~= nil, 'two frames old: still')
cam.Valid = 0
check(camera.Get() == nil, 'not valid: none')
cam.Valid = 1
cam.Version = 2
loaded.namehook = false; nameplates.Hook(); loaded.namehook = true
check(camera.Get() == nil, 'another Version: none')
cam.Version = 1
loaded.namehook = false
check(camera.Get() == nil, 'no namehook: none')

if failures == 0 then
    print('winxi camera: placed as a name is, through lens\'s warp, nothing behind; stale, invalid, older, other Version and no namehook give none passed')
else
    os.exit(1)
end
