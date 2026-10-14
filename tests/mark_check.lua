-- mark: loads, shows a monster's record in words, takes a mark, watches the game for it, times its
-- placeholders and its window, and draws its map
local realLoadfile = loadfile
loadfile = function(path)
    local own = path:match('^C:\\ashita\\addons\\mark\\(.*)$')
    return realLoadfile(own and ('addons/mark/' .. own) or path)
end

-- the game: a zone, the player at the middle of it, and whichever entities are put in range
local zone, entities = 100, {}
local memory = AshitaCore:GetMemoryManager()
local party = memory.GetParty()
party.GetMemberZone = function() return zone end
party.GetMemberTargetIndex = function() return 1024 end
entities[1024] = { x = 0, y = 0, hp = 100, far = 0 }
local function field(name, missing) return function(_, index) local e = entities[index] return e and e[name] or missing end end
local manager = { GetRenderFlags0 = function(_, index) return entities[index] and 0x200 or 0 end, GetHPPercent = field('hp', 0),
    GetDistance = function(_, index) return entities[index] and entities[index].far ^ 2 or 0 end,
    GetLocalPositionX = field('x', 0), GetLocalPositionY = field('y', 0), GetLocalPositionZ = field('h', 0) }
memory.GetParty = function() return party end
memory.GetEntity = function() return manager end
AshitaCore.GetMemoryManager = function() return memory end

-- the client's table of maps, fourteen bytes to a map: West Ronfaure's one map and two of Garlaige
-- Citadel's, each two and a half yalms to the unit with the middle of the zone at the middle of the map
local bytes, words, mapsReadable = {}, {}, false
local function map(index, zoneId, floor)
    local base = 5000 + index * 14
    words[base], bytes[base + 2], bytes[base + 5], words[base + 10], words[base + 12] = zoneId, floor, 2, 65536 - 256, 65536 - 256
end
map(0, 100, 0); map(112, 200, 1); map(113, 200, 2)
ashita.memory.find = function(_, _, signature) return mapsReadable and signature:sub(1, 4) == '8A0D' and 1000 or 0 end
ashita.memory.read_uint32 = function(address) return address == 1000 + 0x1C and 5000 or 0 end
ashita.memory.read_uint16 = function(address) return words[address] or 0 end
ashita.memory.read_uint8 = function(address) return bytes[address] or 0 end
local maps = require('maps')
maps.ClientFloor = function(_, y) return y < 0 and 2 or 1 end -- below ground is the second floor

