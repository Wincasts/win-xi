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
block.Version, block.Size, block.NameSize, block.Hooked = 1, ffi.sizeof('nameplatehook_t'), ffi.sizeof('nameplatehook_name_t'), 1
block.Width, block.Height = 960, 540

local manager = AshitaCore.GetPluginManager()
manager.IsLoaded = function(_, name) return loaded and name == 'nameplatehook' end
AshitaCore.GetPluginManager = function() return manager end
ashita.memory.find = function(module) return module == 'nameplatehook.dll' and tonumber(ffi.cast('uintptr_t', ffi.cast('void*', block))) or 0 end

H.print('the block is laid out as the plugin has it', ffi.sizeof('nameplatehook_name_t') == 128, ffi.offsetof('nameplatehook_t', 'Sequence') == 64,
    ffi.offsetof('nameplatehook_t', 'Override') == 80, ffi.offsetof('nameplatehook_t', 'Names') == 80 + 0x900)

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

block.Hooked = 0
H.print('a client not recognised:', nameplates.Problem())
block.Hooked = 1
block.Version = 2
loaded = false; H.frames(1); loaded = true
H.print('a plugin of another version: no hook', nameplates.Hook() == nil, '|', nameplates.Problem())
loaded = false
H.print('unloaded: no hook', nameplates.Hook() == nil, '| count', nameplates.Count(), '| nothing found', nameplates.Find(300) == nil)
H.unload()
