-- name: the row of status icons over a name, for the statuses chosen to be seen. The player's own
-- and the party's are read from the game, an enemy's worked out from the spells seen to land on it.
local ffi = require('ffi')
local imgui = require('imgui')
local nameplates = require('winxi.nameplates')
local statusicons = require('winxi.statusicons')
local debuffs = require('winxi.debuffs')
local Category, Flag = nameplates.Category, nameplates.Flag
local o = H.options()
imgui.GetFrameHeightWithSpacing = function() return 20 end
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

-- the set's icon where it has one, and the game's where it has not, from the one sheet; until the
-- set lacks one, every icon is the set's
local setLacks = {}
local realPlace = statusicons.SheetPlace
statusicons.MixedSheet = function() return 0x7777 end
statusicons.MixedPlace = function(id)
    if setLacks[id] then return { 0.9, 0.9, 0.95, 0.95 }, false end
    local place = realPlace(id)
    return place, place ~= nil
end
local look = require('winxi.theme').Get()
H.print('icons as party and buff draw them: Custom Icons on in winxisettings', look.StatusIcons == true)
-- the row's place is looked at centred first, and at each of the others further down
local startAlign = o.statusAlign[1]
o.statusAlign[1] = 'center'
block.Frame = 2; H.frames(1)
H.print('the sheet is the plugin\'s eighth picture', draw.Textures[7] == 0x7777)
H.print('own: what is chosen, each once, in the game\'s order:', listed(0x400), '| Protect is not chosen')
H.print('a party member\'s, as the game keeps them:', listed(0x401), '| 300 is not chosen')
H.print('an enemy nothing was seen to land on: none', listed(300) == '', '| a stranger: none', listed(0x402) == '')

-- where the row is: over the name, its middle on the name's, three quarters as wide as it is tall
local row = icons(0x400)
local first, second = row[1], row[2]
local firstLeft, firstFoot = first.X0, first.Y1 -- kept: the quads are drawn over each frame
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

-- where the row goes: above the name or below it, level with its left, its middle or its right
local function letters(index)
    local entity, left, right, foot = draw.Entities[index], math.huge, -math.huge, -math.huge
    for i = 0, entity.Count - 1 do
        local q = draw.Quads[entity.First + i]
        if q.Texture ~= 7 then left, right, foot = math.min(left, q.X0), math.max(right, q.X1), math.max(foot, q.Y1) end
    end
    return left, right, foot
