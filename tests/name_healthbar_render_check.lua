-- Exercise the actual name renderer and shared FFI draw buffer, not a mocked Quad.
-- Native Ashita/ImGui/D3D calls remain mocked: this cannot diagnose a client crash.
local ffi = require('ffi')
local imgui = require('imgui')
local custom = require('custom')
local plates = require('winxi.nameplates')
local types = require('name_types')
ffi.cdef('void* mmap(void*, size_t, int, int, int, long); int munmap(void*, size_t);')
local bytes = ffi.sizeof('namehook_draw_t')
local low = ffi.C.mmap(nil, bytes + 16, 3, 0x62, -1, 0)
assert(low ~= ffi.cast('void*', -1))
local draw = ffi.cast('namehook_draw_t*', low)
local sentinel = ffi.cast('uint8_t*', low) + bytes
ffi.fill(sentinel, 16, 0xA5)
local hook = ffi.new('namehook_t')
hook.Hooked, hook.Draw = 1, tonumber(ffi.cast('uintptr_t', low))
hook.Width, hook.Height, hook.TargetWidth, hook.TargetHeight = 1920, 1080, 1920, 1080
hook.Count = 256
local options = {}
custom.Defaults(options)
options.showCheckDetails[1], options.showStars[1] = false, false
options.monsterFormat[1] = '[name]'
local glyph = { X0 = 0, Y0 = 0, X1 = 8, Y1 = 12, U0 = 0, V0 = 0, U1 = 1, V1 = 1, AdvanceX = 8, Visible = 1 }
local font = { ContainerAtlas = { TexData = { UniqueID = 2, Status = 0, Width = 512, Height = 256 },
    TexUvWhitePixel = { x = 0.125, y = 0.25 } } }
imgui.GetFont = function() return font end
local currentSize = 15
imgui.GetFontBaked = function()
    local g = {}; for k, v in pairs(glyph) do g[k] = v end
    g.X1, g.Y1, g.AdvanceX = currentSize * 8/15, currentSize * 12/15, currentSize * 8/15
    return { FindGlyph = function() return g end }
end
imgui.PushFont = function(_, size) currentSize = size end
imgui.PopFont = function() end
imgui.GetIO = function() return { DisplaySize = { x = 1920, y = 1080 } } end
imgui.GetFontTexUvWhitePixel = function() return 0.125, 0.25 end
-- The harness invents stubs for unknown APIs; genuinely omit this API for fallback coverage.
local fallbackIndex = getmetatable(imgui).__index
setmetatable(imgui, { __index = function(t, key)
    if key == 'GetFontTexUvWhitePixel' then return nil end
    return fallbackIndex(t, key)
end })
local hp, reads = 50, 0
local statuses = {}
local memory = AshitaCore:GetMemoryManager()
AshitaCore.GetMemoryManager = function() return memory end
memory.GetEntity = function() return {
    GetServerId = function(_, index) return 0x1000 + index end,
    GetHPPercent = function() reads = reads + 1; return hp end,
    GetStatus = function(_, index) return statuses[index] end,
} end
for i = 0, 255 do
    local name = hook.Names[i]
    name.EntityIndex, name.ServerId = i + 1, 0x1001 + i
    -- Players avoid the monster death-state HP read, so preview can assert no HP reads.
    name.Category, name.Flags = plates.Category.Player, plates.Flag.Wanted
    name.Scale, name.NameColor = 1, 0x80408020
    ffi.copy(name.Name, 'Player'); ffi.copy(name.Text, 'Player')
