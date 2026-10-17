package.path = 'addons/parse/?.lua;tests/fixtures/?.lua;' .. package.path
local ws = require('parse_ws')
local session = require('parse_session')
local core = require('parse_core')
local columns = require('parse_columns')
local fixture = require('parse_packets')
local capture = require('parse_capture')
local packet = require('parse_packet')
local count = 0
local function check(name, value) assert(value, name); count = count + 1; print(name .. '\ttrue') end
local function near(a,b) return a and math.abs(a-b) < 0.000001 end
local p = { base = 120, store = 0, attempts = 4 }
local hits, misses = ws.Solve(140, p, true)
check('TP base plus 10 per extra hit yields landed strikes and missing attempts', hits == 3 and misses == 1)
hits, misses = ws.Solve(30, p, true)
check('first hit miss is considered instead of assuming base TP', hits == 3 and misses == 1)
hits, misses = ws.Solve(0, p, false)
check('whole WS miss can yield all missed attempts', hits == 0 and misses == 4)
check('successful zero TP is not assumed to be a zero-hit WS', ws.Solve(0, p, true) == nil)
hits, misses = ws.Solve(165, { base = 120, store = 50, attempts = 4 }, true)
check('Store TP applies to extra hits', hits == 4 and misses == 0)
hits = ws.Solve(147, { base = 120, store = 37, attempts = 4 }, true)
check('extra TP rounding matches aggregate extra-hit formula', hits == 3)
check('ambiguous first-hit and extra-hit interpretations excluded', ws.Solve(20, { base = 20, store = 0, attempts = 4 }, true) == nil)
check('off-profile TP and retained TP excluded', ws.Solve(999, p, true) == nil and ws.Solve(1200, p, true) == nil)
check('malformed profile excluded', not ws.Valid({ base = 120, store = -1, attempts = 4 }) and not ws.Valid({ base = 120, store = 0, attempts = 9 }))
local actor = { id = 1, key = '1:1', name = 'Tester', kind = 'me' }
local target = { id = 100, key = '1:100', name = 'Crab', kind = 'mob' }
local function resolve(id) return id == 1 and actor or target end
local function context(safe, sig) return { id = 1, safe = safe ~= false, signature = sig or 'weapon', hp = 1000 } end
local start = { actor = 1, category = 7, targets = { { id = 100, results = { { value = 80 } } } } }
local finish = { actor = 1, category = 3, ability = 80, targets = { { id = 100, results = { {} } } } }
local event = { actor = actor, target = target, category = 'ws', ability = 80, damage = 500, outcome = 'hit' }
local results = {}
local tracker = ws.New(function(result) results[#results + 1] = result end)
local function begin(profile, ctx)
    tracker:Clear()
    tracker:Action(start, {}, 1, ctx or context(), { ['80'] = profile or p })
    tracker:Action(finish, { event }, 2, ctx or context(), { ['80'] = profile or p })
end
begin(); tracker:TP(1, 140, 1000, 2.1); tracker:Tick(2.3, context())
check('fresh TP waits for settling window', tracker.pending ~= nil and #results == 0)
tracker:Tick(2.6, context())
check('settled local WS inferred once', #results == 1 and results[1].hits == 3 and results[1].misses == 1)
tracker:Tick(3, context())
check('same observation cannot be counted twice', #results == 1)
begin(); tracker:TP(2, 140, 1000, 2.1)
check('other party TP cannot satisfy local pending WS', tracker.pending.tp == nil)
tracker:Tick(4.1, context())
check('missing update classified unknown after timeout', results[#results].reason == 'TP observation timeout' and results[#results].hits == nil)
begin(); tracker:TP(1, 140, 1000, 2)
check('same-time update excluded as stale', results[#results].reason == 'stale/late TP update')
begin(); tracker:TP(1, 140, 1000, 2.1); tracker:TP(1, 150, 1000, 2.2)
check('TP movement while waiting is contamination', results[#results].reason == 'TP changed during observation')
begin(); tracker:TP(1, 140, 950, 2.1)
check('HP movement excludes sample', results[#results].reason == 'HP changed')
begin(); tracker:Tick(2.1, context(true, 'swapped'))
check('equipment/context change excludes sample', results[#results].reason == 'context changed')
begin(); tracker:Death(100, 2.2)
check('killing blow does not infer misses for unexecuted strikes', results[#results].reason == 'death/killing blow')
begin(); tracker:Action({ actor = 100, category = 1, targets = { { id = 1 } } }, {}, 2.2, context(), {})
check('incoming action interrupts TP inference', results[#results].reason == 'intervening action')
begin(p, context(false))
check('unsafe pre-WS state excludes sample', results[#results].reason == 'unsafe or changed WS context')
tracker:Clear(); tracker:Action(finish, { event }, 2, context(), { ['80'] = p })
check('missing WS start excluded', results[#results].reason == 'missing/faded WS start')
tracker:Clear(); tracker:Action(finish, { event }, 2, context(), {})
check('no profile does not fall back to guessing', results[#results].reason == 'no calibrated profile')
begin(); tracker:Clear(); tracker:Tick(5, context())
check('reset clears in-flight inference', tracker.pending == nil)
local s = session.New()
s:Process(fixture.Packet(1, 3, 80, { { id = 100, results = { { message = 185, value = 500 } } },
    { id = 101, results = { { message = 264, value = 300 } } } }), 1, resolve)
local row = s.core:Snapshot(2).rows[1]
check('AoE WS counts one action but keeps both target damage results', row.categories.ws_count.count == 1 and row.categories.ws.count == 2 and row.damage == 800)
s:WSResult({ actor = actor, target = target, ability = 80, hits = 3, misses = 1, tp = 140, profile = p }, 2)
s:Process(fixture.Single(1, 1, 15, 0), 3, resolve)
row = s.core:Snapshot(4).rows[1]
check('inferred WS strikes included in melee rate exactly once', near(core.MeleeRate(row), 60) and row.categories.ws.hits == 2 and row.categories.melee.misses == 1)
check('WS hit rate is strike-based while WS count remains action-based', columns.Value('ws_accuracy', row) == '75.0%' and columns.Value('ws_count', row) == '1')
check('accuracy counters add no duplicate damage', row.damage == 800)
s:WSResult({ actor = actor, target = target, ability = 80, reason = 'no update' }, 4)
row = s.core:Snapshot(5).rows[1]
check('unknown WS observations excluded from accuracy', near(core.MeleeRate(row), 60) and columns.Value('ws_unknown', row) == '1')
local magic = session.New()
for i, message in ipairs({ 2, 252, 236, 85, 284, 653, 654, 655, 656, 75, 283, 7 }) do
    magic:Process(fixture.Single(1, 4, message, message == 2 and 100 or message == 252 and 200 or 9999), i, resolve)
end
row = magic.core:Snapshot(20).rows[1]
check('magic damage not inflated by resists, enfeebles, no-effect or healing', row.damage == 300)
check('magic accuracy uses recognized successes and explicit resist outcomes', row.categories.magic_accuracy.hits == 3 and row.categories.magic_accuracy.misses == 6
    and row.categories.magic_accuracy.excluded == 2 and near(core.Rate(row.categories.magic_accuracy), 100/3))
check('magic columns distinguish land percentage from resist count', columns.Value('magic_accuracy', row) == '33.3%' and columns.Value('magic_resists', row) == '6')
magic:Process(fixture.Single(1, 3, 197, 500), 21, resolve)
check('WS damage resistance does not become a spell resist', magic.core:Snapshot(22).rows[1].categories.magic_accuracy.misses == 6)
local allResist = session.New(); allResist:Process(fixture.Single(1, 4, 655, 0), 1, resolve)
check('zero magic land rate is meaningful', columns.Value('magic_accuracy', allResist.core:Snapshot(2).rows[1]) == '0.0%')
local texts = {}
local file = { write = function(self, text) texts[#texts+1] = text; return self end, flush = function() return true end, close = function() end }
local live = session.New(); live:StartCapture(file, 0)
live:Process(fixture.Packet(1, 3, 80, { { id = 100, results = { { message = 185, value = 500 } } } }), 1, resolve)
live:WSResult({ actor = actor, target = target, ability = 80, hits = 3, misses = 1, tp = 140, profile = p }, 2)
live:WSResult({ actor = actor, target = target, ability = 80, reason = 'missing TP' }, 3)
live:EndCapture(4)
local replay = session.New()
for line in table.concat(texts):gmatch('[^\n]+') do
    if line ~= capture.Header:gsub('\n$', '') then assert(replay:Replay(assert(capture.Read(line)))) end
end
row = replay.core:Snapshot(5).rows[1]
check('v2 capture replays WS inference and exclusions without live memory', row.damage == 500 and near(core.MeleeRate(row), 75)
    and row.categories.ws_unknown.count == 1 and replay.core:Duration(5) == 3)
replay.core:Resume(4.5)
local bad = capture.WS(5, { actor = actor, target = target, ability = 80, hits = 4, misses = 0, tp = 140, profile = p })
check('replay rejects TP inference inconsistent with recorded calibration', not replay:Replay(assert(capture.Read(bad:gsub('\n$', '')))))
local bytes = '\0\0\0\0' .. string.char(1,0,0,0,232,3,0,0,0,0,0,0,140,0,0,0)
local id, tp, hp = require('parse_ws_live').TP(bytes)
check('party TP packet reads unsigned server ID, HP and TP', id == 1 and tp == 140 and hp == 1000)
check('truncated TP update is safe', require('parse_ws_live').TP(bytes:sub(1, 19)) == nil)
check('first-hit miss cannot invent an additional attempted strike', ws.Solve(40, p, true) == nil
    and ws.Solve(10, { base = 120, store = 0, attempts = 1 }, true) == nil)
tracker:Clear(); tracker:Action(start, {}, 1, context(), { ['80'] = p }); tracker:Death(100, 1.9)
tracker:Action(finish, { event }, 2, context(), { ['80'] = p })
check('death message arriving before WS finish also excludes sample', results[#results].reason == 'death/killing blow')
local player = { GetMainJob = function() return 7 end, GetSubJob = function() return 3 end,
    GetIsZoning = function() return 0 end, GetStatusIcons = function() return {} end }
local sub, skill = false, 3
local memory = {
    GetParty = function() return { GetMemberServerId = function() return 1 end, GetMemberHP = function() return 1000 end } end,
    GetPlayer = function() return player end,
    GetInventory = function() return {
        GetEquippedItem = function(_, slot) return (slot == 0 or slot == 1 and sub) and { Index = 257 + slot } or nil end,
        GetContainerItem = function(_, bag, index) return { Id = index } end,
    } end,
}
local resources = { GetItemById = function() return { Type = 5, Skill = skill } end }
local liveContext = require('parse_ws_live').Context
check('single-weapon context can qualify', liveContext(memory, resources).safe)
sub = true; check('dual wield context is excluded', not liveContext(memory, resources).safe)
sub = false; skill = 1; check('H2H context is excluded', not liveContext(memory, resources).safe)
skill = 3; player.GetStatusIcons = function() return { 408 } end
check('TP-altering buff context is excluded', not liveContext(memory, resources).safe)
player.GetStatusIcons = function() return {} end; player.GetSubJob = function() return 19 end
check('Conserve TP trait job context is excluded', not liveContext(memory, resources).safe)
player.GetSubJob = nil
check('unknown context is unsafe rather than implicitly valid', not liveContext(memory, resources).safe)
print(('parse accuracy: %d checks passed'):format(count))
