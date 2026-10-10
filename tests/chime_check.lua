-- chime: loads, and sounds for what it should and nothing else
local o = H.options()
H.print('settings: events', o.events.tell.enabled[1], o.events.ko.sound, '| low HP at', o.lowHpPercent[1], '| low MP at', o.lowMpPercent[1])

-- the game: a party of three, the third in another area, and something targeted
local me = { tp = 0, hp = 100, mp = 100, mpMax = 500 }
local members = { [0] = { id = 1, zone = 10, hp = 100 }, [1] = { id = 2, zone = 10, hp = 80 }, [2] = { id = 3, zone = 20, hp = 0 } }
local party = { GetMemberName = function() return 'Tester' end,
    GetMemberTP = function() return me.tp end,
    GetMemberHPPercent = function(_, place) return place == 0 and me.hp or members[place].hp end,
    GetMemberMPPercent = function() return me.mp end,
    GetMemberIsActive = function(_, place) return members[place] and 1 or 0 end,
    GetMemberServerId = function(_, place) return members[place].id end,
    GetMemberZone = function(_, place) return members[place].zone end,
    GetMemberTargetIndex = function(_, place) return members[place].index or 0 end }
local memory = { GetParty = function() return party end,
    GetPlayer = function() return { GetMPMax = function() return me.mpMax end, GetLoginStatus = function() return 2 end } end,
    GetTarget = function() return { GetTargetIndex = function() return 7 end } end }
local core = AshitaCore
AshitaCore = setmetatable({ GetMemoryManager = function() return memory end }, { __index = core })
-- entity 7 is what is targeted; 11 is the second member, whose pet is 12
local entities = { [7] = { ServerId = 900 }, [11] = { ServerId = 2, PetTargetIndex = 12 }, [12] = { ServerId = 77 } }
function GetEntity(index) return entities[index] end

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

-- an action packet, packed a bit at a time as the game packs it: results is a list for each target
local function action(actor, targets, category)
    local bits = {}
    local function put(offset, length, value)
        for i = 0, length - 1 do bits[offset + i] = math.floor(value / 2 ^ i) % 2 end
    end
    put(40, 32, actor); put(72, 6, #targets); put(82, 4, category or 3)
    local offset = 150
    for _, target in ipairs(targets) do
        put(offset, 32, target.id); put(offset + 32, 4, #target.results); offset = offset + 36
        for _, result in ipairs(target.results) do
            put(offset + 44, 10, 185); put(offset + 85, 1, result.added and 1 or 0); offset = offset + 86
            if result.added then put(offset + 27, 10, result.added); offset = offset + 37 end
            put(offset, 1, result.spikes and 1 or 0); offset = offset + 1
            if result.spikes then put(offset + 24, 10, result.spikes); offset = offset + 34 end
        end
    end
    local bytes = {}
    for index = 0, math.ceil(offset / 8) + 4 do
        local byte = 0
        for i = 0, 7 do byte = byte + (bits[index * 8 + i] or 0) * 2 ^ i end
        bytes[#bytes + 1] = string.char(byte)
    end
    return table.concat(bytes)
end
H.packetData(0x028, action(2, { { id = 555, results = { { } } } })); H.print('a weapon skill, no skillchain: silence', heard() == '')
H.packetData(0x028, action(2, { { id = 555, results = { { spikes = 33 }, { added = 288 } } } })); H.print('a party member\'s skillchain:', heard())
H.packetData(0x028, action(77, { { id = 555, results = { { added = 289 } } } })); H.print('a stranger\'s, on something else: silence', heard() == '')
members[1].index = 11; H.packetData(0x028, action(77, { { id = 555, results = { { added = 289 } } } })); H.print('a member\'s pet\'s, on something else:', heard()); members[1].index = nil
H.packetData(0x028, action(77, { { id = 444, results = { { added = 161 } } }, { id = 900, results = { { added = 770 } } } })); H.print('a stranger\'s, on the target:', heard())
H.packetData(0x028, action(2, { { id = 555, results = { { added = 163 } } } })); H.print('another additional effect: silence', heard() == '')
H.packetData(0x028, action(2, { { id = 555, results = { { added = 288 } } } }, 1)); H.print('a round of attacks is not read: silence', heard() == '')

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
members[1].zone = 10; members[1].hp = 70; H.frames(8); members[1].hp = 0; H.frames(20); members[1].hp = 70
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
struct.unpack = stubUnpack

-- arriving somewhere: nothing is believed at first
H.play(false); H.frames(8); me.tp = 0; H.play(true); H.frames(8); me.tp = 2000; me.hp = 5; H.frames(8)
H.print('just arrived, numbers jumping: silence', heard() == ''); me.hp = 100; H.frames(150)

-- switched off
o.events.tell.enabled[1] = false; H.packetData(0x017, chat(3, 'Someone', 'hello')); H.print('tells off: silence', heard() == '')
o.events.tell.enabled[1] = true; o.enabled[1] = false
H.packetData(0x017, chat(3, 'Someone', 'hello')); H.packetData(0x0DC, ('\0'):rep(40)); H.print('everything off: silence', heard() == '')
o.enabled[1] = true
o.events.tell.sound = 'bell.wav'; H.packetData(0x017, chat(3, 'Someone', 'hello')); H.print('another sound chosen:', heard())

-- the command opens the settings, there being no window
local begun = H.calls.Begin or 0
H.print('/chime kept from the game', H.command('/chime')); H.frames(2)
H.print('settings drawn', (H.calls.Begin or 0) > begun, '| checkboxes', (H.calls.Checkbox or 0) > 8, '| sliders', H.calls.SliderInt, '| combos', (H.calls.BeginCombo or 0) > 0)
H.ret.Button = { true }; H.frames(1); H.ret.Button = { false }; H.print('every Test button:', #H.sounds, 'sounds')
H.command('/chime'); begun = H.calls.Begin; H.frames(2); H.print('/chime closes them', H.calls.Begin == begun)
H.unload(); H.print('unload ran; saves', H.saves() > 0)
