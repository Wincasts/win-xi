package.path = 'addons/parse/?.lua;tests/fixtures/?.lua;' .. package.path
local packet = require('parse_packet')
local classify = require('parse_classify')
local core = require('parse_core')
local session = require('parse_session')
local capture = require('parse_capture')
local fixture = require('parse_packets')
local checks = 0
local function check(name, value) assert(value, name); checks = checks + 1; print(name .. '\ttrue') end
local function near(a, b) return a and math.abs(a - b) < 0.00001 end
local function info(id, name, kind, owner)
    return { id = id, key = '1:' .. id, name = name, kind = kind,
        owner_id = owner, owner_key = owner and '1:' .. owner, owner_name = owner and 'Alexanderson' }
end
local actors = {
    [1] = info(1, 'Alexanderson', 'me'), [2] = info(2, 'Alexanderson', 'party'),
    [3] = info(3, 'AlexanderOther', 'party'), [4] = info(4, 'Crab', 'pet', 1),
    [100] = info(100, 'Crab', 'mob'), [101] = info(101, 'Crab', 'mob'),
}
local function resolve(id) return actors[id] end
local data = fixture.Packet(0xFEDCBA98, 3, 0xABCDEF01, {
    { id = 0xF1234567, results = {
        { reaction = 4, kind = 3, animation = 4095, effect = 31, scale = 31, value = 131071, message = 1023, modifier = 2147483647,
            additional = { value = 123456, message = 768, animation = 63, effect = 15 },
            reactive = { value = 16383, message = 536, animation = 63, effect = 15 } },
        { message = 15, value = 0 },
    } },
    { id = 2, results = { { message = 67, value = 345 } } },
})
local decoded = assert(packet.Decode(data))
check('unsigned actor and ability IDs', decoded.actor == 0xFEDCBA98 and decoded.ability == 0xABCDEF01)
local r = decoded.targets[1].results[1]
check('packed fields and optional effects', r.reaction == 4 and r.kind == 3 and r.animation == 4095 and r.value == 131071
    and r.message == 1023 and r.modifier == 2147483647 and r.additional.value == 123456 and r.reactive.value == 16383)
