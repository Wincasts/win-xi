package.path = 'addons/libs/?.lua;' .. package.path
local data = require('winxi.gamedata')
data.Root('addons/libs/winxi/data/')
local items = require('winxi.items')
local function check(label, ok) assert(ok, label) end
check('schema and count', items.Index().Schema == 1 and items.Index().Count > 23000)
check('invalid IDs', not items.Get(-1) and not items.Get(65536) and not items.Get('5149') and not items.Get(1.5))
local ids = items.Ids()
check('complete enumeration', #ids == items.Index().Count)
for n, id in ipairs(ids) do
    check('every item has base data', items.Get(id).Id == id and items.Get(id).Basic.itemid == id)
    check('ordered IDs', n == 1 or ids[n - 1] < id)
end
check('Phoenix stack override', items.Get(605).Basic.stackSize == 12)
check('Phoenix shield jobs', items.Get(12306).Equipment.jobs == 192)
check('Phoenix band cooldown', items.Get(15761).Usable.reuseDelay == 57600)
check('base modifier names', items.ModName(1) == 'DEF')
local sushi = items.Get(5149)
check('food duration and modifiers', sushi.Food.Duration == 1800 and #sushi.Food.Mods == 8)
check('script evidence', items.Script(sushi.Script).Text:find('FOOD_ACC_CAP', 1, true))
for path in pairs(items.Index().Scripts) do
    local evidence = items.Script(path)
    check('every source page readable', evidence and evidence.Path == path and #evidence.SHA256 == 64 and type(evidence.Text) == 'string')
end
local band = items.Get(15761)
check('override declaration', band.Overrides and band.Overrides[1].Callback == 'onItemUse')
check('module source evidence', items.Script(band.Overrides[1].Path).Text:find('5400', 1, true))
local model = items.Tooltip(12306, { Name = { 'Kite Shield' }, Description = { 'Client-only description' } })
check('presentation separate from authority', model.Name == 'Kite Shield' and model.ClientDescription == 'Client-only description' and model.Server.Equipment.jobs == 192 and #model.Warnings >= 2)
check('nil missing tooltip/script', items.Tooltip(65536) == nil and items.Script('../bad') == nil)
for _, id in ipairs(ids) do check('tooltip model for every definition', items.Tooltip(id).Server.Id == id) end
items.Clear()
check('clear reloads', items.Get(605).Basic.stackSize == 12)
print('winxi.items: all definitions, Phoenix overrides, food, script evidence, tooltip models and invalid IDs', true)
