-- Hunting database integration: polling + packets + settings persistence + simplified UI.
local function check(label, ok) assert(ok, label); H.print(label, true) end
local now = 1700000000
os.time = function() return now end
local imgui, hunts = require('imgui'), require('hunts')
local record = { indices = { 295 }, placeholders = { { index = 294, name = 'Hare', respawn = 180 } },
    level = { 20, 25 }, job = 1, aggro = true, link = true, truesight = true, detects = { 'Sight' },
    kinds = 't', respawn = { 300, 600 }, drops = { { rate = 500, items = { { 1000, 10000 } } } } }
hunts.Monster = function() return record end
hunts.ZoneName = function() return 'Test Zone' end
local zone, entities = 100, {}
local memory = AshitaCore:GetMemoryManager()
local party = memory:GetParty()
party.GetMemberZone = function() return zone end
party.GetMemberTargetIndex = function() return 1024 end
memory.GetParty = function() return party end
memory.GetEntity = function()
    return { GetRenderFlags0 = function(_, index) return entities[index] and 0x200 or 0 end,
        GetHPPercent = function(_, index) return entities[index] and entities[index].hp or 0 end,
        GetDistance = function() return 100 end,
        GetLocalPositionX = function() return 0 end, GetLocalPositionY = function() return 0 end,
        GetLocalPositionZ = function() return 0 end }
end
AshitaCore.GetMemoryManager = function() return memory end
local texts = {}
for _, f in ipairs({ 'Text', 'TextUnformatted', 'TextDisabled', 'TableSetupColumn' }) do
    rawset(imgui, f, function(text) texts[#texts + 1] = text end)
end
rawset(imgui, 'TextColored', function(_, text) texts[#texts + 1] = text end)
local function wrote(part)
    for _, text in ipairs(texts) do if tostring(text):find(part, 1, true) then return true end end
    return false
end
local o = H.options()
o.viewZone, o.viewName = 100, 'Test NM'
o.marks, o.tods, o.phTods = {}, {}, {}
o.sound[1] = false
H.play(true)
local function poll() texts = {}; H.frames(9) end
local function row() return o.hunting.monsters['100:Test NM'] end
poll()
check('lookup no longer shows level/job/links/detection summary', not wrote('Lv 20') and not wrote('WAR') and not wrote('Links') and not wrote('Aggressive') and not wrote('True Sight'))
H.command('/mark ph 126'); H.command('/mark tod')
check('manual TOD reports do not invent kills', row() == nil)
entities[294] = { hp = 100 }; poll()
now = now + 10; entities[294].hp = 0
local saved = H.saves()
poll()
check('PH stats and timer saved together in one poll', row().phKills == 1 and H.saves() - saved == 1)
now = now + 50; entities[295] = { hp = 100 }; poll()
check('selected non-mark NM contributes pop averages', row().pops.count == 1 and row().pops.total == 50 and row().pops.phTotal == 1)
local function packet(fields)
    local bytes = {}; for i = 1, 28 do bytes[i] = 0 end
    for _, f in ipairs(fields) do
        local offset, count, value = unpack(f)
        for i = 1, count do bytes[offset + i] = value % 256; value = math.floor(value / 256) end
    end
    return string.char(unpack(bytes))
end
local death = packet({ { 8, 4, 0x01064127 }, { 0x16, 2, 295 }, { 0x18, 2, 6 } })
now = now + 10
saved = H.saves()
H.packetData(0x029, death)
check('confirmed battle death recorded and saved without waiting for poll', row().nmKills == 1 and H.saves() - saved == 1)
entities[295].hp = 0
poll()
check('memory corpse does not duplicate packet kill', row().nmKills == 1)
local loot = packet({ { 4, 4, 2 }, { 8, 4, 0x01064127 }, { 0x10, 2, 1000 }, { 0x12, 2, 295 }, { 0x18, 4, 1234 } })
H.packetData(0x0D2, loot); H.packetData(0x0D2, loot)
check('source-linked loot recorded once', row().items['1000'].quantity == 2 and row().items['1000'].kills == 1 and row().nmKills == 1)
H.tab(3)
H.command('/mark stats')
poll()
check('stats tab displays aggregates and observed loot', wrote('PH Kills') and wrote('NM Kills') and wrote('Avg To Pop') and wrote('Quantity Seen') and wrote('Item 1000') and wrote('100.0%'))
check('drop-rate caveats displayed', wrote('Missing loot/TH/other hunters') and wrote('not party/claim credit'))
local persisted = o.hunting
H.resettle(); poll()
check('saved hunting database survives settings reload without recounting corpse', o.hunting == persisted and row().nmKills == 1 and row().phKills == 1 and row().items['1000'].quantity == 2)
H.play(false)
H.packetData(0x029, death); H.packetData(0x0D2, loot)
check('logged-out packets cannot pollute database', row().nmKills == 1 and row().items['1000'].quantity == 2)
H.play(true)
zone = 101
entities[294], entities[295] = nil, nil
poll()
check('zone-local hunt records kept separate', o.hunting.monsters['101:Test NM'] == nil and row().nmKills == 1)
o.viewZone = 101
H.packetData(0x0D2, loot)
check('delayed loot from previous zone ignored', o.hunting.monsters['101:Test NM'] == nil)
local newZoneLoot = packet({ { 4, 4, 2 }, { 8, 4, 0x01065127 }, { 0x10, 2, 1000 }, { 0x12, 2, 295 }, { 0x18, 4, 1234 } })
H.packetData(0x0D2, newZoneLoot)
check('loot can confirm a watched NM kill before any memory sighting', o.hunting.monsters['101:Test NM'].nmKills == 1 and row().nmKills == 1)
-- Simulate loading another character's saved database.
o.hunting = nil
H.resettle()
check('another character does not inherit aggregate database', o.hunting.version == 1 and next(o.hunting.monsters) == nil)
H.unload()
