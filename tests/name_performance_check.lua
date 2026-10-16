-- Synthetic CPU benchmark, not in-game/GPU timing. Run via tests/harness.lua.
local ffi = require('ffi')
local imgui = require('imgui')
local custom = require('custom')
local plates = require('winxi.nameplates')
local levels = require('levels')
ffi.cdef([[
void* mmap(void*, size_t, int, int, int, long);
int munmap(void*, size_t);
struct name_bench_timespec { long tv_sec; long tv_nsec; };
int clock_gettime(int, struct name_bench_timespec*);
]])
local stamp = ffi.new('struct name_bench_timespec[1]')
local function now()
    assert(ffi.C.clock_gettime(1, stamp) == 0)
    return tonumber(stamp[0].tv_sec) + tonumber(stamp[0].tv_nsec) / 1e9
end
local low = ffi.C.mmap(nil, ffi.sizeof('namehook_draw_t'), 3, 0x62, -1, 0)
assert(low ~= ffi.cast('void*', -1))
local draw = ffi.cast('namehook_draw_t*', low)
draw.QuadsMax = 16384
local hook = ffi.new('namehook_t')
hook.Hooked, hook.Draw = 1, tonumber(ffi.cast('uintptr_t', low))
hook.Width, hook.Height, hook.TargetWidth, hook.TargetHeight = 1920, 1080, 1920, 1080
local options = {}
custom.Defaults(options)
options.showCheckDetails[1], options.showIcons[1], options.showStars[1] = false, false, false
-- [aggro] is in the preferred format: its sign must not cost the names their compiled loop
custom.SetSheets(0x7777, 0x8888)
options.monsterFormat[1] = '[aggro][name] [letter]'
local decoded, prepared, uploads = 0, 0, 0
local glyph = { X0 = 0, Y0 = 0, X1 = 8, Y1 = 12, U0 = 0, V0 = 0, U1 = 1, V1 = 1, AdvanceX = 8, Visible = 1 }
local baked = { FindGlyph = function() decoded = decoded + 1; return glyph end }
local font = { ContainerAtlas = { TexData = { UniqueID = 2, Status = 0, Width = 512, Height = 256 } } }
imgui.GetFont = function() return font end
imgui.GetFontBaked = function() return baked end
imgui.PushFont, imgui.PopFont = function() end, function() end
imgui.AddFontFromFileTTF = function() return font end
imgui.GetIO = function() return { DisplaySize = { x = 1920, y = 1080 } } end
local atlas = require('gdi.atlas')
local source = require('gdi.image').new(8, 12):fill(function() return 0.5 end)
atlas.read = function() prepared = prepared + 1; return source end
atlas.upload = function() uploads = uploads + 1; return ffi.cast('IDirect3DTexture8*', 0x5678) end
local indices = {}
for i = 0, 255 do
    local name = hook.Names[i]
    name.EntityIndex, name.ServerId = i + 1, 0x1000 + i
    name.Category, name.Flags = plates.Category.Monster, plates.Flag.Wanted
    name.Scale, name.NameColor = 0.25 + (i % 4) * 0.25, 0x80808080
    ffi.copy(name.Name, 'Goblin'); ffi.copy(name.Text, 'Goblin')
    indices[i + 1] = { Name = 'Goblin' }
end
levels.Set({ Indices = indices, Names = {} })
local frames = tonumber(os.getenv('NAME_BENCH_FRAMES')) or 500
local function render()
    hook.Frame = hook.Frame + 1
    custom.Frame(options, hook)
end
for _, letters in ipairs({ false, true }) do
    options.showMobLetter[1] = letters
    for _, count in ipairs({ 0, 32, 128, 256 }) do
        hook.Count = count
        for _ = 1, 20 do render() end
        collectgarbage('collect')
        local start = now()
        for _ = 1, frames do render() end
        local elapsed = (now() - start) * 1000 / frames
        collectgarbage('collect'); collectgarbage('stop')
        local memory, readsBefore, uploadsBefore = collectgarbage('count'), prepared, uploads
        local decodedBefore = decoded
        for _ = 1, 50 do render() end
        local allocation = (collectgarbage('count') - memory) / 50
        collectgarbage('restart')
        assert(prepared == readsBefore and uploads == uploadsBefore, 'warm frames must not read/upload badge textures')
        assert(decoded - decodedBefore <= (letters and 4 or 3) * 50,
            'warm frames must only probe font rungs, not reread indicator A-Z')
        H.print(('name CPU fixture: %3d names, letters %-5s | %.3f ms/frame | %.2f KiB/frame allocated | %d glyph lookups/frame | %d quads'):format(
            count, tostring(letters), elapsed, allocation, (decoded - decodedBefore) / 50, draw.QuadCount))
    end
end
ffi.C.munmap(low, ffi.sizeof('namehook_draw_t'))
