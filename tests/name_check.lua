-- name and winxi.nameplates: the addon's settings and the plugin's are kept the same, and the
-- plugin's names are read. The plugin here is a block of the same shape, made in this file.
local ffi = require('ffi')
local imgui = require('imgui')
local nameplates = require('winxi.nameplates')
local Category, Flag = nameplates.Category, nameplates.Flag
local renderer = require('custom')
local frameForTests = renderer.Frame
local suppliedFormats
-- Exercise arbitrary renderer formats as fixtures; production fixes only the player-name baseline.
renderer.Frame = function(options, hook, formats)
    suppliedFormats = formats
    return frameForTests(options, hook)
end
local o = H.options()
H.print('preferred live defaults loaded', o.font == 'trebucbi.ttf', o.fontSize[1] == 32, not o.fontBold[1], o.checkSize[1] == 90,
    not o.showSelf[1], not o.showPlayers[1], not o.showPets[1], o.alwaysTarget[1], o.gdiFonts == nil)
-- Use a deterministic rendering fixture independent of preferred user defaults.
require('custom').Defaults(o)
for _, key in ipairs({ 'showSelf', 'showParty', 'showAlliance', 'showPlayers', 'showMyPet', 'showPets', 'showNpcs', 'showMonsters' }) do o[key][1] = true end
o.alwaysTarget[1] = false

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
H.print('production supplies preferred baseline formats', suppliedFormats ~= nil and suppliedFormats.nameFormat[1] == '[name]',
    suppliedFormats ~= nil and suppliedFormats.monsterFormat[1] == '[aggro] Lv [level]. [name]',
    suppliedFormats ~= nil and suppliedFormats.targetFormat == nil and suppliedFormats.checkedFormat == nil)
H.print('plugin loaded: hook', nameplates.Hook() ~= nil, '| no problem', nameplates.Problem() == nil, '| hidden is players', block.Hidden == Category.Player)

-- a change in the plugin, as by its own command, is taken into the settings and saved
local saves = H.saves()
block.Hidden = Category.Player + Category.Npc
block.Options = 1
H.frames(1)
H.print('changed in the plugin: NPCs off', o.showNpcs[1] == false, '| players still off', o.showPlayers[1] == false, '| always target', o.alwaysTarget[1], '| saved', H.saves() > saves)

-- Text controls are disabled in this ImGui-only test build.
H.command('/name show players npcs'); H.command('/name hide mobs self'); H.command('/name toggle all')
H.print('text controls consumed without changing filters', block.Hidden == Category.Player + Category.Npc, not o.showPlayers[1], o.showMonsters[1])
for _, key in ipairs({ 'showSelf', 'showParty', 'showAlliance', 'showPlayers', 'showMyPet', 'showPets', 'showNpcs', 'showMonsters' }) do o[key][1] = true end
H.resettle(); H.frames(1)
H.print('/names is left alone', H.command('/names') == false)

