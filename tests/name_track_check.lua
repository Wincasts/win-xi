-- A tracked notorious monster's hunt sign and its placeholders' name. Run via tests/harness.lua.
local ffi = require('ffi')
local imgui = require('imgui')
local custom = require('custom')
local customSettings = require('custom_settings')
local plates = require('winxi.nameplates')
local levels = require('levels')
-- the plugin is 32-bit and keeps its drawing's address in 32: somewhere low is asked for
ffi.cdef('void* mmap(void*, size_t, int, int, int, long); int munmap(void*, size_t);')
local low = ffi.C.mmap(nil, ffi.sizeof('namehook_draw_t'), 3, 0x62, -1, 0)
assert(low ~= ffi.cast('void*', -1))
local draw = ffi.cast('namehook_draw_t*', low)
draw.QuadsMax = 16384
local hook = ffi.new('namehook_t')
hook.Hooked, hook.Draw = 1, tonumber(ffi.cast('uintptr_t', low))
hook.Width, hook.Height, hook.TargetWidth, hook.TargetHeight = 1920, 1080, 1920, 1080
local glyph = { X0 = 0, Y0 = 0, X1 = 8, Y1 = 12, U0 = 0, V0 = 0, U1 = 1, V1 = 1, AdvanceX = 8, Visible = 1 }
local font = { ContainerAtlas = { TexData = { UniqueID = 2, Status = 0, Width = 512, Height = 256 } } }
imgui.GetFont = function() return font end
imgui.GetFontBaked = function() return { FindGlyph = function() return glyph end } end
imgui.PushFont, imgui.PopFont = function() end, function() end
imgui.AddFontFromFileTTF = function() return font end
imgui.GetIO = function() return { DisplaySize = { x = 1920, y = 1080 } } end
custom.SetSheets(0x7777, 0x8888, 0x9999)
local options = {}
custom.Defaults(options)
options.showCheckDetails[1], options.showStars[1] = false, false
options.monsterFormat[1] = '[aggro][name]'
local function put(i, index, name, category)
    local entry = hook.Names[i]
    entry.EntityIndex, entry.ServerId = index, 0x1000 + index
    entry.Category, entry.Flags = category or plates.Category.Monster, plates.Flag.Wanted
    entry.Scale, entry.NameColor = 1, 0x80808080
    ffi.fill(entry.Name, 28); ffi.fill(entry.Text, 48)
    ffi.copy(entry.Name, name); ffi.copy(entry.Text, name)
end
put(0, 1, 'Jack'); put(1, 2, 'Hare'); put(2, 3, 'Hare'); put(3, 0x401, 'Jack', plates.Category.Player)
hook.Count = 4
local function render() hook.Frame = hook.Frame + 1; H.wait(0.03); custom.Frame(options, hook) end -- a frame's time, as H.frames
local function quads(index) return draw.Entities[index].Count end
local function first(index) return draw.Quads[draw.Entities[index].First] end

local monster = { Notorious = true, Aggro = true, MinLevel = 5, MaxLevel = 6 }
levels.Set({ Names = { Jack = monster, Hare = { Aggro = false, MinLevel = 2, MaxLevel = 3 }, bomb = { Name = 'Bomb', Notorious = true } }, Indices = {} },
    {}, nil, { Jack = { 2 }, Ghost = { 9 } })
H.print('the area\'s notorious monsters, in order, with one only the lots name',
    table.concat(levels.Notorious(), '|') == 'Bomb|Ghost|Jack', levels.Placeholders('Jack')[2] == true,
    levels.Placeholders('Jack')[3] == nil, levels.Placeholders('Bomb') == nil)

render()
H.print('none tracked: the aggro sign and the name', quads(1) == 5, first(1).Texture == 3, quads(2) == 5, draw.Textures[6] == 0)

options.trackedNm[1] = 'Jack'; render()
local sign = first(1)
H.print('tracked: the hunt sign, whole, in place of the aggro sign', quads(1) == 5, sign.Texture == 6,
    sign.U0 == 0 and sign.V0 == 0 and sign.U1 == 1 and sign.V1 == 1, draw.Textures[6] == 0x9999)
