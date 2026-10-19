package.path = 'addons/libs/?.lua;' .. package.path
local gamedata = require('winxi.gamedata')
gamedata.Root('addons/libs/winxi/data/')
local function check(name, ok) assert(ok, name) end
local kinds = { 'spells', 'abilities', 'weaponskills', 'traits', 'jobs', 'skills', 'elements' }
for _, kind in ipairs(kinds) do
    local api = require('winxi.' .. kind)
    check(kind .. ' revision', #api.Index().Source.Commit == 40)
    check(kind .. ' enumeration', #api.Ids() == api.Index().Count and api.Index().Count > 0)
    check(kind .. ' invalid IDs', not api.Get(-1) and not api.Get('1') and not api.Get(1.2) and not api.Get(65536))
    for _, id in ipairs(api.Ids()) do
        check(kind .. ' definition and model', api.Get(id).Id == id and api.Tooltip(id).Server == api.Get(id))
    end
    for path in pairs(api.Index().Scripts) do
        local script = api.Script(path)
        check(kind .. ' evidence readable', script and script.Path == path and #script.SHA256 == 64 and type(script.Text) == 'string')
    end
    check(kind .. ' literal search', #api.Search('[', 5) == 0 and #api.Search('', 1) == 1)
    check(kind .. ' bad search', #api.Search(nil) == 0 and #api.Search('', 0) == 0)
    local id = api.Ids()[1]
    api.Clear()
    check(kind .. ' reload', api.Get(id).Id == id)
end
local spells = require('winxi.spells')
local abilities = require('winxi.abilities')
local ws = require('winxi.weaponskills')
local traits = require('winxi.traits')
local skills = require('winxi.skills')
local jobs = require('winxi.jobs')
check('spell binary levels', spells.Get(1).Jobs[3] == 1 and spells.Get(1).Jobs[5] == 3 and spells.Get(1).Jobs[1] == nil)
local function has(entries, id) for _, entry in ipairs(entries) do if entry.Id == id then return true end end return false end
check('ForJob level filter', has(spells.ForJob(3, 1), 1) and not has(spells.ForJob(5, 2), 1) and has(spells.ForJob(5, 3), 1))
check('WS job values are not levels', ws.Get(1).Jobs[1] == 2 and has(ws.ForJob(1, 1), 1))
check('WS Phoenix tier-one skill adjustment', ws.Get(1).Data.skilllevel == 10)
check('WS binary SQL removes PUP from asuran fists', not ws.Get(9).Jobs[18])
check('WS skill threshold', not has(ws.ForSkill(1, 9), 1) and has(ws.ForSkill(1, 10), 1))
check('spell cast/recast units', spells.Tooltip(1).Lines[2] == 'Base cast: 2 s; recast: 5 s')
check('Phoenix two-hour ability SQL', abilities.Get(16).Data.recastTime == 7200)
local stratagem
for _, id in ipairs(abilities.Ids()) do if abilities.Get(id).Data.recastId == 231 then stratagem = id; break end end
check('charge progression', stratagem and abilities.ChargeRule(stratagem, 20, 30).maxCharges == 2 and abilities.ChargeRule(stratagem, 20, 70).chargeTime == 60)
check('traits preserve variants', #traits.Get(1).Rows > 2 and #traits.Rows(1, 11, 10) == 2)
for _, row in ipairs(traits.Rows(1, 11, 10)) do check('trait row filtered', row.job == 11 and row.level == 10) end
check('PUP era skill overlay', skills.Get(1).Ranks[18] == 'b_plus')
check('PUP cap follows overlaid rank', skills.Cap(1, 18, 75) == skills.Index().Caps[75].b_plus)
check('unknown skill cap', skills.Cap(65535, 18, 75) == nil)
check('job relationships', jobs.Get(3).Abbreviation == 'WHM' and has(jobs.Related(3, 1).spells, 1) and not jobs.Related(65535))
local calls = {}
AshitaCore = { GetResourceManager = function() return {
    GetSpellById = function(_, id) calls.spell = id; return { Name = { 'Localized spell' }, Description = { 'Client-only' } } end,
    GetAbilityById = function(_, id) calls.ability = id; return { Name = { 'Localized ability' } } end,
} end }
local tip = spells.Tooltip(1, spells.ClientResource(1))
check('client presentation separate', calls.spell == 1 and tip.Name == 'Localized spell' and tip.ClientDescription == 'Client-only' and tip.Server.Data.mpCost == 8)
abilities.ClientResource(16)
check('ability resource namespace offset', calls.ability == 528)
ws.ClientResource(1)
check('WS resource namespace', calls.ability == 1)
check('invalid client resource', not abilities.ClientResource(65535))
print('winxi catalogs: every record/source/model, job bytes, Phoenix SQL, skill overlays, levels, charges, traits and client namespaces', true)
