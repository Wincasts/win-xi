package.path = 'addons/name/?.lua;' .. package.path
local letters = require('mob_letters')
local indices = {}
for ordinal = 28, 1, -1 do indices[ordinal * 3] = { Name = 'Goblin' } end
indices[1] = { Name = 'Rabbit' }
letters.Set(indices)
assert(letters.Of(3, 'Goblin', 123) == 'a')
assert(letters.Of(78, 'Goblin', 123) == 'z')
assert(letters.Of(81, 'Goblin', 123) == 'a')
assert(letters.Of(84, 'Goblin', 123) == 'b')
assert(letters.Of(1, 'Rabbit', 123) == 'a', 'each name has its own sequence')
assert(letters.Of(6, 'Goblin', 123) == 'b', 'unseen lower slots still count')
-- A second user loads the same catalogue in a different order and encounters only
-- the last mob first. Their output must match, with no discovery-order dependence.
local other = dofile('addons/name/mob_letters.lua')
local reordered = { [1] = { Name = 'Rabbit' } }
for ordinal = 1, 28 do reordered[ordinal * 3] = { Name = 'Goblin' } end
other.Set(reordered)
for ordinal = 28, 1, -1 do
    local index = ordinal * 3
    assert(other.Of(index, 'Goblin', 456) == letters.Of(index, 'Goblin', 123))
end
assert(letters.Of(999, 'Goblin', 123) == '')
assert(letters.Of(3, 'Renamed Goblin', 123) == '')
assert(letters.Of(3, 'Goblin', 0) == '')
assert(letters.Of(3, 'Goblin', nil) == '')
assert(letters.Of(3, 'Goblin', 789) == 'a', 'respawn in the same slot keeps its letter')
-- Double letters: past z a name goes on to aa, and only then; the first 26 are as they were
assert(letters.Pairs() == 0, 'no double letters wanted while they are off')
assert(letters.Double(true) and not letters.Double(true), 'said to have changed only when it has')
assert(letters.Of(3, 'Goblin', 123) == 'a' and letters.Of(78, 'Goblin', 123) == 'z')
assert(letters.Of(81, 'Goblin', 123) == 'aa' and letters.Of(84, 'Goblin', 123) == 'ab')
assert(letters.Of(1, 'Rabbit', 123) == 'a' and letters.Pairs() == 2, 'as many as the longest name needs')
local many = {}
for index = 1, 26 + 676 + 2 do many[index] = 'Bee' end
letters.Set(many)
assert(letters.Of(27, 'Bee', 123) == 'aa' and letters.Of(52, 'Bee', 123) == 'az' and letters.Of(53, 'Bee', 123) == 'ba')
assert(letters.Of(702, 'Bee', 123) == 'zz' and letters.Of(703, 'Bee', 123) == 'aa' and letters.Pairs() == 676,
    'past zz the double letters begin again')
