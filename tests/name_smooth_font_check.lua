-- Prefiltered masks retain hinted layout, bold stroke, badges and safe fallbacks.
local ffi = require('ffi')
local imgui = require('imgui')
local custom = require('custom')
local plates = require('winxi.nameplates')
local badges = require('letter_badges')
local levels = require('levels')
local filtered = require('filtered_text')
local originalFilteredPrepare = filtered.Prepare
-- Real GPU readback is tested separately against mocked upload/read functions.
-- Begin with the direct-raster fallback while a filtered atlas is unavailable.
filtered.Prepare = function() return nil end
ffi.cdef('void* mmap(void*, size_t, int, int, int, long); int munmap(void*, size_t);')
local bytes = ffi.sizeof('namehook_draw_t')
local low = ffi.C.mmap(nil, bytes + 16, 3, 0x62, -1, 0)
assert(low ~= ffi.cast('void*', -1))
local draw = ffi.cast('namehook_draw_t*', low)
local sentinel = ffi.cast('uint8_t*', low) + bytes
ffi.fill(sentinel, 16, 0xA5)
draw.QuadsMax = 16384
local hook = ffi.new('namehook_t')
hook.Hooked, hook.Draw = 1, tonumber(ffi.cast('uintptr_t', low))
hook.Width, hook.Height, hook.TargetWidth, hook.TargetHeight = 1920, 1080, 1920, 1080
hook.Count, hook.FontTexture = 2, 0x12340000
local o = H.options()
custom.Defaults(o)
assert(o.fontSmooth[1] == false, 'Smooth Font is opt-in')
o.fontSmooth = 'bad setting'; custom.Settle(o)
assert(o.fontSmooth[1] == false, 'invalid saved quality mode is made safe')
o.fontSmooth = T{ true }; custom.Settle(o)
assert(o.fontSmooth[1], 'valid saved quality mode survives settling')
o.fontSmooth[1] = false
o.fontSize[1], o.minSize[1] = 20, 10
o.showCheckDetails[1], o.showStars[1], o.showStatuses[1], o.showHealthBar[1] = false, false, false, false
o.nameFormat[1], o.monsterFormat[1] = '[name]', '[name][letters]'
local font = { ContainerAtlas = { TexData = { UniqueID = 90, Status = 0, Width = 1024, Height = 1024 } } }
imgui.GetFont = function() return font end
imgui.GetIO = function() return { DisplaySize = { x = 1920, y = 1080 } } end
local size, stack, requested, reads = 15, {}, {}, {}
local shift, missingLarge = 0, false
imgui.PushFont = function(_, height)
    stack[#stack + 1] = size
    size = height
    requested[height] = true
end
imgui.PopFont = function() size = table.remove(stack) end
imgui.GetFontBaked = function()
    local height = size
    if missingLarge and height == 80 then return nil end
    return { FindGlyph = function(_, byte)
        local key = height .. ':' .. byte
        reads[key] = (reads[key] or 0) + 1
        -- Deliberately NOT scale-proportional metrics: using the 4x bearings or
        -- advance divided by two would still move the nameplate in this fixture.
        return { X0 = 1 + height * 0.025, Y0 = 2 + height * 0.01,
            X1 = height * 0.6, Y1 = height * 0.8, AdvanceX = height * 0.65,
            U0 = height / 1000 + shift, V0 = 0.1, U1 = height / 1000 + shift + 0.01,
            V1 = 0.15, Visible = 1 }
    end }
end
local badgeDefinitions
badges.Prepare = function(_, definitions)
    badgeDefinitions = definitions
    local regions = {}
    for _, definition in ipairs(definitions) do
        regions[definition.height] = { A = { width = 14, height = 14, padding = 1,
            top = 0, uv = { w = 16, h = 16, u0 = 0.6, v0 = 0.6, u1 = 0.7, v1 = 0.7 } } }
    end
    return { address = 0x56780000, regions = regions }
end
local hp = 100
local memory = AshitaCore:GetMemoryManager()
AshitaCore.GetMemoryManager = function() return memory end
memory.GetEntity = function() return {
    GetServerId = function(_, index) return 0x1000 + index end,
    GetHPPercent = function() return hp end,
    GetRenderFlags0 = function() return 0x200 end,
} end
levels.Set({ Indices = { [2] = { Name = 'AV' } }, Names = {} })
for i = 0, 1 do
    local name = hook.Names[i]
    name.EntityIndex, name.ServerId = i + 1, 0x1001 + i
    name.Category = i == 0 and plates.Category.Player or plates.Category.Monster
    name.Flags, name.Scale, name.NameColor = plates.Flag.Wanted, 1, 0x80408020
    ffi.copy(name.Name, 'AV'); ffi.copy(name.Text, 'AV')
end
local function render()
    hook.Frame = hook.Frame + 1
    H.wait(0.03)
    assert(custom.Frame(o, hook) == nil)
    assert(#stack == 0, 'font stack must stay balanced')
    for i = 0, 15 do assert(sentinel[i] == 0xA5, 'no draw-buffer overrun') end
    local snapshot = {}
    for entity = 1, 2 do
        local entry = draw.Entities[entity]
        local copy = { edge = tonumber(entry.Edge), alpha = tonumber(entry.Alpha), quads = {} }
        for i = entry.First, entry.First + entry.Count - 1 do
            local q = draw.Quads[i]
            copy.quads[#copy.quads + 1] = { x0 = q.X0, y0 = q.Y0, x1 = q.X1, y1 = q.Y1,
                u0 = q.U0, color = tonumber(q.Color), texture = tonumber(q.Texture), flags = tonumber(q.Flags) }
        end
        snapshot[entity] = copy
    end
    return snapshot
end
local function sameLayout(a, b)
    for entity = 1, 2 do
        assert(a[entity].edge == b[entity].edge and a[entity].alpha == b[entity].alpha)
        assert(#a[entity].quads == #b[entity].quads, 'quality does not add glyph copies')
        for index, q in ipairs(a[entity].quads) do
            local other = b[entity].quads[index]
            for _, field in ipairs({ 'x0', 'y0', 'x1', 'y1', 'color', 'texture', 'flags' }) do
                assert(q[field] == other[field], 'quality changed ' .. field)
            end
        end
    end
end
local normal = render()
assert(not requested[80], 'normal mode does not request the 4x source')
local badgeUv = badgeDefinitions[1].glyphs.A[5]
o.fontSmooth[1] = true
local smooth = render()
sameLayout(normal, smooth)
assert(requested[80] and math.abs(smooth[1].quads[1].u0 - 0.08) < 0.00001, 'fallback text samples the 4x source')
assert(badgeDefinitions[1].height == 20 and badgeDefinitions[1].glyphs.A[5] == badgeUv,
    'badge source glyphs are not supersampled again')
assert(smooth[2].quads[3].texture == 5 and smooth[2].quads[3].u0 == normal[2].quads[3].u0,
    'badge atlas and UVs stay unchanged')
local warmReads = reads['80:86']
for _ = 1, 30 do sameLayout(smooth, render()) end
assert(reads['80:86'] == warmReads, 'warm frames reuse the cached source glyph/run')
o.fontSmooth[1] = false
sameLayout(normal, render())
o.fontBold[1] = true
local bold = render()
o.fontSmooth[1] = true
local smoothBold = render()
sameLayout(bold, smoothBold)
assert(smoothBold[1].quads[2].x0 - smoothBold[1].quads[1].x0 == 1,
    'Bold keeps its existing one-pixel stroke in smooth mode')
o.fontBold[1] = false
-- UV movement without a new texture ID must still invalidate the smooth runs.
shift = 0.2
local repacked = render()
sameLayout(smooth, repacked)
assert(math.abs(repacked[1].quads[1].u0 - 0.28) < 0.00001, 'repacked source UVs are refreshed')
missingLarge = true
local fallback = render()
sameLayout(smooth, fallback)
assert(math.abs(fallback[1].quads[1].u0 - 0.22) < 0.00001, 'missing large raster falls back to native UVs')
missingLarge = false
local restored = render()
sameLayout(smooth, restored)
assert(math.abs(restored[1].quads[1].u0 - 0.28) < 0.00001, 'large raster can recover')

-- Once available, a dedicated atlas replaces slot 0, not the original source in
-- slot 4. Its guard changes only the texture quad; visible bearings stay pinned.
local active = { address = 0x34560000, regions = {}, white = { u = 0.91, v = 0.92 } }
filtered.Prepare = function(address, definitions)
    assert(address == hook.FontTexture)
    for _, definition in ipairs(definitions) do
        local letters = active.regions[definition.height] or {}
        active.regions[definition.height] = letters
        for byte, glyph in pairs(definition.glyphs) do
            assert(glyph.byte == byte)
            letters[byte] = { padX = 1, padY = 1, uv = { u0 = 0.7, v0 = 0.7, u1 = 0.8, v1 = 0.8 } }
        end
    end
    return active
end
local sourceSlot = tonumber(draw.Textures[4])
local own = render()
assert(draw.Textures[0] == active.address and draw.Textures[4] == sourceSlot,
    'filtered text and source icons must have independent texture slots')
for entity = 1, 2 do
    for index = 1, 2 do
        local a, b = restored[entity].quads[index], own[entity].quads[index]
        assert(math.abs(b.x0 + 1 - a.x0) < 0.00001 and math.abs(b.y0 + 1 - a.y0) < 0.00001
            and math.abs(b.x1 - 1 - a.x1) < 0.00001 and math.abs(b.y1 - 1 - a.y1) < 0.00001,
            'visible geometry must exclude the filtering guard')
        assert(b.u0 > 0.69 and b.u0 < 0.71 and b.color == a.color and b.flags == a.flags)
    end
end
assert(own[2].quads[3].x0 == restored[2].quads[3].x0 and own[2].quads[3].texture == 5,
    'filtered text must not move or retarget badges')
-- A missing atlas glyph must use original UVs AND the original font texture.
filtered.Prepare = function()
    active.regions[20][86] = nil
    return active
end
local missing = render()
assert(missing[1].quads[1].texture == 0 and missing[1].quads[2].texture == 4,
    'unfiltered fallback glyphs must not sample the generated atlas')
assert(math.abs(missing[1].quads[2].u0 - 0.28) < 0.00001)
-- The HP bar uses the white tile belonging to the active slot-0 atlas.
hp, o.showHealthBar[1] = 50, true
render()
local entry = draw.Entities[1]
local bar = draw.Quads[entry.First + entry.Count - 1]
assert(bar.Texture == 0 and math.abs(bar.U0 - active.white.u) < 0.00001
    and math.abs(bar.V0 - active.white.v) < 0.00001, 'bar white UVs must follow the active text texture')
hp, o.showHealthBar[1] = 100, false
filtered.Prepare = function() return nil end
sameLayout(restored, render())
assert(draw.Textures[0] == sourceSlot, 'unavailable filtered atlas restores the source font slot')
-- Distance scaling remains the same in either mode after the size stabilises.
hook.Names[0].Scale, hook.Names[1].Scale = 0.5, 0.5
for _ = 1, 30 do render() end
local distant = render()
o.fontSmooth[1] = false
sameLayout(distant, render())
-- Full renderer + real CPU builder: only D3D read/upload are mocked. This
-- catches texture-slot, immutable-definition and startup-loop integration bugs.
local atlas = require('gdi.atlas')
local image = require('gdi.image')
pcall(ffi.cdef, 'typedef struct IDirect3DTexture8 IDirect3DTexture8;')
local source = image.new(1024, 1024):fill(function(x, y) return (math.floor(x) + math.floor(y)) % 2 end)
local sourceReads, sourceUploads, sourceReleases = 0, 0, 0
atlas.release = function() sourceReleases = sourceReleases + 1 end
atlas.read = function() sourceReads = sourceReads + 1; return source end
atlas.upload = function() sourceUploads = sourceUploads + 1; return ffi.cast('IDirect3DTexture8*', 0x34560000) end
package.loaded.d3d8 = { gc_safe_release = function(t) return t end }
filtered.Prepare = originalFilteredPrepare
o.fontSmooth[1] = true
render()
assert(sourceReads == 0 and draw.Textures[0] == sourceSlot, 'first frame waits for upload and uses the source')
render()
assert(sourceReads == 1 and sourceUploads == 1 and draw.Textures[0] == 0x34560000,
    'second stable frame builds and binds the filtered atlas')
for _ = 1, 100 do render() end
assert(sourceReads == 1 and sourceUploads == 1, 'stable renderer must not regenerate the atlas every frame')
o.fontBold[1] = true
render()
assert(sourceReads == 1 and sourceUploads == 1, 'synthetic Bold does not require another mask atlas')
o.fontSmooth[1] = false
render()
assert(draw.Textures[0] == sourceSlot and sourceReleases == 1,
    'switching off restores the original font texture and releases the filtered atlas')
o.fontSmooth[1] = true
render(); render()
assert(draw.Textures[0] == 0x34560000 and sourceReads == 2, 'switching back on builds a fresh atlas')
shift = 0.3
render(); render()
assert(sourceReads == 3 and sourceUploads == 3, 'source UV repacking rebuilds the generated atlas once')
o.fontSize[1] = 40
render(); render()
assert(sourceReads == 4 and sourceUploads == 4, 'a changed native size rebuilds the rung masks once')
font.ContainerAtlas.TexData.UniqueID = 91
render(); render()
assert(sourceReads == 5 and sourceUploads == 5, 'new source texture identity invalidates the cached masks')
o.fontSmooth[1] = false
hook.Hooked = 0
assert(custom.Frame(o, hook) == 'unhooked' and sourceReleases == 5,
    'disabling drops the cache even if normal rendering is unavailable')
ffi.C.munmap(low, bytes + 16)
H.print('Smooth Font: filtered atlas/guards, native layout, independent Bold, unchanged badges, white tile, cache/repack/fallback and distance scaling', true)