end
local function render(capacity)
    draw.QuadsMax = capacity or 16384
    hook.Frame = hook.Frame + 1
    H.wait(0.03) -- a frame's time, as H.frames: a leap in size is believed after a tenth of a second
    assert(custom.Frame(options, hook) == nil)
    assert(draw.QuadCount <= draw.QuadsMax, 'global quad capacity exceeded')
    for i = 1, 256 do
        local entry = draw.Entities[i]
        if entry.Frame == draw.Frame then
            assert(entry.Count <= 256 and entry.First + entry.Count <= draw.QuadCount,
                'invalid per-name draw range')
        end
    end
    for i = 0, 15 do assert(sentinel[i] == 0xA5, 'draw buffer overrun') end
    for i = 0, draw.QuadCount - 1 do
        local q = draw.Quads[i]
        assert(q.X0 == q.X0 and q.Y0 == q.Y0 and q.X1 == q.X1 and q.Y1 == q.Y1
            and math.abs(q.X0) < math.huge and math.abs(q.Y0) < math.huge
            and math.abs(q.X1) < math.huge and math.abs(q.Y1) < math.huge,
            'non-finite bar coordinates')
        assert(q.Texture == 0, 'basic bars must use the font texture mark, not a new pointer')
    end
    return tonumber(draw.QuadCount)
end
local baseline = render()
options.showHealthBar[1] = true
local live = render()
assert(live == baseline + 256 * 3, 'live HP rendering adds three quads per damaged name')
local first = draw.Entities[1]
assert(draw.Quads[first.First + first.Count - 1].Color == draw.Quads[first.First].Color,
    'renderer gives bar fill the same converted colour as name text')
options.nameFormat[1] = '[name: color=cyan]'
assert(render() == live)
local tinted = draw.Entities[1]
assert(draw.Quads[tinted.First].Color == 0xFF60E0E0
    and draw.Quads[tinted.First + tinted.Count - 1].Color == 0xFF60E0E0,
    'token colour overrides must also colour the health-bar fill')
options.nameFormat[1] = '[icons: space=4][name]'
options.healthBarWidth[1], options.healthBarHeight[1] = 100, 10
assert(render() == live)
local bar = draw.Quads[draw.Entities[1].First + draw.Entities[1].Count - 3]
assert(bar.X1 - bar.X0 == 100 and bar.Y1 - bar.Y0 == 10,
    'renderer forwards saved width and height')
-- Entity Types: only the kinds ticked have a bar
assert(options.healthBarCategories[1] == plates.Category.All, 'every kind to begin with')
options.healthBarCategories[1] = plates.Category.All - plates.Category.Player
assert(render() == baseline, 'Other Players unticked: no bar over a player')
options.healthBarCategories[1] = plates.Category.Player
assert(render() == live, 'Other Players alone: the bars back')
options.healthBarCategories[1] = plates.Category.All
-- a name further away is drawn smaller, and its bar shrinks with it by the same factor
local keptMax, keptMin = options.fontSize[1], options.minSize[1]
options.fontSize[1], options.minSize[1] = 20, 10
hook.Names[1].Scale = 0.5
for _ = 1, 30 do render() end -- a leap in size is held for a few frames before it is believed
local nearName, farName = draw.Quads[draw.Entities[1].First], draw.Quads[draw.Entities[2].First]
local nearBar = draw.Quads[draw.Entities[1].First + draw.Entities[1].Count - 3]
local farBar = draw.Quads[draw.Entities[2].First + draw.Entities[2].Count - 3]
local shrunk = (farName.Y1 - farName.Y0) / (nearName.Y1 - nearName.Y0)
assert(shrunk < 0.95 and math.abs((farBar.X1 - farBar.X0) / (nearBar.X1 - nearBar.X0) - shrunk) < 0.03
    and math.abs((farBar.Y1 - farBar.Y0) / (nearBar.Y1 - nearBar.Y0) - shrunk) < 0.12,
    'the bar shrinks with the name as it goes further away')
hook.Names[1].Scale = 1
options.fontSize[1], options.minSize[1] = keptMax, keptMin
hp = 100
assert(render() == baseline, 'full HP removes all bars')
options.showHealthBar[1] = false
reads = 0
assert(render() == baseline and reads == 0, 'disabled health bars do not read HP or draw samples')
hp = 50
-- Repeated live toggles and atlas updates, including the vector/fallback bindings.
for frame = 1, 500 do
    options.showHealthBar[1] = frame % 2 == 0
    font.ContainerAtlas.TexData.UniqueID = frame + 2
    if frame % 3 == 0 then
        imgui.GetFontTexUvWhitePixel = nil
    elseif frame % 3 == 1 then
        imgui.GetFontTexUvWhitePixel = function() return { x = 0.125, y = 0.25 } end
    else
        imgui.GetFontTexUvWhitePixel = function() return 0.125, 0.25 end
    end
    local count = render()
    assert(count == (options.showHealthBar[1] and live or baseline),
        ('frame %d: %d quads, expected %d'):format(frame, count, options.showHealthBar[1] and live or baseline))
