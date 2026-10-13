-- mark: loads, shows a monster's record in words, takes a mark, and watches the game for it
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
    GetLocalPositionX = field('x', 0), GetLocalPositionY = field('y', 0) }
memory.GetParty = function() return party end
memory.GetEntity = function() return manager end
AshitaCore.GetMemoryManager = function() return memory end

-- everything written in a window, to look through
local texts = {}
local imgui = require('imgui')
for _, name in ipairs({ 'Text', 'TextWrapped', 'TextDisabled' }) do
    rawset(imgui, name, function(text) texts[#texts + 1] = text end)
end
rawset(imgui, 'TextColored', function(_, text) texts[#texts + 1] = text end)
rawset(imgui, 'TableSetupColumn', function(text) texts[#texts + 1] = text end)
local function wrote(part)
    for _, text in ipairs(texts) do if tostring(text):find(part, 1, true) then return true end end
    return false
end
local function frames(count) texts = {}; H.frames(count or 9) end

local o = H.options()
H.play(true); frames()
H.print('nothing chosen: the first monster of the zone the player is in', o.viewZone == 100, o.viewName)

o.viewName = 'Jaggedy-Eared Jack'; frames()
H.print('how it appears', wrote('Lottery: a 9% chance'), wrote('closed for 40 min'))
H.print('its placeholder and where', wrote('Forest Hare'), wrote('Anywhere within about 120 yalms of (-341, -233)'))
H.print('its drops at each level', wrote('Item 13112'), wrote('No TH'), wrote('TH4'), wrote('TH5') == false, wrote('2.5%'))
H.print('what can be stolen', wrote('Steal: Item 4389'))
H.print('nearest spawn point from where the player stands', wrote('Nearest is 413 yalms SW of you.'))
o.maxTh[1] = 8; frames(); H.print('more Treasure Hunter asked for', wrote('TH8'), wrote('4.75%'))

local saves = H.saves()
H.ret.Button = { true }; frames(1); H.ret.Button = { false }
H.print('Set As Mark', o.markName, o.markZone, '| saved', H.saves() > saves)
frames(); H.print('the mark heads the window, out of range', wrote('Mark:'), wrote('Not In Range'))

entities[295] = { x = 30, y = 30, hp = 100, far = 42.4 }
frames(); H.print('up: said', H.printed[#H.printed], '| sound', H.sounds[#H.sounds], '| shown', wrote('Up, 42 yalms NE'))
local said = #H.printed; frames(); H.print('said once', #H.printed == said)
entities[294] = { x = -10, y = 0, hp = 100, far = 10 }
frames(); H.print('its placeholder in range', wrote('Up, 10 yalms W'))

entities[295].hp = 0
frames(); H.print('dead: said', H.printed[#H.printed], '| time kept', o.killedAt > 0, '| lottery', wrote('The lottery opens in 40 min.'))
entities[295] = nil; o.killedAt = os.time() - 3000
frames(); H.print('later', wrote('Seen dead 50 min ago. The lottery is open.'))
entities[295] = { x = 0, y = -5, hp = 100, far = 5 }
frames(); H.print('up again: the time is let go', o.killedAt == 0, H.printed[#H.printed])

H.command('/mark compact'); frames()
H.print('compact: the mark and its placeholder, and no more', o.compact[1], wrote('Forest Hare'), wrote('Drops') == false)
zone = 107; frames(); H.print('in another zone: where the mark is', wrote('West Ronfaure'), wrote('Forest Hare') == false)
H.command('/mark compact')

H.command('/mark set lizz'); H.print('/mark set, by a part of a name:', H.printed[#H.printed], '|', o.markZone, o.viewName)
frames(); H.print('a monster of two spawns, a lottery from a module', wrote('closed for 1 hr'), wrote('Rock Lizard'))
H.command('/mark set nobody at all'); H.print('no such monster:', H.printed[#H.printed])
H.command('/mark clear'); H.print('/mark clear:', H.printed[#H.printed], '|', o.markName == '')
frames(); H.print('no mark: nothing heads the window', wrote('Mark:') == false)

o.viewZone, o.viewName = 127, 'King Behemoth'; frames()
H.print('a trade to a ???', wrote('Forced: trade Item 3342 to the ??? at (-269, 74).'), '| a roll of several', wrote('One Of'), wrote('   Item 1334'))
o.viewZone, o.viewName = 200, 'Serket'; frames()
H.print('a timed spawn of many points', wrote('Timed: it respawns 21 hr to 24 hr after it dies.'), wrote('40 points, from'))

o.viewName = 'Nobody'; frames(); H.print('a name the data has not', wrote('There is no data for Nobody.'))
H.ret.BeginCombo = { true }; H.ret.Selectable = { true }; frames(2); H.ret.BeginCombo = nil; H.ret.Selectable = { false }
H.print('the dropdowns open and choose', o.viewName ~= 'Nobody', o.viewName)
H.print('scripted spawns are left out until asked for', (function()
    local hunts = require('hunts')
    return #hunts.Zones(true) > #hunts.Zones(false) and #hunts.Find('Marauder Dvogzog', false) == 0 and #hunts.Find('Marauder Dvogzog', true) == 1
end)())

H.print('/mark config kept from the game', H.command('/mark config')); frames(1)
H.command('/mark'); H.print('/mark hides it', o.isVisible[1] == false, '| /marker is left alone', H.command('/marker x') == false)
H.unload(); H.print('unload ran; saves', H.saves() > 0)
