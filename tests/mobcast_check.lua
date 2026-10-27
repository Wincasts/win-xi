-- mobcast: loads, and says in its box what the enemies do and nothing else
local window = require('winxi.window')
local text = require('winxi.text')
local game = require('winxi.game')
local box = require('box')
local o = H.options()
-- Printed boolean checks must fail the process, not just leave a 'false' in the output.
local printCheck = H.print
H.print = function(label, ...)
    printCheck(label, ...)
    for i = 1, select('#', ...) do
        assert(select(i, ...) ~= false, label)
    end
end
H.print('settings: spells', o.showSpells[1], '| weaponskills', o.showSkills[1], '| abilities', o.showAbilities[1],
    '| targets', o.showTargets[1], '| only my target off', o.onlyTarget[1] == false, '| seconds', o.seconds[1], '| lines', o.maxLines[1], '| grows from', o.grow, '| newest', o.newest)

-- the game: the player, a party member, and some mobs, an NPC and a pet about
local me = { id = 0x1001, index = 0x400 }
local party = { GetMemberName = function(_, place) return place == 0 and 'Tester' or place == 1 and 'Friend' or '' end,
    GetMemberServerId = function(_, place) return place == 0 and me.id or place == 1 and 0x1002 or 0 end,
    GetMemberTargetIndex = function(_, place) return place == 0 and me.index or 0 end }
local targetIndex = 0
local memory = { GetParty = function() return party end,
    GetTarget = function() return { GetTargetIndex = function() return targetIndex end } end,
    GetEntity = function() return { } end,
    GetPlayer = function() return { GetLoginStatus = function() return 2 end } end }
local names = { [144] = 'Fire', [258] = 'Sheep Song', [512] = 'Mighty Strikes', [16] = 'Fast Blade' }
local resources = {
    GetSpellById = function(_, id) return names[id] and { Name = { names[id] } } or nil end,
    GetAbilityById = function(_, id) return names[id] and { Name = { names[id] } } or nil end,
    GetString = function(_, table, index) assert(table == 'monsters.abilities'); return names[index + 256] end,
}
local core = AshitaCore
AshitaCore = setmetatable({ GetMemoryManager = function() return memory end, GetResourceManager = function() return resources end }, { __index = core })
local entities = {
    [0x123] = { ServerId = 0x1066123, Name = 'Acro Bat', SpawnFlags = 0x10 },
    [0x124] = { ServerId = 0x1066124, Name = 'Akbaba', SpawnFlags = 0x10 },
    [0x125] = { ServerId = 0x1066125, Name = 'Guard', SpawnFlags = 0x02 },
    [0x700] = { ServerId = 0x1066700, Name = 'Carbuncle', SpawnFlags = 0x110 },
    [0x400] = { ServerId = me.id, Name = 'Tester', SpawnFlags = 0x01 },
}
function GetEntity(index) return entities[index] end

