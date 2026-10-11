-- nametoggle and winxi.nameplates: the addon's settings and the plugin's are kept the same, and the
-- plugin's names are read. The plugin here is a block of the same shape, made in this file.
local ffi = require('ffi')
local imgui = require('imgui')
local nameplates = require('winxi.nameplates')
local Category, Flag = nameplates.Category, nameplates.Flag
local o = H.options()

local loaded = false
local block = ffi.new('nameplatehook_t')
ffi.copy(block.Magic, 'NAMEPLATEHOOK')
block.Version, block.Size, block.NameSize, block.Hooked = 2, ffi.sizeof('nameplatehook_t'), ffi.sizeof('nameplatehook_name_t'), 1
block.Width, block.Height = 960, 540

local manager = AshitaCore.GetPluginManager()
manager.IsLoaded = function(_, name) return loaded and name == 'nameplatehook' end
AshitaCore.GetPluginManager = function() return manager end
ashita.memory.find = function(module) return module == 'nameplatehook.dll' and tonumber(ffi.cast('uintptr_t', ffi.cast('void*', block))) or 0 end

H.print('the block is laid out as the plugin has it', ffi.sizeof('nameplatehook_name_t') == 128, ffi.offsetof('nameplatehook_t', 'Sequence') == 64,
    ffi.offsetof('nameplatehook_t', 'Draw') == 68, ffi.offsetof('nameplatehook_t', 'Override') == 80, ffi.offsetof('nameplatehook_t', 'Names') == 80 + 0x900)
H.print('and so is what is drawn for it', ffi.sizeof('nameplatehook_quad_t') == 48, ffi.sizeof('nameplatehook_drawing_t') == 24,
    ffi.offsetof('nameplatehook_draw_t', 'Entities') == 48, ffi.offsetof('nameplatehook_draw_t', 'Quads') == 48 + 24 * 0x900)

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
H.print('/nametoggle show kept from the game', H.command('/nametoggle show players npcs'))
H.print('shown again', o.showPlayers[1] and o.showNpcs[1], '| hidden', block.Hidden)
H.command('/nametoggle hide mobs self')
H.print('hide mobs self', block.Hidden == Category.Monster + Category.Self, o.showMonsters[1] == false)
H.command('/nametoggle toggle all')
H.print('toggle all', block.Hidden == Category.All - Category.Monster - Category.Self)
H.command('/nametoggle hide goblins')
H.print('a word that is no category changes nothing', block.Hidden == Category.All - Category.Monster - Category.Self, '| said:', H.printed[#H.printed])
H.command('/nametoggle show all')
H.print('/names is left alone', H.command('/names') == false)

-- a checkbox in the settings window: the fourth, Other Players
local before = H.calls.Begin or 0
H.command('/nametoggle'); H.frames(1)
H.print('settings window drawn', (H.calls.Begin or 0) > before, '| checkboxes', H.calls.Checkbox)
local realCheckbox = imgui.Checkbox
imgui.Checkbox = function(id, value) if id == '##nametoggle.showPlayers' then value[1] = not value[1] return true end return false end
H.frames(1)
imgui.Checkbox = realCheckbox
H.print('unticked: players hidden in the plugin', block.Hidden == Category.Player, o.showPlayers[1] == false)
H.command('/nametoggle')

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
local low = ffi.C.mmap(nil, ffi.sizeof('nameplatehook_draw_t'), 3, 0x62, -1, 0) -- read and write; private, anonymous, 32-bit
local draw = ffi.cast('nameplatehook_draw_t*', low)
draw.QuadsMax = 16384
block.Draw = tonumber(ffi.cast('uintptr_t', low))
block.TargetWidth, block.TargetHeight = 1440, 810 -- the game's picture, half as large again as its window
local glyph = { X0 = 1, Y0 = 2, X1 = 9, Y1 = 14, U0 = 0.25, V0 = 0.5, U1 = 0.3, V1 = 0.6, AdvanceX = 10, Visible = 1 }
local pushed = {}
imgui.PushFont = function(_, size) pushed[#pushed + 1] = size end
imgui.GetFontBaked = function() return { FindGlyph = function() return glyph end } end
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
H.print('/nametoggle custom kept from the game', H.command('/nametoggle custom'), '| on', o.customNames[1], '| said:', H.printed[#H.printed])
block.Frame = 78
H.frames(1)
local buddy = draw.Entities[0x401]
H.print('custom on: all claimed', block.Claimed == Category.All, '| set out in frame', draw.Frame, '| font texture', draw.Textures[0] == 0x1234)
-- five letters; the hidden name is not set out
H.print('the wanted name: quads', buddy.Count, '| of this frame', buddy.Frame == draw.Frame, '| the hidden one: none', draw.Entities[0x402].Frame ~= draw.Frame, '| in all', draw.QuadCount)
-- 15 pixels on the screen is 23 of the game's picture; the edge 1 pixel of the screen
H.print('letters at', pushed[#pushed], 'pixels | edge', buddy.Edge, '| solid', buddy.Alpha, ('| edge colour %08X'):format(buddy.EdgeColor))
local first = draw.Quads[buddy.First]
-- 50 wide, so it starts 25 left of the middle; the letter's own corner is 1, 2 from there, and the line 12 above
H.print('first letter: corner', first.X0, first.Y0, first.X1, first.Y1, ('| colour %08X'):format(first.Color), '| edged', first.Flags == 1, '| texture', first.Texture)
local last = draw.Quads[buddy.First + 4]
H.print('last letter: 40 further on', last.X0 - first.X0, '| where in the texture', first.U0, first.V1)
-- a name half way to the distance it is no longer drawn at is smaller, and one nearly there fainter
block.Names[0].Scale = 0.5; H.frames(1)
H.print('half way: letters at', pushed[#pushed], '| solid', buddy.Alpha)
block.Names[0].Scale = 0.075; H.frames(1)
H.print('nearly gone: letters at', pushed[#pushed], '| half solid', buddy.Alpha)
block.Names[0].Scale = 1
o.outline[1] = 0; H.frames(1)
H.print('no outline: no edge', buddy.Edge)
-- while the font has no texture nothing is set out, and what was is left to go stale
fontTexture = 0; local frameBefore = draw.Frame; block.Frame = 90; block.ClaimFrame = 0; H.frames(1)
H.print('no font texture: nothing set out', draw.Frame == frameBefore, '| nor claimed', block.ClaimFrame == 0)
fontTexture = 0x5678; H.frames(1)
H.print('another texture: taken up', draw.Textures[0] == 0x5678, draw.Frame == 90)
H.tab(2); H.command('/nametoggle'); local sliders = H.calls.SliderInt or 0; H.frames(1); H.command('/nametoggle'); H.tab(1)
H.print('its tab drawn: sliders', (H.calls.SliderInt or 0) - sliders)
block.Hooked = 0; block.Claimed = 0; H.frames(1)
H.print('a client not recognised: nothing claimed', block.Claimed == 0)
block.Hooked = 1
H.command('/nametoggle custom off'); block.Claimed = 0; H.frames(1)
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
