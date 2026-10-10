-- twister: loads, and sounds for what it should and nothing else
local o = H.options()
H.print('settings: events', o.events.tell.enabled[1], o.events.ko.sound, '| low HP at', o.lowHpPercent[1], '| low MP at', o.lowMpPercent[1])

-- the game: a party of three, the third in another area
local me = { tp = 0, hp = 100, mp = 100, mpMax = 500 }
local members = { [0] = { id = 1, zone = 102, hp = 100 }, [1] = { id = 2, zone = 102, hp = 80 }, [2] = { id = 3, zone = 20, hp = 0 } }
local party = { GetMemberName = function() return 'Tester' end,
    GetMemberTP = function() return me.tp end,
    GetMemberHPPercent = function(_, place) return place == 0 and me.hp or members[place].hp end,
    GetMemberMPPercent = function() return me.mp end,
    GetMemberIsActive = function(_, place) return members[place] and 1 or 0 end,
    GetMemberServerId = function(_, place) return members[place].id end,
    GetMemberZone = function(_, place) return members[place].zone end }
local memory = { GetParty = function() return party end,
    GetPlayer = function() return { GetMPMax = function() return me.mpMax end, GetLoginStatus = function() return 2 end } end }
local core = AshitaCore
AshitaCore = setmetatable({ GetMemoryManager = function() return memory end }, { __index = core })

-- what has sounded since last asked, and time enough gone by for the same event to sound again
local function heard()
    local names = table.concat(H.sounds, ' ')
    for i = #H.sounds, 1, -1 do H.sounds[i] = nil end
    H.frames(40)
    local late = table.concat(H.sounds, ' ')
    for i = #H.sounds, 1, -1 do H.sounds[i] = nil end
    return names .. late
end

H.play(true); H.frames(150) -- in the game, and settled
H.print('nothing happening: silence', heard() == '')

