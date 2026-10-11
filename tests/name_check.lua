-- name and winxi.nameplates: the addon's settings and the plugin's are kept the same, and the
-- plugin's names are read. The plugin here is a block of the same shape, made in this file.
local ffi = require('ffi')
local imgui = require('imgui')
local nameplates = require('winxi.nameplates')
local Category, Flag = nameplates.Category, nameplates.Flag
local o = H.options()

local loaded = false
local block = ffi.new('namehook_t')
ffi.copy(block.Magic, 'NAMEHOOK')
block.Version, block.Size, block.NameSize, block.Hooked = 2, ffi.sizeof('namehook_t'), ffi.sizeof('namehook_name_t'), 1
block.Width, block.Height = 960, 540

local manager = AshitaCore.GetPluginManager()
manager.IsLoaded = function(_, name) return loaded and name == 'namehook' end
AshitaCore.GetPluginManager = function() return manager end
ashita.memory.find = function(module) return module == 'namehook.dll' and tonumber(ffi.cast('uintptr_t', ffi.cast('void*', block))) or 0 end

H.print('the block is laid out as the plugin has it', ffi.sizeof('namehook_name_t') == 128, ffi.offsetof('namehook_t', 'Sequence') == 64,
    ffi.offsetof('namehook_t', 'Draw') == 68, ffi.offsetof('namehook_t', 'Override') == 80, ffi.offsetof('namehook_t', 'Names') == 80 + 0x900)
H.print('and so is what is drawn for it', ffi.sizeof('namehook_quad_t') == 48, ffi.sizeof('namehook_drawing_t') == 24,
    ffi.offsetof('namehook_draw_t', 'Entities') == 48, ffi.offsetof('namehook_draw_t', 'Quads') == 48 + 24 * 0x900)

-- without the plugin: nothing to read, nothing set, and the settings say so
H.print('settings: everything shown', o.showSelf[1], o.showPlayers[1], o.showMonsters[1], '| always target off', o.alwaysTarget[1] == false)
H.frames(2)
H.print('no plugin: no hook', nameplates.Hook() == nil, '| count', nameplates.Count(), '| said', nameplates.Problem())
o.showPlayers[1] = false
nameplates.SetHidden(Category.Self, true)
H.print('nothing is written', block.Hidden == 0)

-- the plugin loaded: found, and given the settings
loaded = true
H.frames(1)
H.print('plugin loaded: hook', nameplates.Hook() ~= nil, '| no problem', nameplates.Problem() == nil, '| hidden is players', block.Hidden == Category.Player)

-- a change in the plugin, as by its own command, is taken into the settings and saved
local saves = H.saves()
block.Hidden = Category.Player + Category.Npc
block.Options = 1
H.frames(1)
H.print('changed in the plugin: NPCs off', o.showNpcs[1] == false, '| players still off', o.showPlayers[1] == false, '| always target', o.alwaysTarget[1], '| saved', H.saves() > saves)