-- a checkbox in Filters (the second tab): the fourth, Other Players
H.tab(2)
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
-- The rendering fixture's actual output matches its window; menu coordinates alone
-- no longer determine font scaling. Screen() above separately tests a larger display.
imgui.GetIO = function() return { DisplaySize = { x = 960, y = 540 } } end
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
H.print('rendering on by default', block.Claimed ~= 0, '| retired setting absent', o.customNames == nil)
H.print('/name custom compatibility command kept from the game', H.command('/name custom'), '| said:', H.printed[#H.printed])
block.Frame = 78
H.frames(1)
local buddy = draw.Entities[0x401]
H.print('custom on: all claimed', block.Claimed == Category.All, '| set out in frame', draw.Frame, '| font texture', draw.Textures[0] == 0x1234)
-- five letters; the hidden name is not set out
H.print('the wanted name: quads', buddy.Count, '| of this frame', buddy.Frame == draw.Frame, '| the hidden one: none', draw.Entities[0x402].Frame ~= draw.Frame, '| in all', draw.QuadCount)
-- 15 pixels on the screen is 23 of the game's picture, the largest of the three sizes letters are kept
-- at; the edge is snapped after conversion to render-target pixels
table.sort(pushed)
H.print('letters kept at', pushed[#pushed], pushed[#pushed - 1], pushed[1], 'pixels | edge', buddy.Edge, '| solid', buddy.Alpha, ('| edge colour %08X'):format(buddy.EdgeColor))
H.print('outline at 1.5x: rounded down to one render-target pixel', buddy.Edge == 1)
local originalTargetWidth = block.TargetWidth
block.TargetWidth = block.Width * 1.25; H.frames(1)
H.print('outline at 1.25x: snapped to one render-target pixel', buddy.Edge == 1)
o.outline[1] = 2
block.TargetWidth = originalTargetWidth; H.frames(1)
H.print('thicker outline setting remains available', buddy.Edge == 3)
o.outline[1] = 1
block.TargetWidth = block.Width * 0.25; H.frames(1)
H.print('enabled outline never thinner than one render-target pixel', buddy.Edge == 1)
block.TargetWidth = originalTargetWidth; H.frames(1)
local nearbyOutlineColor = buddy.EdgeColor
local first = draw.Quads[buddy.First]
-- 50 wide, so it starts 25 left of the middle; the letter's own corner is 1, 2 from there, the line's top on the point
H.print('first letter: corner', first.X0, first.Y0, first.X1, first.Y1, ('| colour %08X'):format(first.Color), '| edged', first.Flags == 1, '| texture', first.Texture)
local last = draw.Quads[buddy.First + 4]
H.print('last letter: 40 further on', last.X0 - first.X0, '| where in the texture', first.U0, first.V1)
local normalCount, normalEdge, normalSpacing = buddy.Count, buddy.Edge, last.X0 - first.X0
o.fontBold[1] = true; H.frames(1)
local boldFirst, boldCopy = draw.Quads[buddy.First], draw.Quads[buddy.First + 1]
H.print('bold default font: extra fill stroke, same outline thickness', buddy.Count == normalCount * 2, boldCopy.X0 - boldFirst.X0 == 1, buddy.Edge == normalEdge)
H.print('bold copy retains texture and colour', boldFirst.U0 == boldCopy.U0, boldFirst.Color == boldCopy.Color, boldFirst.Texture == boldCopy.Texture)
o.fontBold[1] = false; H.frames(1)
H.print('bold off restores count and spacing', buddy.Count == normalCount, last.X0 - first.X0 == normalSpacing)
-- a name half way to the distance it is no longer drawn at is smaller, and one nearly there fainter:
-- its letters are the next size up's, made smaller to fit, and no size of its own is asked of imgui
local function letterHeight() local q = draw.Quads[buddy.First] return math.floor((q.Y1 - q.Y0) * 100 + 0.5) / 100 end
H.print('at its largest: a letter as it is kept, high', letterHeight())
local sizes = #pushed
block.Names[0].Scale = 0.5; H.frames(5)
H.print('half way: a letter high', letterHeight(), '| solid', buddy.Alpha)
block.Names[0].Scale = 0.075; H.frames(5)
H.print('nearly gone: a letter high', letterHeight(), '| half solid', buddy.Alpha)
H.print('distant outline: stays thin, pixel-snapped and less opaque', buddy.Edge == 1, buddy.Edge == math.floor(buddy.Edge),
    math.floor(buddy.EdgeColor / 0x1000000) < math.floor(nearbyOutlineColor / 0x1000000), buddy.EdgeColor % 0x1000000 == nearbyOutlineColor % 0x1000000)
o.shrink = { false }; H.frames(1)
H.print('old shrink opt-out no longer affects automatic shrinking', buddy.Edge == 1, buddy.EdgeColor ~= nearbyOutlineColor)
o.shrink = nil; H.frames(1)
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
H.print('no outline: no edge', buddy.Edge, '| remains disabled', buddy.Edge == 0)
-- while the font has no texture nothing is set out, and what was is left to go stale
fontTexture = 0; local frameBefore = draw.Frame; block.Frame = 90; block.ClaimFrame = 0; H.frames(1)
H.print('no font texture: nothing set out', draw.Frame == frameBefore, '| nor claimed', block.ClaimFrame == 0)
fontTexture = 0x5678; H.frames(1)
H.print('another texture: taken up', draw.Textures[0] == 0x5678, draw.Frame == 90)
-- two icons before a name: 2 pixels of the screen between them, and Icon Spacing between the last and the name
local icons = require('icons')
local realHas, realPlace, realTexture = icons.Has, icons.Place, icons.Texture
icons.Has = function() return false end
icons.Place = function() return false end
icons.Texture = function() return 0x4321 end
ffi.copy(block.Names[0].Text, '\146\147 Buddy'); H.frames(1)
local withoutIcons = buddy.Count
icons.Has = function(byte) return byte == 0x92 or byte == 0x93 end
icons.Place = function() return { 0, 0, 0.125, 0.125 } end
H.frames(1)
-- Neither the text nor texture changed: parsing must not permanently discard unavailable icons.
assert(buddy.Count == withoutIcons + 5, 'delayed player icons and mastery stars must recover')
H.print('unchanged names recover delayed player icons and stars', buddy.Count == withoutIcons + 5)
local function gapToName()
    H.frames(1)
    local q = draw.Quads
    -- the three stars, the two icons, then the letters; a letter's own corner is 1 in from where it is put
    local first = buddy.First + 3
    return q[first + 1].X0 - q[first].X1, (q[first + 2].X0 - 1) - q[first + 1].X1
end
H.print('icons: quads', buddy.Count, '| between the icons, and before the name', gapToName())
do
    local pearl, flag = draw.Quads[buddy.First + 3], draw.Quads[buddy.First + 4]
    H.print('player icons receive softened outlines; stars unchanged', pearl.Flags == 3, flag.Flags == 3,
        pearl.Reserved == 191, flag.Reserved == 191, draw.Quads[buddy.First].Flags == 0)
    local edge = o.outline[1]
    o.outline[1] = 0; H.frames(1)
    H.print('outline zero disables player icon edges too', buddy.Edge == 0)
    o.outline[1] = edge; H.frames(1)
end
o.iconSpacing[1] = 10
H.print('Icon Spacing 10: between the icons, and before the name', gapToName())
o.iconSpacing[1] = 0
H.print('Icon Spacing 0:', gapToName())
o.iconSpacing[1] = 2
icons.Has = function(byte) return byte == 0xAC end
ffi.copy(block.Names[0].Text, '\172 Buddy'); H.frames(1)
H.print('both halves of two-part player icon outlined', draw.Quads[buddy.First + 3].Flags == 3, draw.Quads[buddy.First + 4].Flags == 3)
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
-- Target formats an older version saved must not affect ordinary or targeted mob nameplates.
o.monsterFormat[1] = '[name]'; o.targetFormat = T{ '<[name]> [distance]' }; H.frames(1)
assert(goblin.Count == 6)
H.print('legacy target format ignored for ordinary mobs', true)
block.Names[1].Flags = Flag.Wanted + Flag.Target; H.frames(1)
assert(goblin.Count == 6)
H.print('targeted mobs use the same mob format', true)
o.targetFormat = T{ '' }
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
-- Legacy checked/targeted overrides must be ignored, even when both apply.
o.monsterFormat[1] = '[name]'; H.frames(1)
H.print('Checked Monster Format empty: the monster as any other, quads', goblin.Count)
o.checkedFormat = T{ '[name] [level]!' }; H.frames(1)
assert(goblin.Count == 6)
H.print('saved checked override ignored', true)
o.targetFormat = T{ '<[name]>' }; block.Names[1].Flags = Flag.Wanted + Flag.Target; H.frames(1)
assert(goblin.Count == 6)
H.print('checked and targeted mobs still use Mob Format', true)
o.monsterFormat[1] = '<[name]>'; H.frames(1)
assert(goblin.Count == 8, 'editing Mob Format must update checked and targeted mobs too')
o.monsterFormat[1] = '[name]'
o.checkedFormat = T{ '' }; H.frames(1)
assert(goblin.Count == 6)
H.print('clearing checked override does not activate target override', true)
o.targetFormat = T{ '' }; block.Names[1].Flags = Flag.Wanted
o.checkedFormat = T{ '[name] [level]!' }; o.monsterFormat[1] = '[name] L[level]'; H.frames(1)
-- a message of the same number that is no check, and one about damage, change nothing
H.packetData(0x029, message(0x1000 + 300, 50, 7, 300, 173)); H.packetData(0x029, message(0x1000 + 300, 120, 0, 300, 1))
H.print('other messages: still', levels.Of(300, 'Goblin', 0x1000 + 300), '| another with its index is not it', levels.Of(300, 'Goblin', 0x2000))
alive[300].hp = 0; H.frames(1)
-- under a checked monster's name: how hard it was said to be, what it does, and what it links with
o.checkedFormat = T{ '' }; o.monsterFormat[1] = '[name]'; o.showCheckDetails[1] = true
alive[300] = { id = 0x1000 + 300, hp = 100 }
local custom = require('custom'); custom.SetSheets(0x7777, 0x8888)
levels.Set({ Indices = { [300] = { MinLevel = 8, MaxLevel = 10, Aggro = true, Notorious = false, Sight = true, Sound = true, Link = true, Family = 'Goblin' } }, Names = {} })
H.frames(1)
H.print('not checked: the name alone, quads', goblin.Count)
H.packetData(0x029, message(0x1000 + 300, 9, 0x46, 300, 174)); H.frames(2)
H.print('checked, said to be', levels.Checked(300, 0x1000 + 300).hard, '| the name and its line, quads', goblin.Count, '| the two sheets of signs given to the plugin', draw.Textures[2] == 0x7777, draw.Textures[3] == 0x8888)
-- "Goblin" (6), then "VT" (2), sight and sound (2 signs),
-- the link sign, "Goblin (Sight/Hearing)" (22).
H.print('compact difficulty default with link senses in icon mode', o.abbreviateDifficulty[1], levels.Checked(300, 0x1000 + 300).hardShort == 'VT', goblin.Count == 34)
local quads = {}
for i = 0, goblin.Count - 1 do local q = draw.Quads[goblin.First + i]; quads[#quads + 1] = q end
local nameLeft, nameRight = quads[1].X0, quads[6].X1
local lineLeft, lineRight = quads[7].X0, quads[#quads].X1
H.print('its middle under the name\'s', math.abs((nameLeft + nameRight) / 2 - (lineLeft + lineRight) / 2) < 1.6, '| below it', quads[7].Y0 > quads[1].Y1, '| smaller', (quads[7].Y1 - quads[7].Y0) < (quads[1].Y1 - quads[1].Y0))
H.print('check text now 90 percent of name height', math.abs((quads[8].Y1 - quads[8].Y0) / (quads[1].Y1 - quads[1].Y0) - 0.90) < 0.001)
do
    o.checkSize[1] = 110; H.frames(1)
    local detailQuad, nameQuad = draw.Quads[goblin.First + 7], draw.Quads[goblin.First]
    H.print('check-size slider scales rendered text', math.abs((detailQuad.Y1 - detailQuad.Y0) / (nameQuad.Y1 - nameQuad.Y0) - 1.10) < 0.001)
    o.checkSize[1] = 90; H.frames(1)
end
local softIconEdges = true
for _, q in ipairs(quads) do
    if q.Texture >= 2 then softIconEdges = softIconEdges and q.Flags == 3 and q.Reserved == 191 and q.Color % 0x1000000 == 0xFFFFFF and math.floor(q.Color / 0x1000000) == math.floor(quads[7].Color / 0x1000000) end
end
H.print('detail icon edges softened; fill and text edges unchanged', softIconEdges, quads[8].Flags == 1, quads[8].Reserved == 0)
H.print('magnifier leads check line, not name', quads[7].Texture == 4, quads[7].Y0 > quads[1].Y1, quads[7].X0 < quads[8].X0)
local signs = {}
for _, q in ipairs(quads) do if q.Texture >= 2 then signs[#signs + 1] = ('%d:%.2f,%.2f'):format(q.Texture, q.U0, q.V0) end end
-- sight and sound (the second row's first and third) and link (the last row's last); none from the aggro sheet
H.print('the signs, by sheet and where they are in it:', table.concat(signs, ' '))
o.abbreviateDifficulty[1] = false; H.frames(1)
H.print('full difficulty remains available in icon mode', goblin.Count == 42)
o.abbreviateDifficulty[1] = true; H.frames(1)
-- In words, compact difficulty followed by aggro and link information.
o.checkDetailsInWords[1] = true; H.frames(1)
signs = {}
for i = 0, goblin.Count - 1 do local q = draw.Quads[goblin.First + i]; if q.Texture >= 2 then signs[#signs + 1] = ('%d:%.2f,%.2f'):format(q.Texture, q.U0, q.V0) end end
H.print('in words: quads', goblin.Count, '| signs', table.concat(signs, ' '))
do
    local abbreviatedCount = goblin.Count
    o.abbreviateDifficulty[1] = false; H.frames(1)
    H.print('words-mode sentence cache updates when abbreviations change', goblin.Count == abbreviatedCount + 8)
    o.abbreviateDifficulty[1] = true; H.frames(1)
    H.print('words-mode abbreviation restored', goblin.Count == abbreviatedCount)
end
levels.Set({ Indices = { [300] = { MinLevel = 8, MaxLevel = 10, Aggro = true, TrueSight = true, Sight = true, Sound = true, Blood = true, Link = true } }, Names = {} })
H.frames(1)
-- "Very Tough, True Sight/True Sound/Blood Aggro, Link" (51) for one of no family
H.print('one that sees and hears truly, and links with a family the tables do not name: quads', goblin.Count)
-- one that is not aggressive and does not link: "Very Tough" alone (10); aggressive with nothing said of how: "Very Tough, Aggro" (17)
levels.Set({ Indices = { [300] = { MinLevel = 8, MaxLevel = 10, Aggro = false, Sight = true } }, Names = {} }); H.frames(1)
local passive = goblin.Count
levels.Set({ Indices = { [300] = { MinLevel = 8, MaxLevel = 10, Aggro = true } }, Names = {} }); H.frames(1)
H.print('not aggressive: the words for how hard alone, quads', passive, '| aggressive and no more known: quads', goblin.Count)
H.print('difficulty-only words layout uses full Very Tough', passive == 16)
levels.Set({ Indices = { [300] = { MinLevel = 8, MaxLevel = 10, Aggro = true, Notorious = false, Sight = true, Sound = true, Link = true, Family = 'Goblin' } }, Names = {} })
o.checkDetailsInWords[1] = false; H.frames(1)
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
-- letters 23 high: the sign 29 square, three above the line's top and three below its foot, with the edge letters have
H.print('[aggro] is a thing:', parts('[aggro][name]'), '| quads', goblin.Count, ('| the sign first: texture %d, at %.2f,%.2f, %d square, from %d down'):format(first.Texture, first.U0, first.V0, first.X1 - first.X0, first.Y0), '| softer edge', first.Flags == 3 and first.Reserved == 191,
    '| the name after it', draw.Quads[goblin.First + 1].X0 >= first.X1)
-- Exercise the production path (fixed player profile supplied), not just the fixture wrapper.
frameForTests(o, block, suppliedFormats)
assert(goblin.Count == 7, 'editable mob format must override the fixed profile')
o.showAggroIcons[1] = false
frameForTests(o, block, suppliedFormats)
assert(goblin.Count == 6, 'aggro toggle must remove the inline icon')
o.monsterFormat[1] = '[aggro] Lv [level]. [name]'
o.showMobLevel[1] = false
frameForTests(o, block, suppliedFormats)
assert(goblin.Count == 6, 'level toggle must remove the level and standard Lv punctuation')
assert(o.monsterFormat[1] == '[aggro] Lv [level]. [name]', 'toggles must not rewrite saved formats')
o.showMobLevel[1], o.showAggroIcons[1] = true, true
o.monsterFormat[1] = '[aggro][name]'
H.frames(1)
assert(goblin.Count == 7, 're-enabling aggro must restore the icon')
H.print('production mob format is editable; level and aggro toggles preserve saved strings', true)
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
-- one that does not link, and is not aggressive: the words alone
levels.Set({ Indices = { [300] = { MinLevel = 8, MaxLevel = 10, Aggro = false, Sight = true, Link = false, Family = 'Goblin' } }, Names = {} })
H.packetData(0x029, message(0x1000 + 300, 9, 0x40, 300, 174)); H.frames(1)
signs = {}
for i = 0, goblin.Count - 1 do local q = draw.Quads[goblin.First + i]; if q.Texture >= 2 then signs[#signs + 1] = ('%d:%.2f,%.2f'):format(q.Texture, q.U0, q.V0) end end
H.print('a passive one, said to be', levels.Checked(300, 0x1000 + 300).hard, '| signs', table.concat(signs, ' '), '| quads', goblin.Count)
H.print('difficulty-only icon layout uses full Too Weak', goblin.Count == 15)
do
    local correct = true
    for _, difficulty in ipairs({ { 0x42, 'Easy Prey' }, { 0x45, 'Tough' }, { 0x46, 'Very Tough' } }) do
        for _, words in ipairs({ false, true }) do
            o.checkDetailsInWords[1] = words
            H.packetData(0x029, message(0x1000 + 300, 9, difficulty[1], 300, 174)); H.frames(1)
            correct = correct and goblin.Count == (words and 6 or 7) + #difficulty[2]
        end
    end
    H.print('EP, T and VT alone use full words in both layouts', correct)
    o.checkDetailsInWords[1] = false
end
-- one the tables do not have: the words alone; and one impossible to gauge
levels.Set(nil)
H.packetData(0x029, message(0x1000 + 300, 0, 0, 300, 249)); H.frames(1)
H.print('not in the tables, and impossible to gauge:', levels.Checked(300, 0x1000 + 300).hard, '| no level', levels.Of(300, 'Goblin', 0x1000 + 300) == nil, '| quads', goblin.Count)
H.print('impossible to gauge defaults to ???', levels.Checked(300, 0x1000 + 300).hardShort == '???', goblin.Count == 10)
-- five minutes after it was checked it is forgotten, alive or not
H.frames(9990); H.print('after 4m59s: still known', levels.IsChecked(300, 0x1000 + 300))
H.frames(20); H.print('after 5m: forgotten', levels.IsChecked(300, 0x1000 + 300) == false)
H.packetData(0x029, message(0x1000 + 300, 0, 0, 300, 249)); H.frames(1)
alive[300].hp = 0; H.frames(1)
H.print('dead: the name alone again, quads', goblin.Count)
alive[300].hp = 100
levels.Set({ Indices = { [300] = { MinLevel = 8, MaxLevel = 10 } }, Names = {} })
o.monsterFormat[1] = '[name] L[level]'; o.checkedFormat = T{ '[name] [level]!' }
H.packetData(0x029, message(0x1000 + 300, 9, 0x43, 300, 173)); o.showCheckDetails[1] = false; H.frames(1)
alive[300].hp = 0; H.frames(1)
H.print('dead: the range again, quads', draw.Entities[300].Count, '|', levels.Of(300, 'Goblin', 0x1000 + 300))
alive[300].hp = 100; o.showCheckDetails[1] = true
o.checkedFormat = T{ '' }
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
H.print('distance, brought over:', o.monsterFormat[1], '| the old settings gone', o.showDistance == nil, o.targetFormat == nil)
o.targetFormat = T{ '' }; H.frames(1)

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

-- A warmed frame must not decode text bytes again just to measure/draw names.
local originalByte, decoded = string.byte, 0
string.byte = function(...) decoded = decoded + 1; return originalByte(...) end
H.frames(1)
string.byte = originalByte
H.print('cached glyph runs: warm frame decodes no text bytes', decoded == 0)

local function upvalue(fn, wanted)
    for index = 1, 100 do
        local name, value = debug.getupvalue(fn, index)
        if name == nil then break end
        if name == wanted then return value end
    end
    error('missing test upvalue: ' .. wanted)
end
-- what is written under a checked monster's name is a function of its own, which the frame's calls
local linkLabel = upvalue(upvalue(frameForTests, 'writeDetails'), 'linkWords')
local sightLink = { Link = true, Sight = true, Family = 'Goblin', Aggro = false }
local hearingLink = { Link = true, Sound = true, TrueSight = true, Family = 'Funguar' }
local bothLink = { Link = true, Sight = true, Sound = true, Family = 'Goblin' }
H.print('link senses: sight, hearing and both', linkLabel(sightLink) == 'Link: Goblin (Sight)',
    linkLabel(hearingLink) == 'Link: Funguar (Hearing)', linkLabel(bothLink) == 'Link: Goblin (Sight/Hearing)')
H.print('link icon labels retain family and senses', linkLabel(bothLink, true) == 'Goblin (Sight/Hearing)',
    linkLabel({ Link = true, Sound = true }, true) == 'Hearing')
H.print('unknown link sense remains unspecified; nonlinking stays empty',
    linkLabel({ Link = true, TrueSight = true, Family = 'Goblin' }) == 'Link: Goblin',
    linkLabel({ Link = true }) == 'Link', linkLabel({ Link = false, Sight = true }) == '')
local measure = upvalue(frameForTests, 'wordsWidth')
local runSet = { glyphs = {}, baked = { FindGlyph = function() return glyph end } }
local firstWidth = measure(runSet, 'AAA', 1)
H.print('glyph-run cache scales without duplicating entries', measure(runSet, 'AAA', 0.5) == firstWidth * 0.5, runSet.runCount == 1)
H.print('empty text skips glyph-run allocation', measure(runSet, '', 1) == 0, runSet.runCount == 1)
runSet.syntheticBold = true
H.print('bold change invalidates cached advances', measure(runSet, 'AAA', 1) == firstWidth + 3, runSet.runCount == 1)
runSet.syntheticBold = false
H.print('regular advances restored after bold', measure(runSet, 'AAA', 1) == firstWidth)
local getRungs = upvalue(frameForTests, 'fontRungs')
local rungSizes = getRungs(23)
H.print('font rungs reused across names and frames', rungSizes == getRungs(23), rungSizes[1] == 23, rungSizes[2] == 17, rungSizes[3] == 12)
local resized = getRungs(24)
H.print('font rungs made again as the size changes', #resized == 3, resized[2] == 18, resized ~= rungSizes)
for index = 1, 600 do measure(runSet, tostring(index), 1) end
H.print('glyph-run cache remains bounded', runSet.runCount <= 512)
local replacementGlyph = {}
for key, value in pairs(glyph) do replacementGlyph[key] = value end
replacementGlyph.AdvanceX = glyph.AdvanceX * 2
local replacementSet = { glyphs = {}, baked = { FindGlyph = function() return replacementGlyph end } }
H.print('replacement font set never reuses stale glyph runs', measure(replacementSet, 'AAA', 1) == firstWidth * 2)
block.Count = 1
H.tab(1); H.command('/name'); local sliders = H.calls.SliderInt or 0; H.frames(1); H.command('/name'); H.tab(2)
H.print('its tab drawn: sliders', (H.calls.SliderInt or 0) - sliders)

H.print('ImGui signs retain their own texture', draw.Textures[4] == fontTexture)
local savedMonsterFormat = o.monsterFormat[1]
local savedSignName = ffi.new(ffi.typeof(block.Names[1]), block.Names[1])
local savedSignAlive, savedSignCount = alive[300], block.Count
block.Count = 2
alive[300] = { id = 0x1000 + 300, hp = 100 }
put(1, 300, Category.Monster, Flag.Wanted, 'Goblin')
block.Names[1].Scale, block.Names[1].NameColor = 1, 0x80808080
o.monsterFormat[1] = '[checked][name]'
H.packetData(0x029, message(0x1000 + 300, 9, 0x46, 300, 174)); H.frames(2)
local softMagnifier = false
for i = 0, goblin.Count - 1 do
    local q = draw.Quads[goblin.First + i]
    if q.Texture == 4 then softMagnifier = q.Flags == 3 and q.Reserved == 191 end
end
H.print('magnifier edge softened too', softMagnifier)
block.Count = savedSignCount
block.Names[1] = savedSignName
alive[300] = savedSignAlive
o.monsterFormat[1] = savedMonsterFormat

do
    local expected = { 'TW', 'IEP', 'EP', 'DC', 'EM', 'T', 'VT', 'IT' }
    local correct = true
    for index, abbreviation in ipairs(expected) do
        H.packetData(0x029, message(0x1000 + 300, 9, 0x3F + index, 300, 174))
        correct = correct and levels.Checked(300, 0x1000 + 300).hardShort == abbreviation
    end
    H.print('all eight difficulty abbreviations mapped correctly', correct)
end
block.Hooked = 0; block.Claimed = 0; H.frames(1)
H.print('a client not recognised: nothing claimed', block.Claimed == 0)
block.Hooked = 1
H.command('/name custom off'); block.Claimed = 0; H.frames(1)
H.print('legacy custom off no longer disables rendering', o.customNames == nil, block.Claimed ~= 0)

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

-- Do not reserve 256 slots for a short name: fill every remaining slot safely.
nameplates.BeginDrawing(block)
draw.QuadsMax = 3
nameplates.BeginName(5, 1, 0, 0)
nameplates.Quad(0, 0, 1, 1, 0, 0, 1, 1, 0xFFFFFFFF, 0, false)
nameplates.EndName()
local lastName = nameplates.BeginName(6, 1, 0, 0)
for _ = 1, 5 do nameplates.Quad(0, 0, 1, 1, 0, 0, 1, 1, 0xFFFFFFFF, 0, false) end
nameplates.EndName()
H.print('small final name uses remaining capacity without overflow', lastName, draw.Entities[6].Count == 2, draw.QuadCount == 3, not nameplates.BeginName(7, 1, 0, 0))
draw.QuadsMax = 16384

-- Experimental letters use the complete zone table, not the visible list.
-- Mock only GPU preparation; exercise actual token measurement / badge quad submission.
local badges = require('letter_badges')
local originalBadgePrepare = badges.Prepare
local badgeMasterHeight, pairsWanted;
badges.Prepare = function(_, definitions)
    pairsWanted = definitions[1].pairs
    assert(#definitions == 1, 'all distances must share one close-up badge master')
    if badgeMasterHeight then
        assert(definitions[1].height == badgeMasterHeight, 'distance must not change the badge master size')
    end
    badgeMasterHeight = definitions[1].height
    local regions = {}
    for _, definition in ipairs(definitions) do
        assert(definition.glyphs.B, 'badge glyphs must come from the indicator font in uppercase')
        assert(badges.Font == 'arialbd.ttf', 'indicators must always use Arial Bold')
        assert(definition.bold == false, 'native bold indicators must not add synthetic bold')
        regions[definition.height] = { B = { top = 0, uv = {
            w = definition.height, h = definition.height, u0 = 0, v0 = 0, u1 = 1, v1 = 1 } } }
        if (definition.pairs or 0) > 0 then
            regions[definition.height].AA = { top = 0, uv = {
                w = definition.height * 1.5, h = definition.height, u0 = 0, v0 = 0, u1 = 1, v1 = 1 } }
        end
    end
    return { address = 0x5555, regions = regions }
end
local preparedBadges = badges.Prepare
custom.Defaults(o)
o.showCheckDetails[1], o.showIcons[1], o.showStars[1] = false, false, false
o.outline[1] = 0
levels.Set({ Indices = { [299] = { Name = 'Goblin' }, [300] = { Name = 'Goblin' } }, Names = {} })
put(0, 300, Category.Monster, Flag.Wanted + Flag.Target, 'Goblin')
block.Count = 1
o.monsterFormat[1] = '[name][letter:yellow]'
o.showMobLetter[1] = true
frameForTests(o, block, suppliedFormats)
local labelled = draw.Entities[300]
assert(levels.Letter(300, 'Goblin', block.Names[0].ServerId) == 'b')
assert(labelled.Count == 7, 'explicit letter token must draw one letter without automatic duplication')
local badgeQuad = draw.Quads[labelled.First + 6]
assert(badgeQuad.Color == 0xFFFFE040, 'letter token colour must tint the box')
assert(badgeQuad.Texture == 5 and draw.Textures[5] == 0x5555, 'letter must use the font-derived badge atlas')
assert(badgeQuad.Flags == 1, 'badge must opt into the nameplate outline effect')
assert(badgeQuad.X1 - badgeQuad.X0 == badgeQuad.Y1 - badgeQuad.Y0, 'badge must be square')
assert(math.abs(badgeQuad.Y1 - draw.Quads[labelled.First].Y1) < 0.001,
    'box bottom must align with the name font lowercase baseline')
assert(math.abs(badgeQuad.X1 + draw.Quads[labelled.First].X0) <= 1,
    'measured badge width must keep the complete nameplate centred')
local closeBadgeHeight = badgeQuad.Y1 - badgeQuad.Y0
local closeU, closeV = badgeQuad.U0, badgeQuad.V0
block.Names[0].Scale = 0.2
block.Names[0].ServerId = block.Names[0].ServerId + 1 -- reset distance stabilization for this fixture
frameForTests(o, block, suppliedFormats)
local farBadge = draw.Quads[labelled.First + 6]
assert(farBadge.Y1 - farBadge.Y0 < closeBadgeHeight, 'same close-up artwork must scale down at distance')
assert(math.abs(farBadge.Y1 - draw.Quads[labelled.First].Y1) < 0.001,
    'box bottom must stay aligned when distance changes the font rung')
assert(farBadge.U0 == closeU and farBadge.V0 == closeV,
    'distance must retain the master badge UVs')
block.Names[0].Scale = 1
block.Names[0].ServerId = block.Names[0].ServerId + 1
badges.Prepare = function() return nil end
frameForTests(o, block, suppliedFormats)
assert(labelled.Count == 7 and draw.Quads[labelled.First + 6].Texture == 4,
    'failed badge preparation must fall back to the fixed indicator font on the ImGui texture')
badges.Prepare = originalBadgePrepare
o.showMobLetter[1] = false
frameForTests(o, block, suppliedFormats)
assert(labelled.Count == 6, 'toggle off must suppress explicit letter tokens')
o.showMobLetter[1], o.monsterFormat[1] = true, '[name]'
frameForTests(o, block, suppliedFormats)
assert(labelled.Count == 8, 'toggle on must append a spaced letter without editing Mob Format')
levels.Set({ Indices = { [300] = { Name = 'Goblin' } }, Names = {} })
assert(levels.Letter(300, 'Goblin', block.Names[0].ServerId) == 'a', 'new zone/table must reset letter ranks')
-- Double Letters: the twenty-seventh of a name is AA in one wider badge, and A again with it off
local crowd = {}
badges.Prepare = preparedBadges
for index = 274, 300 do crowd[index] = { Name = 'Goblin' } end
levels.Set({ Indices = crowd, Names = {} })
o.monsterFormat[1] = '[name][letter]'
frameForTests(o, block, suppliedFormats)
assert(levels.Letter(300, 'Goblin', block.Names[0].ServerId) == 'a' and pairsWanted == 0, 'off: a again, and no double badges made')
o.doubleMobLetters[1] = true
frameForTests(o, block, suppliedFormats)
assert(levels.Letter(300, 'Goblin', block.Names[0].ServerId) == 'aa' and pairsWanted == 1, 'on: as many double badges as the area needs')
local doubleQuad = draw.Quads[labelled.First + 6]
assert(labelled.Count == 7 and doubleQuad.Texture == 5, 'a double letter is one badge')
assert(math.abs((doubleQuad.X1 - doubleQuad.X0) - 1.5 * (doubleQuad.Y1 - doubleQuad.Y0)) < 0.001, 'half as wide again as it is tall')
assert(math.abs(doubleQuad.X1 + draw.Quads[labelled.First].X0) <= 1, 'and the nameplate still centred')
o.doubleMobLetters[1] = false
frameForTests(o, block, suppliedFormats)
assert(levels.Letter(300, 'Goblin', block.Names[0].ServerId) == 'a' and pairsWanted == 0, 'off again: as it was')
badges.Prepare = originalBadgePrepare
levels.Set(nil)
frameForTests(o, block, suppliedFormats)
assert(labelled.Count == 6, 'missing zone catalogue must not invent an encounter-based letter')
o.showMobLetter[1] = false
H.print('experimental mob letters: square cutout badge, centring, tint, fallback, suffix, toggle, double letters and zone-table reset', true)

-- Exercise the actual shared file loader: bounded startup retries, then success caching.
pcall(ffi.cdef, 'typedef struct IDirect3DTexture8 IDirect3DTexture8;')
local originalC, originalClock = ffi.C, os.clock
local now, attempts, ready = 1000, 0, false
os.clock = function() return now end
ffi.C = setmetatable({
    S_OK = 0,
    D3DXCreateTextureFromFileA = function(_, path, made)
        assert(path == addon.path .. 'assets/player-icons.png')
        attempts = attempts + 1
        if not ready then return -1 end
        made[0] = ffi.cast('IDirect3DTexture8*', 0x4321)
        return 0
    end,
}, { __index = originalC })
block.Hooked, block.Count = 1, 0
custom.Frame(o, block)
custom.Frame(o, block)
assert(attempts == 1 and draw.Textures[1] == 0, 'failed sheet loads must be throttled')
ready, now = true, now + 1
custom.Frame(o, block)
assert(attempts == 2 and draw.Textures[1] == 0x4321, 'player sheet must recover after startup failure')
now = now + 2
custom.Frame(o, block)
assert(attempts == 2, 'successful sheet must remain cached')
ffi.C, os.clock = originalC, originalClock
H.print('bundled player sheet: shared file loading, bounded retries and success caching', true)

block.Hooked = 0
H.print('a client not recognised:', nameplates.Problem())
block.Hooked = 1
block.Version = 1
loaded = false; H.frames(1); loaded = true
H.print('a plugin of another version: no hook', nameplates.Hook() == nil, '|', nameplates.Problem())
loaded = false
H.print('unloaded: no hook', nameplates.Hook() == nil, '| count', nameplates.Count(), '| nothing found', nameplates.Find(300) == nil)
H.unload()