-- chat: the kind at 0x04, the speaker at 0x08, the words at 0x17
local function chat(kind, speaker, words)
    return ('\0'):rep(4) .. string.char(kind) .. ('\0'):rep(3) .. speaker .. ('\0'):rep(15 - #speaker) .. words .. '\0'
end
H.packetData(0x017, chat(3, 'Someone', 'hello')); H.print('a tell:', heard())
H.packetData(0x017, chat(0, 'Someone', 'hello tester')); H.print('said aloud, with the name: silence', heard() == '')
H.packetData(0x017, chat(4, 'Someone', 'thanks Tester!')); H.print('the name in party chat:', heard())
H.packetData(0x017, chat(5, 'Someone', 'TESTER, you there?')); H.print('in linkshell chat, in capitals:', heard())
H.packetData(0x017, chat(4, 'Someone', 'the testers are here')); H.print('the name inside another word: silence', heard() == '')
H.packetData(0x017, chat(4, 'Tester', 'Tester is me')); H.print('said by the player: silence', heard() == '')
H.packetData(0x0DC, ('\0'):rep(40)); H.print('an invitation:', heard())
H.packetData(0x021, ('\0'):rep(16)); H.print('asked to trade:', heard())
-- two things at once: the second sound waits for the first to be over, and is not lost to it
H.packetData(0x017, chat(3, 'Someone', 'hello')); H.packetData(0x0DC, ('\0'):rep(40))
local atOnce = table.concat(H.sounds, ' '); H.frames(40)
H.print('a tell and an invitation together: at once', atOnce, '| then', H.sounds[#H.sounds], '| both heard', #H.sounds == 2); heard()

-- triggers: an action packet, packed a bit at a time as the game packs it. Who acts, the kind of action,
-- and the first result of the first target: its number and its message.
local function action(actor, category, number, message, what)
    local bits = {}
    local function put(offset, length, value)
        for i = 0, length - 1 do bits[offset + i] = math.floor(value / 2 ^ i) % 2 end
    end
    put(40, 32, actor); put(72, 6, 1); put(82, 4, category); put(86, 32, what or 0)
    put(150, 32, 1); put(182, 4, 1); put(213, 17, number); put(230, 10, message)
    local bytes = {}
    for index = 0, 40 do
        local byte = 0
        for i = 0, 7 do byte = byte + (bits[index * 8 + i] or 0) * 2 ^ i end
        bytes[#bytes + 1] = string.char(byte)
    end
    return table.concat(bytes)
end
-- mobs.lua is the project's; entity 0x123 is an Acro Bat, a bat, and 0x124 an Akbaba, a bird
local realLoadfile = loadfile
loadfile = function(path) local own = path:match('twister.(mobs%.lua)$') return realLoadfile(own and ('addons/twister/' .. own) or path) end
local entities = { [0x123] = { ServerId = 0x1066123, Name = 'Acro Bat' }, [0x124] = { ServerId = 0x1066124, Name = 'Akbaba' } }
function GetEntity(index) return entities[index] end
H.packetData(0x028, action(0x1066123, 7, 392, 43)); H.print('a weaponskill, no triggers: silence', heard() == '')
-- a trigger is for a kind of mob, wherever it is: which kind a mob is, is read from mobs.lua for the area, once
local reads = 0; local mapped = loadfile; loadfile = function(path) if path:find('mobs%.lua') then reads = reads + 1 end return mapped(path) end
o.triggers[1] = { mob = 'Bat', kind = 'skill', ids = { 392, 1700 }, name = 'Ultrasonics', sound = 'voicef-trigger.wav', enabled = { true } }
o.triggers[2] = { mob = 'Elemental', kind = 'spell', ids = { 154 }, name = 'Aero', sound = 'tone-trigger1.wav', enabled = { true } }
H.packetData(0x028, action(0x1066123, 7, 392, 43)); H.print('the mob readies the weaponskill:', heard())
H.packetData(0x028, action(0x1066123, 7, 392, 0)); H.print('and one with no message:', heard())
H.packetData(0x028, action(0x1066123, 7, 1700, 43)); H.print('the same weaponskill under its other number:', heard())
H.packetData(0x028, action(0x1066123, 7, 394, 43)); H.print('another weaponskill of its: silence', heard() == '')
H.packetData(0x028, action(0x1066124, 7, 392, 43)); H.print('the weaponskill, by a mob of another kind: silence', heard() == '')
entities[0x127] = { ServerId = 0x1066127, Name = 'Poison Bat' }
H.packetData(0x028, action(0x1066127, 7, 392, 43)); H.print('and by another mob of the kind:', heard())
H.packetData(0x028, action(0x1066123, 8, 392, 327)); H.print('a spell of the same number: silence', heard() == '')
H.packetData(0x028, action(0x1066123, 3, 392, 185)); H.print('the weaponskill landing: silence', heard() == '')
entities[0x125] = { ServerId = 0x1066125, Name = 'Air Elemental' }
H.packetData(0x028, action(0x1066125, 8, 154, 327)); H.print('a mob begins the spell:', heard())
H.packetData(0x028, action(0x1066125, 8, 154, 0)); H.print('the spell broken off: silence', heard() == '')
o.triggers[2].enabled[1] = false; H.packetData(0x028, action(0x1066125, 8, 154, 327)); H.print('its trigger off: silence', heard() == ''); o.triggers[2].enabled[1] = true
-- an ability is used at once: nothing says it is begun, and what says it is done names it as what the action is
entities[0x126] = { ServerId = 0x1066126, Name = 'Bloodtear Baldurf' }
o.triggers[3] = { mob = 'Ram', kind = 'ability', ids = { 688 }, name = 'Mighty Strikes', sound = 'tone-tp1.wav', enabled = { true } }
H.packetData(0x028, action(0x1066126, 11, 0, 0, 688)); H.print('a mob uses the ability:', heard())
H.packetData(0x028, action(0x1066126, 11, 0, 0, 265)); H.print('a weaponskill of its done: silence', heard() == '')
H.packetData(0x028, action(0x1066123, 11, 0, 0, 688)); H.print('the ability, by a mob of another kind: silence', heard() == '')
H.print('mobs.lua read for all of that:', reads, 'time')
-- another area: its own mobs of the kind, and not this one's
entities[0x128] = { ServerId = 0x106B128, Name = 'Fledermaus' }
members[0].zone = 107; H.packetData(0x028, action(0x106B128, 7, 392, 43)); H.print('in another area, a mob of the kind there:', heard())
H.packetData(0x028, action(0x1066123, 7, 392, 43)); H.print('and a mob that is not of that area: silence', heard() == '', '| read', reads, 'times')
members[0].zone = 5; H.packetData(0x028, action(0x1066123, 7, 392, 43)); H.print('in an area nothing is known of: silence', heard() == ''); members[0].zone = 102
-- triggers as they were first made, for an area: for one mob of it, and then for a kind there
o.triggers[4] = { zone = 107, mob = 'Rock Lizard', kind = 'skill', id = 366, sound = 'tp.wav', enabled = { true } }
o.triggers[5] = { zone = 107, mob = 'Quadav', mobs = { 'amber quadav' }, kind = 'spell', id = 1, name = 'Cure', sound = 'tp.wav', enabled = { true } }
o.events.tell.sound = 'voice-tell.wav'; o.triggers[1].sound = 'voice-trigger.wav'; o.events.ko.sound = 'ko.wav'
H.resettle(); o = H.options()
H.print('a sound chosen under its old name: its new one', o.events.tell.sound, o.triggers[1].sound, o.events.ko.sound, o.triggers[4].sound)
H.print('made for one mob of an area: now for its kind, anywhere', o.triggers[4].mob, o.triggers[4].zone == nil, '| made for a kind there: for the kind', o.triggers[5].mob, o.triggers[5].mobs == nil, '| and for one number: kept as its numbers', o.triggers[4].ids[1], o.triggers[4].id == nil)
table.remove(o.triggers); table.remove(o.triggers); H.frames(2)

-- TP, HP and MP
me.tp = 990; H.frames(8); me.tp = 1200; H.frames(8); H.print('TP over 1000:', heard())
me.tp = 1500; H.frames(8); H.print('more TP: silence', heard() == '')
me.hp = 40; H.frames(8); H.print('HP 40: silence', heard() == '')
me.hp = 25; H.frames(8); H.print('HP 25:', heard())
me.hp = 27; H.frames(8); me.hp = 20; H.frames(8); H.print('up a little and down again: silence', heard() == '')
me.hp = 60; H.frames(8); me.hp = 10; H.frames(8); H.print('healed, then low again:', heard())
me.hp = 0; H.frames(8); H.print('knocked out: silence', heard() == ''); me.hp = 100; H.frames(8)
me.mp = 15; H.frames(8); H.print('MP 15:', heard())
me.mp = 100; H.frames(8); me.mpMax = 0; me.mp = 0; H.frames(8); H.print('a job with no MP: silence', heard() == ''); me.mpMax = 500; me.mp = 100; H.frames(8)

-- the party
H.frames(200) -- the members have been here long enough to be believed
members[1].hp = 0; H.frames(8); H.print('a member has no HP: silence at first', #H.sounds == 0); H.print('and a second on, knocked out:', heard())
members[1].hp = 50; H.frames(8); members[1].hp = 0; H.frames(8); members[1].hp = 50; H.print('no HP for a moment only: silence', heard() == '')
members[1].hp = 0; H.frames(8); members[1].zone = 20; H.print('no HP, then gone from the area: silence', heard() == '')
members[1].zone = 102; members[1].hp = 70; H.frames(8); members[1].hp = 0; H.frames(20); members[1].hp = 70
H.print('arriving in the area, shown with no HP for a moment: silence', heard() == '')
H.frames(200); members[1].hp = 0; H.print('but knocked out later:', heard()); members[1].hp = 70; H.frames(8)
members[1].id = 9; H.frames(8); members[1].hp = 0; H.frames(40); members[1].hp = 70; H.print('someone new in their place, not yet believed: silence', heard() == ''); members[1].id = 2; H.frames(200)

-- a message: who it is about at 0x08, which message at 0x18. struct is the harness's stand-in, so its
-- unpack is given a real one for these two kinds of number.
local function message(about, id)
    local function le(value, bytes) local out = '' for _ = 1, bytes do out = out .. string.char(value % 256); value = math.floor(value / 256) end return out end
    return ('\0'):rep(8) .. le(about, 4) .. ('\0'):rep(12) .. le(id, 2) .. ('\0'):rep(4)
end
local stubUnpack = struct.unpack
struct.unpack = function(format, data, at)
    local size, value = format == 'I' and 4 or 2, 0
    for i = size - 1, 0, -1 do value = value * 256 + data:byte(at + i) end
    return value
end
H.packetData(0x029, message(1, 38)); H.print('a skill of the player\'s rises:', heard())
H.packetData(0x029, message(1, 53 + 0x8000)); H.print('and reaches a level:', heard())
H.packetData(0x029, message(2, 38)); H.print('someone else\'s skill: silence', heard() == '')
H.packetData(0x029, message(1, 206)); H.print('another message about the player: silence', heard() == '')
-- a system message: who it is from at 0x04, which message at 0x0A
local function systemMessage(id)
    return ('\0'):rep(10) .. string.char(id % 256, math.floor(id / 256)) .. string.char(0x10) .. 'string2 Someone' .. ('\0'):rep(8)
end
H.packetData(0x009, systemMessage(89)); H.print('examined:', heard())
H.packetData(0x009, systemMessage(88)); H.print('another system message: silence', heard() == '')
-- treasure: which item at 0x10, and whether it was in the pool already at 0x15. The harness names item 500 'Item 500'.
local function treasure(item, old)
    return ('\0'):rep(16) .. string.char(item % 256, math.floor(item / 256)) .. ('\0'):rep(3) .. string.char(old and 1 or 0) .. ('\0'):rep(38)
end
H.packetData(0x0D2, treasure(500)); H.print('a drop, no items named: silence', heard() == '')
o.dropItems[1] = 'Other Thing,  item 500 ,'
H.packetData(0x0D2, treasure(500)); H.print('a drop of an item named:', heard())
H.packetData(0x0D2, treasure(501)); H.print('a drop of another item: silence', heard() == '')
H.packetData(0x0D2, treasure(500, true)); H.print('one in the pool already: silence', heard() == '')
H.packetData(0x0D2, treasure(0)); H.print('an empty place in the pool: silence', heard() == '')
o.events.drop.enabled[1] = false; H.packetData(0x0D2, treasure(500)); H.print('drops off: silence', heard() == ''); o.events.drop.enabled[1] = true
struct.unpack = stubUnpack

-- arriving somewhere: nothing is believed at first
H.play(false); H.frames(8); me.tp = 0; H.play(true); H.frames(8); me.tp = 2000; me.hp = 5; H.frames(8)
H.print('just arrived, numbers jumping: silence', heard() == ''); me.hp = 100; H.frames(150)

-- switched off
o.events.tell.enabled[1] = false; H.packetData(0x017, chat(3, 'Someone', 'hello')); H.print('tells off: silence', heard() == '')
o.events.tell.enabled[1] = true
o.events.tell.sound = 'tone-tell2.wav'; H.packetData(0x017, chat(3, 'Someone', 'hello')); H.print('another sound chosen:', heard())

-- the command opens the settings, there being no window
local begun = H.calls.Begin or 0
H.print('/twister kept from the game', H.command('/twister')); H.frames(2)
H.print('settings drawn', (H.calls.Begin or 0) > begun, '| checkboxes', (H.calls.Checkbox or 0) > 8, '| sliders', H.calls.SliderInt, '| combos', (H.calls.BeginCombo or 0) > 0)
local lines = H.calls.NewLine or 0; H.frames(1)
H.print('a blank line over each group but the first', (H.calls.NewLine or 0) - lines == 2)
H.print('the items named can be written', (H.calls.InputText or 0) > 0)
H.print('a mark for each event\'s description', (H.calls.TextDisabled or 0) > 0)
H.ret.IsItemHovered = { true }; local tips = H.calls.BeginTooltip or 0; H.frames(1); H.ret.IsItemHovered = { false }
H.print('hovered, a mark says its piece in a box no wider than a line', (H.calls.BeginTooltip or 0) > tips, H.calls.PushTextWrapPos == H.calls.PopTextWrapPos, H.calls.BeginTooltip == H.calls.EndTooltip)
local sliders = H.calls.SliderInt
o.events.lowhp.enabled[1] = false; H.frames(1); H.print('Low HP off: its threshold not drawn', H.calls.SliderInt - sliders == 1)
sliders = H.calls.SliderInt
o.events.lowhp.enabled[1] = true; H.frames(1); H.print('and on again: drawn', H.calls.SliderInt - sliders == 2)
H.ret.Button = { true }; H.frames(1); H.ret.Button = { false }; H.print('every Test button:', #H.sounds, 'sounds'); heard()

-- the Triggers tab: the area's mobs to choose from, and what the chosen one does
H.tab(2); local combos, texts = H.calls.BeginCombo, H.calls.Text or 0; H.frames(1)
H.print('Triggers drawn: combos', H.calls.BeginCombo - combos, '| a line for each trigger', (H.calls.Text or 0) - texts >= 3)
-- what a kind does: what its mobs do first, then what only its notorious monsters do, each list under the monster's name
-- and level: those of the area first, and a monster that is in two areas as two
local function beetle()
    local imgui, seen = require('imgui'), {}
    rawset(imgui, 'Selectable', function(label) seen[#seen + 1] = label:match('^[^#]+') return label == 'Beetle' end)
    rawset(imgui, 'TextDisabled', function(text) seen[#seen + 1] = '[' .. text .. ']' end); rawset(imgui, 'Separator', function() seen[#seen + 1] = '|' end)
    H.ret.BeginCombo = { true }; H.frames(1); seen = {}; H.frames(1); H.ret.BeginCombo = { false }
    rawset(imgui, 'Selectable', nil); rawset(imgui, 'TextDisabled', nil); rawset(imgui, 'Separator', nil)
    local text = table.concat(seen, ' '); local actions = text:sub((text:find('Elsewhere', 1, true)))
    local headers = {} for header in actions:gmatch('| %[([^%]]-%(Lv [^%]]+)%]') do headers[#headers + 1] = header end
    return actions, headers
end
do
    local actions, headers = beetle()
    H.print('Beetle, what its mobs do:', actions:match('%(%?%)%] (.-) | %['))
    -- what three or more of its notorious monsters do is said once, under one heading, and not under each
    local several = actions:match('%[Notorious Monsters%] ([^|]*)')
    H.print('then what several of its notorious monsters do:', several, '| and none of it under a monster', actions:match('Lancing Lamorak[^|]*'):find(several:match('^(.-%))'), 1, true) == nil)
    H.print('then its notorious monsters, lowest first:', table.concat(headers, ', '))
    -- every list in the same order: abilities, then weaponskills, then spells, each by name
    local lumber = actions:match('%[Lumber Jack %(Lv 55%)%] ([^|]*)')
    H.print('a list is abilities, weaponskills, spells:', lumber:find('%(Ability%)') < lumber:find('%(Spell%)'), '| Lumber Jack\'s begins', lumber:match('^.-%)'), '| and its spells are by name', lumber:match('%(Spell%) (.-) %(Spell%)') ~= nil)
    H.print('Tornado (spell 208) is Lancing Lamorak\'s, not every beetle\'s', actions:match('Lancing Lamorak.*Spell 208') ~= nil, actions:match('%(%?%)%] (.-) | %['):find('Spell 208', 1, true) == nil)
    -- West Ronfaure, where Lancing Lamorak is: its list is the first, and has all that is its own
    members[0].zone = 100; local there, first = beetle(); members[0].zone = 102
    H.print('in its own area a monster is first:', first[1], '| then', first[2], '| with all that is its own, there as anywhere', select(2, there:match('Lancing Lamorak[^|]*'):gsub('Spell', '')) == select(2, actions:match('Lancing Lamorak[^|]*'):gsub('Spell', '')))
    -- every monster has all of its own, whoever else does it: Kettenkaefer and the higher Panzer Percival cast the same things
    H.print('two monsters that do the same things each have them:', actions:match('%[Kettenkaefer %(Lv 80%)%] ([^|]*)') == actions:match('%[Panzer Percival %(Lv 75%-80%)%] ([^|]*)'), '| spells under Lancing Lamorak', select(2, actions:match('Lancing Lamorak[^|]*'):gsub('Spell', '')))
end
-- every list open and everything in it chosen: the last kind of mob, of those not in the area, and the last thing it does are what is being made
H.ret.BeginCombo = { true }; H.ret.Selectable = { true }; H.frames(2); H.ret.BeginCombo = { false }; H.ret.Selectable = { false }; heard()
-- every button pressed at once: Create Trigger makes one, and Remove, pressed on each, takes the last away again, which is that one
local before, gone, realRemove = #o.triggers, nil, table.remove
table.remove = function(list, at) if list == o.triggers then gone = list[at] end return realRemove(list, at) end
H.ret.Button = { true }; H.frames(1); H.ret.Button = { false }; heard(); table.remove = realRemove
H.print('Create Trigger made one:', gone.mob, gone.kind, table.concat(gone.ids, ' '), gone.sound, gone.enabled[1], '| for no one area', gone.zone == nil, '| and Remove took it away', #o.triggers == before)
-- what is known of the mobs is read for the tab and let go of with the settings: asked for again when they are next open
reads = 0
H.frames(3); H.print('with the settings open, not read again', reads == 0)
members[0].zone = 5; H.frames(1); H.print('an area nothing is known of: drawn all the same', reads == 0); members[0].zone = 102
H.command('/twister'); H.frames(2); H.command('/twister'); H.frames(3); H.print('closed and opened: read once more', reads == 1)
H.tab(1)

-- an event's list of sounds: the ones made for it first (its two voices, its tone, its second tone), then a line, then the rest
local imgui, listed = require('imgui'), {}
ashita.fs.get_directory = function() return { 'zebra.wav', 'tone-tell2.wav', 'voicef-ko.wav', 'tone-tell1.wav', 'voicem-tell.wav', 'voicef-tell.wav', 'tone-ko2.wav' } end
rawset(imgui, 'Selectable', function(label) listed[#listed + 1] = label return false end); rawset(imgui, 'Separator', function() listed[#listed + 1] = '|' end)
H.frames(110) -- long enough for the files to be looked for again
H.ret.BeginCombo = { true }; H.frames(1); H.ret.BeginCombo = { false }; rawset(imgui, 'Selectable', nil); rawset(imgui, 'Separator', nil)
H.print('the first event\'s sounds:', table.concat(listed, ' ', 1, 8))
H.command('/twister'); begun = H.calls.Begin; H.frames(2); H.print('/twister closes them', H.calls.Begin == begun)
H.unload(); H.print('unload ran; saves', H.saves() > 0)
