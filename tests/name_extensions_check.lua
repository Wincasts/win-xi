local format, fields, rules = require('format'), require('mob_fields'), require('block_rules')
local readable, levels = require('mob_readable'), require('levels')
local calls = { item = 0, spell = 0 }
AshitaCore.GetResourceManager = function() return {
    GetItemById = function(_, id) calls.item = calls.item+1; return id == 505 and { Name = { 'Rabbit Hide\0extra' } } or nil end,
    GetSpellById = function(_, id) calls.spell = calls.spell+1; return id == 144 and { Name = { 'Fire' } } or nil end,
} end
readable.Clear()
local mob = { Name = 'Real Mob', Family = 'Rabbit', Job = 1, SubJob = 0, MinLevel = 10, MaxLevel = 12,
    Aggro = false, Notorious = false, Immunities = 0x4005, Drops = { 505, 999 }, Spells = {144, 999},
    Despoil = {}, Modifiers = { Fire = 1, Ice = 1.5 } }
local function value(field, mode)
    return fields.Value({ kind = 'mob', field = field, display = mode }, mob)
end
assert(value('drops') == 'Drops (IDs): 505, 999', 'existing formats remain raw')
assert(value('drops', 'names') == 'Drops: Rabbit Hide, Item #999')
assert(value('spells', 'both') == 'Spells: Fire (#144), Spell #999')
assert(value('job', 'names') == 'Job: WAR' and value('subjob', 'names') == 'Subjob: None')
assert(value('immunities', 'names') == 'Immunities: Sleep, Bind, Unknown 0x4000')
assert(value('immunities', 'both'):find('mask 16389', 1, true))
assert(value('despoil', 'names') == 'Despoil: none')
for i = 1, 20 do value('drops', 'names'); value('spells', 'both') end
assert(calls.item == 2 and calls.spell == 2, 'resource names/fallbacks are cached, with no item-to-spell fallback')
local p = format.Compile('[mob: field=drops, display=both, when=relevant+target+checked, within=20]')[1]
assert(p.display == 'both' and p.when == 'target+checked+relevant' and p.within == 20)
local round = format.Compile(format.Serialize({p}))[1]
assert(round.display == p.display and round.when == p.when and round.within == p.within)
local label = { kind = 'text', text = 'Lv [label] 100%, ', when = 'target+checked', within = 10, color = 0xFFFFE040 }
local encoded = format.Serialize({label})
local decoded = format.Compile(encoded)[1]
assert(decoded.text == label.text and decoded.when == label.when and decoded.within == 10 and decoded.color == label.color,
    'conditional literal labels round-trip punctuation, spaces, percent signs and case')
assert(format.Compile('[text]')[1].text == '[text]', 'legacy literal [text] stays literal')
for _, text in ipairs({ '[name: when=unknown]', '[name: when=target++nm]', '[name: when=+target]',
    '[name: when=target+]', '[name: display=names]', '[mob: field=job, display=bad]' }) do
    assert(format.Compile(text)[1].kind == 'text', 'malformed conditions/options remain literal')
end
assert(format.Compile('[name: within=999]')[1].within == 100)
local ctx = { monster = mob, ruleTarget = true, ruleChecked = true, ruleDistance = 12, words = 'Real Mob' }
assert(rules.Visible(p, ctx))
ctx.ruleTarget = false; assert(not rules.Visible(p, ctx)); ctx.ruleTarget = true
ctx.ruleChecked = false; assert(not rules.Visible(p, ctx)); ctx.ruleChecked = true
ctx.ruleDistance = 21; assert(not rules.Visible(p, ctx)); ctx.ruleDistance = nil; assert(not rules.Visible(p, ctx)); ctx.ruleDistance = 12
local nm = format.Compile('[name: when=nm]')[1]
assert(not rules.Visible(nm, ctx)); mob.Notorious = true; assert(rules.Visible(nm, ctx)); mob.Notorious = false
local relevant = format.Compile('[mob: field=notorious, when=relevant]')[1]
assert(not rules.Visible(relevant, ctx))
relevant.field = 'modifiers.fire'; assert(not rules.Visible(relevant, ctx))
relevant.field = 'modifiers.ice'; assert(rules.Visible(relevant, ctx))
relevant.field = 'despoil'; assert(not rules.Visible(relevant, ctx))
relevant.field = 'subjob'; assert(not rules.Visible(relevant, ctx))
relevant.field = 'missing'; assert(not rules.Visible(relevant, ctx))
nm.when = nil; assert(rules.Visible(nm, ctx))

levels.Set(nil)
H.print('name extensions: cached resource names, verified immunity masks, raw compatibility and conditional blocks', true)
