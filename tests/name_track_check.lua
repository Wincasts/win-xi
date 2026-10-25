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
H.print('tracked: the hunt sign, the sheet\'s first sign, in place of the aggro sign', quads(1) == 5, sign.Texture == 6,
    sign.U0 == 0 and sign.V0 == 0 and sign.U1 == 0.25 and sign.V1 == 0.5, draw.Textures[6] == 0x9999)
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

-- a vendor's coin: the sheet's other half, before the name of an NPC the area's list has
local vendorList = require('vendor_list')
local zoneOf, managerOf = 240, AshitaCore.GetMemoryManager
AshitaCore.GetMemoryManager = function(...)
    local memory = managerOf(...)
    local party = memory.GetParty()
    party.GetMemberZone = function() return zoneOf end
    memory.GetParty = function() return party end
    return memory
end
put(3, 0x402, 'Babubu', plates.Category.Npc); put(4, 0x403, 'Kohlo-Lakolo', plates.Category.Npc)
hook.Count = 5; render()
local coin = first(0x402)
H.print('bundled Port Windurst: Babubu sells, Kohlo-Lakolo does not', vendorList[240]['Babubu'] == true, vendorList[240]['Kohlo-Lakolo'] == nil)
H.print('[vendor]: the coin before a vendor\'s name, none for another NPC or a monster of the name',
    quads(0x402) == 1 + #'Babubu', coin.Texture == 6, coin.U0 == 0.25 and coin.U1 == 0.5 and coin.V1 == 0.5, draw.Textures[6] == 0x9999,
    quads(0x403) == #'Kohlo-Lakolo', first(1).Texture ~= 6 or options.trackedNm[1] ~= '')
local after = draw.Quads[draw.Entities[0x402].First + 1]
H.print('the name follows it, the whole of it centred', after.X0 > coin.X1, math.abs(coin.X0 + draw.Quads[draw.Entities[0x402].First + quads(0x402) - 1].X1) <= 1)
zoneOf = 1; render()
H.print('an area with no vendors: no coin', quads(0x402) == #'Babubu', draw.Textures[6] == 0)
zoneOf = 240; local npcFormat = options.npcFormat[1]; options.npcFormat[1] = '[name]'; render()
H.print('no [vendor]: no coin, and the sheet not asked for', quads(0x402) == #'Babubu', draw.Textures[6] == 0)
options.npcFormat[1] = '[name][vendor: space=4]'; render()
local last = draw.Quads[draw.Entities[0x402].First + quads(0x402) - 1]
H.print('[vendor] after the name: the coin last', quads(0x402) == 1 + #'Babubu', last.Texture == 6)
options.npcFormat[1] = npcFormat
AshitaCore.GetMemoryManager = managerOf
hook.Count = 4

-- party and alliance signs in [icons]: a party of three and another party of two in an alliance
local special = require('special')
local members = { [0] = 0x1501, 0x1502, 0x1503, [6] = 0x1506, [7] = 0x1507 }
local leaders = { 0x1502, 0x1506, 0, alliance = 0x1501 }
AshitaCore.GetMemoryManager = function(...)
    local memory = managerOf(...)
    memory.GetParty = function() return {
        GetMemberIsActive = function(_, slot) return members[slot] and 1 or 0 end,
        GetMemberServerId = function(_, slot) return members[slot] or 0 end,
        GetAlliancePartyLeaderServerId1 = function() return leaders[1] end,
        GetAlliancePartyLeaderServerId2 = function() return leaders[2] end,
        GetAlliancePartyLeaderServerId3 = function() return leaders[3] end,
        GetAllianceLeaderServerId = function() return leaders.alliance end,
    } end
    return memory
end
local function player(i, index, label, category, icon)
    put(i, index, label, category)
    hook.Names[i].ServerId = 0x1100 + index
    if icon then ffi.fill(hook.Names[i].Text, 48); ffi.copy(hook.Names[i].Text, string.char(icon) .. ' ' .. label) end
end
player(0, 0x401, 'Ann', plates.Category.Self); player(1, 0x402, 'Ben', plates.Category.Party)
player(2, 0x403, 'Cat', plates.Category.Party, 0x91); player(3, 0x406, 'Dan', plates.Category.Alliance)
player(4, 0x407, 'Eve', plates.Category.Alliance); player(5, 0x408, 'Fay', plates.Category.Player, 0x91)
hook.Count = 6
-- the player icons' sheet, which the tests cannot load
local iconSheet = require('icons'); local realBegin = iconSheet.Begin
iconSheet.Begin = function() return realBegin(function() return 0x5555 end) end
local function uv(sign) local u0, v0, u1, v1 = special.UV(sign); return { u0, v0, u1, v1 } end
local function signed(index, sign)
    local q, want = first(index), uv(sign)
    return q.Texture == 6 and q.U0 == want[1] and q.V0 == want[2] and q.U1 == want[3] and q.V1 == want[4]
end
local playerFormat = options.nameFormat[1]
H.print('[party] before [icons] to begin with', playerFormat == '[party: space=2][icons: space=4][name]')
render()
H.print('alliance leader, party leader, party member, the other party\'s leader, alliance member',
    signed(0x401, special.AllianceLeader), signed(0x402, special.PartyLeader), signed(0x403, special.PartyMember),
    signed(0x406, special.AlliancePartyLeader), signed(0x407, special.AllianceMember), draw.Textures[6] == 0x9999)
H.print('beside: the sign, then the game\'s icon, then the name; an outsider keeps only the game\'s',
    quads(0x403) == 2 + #'Cat', draw.Quads[draw.Entities[0x403].First + 1].Texture == 1, quads(0x402) == 1 + #'Ben',
    quads(0x408) == 1 + #'Fay', first(0x408).Texture == 1)
options.nameFormat[1] = '[party: replace, space=4][icons: space=4][name]'; render()
H.print('replace: the sign in place of the game\'s icon; an outsider keeps the game\'s',
    quads(0x403) == 1 + #'Cat', signed(0x403, special.PartyMember), quads(0x408) == 1 + #'Fay', first(0x408).Texture == 1)
options.nameFormat[1] = playerFormat; leaders = { 0x1502, 0, 0, alliance = 0x1502 }; members = { [0] = 0x1501, 0x1502, 0x1503 }; render()
H.print('no alliance: its leader is the party\'s, and the others are party members', signed(0x402, special.PartyLeader), signed(0x401, special.PartyMember), quads(0x406) == #'Dan')
members = { [0] = 0x1501 }; leaders = { 0x1501, 0, 0, alliance = 0x1501 }; render()
H.print('alone: no sign, nor the sheet', quads(0x401) == #'Ann', quads(0x403) == 1 + #'Cat', draw.Textures[6] == 0)
members = { [0] = 0x1501, 0x1502 }; options.nameFormat[1] = '[icons: space=4][name]'; render()
H.print('no [party]: none', quads(0x401) == #'Ann', quads(0x402) == #'Ben', draw.Textures[6] == 0)
options.nameFormat[1] = playerFormat
AshitaCore.GetMemoryManager = managerOf
iconSheet.Begin = realBegin; realBegin(function() return 0 end)
put(0, 1, 'Jack'); put(1, 2, 'Hare'); put(2, 3, 'Hare'); put(3, 0x401, 'Jack', plates.Category.Player)
hook.Count = 4

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

-- The game gives the player's own name no text while they are their own target or sub target:
-- the name is drawn all the same, as it was, its icons with it; with nothing before, the entity's name
options.nameFormat[1] = '[icons][name]'; custom.Settle(options)
put(0, 0x408, 'Win', plates.Category.Self); ffi.copy(hook.Names[0].Text, '\146 Win'); hook.Count = 1
render(); local own = quads(0x408)
ffi.fill(hook.Names[0].Text, 48); hook.Names[0].Flags = plates.Flag.Wanted + plates.Flag.Target; render()
assert(draw.Entities[0x408].Frame == hook.Frame and quads(0x408) == own, 'own name, given no text, drawn as it was')
ffi.copy(hook.Names[0].Text, 'Win'); render(); local plainName = quads(0x408)
put(0, 0x409, 'Win', plates.Category.Self); ffi.fill(hook.Names[0].Text, 48); render()
assert(draw.Entities[0x409].Frame == hook.Frame and quads(0x409) == plainName, 'given no text from the start: the entity\'s name')
H.print('own name given no text: drawn as before, and the entity\'s name with nothing before', true)

-- Letter Spacing: each letter after the first is moved on by the setting, in screen pixels at the name's
-- largest; a token's spacing= in place of it; nothing else changed
options.nameFormat[1] = '[name]'; options.letterSpacing = T{ 0 }; custom.Settle(options)
put(0, 0x408, 'Win', plates.Category.Self); hook.Count = 1
local function lefts() local at = {}; for k = 0, quads(0x408) - 1 do at[#at + 1] = draw.Quads[draw.Entities[0x408].First + k].X0 end; return at end
render(); local tight = lefts()
options.letterSpacing[1] = 3; render(); local spaced = lefts()
assert(#spaced == #tight and spaced[2] - spaced[1] == tight[2] - tight[1] + 3 and spaced[3] - spaced[1] == tight[3] - tight[1] + 6,
    'Letter Spacing 3: each letter 3 px further on than the one before')
assert(spaced[1] == tight[1] - 3, 'the name still centred: the 6 px are shared either side')
options.nameFormat[1] = '[name: spacing=1]'; render(); local own = lefts()
assert(own[2] - own[1] == tight[2] - tight[1] + 1, 'a token\'s spacing= in place of the setting')
options.letterSpacing[1] = 99; custom.Settle(options); assert(options.letterSpacing[1] == 10, 'kept within 0 to 10')
options.letterSpacing[1] = 0; options.nameFormat[1] = '[name]'
H.print('Letter Spacing: letters moved apart, centred, a token\'s own spacing, kept within bounds', true)

-- A linkshell pearl's colour: given as the game has it, doubled by the plugin (namehook 1.36) as the game
-- draws it, so that more than 0x80 is brighter than the icon; with an older plugin as before, where it is not
options.nameFormat[1] = '[icons][name]'; custom.Settle(options)
put(0, 0x408, 'Win', plates.Category.Self); ffi.copy(hook.Names[0].Text, '\146 Win'); hook.Names[0].IconColor = 0x008F1F8F; hook.Count = 1
local supports = plates.Supports
local iconsModule = require('icons'); local realPlace = iconsModule.Place
iconsModule.Place = function(byte) return byte == 0x92 and { 0, 0, 0.1, 0.1 } or realPlace(byte) end
local function pearl() for k = 0, quads(0x408) - 1 do local q = draw.Quads[draw.Entities[0x408].First + k]; if q.Texture == 1 then return q end end end
plates.Supports = function(features, ...) if features == plates.Feature.Doubled then return true end return supports(features, ...) end
render(); local q = pearl()
assert(q ~= nil and q.Color == 0xFF8F1F8F and bit.band(q.Flags, 32) ~= 0, 'pearl: the game\'s colour, doubled by the plugin')
assert(bit.band(q.Flags, 1) ~= 0, 'and still edged as icons are')
plates.Supports = function(features, ...) if features == plates.Feature.Doubled then return false end return supports(features, ...) end
render(); q = pearl()
assert(q.Color == 0xFFFF3EFF and bit.band(q.Flags, 32) == 0, 'older plugin: doubled here, more than 0x80 no brighter')
options.nameFormat[1] = '[icons: color=red][name]'; plates.Supports = function(features, ...) if features == plates.Feature.Doubled then return true end return supports(features, ...) end
render(); q = pearl()
assert(q.Color == 0xFFFF4040 and bit.band(q.Flags, 32) == 0, 'a colour of the format\'s own is not doubled')
plates.Supports, iconsModule.Place = supports, realPlace; options.nameFormat[1] = '[name]'
H.print('pearl colour: doubled by the plugin, as before with an older one, a format\'s colour as it is', true)

-- [aggro: size=]: the sign's height as a percentage of the name's, 125 without it; the name moved on by the difference
options.monsterFormat[1] = '[aggro][name]'; custom.Settle(options)
put(0, 1, 'Jack'); hook.Count = 1; options.trackedNm[1] = ''
render(); local usualSign, usualName = first(1), draw.Quads[draw.Entities[1].First + 1]
local usualHeight, usualAt = usualSign.Y1 - usualSign.Y0, usualName.X0 - usualSign.X0
options.monsterFormat[1] = '[aggro: size=250][name]'; render()
local bigSign, bigName = first(1), draw.Quads[draw.Entities[1].First + 1]
assert(math.abs((bigSign.Y1 - bigSign.Y0) - usualHeight * 2) <= 1, '250%: twice the 125% sign')
assert(bigName.X0 - bigSign.X0 > usualAt, 'and the name after it moved on')
options.monsterFormat[1] = '[aggro][name]'
H.print('[aggro: size=]: the sign sized, the name after it', true)

-- Text Outline Opacity: the edge of the text alone softened, as Icon Outline Opacity does for icons
options.monsterFormat[1] = '[aggro][name]'; options.textOutlineOpacity = T{ 100 }; custom.Settle(options)
render(); local letter = draw.Quads[draw.Entities[1].First + 1]
assert(bit.band(letter.Flags, 2) == 0, 'at 100% the text\'s edge as it was')
options.textOutlineOpacity[1] = 40; render()
local softened, sign = draw.Quads[draw.Entities[1].First + 1], first(1)
assert(bit.band(softened.Flags, 3) == 3 and bit.band(softened.Reserved, 0xFF) == 102, '40%: the letters\' edge at 40%')
assert(bit.band(sign.Reserved, 0xFF) == 255, 'the icon\'s edge as Icon Outline Opacity has it')
options.textOutlineOpacity[1] = 999; custom.Settle(options); assert(options.textOutlineOpacity[1] == 100, 'kept within 0 to 100')
H.print('Text Outline Opacity: the text\'s edge alone, kept within bounds', true)

-- [space]: a gap of its own, only between two things written
iconsModule.Place = function(byte) return byte == 0x92 and { 0, 0, 0.1, 0.1 } or realPlace(byte) end
put(0, 0x408, 'Win', plates.Category.Self); hook.Count = 1
local function layout(format, text)
    options.nameFormat[1] = format; ffi.fill(hook.Names[0].Text, 48); ffi.copy(hook.Names[0].Text, text); render()
    local at, quadsOf = {}, quads(0x408)
    for k = 0, quadsOf - 1 do local q = draw.Quads[draw.Entities[0x408].First + k]; at[#at + 1] = { x = q.X0, icon = q.Texture == 1 } end
    local name = nil; for _, q in ipairs(at) do if not q.icon then name = name or q.x end end
    return { first = at[1].x, name = name, count = quadsOf }
end
local tight = layout('[icons: space=0][name]', '\146 Win')
local gapped = layout('[icons][space: 8][name]', '\146 Win')
assert(gapped.name - gapped.first == tight.name - tight.first + 8, '[space: 8]: the name 8 px further from the icon')
assert(gapped.first == tight.first - 4, 'and the line still centred')
local attribute = layout('[icons: space=8][name]', '\146 Win')
assert(attribute.first == gapped.first and attribute.name == gapped.name, '[icons][space: 8] as [icons: space=8]: the icons\' own spacing gives way')
local default = layout('[icons][space][name]', '\146 Win')
assert(default.name - default.first == tight.name - tight.first + 4, '[space]: 4 px without a size')
local summed = layout('[icons][space: 3][space: 5][name]', '\146 Win')
assert(summed.name - summed.first == gapped.name - gapped.first, 'two together are the two sizes')
local plain = layout('[name]', 'Win')
assert(layout('[icons][space: 8][name]', 'Win').first == plain.first, 'no icons: no gap before the name')
assert(layout('[name][space: 8]', 'Win').first == plain.first, 'nothing after: no gap at the end')
assert(layout('[name][space: 8][distance]', 'Win').first == plain.first, 'nothing written after it: no gap')
iconsModule.Place = realPlace; options.nameFormat[1] = '[name]'
H.print('[space]: a gap between icons and name, none at the ends nor beside what writes nothing, two summed', true)
