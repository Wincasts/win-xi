local custom, types, format = require('custom'), require('name_types'), require('format')
local o = {}; custom.Defaults(o)
o.fontSize[1], o.minSize[1] = 32, 9
o.showHealthBar[1], o.healthBarWidth[1], o.healthBarHeight[1] = true, 88, 8
o.monsterFormat[1] = '[aggro] Lv [level]. [name]'
o.showMobLevel[1], o.showAggroIcons[1] = false, false
o.showMobLetter[1], o.doubleMobLetters[1] = true, true
custom.Settle(o)
assert(o.fontSize[1] == 32 and o.minSize[1] == 9)
for _, key in ipairs(types.List) do assert(not o[key].fontSize and not o[key].minSize) end
assert(o.playerNames.showHealthBar[1] and o.enemyNames.showHealthBar[1] and not o.npcNames.showHealthBar[1],
    'old bars migrate to players/enemies without newly enabling NPC bars')
for _, key in ipairs(types.List) do
    assert(o[key].healthBarWidth[1] == 88 and o[key].healthBarHeight[1] == 8)
end
assert(format.Compile(o.monsterFormat[1]).level and format.Compile(o.monsterFormat[1]).aggro,
    'tokens in the string remain authoritative even when old toggles were false')
assert(format.Compile(o.monsterFormat[1]).doubleLetters, 'old automatic double letters migrate into a token')
o.playerNames.fontSize, o.playerNames.healthBarWidth[1] = { 24 }, 100
o.enemyNames.fontSize, o.enemyNames.healthBarHeight[1] = { 40 }, 12
o.npcNames.showHealthBar[1] = true
o.monsterFormat[1] = '[name]'
custom.Settle(o)
assert(not o.playerNames.fontSize and not o.enemyNames.fontSize and o.fontSize[1] == 32,
    'obsolete per-type sizes are removed without overwriting General settings')
assert(o.playerNames.healthBarWidth[1] == 100 and o.enemyNames.healthBarHeight[1] == 12 and o.npcNames.showHealthBar[1])
assert(o.monsterFormat[1] == '[name]', 'migration must not append letters again after token removal')
assert(types.Maximum(o) == 32)
o.minSize[1], o.fontSize[1] = 99, 12
o.enemyNames.healthBarWidth[1] = 999
o.npcNames.healthBarHeight[1] = -5
custom.Settle(o)
assert(o.minSize[1] == 12 and o.fontSize[1] == 12
    and o.enemyNames.healthBarWidth[1] == 300 and o.npcNames.healthBarHeight[1] == 3)
o.fontSize[1], o.minSize[1] = 0/0, 'invalid'; custom.Settle(o)
assert(o.fontSize[1] == 15 and o.minSize[1] == 10, 'malformed shared sizes recover safely')
-- Consolidation runs once; preserve legacy archives but never let them drive live bars again.
for _, source in ipairs({ 'enemyNames', 'playerNames', 'npcNames' }) do
    local shared = {}; custom.Defaults(shared); shared.nameTypesVersion = 1
    shared[source].showHealthBar[1] = true
    shared[source].healthBarWidth[1], shared[source].healthBarHeight[1] = 133, 11
    custom.Settle(shared)
    assert(shared.showHealthBar[1] and shared.healthBarWidth[1] == 133 and shared.healthBarHeight[1] == 11)
    shared.showHealthBar[1], shared.healthBarWidth[1] = false, 99
    shared[source].healthBarWidth[1] = 222
    custom.Settle(shared)
    assert(not shared.showHealthBar[1] and shared.healthBarWidth[1] == 99, 'migration must not repeat')
end
local priority = {}; custom.Defaults(priority); priority.nameTypesVersion = 1
priority.playerNames.showHealthBar[1], priority.enemyNames.showHealthBar[1] = true, true
priority.playerNames.healthBarWidth[1], priority.enemyNames.healthBarWidth[1] = 88, 144
custom.Settle(priority); assert(priority.healthBarWidth[1] == 144, 'enabled enemy dimensions have first migration priority')
assert(not priority.healthBarsCombatOnly[1], 'combat-only starts off')
local alias = {}; custom.Defaults(alias)
alias.monsterFormat[1] = '[name][letter:yellow]'
alias.showMobLetter[1], alias.doubleMobLetters[1] = true, true
custom.Settle(alias)
local part = format.Compile(alias.monsterFormat[1])[2]
assert(part.kind == 'letter' and part.type == 'double' and part.color == 0xFFFFE040,
    'legacy letter colour must survive migration into plural/type syntax')
assert(format.Compile('[letters: type=double]')[1].type == 'double')
assert(format.Compile('[letters: type=single]')[1].kind == 'letter')
assert(format.Compile('[letters: type=bad]')[1].kind == 'text')
assert(format.Compile('[name: type=double]')[1].kind == 'text')
H.print('name types: shared General sizes, obsolete overrides removed, independent bars, bounds and letter-token migration', true)
