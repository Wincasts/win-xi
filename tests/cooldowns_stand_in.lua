-- Extend the generic harness with recast memory and an automaton.
-- The native settings loader calls defaults:copy(true) on first use. The generic harness
-- accepts plain tables, so enforce the native T{} contract here as a fresh-install regression.
local Settings = require('settings')
local originalSettingsLoad = Settings.load
Settings.load = function(defaults, ...)
    assert(getmetatable(defaults) ~= nil, 'settings defaults must use T{} for native :copy(true)')
    COOLDOWNS_DEFAULTS_CHECKED = true
    return originalSettingsLoad(defaults, ...)
end
string.fmt = string.format
RECAST_GAME = { job = 18, owner = 1, pet = 2, buffs = {}, playerTimer = 600, spellTimer = 300 }
local game = RECAST_GAME
local memory = AshitaCore:GetMemoryManager()
local player, party = memory:GetPlayer(), memory:GetParty()
player.GetMainJob = function() return game.job end
player.GetSubJob = function() return game.subjob or 0 end
player.GetBuffs = function() return game.buffs end
player.GetPetMPPercent = function() return 100 end
party.GetMemberServerId = function() return game.owner end
party.GetMemberTargetIndex = function() return 1 end
memory.GetPlayer = function() return player end
memory.GetParty = function() return party end
memory.GetRecast = function() return {
    GetAbilityTimerId = function(_, slot) return slot == 1 and 210 or 0 end,
    GetAbilityTimer = function(_, slot) return slot == 1 and game.playerTimer or 0 end,
    GetSpellTimer = function(_, id) return id == 4 and game.spellTimer or 0 end,
} end
AshitaCore.GetMemoryManager = function() return memory end
AshitaCore.GetResourceManager = function() return {
    GetAbilityByTimerId = function() return { Name = { 'Fire Maneuver' } } end,
    GetSpellById = function() return { Name = { 'Cure IV' } } end,
} end
GetEntity = function(index)
    if index == 1 then return { ServerId = game.owner, PetTargetIndex = game.pet } end
    if index == game.pet then return { ServerId = game.pet, HPPercent = 100 } end
end
local Game = require('winxi.game')
for _, key in ipairs({ 'IsChatExpanded', 'IsMapOpen', 'IsEventHappening', 'IsInterfaceHidden' }) do
    Game[key] = function() return game.hidden or false end
end
dofile('forks/addons/cooldowns/cooldowns.lua')