check('variable offsets across results and targets', decoded.targets[1].results[2].message == 15 and decoded.targets[2].results[1].value == 345)
for cut = 1, math.floor((#data - 4) / 2) do
    local ok = packet.Decode(data:sub(1, cut))
    assert(not ok, 'truncated input accepted at ' .. cut)
end
check('truncated and oversized packets rejected', not packet.Decode('') and not packet.Decode(string.rep('\0', 513)))
local empty = assert(packet.Decode(fixture.Packet(1, 1, 0, {})))
check('zero-target packets safe', #empty.targets == 0)
local s = session.New()
local function feed(actor, c, message, damage, now, target)
    return s:Process(fixture.Single(actor, c, message, damage, target), now, resolve)
end
feed(1, 1, 1, 100, 10)
feed(1, 1, 67, 150, 11)
feed(1, 1, 15, 0, 12)
feed(1, 1, 31, 3, 13)
feed(1, 2, 354, 0, 14)
feed(2, 1, 1, 30, 15)
feed(3, 1, 1, 40, 16)
feed(4, 1, 1, 50, 17)
local shot = s.core:Snapshot(20)
check('same and long names never merge actors', #shot.rows == 4 and shot.total == 370)
local melee = shot.rows[1].categories.melee
check('melee successes, misses, crits and excluded outcomes', melee.hits == 2 and melee.misses == 1 and melee.criticals == 1 and melee.excluded == 1 and melee.damage == 250)
check('observed hit rate and meaningful zero', near(core.Rate(melee), 200/3) and core.Rate(shot.rows[1].categories.ranged) == 0)
check('no trial is distinct from zero', core.Rate({ hits = 0, misses = 0 }) == nil)
check('shared encounter duration and DPS', shot.duration == 10 and shot.rows[1].dps == 25)
s:Process(fixture.Packet(1, 3, 42, { { id = 100, results = { { message = 185, value = 1000,
    additional = { message = 288, value = 500 } } } } }), 21, resolve)
local with = s.core:Snapshot(22, { combinePets = true })
local without = s.core:Snapshot(22, { combinePets = true, includeSkillchains = false })
check('pets and skillchains grouped reversibly', #with.rows == 3 and with.rows[1].damage == 1800 and without.rows[1].damage == 1300)
check('skillchains remain attributed to exact closing actor', with.rows[1].categories.skillchain.damage == 500 and #s.core:Snapshot(22).rows == 4)
s:Process(fixture.Packet(1, 4, 42, {
    { id = 100, results = { { message = 2, value = 20 } } },
    { id = 101, results = { { message = 264, value = 35 } } },
}), 23, resolve)
local filtered = s.core:Snapshot(24, { target = '1:101' })
check('AoE counts each target without leaking previous category', filtered.total == 35 and filtered.rows[1].categories.spell.damage == 35)
feed(1, 8, 3, 9999, 25)
feed(1, 4, 7, 9999, 25)
feed(1, 4, 999, 9999, 25)
check('starts and healing ignored; unknown never guessed as damage', s.core.unknown['4:base:999'] == 1 and s.core:Snapshot(25).total == 1925)
local events = classify.Events(assert(packet.Decode(fixture.Packet(100, 1, 0, { { id = 1, results = {
    { message = 33, value = 20 },
    { message = 0, reactive = { message = 33, value = 30 } },
    { message = 1, value = 500, reactive = { message = 44, value = 40 } },
    { message = 1, value = 500, reactive = { message = 535, value = 2 } },
    { message = 1, value = 500, reactive = { message = 536, value = 50 } },
} } }))), resolve)
local counterCore = core.New(); counterCore:Record(events, {}, 0)
local defense = counterCore:Snapshot(1)
check('counter and spikes reverse actor/target; no incoming damage counted', defense.total == 140 and #defense.rows == 1
    and defense.rows[1].categories.counter.damage == 50 and defense.rows[1].categories.retaliation.damage == 50)
s:Pause(30)
feed(1, 1, 1, 9999, 40)
check('paused recording and clock frozen', s.core:Duration(100) == 20 and s.core:Snapshot(100).total == 1925)
s:Resume(100)
check('resume excludes pause duration', s.core:Duration(110) == 30)
s:Zone(110)
check('zoning freezes encounter and advances identity scope', not s.core.running and s.epoch == 2 and s.core:Duration(200) == 30)
s:Reset(201)
check('reset waits for first event rather than counting idle time', s.core:Duration(300) == 0 and s.core:Snapshot(300).total == 0)
feed(1, 1, 1, 1, 301)
for i = 1, 500 do feed(1, 1, 1, 1, 301 + i) end
check('diagnostic event history bounded', #s.core.history == 128 and s.core.event_count == 501)
local dedupe = require('parse_dedupe').New()
dedupe.Boundary()
check('identical legitimate results in same chunk retained', dedupe.Accept('a') and dedupe.Accept('a'))
dedupe.Boundary()
check('retransmissions preserve multiplicity', not dedupe.Accept('a') and not dedupe.Accept('a') and dedupe.Accept('a'))
dedupe.Clear()
check('dedupe reset forgets preceding chunks', dedupe.Accept('a'))
local text = {}
local file = { write = function(self, value) text[#text + 1] = value; return self end,
    flush = function() return true end, close = function() end }
local live = session.New(); live:StartCapture(file, 0)
actors[1].name = 'An actor, with; delimiters\nand a tab\t'
live:Process(fixture.Single(1, 1, 1, 200), 1, resolve)
live:Pause(4); live:Resume(10)
live:Process(fixture.Single(1, 1, 15, 0), 11, resolve)
live:Pause(12); live:CloseCapture()
local replay = session.New()
for line in table.concat(text):gmatch('[^\n]+') do
    if line ~= capture.Header:gsub('\n$', '') then assert(replay:Replay(assert(capture.Read(line)))) end
end
local original, replayed = live.core:Snapshot(20), replay.core:Snapshot(20)
check('capture replay exact totals, rates, names and pause timing', original.total == replayed.total and original.duration == replayed.duration
    and replayed.rows[1].name == actors[1].name and core.Rate(replayed.rows[1].categories.melee) == 50)
check('capture rejects executable and malformed input', not capture.Read('return os.execute("bad")') and not capture.Read('D\t1\tzz\t'))
live:Resume(13)
check('malformed live packets diagnosed without recording', not live:Process('', 13, resolve) and live.diagnostics.malformed == 1)
local failed = session.New()
failed:StartCapture({ write = function() return nil, 'disk full' end, close = function() end }, 0)
check('capture write failure releases file and preserves reason', failed.file == nil and failed.error == 'disk full')
local golden = session.New()
local goldenFile = assert(io.open('tests/fixtures/parse_capture.txt', 'rb'))
assert(goldenFile:read('*l') == 'winxi-parse\t1')
for line in goldenFile:lines() do assert(golden:Replay(assert(capture.Read(line)))) end
goldenFile:close()
check('fixed wire/capture fixture has known accounting', golden.core:Snapshot(100).total == 100 and golden.core:Duration(100) == 10)
local metadata = {
    [5] = { id = 100, name = 'Same name', flags = 0x10 },
    [6] = { id = 200, name = 'Owner' },
    [7] = { id = 201, name = 'Trust' },
    [8] = { id = 202, name = 'Alliance' },
    [9] = { id = 203, name = 'Same name', flags = 0x10 },
}
local entityManager = {
    GetServerId = function(_, index) assert(index ~= 0, 'entity zero accessed'); return metadata[index] and metadata[index].id or 0 end,
    GetName = function(_, index) return metadata[index].name end,
    GetSpawnFlags = function(_, index) return metadata[index].flags or 0 end,
    GetTrustOwnerTargetIndex = function(_, index) return index == 7 and 6 or 0 end,
    GetPetTargetIndex = function(_, index) return index == 6 and 9 or 0 end,
    GetFellowTargetIndex = function() return 0 end,
}
local members = { [0] = 6, [1] = 7, [6] = 8 }
local party = {
    GetMemberIsActive = function(_, index) return members[index] and 1 or 0 end,
    GetMemberTargetIndex = function(_, index) return members[index] end,
    GetMemberServerId = function(_, index) return metadata[members[index]].id end,
    GetMemberName = function(_, index) return metadata[members[index]].name end,
}
local memory = { GetEntity = function() return entityManager end, GetParty = function() return party end }
local identify = require('parse_identity').Resolver(memory, 7)
check('fallback lookup verifies server IDs without entity-zero fallback', identify(100).kind == 'mob' and identify(999).kind == 'other')
check('roster distinguishes player, trust and alliance', identify(200).kind == 'me' and identify(201).kind == 'trust' and identify(202).kind == 'alliance')
check('pet ownership takes precedence over monster spawn flags', identify(203).kind == 'pet' and identify(203).owner_key == '7:200')
local active = party.GetMemberIsActive
party.GetMemberIsActive = function() return 0 end
local solo = require('parse_identity').Resolver(memory, 7)
check('solo player and pet resolve without party-active flag', solo(200).kind == 'me'
    and solo(203).kind == 'pet' and solo(203).owner_key == '7:200' and solo(201).kind == 'other')
local soloSession = session.New()
assert(soloSession:Process(fixture.Single(200, 1, 1, 123, 100), 1, solo))
check('solo damage reaches accounting without party-active flag', soloSession.core:Snapshot(2).total == 123)
party.GetMemberIsActive = active
local nextZone = require('parse_identity').Resolver(memory, 8)
check('entity keys scope server IDs to zone epochs', nextZone(203).key ~= identify(203).key)
local endCaptureText = {}
local endCapture = session.New()
endCapture:StartCapture({ write = function(self, value) endCaptureText[#endCaptureText + 1] = value; return self end,
    flush = function() return true end, close = function() end }, 0)
endCapture:Process(fixture.Single(1, 1, 1, 10), 1, resolve)
endCapture:EndCapture(3)
check('capture off freezes replay without pausing live encounter', endCapture.core.running and endCapture.file == nil and endCaptureText[#endCaptureText] == capture.Control('S', 3))
local sources = session.New()
for _, case in ipairs({ {2,352,'ranged'}, {2,353,'ranged'}, {3,185,'ws'}, {4,2,'spell'},
    {4,252,'burst'}, {6,110,'ability'}, {13,185,'pet_ability'} }) do
    assert(sources:Process(fixture.Single(1, case[1], case[2], 10), 1, resolve))
    assert(sources.core:Snapshot(2).rows[1].categories[case[3]].damage >= 10)
end
check('explicit direct damage categories covered', sources.core:Snapshot(2).total == 70)
local proc = session.New()
proc:Process(fixture.Packet(1, 1, 0, { { id = 100, results = {
    { message = 1, value = 0, additional = { message = 163, value = 10 } },
    { message = 67, value = 20, additional = { message = 161, value = 20 } },
} } }), 1, resolve)
check('additional damage counted, drain not double counted, zero damage still a hit', proc.core:Snapshot(2).total == 30
    and proc.core:Snapshot(2).rows[1].categories.melee.hits == 2 and proc.core.unknown['1:additional:161'] == 1)
local namespaces = session.New()
namespaces:Process(fixture.Single(1, 3, 747, 10), 1, resolve)
namespaces:Process(fixture.Single(1, 4, 252, 20), 1, resolve)
local abilityBuckets = namespaces.core:Snapshot(2).rows[1].abilities
check('same numeric spell/WS ID does not merge ability buckets', abilityBuckets['burst:3:42'].damage == 10 and abilityBuckets['burst:4:42'].damage == 20)
local partial = fixture.Packet(1, 4, 42, { { id = 100, results = { { message = 2, value = 300 } } },
    { id = 101, results = { { message = 2, value = 400 } } } })
local atomic = session.New()
check('malformed multi-target packet cannot partially update totals', not atomic:Process(partial:sub(1, #partial - 8), 1, resolve)
    and atomic.core:Snapshot(2).total == 0 and atomic.diagnostics.malformed == 1)
local preview = require('parse_preview')
local dummy = preview.New(18)
local combined = dummy:Snapshot(preview.Duration, { combinePets = true })
check('preview contains 18 distinct people with plausible damage and rates', #combined.rows == 18 and combined.total > 0
    and combined.duration == 180 and core.Rate(combined.rows[1].categories.melee) > 0)
check('preview exercises reversible pet and skillchain options', #dummy:Snapshot(180).rows == 24
    and dummy:Snapshot(180, { combinePets = true, includeSkillchains = false }).total < combined.total)
check('preview can show a smaller party without touching another model', #preview.New(6):Snapshot(180, { combinePets = true }).rows == 6
    and golden.core:Snapshot(100).total == 100)
local columns = require('parse_columns')
local columnOptions = { columnOrder = { 'dps', 'gone', 'dps', 'actor' }, columnShown = { dps = false, gone = true } }
columns.Normalize(columnOptions)
check('column settings normalize unknown and duplicate entries without losing choices', table.concat(columnOptions.columnOrder, ',') == 'dps,actor,damage,share,melee,ranged,magic,ws_count,ws_accuracy,ws_unknown,magic_accuracy,magic_resists'
    and not columnOptions.columnShown.dps and columnOptions.columnShown.gone == nil)
check('column selection follows saved order', table.concat(columns.Visible(columnOptions), ',') == 'actor,damage,share,melee,ranged')
check('column moves respect boundaries', not columns.Move(columnOptions, 1, -1) and not columns.Move(columnOptions, #columnOptions.columnOrder, 1)
    and columns.Move(columnOptions, 2, -1) and columnOptions.columnOrder[1] == 'actor')
check('column layouts preserve original width slot and isolate alternate layouts', columns.TableId({ 'actor', 'damage', 'share', 'dps', 'melee', 'ranged' }) == '##parse.results'
    and columns.TableId({ 'damage', 'actor' }) ~= columns.TableId({ 'actor', 'damage' }))
check('column formatting preserves real zero and unavailable values', columns.Value('damage', { damage = 0 }) == '0'
    and columns.Value('dps', {}) == '--' and columns.Value('share', { share = 0 }) == '0.0%')
for key in pairs(columnOptions.columnShown) do columnOptions.columnShown[key] = false end
columns.Normalize(columnOptions)
check('all hidden columns remain a valid saved choice', #columns.Visible(columnOptions) == 0)
local oldColumns = { columnOrder = { 'damage', 'actor', 'share', 'dps', 'melee', 'ranged' }, columnShown = { share = false } }
columns.Normalize(oldColumns)
check('magic column added to old settings without changing visibility or order', oldColumns.columnOrder[1] == 'damage'
    and oldColumns.columnOrder[7] == 'magic' and not oldColumns.columnShown.magic and not oldColumns.columnShown.share)
check('magic damage combines spells and bursts without counting WS or skillchains', columns.Value('magic', { categories = {
    spell = { damage = 120 }, burst = { damage = 80 }, ws = { damage = 900 }, skillchain = { damage = 400 },
} }) == '200')
check('magic damage supports absent categories and zero', columns.Value('magic', { categories = {} }) == '0'
    and columns.Value('magic', { categories = { spell = { damage = 23 } } }) == '23'
    and columns.Value('magic', { categories = { burst = { damage = 45 } } }) == '45')
oldColumns.columnShown.magic = true
columns.Normalize(oldColumns)
check('enabled magic column survives normalization', oldColumns.columnShown.magic)
local wsOnly = session.New()
wsOnly:Process(fixture.Single(1, 3, 185, 321), 1, resolve)
wsOnly:Process(fixture.Single(1, 3, 188, 0), 2, resolve)
local wsRow = wsOnly.core:Snapshot(3).rows[1]
check('WS counts are whole-result observations, not individual swings', wsRow.categories.ws.hits == 1
    and wsRow.categories.ws.misses == 1 and wsRow.categories.ws.damage == 321 and wsRow.categories.melee == nil)
print(('parse: %d checks passed'):format(checks))
