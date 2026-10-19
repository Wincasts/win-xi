package.path = 'addons/libs/?.lua;' .. package.path
local data = require('winxi.gamedata')
data.Root('addons/libs/winxi/data/')
local quests = require('winxi.quests')
local function check(label, ok) assert(ok, label) end
local function has(records, key)
    for _, record in ipairs(records) do if record.Key == key then return true end end
    return false
end
local index = quests.Index()
check('revision and schema', index.Schema == 1 and #index.Source.Commit == 40)
check('complete numbered enumeration', #quests.Keys() == index.Count and index.Count > 1000)
check('hidden entries separate', #quests.Keys(true) == index.Count + index.HiddenCount and index.HiddenCount > 0)
check('invalid identity rejected', not quests.Get(nil, 1) and not quests.Get(0) and not quests.Get(-1, 0) and not quests.Get(0, 65536) and not quests.Get('0', 0) and not quests.Get(0, 1.5))
check('cross-log collisions', quests.Get(0, 0) and quests.Get(1, 0) and quests.Get(0, 0) ~= quests.Get(1, 0))
check('unknown/path input', not quests.GetKey('../0') and not quests.GetKey(nil) and not quests.Hidden('../bad') and not quests.Script('../index'))
local sourceLines = {}
for path in pairs(index.Scripts) do
    local source = quests.Script(path)
    check('every source readable', source and source.Path == path and #source.SHA256 == 64 and type(source.Text) == 'string')
    local lines = {}
    for line in (source.Text .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = line end
    sourceLines[path] = lines
end
for _, key in ipairs(quests.Keys(true)) do
    local record = quests.GetKey(key)
    check('record and presentation', record and record.Key == key and quests.TooltipKey(key).Server == record)
    for _, field in ipairs({ 'Sources', 'HelperSources', 'RelatedSources', 'Modules' }) do
        for _, path in ipairs(record[field] or {}) do check('indexed evidence source', index.Scripts[path] ~= nil) end
    end
    for _, entry in ipairs(record.Evidence or {}) do
        local line = sourceLines[entry.Source] and sourceLines[entry.Source][entry.Line]
        check('evidence line exactly matches source', line and line:match('^%s*(.-)%s*$') == entry.Text)
    end
    for _, declaration in ipairs(record.RewardDeclarations or {}) do
        check('reward declaration source and scope', sourceLines[declaration.Source] and declaration.Scope:find('not effective reward', 1, true))
    end
end
for zone, keys in pairs(index.ByZone) do
    for _, key in ipairs(keys) do
        local found = false
        for _, ref in ipairs(quests.GetKey(key).Zones or {}) do if ref.Id == zone then found = true end end
        check('zone index points at real references', found)
    end
end
local elder = quests.Get(4, 24)
check('Elder Memories identity', elder.Name == 'Elder Memories' and quests.GetBySymbol('otherAreas', 'ELDER_MEMORIES') == elder)
check('Selbina and Isacio references', has(quests.ForZone(248), elder.Key) and has(quests.ForNpc('ISACIO', 248), elder.Key))
check('search includes zone references', has(quests.Search('Selbina', { Log = 4 }), elder.Key))
check('literal search and limit', #quests.Search('[%') == 0 and #quests.Search('', { Limit = 2 }) == 2 and #quests.Search('', { Limit = 0 }) == 0)
check('invalid filter input', #quests.ForNpc(nil) == 0 and #quests.ForZone('248') == 0 and #quests.ForReward(-1) == 0 and not quests.GetBySymbol(nil, 'x'))
local knight = quests.Get(0, 29)
check('source title punctuation', knight.Name == "A Knight's Test" and knight.NameSource == 'source-header')
check('literal base reward item', has(quests.ForReward(12306), knight.Key) and knight.DeclaredRewardItems[1] == 12306)
local meat = quests.Get(0, 100)
check('base gil declaration', meat.RewardDeclarations[1].Fields.gil == 150 and not meat.DeclaredRewardItems)
local model = quests.Tooltip(0, 100, { Name = 'Localized title', Description = 'Client journal text' })
check('presentation separate from authority', model.Name == 'Localized title' and model.ClientDescription == 'Client journal text' and model.Server == meat and #model.Warnings >= 4)
local bag = quests.Get(3, 27)
check('static factory cataloged', bag.Factory.Name == 'GobbiebagQuest' and bag.Coverage == 'factory-script' and has(quests.ForNpc('Bluffnix', 245), bag.Key))
local shadows = quests.GetBySymbol('jeuno', 'SHADOWS_OF_THE_DEPARTED')
check('enabled era module indexed', shadows and shadows.Modules and quests.Script('modules/era/lua/quests/jeuno/shadows_of_the_departed.lua'))
local hidden = quests.Hidden('scripts/quests/hiddenQuests/New_Character_Cutscenes')
check('hidden quest namespace', hidden and hidden.Kind == 'hidden' and hidden.Log == nil and hidden.Id == nil and quests.GetKey(hidden.Key) == hidden)
check('Phoenix hidden quest module', hidden.Modules and quests.Script('modules/phoenix/lua/quests/hiddenquests/anniversary_ring.lua'))
check('hidden opt-in', not has(quests.ForZone(235), hidden.Key) and has(quests.ForZone(235, { Hidden = true }), hidden.Key))
local totals = 0
for _, value in pairs(index.Coverage) do totals = totals + value end
check('honest coverage totals', totals == index.Count and index.Coverage['enum-only'] > 0 and #index.Unresolved > 0 and #index.TodoFiles > 0)
data.Root('/nonexistent/winxi-quests-test/')
quests.Clear()
check('missing data safe', not quests.Get(4, 24) and #quests.Search('Selbina') == 0 and not quests.Hidden(hidden.Key))
data.Root('addons/libs/winxi/data/')
quests.Clear()
check('cache reload', quests.Get(4, 24).Name == 'Elder Memories')
print('winxi.quests: every definition/source/model, composite identities, hidden namespace, source lines, factories, modules, zone/NPC/reward filters and safe missing data', true)
