-- Monster Letters: a monster's spawn letter after its name in the target window, the one name writes
-- over it (winxi.mob_letters, from the area's list in the game's files, winxi.zone_names); none for a
-- player or an NPC, none with the setting off, the list read again in another area, and quiet about a
-- list that differs (name says that).
H.load()
local options = H.options()
options.party.enabled[1], options.pets.enabled[1], options.showConfig[1] = false, false, false
options.fade.Enabled = false
options.target.enabled[1], options.target.showMain[1] = true, true
options.target.showSub[1], options.target.showTot[1] = false, false
assert(options.target.monsterLetters[1] == true, 'letters on to begin with')
require('winxi.game').IsHidden = function() return false end

local zone = 100
local core = AshitaCore
local party = setmetatable({ GetMemberZone = function() return zone end }, { __index = core.GetMemoryManager():GetParty() })
local memory = setmetatable({ GetParty = function() return party end }, { __index = core.GetMemoryManager() })
AshitaCore = setmetatable({ GetMemoryManager = function() return memory end }, { __index = core })

-- the area's list: three Goblins and a Rabbit, and a merchant
local reads = { }
package.loaded['winxi.zone_names'] = { Read = function(area)
    reads[#reads + 1] = area
    if area == 100 then return { [5] = 'Goblin', [9] = 'Goblin', [7] = 'Goblin', [3] = 'Rabbit', [20] = 'Merchant' } end
    return { [5] = 'Crab' }
end }
local function Id(area, index) return 0x01000000 + area * 0x1000 + index end
local entities = {
    [9] = { Name = 'Goblin', SpawnFlags = 0x10, ServerId = Id(100, 9), Distance = 64, HPPercent = 80 },
    [3] = { Name = 'Rabbit', SpawnFlags = 0x10, ServerId = Id(100, 3), Distance = 64, HPPercent = 80 },
    [20] = { Name = 'Merchant', SpawnFlags = 0x02, ServerId = Id(100, 20), Distance = 64, HPPercent = 100 },
    [30] = { Name = 'Tester', SpawnFlags = 0x01, ServerId = 12345, Distance = 64, HPPercent = 100 },
}
GetEntity = function(index) return entities[index] end

local frames, letter = require('frames'), nil
local draw = frames.Draw
frames.Draw = function(lines, kind, ...) if kind == 'target' then letter = lines[1].letter end return draw(lines, kind, ...) end
local function Letter(index)
    require('target').Indexes = function() return index, 0, 0 end
    letter = 'unset'
    H.frames(1)
    return letter
end

assert(Letter(9) == 'C', 'the third Goblin of the area\'s list by index: C')
assert(Letter(3) == 'A', 'each name lettered on its own')
assert(#reads == 1, 'the area\'s list read once')
assert(Letter(20) == nil, 'an NPC has none')
assert(Letter(30) == nil, 'a player has none')
options.target.monsterLetters[1] = false
assert(Letter(9) == nil, 'setting off: none')
options.target.monsterLetters[1] = true
entities[9].Name = 'Hobgoblin'
assert(Letter(9) == nil, 'a name the list does not have there: none')
assert(require('winxi.mob_letters').Quiet == true, 'party leaves the report to name')
entities[9].Name = 'Goblin'
zone = 101
entities[5] = { Name = 'Crab', SpawnFlags = 0x10, ServerId = Id(101, 5), Distance = 64, HPPercent = 80 }
assert(Letter(5) == 'A' and reads[#reads] == 101, 'another area: its list read')
H.print('monster letters: name\'s spawn letter after a monster\'s name, none for others or with the setting off, read per area', true)
