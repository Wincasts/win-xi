-- Run: luajit tests/tcrossbar_catalog_check.lua
-- Reuse the settings harness's Ashita/graphics stubs, then exercise the real action catalogs.
dofile('tests/tcrossbar_settings_check.lua')
bit = require('bit')
local editor = require('bindinggui')
local function Upvalue(fn, wanted)
    for i = 1,100 do
        local name, value = debug.getupvalue(fn, i)
        if name == wanted then return value end
        if not name then break end
    end
    error('missing upvalue: ' .. wanted)
end
local setup = Upvalue(editor.Show, 'Setup')
local state = Upvalue(editor.Render, 'state')
local refresh = Upvalue(editor.Render, 'RefreshActionCatalog')
local encoding = require('gdifonts.encoding')
encoding.ShiftJIS_To_UTF8 = function(_, value) return value end
local player = require('state.player')
player.KnowsAbility = function(_, id) return id == 547 or id == 1 end
player.HasSpell = function(_, res) return res.Index == 1 or res.Index == 3 end
player.GetJobData = function() return { MainJob = 18, MainJobLevel = 1, SubJob = 1, SubJobLevel = 1 } end
player.GetJobPointTotal = function() return 0 end
local function ability(id, name)
    return { Id = id, Name = { name }, Targets = 4, RecastTimerId = 10 }
end
local abilities = {
    [547] = ability(547, 'Provoke'), [650] = ability(650, 'Deploy'),
    [567] = ability(567, 'Pet Commands'), [651] = ability(651, ''),
    [652] = ability(652, '.'), [653] = ability(653, '   '),
    [1] = ability(1, 'Known WS'), [2] = ability(2, 'Unknown WS'),
}
local function spell(id, name, trust, level)
    local levels = {}
    for job = 1,23 do levels[job] = -1 end
    levels[2] = trust and 1 or -1
    levels[19] = level -- PUP, simply to test current-job/level filtering
    return { Index = id, Name = { name }, LevelRequired = levels, JobPointMask = 0 }
end
local spells = {
    [1] = spell(1, 'Known Spell', false, 1),
    [2] = spell(2, 'Unknown Spell', false, 99),
    [3] = spell(3, 'Known But Too High Level', false, 99),
    [4] = spell(4, 'Unknown Trust', true, -1),
    [5] = spell(5, '', false, 1),
}
AshitaCore.GetResourceManager = function() return {
    GetAbilityById = function(_, id) return abilities[id] end,
    GetSpellById = function(_, id) return spells[id] end,
} end
gTextureCache = { GetTexture = function() return nil end }
local function Has(id)
    for _,res in ipairs(state.ActionResources) do if (res.Id or res.Index) == id then return true end end
    return false
end
gSettings.ShowUnavailableActions = false
setup.Ability(true)
assert(#state.ActionResources == 1 and Has(547) and not Has(650))
setup.Spell(true)
assert(#state.ActionResources == 1 and Has(1))
setup.Trust(true)
assert(#state.ActionResources == 0)
setup.Weaponskill(true)
assert(#state.ActionResources == 1 and Has(1))
gSettings.ShowUnavailableActions = true
setup.Ability(true)
assert(#state.ActionResources == 2 and Has(547) and Has(650) and not Has(567))
setup.Spell(true)
assert(#state.ActionResources == 3 and Has(1) and Has(2) and Has(3) and not Has(4))
setup.Trust(true)
assert(#state.ActionResources == 1 and Has(4))
setup.Weaponskill(true)
assert(#state.ActionResources == 2 and Has(1) and Has(2))
-- Filter changes preserve a selected pet command and a custom macro, even when no longer listed.
state.Combos.Type, state.Indices.Type = T{ 'Ability' }, 1
setup.Ability(true)
for index,res in ipairs(state.ActionResources) do if res.Id == 650 then state.Indices.Action = index end end
state.MacroText, state.MacroLabel = { '/pet "Deploy" <t>' }, { 'My Puppet' }
local originalContexts = state.ContextEditors
gSettings.ShowUnavailableActions = false
refresh()
assert(state.ActionResources[state.Indices.Action].Id == 650)
assert(state.MacroText[1] == '/pet "Deploy" <t>' and state.MacroLabel[1] == 'My Puppet')
assert(state.ContextEditors == originalContexts)
gSettings.ShowUnavailableActions = true
refresh()
assert(#state.ActionResources == 2 and state.ActionResources[state.Indices.Action].Id == 650)
-- Empty catalogs can be populated by the toggle without leaving an invalid selection.
state.Combos.Type = T{ 'Ability' }
state.ActionResources, state.Indices.Action = T{}, 1
refresh()
assert(state.ActionResources[state.Indices.Action] and state.MacroText[1]:find('Deploy'))
print('tcrossbar catalog: unavailable pet commands, unlearned/high-level spells, trusts, weaponskills, invalid/category filtering and draft preservation passed')