H.print('its placeholder is named Placeholder and has the hunt sign too; another of the name is as it was',
    quads(2) == 1 + #'Placeholder', first(2).Texture == 6, quads(3) == 5, first(3).Texture == 3)
H.print('a player of the name is no monster', quads(0x401) == 4)

options.labelPlaceholders[1] = false; render()
H.print('Label Placeholders off: its own name, the hunt sign still', quads(2) == 5, first(2).Texture == 6, first(1).Texture == 6)
options.labelPlaceholders[1] = true

-- the letters' height, by the last quad of a name; the stand-in font's letters are 12 high at every size
local function tall(index) local q = draw.Quads[draw.Entities[index].First + quads(index) - 1]; return q.Y1 - q.Y0 end
local usual, lotTall = tall(1), tall(2)
options.huntScale[1] = 150; render()
H.print('Hunt Target Scale 150%: half as large again, sign and all; the placeholder and the rest as they were',
    math.abs(tall(1) - usual * 1.5) < 0.01, math.abs((first(1).Y1 - first(1).Y0) / (first(2).Y1 - first(2).Y0) - 1.5) < 0.05,
    tall(2) == lotTall, tall(3) == lotTall)
hook.Names[0].Scale = 0.5; for _ = 1, 6 do render() end -- a leap in size is not believed at once
local farHunted = tall(1)
options.huntScale[1] = 100; render()
H.print('and at a distance, where names are smaller', math.abs(farHunted - tall(1) * 1.5) < 0.01, tall(1) < usual)
hook.Names[0].Scale = 1; for _ = 1, 6 do render() end
options.huntScale[1] = 999; custom.Settle(options)
H.print('kept within 100 to 200', options.huntScale[1] == 200)
options.huntScale[1] = 100; render()

options.monsterFormat[1] = '[name]'; render()
local any = false
for i = 0, quads(1) - 1 do any = any or draw.Quads[draw.Entities[1].First + i].Texture == 6 end
H.print('Aggro token omitted: no sign, placeholder still named', quads(1) == 4, not any, quads(2) == #'Placeholder')
options.monsterFormat[1] = '[aggro][name]'

levels.Set({ Names = {}, Indices = {} }, {}, nil, nil); render()
H.print('not in the tables, still tracked by name: the hunt sign; no lots, no placeholder', quads(1) == 5, first(1).Texture == 6, quads(2) == 4)

put(0, 1, 'Jill'); render()
H.print('renamed in its slot: no longer the one', quads(1) == 4)
put(0, 1, 'Jack')

options.trackedNm[1] = ''; render()
H.print('tracking ended: as before', quads(1) == 4, draw.Textures[6] == 0)

options.trackedNm, options.labelPlaceholders = 'Jack', nil
custom.Settle(options)
options.huntScale = 'big'; custom.Settle(options)
H.print('settings of another shape are made good', options.trackedNm[1] == '', options.labelPlaceholders[1] == true, options.huntScale[1] == 100)

-- the settings: the dropdown lists the area's, and the toggle is only there for one with placeholders
levels.Set({ Names = { Jack = monster, Bomb = { Notorious = true } }, Indices = {} }, {}, nil, { Jack = { 2 } })
local listed, boxes, saved, pick = {}, {}, 0, nil
local realSlider = imgui.SliderInt
imgui.SliderInt = function(id, ...) boxes[id] = true; return false end
AshitaCore.GetPluginManager = function() return { IsLoaded = function() return false end } end
imgui.BeginCombo = function(id) return id == '##name.trackedNm' end
imgui.EndCombo = function() end
imgui.Selectable = function(label) listed[#listed + 1] = label; return label == pick end
local realCheckbox = imgui.Checkbox
imgui.Checkbox = function(id, ...) boxes[id] = true; return false end
customSettings.DrawTracking(options, function() saved = saved + 1 end)
H.print('dropdown: None and the area\'s notorious monsters; none tracked, no scale', table.concat(listed, '|') == 'None|Bomb|Jack', boxes['##name.labelPlaceholders'] == nil, boxes['##name.huntScale'] == nil)
pick = 'Bomb'; customSettings.DrawTracking(options, function() saved = saved + 1 end)
H.print('chosen and saved; one with no placeholders has no toggle', options.trackedNm[1] == 'Bomb', saved == 1, boxes['##name.labelPlaceholders'] == nil)
pick = 'Jack'; customSettings.DrawTracking(options, function() saved = saved + 1 end)
H.print('one with placeholders has the toggle, and any tracked the scale', options.trackedNm[1] == 'Jack', saved == 2, boxes['##name.labelPlaceholders'] == true, boxes['##name.huntScale'] == true)
pick = 'None'; customSettings.DrawTracking(options, function() saved = saved + 1 end)
H.print('None ends it', options.trackedNm[1] == '', saved == 3)
imgui.Checkbox, imgui.SliderInt = realCheckbox, realSlider

-- the bundled lots are of the bundled tables: the slot's name is the game's to give, read as the area is entered
local zone = dofile('addons/libs/winxi/data/placeholders/100.lua')
local tables = dofile('addons/libs/winxi/data/mobs/100.lua')
H.print('bundled West Ronfaure: Jaggedy-Eared Jack is drawn from one slot, in an area with Forest Hares',
    #zone['Jaggedy-Eared Jack'] == 1 and zone['Jaggedy-Eared Jack'][1] == 294 and tables.Names['Forest Hare'] ~= nil)

-- the name under the sub-target cursor, while one is being chosen
local subActive, subFlags, subIndex, asked = 0, 0xFFFFFFFF, 3, 0
local manager = AshitaCore.GetMemoryManager
AshitaCore.GetMemoryManager = function(...)
    local memory = manager(...)
    memory.GetTarget = function() asked = asked + 1; return {
        GetIsSubTargetActive = function() return subActive end,
        GetSubTargetFlags = function() return subFlags end,
        GetTargetIndex = function(_, slot) return slot == 0 and subIndex or 1 end,
    } end
    return memory
end
render(); local plain = tall(3)
options.subtargetScale[1] = 150; render()
H.print('no sub target being chosen: every name its usual size', asked == 2, tall(3) == plain, tall(2) == plain)
subActive = 1; render()
H.print('Subtarget Scale 150%: the name under the cursor half as large again, the rest as they were',
    math.abs(tall(3) - plain * 1.5) < 0.01, tall(2) == plain, tall(1) == plain)
options.subtargetScale[1] = 50; render()
-- below 100% a smaller rung's letters are taken, and the stand-in's are 12 high at every rung
H.print('and 50% smaller, the rest as they were', tall(3) < plain, tall(2) == plain, tall(1) == plain)
subActive = 0; render()
H.print('chosen: as before', tall(3) == plain)
-- with nothing targeted first, the choice is made in the first slot and only the flags say so
options.subtargetScale[1] = 150; subFlags = 0x1F; render()
H.print('nothing targeted first: the name under the cursor larger all the same', math.abs(tall(3) - plain * 1.5) < 0.01, tall(2) == plain)
subFlags = 0xFFFFFFFF; render()
H.print('and chosen: as before', tall(3) == plain)
-- the game sizes the name its own way as the choice begins and ends: none of it is seen, only our scale
local function frames(n) for _ = 1, n do render() end end
frames(31) -- the last choice's hold over, its size is the game's again
hook.Names[2].Scale = 0.5; frames(6); local far = tall(3)
H.print('a name further off, as the game has it', far < plain)
subFlags = 0x1F; hook.Names[2].Scale = 1; frames(6)
H.print('the game\'s leap to full size while it is chosen is not taken: our scale of its own size', math.abs(tall(3) - far * 1.5) < 0.01)
-- a walk's step, the same for another name of the same size: the chosen one is that one's, half as large again
hook.Names[1].Scale = 0.5; frames(6)
for _, step in ipairs({ 0.4, 0.3, 0.2 }) do hook.Names[1].Scale, hook.Names[2].Scale = step, step; render() end
H.print('the steps of a walk are still followed', tall(2) < far, math.abs(tall(3) - tall(2) * 1.5) < 0.01)
for _, step in ipairs({ 0.3, 0.4, 0.5 }) do hook.Names[1].Scale, hook.Names[2].Scale = step, step; render() end
hook.Names[1].Scale = 1; frames(6)
subFlags = 0xFFFFFFFF; hook.Names[2].Scale = 0; render(); hook.Names[2].Scale = 1; frames(6)
H.print('nor its leaps as the choice ends: its own size, without our scale', math.abs(tall(3) - far) < 0.01)
hook.Names[2].Scale = 0.5; frames(31); hook.Names[2].Scale = 1; frames(6)
H.print('once settled, the game\'s sizes are followed again', tall(3) == plain)
-- At 144 frames a second, the game's leap for one frame of its own (a 30th of a second) lasts five
-- of ours: it is timed, not counted, so it is still not taken; a leap that lasts is, a tenth on
local function fast(n) for _ = 1, n do hook.Frame = hook.Frame + 1; H.wait(1 / 144); custom.Frame(options, hook) end end
hook.Names[2].Scale = 0.5; fast(30); local before = tall(3)
hook.Names[2].Scale = 1; fast(5); local during = tall(3)
hook.Names[2].Scale = 0.5; fast(1)
H.print('144 fps: a leap for one of the game\'s frames, five of ours, not taken', during == before, tall(3) == before)
hook.Names[2].Scale = 1; fast(12); local early = tall(3); fast(4)
H.print('144 fps: one that lasts is taken a tenth of a second on, and not before', early == before, tall(3) == plain)
options.subtargetScale[1] = 999; custom.Settle(options)
H.print('kept within 50 to 200', options.subtargetScale[1] == 200)
options.subtargetScale = 'big'; custom.Settle(options)
H.print('of another shape, made good', options.subtargetScale[1] == 100)
AshitaCore.GetMemoryManager = manager
