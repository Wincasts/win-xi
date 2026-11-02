-- Run with: luajit tests/harness.lua winventory addons/winventory/winventory.lua tests/inventory_former_check.lua
-- winventory was inventory up to 1.1, and inv before that: a character's settings are brought over
-- once, from inventory where it has them, otherwise from inv, as the settings are loaded with the
-- character known (winxi.shell's formerName as a list)
local o = H.options()
local legacy = require('winxi.legacy')
local readSettings = legacy.ReadSettings
local saved, asked = {}, {}
legacy.ReadSettings = function(name) asked[#asked + 1] = name; return saved[name] end
local function settle()
    asked = {}
    o.importedFromFormer = false
    H.resettle()
end

saved = { inv = { gridColumns = { 9 } } }
settle()
H.print('only inv: looked for under inventory, then inv, and brought over from inv', asked[1] == 'inventory', asked[2] == 'inv',
    o.gridColumns[1] == 9, o.importedFromFormer == true, H.printed[#H.printed]:find('brought over from inv', 1, true) ~= nil)

saved = { inventory = { gridColumns = { 12 } }, inv = { gridColumns = { 9 } } }
settle()
H.print('both: inventory\'s taken, inv not looked for', #asked == 1, o.gridColumns[1] == 12,
    H.printed[#H.printed]:find('brought over from inventory', 1, true) ~= nil)

asked = {}
o.gridColumns[1] = 7
H.resettle()
H.print('once only', #asked == 0, o.gridColumns[1] == 7)
legacy.ReadSettings = readSettings
