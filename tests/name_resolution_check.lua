-- Independent window/menu/background dimensions; no game or GPU required.
local ffi = require('ffi')
local imgui = require('imgui')
local nameplates = require('winxi.nameplates')
local hook = ffi.new('namehook_t')
ffi.cdef('void* mmap(void*, size_t, int, int, int, long); int munmap(void*, size_t);')
local low = ffi.C.mmap(nil, ffi.sizeof('namehook_draw_t'), 3, 0x62, -1, 0)
assert(low ~= ffi.cast('void*', -1))
local draw = ffi.cast('namehook_draw_t*', low)
hook.Hooked = 1
hook.Draw = tonumber(ffi.cast('uintptr_t', draw))
draw.QuadsMax = 16384
local oldGetIO = imgui.GetIO
local display = { x = 1920, y = 1080 }
imgui.GetIO = function() return { DisplaySize = display } end
local cases = 0
local function close(a, b, message)
    assert(math.abs(a - b) < 0.002, message)
end
local function check(outputW, outputH, menuW, menuH, targetW, targetH)
    display.x, display.y = outputW, outputH
    hook.Width, hook.Height = menuW, menuH
    hook.TargetWidth, hook.TargetHeight = targetW, targetH
    hook.Frame = hook.Frame + 1
    local scale = nameplates.BeginDrawing(hook, true)
    close(scale, targetH / outputH, 'vertical scale')
    assert(draw.Frame == hook.Frame and draw.QuadCount == 0)
    assert(nameplates.BeginName(5, 1, scale, 0))
    -- Both a centred square and an asymmetric detail/icon offset.
    nameplates.Quad(-10 * scale, -10 * scale, 10 * scale, 10 * scale,
        0, 0, 1, 1, 0xFFFFFFFF, 0, true)
    nameplates.Quad(13 * scale, 17 * scale, 18 * scale, 24 * scale,
        0, 0, 1, 1, 0xFFFFFFFF, 0, false)
    nameplates.EndName()
    local q = draw.Quads[0]
    close((q.X1 - q.X0) * outputW / targetW, 20, 'square width')
    close((q.Y1 - q.Y0) * outputH / targetH, 20, 'square height')
    close(q.X0 + q.X1, 0, 'centred name')
    q = draw.Quads[1]
    close(q.X0 * outputW / targetW, 13, 'horizontal spacing')
    close(q.Y0 * outputH / targetH, 17, 'vertical spacing')
    -- Native renderer applies this optional ratio to its X outline offset.
    close(draw.Entities[5].Edge * (draw.Reserved / 65536) * outputW / targetW,
        1, 'outline width')
    close(draw.Entities[5].Edge * outputH / targetH, 1, 'outline height')
    cases = cases + 1
end
local sizes = {
    { 640, 480 }, { 1280, 720 }, { 1920, 1080 }, { 1920, 1200 },
    { 2560, 1080 }, { 3440, 1440 }, { 3840, 2160 }, { 5120, 1440 },
    { 1080, 1920 }, { 2048, 2048 }, { 7680, 4320 },
}
-- Cartesian product: menu dimensions must have no effect on output geometry.
for _, output in ipairs(sizes) do
    for _, menu in ipairs(sizes) do
        for _, target in ipairs(sizes) do
            check(output[1], output[2], menu[1], menu[2], target[1], target[2])
        end
    end
end
-- Minimized/unknown output falls back to the client's coordinates.
display.x, display.y = 0, 0
hook.Width, hook.Height = 640, 480
hook.TargetWidth, hook.TargetHeight = 1280, 960
assert(nameplates.BeginDrawing(hook, true) == 2)
-- Unknown render dimensions safely fall back and reset the previous fit.
hook.TargetHeight = 0
assert(nameplates.BeginDrawing(hook, true) == 1 and draw.Reserved == 0)
-- Resize back into a strongly nonuniform render target without stale state.
check(2560, 1080, 640, 480, 2048, 2048)
-- Existing library clients still submit unmodified target coordinates.
hook.Width, hook.TargetWidth = 640, 1280
assert(nameplates.BeginDrawing(hook) == 2 and draw.Reserved == 0)
nameplates.BeginName(5, 1, 0, 0)
nameplates.Quad(1, 2, 3, 4, 0, 0, 1, 1, 0xFFFFFFFF)
assert(draw.Quads[0].X0 == 1 and draw.Quads[0].X1 == 3)
-- Optional AA changes flags only; a textured quad asking for it gets it too (namehook 1.37 feathers it,
-- an older one draws it hard), and nothing that does not ask is feathered.
nameplates.Quad(1, 2, 3, 4, 0.5, 0.5, 0.5, 0.5, 0xFFFFFFFF, 0, false, nil, true)
assert(draw.Quads[1].Flags == 4 and draw.Quads[1].X0 == 1 and draw.Quads[1].X1 == 3)
nameplates.Quad(1, 2, 3, 4, 0, 0, 1, 1, 0xFFFFFFFF, 0, false, nil, true)
assert(draw.Quads[2].Flags == 4, 'a textured quad can ask for the rectangle AA (the textured bars)')
nameplates.Quad(1, 2, 3, 4, 0.5, 0.5, 0.5, 0.5, 0xFFFFFFFF, 0, true, 0.75, true)
assert(draw.Quads[3].Flags == 3 and draw.Quads[3].Reserved == 191, 'outlined quads retain existing edge flags')
nameplates.Quad(1, 2, 3, 4, 0, 0, 1, 1, 0xFFFFFFFF, 3, true, 1, nil, true)
assert(draw.Quads[4].Flags == 11 and draw.Quads[4].Reserved == 255, 'aggro glyphs can request a full-strength tight edge')
nameplates.Quad(1, 2, 3, 4, 0, 0, 1, 1, 0xFFFFFFFF, 3, false, nil, nil, true)
assert(draw.Quads[5].Flags == 0, 'tight style has no effect without an outline')
nameplates.Quad(1, 2, 3, 4, 0, 0, 1, 1, 0xFFFFFFFF, 3, true, .5, nil, true, 2.5)
assert(draw.Quads[6].Flags == 27 and draw.Quads[6].Reserved == 640 * 256 + 128,
    'independent fractional radius preserves explicit opacity and tight style')
nameplates.EndName()
for slot=0,7 do nameplates.SetTexture(slot,0x12340000+slot) end
hook.Frame=0
nameplates.ClearDrawing(hook)
assert(draw.QuadCount==0 and draw.Frame==4294967287, 'deactivation invalidates the batch across frame wrap')
for slot=0,7 do assert(draw.Textures[slot]==0, 'unpublish pointers before releasing GPU owners') end
nameplates.SetTexture(0,0x9999)
assert(draw.Textures[0]==0, 'no cached writer survives ClearDrawing')
nameplates.ClearDrawing() -- no plugin: never dereference the previous DLL/draw pointer
imgui.GetIO = oldGetIO
ffi.C.munmap(low, ffi.sizeof('namehook_draw_t'))
H.print(('name resolution correction: %d combinations passed'):format(cases), true)