-- the addon's command
H.print('/name show kept from the game', H.command('/name show players npcs'))
H.print('shown again', o.showPlayers[1] and o.showNpcs[1], '| hidden', block.Hidden)
H.command('/name hide mobs self')
H.print('hide mobs self', block.Hidden == Category.Monster + Category.Self, o.showMonsters[1] == false)
H.command('/name toggle all')
H.print('toggle all', block.Hidden == Category.All - Category.Monster - Category.Self)
H.command('/name hide goblins')
H.print('a word that is no category changes nothing', block.Hidden == Category.All - Category.Monster - Category.Self, '| said:', H.printed[#H.printed])
H.command('/name show all')
H.print('/names is left alone', H.command('/names') == false)

-- a checkbox in the settings window: the fourth, Other Players
local before = H.calls.Begin or 0
H.command('/name'); H.frames(1)
H.print('settings window drawn', (H.calls.Begin or 0) > before, '| checkboxes', H.calls.Checkbox)
local realCheckbox = imgui.Checkbox
imgui.Checkbox = function(id, value) if id == '##name.showPlayers' then value[1] = not value[1] return true end return false end
H.frames(1)
imgui.Checkbox = realCheckbox
H.print('unticked: players hidden in the plugin', block.Hidden == Category.Player, o.showPlayers[1] == false)
H.command('/name')

-- another character's settings are given to the plugin
o.showPlayers[1] = true; o.showAlliance[1] = false; o.alwaysTarget[1] = false
H.resettle(); H.frames(1)
H.print('settings swapped: given to the plugin', block.Hidden == Category.Alliance, block.Options == 0)

-- the names of a frame
local function put(i, index, category, flags, name, text)
    local n = block.Names[i]
    n.EntityIndex, n.ServerId, n.Category, n.Flags = index, 0x1000 + index, category, flags
    n.ScreenX, n.ScreenY = 480, 135
    ffi.copy(n.Name, name); ffi.copy(n.Text, text or name)
end
put(0, 0x401, Category.Party, Flag.Wanted + Flag.Drawn + Flag.OnScreen, 'Buddy', '\146 Buddy')
put(1, 300, Category.Monster, Flag.Wanted + Flag.Drawn, 'Goblin')
put(2, 0x402, Category.Alliance, Flag.OnScreen, 'Ally')
block.Count, block.Sequence = 3, block.Sequence + 1

local seen = {}
for i, name in nameplates.Each() do seen[#seen + 1] = i .. ' ' .. nameplates.Name(name) end
H.print('each name:', table.concat(seen, ', '), '| count', nameplates.Count())
local buddy = nameplates.Find(0x401)
H.print('found by entity:', nameplates.Name(buddy), '| written', #nameplates.Text(buddy), 'bytes | drawn', nameplates.Has(buddy, Flag.Drawn), '| no stars', not nameplates.Has(buddy, Flag.Stars))
-- the plugin's picture is 960 by 540 and imgui's 1920 by 1080
H.print('on screen at', nameplates.Screen(buddy))
H.print('behind the camera: no place', nameplates.Screen(nameplates.Find(300)) == nil, '| no such entity', nameplates.Find(5) == nil)

-- the next frame's names take the place of these
put(0, 300, Category.Monster, Flag.Wanted, 'Goblin')
block.Count, block.Sequence = 1, block.Sequence + 1
H.print('next frame: the party member is gone', nameplates.Find(0x401) == nil, '| the monster is first', nameplates.Find(300).EntityIndex == 300)

-- one entity's name, a claim, and the plugin going away
nameplates.Override(300, false); nameplates.Override(301, true); nameplates.Override(0x900, true)
H.print('overrides', block.Override[300], block.Override[301])
nameplates.Override(300, nil)
H.print('one taken back', block.Override[300], block.Override[301])
nameplates.ClearOverrides()
H.print('all taken back', block.Override[301])
block.Frame = 77
nameplates.Claim(Category.Party + Category.Player)
H.print('claimed', block.Claimed == Category.Party + Category.Player, '| in frame', block.ClaimFrame)

-- custom names: off, nothing is claimed or drawn; on, every name is claimed and the wanted ones set
-- out for the plugin, a quad to a letter
-- The plugin gives its place for them as a 32-bit address, as every address in the game is: here it
-- has to be asked for low enough in memory to be one
ffi.cdef('void* mmap(void*, size_t, int, int, int, long);')
local low = ffi.C.mmap(nil, ffi.sizeof('namehook_draw_t'), 3, 0x62, -1, 0) -- read and write; private, anonymous, 32-bit
local draw = ffi.cast('namehook_draw_t*', low)
draw.QuadsMax = 16384
block.Draw = tonumber(ffi.cast('uintptr_t', low))
block.TargetWidth, block.TargetHeight = 1440, 810 -- the game's picture, half as large again as its window
local glyph = { X0 = 1, Y0 = 2, X1 = 9, Y1 = 14, U0 = 0.25, V0 = 0.5, U1 = 0.3, V1 = 0.6, AdvanceX = 10, Visible = 1 }
local pushed = {}
imgui.PushFont = function(_, size) pushed[#pushed + 1] = size end
local signGlyph = { X0 = 0, Y0 = 1, X1 = 12, Y1 = 13, U0 = 0.7, V0 = 0.7, U1 = 0.8, V1 = 0.8, AdvanceX = 14, Visible = 1 }
local hasSign = true
imgui.GetFontBaked = function() return { FindGlyph = function() return glyph end, FindGlyphNoFallback = function(_, code) return hasSign and code == 0xF002 and signGlyph or nil end } end
local fontTexture = 0x1234
imgui.GetFont = function() return { ContainerAtlas = { TexRef = { GetTexID = function() return fontTexture end }, TexData = { GetTexID = function() return 0 end } } } end

block.Claimed, block.ClaimFrame = 0, 0
put(0, 0x401, Category.Party, Flag.Wanted + Flag.Stars, 'Buddy', '\146 Buddy')
put(1, 0x402, Category.Alliance, 0, 'Ally')
block.Names[0].Scale, block.Names[0].NameColor = 1, 0x80408020
block.Names[1].Scale, block.Names[1].NameColor = 1, 0x80808080
block.Count, block.Sequence = 2, block.Sequence + 1
H.load()
H.frames(1)
H.print('custom off: nothing claimed', block.Claimed == 0, '| nothing set out', draw.QuadCount == 0)
H.print('/name custom kept from the game', H.command('/name custom'), '| on', o.customNames[1], '| said:', H.printed[#H.printed])
block.Frame = 78
H.frames(1)
local buddy = draw.Entities[0x401]
H.print('custom on: all claimed', block.Claimed == Category.All, '| set out in frame', draw.Frame, '| font texture', draw.Textures[0] == 0x1234)
-- five letters; the hidden name is not set out
H.print('the wanted name: quads', buddy.Count, '| of this frame', buddy.Frame == draw.Frame, '| the hidden one: none', draw.Entities[0x402].Frame ~= draw.Frame, '| in all', draw.QuadCount)
-- 15 pixels on the screen is 23 of the game's picture, the largest of the three sizes letters are kept
-- at; the edge 1 pixel of the screen
table.sort(pushed)
H.print('letters kept at', pushed[#pushed], pushed[#pushed - 1], pushed[1], 'pixels | edge', buddy.Edge, '| solid', buddy.Alpha, ('| edge colour %08X'):format(buddy.EdgeColor))
local first = draw.Quads[buddy.First]
-- 50 wide, so it starts 25 left of the middle; the letter's own corner is 1, 2 from there, the line's top on the point
H.print('first letter: corner', first.X0, first.Y0, first.X1, first.Y1, ('| colour %08X'):format(first.Color), '| edged', first.Flags == 1, '| texture', first.Texture)
local last = draw.Quads[buddy.First + 4]
H.print('last letter: 40 further on', last.X0 - first.X0, '| where in the texture', first.U0, first.V1)
-- a name half way to the distance it is no longer drawn at is smaller, and one nearly there fainter:
-- its letters are the next size up's, made smaller to fit, and no size of its own is asked of imgui
local function letterHeight() local q = draw.Quads[buddy.First] return math.floor((q.Y1 - q.Y0) * 100 + 0.5) / 100 end
H.print('at its largest: a letter as it is kept, high', letterHeight())
local sizes = #pushed
block.Names[0].Scale = 0.5; H.frames(5)
H.print('half way: a letter high', letterHeight(), '| solid', buddy.Alpha)
block.Names[0].Scale = 0.075; H.frames(5)
H.print('nearly gone: a letter high', letterHeight(), '| half solid', buddy.Alpha)
for i = sizes + 1, #pushed do if pushed[i] ~= 23 and pushed[i] ~= 17 and pushed[i] ~= 12 then H.print('another size asked for', pushed[i], false) end end
block.Names[0].Scale = 1
-- As a character becomes the target the game gives its name its full size for a frame: not followed.
-- A size that leaps and stays is, a few frames on; and a walk's steps are, at once.
block.Names[0].Scale = 0.425; H.frames(6)
local far = letterHeight()
block.Names[0].Scale = 1; H.frames(1)
local leapt = letterHeight()
block.Names[0].Scale = 0.425; H.frames(1)
H.print('at a distance: a letter high', far, '| full size for one frame: unchanged', leapt == far, '| and after', letterHeight() == far)
block.Names[0].Scale = 1; H.frames(3)
local waiting = letterHeight()
H.frames(2)
H.print('full size that lasts: not yet at three frames', waiting == far, '| taken up by five', letterHeight() == 12)
block.Names[0].Scale = 0.9; H.frames(1)
H.print('a step of a walk: followed at once', letterHeight() < 12 and letterHeight() > far)
block.Names[0].Scale = 1; H.frames(1)
-- a pulse towards white and back, as the game gives the target's name, is not followed: the name
-- keeps the colour the pulse starts from
H.frames(8)
local function pulse(base, frames)
    for i = 1, frames do
        local toWhite = (i % 10) * 12
        local r, g, b = math.floor(base / 0x10000) % 0x100, math.floor(base / 0x100) % 0x100, base % 0x100
        block.Names[0].NameColor = 0x80000000 + math.min(0x80, r + toWhite) * 0x10000 + math.min(0x80, g + toWhite) * 0x100 + math.min(0x80, b + toWhite)
        H.frames(1)
    end
    return draw.Quads[buddy.First].Color
end
H.print(('pulsing: still drawn %08X'):format(pulse(0x408020, 120)))
-- the name goes red as the fight begins, pulsing all the while: taken up within a pulse
H.print(('pulsing in another colour: drawn %08X'):format(pulse(0x800000, 12)))
H.print(('and kept %08X'):format(pulse(0x800000, 120)))
-- and back to a weaker colour: taken up once the stronger has not been seen for a while
H.print(('pulsing in a weaker colour: drawn %08X'):format(pulse(0x606020, 120)))
block.Names[0].NameColor = 0x80101010; H.frames(5)
H.print(('a colour that stays: taken up at once %08X'):format(draw.Quads[buddy.First].Color))
o.outline[1] = 0; H.frames(1)
H.print('no outline: no edge', buddy.Edge)
-- while the font has no texture nothing is set out, and what was is left to go stale
fontTexture = 0; local frameBefore = draw.Frame; block.Frame = 90; block.ClaimFrame = 0; H.frames(1)
H.print('no font texture: nothing set out', draw.Frame == frameBefore, '| nor claimed', block.ClaimFrame == 0)
fontTexture = 0x5678; H.frames(1)
H.print('another texture: taken up', draw.Textures[0] == 0x5678, draw.Frame == 90)
-- two icons before a name: 2 pixels of the screen between them, and Icon Spacing between the last and the name
local icons = require('icons')
local realHas, realPlace, realTexture = icons.Has, icons.Place, icons.Texture
icons.Has = function(byte) return byte == 0x92 or byte == 0x93 end
icons.Place = function() return { 0, 0, 0.125, 0.125 } end
icons.Texture = function() return 0x4321 end
ffi.copy(block.Names[0].Text, '\146\147 Buddy'); H.frames(1)
local function gapToName()
    H.frames(1)
    local q = draw.Quads
    -- the three stars, the two icons, then the letters; a letter's own corner is 1 in from where it is put
    local first = buddy.First + 3
    return q[first + 1].X0 - q[first].X1, (q[first + 2].X0 - 1) - q[first + 1].X1
end
H.print('icons: quads', buddy.Count, '| between the icons, and before the name', gapToName())
o.iconSpacing[1] = 10
H.print('Icon Spacing 10: between the icons, and before the name', gapToName())
o.iconSpacing[1] = 0
H.print('Icon Spacing 0:', gapToName())
o.iconSpacing[1] = 2
icons.Has, icons.Place, icons.Texture = realHas, realPlace, realTexture
ffi.copy(block.Names[0].Text, 'Buddy'); H.frames(1)

-- how a name is written is a line of its player's: [name], [distance], and the rest as typed
local format = require('format')
local function parts(text)
    local out = {}
    for _, part in ipairs(format.Compile(text)) do
        out[#out + 1] = (part.kind == 'text' and ('"' .. part.text .. '"') or part.kind) .. (part.color and (':%08X'):format(part.color) or '')
    end
    return table.concat(out, ' ')
end
H.print('a line taken apart:', parts('[name] ([distance])'))
H.print('one thing in a colour, and a stretch of them:', parts('[Name:#F80] <[yellow][ distance ]y[/]> [distance:#102030]'))
H.print('what is not known is written as it is:', parts('[lvl] [name:nocolour] [open'), '| distance wanted', format.Compile('[lvl]').distance, format.Compile('x[distance]').distance)

local memory = AshitaCore.GetMemoryManager()
local asked = 0
memory.GetEntity = function() return { GetDistance = function(_, index) asked = asked + 1 return index == 300 and 151.29 or 4 end } end
AshitaCore.GetMemoryManager = function() return memory end
put(1, 300, Category.Monster, Flag.Wanted, 'Goblin')
block.Names[1].Scale, block.Names[1].NameColor = 1, 0x80808080
block.Count, block.Sequence = 2, block.Sequence + 1
H.frames(1)
H.print('as it starts, the name alone: the monster, quads', draw.Entities[300].Count, '| nothing asked of the game', asked == 0)
-- "Goblin 12.3y": twelve characters, the space among them a letter here
o.monsterFormat[1] = '[name] [distance:yellow]y'; H.frames(1)
local goblin = draw.Entities[300]
H.print('with its distance: the monster, quads', goblin.Count, '| the player as before', buddy.Count, '| asked once', asked == 1)
H.print(('the name in its own colour %08X, the distance in yellow %08X, what follows in its own %08X'):format(
    draw.Quads[goblin.First].Color, draw.Quads[goblin.First + 7].Color, draw.Quads[goblin.First + 11].Color))
-- for the target only: another line for the monster that is the target
o.monsterFormat[1] = '[name]'; o.targetFormat[1] = '<[name]> [distance]'; H.frames(1)
H.print('a line for the target, not the target: quads', goblin.Count)
block.Names[1].Flags = Flag.Wanted + Flag.Target; H.frames(1)
H.print('and the target: quads', goblin.Count)
o.targetFormat[1] = ''
-- a player's line: the distance there too, if asked for
o.nameFormat[1] = '[distance] [name]'; H.frames(1)
H.print('a player with a distance before the name: quads', buddy.Count)
o.nameFormat[1] = '[name]'
block.Count = 1

-- [level]: the levels a monster can be, from the area's tables: by its index, or failing that its name
local levels = require('levels')
H.print('[level] is a thing:', parts('[name] Lv[level:grey]'), '| wanted', format.Compile('[level]').level)
local zone = dofile('addons/name/data/100.lua') -- West Ronfaure, as copied from mobdb
H.print('the copied tables read: by index, a Forest Hare', zone.Indices[60].Name, zone.Indices[60].MinLevel, zone.Indices[60].MaxLevel)
levels.Set(zone)
H.print('by index', levels.Of(60, 'Whatever'), '| by name', levels.Of(9999, 'Bomb'), '| not in them', levels.Of(9999, 'Nobody') == nil)
levels.Set({ Indices = { [300] = { MinLevel = 8, MaxLevel = 8 } }, Names = { Goblin = { MinLevel = 1, MaxLevel = 99 } } })
put(1, 300, Category.Monster, Flag.Wanted, 'Goblin')
block.Names[1].Scale, block.Names[1].NameColor = 1, 0x80808080
block.Count, block.Sequence = 2, block.Sequence + 1
-- "Goblin L8": the index's one level, not the name's range
o.monsterFormat[1] = '[name] L[level]'; H.frames(1)
H.print('a monster of one level: quads', draw.Entities[300].Count)
-- a monster the tables do not have: "Wolf L", the level writing nothing
put(1, 301, Category.Monster, Flag.Wanted, 'Wolf'); block.Names[1].Scale, block.Names[1].NameColor = 1, 0x80808080; H.frames(1)
H.print('one not in the tables: quads', draw.Entities[301].Count)
levels.Set(nil); block.Names[1].ServerId = 9; H.frames(1)
H.print('no tables for the area: quads', draw.Entities[301].Count)

-- a monster its player checks is written with the level the game's answer gives, until it dies or the
-- area is left
struct.unpack = function(kind, raw, at)
    local value = 0
    for i = (kind == 'I' and 3 or 1), 0, -1 do value = value * 256 + (raw:byte(at + i) or 0) end
    return value
end
local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function u32(n) return u16(n % 65536) .. u16(math.floor(n / 65536)) end
-- the game's message about a target: who, the target, two values, their indexes, which message
local function message(targetId, value, value2, targetIndex, number)
    return u32(0) .. u32(1) .. u32(targetId) .. u32(value) .. u32(value2) .. u16(0x400) .. u16(targetIndex) .. u16(number) .. u16(0)
end
local alive = { [300] = { id = 0x1000 + 300, hp = 100 } }
memory.GetEntity = function() return {
    GetDistance = function() return 4 end,
    GetServerId = function(_, index) return alive[index] and alive[index].id or 0 end,
    GetHPPercent = function(_, index) return alive[index] and alive[index].hp or 0 end } end
o.showCheckDetails[1] = false -- looked at by itself further down
levels.Set({ Indices = { [300] = { MinLevel = 8, MaxLevel = 10 } }, Names = {} })
put(1, 300, Category.Monster, Flag.Wanted, 'Goblin'); block.Names[1].Scale, block.Names[1].NameColor = 1, 0x80808080
H.frames(1)
-- "Goblin L8-10", then checked and found to be 9: "Goblin L9"
H.print('before it is checked: the range, quads', draw.Entities[300].Count, '|', levels.Of(300, 'Goblin', 0x1000 + 300))
o.monsterFormat[1] = '[name] L[level][checked:yellow]'; H.frames(1)
H.print('[checked] is a thing:', parts('[checked:yellow]'), '| not yet checked: nothing more written, quads', draw.Entities[300].Count)
H.packetData(0x029, message(0x1000 + 300, 9, 0x43, 300, 173)); H.frames(1)
local goblin = draw.Entities[300]
local glass = draw.Quads[goblin.First + goblin.Count - 1]
-- "Goblin L9" and the magnifying glass after it, in yellow, from where the font keeps it
H.print('checked: its level and the glass, quads', goblin.Count, '|', levels.Of(300, 'Goblin', 0x1000 + 300), '| is checked', levels.IsChecked(300, 0x1000 + 300))
-- as the font has it the glass is 12 wide and 12 high, from 1 to 13 of a line of 23: drawn at seven
-- tenths of that, about the middle of the line
H.print(('the glass: wide %.1f, high %.1f, from %.2f down | colour %08X | where in the texture %.1f'):format(glass.X1 - glass.X0, glass.Y1 - glass.Y0, glass.Y0, glass.Color, glass.U0))
block.Names[1].Scale = 0.5; H.frames(5)
glass = draw.Quads[goblin.First + goblin.Count - 1]
local letter = draw.Quads[goblin.First]
H.print(('a name half way off: the glass high %.2f beside a letter high %.2f, still seven tenths as large'):format(glass.Y1 - glass.Y0, letter.Y1 - letter.Y0),
    math.abs((glass.Y1 - glass.Y0) / (letter.Y1 - letter.Y0) - 0.7) < 0.001)
block.Names[1].Scale = 1; H.frames(5)
o.monsterFormat[1] = '[name] L[level]'; H.frames(1)
H.print('without it: quads', goblin.Count)
-- a line of its own for a monster that has been checked: empty, nothing is different; set, it is
-- written by that line, and by it before the target's
o.monsterFormat[1] = '[name]'; H.frames(1)
H.print('Checked Monster Format empty: the monster as any other, quads', goblin.Count)
o.checkedFormat[1] = '[name] [level]!'; H.frames(1)
H.print('set: "Goblin 9!", quads', goblin.Count)
o.targetFormat[1] = '<[name]>'; block.Names[1].Flags = Flag.Wanted + Flag.Target; H.frames(1)
H.print('checked and the target: still by the checked line, quads', goblin.Count)
o.checkedFormat[1] = ''; H.frames(1)
H.print('emptied again: by the target\'s line, quads', goblin.Count)
o.targetFormat[1] = ''; block.Names[1].Flags = Flag.Wanted
o.checkedFormat[1] = '[name] [level]!'; o.monsterFormat[1] = '[name] L[level]'; H.frames(1)
-- a message of the same number that is no check, and one about damage, change nothing
H.packetData(0x029, message(0x1000 + 300, 50, 7, 300, 173)); H.packetData(0x029, message(0x1000 + 300, 120, 0, 300, 1))
H.print('other messages: still', levels.Of(300, 'Goblin', 0x1000 + 300), '| another with its index is not it', levels.Of(300, 'Goblin', 0x2000))
alive[300].hp = 0; H.frames(1)
-- under a checked monster's name: how hard it was said to be, what it does, and what it links with
o.checkedFormat[1] = ''; o.monsterFormat[1] = '[name]'; o.showCheckDetails[1] = true
alive[300] = { id = 0x1000 + 300, hp = 100 }
local custom = require('custom'); custom.SetSheets(0x7777, 0x8888)
levels.Set({ Indices = { [300] = { MinLevel = 8, MaxLevel = 10, Aggro = true, Notorious = false, Sight = true, Sound = true, Link = true, Family = 'Goblin' } }, Names = {} })
H.frames(1)
H.print('not checked: the name alone, quads', goblin.Count)
H.packetData(0x029, message(0x1000 + 300, 9, 0x46, 300, 174)); H.frames(2)
H.print('checked, said to be', levels.Checked(300, 0x1000 + 300).hard, '| the name and its line, quads', goblin.Count, '| the two sheets of signs given to the plugin', draw.Textures[2] == 0x7777, draw.Textures[3] == 0x8888)
-- "Goblin" (6), then "Very Tough" (10 with its space), aggressive, sight, sound (3 signs), the link sign, "Goblin" (6)
local quads = {}
for i = 0, goblin.Count - 1 do local q = draw.Quads[goblin.First + i]; quads[#quads + 1] = q end
local nameLeft, nameRight = quads[1].X0, quads[6].X1
local lineLeft, lineRight = quads[7].X0, quads[#quads].X1
H.print('its middle under the name\'s', math.abs((nameLeft + nameRight) / 2 - (lineLeft + lineRight) / 2) < 1.6, '| below it', quads[7].Y0 > quads[1].Y1, '| smaller', (quads[7].Y1 - quads[7].Y0) < (quads[1].Y1 - quads[1].Y0))
local signs = {}
for _, q in ipairs(quads) do if q.Texture >= 2 then signs[#signs + 1] = ('%d:%.2f,%.2f'):format(q.Texture, q.U0, q.V0) end end
-- from the aggro sheet, an aggressive monster of level 9 (the seventh sign: the second row's third); then
-- from the other, sight and sound (the second row's first and third) and link (the last row's last)
H.print('the signs, by sheet and where they are in it:', table.concat(signs, ' '))
-- it fades in as the monster is checked, is there five seconds, and fades out; a frame here is 0.03s
local function lineAlpha() return goblin.Count > 6 and math.floor(draw.Quads[goblin.First + 6].Color / 0x1000000) or 0 end
H.packetData(0x029, message(0x1000 + 300, 9, 0x46, 300, 174)); H.frames(1)
local coming = lineAlpha()
H.frames(4); local halfIn = lineAlpha()
H.frames(10); local there = lineAlpha()
H.print('just checked: faint', coming > 0 and coming < 64, '| coming', halfIn > coming and halfIn < 255, '| there', there == 255, '| the name as solid as ever', math.floor(draw.Quads[goblin.First].Color / 0x1000000) == 255)
H.frames(150); local still = lineAlpha()
H.frames(15); local going = lineAlpha()
H.frames(25); local gone = lineAlpha()
H.print('after 4.9s: still there', still == 255, '| after 5.4: going', going > 0 and going < 255, '| after 6.1: gone, the name alone, quads', gone == 0 and goblin.Count == 6, '| still known as checked', levels.IsChecked(300, 0x1000 + 300))
H.packetData(0x029, message(0x1000 + 300, 9, 0x46, 300, 174)); H.frames(20)
H.print('checked again: back', lineAlpha() == 255)
o.showCheckDetails[1] = false; H.frames(1)
H.print('Show Check Details off: the name alone, quads', goblin.Count)
-- [aggro]: the sign that it is aggressive, before its name, whether or not it has been checked
o.monsterFormat[1] = '[aggro][name]'; H.frames(1)
local first = draw.Quads[goblin.First]
H.print('[aggro] is a thing:', parts('[aggro][name]'), '| quads', goblin.Count, ('| the sign first: texture %d, at %.2f,%.2f, %d square'):format(first.Texture, first.U0, first.V0, first.X1 - first.X0),
    '| the name after it', draw.Quads[goblin.First + 1].X0 >= first.X1)
-- which of the twelve signs: six for one that is not aggressive and six for one that is, the first
-- five of each by level and the sixth a notorious monster's
local function sign(monster, checkedAs)
    levels.Set({ Indices = { [300] = monster }, Names = {} })
    if checkedAs then H.packetData(0x029, checkedAs) end
    H.frames(1)
    local q = draw.Quads[goblin.First]
    return math.floor(q.V0 * 4 + 0.5) * 4 + math.floor(q.U0 * 4 + 0.5) + 1
end
alive[300].hp = 0; H.frames(1); alive[300].hp = 100 -- what the last check found is forgotten
local byLevel = {}
for _, level in ipairs({ 1, 19, 20, 37, 38, 56, 57, 74, 75, 99 }) do
    byLevel[#byLevel + 1] = level .. ':' .. sign({ MinLevel = 1, MaxLevel = level, Aggro = false })
end
H.print('not aggressive, by the highest level it can be:', table.concat(byLevel, ' '))
H.print('aggressive: level 10', sign({ MinLevel = 8, MaxLevel = 10, Aggro = true }), '| level 80', sign({ MinLevel = 78, MaxLevel = 80, Aggro = true }),
    '| notorious, whatever its level', sign({ MinLevel = 5, MaxLevel = 6, Aggro = true, Notorious = true }), sign({ MinLevel = 5, MaxLevel = 6, Aggro = false, Notorious = true }))
-- the level a check finds comes before the tables', and one impossible to gauge is as a notorious monster
H.print('said by the tables to be 30 to 40 and found by a check to be 30:', sign({ MinLevel = 30, MaxLevel = 40, Aggro = true }, message(0x1000 + 300, 30, 0x44, 300, 174)),
    '| found impossible to gauge:', sign({ MinLevel = 30, MaxLevel = 40, Aggro = true }, message(0x1000 + 300, 0, 0, 300, 249)))
alive[300].hp = 0; H.frames(1); alive[300].hp = 100
o.monsterFormat[1] = '[name]'; H.frames(1)
o.showCheckDetails[1] = true
-- one that does not link, and is not aggressive: the passive sign alone after the words
levels.Set({ Indices = { [300] = { MinLevel = 8, MaxLevel = 10, Aggro = false, Sight = true, Link = false, Family = 'Goblin' } }, Names = {} })
H.packetData(0x029, message(0x1000 + 300, 9, 0x40, 300, 174)); H.frames(1)
signs = {}
for i = 0, goblin.Count - 1 do local q = draw.Quads[goblin.First + i]; if q.Texture >= 2 then signs[#signs + 1] = ('%d:%.2f,%.2f'):format(q.Texture, q.U0, q.V0) end end
H.print('a passive one, said to be', levels.Checked(300, 0x1000 + 300).hard, '| signs', table.concat(signs, ' '), '| quads', goblin.Count)
-- one the tables do not have: the words alone; and one impossible to gauge
levels.Set(nil)
H.packetData(0x029, message(0x1000 + 300, 0, 0, 300, 249)); H.frames(1)
H.print('not in the tables, and impossible to gauge:', levels.Checked(300, 0x1000 + 300).hard, '| no level', levels.Of(300, 'Goblin', 0x1000 + 300) == nil, '| quads', goblin.Count)
-- five minutes after it was checked it is forgotten, alive or not
H.frames(9990); H.print('after 4m59s: still known', levels.IsChecked(300, 0x1000 + 300))
H.frames(20); H.print('after 5m: forgotten', levels.IsChecked(300, 0x1000 + 300) == false)
H.packetData(0x029, message(0x1000 + 300, 0, 0, 300, 249)); H.frames(1)
alive[300].hp = 0; H.frames(1)
H.print('dead: the name alone again, quads', goblin.Count)
alive[300].hp = 100
levels.Set({ Indices = { [300] = { MinLevel = 8, MaxLevel = 10 } }, Names = {} })
o.monsterFormat[1] = '[name] L[level]'; o.checkedFormat[1] = '[name] [level]!'
H.packetData(0x029, message(0x1000 + 300, 9, 0x43, 300, 173)); o.showCheckDetails[1] = false; H.frames(1)
alive[300].hp = 0; H.frames(1)
H.print('dead: the range again, quads', draw.Entities[300].Count, '|', levels.Of(300, 'Goblin', 0x1000 + 300))
alive[300].hp = 100; o.showCheckDetails[1] = true
o.checkedFormat[1] = ''
alive[300].hp = 100
H.packetData(0x029, message(0x1000 + 300, 10, 0x44, 300, 174))
H.packetData(0x029, message(0x1000 + 300, 0, 0, 300, 6))
H.print('checked again, then said to be defeated:', levels.Of(300, 'Goblin', 0x1000 + 300))
H.packetData(0x029, message(0x1000 + 300, 10, 0x44, 300, 174))
alive[300] = nil; H.frames(1)
H.print('checked again, then gone from sight:', levels.Of(300, 'Goblin', 0x1000 + 300))
H.packetData(0x029, message(0x1000 + 300, 10, 0x44, 300, 174))
local before = levels.Of(300, 'Goblin', 0x1000 + 300)
H.packetData(0x00A, string.rep('\0', 0x100))
H.print('checked again:', before, '| then the area left: forgotten', levels.Of(300, 'Goblin', 0x1000 + 300) == nil)
levels.Set(nil)
o.monsterFormat[1] = '[name]'
block.Count = 1

-- the settings of 1.10 are made the lines that say the same
o.showDistance, o.distanceTargetOnly = T{ true }, T{ true }
H.resettle()
H.print('distance for the target only, brought over:', o.monsterFormat[1], '|', o.targetFormat[1], '| the old settings gone', o.showDistance == nil)
o.targetFormat[1] = ''; H.frames(1)

-- a size is pushed on imgui once a frame however many names are of it, and the plugin is asked after
-- once a frame whatever is done with it
put(1, 0x403, Category.Player, Flag.Wanted, 'Stranger'); put(2, 0x404, Category.Player, Flag.Wanted, 'Friend')
for i = 1, 2 do block.Names[i].Scale, block.Names[i].NameColor = 1, 0x80808080 end
block.Count, block.Sequence = 3, block.Sequence + 1
local pushes, asked = #pushed, 0
local realIsLoaded = manager.IsLoaded
manager.IsLoaded = function(...) asked = asked + 1 return realIsLoaded(...) end
H.frames(1)
manager.IsLoaded = realIsLoaded
H.print('three names: sizes pushed', #pushed - pushes, '| the plugin asked after', asked, '| all set out', draw.Entities[0x403].Count, draw.Entities[0x404].Count)
-- a name written otherwise is taken apart again
ffi.copy(block.Names[1].Text, 'Other'); H.frames(1)
H.print('another name for the same entity: quads', draw.Entities[0x403].Count)
block.Count = 1
H.tab(2); H.command('/name'); local sliders = H.calls.SliderInt or 0; H.frames(1); H.command('/name'); H.tab(1)
H.print('its tab drawn: sliders', (H.calls.SliderInt or 0) - sliders)
block.Hooked = 0; block.Claimed = 0; H.frames(1)
H.print('a client not recognised: nothing claimed', block.Claimed == 0)
block.Hooked = 1
H.command('/name custom off'); block.Claimed = 0; H.frames(1)
H.print('custom off again', o.customNames[1] == false, block.Claimed == 0)

-- the library's own calls: a name that is not begun takes no quads, and one too long is cut off
block.Frame = 95
H.print('drawing begun: scale', nameplates.BeginDrawing())
nameplates.Quad(0, 0, 1, 1, 0, 0, 1, 1, 0xFFFFFFFF, 0, false)
H.print('no name begun: no quad', draw.QuadCount == 0, '| a name out of range refused', nameplates.BeginName(0x900, 1, 0, 0) == false)
nameplates.BeginName(5, 0.5, 2, 0xFF000000)
for _ = 1, 300 do nameplates.Quad(0, 0, 1, 1, 0, 0, 1, 1, 0xFFFFFFFF, 1, false) end
nameplates.EndName()
H.print('a long name: quads', draw.Entities[5].Count, '| in all', draw.QuadCount, '| texture slot', draw.Quads[0].Texture)
nameplates.SetTexture(9, 1); nameplates.SetTexture(7, 77)
H.print('texture slots', draw.Textures[7])

block.Hooked = 0
H.print('a client not recognised:', nameplates.Problem())
block.Hooked = 1
block.Version = 1
loaded = false; H.frames(1); loaded = true
H.print('a plugin of another version: no hook', nameplates.Hook() == nil, '|', nameplates.Problem())
loaded = false
H.print('unloaded: no hook', nameplates.Hook() == nil, '| count', nameplates.Count(), '| nothing found', nameplates.Find(300) == nil)
H.unload()
