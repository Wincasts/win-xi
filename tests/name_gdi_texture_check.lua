-- Exercise the actual readback helper, including direct vtable descriptor ownership.
package.path = 'addons/name/?.lua;' .. package.path
local ffi = require('ffi')
ffi.cdef[[
    enum { S_OK = 0, D3DFMT_A8R8G8B8 = 21 };
    typedef struct { int Format; uint32_t Width, Height; } D3DSURFACE_DESC;
    typedef struct { int32_t Pitch; void* pBits; } D3DLOCKED_RECT;
]]
package.loaded.d3d8 = { get_error = tostring }
local image = require('gdi.image')
local atlas = require('gdi.atlas')
local pixels = ffi.new('uint32_t[8]', { 1, 2, 99, 99, 3, 4, 99, 99 })
local pitch, width, unlocks = 16, 2, 0
local tex = {
    GetLevelDesc = function() error('unsafe wrapper must not be used') end,
    LockRect = function() error('unsafe wrapper must not be used') end,
    UnlockRect = function() unlocks = unlocks + 1 end,
    lpVtbl = {
        GetLevelDesc = function(_, _, out)
            out[0].Format, out[0].Width, out[0].Height = 21, width, 2
            return 0
        end,
        LockRect = function(_, _, out)
            out[0].Pitch, out[0].pBits = pitch, pixels
            return 0
        end,
    },
}
local originalNew = image.new
image.new = function(w, h)
    collectgarbage('collect') -- descriptor dimensions must already be standalone numbers
    return originalNew(w, h)
end
local img = assert(atlas.read(tex))
assert(img.w == 2 and img.h == 2 and unlocks == 1)
assert(img.px[0] == 1 and img.px[1] == 2 and img.px[2] == 3 and img.px[3] == 4)
pitch = 4
local rejected, err = atlas.read(tex)
assert(rejected == nil and err:find('pitch') and unlocks == 2)
width = 65535
rejected, err = atlas.read(tex)
assert(rejected == nil and err:find('dimensions') and unlocks == 2)
-- Deterministic release must remove the GC finalizer to avoid double Release.
ffi.cdef('typedef struct { int unused; } name_test_owned_texture;')
local releases, finalizers = 0, 0
ffi.metatype('name_test_owned_texture', { __index = { Release = function() releases = releases + 1 end } })
local owned = ffi.gc(ffi.new('name_test_owned_texture'), function(t)
    finalizers = finalizers + 1
    t:Release()
end)
atlas.release(owned)
assert(releases == 1 and finalizers == 0)
owned = nil
collectgarbage('collect'); collectgarbage('collect')
assert(releases == 1 and finalizers == 0, 'manual release must not run the old finalizer later')
atlas.release(nil)
print('GDI readback/release: descriptor ownership, GC, pitch/bounds and no double Release\ttrue')
