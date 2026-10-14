-- name: the row of status icons over a name, for the statuses chosen to be seen. The player's own
-- and the party's are read from the game, an enemy's worked out from the spells seen to land on it.
local ffi = require('ffi')
local imgui = require('imgui')
local nameplates = require('winxi.nameplates')
local statusicons = require('winxi.statusicons')
local debuffs = require('winxi.debuffs')
local Category, Flag = nameplates.Category, nameplates.Flag
local o = H.options()
require('custom').Defaults(o)
for _, key in ipairs({ 'showSelf', 'showParty', 'showAlliance', 'showPlayers', 'showMyPet', 'showPets', 'showNpcs', 'showMonsters' }) do o[key][1] = true end
o.showStars[1], o.showIcons[1], o.fontSize[1], o.monsterFormat[1] = true, false, 16, '[name]'

H.print('settings: shown, at 125%', o.showStatuses[1], o.statusSize[1], '| what ails a character chosen to begin with', #o.statusList, o.statusList[1], o.statusList[#o.statusList])

-- the game: the player under paralysis, Protect, paralysis again and slow; one other of the party
-- under slow and status 300, whose number takes two of the bits kept apart
local own = { 4, 40, 4, 13, 255, 0 }
local manager = AshitaCore.GetMemoryManager()
manager.GetPlayer = function() return { GetIsZoning = function() return 0 end, GetStatusIcons = function() return own end,
    GetMainJob = function() return 18 end, GetLoginStatus = function() return 2 end } end
AshitaCore.GetMemoryManager = function() return manager end
AshitaCore.GetResourceManager = function() return { GetString = function(_, _, id) return id == 77 and '' or ('status ' .. id) end } end
local BASE = 0x5000
local memory = { [0x4000] = BASE, [BASE + 0x30] = 0x1401, [BASE + 0x30 + 8] = 0x04, [BASE + 0x30 + 16] = 13, [BASE + 0x30 + 17] = 300 - 256 }
for slot = 2, 31 do memory[BASE + 0x30 + 16 + slot] = 255 end
AshitaCore.GetPointerManager = function() return { Get = function(_, name) return name == 'party.statusicons' and 0x4000 or 0 end } end
ashita.memory.read_uint32 = function(at) return memory[at] or 0 end
ashita.memory.read_uint8 = function(at) return memory[at] or 0 end
local now = 1000
os.time = function() return now end

-- the plugin, and its place for what is drawn
local block = ffi.new('namehook_t')
ffi.copy(block.Magic, 'NAMEHOOK')
block.Version, block.Size, block.NameSize, block.Hooked = 2, ffi.sizeof('namehook_t'), ffi.sizeof('namehook_name_t'), 1
block.Width, block.Height, block.TargetWidth, block.TargetHeight = 960, 540, 960, 540
local plugins = AshitaCore.GetPluginManager()
plugins.IsLoaded = function(_, name) return name == 'namehook' end
AshitaCore.GetPluginManager = function() return plugins end
ashita.memory.find = function(module) return module == 'namehook.dll' and tonumber(ffi.cast('uintptr_t', ffi.cast('void*', block))) or 0 end
ffi.cdef('void* mmap(void*, size_t, int, int, int, long);')
local low = ffi.C.mmap(nil, ffi.sizeof('namehook_draw_t'), 3, 0x62, -1, 0)
local draw = ffi.cast('namehook_draw_t*', low)
draw.QuadsMax = 16384
block.Draw = tonumber(ffi.cast('uintptr_t', low))
imgui.GetIO = function() return { DisplaySize = { x = 960, y = 540 } } end
local glyph = { X0 = 1, Y0 = 2, X1 = 9, Y1 = 14, U0 = 0.25, V0 = 0.5, U1 = 0.3, V1 = 0.6, AdvanceX = 10, Visible = 1 }
imgui.GetFontBaked = function() return { FindGlyph = function() return glyph end, FindGlyphNoFallback = function() return nil end } end
imgui.GetFont = function() return { ContainerAtlas = { TexRef = { GetTexID = function() return 0x1234 end }, TexData = { GetTexID = function() return 0 end } } } end

local function put(i, index, category, flags, name)
    local n = block.Names[i]
    n.EntityIndex, n.ServerId, n.Category, n.Flags = index, 0x1000 + index, category, flags
    n.Scale, n.NameColor = 1, 0x80808080
    ffi.copy(n.Name, name); ffi.copy(n.Text, name)
end
put(0, 0x400, Category.Self, Flag.Wanted, 'Tester')
put(1, 0x401, Category.Party, Flag.Wanted, 'Buddy')
put(2, 300, Category.Monster, Flag.Wanted, 'Goblin')
put(3, 0x402, Category.Player, Flag.Wanted, 'Other')
block.Count, block.Sequence = 4, 1

-- the icons of one name: the quads drawn from the sheet, as "left..right" places across
local function icons(index)
    local entity, found = draw.Entities[index], {}
    if entity.Frame == draw.Frame then
        for i = 0, entity.Count - 1 do
            local q = draw.Quads[entity.First + i]
            if q.Texture == 7 then found[#found + 1] = q end
        end
    end
    return found
end
-- which status a quad is: its place in the sheet, 42 to a row of 48 by 64 in 2048 by 1024
local function status(q) return math.floor(q.V0 * 1024 / 64) * 42 + math.floor(q.U0 * 2048 / 48) end
local function listed(index)
    local ids = {}
    for _, q in ipairs(icons(index)) do ids[#ids + 1] = status(q) end
    return table.concat(ids, ' ')
end

-- no sheet: nothing is drawn of them, and the names are as ever
H.load(); block.Frame = 1; H.frames(1)
H.print('no sheet: no row', listed(0x400) == '', '| the name still set out', draw.Entities[0x400].Count, '| nothing given to the plugin', draw.Textures[7] == 0)

statusicons.Sheet = function() return 0x7777 end
block.Frame = 2; H.frames(1)
H.print('the sheet is the plugin\'s eighth picture', draw.Textures[7] == 0x7777)
H.print('own: what is chosen, each once, in the game\'s order:', listed(0x400), '| Protect is not chosen')
H.print('a party member\'s, as the game keeps them:', listed(0x401), '| 300 is not chosen')
H.print('an enemy nothing was seen to land on: none', listed(300) == '', '| a stranger: none', listed(0x402) == '')

-- where the row is: over the name, its middle on the name's, three quarters as wide as it is tall
local row = icons(0x400)
local first, second = row[1], row[2]
H.print('icon: wide', first.X1 - first.X0, 'tall', first.Y1 - first.Y0, '| foot above the letters', first.Y1, '| not edged', first.Flags == 0, ('| colour %08X'):format(first.Color))
H.print('the row is centred', math.abs(first.X0 + second.X1) <= 1, '| a pixel between them', second.X0 - first.X1)
H.print('from the icon\'s own part of the sheet', ('%.5f %.5f %.5f %.5f'):format(first.U0, first.V0, first.U1, first.V1))
local playerIcons = require('icons')
local realPlace = playerIcons.Place
playerIcons.Place = function(byte) return byte == 0xAD and { 0, 0, 0.1, 0.1 } or false end
block.Names[0].Flags = Flag.Wanted + Flag.Stars; block.Frame = 3; H.frames(1)
local starred = icons(0x400)[1]
H.print('with the mastery stars: above them', starred.Y1 < first.Y1)
block.Names[0].Flags = Flag.Wanted; playerIcons.Place = realPlace
o.statusSize[1] = 200; block.Frame = 4; H.frames(1)
H.print('at 200%: tall', icons(0x400)[1].Y1 - icons(0x400)[1].Y0)
o.statusSize[1] = 125

-- an enemy: Dia and Slow are seen to land on it, Slow is resisted on another
local function cast(spell, results)
    local targets = {}
    for id, message in pairs(results) do targets[#targets + 1] = { id = id, actions = { { message = message } } } end
    debuffs.Action({ actor_id = 1, category = 4, param = spell, targets = targets })
end
cast(56, { [0x1000 + 300] = 236, [0x1000 + 0x402] = 85 }); cast(23, { [0x1000 + 300] = 2 })
block.Frame = 5; H.frames(1)
H.print('an enemy under Slow and Dia, the lowest number first:', listed(300), '| resisted on the other', listed(0x402) == '')
now = now + 90; block.Frame = 6; H.frames(1)
H.print('Dia has run out:', listed(300))
debuffs.Message({ target = 0x1000 + 300, message = 206, param = 13 }); block.Frame = 7; H.frames(1)
H.print('Slow wears off: none', listed(300) == '')

-- the list is the player's: one added, one taken out, none
local list = o.statusList
list[#list + 1] = 40; block.Frame = 8; H.frames(1)
H.print('Protect chosen:', listed(0x400))
list[#list] = nil
o.statusList = T{ 300 }; block.Frame = 9; H.frames(1)
H.print('another list: own', listed(0x400) == '', '| the party member', listed(0x401))
o.statusList = T{}; block.Frame = 10; H.frames(1)
H.print('nothing chosen: no rows', listed(0x401) == '', draw.Textures[7] == 0)
o.statusList = list
o.showStatuses[1] = false; block.Frame = 11; H.frames(1)
H.print('switched off: no rows', listed(0x400) == '', draw.Textures[7] == 0)
o.showStatuses[1] = true

-- more than a row holds
own = {}; for id = 1, 32 do own[id] = id + 1 end
o.statusList = T{}; for id = 2, 33 do o.statusList[#o.statusList + 1] = id end
block.Frame = 12; H.frames(1)
H.print('thirty-two chosen and on: twelve drawn', #icons(0x400))
o.statusList = list; own = { 4, 13 }

-- the settings' tab, the fourth: a list of every status that has an icon and a name
local boxes, saves = {}, H.saves()
local realCheckbox = imgui.Checkbox
imgui.Checkbox = function(id, value) boxes[#boxes + 1] = id return false end
imgui.GetFrameHeightWithSpacing = function() return 20 end
H.tab(4); H.command('/name'); H.frames(1)
local named = 0
for _, id in ipairs(boxes) do if id:find('##name.status.', 1, true) then named = named + 1 end end
H.print('settings: Show Statuses first', boxes[1] == '##name.showStatuses', '| statuses listed', named, '| by name, with the number', boxes[3])
imgui.Checkbox = function(id, value)
    if id:find('##name.status.41', 1, true) and id:match('%.41$') then value[1] = not value[1] return true end
    return false
end
H.frames(1)
imgui.Checkbox = function() return false end
local has, ordered = false, true
for i = 2, #o.statusList do ordered = ordered and o.statusList[i - 1] < o.statusList[i] end
for _, id in ipairs(o.statusList) do has = has or id == 41 end
H.print('Shell ticked: in the list', has, '| kept in order', ordered, '| saved', H.saves() > saves)
block.Frame = 13; H.frames(1)
H.print('not over the name yet', listed(0x400) == '4 13')
own = { 41 }; block.Frame = 14; H.frames(1)
H.print('once the player is under it:', listed(0x400))
imgui.Checkbox = realCheckbox
H.command('/name')