-- everything written in a window, to look through
local texts = {}
local imgui = require('imgui')
for _, name in ipairs({ 'Text', 'TextUnformatted', 'TextWrapped', 'TextDisabled', 'TableSetupColumn', 'SetTooltip' }) do
    rawset(imgui, name, function(text) texts[#texts + 1] = text end)
end
rawset(imgui, 'TextColored', function(_, text) texts[#texts + 1] = text end)
local function wrote(part)
    for _, text in ipairs(texts) do if tostring(text):find(part, 1, true) then return true end end
    return false
end
local function exactly(whole)
    for _, text in ipairs(texts) do if text == whole then return true end end
    return false
end
local function frames(count) texts = {}; H.frames(count or 9) end
local function drawn(name) return H.calls['draw.' .. name] or 0 end

local o = H.options()
H.play(true); frames()
H.print('nothing chosen: the first monster of the zone the player is in', o.viewZone == 100, o.viewName)

o.viewName = 'Jaggedy-Eared Jack'; frames()
H.print('how it appears', wrote('Lottery: a 9% chance'), wrote('closed for 40 min'))
H.print('a percent sign is written as it is, not as a format', H.calls.TextWrapped == nil)
H.print('its placeholder and where, with no map to be read', wrote('Forest Hare'), wrote('Anywhere within about 120 yalms of (-341, -233)'), '| the placeholder\'s is the point alone', exactly('(-341, -233)'))
H.print('its drops at each level', wrote('Item 13112'), wrote('No TH'), wrote('TH4'), wrote('TH5') == false, wrote('2.5%'))
H.print('what can be stolen', wrote('Steal: Item 4389'))
H.print('nearest spawn point from where the player stands', wrote('Nearest is 413 yalms SW of you.'))
o.maxTh[1] = 8; frames(); H.print('more Treasure Hunter asked for', wrote('TH8'), wrote('4.75%'))

-- the map can be read: the square goes before the point (the first reading is tried again in five seconds)
mapsReadable = true; frames(200)
H.print('the square of the map', wrote('Anywhere within about 120 yalms of D-11 (-341, -233)'), exactly('D-11 (-341, -233)'))
H.print('squares: the middle is H-8, the corner A-1', maps.Square(256, 256) == 'H-8', maps.Square(20, 20) == 'A-1', maps.Square(47, 48) == 'A-2', maps.Square(48, 47) == 'B-1')

-- the header and the tabs
H.print('a header, and three tabs with Database the first', exactly('Mark'), H.calls.BeginTabBar ~= nil, H.calls.BeginTabItem ~= nil, wrote('How It Appears'))
H.tab(2); frames(); H.print('the Marks tab, with nothing in it yet', wrote('No marks, and no times of death.'), wrote('How It Appears') == false)
o.marks[1] = { zone = 100, name = 'Jaggedy-Eared Jack' }
frames(); H.print('a mark is listed there, out of range', exactly('Jaggedy-Eared Jack'), exactly('West Ronfaure'), exactly('Unknown'), wrote('Next Spawn'))

entities[295] = { x = 30, y = 30, hp = 100, far = 42.4 }
frames(); H.print('up: said', H.printed[#H.printed], '| sound', H.sounds[#H.sounds], '| shown', wrote('Up, 42 yalms NE'))
H.tab(1)
local said = #H.printed; frames(); H.print('said once', #H.printed == said)

-- the placeholder: in range, dead and timed from then, up again
entities[294] = { x = -10, y = 0, hp = 100, far = 10 }
frames(); H.print('its placeholder in range', wrote('Up, 10 yalms W'))
entities[294].hp = 0
frames(); H.print('its placeholder dead: timed from its respawn of three minutes', exactly('In 3:00') or exactly('In 2:59'), '| no level, and Next Spawn for Now', exactly('Lv') == false, exactly('Now') == false, exactly('Next Spawn'))
entities[294] = nil
frames(); H.print('out of range: still timed', wrote('In 2:5') or wrote('In 3:00'))
entities[294] = { x = -10, y = 0, hp = 100, far = 10 }
frames(); frames(1); H.print('up again: no longer timed', wrote('Up, 10 yalms W'), wrote('In 2:5') == false)

H.print('said as it came up', H.printed[#H.printed])

-- a placeholder's death given by hand, and said as it falls due
H.command('/mark ph 126 2'); H.print('/mark ph 126 2:', (H.printed[#H.printed]:gsub('%d%d:%d%d:%d%d', 'HH:MM:SS')))
entities[294] = nil; frames(); frames(1); H.print('timed from two minutes ago', exactly('In 1:00') or exactly('In 0:59'))
H.command('/mark ph 126 4'); frames(); frames(1); H.print('past due: shown and said', wrote('Due 1:0'), H.printed[#H.printed])
said = #H.printed; frames(); H.print('said once', #H.printed == said)
H.command('/mark ph 126 clear'); H.print('/mark ph 126 clear:', H.printed[#H.printed])
H.command('/mark ph 999'); H.print('an ID that is no placeholder\'s:', H.printed[#H.printed]:sub(1, 28))
H.ret.SmallButton = { true }; frames(1); H.ret.SmallButton = nil; frames(); frames(1)
H.print('the row\'s buttons: the map opened, and its death timed then forgotten', o.showMap[1], exactly('Unknown'))
o.showMap[1] = false
entities[294] = { x = -10, y = 0, hp = 100, far = 10 }; frames()

-- the mark's death, seen
entities[295].hp = 0
frames(); H.print('dead: said', H.printed[#H.printed], '| time kept', #o.tods == 1 and o.tods[1].name, '| lottery', wrote('The lottery opens in 40:00') or wrote('The lottery opens in 39:59'))
entities[295] = nil; o.tods[1].at = os.time() - 3000
frames(); H.print('later', wrote('Died 50 min ago. The lottery is open.'))
entities[295] = { x = 0, y = -5, hp = 100, far = 5 }
frames(); H.print('up again: the time is let go', #o.tods == 0, H.printed[#H.printed])
entities[295] = nil; frames()

-- a death given by hand
H.command('/mark tod 15'); H.print('/mark tod 15:', (H.printed[#H.printed]:gsub('%d%d:%d%d%.', 'HH:MM.', 1)), '|', #o.tods == 1 and math.abs(os.time() - 900 - o.tods[1].at) <= 1)
H.command('/mark tod 99:99'); H.print('a time that is none:', H.printed[#H.printed]:sub(1, 30))
H.command('/mark tod clear'); H.print('/mark tod clear:', H.printed[#H.printed], '|', #o.tods == 0)
local clock = os.date('%H:%M', os.time() - 7200)
H.command('/mark tod ' .. clock); H.print('/mark tod by the clock: two hours ago', #o.tods == 1 and math.abs(os.time() - 7200 - o.tods[1].at) < 61)
H.command('/mark tod clear')
H.ret.Button = { true }; frames(1); H.ret.Button = { false }
H.print('Clear Mark, Show Map and Report TOD clicked', #o.marks == 0, o.showMap[1], #o.tods == 1 and o.tods[1].name)
H.print('and the header\'s button, which closes the window', o.isVisible[1] == false)
o.showMap[1], o.isVisible[1] = false, true

-- the Marks tab: a monster with a time of death and no mark on it, and its buttons
H.tab(2); frames()
H.print('a time of death alone puts a monster in the list', exactly('Jaggedy-Eared Jack'), wrote('Window in '), wrote('Forest Hare') == false)
o.viewName = 'Bomb King'
H.ret.SmallButton = { true }; frames(1); H.ret.SmallButton = nil
H.print('its buttons: looked up, its time forgotten, made a mark', o.viewName, #o.tods == 0, #o.marks == 1 and o.marks[1].name)
frames(2); H.print('Database turns to the first tab', H.calls.BeginTabItem ~= nil)
entities[294] = { x = -10, y = 0, hp = 100, far = 10 }; frames()
H.print('a mark of this zone has its placeholders under it', wrote('Forest Hare (126)'), wrote('Up, 10 yalms W'))
o.marks[2] = { zone = 127, name = 'King Behemoth' }; frames()
H.print('a second mark, of another zone', exactly('King Behemoth'), exactly('Unknown'))
table.remove(o.marks, 2); H.tab(1)

H.command('/mark tod'); H.command('/mark compact'); entities[294].hp = 0; frames()
H.print('compact: the mark, its window and its placeholder\'s respawn, and no more', o.compact[1], wrote('The lottery opens in'), wrote('Forest Hare'), wrote('Respawns in'), wrote('Drops') == false, exactly('Mark') == false)
zone = 107; frames(); H.print('in another zone: where the mark is', wrote('West Ronfaure'), wrote('Forest Hare') == false)
H.command('/mark compact')

H.command('/mark set lizz'); H.print('/mark set, by a part of a name:', H.printed[#H.printed], '|', #o.marks == 2 and o.marks[2].zone, o.viewName)
frames(); H.print('a monster of two spawns, a lottery from a module', wrote('closed for 1 hr'), wrote('Rock Lizard'))
H.tab(2); frames(); H.print('both marks are listed, the first with how its window stands', exactly('Jaggedy-Eared Jack'), exactly(o.marks[2].name), wrote('Window in ')); H.tab(1)
H.command('/mark set nobody at all'); H.print('no such monster:', H.printed[#H.printed])
H.command('/mark clear lizz'); H.print('/mark clear <name>:', H.printed[#H.printed], '|', #o.marks == 1 and o.marks[1].name)
H.command('/mark clear nobody'); H.print('/mark clear, of no mark:', H.printed[#H.printed])
H.command('/mark clear'); H.print('/mark clear:', H.printed[#H.printed], '|', #o.marks == 0)

o.viewZone, o.viewName = 127, 'King Behemoth'; frames()
H.print('a trade to a ???', wrote('Forced: trade Item 3342 to the ??? at (-269, 74).'), '| a roll of several', wrote('One Of'), wrote('   Item 1334'))
o.viewZone, o.viewName = 200, 'Serket'; frames()
H.print('a timed spawn of many points', wrote('Timed: it respawns 21 hr to 24 hr after it dies.'), wrote('40 points, from'))
H.command('/mark tod 60'); frames()
H.print('with no mark, /mark tod is the monster on show\'s: a timed window', #o.tods == 2 and o.tods[2].name, wrote('Its window opens in 20:00:0') or wrote('Its window opens in 19:59:5'))
o.tods[2].at = os.time() - 80000; frames(); H.print('inside the window', wrote('Its window is open, for 1:46:'))

-- the map
zone = 100; o.viewZone, o.viewName = 100, 'Jaggedy-Eared Jack'; entities[294].hp = 100
local before = drawn('AddRectFilled')
H.command('/mark map'); frames()
H.print('/mark map: the map, with no picture to be had here', o.showMap[1], wrote('picture was not found'), wrote('Placeholders'))
H.print('a region filled, the player and the placeholder in range spotted', drawn('AddRectFilled') - before > 20, drawn('AddCircleFilled') > 0, wrote('In Range'))
H.ret.IsItemHovered = { true }; H.ret.GetMousePos = { 10 + 256, 20 + 256 }; frames(1); H.ret.IsItemHovered = { false }
H.print('under the mouse, the middle of the map', wrote('H-8 (0, 0)'))
o.mapSize[1] = 256; frames(); H.print('a smaller map', true)

-- a zone of several maps: one cannot be told from another outside it
o.viewZone, o.viewName = 200, 'Serket'; frames(200)
H.print('outside it: no squares, and the map says why', wrote('40 points, from'), wrote('40 points in') == false, wrote('can be told only in the zone'))
zone = 200; local spots = drawn('AddCircleFilled'); frames(200); frames(1)
H.print('inside it: squares, and its spots on the map its places are on', wrote('40 points in'), wrote('can be told only in the zone') == false, drawn('AddCircleFilled') > spots)
o.viewZone, o.viewName = 127, 'King Behemoth'; frames(200)
H.print('a zone whose map the client does not give up', wrote('could not be read'))
H.command('/mark map')

o.viewName = 'Nobody'; frames(); H.print('a name the data has not', wrote('There is no data for Nobody.'))
H.ret.BeginCombo = { true }; H.ret.Selectable = { true }; frames(2); H.ret.BeginCombo = nil; H.ret.Selectable = { false }
H.print('the dropdowns open and choose', o.viewName ~= 'Nobody', o.viewName)
H.print('scripted spawns are left out until asked for', (function()
    local hunts = require('hunts')
    return #hunts.Zones(true) > #hunts.Zones(false) and #hunts.Find('Marauder Dvogzog', false) == 0 and #hunts.Find('Marauder Dvogzog', true) == 1
end)())

o.tods[1] = 'nonsense'; H.resettle(); H.print('a time of death with a part missing is dropped', #o.tods == 1 and o.tods[1].name)
o.marks[1] = 'nonsense'; o.markZone, o.markName = 100, 'Jaggedy-Eared Jack'; H.resettle()
H.print('a mark with a part missing is dropped, and the one mark of an older file is brought over', #o.marks == 1 and o.marks[1].name, o.markName == nil)
H.print('/mark config kept from the game', H.command('/mark config')); frames(1)
H.command('/mark'); H.print('/mark hides it', o.isVisible[1] == false, '| /marker is left alone', H.command('/marker x') == false)
H.unload(); H.print('unload ran; saves', H.saves() > 0)
