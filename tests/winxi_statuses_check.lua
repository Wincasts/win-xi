-- winxi.statuses: the server's status effects, and Harmful, the one list addons tell debuffs by,
-- from the repository's data and, as a released addon has it, without any
package.path = 'addons/libs/?.lua;' .. package.path
AshitaCore = { GetInstallPath = function() return 'nowhere/' end }
local gamedata = require('winxi.gamedata')
local statuses = require('winxi.statuses')

-- without the data: the list as it was
assert(#statuses.Ids() == 0, 'no data where there is none')
local without = {}
for id = 0, 1023 do without[id] = statuses.Harmful(id) end
assert(without[2] and without[4] and without[386] and not without[33] and not without[40], 'the list without data')

-- with it: the server's flags and the shared list, the same statuses on Phoenix
gamedata.Root('addons/libs/winxi/data/')
statuses.Clear()
assert(#statuses.Ids() > 600, 'the server\'s statuses')
assert(statuses.Get(4).Name == 'paralysis' and statuses.Get(4).Element == 'ice', 'a status as the server has it')
for id = 0, 1023 do
    assert(statuses.Harmful(id) == without[id], 'harmful ' .. id .. ' differs with the data')
end
assert(not statuses.Harmful(24), 'a number the server has no status for is not harmful')
print('winxi.statuses: the server\'s statuses, and Harmful the same with the data and without', true)