-- an action packet, packed a bit at a time as the game packs it: who acts, the kind of action, what
-- the action is, the first target, and its first result's number, message and animation
local function action(actor, category, what, target, number, message, results, animation)
    local bits = {}
    local function put(offset, length, value)
        for i = 0, length - 1 do bits[offset + i] = math.floor(value / 2 ^ i) % 2 end
    end
    put(40, 32, actor); put(72, 6, 1); put(82, 4, category); put(86, 32, what or 0)
    put(150, 32, target or 0); put(182, 4, results or 1); put(213, 17, number or 0); put(230, 10, message or 0)
    put(191, 12, animation or 0)
    local bytes = {}
    for index = 0, 40 do
        local byte = 0
        for i = 0, 7 do byte = byte + (bits[index * 8 + i] or 0) * 2 ^ i end
        bytes[#bytes + 1] = string.char(byte)
    end
    return table.concat(bytes)
end
local cast, castBroken, skillUse, skillBroken = 0x6B626163, 0x6B627073, 0x65746163, 0x65747073 -- cabk, spbk, cate, spte
local bat, akbaba, guard, carby = 0x1066123, 0x1066124, 0x1066125, 0x1066700

-- what the box says: every line drawn in a frame, with its colour's setting
local said, colors, drawn, style = {}, {}, 0, nil
window.Plain = function(name, open, flags, draw, options)
    assert(name == 'mobcast.box' and options.title == 'Mobcast')
    drawn, style = drawn + 1, options
    draw()
end
text.Outlined = function(words, color) said[#said + 1] = words; colors[#colors + 1] = color end
local function shown()
    for i = #said, 1, -1 do said[i] = nil; colors[i] = nil end
    H.frames(1)
    return table.concat(said, ' | ')
end
o.fadeInOut[1] = false
H.play(true); H.login(2); H.frames(3)
H.print('nothing happening: no window', shown() == '' and drawn == 0)

-- spells
H.packetData(0x028, action(bat, 8, cast, me.id, 144, 327))
H.print('a mob begins a spell on the player:', shown() == 'Acro Bat starts casting Fire on Tester.', colors[1] == o.spellColor)
H.packetData(0x028, action(bat, 4, 144, me.id, 144, 2))
H.print('the spell cast takes the place of its beginning:', shown() == 'Acro Bat casts Fire.')
H.wait(10); shown()
H.print('and goes after its time:', shown() == '')
H.packetData(0x028, action(bat, 8, cast, bat, 144, 3))
H.print('a spell on itself names no target:', shown() == 'Acro Bat starts casting Fire.')
H.packetData(0x028, action(bat, 8, castBroken, bat, 144, 0))
H.print('broken off, the line says so:', shown() == 'Acro Bat\'s casting is interrupted.')
H.wait(10); shown()
H.packetData(0x028, action(bat, 8, cast, 0x1002, 144, 0))
H.print('a spell the game says nothing of: nothing', shown() == '')
H.packetData(0x028, action(bat, 8, cast, me.id, 144, 327))
H.packetData(0x028, action(bat, 4, 144, me.id, 0, 84, 1, 508))
H.packetData(0x028, action(bat, 8, castBroken, bat, 144, 0, 1, 508))
H.print('paralyzed at the end of a spell, the line says so, and not interrupted after:',
    shown() == 'Acro Bat is paralyzed and stops casting Fire.')
H.packetData(0x028, action(bat, 8, castBroken, bat, 144, 0))
H.print('a later spell broken off is said again:', shown() == 'Acro Bat\'s casting is interrupted.')
H.wait(10); shown()
H.packetData(0x028, action(bat, 8, cast, me.id, 144, 327))
H.packetData(0x028, action(bat, 4, 144, me.id, 0, 106, 1, 508))
H.packetData(0x028, action(bat, 8, castBroken, bat, 144, 0, 1, 508))
H.print('intimidated, the same:', shown() == 'Acro Bat is intimidated and stops casting Fire.')
H.wait(10); shown()
H.packetData(0x028, action(bat, 4, 0, me.id, 0, 84, 1, 508))
H.print('an attack paralyzed: nothing, not Spell 0', shown() == '')
H.packetData(0x028, action(bat, 4, 0, me.id, 0, 78, 1, 508))
H.print('a move out of range: nothing', shown() == '')
H.packetData(0x028, action(bat, 4, 0, me.id, 0, 0))
H.print('a spell finished with no spell: nothing', shown() == '')
H.packetData(0x028, action(bat, 8, cast, 0x1002, 144, 327))
H.print('a party member as the target, by the party list:', shown() == 'Acro Bat starts casting Fire on Friend.')
H.packetData(0x028, action(bat, 8, cast, akbaba, 144, 327))
H.print('another mob as the target, by its id, in the place of the mob\'s last cast:', shown() == 'Acro Bat starts casting Fire on Akbaba.')
H.wait(10); shown()
H.packetData(0x028, action(bat, 8, cast, me.id, 999, 327))
H.print('a spell the game has no name for:', shown() == 'Acro Bat starts casting Spell 999 on Tester.')
H.wait(10); shown()

-- not enemies
H.packetData(0x028, action(me.id, 8, cast, bat, 144, 327))
H.packetData(0x028, action(guard, 8, cast, bat, 144, 327))
H.packetData(0x028, action(carby, 8, cast, bat, 144, 327))
H.packetData(0x028, action(0x1066999, 8, cast, bat, 144, 327))
H.print('a player, an NPC, a pet and an unknown: nothing', shown() == '')

-- weaponskills
H.packetData(0x028, action(bat, 7, skillUse, me.id, 258, 43))
H.print('a mob readies a weaponskill:', shown() == 'Acro Bat readies Sheep Song on Tester.', colors[1] == o.skillColor)
H.packetData(0x028, action(bat, 11, 258, me.id, 0, 185))
H.print('used, it takes the place of the readying:', shown() == 'Acro Bat uses Sheep Song.')
H.packetData(0x028, action(akbaba, 7, skillUse, bat, 258, 43))
H.packetData(0x028, action(akbaba, 7, skillBroken, akbaba, 0, 0, 0))
H.print('another mob\'s, broken off:', shown() == 'Acro Bat uses Sheep Song. | Akbaba is interrupted.')
H.wait(10); shown()
H.packetData(0x028, action(bat, 3, 16, me.id, 0, 185))
H.print('a weaponskill of the players\' own, done:', shown() == 'Acro Bat uses Fast Blade.')
H.packetData(0x028, action(bat, 7, skillUse, me.id, 258, 0))
H.print('readied with nothing said of it: no new line', shown() == 'Acro Bat uses Fast Blade.')
H.wait(10); shown()

-- abilities
H.packetData(0x028, action(bat, 6, 0, bat, 0, 100))
H.print('a mob uses an ability:', shown() == 'Acro Bat uses Mighty Strikes.', colors[1] == o.abilityColor)
H.packetData(0x028, action(bat, 6, 0, bat, 0, 100))
H.print('and again: said once', shown() == 'Acro Bat uses Mighty Strikes.')
H.packetData(0x028, action(bat, 6, 0, me.id, 0, 100))
H.print('on someone else:', shown() == 'Acro Bat uses Mighty Strikes. | Acro Bat uses Mighty Strikes on Tester.')
H.wait(10); shown()

-- the switches
o.showSpells[1] = false; H.packetData(0x028, action(bat, 8, cast, me.id, 144, 327))
o.showSkills[1] = false; H.packetData(0x028, action(bat, 7, skillUse, me.id, 258, 43))
o.showAbilities[1] = false; H.packetData(0x028, action(bat, 6, 0, me.id, 0, 100))
H.print('each kind switched off: nothing', shown() == '')
o.showSpells[1], o.showSkills[1], o.showAbilities[1] = true, true, true
o.showTargets[1] = false; H.packetData(0x028, action(bat, 8, cast, me.id, 144, 327))
H.print('targets off:', shown() == 'Acro Bat starts casting Fire.'); o.showTargets[1] = true
H.wait(10); shown()
o.onlyTarget[1] = true
H.packetData(0x028, action(bat, 8, cast, me.id, 144, 327))
H.print('only my target, with another targeted: nothing', shown() == '')
targetIndex = 0x123; H.packetData(0x028, action(bat, 8, cast, me.id, 144, 327))
H.print('and with it targeted:', shown() == 'Acro Bat starts casting Fire on Tester.')
o.onlyTarget[1] = false; targetIndex = 0
H.wait(10); shown()

-- the box
o.maxLines[1] = 2
for i = 1, 3 do H.packetData(0x028, action(bat, 6, 0, entities[0x122 + i] and entities[0x122 + i].ServerId or me.id, 0, 100)) end
H.print('no more lines than wanted, the oldest gone:', shown() == 'Acro Bat uses Mighty Strikes on Akbaba. | Acro Bat uses Mighty Strikes on Guard.')
o.maxLines[1] = 5
H.wait(10); shown()
o.seconds[1] = 2
H.packetData(0x028, action(bat, 6, 0, bat, 0, 100)); shown()
H.wait(1.5); H.print('within its time:', shown() == 'Acro Bat uses Mighty Strikes.')
H.wait(1); shown(); H.print('after it: gone', shown() == '')
o.seconds[1] = 6
H.command('/mobcast test')
H.print('/mobcast test says a line of each kind:', shown() == 'Mad Sheep readies Sheep Song. | Goblin Smithy starts casting Fire on Tester. | Orcish Fighter uses Mighty Strikes.',
    colors[1] == o.skillColor and colors[2] == o.spellColor and colors[3] == o.abilityColor)
H.print('the box is not locked, at the theme\'s size:', style.locked == nil and style.clickThrough == nil and style.fontSize == nil)
o.locked[1], o.fontSize[1] = true, 18; shown()
H.print('locked, the mouse goes through it, and the size is its own:', style.locked == true and style.clickThrough == true and style.fontSize == 18)
o.locked[1], o.fontSize[1] = false, 0
o.newest = 'Top'
H.print('the newest at the top: the order the other way about', shown() == 'Orcish Fighter uses Mighty Strikes. | Goblin Smithy starts casting Fire on Tester. | Mad Sheep readies Sheep Song.',
    colors[1] == o.abilityColor and colors[3] == o.skillColor)
H.packetData(0x028, action(bat, 6, 0, bat, 0, 100))
H.print('a new line goes in at the top:', shown():sub(1, 30) == 'Acro Bat uses Mighty Strikes. ')
o.newest = 'Bottom'
H.wait(10); shown()

-- the sample, with the settings open
H.command('/mobcast'); drawn = 0
H.print('the settings open, the sample is shown:', shown() == 'Mad Sheep readies Sheep Song. | Goblin Smithy starts casting Fire on Tester. | Orcish Fighter uses Mighty Strikes.', drawn == 1)

-- the settings window: described rows under their sections, the Settings tab and the Visibility tab
local widgets = require('winxi.widgets')
local imgui = require('imgui')
local rows, sections, beginRow, header = {}, {}, widgets.BeginRow, widgets.Header
widgets.BeginRow = function(name, sentence, spec)
    rows[#rows + 1] = name
    assert(type(sentence) == 'string' and sentence ~= '', name .. ' has no sentence')
    return beginRow(name, sentence, spec)
end
widgets.Header = function(name, first, collapsed)
    sections[#sections + 1] = name
    return header(name, first, collapsed)
end
local function laidOut(tab)
    for i = #rows, 1, -1 do rows[i] = nil end
    for i = #sections, 1, -1 do sections[i] = nil end
    H.tab(tab); H.frames(1)
    return table.concat(sections, ' | '), table.concat(rows, ' | ')
end
local settingsSections, settingsRows = laidOut(1)
H.print('the Settings tab: Window, Enemies and Lines,', settingsSections == 'Window | Enemies | Lines',
    'each setting a row:', settingsRows == 'Lock Window | Position | Grow From | Font Size | Show Spells | Show Weaponskills | Show Abilities | Show Targets | Only My Target | Duration | Max Lines | Newest Line | Spell Color | Weaponskill Color | Ability Color | Test')
local visibilitySections, visibilityRows = laidOut(2)
H.print('the Visibility tab, the addon\'s own: Fade In And Out and the hide rules', visibilitySections == 'Visibility',
    visibilityRows == 'Fade In And Out | Hide While Map Open | Hide While Chat Open | Hide While Loading | Hide During Events | Hide With Game Interface')
H.tab(1); H.frames(1)
widgets.BeginRow, widgets.Header = beginRow, header

-- the Position row moves the box there: the anchor forgotten, and imgui told
local moved = nil
local setWindowPos = imgui.SetWindowPos
rawset(imgui, 'SetWindowPos', function(name, pos) if name == 'mobcast.box' then moved = pos end end)
o.pos[1], o.pos[2] = 250, 350
box.Move(o)
H.print('the box put at the Position row\'s numbers:', moved == o.pos and moved[1] == 250)
rawset(imgui, 'SetWindowPos', setWindowPos)
H.packetData(0x028, action(bat, 6, 0, bat, 0, 100))
H.print('and a real line puts it away:', shown() == 'Acro Bat uses Mighty Strikes.')
H.wait(10); shown()
local isHidden = game.IsHidden
game.IsHidden = function(rules) assert(rules == o.hide); return true end
drawn = 0; H.print('hidden by its rules: not drawn', shown() == '' and drawn == 0)
game.IsHidden = isHidden
H.command('/mobcast'); drawn = 0
H.print('the settings closed: nothing to show', shown() == '' and drawn == 0)

-- the settings made good
o.seconds[1], o.maxLines[1], o.grow, o.newest, o.spellColor, o.pos = 99, 'x', 'Up', 'Middle', 'blue', nil
H.resettle(); o = H.options()
H.print('bad settings made good:', o.seconds[1] == 30, o.maxLines[1] == 5, o.grow == 'Left', o.newest == 'Bottom', o.spellColor[1] == 0.6, o.pos[1] == 100)

-- fading: with the fade on, the box lingers after its last line to fade out with
o.fadeInOut[1], o.seconds[1] = true, 1
H.packetData(0x028, action(bat, 6, 0, bat, 0, 100)); H.frames(33)
drawn = 0; H.frames(1)
H.print('fading out, the last line is still drawn:', drawn == 1, said[#said] == 'Acro Bat uses Mighty Strikes.')
H.frames(10); drawn = 0; H.frames(1)
H.print('and gone once faded:', drawn == 0)
H.print('mobcast: loads, spells, weaponskills, abilities, targets, enemies only, the switches, the box, the sample, hiding, fading', true)