end
options.showHealthBar[1] = true
for _, capacity in ipairs({ 0, 1, 6, 7, 8, 9, 10, 16384 }) do render(capacity) end
-- Long formats can consume the per-name budget before the bars are appended.
options.nameFormat[1] = string.rep('[name]', 50)
render()
assert(draw.Entities[1].Count == 256, 'per-name quad limit must clip safely')
options.showHealthBar[1] = false
-- All categories share General text sizes and health-bar dimensions.
options.nameFormat[1] = '[name]'
hook.Count = 3
hook.Names[1].Category, hook.Names[2].Category = plates.Category.Monster, plates.Category.Npc
hp = 50
options.fontSize[1], options.minSize[1] = 30, 30
for i, key in ipairs(types.List) do
    local style = options[key]
    style.fontSize, style.minSize = { 10 + 10*i }, { 10 + 10*i } -- stale overrides must be ignored
    style.healthBarWidth[1], style.healthBarHeight[1] = 30 + 30*i, 2 + 2*i
    style.showHealthBar[1] = false
end
assert(render() == 18)
for i = 1, 3 do
    local q = draw.Quads[draw.Entities[i].First]
    assert(math.abs(q.Y1 - q.Y0 - 30*12/15) < 0.01, 'every category must use the shared General size')
end
options.fontSize[1], options.minSize[1] = 20, 20
assert(render() == 18)
for i = 1, 3 do
    local q = draw.Quads[draw.Entities[i].First]
    assert(math.abs(q.Y1 - q.Y0 - 20*12/15) < 0.01, 'changing General updates every category together')
end
for _, category in ipairs({ plates.Category.Self, plates.Category.Party, plates.Category.Alliance,
    plates.Category.Player, plates.Category.MyPet, plates.Category.Pet, plates.Category.Npc, plates.Category.Monster }) do
    hook.Names[0].Category = category
    render()
    local q = draw.Quads[draw.Entities[1].First]
    assert(math.abs(q.Y1 - q.Y0 - 20*12/15) < 0.01, 'shared sizes include self, party, alliance and pets')
end
hook.Names[0].Category = plates.Category.Player
options.showHealthBar[1], options.healthBarWidth[1], options.healthBarHeight[1] = true, 120, 8
assert(render() == 27, 'shared toggle applies to all categories despite legacy per-type toggles')
for i = 1, 3 do
    local bar = draw.Quads[draw.Entities[i].First + 6]
    assert(bar.X1-bar.X0 == 120 and bar.Y1-bar.Y0 == 8, 'all bar dimensions are shared')
end
hp = 100
assert(render() == 18, 'full-health entities never display sample bars')
hp = 50; options.healthBarsCombatOnly[1] = true
statuses[1], statuses[2], statuses[3] = 1, 0, nil
assert(render() == 21 and draw.Entities[1].Count == 9 and draw.Entities[2].Count == 6
    and draw.Entities[3].Count == 6, 'combat only is per entity; idle and unknown states hide bars')
statuses[2], statuses[3] = 1, 1
assert(render() == 27, 'combat filter supports all categories, including engaged NPCs')
statuses[1], statuses[2], statuses[3] = 0, 0, 0
assert(render() == 18, 'target/claim status alone cannot bypass the combat filter')
statuses[1], statuses[2], statuses[3] = 1, 1, 1; hp = 0
assert(render() == 18, 'zero HP cannot count as combat even with a stale engaged status')
ffi.C.munmap(low, bytes + 16)
H.print('health-bar renderer: 256 names, live toggles, atlas updates and draw-buffer limits', true)
