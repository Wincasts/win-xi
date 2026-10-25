-- Reproducible synthetic profile; native Ashita memory/ImGui costs are NOT represented.
-- Run: luajit tests/harness.lua cooldowns tests/cooldowns_stand_in.lua tests/cooldowns_performance_check.lua
local game, options = RECAST_GAME, H.options()
local memory = AshitaCore:GetMemoryManager()
local recast, resources = memory:GetRecast(), AshitaCore:GetResourceManager()
local petRecasts = require('winxi.automaton.recasts')
local packets = require('winxi.packets')
local imgui = require('imgui')
local metrics = {}
local function bump(key) metrics[key] = (metrics[key] or 0) + 1 end
for _, key in ipairs({ 'GetAbilityTimerId', 'GetAbilityTimer', 'GetSpellTimer' }) do
    local original = recast[key]
    recast[key] = function(self, ...)
        bump(key)
        if key == 'GetAbilityTimerId' and game.unknown and (...) == 1 then return 250 end
        return original(self, ...)
    end
end
memory.GetRecast = function() return recast end
local originalAbility, originalSpell = resources.GetAbilityByTimerId, resources.GetSpellById
resources.GetAbilityByTimerId = function(self, id)
    bump('abilityNames')
    if game.unknown then return nil end
    return originalAbility(self, id)
end
resources.GetSpellById = function(self, id) bump('spellNames'); return originalSpell(self, id) end
resources.GetAbilityById = function() bump('fallbackResources'); return nil end
AshitaCore.GetResourceManager = function() return resources end
local originalPetTimers, originalSort, originalParse = petRecasts.Timers, table.sort, packets.inbound.action.parse
petRecasts.Timers = function(...) bump('petUpdates'); return originalPetTimers(...) end
table.sort = function(...) bump('sorts'); return originalSort(...) end
local originalFormat, originalMeasure = string.fmt, imgui.CalcTextSize
string.fmt = function(...) bump('formats'); return originalFormat(...) end
imgui.CalcTextSize = function(...) bump('textMeasures'); return originalMeasure(...) end
local function observed()
    require('winxi.automaton.tracker').Clear()
    packets.inbound.action.parse = function()
        return { actor_id = 2, category = 11, param = 1945, targets = {} }
    end
    H.packetData(packets.inbound.action.id, '')
end
local function profile(label)
    H.frames(30) -- JIT/cache warmup
    collectgarbage('collect')
    metrics = {}
    local saves, start = H.saves(), H.cpuClock()
    H.frames(1000)
    local elapsed = H.cpuClock() - start
    local measured = metrics
    assert(H.saves() == saves, 'steady-state frames must never write settings')
    metrics = {}
    collectgarbage('collect'); collectgarbage('stop')
    local before = collectgarbage('count')
    H.frames(100)
    local allocated = (collectgarbage('count') - before) / 100
    collectgarbage('restart'); collectgarbage('collect')
    local function perFrame(key) return (measured[key] or 0) / 1000 end
    H.print(('%s: %.3f ms/frame; %.2f KiB allocated/frame; spell reads %.0f; ability reads %.0f; name lookups %.0f; fallback lookups %.0f; pet updates %.0f; sorts %.0f; formats %.0f; text measures %.0f'):format(
        label, elapsed, allocated, perFrame('GetSpellTimer'),
        perFrame('GetAbilityTimerId') + perFrame('GetAbilityTimer'), perFrame('abilityNames') + perFrame('spellNames'),
        perFrame('fallbackResources'), perFrame('petUpdates'), perFrame('sorts'), perFrame('formats'), perFrame('textMeasures')))
    return measured
end
H.print('Cooldowns synthetic profile (1000 timed frames, 100 allocation-sampling frames per case):')
game.playerTimer, game.spellTimer, game.pet = 0, 0, 0
local idle = profile('idle/no pet')
assert(idle.GetSpellTimer <= 301 * 1025, 'player scans must be throttled to at most 10Hz')
game.playerTimer, game.spellTimer = 600, 300
local players = profile('2 player cooldowns')
assert(not players.spellNames and not players.abilityNames, 'warm names must avoid resource lookups')
assert(players.formats < 2000, 'countdown text must be reused for measurement/rendering')
game.pet = 2
options.petAutomaton = { head = 4, frame = 0x23, attachments = { 1 } }
game.buffs = { 300 }
observed()
profile('player + pet cooldowns')
options.showPetCooldowns = false
observed()
local disabled = profile('pet display disabled')
assert(not disabled.petUpdates, 'disabled pet display must skip row calculations')
options.showPetCooldowns, options.showPlayerCooldowns = true, false
observed()
local noPlayer = profile('player display disabled')
assert(not noPlayer.GetSpellTimer and not noPlayer.GetAbilityTimer and noPlayer.petUpdates,
    'disabled player display must skip recast scans but keep pets')
options.showPlayerCooldowns, options.sortByTime = true, true
observed()
profile('time sorting enabled')
options.sortByTime, game.unknown = false, true
local unresolved = profile('unresolved ability fallback')
assert(not unresolved.fallbackResources and not unresolved.abilityNames, 'warm fallback misses must be cached')
game.unknown, game.hidden = false, true
local hidden = profile('UI hidden')
assert(not hidden.GetSpellTimer and not hidden.GetAbilityTimer and not hidden.petUpdates,
    'hidden UI must skip all recast collection')
game.hidden = false
petRecasts.Timers, table.sort, packets.inbound.action.parse = originalPetTimers, originalSort, originalParse
string.fmt, imgui.CalcTextSize = originalFormat, originalMeasure
H.print('Cooldowns performance invariants passed: throttled scans; cached names/misses and text; no disabled player scans or pet calculations, or steady-state saves; hidden UI skips collection.')
