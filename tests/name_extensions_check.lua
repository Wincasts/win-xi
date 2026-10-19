-- name: a token's conditions, when= and within=, as format.lua reads and writes them and block_rules
-- judges them. Run via tests/harness.lua.
local format, rules = require('format'), require('block_rules')

local p = format.Compile('[level: when=relevant+target+checked, within=20, color=yellow, space=3]')[1]
assert(p.kind == 'level' and p.when == 'target+checked+relevant' and p.within == 20 and p.color == 0xFFFFE040 and p.space == 3,
    'conditions are read in any order and kept in one')
local round = format.Compile(format.Serialize({ p }))[1]
assert(round.when == p.when and round.within == p.within and round.color == p.color and round.space == p.space,
    'a token with conditions is written back as it was read')
assert(format.Compile('[name: when=always]')[1].when == nil, 'always is no condition')
assert(format.Compile('[text]')[1].kind == 'text' and format.Compile('[text]')[1].text == '[text]', '[text] is written as typed')
for _, text in ipairs({ '[name: when=unknown]', '[name: when=target++nm]', '[name: when=+target]',
    '[name: when=target+]', '[name: display=names]', '[mob: field=family]', '[difficulty]', '[text: value=%41]' }) do
    assert(format.Compile(text)[1].kind == 'text', 'malformed conditions, and the builder\'s own tokens, remain literal: ' .. text)
end
assert(format.Compile('[name: within=999]')[1].within == 100, 'within is kept to 100 yalms')
local line = format.Compile('[name: when=target] [letters: within=5]')
assert(line.rules and line.ruleDistance, 'a line with a condition says so, and one with within= wants the distance')
assert(not format.Compile('[name] [letters]').rules, 'a line without has no conditions to check')

local mob = { Name = 'Real Mob', Family = 'Rabbit', Aggro = false, Notorious = false }
local ctx = { monster = mob, ruleTarget = true, ruleChecked = true, ruleDistance = 12, words = 'Real Mob', level = '10-12', letter = 'a' }
assert(rules.Visible(p, ctx))
ctx.ruleTarget = false; assert(not rules.Visible(p, ctx)); ctx.ruleTarget = true
ctx.ruleChecked = false; assert(not rules.Visible(p, ctx)); ctx.ruleChecked = true
ctx.ruleDistance = 21; assert(not rules.Visible(p, ctx)); ctx.ruleDistance = nil; assert(not rules.Visible(p, ctx)); ctx.ruleDistance = 12
local nm = format.Compile('[name: when=nm]')[1]
assert(not rules.Visible(nm, ctx)); mob.Notorious = true; assert(rules.Visible(nm, ctx)); mob.Notorious = false
nm.when = nil; assert(rules.Visible(nm, ctx))
-- relevant: the token has something to write
local function relevant(text) return rules.Visible(format.Compile(text)[1], ctx) end
assert(relevant('[name: when=relevant]') and relevant('[level: when=relevant]') and relevant('[letters: when=relevant]')
    and relevant('[distance: when=relevant]') and relevant('[checked: when=relevant]') and relevant('[icons: when=relevant]'))
assert(not relevant('[aggro: when=relevant]'), 'a monster that is not aggressive has no sign')
mob.Aggro = true; assert(relevant('[aggro: when=relevant]'))
ctx.words, ctx.level, ctx.letter, ctx.ruleChecked = '', '', '', false
assert(not relevant('[name: when=relevant]') and not relevant('[level: when=relevant]') and not relevant('[letters: when=relevant]')
    and not relevant('[checked: when=relevant]'))
ctx.monster = nil
assert(not relevant('[aggro: when=relevant]') and not relevant('[letters: when=nm]'), 'a monster the tables lack is no notorious monster')

H.print('token conditions: read, written back, kept in range, judged by target, checked, nm, within and relevance', true)
