-- Regression checks for cached searches, per-poll snapshots, and batched persistence.
-- luajit tests/harness.lua mark addons/mark/mark.lua tests/mark_performance_check.lua
require('winxi.gamedata').Root('addons/libs/winxi/data/') -- the server's sets, from the repository's data
local realLoadfile = loadfile
loadfile = function(path)
    local own = path:match('^C:\\ashita\\addons\\mark\\(.*)$')
    return realLoadfile(own and ('addons/mark/' .. own) or path)
end
local function check(label, ok)
    assert(ok, label)
    H.print(label, true)
end

local hunts = require('hunts')
local originalZones = hunts.Zones
local scans = 0
hunts.Zones = function(...)
    scans = scans + 1
    return originalZones(...)
end
local first = hunts.Find('behemoth', true, 40)
check('search scans once', scans == 1 and #first > 0)
check('unchanged normalized search reuses results', hunts.Find('BEHEMOTH', true) == first and scans == 1)
local limited = hunts.Find('behemoth', true, 1)
check('result limit invalidates search', limited ~= first and #limited == 1 and scans == 2)
local hidden = hunts.Find('Marauder Dvogzog', false)
check('scripted monsters filtered', #hidden == 0)
local scripted = hunts.Find('Marauder Dvogzog', true)
check('scripted setting invalidates search', #scripted == 1 and scripted ~= hidden)
local missing = hunts.Find('no such notorious monster', true)
local before = scans
check('empty results cached too', #missing == 0 and hunts.Find('no such notorious monster', true) == missing and scans == before)
hunts.Zones = originalZones

local zone, entities, reads = 100, {}, {}
local respawnReads = 0
local placeholder = setmetatable({ index = 294, name = 'Shared Hare' }, {
    __index = function(_, field)
        if field == 'respawn' then respawnReads = respawnReads + 1; return 180 end
    end,
})
local function record(index)
    return { indices = { index }, placeholders = { placeholder }, level = { 1, 1 },
        respawn = { 300, 600 }, kinds = 't', drops = {} }
end
local records = { Alpha = record(295), Beta = record(296), Other = record(297) }
local originalMonster = hunts.Monster
hunts.Monster = function(z, name)
    return z == 100 and records[name] or originalMonster(z, name)
end
local function field(name, default)
    return function(_, index) return entities[index] and entities[index][name] or default end
end
local entity = {
    GetRenderFlags0 = function(_, index)
        reads[index] = (reads[index] or 0) + 1
        return entities[index] and 0x200 or 0
    end,
    GetHPPercent = field('hp', 0), GetDistance = function() return 100 end,
    GetLocalPositionX = function() return 0 end, GetLocalPositionY = function() return 0 end,
    GetLocalPositionZ = function() return 0 end,
}
local memory = AshitaCore:GetMemoryManager()
local party = memory:GetParty()
party.GetMemberZone = function() return zone end
party.GetMemberTargetIndex = function() return 1024 end
memory.GetParty = function() return party end
memory.GetEntity = function() return entity end
AshitaCore.GetMemoryManager = function() return memory end
local o = H.options()
o.viewZone, o.viewName = 100, 'Alpha'
o.marks = { { zone = 100, name = 'Alpha' }, { zone = 100, name = 'Beta' } }
o.tods = {}
o.isVisible[1], o.sound[1] = false, false
local function poll()
    reads, respawnReads = {}, 0
    H.frames(9) -- one poll, even while the main window is closed
end
H.play(true)
poll()
check('out-of-range NM and shared PH read once per poll', reads[295] == 1 and reads[296] == 1 and reads[294] == 1)
entities[295], entities[296], entities[294] = { hp = 100 }, { hp = 100 }, { hp = 100 }
poll()
check('visible NM and shared PH read once, cached misses refreshed', reads[295] == 1 and reads[296] == 1 and reads[294] == 1)
local said = #H.printed
poll()
check('unchanged live marks do not announce again', #H.printed == said)

entities[295].hp, entities[296].hp, entities[294].hp = 0, 0, 0
local saved = H.saves()
poll()
check('two automatic deaths saved once', #o.tods == 2 and H.saves() - saved == 1)
check('shared placeholder state processed once', respawnReads == 2)
saved = H.saves()
poll()
check('corpses not saved repeatedly', H.saves() == saved)
entities[294] = nil
H.command('/mark ph 126 4')
said = #H.printed
poll()
check('shared placeholder due once', #H.printed - said == 1 and respawnReads == 2)
said = #H.printed
poll()
check('due announcement not repeated', #H.printed == said)
entities[294] = { hp = 100 }
said = #H.printed
poll()
check('shared placeholder respawn announced once', #H.printed - said == 1)
entities[295].hp, entities[296].hp = 100, 100
saved = H.saves()
poll()
check('two automatic TOD removals saved once', #o.tods == 0 and H.saves() - saved == 1)

-- A single command still persists immediately; only bulk changes defer saving.
saved = H.saves()
H.command('/mark tod')
check('manual TOD saved immediately', #o.tods == 1 and H.saves() - saved == 1)
H.command('/mark tod clear')
o.tods = { { zone = 100, name = 'Alpha', at = os.time() }, { zone = 100, name = 'Other', at = os.time() } }
local texts = {}
local imgui = require('imgui')
rawset(imgui, 'TextColored', function(_, text) texts[#texts + 1] = text end)
local function occurrences(name)
    local count = 0
    for _, text in ipairs(texts) do if text == name then count = count + 1 end end
    return count
end
o.isVisible[1] = true
H.tab(2)
poll()
texts = {}; H.frames(1)
check('membership lookup preserves ordered rows without duplicate TOD rows',
    texts[1] == 'Mark' and occurrences('Alpha') == 1 and occurrences('Beta') == 1 and occurrences('Other') == 1)
-- Direct settings replacement must not leave membership stale.
o.marks = { { zone = 100, name = 'Beta' } }
poll()
texts = {}; H.frames(1)
check('membership refreshed when marks change', occurrences('Alpha') == 1 and occurrences('Beta') == 1 and occurrences('Other') == 1)

saved = H.saves()
H.command('/mark clear nobody')
check('no matching marks means no save', H.saves() == saved)
o.marks = {}
for i = 1, 10 do o.marks[i] = { zone = 100, name = 'Bulk ' .. i } end
saved = H.saves()
H.command('/mark clear bulk')
check('clearing ten marks saves once', #o.marks == 0 and H.saves() - saved == 1)
saved = H.saves()
H.command('/mark clear')
check('clearing empty list does not save', H.saves() == saved)
o.marks = { { zone = 100, name = 'Alpha' }, { zone = 100, name = 'Beta' } }
saved = H.saves()
H.command('/mark clear alpha')
check('selective clear keeps unmatched mark and saves once', #o.marks == 1 and o.marks[1].name == 'Beta' and H.saves() - saved == 1)

-- Entity indices are zone-local, including cached misses and placeholder transitions.
-- No selected view here: its rebuild also reads the static respawn description.
o.viewName = ''
entities[294].hp = 0
poll()
zone = 101
poll()
check('no entity reads for marks in a different zone', reads[294] == nil and reads[295] == nil and reads[296] == nil)
zone = 100
entities[294] = nil
said = #H.printed
poll()
check('zone change refreshes snapshots and restores saved placeholder timers',
    reads[294] == 1 and respawnReads == 2 and #o.phTods == 1 and #H.printed - said == 1)
H.unload()
