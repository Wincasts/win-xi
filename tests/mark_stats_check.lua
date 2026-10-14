package.path = 'addons/mark/?.lua;' .. package.path
local stats = require('stats')
local function check(label, ok) assert(ok, label); print(label, true) end
local db = stats.Prepare(nil)
local t = stats.New(db)
local targets = { { zone = 100, name = 'Jack', record = { indices = { 295, 296 }, placeholders = { { index = 294 } } } } }
local up, dead = { up = true }, { up = false }
t:Watch(100, targets)
t:Observe({ [294] = dead, [295] = dead }, 1)
check('initial corpses are not counted as kills', next(db.monsters) == nil)
t:Observe({ [294] = up }, 10)
t:Observe({ [294] = dead }, 20)
local row = db.monsters['100:Jack']
check('witnessed PH kill recorded', row.phKills == 1 and row.placeholders['294'] == 1)
t:Death(294, 21, true); t:Observe({ [294] = dead }, 22)
check('packet and corpse duplicate same PH death once', row.phKills == 1)
t:Observe({ [294] = up }, 30)
t:Observe({ [294] = dead }, 40)
t:Observe({ [295] = up, [296] = up, [294] = dead }, 80)
check('one pop sample across multiple NM indices', row.pops.count == 1 and row.pops.total == 60 and row.pops.phTotal == 2 and row.sightings == 1)
t:Observe({ [296] = up }, 90)
check('alternate NM index does not create extra sighting', row.sightings == 1)
t:Observe({ [296] = dead }, 100)
check('witnessed NM kill recorded', row.nmKills == 1 and row.lastKill == 100)
t:Death(296, 101, true)
t:Drop(296, 1000, 2, 'one', 101)
t:Drop(296, 1000, 2, 'one', 101)
t:Drop(296, 1000, 1, 'two', 102)
t:Drop(296, 2000, 1, 'three', 102)
check('loot packets deduplicated; quantities and kills with item separate', row.nmKills == 1 and row.items['1000'].quantity == 3 and row.items['1000'].kills == 1 and row.items['2000'].kills == 1 and row.lootKills == 1)
t:Observe({ [296] = up }, 101)
check('stale alive memory immediately after packet does not reopen kill', row.sightings == 1)
t:Observe({ [296] = up }, 200)
check('NM return interval sampled for the same entity index', row.returns.count == 1 and row.returns.total == 100 and row.sightings == 2)
t:Drop(296, 1000, 1, 'new-kill', 210)
check('new NM kill has a new loot denominator', row.nmKills == 2 and row.items['1000'].kills == 2 and row.lootKills == 2)
t:Drop(999, 1000, 1, 'other', 220)
t:Drop(294, 1000, 1, 'ph', 220)
check('unwatched monsters and placeholder loot ignored', row.items['1000'].quantity == 4)

-- A pending first-PH-to-pop sample is deliberately not persisted across observation gaps.
t:Observe({ [294] = up }, 300)
t:Observe({ [294] = dead }, 310)
local samples = row.pops.count
t:Reset(); t:Watch(100, targets)
t:Observe({ [295] = up }, 1000)
check('logout/reload drops unfinished timing sample, not totals', row.pops.count == samples and row.phKills == 3 and row.nmKills == 2)
t:Observe({ [294] = up }, 1100)
t:Observe({ [294] = dead }, 1110)
t:Watch(101, targets); t:Watch(100, targets)
t:Observe({ [295] = up }, 1200)
check('zone changes do not contaminate pop averages', row.pops.count == samples)
t:Observe({ [294] = up }, 1300); t:Observe({ [294] = dead }, 1310)
t:Watch(100, {}); t:Watch(100, targets); t:Observe({ [295] = up }, 1400)
check('untracking a hunt discards its pending sample', row.pops.count == samples)

local shared = stats.New(stats.Prepare(nil))
shared:Watch(100, {
    targets[1], { name = 'Other Jack', record = { indices = { 297 }, placeholders = { { index = 294 } } } },
})
shared:Observe({ [294] = up }, 10); shared:Observe({ [294] = dead }, 20)
check('shared PH credited once to each associated hunt', shared.db.monsters['100:Jack'].phKills == 1 and shared.db.monsters['100:Other Jack'].phKills == 1)
shared:Observe({ [294] = up }, 30)
shared:Observe({ [294] = dead, [295] = up }, 40)
check('same-poll PH kill and NM pop processed deterministically', shared.db.monsters['100:Jack'].pops.phTotal == 2)

local function packet(size, fields)
    local bytes = {}
    for i = 1, size do bytes[i] = 0 end
    for _, field in ipairs(fields) do
        local offset, count, value = unpack(field)
        for i = 1, count do bytes[offset + i] = value % 256; value = math.floor(value / 256) end
    end
    return string.char(unpack(bytes))
end
local event = stats.Packet(0x029, packet(28, { { 8, 4, 0x01000127 }, { 0x16, 2, 295 }, { 0x18, 2, 6 } }))
check('battle message parsed from documented little-endian layout', event.kind == 'death' and event.index == 295 and event.source == 0x01000127)
local fields = { { 4, 4, 2 }, { 8, 4, 0x01000127 }, { 0x10, 2, 1000 }, { 0x12, 2, 295 }, { 0x14, 1, 3 }, { 0x18, 4, 1234 } }
event = stats.Packet(0x0D2, packet(28, fields))
check('source, item quantity, pool slot and timestamp parsed', event.kind == 'drop' and event.index == 295 and event.item == 1000 and event.quantity == 2 and event.token == '16777511:1234:3:1000')
fields[#fields + 1] = { 0x15, 1, 1 }
check('old pool replay ignored', stats.Packet(0x0D2, packet(28, fields)) == nil)
fields[#fields] = { 0x16, 1, 1 }
check('container loot ignored', stats.Packet(0x0D2, packet(28, fields)) == nil)
check('truncated and unrelated packets ignored', stats.Packet(0x0D2, '') == nil and stats.Packet(0x029, '') == nil and stats.Packet(1, 'anything') == nil)

local persisted = stats.Prepare(db)
local restored = stats.New(persisted)
restored:Watch(100, targets); restored:Observe({ [296] = dead }, 2000)
check('database restoration retains totals without recounting corpse', persisted.monsters['100:Jack'].nmKills == 2)
local corrupt = { version = 1, monsters = { bad = 'bad', ['100:Good'] = { zone = 100, name = 'Good', nmKills = 0 / 0, items = { bad = 1 }, placeholders = { bad = 'bad' } } } }
stats.Prepare(corrupt)
check('malformed aggregates normalized', corrupt.monsters.bad == nil and corrupt.monsters['100:Good'].nmKills == 0 and next(corrupt.monsters['100:Good'].items) == nil and next(corrupt.monsters['100:Good'].placeholders) == nil)
