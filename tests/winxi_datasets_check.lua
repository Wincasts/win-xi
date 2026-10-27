-- winxi.gamedata's choice of server: the servers there is data for, the one chosen for every addon
-- (kept in config\addons\winxi\dataset.lua), a set read from the chosen server's folder or else from
-- data's own, and the readers told when the choice changes, here or in another addon
package.path = 'addons/libs/?.lua;' .. package.path
local tmp = os.tmpname(); os.remove(tmp); os.execute('mkdir -p ' .. tmp)
local function write(path, text)
    os.execute(('mkdir -p "%s"'):format((tmp .. '/' .. path):match('^(.*)/')))
    local f = assert(io.open(tmp .. '/' .. path, 'w')); f:write(text); f:close()
end
write('data/datasets.lua', "return { { Key = 'phoenix', Name = 'Phoenix' }, { Key = 'other', Name = 'Other' } }")
write('data/phoenix/manifest.lua', "return { Source = { Name = 'Phoenix' } }")
write('data/phoenix/rules/index.lua', "return { Who = 'phoenix' }")
write('data/other/manifest.lua', "return { Source = { Name = 'Other' } }")
write('data/other/rules/index.lua', "return { Who = 'other' }")
write('data/tooltips/name.lua', "return { Who = 'no server' }")
-- the install, with its config folder; the choice's path takes \ as Windows does, and Linux's io does not
AshitaCore = { GetInstallPath = function() return tmp .. '/' end }
local fs = {}
ashita = { fs = { create_directory = function(path) fs[#fs + 1] = path; os.execute(('mkdir -p "%s"'):format((path:gsub('\\', '/')))) end } }
local realOpen = io.open
io.open = function(path, mode) return realOpen((path:gsub('\\', '/')), mode) end
local realLoad = loadfile
loadfile = function(path) return realLoad((path:gsub('\\', '/'))) end
local now = 0
os.clock = function() return now end

local gamedata = require('winxi.gamedata')
gamedata.Root(tmp .. '/data/')
local listed = gamedata.Datasets()
assert(#listed == 2 and listed[2].Name == 'Other', 'the servers there is data for')
assert(gamedata.Dataset() == 'phoenix', 'none chosen: the first')
assert(gamedata.Read('rules', 'index').Who == 'phoenix', 'a set from the chosen server\'s folder')
assert(gamedata.Read('tooltips', 'name').Who == 'no server', 'a set no server\'s, from data\'s own')
assert(gamedata.Manifest().Source.Name == 'Phoenix', 'the chosen server\'s manifest')

local told = 0
gamedata.OnChange(function() told = told + 1 end)
assert(not gamedata.UseDataset('nowhere'), 'a server there is no data for is not chosen')
assert(gamedata.UseDataset('other') and told == 1, 'chosen, and the readers told')
assert(gamedata.Read('rules', 'index').Who == 'other' and gamedata.Manifest().Source.Name == 'Other', 'read from it now')
local kept = realLoad(tmp .. '/config/addons/winxi/dataset.lua')()
assert(kept.Key == 'other', 'kept for every addon')

-- another addon chooses: seen within a few seconds, and the readers told
write('config/addons/winxi/dataset.lua', "return { Key = 'phoenix' }")
now = 1; assert(gamedata.Dataset() == 'other', 'not read again at once')
now = 6; assert(gamedata.Dataset() == 'phoenix' and told == 2, 'read again, and the readers told')
os.execute('rm -rf ' .. tmp)
print('winxi.gamedata datasets: listed, chosen, kept, read from the chosen and else data\'s own, a change told', true)
