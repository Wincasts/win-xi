local format, fields, rules = require('format'), require('mob_fields'), require('block_rules')
local readable, levels, builder = require('mob_readable'), require('levels'), require('builder')
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
rules.Set(nm, 'nm', false); assert(not nm.when and rules.Visible(nm, ctx))
rules.Set(nm, 'target', true); assert(nm.when == 'target')

levels.Set({ Names = { ['Real Mob'] = mob }, Indices = { [300] = { Name='Variant', Family='Crab', MinLevel=20, MaxLevel=20 } } })
local list = levels.PreviewMobs()
assert(#list == 2 and levels.PreviewMobs() == list, 'zone preview list is cached')
local o, original = H.options(), H.options().monsterFormat[1]
local d = builder.Load(o)
local preview = builder.Preview(d)
assert(preview.monster == mob and preview.words == 'Real Mob' and preview.level == '11')
d.preview.checked[1], d.preview.target[1], d.preview.distance[1], d.preview.distant[1] = false, false, 35, true
preview = builder.Preview(d)
assert(not preview.found and preview.level == '10-12' and not preview.ruleTarget and preview.ruleDistance == 35)
d.preview.choice = 'Indices:300'; preview = builder.Preview(d)
assert(preview.monster.Family == 'Crab' and preview.words == 'Variant')
assert(o.monsterFormat[1] == original, 'preview controls never alter live settings')
assert(builder.Insert(d, 'mob', nil, nil, 'check', nil, 'job') and d.checkParts[#d.checkParts].display == 'names')
local imgui = require('imgui')
d.preview.choice = 'Names:Real Mob'
imgui.BeginCombo = function(id) return id == 'Preview mob##builder.previewMob' or id == 'Database values##builder.display' end
imgui.Selectable = function(id) return id == 'Variant [index 300]##builder.preview.Indices:300' or id == 'both##builder.display.both' end
imgui.Checkbox = function(id, value)
    if id == 'Targeted##builder.previewTarget' then value[1] = false; return true end
    if id == 'Target only##builder.when.target' or id == 'Limit distance##builder.withinEnabled' then value[1] = true; return true end
    return false
end
imgui.SliderInt = function(id, value) if id == 'Within (y)##builder.within' then value[1] = 8; return true end; return false end
builder.Draw(o)
local selected = d.checkParts[d.selected]
assert(d.preview.choice == 'Indices:300' and not d.preview.target[1], 'preview selector/state controls work through the UI')
assert(selected.display == 'both' and selected.when == 'target' and selected.within == 8, 'inspector exposes readable values and conditions')
assert(o.monsterFormat[1] == original and not rules.Visible(selected, builder.Preview(d)), 'UI edits stay in the draft and affect preview visibility')
levels.Set({ Names = { ['New Zone'] = { Name='New Zone', Job=2 } }, Indices = {} })
preview = builder.Preview(d)
assert(preview.words == 'New Zone', 'zone change drops stale preview selection/data')
d.preview.choice = 'sample'; assert(builder.Preview(d).words == 'Goblin Butcher')
levels.Set(nil)
assert(#levels.PreviewMobs() == 0)
H.print('name extensions: cached resource names, verified immunity masks, raw compatibility, conditional blocks, real-zone variants and isolated preview state', true)
