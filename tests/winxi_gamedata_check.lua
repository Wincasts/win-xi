-- luajit tests/winxi_gamedata_check.lua
-- winxi.gamedata reads libs\winxi\data's sets, and winxi.mobs an area's monsters and placeholders from
-- them: by index and then name, a part of an area's own tables first, nothing for what is not there.
package.path = 'addons/libs/?.lua;' .. package.path
AshitaCore = { GetInstallPath = function() return 'C:\\ashita\\' end }
local gamedata = require('winxi.gamedata')
local mobs = require('winxi.mobs')
local function check(what, ok) if not ok then error(what, 2) end end

check('the installed folder to begin with', gamedata.Root() == 'C:\\ashita\\\\addons\\libs\\winxi\\data\\' or gamedata.Root():find('addons\\libs\\winxi\\data\\', 1, true))
gamedata.Root('addons/libs/winxi/data/')

local manifest = gamedata.Manifest()
check('manifest: the live branch on GitHub', manifest.Source and manifest.Source.Repository:find('phoenixffxi/Phoenix', 1, true) and manifest.Source.Branch == 'live')
check('manifest: a commit', type(manifest.Source.Commit) == 'string' and #manifest.Source.Commit == 40)
check('manifest: each set and its files', manifest.Sets.mobs.Files > 200 and manifest.Sets.placeholders.Files > 50)

local ronfaure = mobs.Zone(100)
check('West Ronfaure', ronfaure ~= nil and ronfaure.Names['Bomb'] ~= nil)
check('by name', mobs.Find(ronfaure, 99999, 'Bomb').Aggro == true)
local index, indexed = next(ronfaure.Indices)
check('by index first', mobs.Find(ronfaure, index, 'Bomb') == indexed)
check('neither', mobs.Find(ronfaure, 99999, 'Nobody') == nil and mobs.Find(nil, 1, 'Bomb') == nil)
check('a part of an area without tables of its own: the area\'s', mobs.Zone(100, 1100) == nil or mobs.Zone(100, 1100).Names ~= nil)
check('no area', mobs.Zone(0) == nil and mobs.Zone(nil) == nil and mobs.Zone(9999) == nil)

local lots = mobs.Placeholders(100)
check('placeholders: Jaggedy-Eared Jack', lots and lots['Jaggedy-Eared Jack'] and lots['Jaggedy-Eared Jack'][1] == 294)
check('placeholders: none', mobs.Placeholders(0) == nil and mobs.Placeholders(9999) == nil)

check('a set or key that is not a plain name is not read', gamedata.Read('../mobs', 100) == nil and gamedata.Read('mobs', '../100') == nil)
-- a data file is data: it reaches nothing of the addon's
local scratch = os.tmpname(); os.remove(scratch); os.execute('mkdir -p ' .. scratch .. '/probe')
local file = io.open(scratch .. '/probe/1.lua', 'w'); file:write('return { reached = print ~= nil or require ~= nil }'); file:close()
gamedata.Root(scratch .. '/')
check('no globals', gamedata.Read('probe', 1).reached == false)
os.execute('rm -rf ' .. scratch)
print('winxi.gamedata and winxi.mobs: the manifest, an area\'s tables by index and name, placeholders, nothing for what is not there, data reaching nothing', true)