end
H.print('settings: above and level with the left to begin with', o.statusPlace[1], startAlign)
local placed = {}
for _, place in ipairs({ 'above', 'below' }) do
    for _, align in ipairs({ 'left', 'center', 'right' }) do
        o.statusPlace[1], o.statusAlign[1] = place, align; block.Frame = block.Frame + 1; H.frames(1)
        local got = icons(0x400)
        local left, right, foot = letters(0x400)
        placed[place .. align] = { got[1].X0, got[#got].X1, got[1].Y0, got[1].Y1, left, right, foot }
    end
end
local function at(key) return placed[key] end
H.print('above: the foot over the letters', at('aboveleft')[4] < 0, at('abovecenter')[4] < 0, at('aboveright')[4] < 0)
H.print('below: the top under the letters', at('belowleft')[3] > at('belowleft')[7], at('belowcenter')[3] > at('belowcenter')[7], at('belowright')[3] > at('belowright')[7])
H.print('left: level with the name\'s left', math.abs(at('aboveleft')[1] - at('aboveleft')[5]) <= 1, math.abs(at('belowleft')[1] - at('belowleft')[5]) <= 1)
H.print('right: level with its right', math.abs(at('aboveright')[2] - at('aboveright')[6]) <= 1, math.abs(at('belowright')[2] - at('belowright')[6]) <= 1)
H.print('center: its middle on the name\'s', math.abs(at('abovecenter')[1] + at('abovecenter')[2] - at('abovecenter')[5] - at('abovecenter')[6]) <= 2,
    '| as it was', at('abovecenter')[1] == firstLeft and at('abovecenter')[4] == firstFoot)
o.statusPlace[1], o.statusAlign[1] = 'above', 'center'

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

-- preview: the first four chosen over every name, whatever it is under
local previewBox
local realBox = imgui.Checkbox
imgui.Checkbox = function(id, value) if id == '##name.statusPreview' then previewBox = value end return false end
H.tab(3); H.command('/name'); H.frames(1); H.command('/name')
imgui.Checkbox = realBox
previewBox[1] = true; block.Frame = 30; H.frames(1)
H.print('preview: the same four over every name', listed(0x400), '|', listed(300) == listed(0x400), listed(0x402) == listed(0x400))
previewBox[1] = false; block.Frame = 31; H.frames(1)
H.print('preview off: as they really are', listed(0x400), '| a stranger', listed(0x402) == '')

-- the game's own icons, for whoever prefers them: square, from the sheet made of them
local gameSheet = nil
statusicons.GameSheet = function() return gameSheet end
statusicons.GameSheetPlace = function(id) return gameSheet and id ~= 13 and { id / 1024, 0, (id + 1) / 1024, 1 / 32 } or nil end
look.StatusIcons = false; block.Frame = 40; H.frames(1)
H.print('game icons, their sheet not made yet: none', #icons(0x400) == 0, draw.Textures[7] == 0)
gameSheet = 0x6666; block.Frame = 41; H.frames(1)
local square = icons(0x400)
H.print('game icons: from their sheet', draw.Textures[7] == 0x6666, '| square', square[1].X1 - square[1].X0 == square[1].Y1 - square[1].Y0,
    '| one the game has no icon for is left out', #square == 1)
look.StatusIcons = true; block.Frame = 42; H.frames(1)
H.print('custom icons again', draw.Textures[7] == 0x7777, #icons(0x400) == 2)
setLacks[13] = true; block.Frame = 43; H.frames(1)
local mixedRow = icons(0x400)
H.print('a status the set has no icon for: the game\'s, square', #mixedRow == 2, math.abs(mixedRow[2].U0 - 0.9) < 1e-4 and mixedRow[2].X1 - mixedRow[2].X0 == mixedRow[2].Y1 - mixedRow[2].Y0,
    '| beside the set\'s, narrower', mixedRow[1].X1 - mixedRow[1].X0 < mixedRow[1].Y1 - mixedRow[1].Y0, '| a pixel between them', mixedRow[2].X0 - mixedRow[1].X1)
setLacks[13] = nil

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
H.tab(3); H.command('/name'); H.frames(1)
local named = 0
local firstStatus = nil
for _, id in ipairs(boxes) do if id:find('##name.status.', 1, true) then named = named + 1; firstStatus = firstStatus or id end end
H.print('settings: Show Statuses first', boxes[1] == '##name.showStatuses', '| statuses listed', named, '| by name, with the number', firstStatus)
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

-- below a checked monster: under the line its check is written on, while that is shown
do
    local levels = require('levels')
    local function u32(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
    local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
    local unpack = struct.unpack
    struct.unpack = function(kind, raw, at)
        local value = 0
        for i = (kind == 'I' and 3 or 1), 0, -1 do value = value * 256 + (raw:byte(at + i) or 0) end
        return value
    end
    manager.GetEntity = function() return {
        GetDistance = function() return 4 end,
        GetServerId = function(_, index) return index == 300 and 0x1000 + 300 or 0 end,
        GetHPPercent = function(_, index) return index == 300 and 100 or 0 end } end
    o.showCheckDetails[1] = true
    levels.Set({ Indices = { [300] = { MinLevel = 8, MaxLevel = 10, Aggro = true, Sight = true, Link = false, Family = 'Goblin' } }, Names = {} })
    cast(56, { [0x1000 + 300] = 236 })
    o.statusPlace[1] = 'below'; block.Frame = 60; H.frames(1)
    local _, _, plainFoot = letters(300)
    local plainTop = icons(300)[1].Y0
    H.packetData(0x029, u32(0) .. u32(1) .. u32(0x1000 + 300) .. u32(9) .. u32(0x46) .. u16(0x400) .. u16(300) .. u16(174) .. u16(0)); block.Frame = 61; H.frames(2)
    local _, _, checkedFoot = letters(300)
    local row = icons(300)
    H.print('below a checked monster: its line is lower than the name', checkedFoot > plainFoot, '| the row under the line', #row > 0 and row[1].Y0 > checkedFoot, '| lower than without it', #row > 0 and row[1].Y0 > plainTop)
    o.statusPlace[1], struct.unpack = 'above', unpack
end

-- the time left, written under each icon: off to begin with, then on
do
    -- the letters under a name's icons: of the font, their top at or below the icons' foot, by place across
    local function times(index)
        local row, entity, found = icons(index), draw.Entities[index], {}
        if #row == 0 then return '' end
        local foot, top = row[1].Y1, row[1].Y0
        for i = 0, entity.Count - 1 do
            local q = draw.Quads[entity.First + i]
            if q.Texture == 0 and q.Y0 >= foot and q.Y1 < (o.statusPlace[1] == 'above' and 0 or math.huge) then
                found[#found + 1] = q
            end
        end
        return #found, found
    end
    local GLYPHS = 1 -- the stand-in's letters are all the one glyph, a quad each
    local resources = AshitaCore.GetResourceManager()
    AshitaCore.GetResourceManager = function() return {
        GetString = resources.GetString,
        GetStatusIconByIndex = function(_, id) return { HideTimer = id == 13 and 1 or 0 } end } end
    -- the game's count of time: the player's Paralysis has 90 s left, Slow none it would say
    local EPOCH, STAMP = 0x3C307D70, 0x3C307D70 + 5000
    memory[0x9000], memory[0x9100], memory[0x9200 + 0x0C] = 0x9100, 0x9200, STAMP
    local realFind = ashita.memory.find
    ashita.memory.find = function(module, ...) if module == 'FFXiMain.dll' then return 0x9000 end return realFind(module, ...) end
    own = { 4, 13 }
    local player = manager.GetPlayer()
    manager.GetPlayer = function() return { GetIsZoning = player.GetIsZoning, GetStatusIcons = function() return own end,
        GetStatusTimers = function() return { (STAMP - EPOCH) * 60 + 90 * 60, (STAMP - EPOCH) * 60 + 30 * 60 } end,
        GetMainJob = player.GetMainJob, GetLoginStatus = player.GetLoginStatus } end
    debuffs.Clear(); cast(58, { [0x1000 + 300] = 236 })

    H.print('settings: Timers off to begin with', o.statusTimers[1] == false)
    block.Frame = 70; H.frames(1)
    local plainFoot = icons(0x400)[1].Y1
    H.print('off: nothing under the icons', times(0x400) == 0, times(300) == 0)
    o.statusTimers[1] = true; block.Frame = 71; H.frames(1)
    local ownCount, ownQuads = times(0x400)
    H.print('own: Paralysis 1m, two letters; none under Slow, which the game writes no time for', ownCount == 2 * GLYPHS)
    local row = icons(0x400)
    H.print('the time\'s middle under its icon', math.abs((ownQuads[1].X0 + ownQuads[#ownQuads].X1) * 0.5 - (row[1].X0 + row[1].X1) * 0.5) <= 2)
    H.print('outlined, as the names\' letters are', ownQuads[1].Flags ~= 0, ('| colour %08X'):format(ownQuads[1].Color))
    H.print('above: the row raised to make room', row[1].Y1 < plainFoot)
    local enemyCount = times(300)
    H.print('an enemy: Paralyze, 2m by the server\'s 120 s', enemyCount == 2 * GLYPHS)
    now = now + 75; block.Frame = 72; H.frames(1)
    H.print('75 s on: 45, still two letters', times(300) == 2 * GLYPHS)
    now = now + 40; block.Frame = 73; H.frames(1)
    H.print('115 s on: 5, one letter', times(300) == 1 * GLYPHS)
    H.print('a party member, whose times are not known: none', times(0x401) == 0, '| the row not raised', icons(0x401)[1].Y1 == plainFoot)
    o.statusPlace[1] = 'below'; block.Frame = 74; H.frames(1)
    H.print('below: the time under the icons still', times(0x400) == 2 * GLYPHS)
    o.statusPlace[1] = 'above'; o.statusTimers[1] = false
    AshitaCore.GetResourceManager, ashita.memory.find, manager.GetPlayer = function() return resources end, realFind, function() return player end
end
