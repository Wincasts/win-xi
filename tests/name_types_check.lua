local custom, types, format = require('custom'), require('name_types'), require('format')
-- a file saved before the formats and the shared bars: switches for what the formats now say
local o = {}; custom.Defaults(o)
o.fontSize[1], o.minSize[1] = 32, 9
o.showHealthBar[1], o.healthBarWidth[1], o.healthBarHeight[1] = true, 88, 8
o.monsterFormat[1] = '[aggro] Lv [level]. [name]'
o.showMobLevel, o.showAggroIcons = { false }, { false }
o.showMobLetter, o.doubleMobLetters = { true }, { true }
custom.Settle(o)
assert(o.fontSize[1] == 32 and o.minSize[1] == 9)
assert(o.showHealthBar[1] and o.healthBarWidth[1] == 88 and o.healthBarHeight[1] == 8,
    'shared bars from before the types kept as they were')
for _, key in ipairs(types.List) do assert(o[key] == nil, 'no per-type table kept: ' .. key) end
assert(o.nameTypesVersion == nil and o.sharedHealthBarsVersion == 1)
assert(format.Compile(o.monsterFormat[1]).level and format.Compile(o.monsterFormat[1]).aggro,
    'tokens in the string remain authoritative even when old toggles were false')
assert(format.Compile(o.monsterFormat[1]).doubleLetters, 'old automatic double letters migrate into a token')
for _, key in ipairs({ 'showMobLevel', 'showAggroIcons', 'showMobLetter', 'doubleMobLetters', 'showIcons' }) do
    assert(o[key] == nil, 'an old switch is let go of once brought over: ' .. key)
end
o.monsterFormat[1] = '[name]'
custom.Settle(o)
assert(o.monsterFormat[1] == '[name]', 'migration must not append letters again after token removal')
o.minSize[1], o.fontSize[1] = 99, 12
custom.Settle(o)
assert(o.minSize[1] == 12 and o.fontSize[1] == 12)
o.fontSize[1], o.minSize[1] = 0/0, 'invalid'; custom.Settle(o)
assert(o.fontSize[1] == 15 and o.minSize[1] == 10, 'malformed shared sizes recover safely')
-- A file whose types had bars of their own (nameTypesVersion 1): the first type with bars on gives
-- the shared ones, once, its size made good; the tables are let go of
local function perType()
    local saved = {}; custom.Defaults(saved); saved.nameTypesVersion = 1
    for _, key in ipairs(types.List) do
        saved[key] = { showHealthBar = { false }, healthBarWidth = { 60 }, healthBarHeight = { 6 }, fontSize = { 24 } }
    end
    return saved
end
for _, source in ipairs({ 'enemyNames', 'playerNames', 'npcNames' }) do
    local shared = perType()
    shared[source].showHealthBar[1] = true
    shared[source].healthBarWidth[1], shared[source].healthBarHeight[1] = 133, 11
    custom.Settle(shared)
    assert(shared.showHealthBar[1] and shared.healthBarWidth[1] == 133 and shared.healthBarHeight[1] == 11)
    assert(shared[source] == nil and shared.sharedHealthBarsVersion == 1)
    shared.showHealthBar[1], shared.healthBarWidth[1] = false, 99
    custom.Settle(shared)
    assert(not shared.showHealthBar[1] and shared.healthBarWidth[1] == 99, 'migration must not repeat')
end
local priority = perType()
priority.playerNames.showHealthBar[1], priority.enemyNames.showHealthBar[1] = true, true
priority.playerNames.healthBarWidth[1], priority.enemyNames.healthBarWidth[1] = 88, 144
custom.Settle(priority); assert(priority.healthBarWidth[1] == 144, 'enabled enemy dimensions have first migration priority')
assert(not priority.healthBarsCombatOnly[1], 'combat-only starts off')
local none = perType()
none.enemyNames.healthBarWidth[1], none.enemyNames.healthBarHeight[1] = 999, -5
custom.Settle(none)
assert(not none.showHealthBar[1] and none.healthBarWidth[1] == 300 and none.healthBarHeight[1] == 3,
    'none on: the enemies\' size, made good')
local missing = {}; custom.Defaults(missing); missing.nameTypesVersion = 1
custom.Settle(missing)
assert(not missing.showHealthBar[1] and missing.healthBarWidth[1] == 60 and missing.healthBarHeight[1] == 6,
    'no tables at all: the sizes as they were by default')
local alias = {}; custom.Defaults(alias)
alias.monsterFormat[1] = '[name][letter:yellow]'
alias.showMobLetter, alias.doubleMobLetters = { true }, { true }
custom.Settle(alias)
local part = format.Compile(alias.monsterFormat[1])[2]
assert(part.kind == 'letter' and part.type == 'double' and part.color == 0xFFFFE040,
    'legacy letter colour must survive migration into plural/type syntax')
assert(format.Compile('[letters: type=double]')[1].type == 'double')
assert(format.Compile('[letters: type=single]')[1].kind == 'letter')
assert(format.Compile('[letters: type=bad]')[1].kind == 'text')
assert(format.Compile('[name: type=double]')[1].kind == 'text')
H.print('name types: shared General sizes, obsolete overrides removed, independent bars, bounds and letter-token migration', true)