assert(letters.Double(false) and letters.Of(27, 'Bee', 123) == 'a' and letters.Pairs() == 0)
letters.Set(indices)
letters.Set({ [6] = { Name = 'Goblin' } })
assert(letters.Of(6, 'Goblin', 123) == 'a', 'zone/table switch rebuilds sequences')
assert(letters.Of(3, 'Goblin', 123) == '')
letters.Set(nil)
assert(letters.Of(6, 'Goblin', 123) == '')
-- Production loading must use the game's own list of the area's names, not sparse MobDB exceptions.
-- A stand-in for the area's file: the header the game's have, then a record for each slot
local function record(name, id)
    local function byte(shift) return string.char(math.floor(id / shift) % 256) end
    return name .. ('\0'):rep(28 - #name) .. byte(1) .. byte(0x100) .. byte(0x10000) .. byte(0x1000000)
end
local function slot(zone, index) return 0x1000000 + zone * 0x1000 + index end
local listed = { record('none', 0) }
for index = 6, 15 do listed[#listed + 1] = record('Wild Rabbit', slot(100, index)) end
listed[#listed + 1] = record('Forest Hare', slot(100, 60))
listed[#listed + 1] = record('A Name Of Twenty-Eight Bytes', slot(100, 61))
listed[#listed + 1] = record('', slot(100, 62))
listed[#listed + 1] = record('Another Area\'s', slot(101, 63))
local listPath = os.tmpname()
local listFile = assert(io.open(listPath, 'wb'))
listFile:write(table.concat(listed))
listFile:close()
local asked = {}
local events = {}
addon = { path = 'addons/name/' }
ashita = { fs = { exists = function(path)
    local file = io.open(path, 'r')
    if file then file:close(); return true end
    return false
end }, events = { register = function(_, name, callback) events[name] = callback end } }
AshitaCore = { GetMemoryManager = function() return { GetParty = function() return {
    GetMemberZone = function() return 100 end,
} end } end, GetResourceManager = function() return { GetFilePath = function(_, id)
    asked[#asked + 1] = id
    return id == 6820 and listPath or (id == 6821 and listPath .. '.missing' or '')
end } end }
local names = require('zone_names')
local read = assert(names.Read(100))
assert(asked[1] == 6820, 'an area\'s file is numbered from 6720')
assert(read[6] == 'Wild Rabbit' and read[60] == 'Forest Hare' and read[61] == 'A Name Of Twenty-Eight Bytes',
    'a name that fills its record has no end to find')
assert(read[62] == nil and read[63] == nil and read[0] == nil, 'no nameless slot, other area\'s slot or header')
local none, why = names.Read(101)
assert(none == nil and why:find('could not be read', 1, true), why)
none, why = names.Read(300)
assert(none == nil and asked[#asked] == 86491 + 44 and why:find('did not say', 1, true), 'areas past 255 are numbered from 86491')
assert(names.Read(0) == nil and names.Parse(record('Wild Rabbit', slot(101, 6)), 100) == nil)
local levels = require('levels')
local sparse = dofile('addons/name/data/100.lua')
assert(sparse.Indices[6] == nil and sparse.Indices[7] == nil,
    'regression fixture must be absent from the level exception table')
assert(levels.Letter(6, 'Wild Rabbit', 0x1064006) == 'a')
assert(levels.Letter(7, 'Wild Rabbit', 0x1064007) == 'b',
    'ordinary same-name mobs must draw letters despite having no Indices exception')
levels.Set(sparse, {})
assert(levels.Letter(60, 'Forest Hare', 0x106403c) == '', 'missing full roster must not rank sparse exceptions')
levels.Set(sparse, read)
assert(levels.Letter(7, 'Wild Rabbit', 0x1064007) == 'b')
-- A roster behind the server is noticed from the zone's own monsters, said once, and not mended.
local said = {}
local realPrint = print
print = function(text) said[#said + 1] = text end
local roster = { [3] = 'Goblin', [6] = 'Goblin' }
local id = slot
letters.Set(roster, 100)
assert(letters.Of(3, 'Goblin', id(100, 3)) == 'a' and letters.Problem() == nil)
assert(letters.Of(0x401, 'Goblin', 0x12345) == '' and letters.Problem() == nil, 'a charmed player is no spawn slot')
assert(letters.Of(12, 'Goblin', id(101, 12)) == '' and letters.Problem() == nil, 'another zone\'s monster is not evidence')
assert(letters.Of(0x701, 'Goblin', id(100, 0x701)) == '' and letters.Problem() ~= nil, 'a zone slot the roster lacks')
assert(#said == 1 and said[1]:find('"Goblin" in slot 1793 is not in the game\'s files', 1, true), said[1])
assert(letters.Of(6, 'Orc', id(100, 6)) == '' and letters.Of(6, 'Orc', id(100, 6)) == '')
assert(#said == 1, 'said once per zone')
assert(letters.Problem():find('and 1 more', 1, true), 'each slot counted once')
assert(letters.Of(3, 'Goblin', id(100, 3)) == 'a', 'letters are not renumbered by what was met')
letters.Set(roster, 100)
assert(letters.Problem() == nil, 'forgotten on zone entry')
assert(letters.Of(6, 'Orc', id(100, 6)) == '' and said[2]:find('slot 6 is "Orc", the game\'s files have "Goblin"', 1, true))
letters.Set(roster)
assert(letters.Of(6, 'Orc', id(100, 6)) == '' and letters.Problem() == nil, 'no zone given: nothing to check against')
letters.Set({}, 100)
assert(letters.Of(6, 'Orc', id(100, 6)) == '' and letters.Problem() == nil, 'no roster for the zone is not a stale one')
print = realPrint
levels.Set(sparse, many, 100)
local before = levels.Generation()
levels.DoubleLetters(true)
assert(levels.Generation() ~= before and levels.Letter(27, 'Bee', slot(100, 27)) == 'aa' and levels.LetterPairs() == 676,
    'what is written is looked for again when the setting changes')
before = levels.Generation()
levels.DoubleLetters(true)
assert(levels.Generation() == before, 'and not while it stays')
levels.DoubleLetters(false)
assert(levels.Letter(27, 'Bee', slot(100, 27)) == 'a')
levels.Set(sparse, read, 100)
assert(levels.Letter(7, 'Wild Rabbit', 0x1064007) == 'b' and levels.RosterProblem() == nil)
assert(levels.Letter(517, 'Bull', 0x1064205) == '' and levels.RosterProblem() ~= nil)
-- an area whose file cannot be read has no letters, and says why
struct = { unpack = function(_, data, at) return data:byte(at) + data:byte(at + 1) * 256 end }
events.name_levels_packet({ id = 0x00A, data = ('\0'):rep(0x30) .. string.char(101, 0) .. ('\0'):rep(0x100) })
assert(levels.Letter(6, 'Wild Rabbit', slot(101, 6)) == '' and levels.RosterProblem():find('could not be read', 1, true))
events.name_levels_packet({ id = 0x00A, data = ('\0'):rep(0x30) .. string.char(100, 0) .. ('\0'):rep(0x100) })
assert(levels.Letter(7, 'Wild Rabbit', slot(100, 7)) == 'b' and levels.RosterProblem() == nil)
os.remove(listPath)
print('name mob letters: independent clients/order, per-name rank, unseen slots, wrap, respawn, zone reset, double letters, the game\'s own list read and a differing one reported\ttrue')
