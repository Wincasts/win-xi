-- Native-call counters and correctness regressions for the throttled snapshot/name caches.
local game, options = RECAST_GAME, H.options()
local memory = AshitaCore:GetMemoryManager()
local recast, resources = memory:GetRecast(), AshitaCore:GetResourceManager()
local packets, pet = require('winxi.packets'), require('winxi.automaton.recasts')
local imgui, window = require('imgui'), require('winxi.window')
local reads, names, fallback, spellNames, petUpdates, formats = 0, 0, 0, 0, 0, 0
local id, expires, spellTime = 250, os.clock() + 12.08, 0
recast.GetAbilityTimerId = function(_, slot) return slot == 1 and id or 0 end
recast.GetAbilityTimer = function(_, slot) return slot == 1 and math.max(0, (expires - os.clock()) * 60) or 0 end
recast.GetSpellTimer = function(_, spell) reads = reads + 1; return spell == 4 and spellTime or 0 end
memory.GetRecast = function() return recast end
resources.GetAbilityByTimerId = function() names = names + 1; return nil end
resources.GetAbilityById = function(_, ability)
    fallback = fallback + 1
    if ability == 42 then return { RecastTimerId = 250, Name = { 'Fallback ability' } } end
end
resources.GetSpellById = function() spellNames = spellNames + 1; return { Name = { 'Cached spell' } } end
AshitaCore.GetResourceManager = function() return resources end
local originalPetTimers = pet.Timers
pet.Timers = function(...) petUpdates = petUpdates + 1; return originalPetTimers(...) end
local originalFormat = string.fmt
string.fmt = function(format, ...)
    if format == '%is' or format == '%im %is' or format == '%ih %im %is' then formats = formats + 1 end
    return originalFormat(format, ...)
end
local drawn = {}
window.Full = function(name, _, _, draw)
    if name == 'Cooldowns' then draw() end
end
imgui.Text = function(text) drawn[text] = true end
imgui.TextColored = function(_, text) drawn[text] = true end
local function frame(n)
    for _ = 1, n or 1 do drawn = {}; H.frames(1) end
end
local count = 0
local function check(ok, message) assert(ok, message); count = count + 1 end
options.showPetCooldowns = false
frame()
check(reads == 1025 and names == 1 and fallback == 2049, 'first scan resolves fallback once')
check(formats == 1 and drawn['Fallback ability'] and drawn['12s'], 'one countdown format shared by measurement and rendering')
frame()
check(reads == 1025 and formats == 1, 'between scans, same-second countdown reuses text')
frame()
check(reads == 1025 and drawn['11s'] and formats == 2, 'countdown advances smoothly between scans')
frame(2)
check(reads == 2050 and names == 1 and fallback == 2049, 'subsequent scans reuse resolved ability name')
check(petUpdates == 0, 'disabled pet section skips row calculations')
id = 251
H.wait(0.11); frame()
check(drawn['(Unknown: 251)'] and fallback == 2049 and names == 2, 'fallback miss uses prebuilt map')
H.wait(0.11); frame()
check(names == 2 and fallback == 2049, 'unknown ability names are cached too')
spellTime = 600
H.wait(0.11); frame()
H.wait(0.11); frame()
check(spellNames == 1 and drawn['Cached spell'], 'spell names are cached across scans')
-- Expiry must not wait for the next 10Hz scan.
spellTime, id, expires = 0, 250, os.clock() + 0.075
H.resettle(); frame()
local beforeExpiry = reads
check(drawn['Fallback ability'], 'short active cooldown collected')
frame(2)
check(reads == beforeExpiry and not drawn['Fallback ability'], 'expired snapshot row disappears between scans')
expires = os.clock() + 20
H.wait(0.11); frame()
local beforeNames, beforeFallback = names, fallback
local function invalidates(change, message)
    change(); frame()
    check(names == beforeNames + 1 and fallback == beforeFallback + 2049, message)
    beforeNames, beforeFallback = names, fallback
end
invalidates(function() game.job = 1 end, 'main job change invalidates name and snapshot caches')
invalidates(function() game.subjob = 2 end, 'subjob change invalidates caches')
invalidates(function() game.owner = 2 end, 'character identity change invalidates caches')
invalidates(function() H.packet(0x00A) end, 'zone packet invalidates caches')
invalidates(function() H.resettle() end, 'settings reload invalidates caches')
game.hidden = true
local hiddenReads = reads
frame(5)
check(reads == hiddenReads, 'hidden game UI skips scans')
game.hidden = false
frame()
check(reads == hiddenReads + 1025, 'returning UI refreshes immediately')
-- Observation still runs while pet rows are disabled, so toggling on needs no new pet action.
game.job, game.pet = 18, 2
options.petAutomaton = { head = 3, frame = 0x21, attachments = {} }
packets.inbound.action.parse = function() return { actor_id = 2, category = 11, param = 1944, targets = {} } end
H.packetData(packets.inbound.action.id, '')
frame()
check(not drawn.Bash, 'disabled section remains hidden after observing action')
options.showPetCooldowns = true
frame()
check(drawn.Bash, 'reenabled pet section uses observations collected while disabled')
string.fmt, pet.Timers = originalFormat, originalPetTimers
H.print(('cooldowns optimization: %d assertions passed'):format(count))
