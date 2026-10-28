-- Run: luajit tests/tcrossbar_weapon_check.lua
package.path = 'forks/addons/tcrossbar/?.lua;' .. package.path
local methods = {
    contains = function(self, value) for _,v in ipairs(self) do if v == value then return true end end return false end,
    append = function(self, value) self[#self + 1] = value end,
}
function T(t) return setmetatable(t or {}, { __index = methods }) end
local files, originalOpen = {}, io.open
io.open = function(path)
    local parts = {}
    return { write = function(_, s) parts[#parts + 1] = s end, close = function() files[path] = table.concat(parts) end }
end
function LoadFile_s(path) return files[path] and assert(loadstring(files[path]))() end
ashita = { fs = { exists = function() return false end, create_directory = function() end } }
addon = { name = 'tcrossbar' }
gSettings = { AutoDetectSubjob = false, BindingSubjob = 2 }
gBindingGUI = { GetActive = function() return false end }
local errors = 0
function Error() errors = errors + 1 end
function Message() end
local skill, playerIndex, equipped, itemId = 3, 100, { Index = 0xB05 }, 12345
local resourceMissing = false
local inventory = {
    GetEquippedItem = function(_, slot) assert(slot == 0); return equipped end,
    GetContainerItem = function(_, bag, index) assert(bag == 11 and index == 5); return { Id = itemId } end,
}
AshitaCore = {
    GetInstallPath = function() return '/fake/' end,
    GetMemoryManager = function() return {
        GetParty = function() return { GetMemberTargetIndex = function() return playerIndex end } end,
        GetInventory = function() return inventory end,
    } end,
    GetResourceManager = function() return {
        GetItemById = function(_, id) assert(id == 12345); if not resourceMissing then return { Skill = skill } end end,
        GetString = function(_, _, job) return 'JOB' .. job end,
    } end,
}
local weapon = require('weaponcontext')
assert(weapon.Current() == 3 and weapon.Label(3) == 'Sword')
for i = 1,12 do skill = i; assert(weapon.Current() == i and weapon.Label(i) ~= 'Unavailable') end
skill = 26
assert(weapon.Current() == 0) -- unsupported non-melee skill
skill = 3
resourceMissing = true
assert(weapon.Current() == 0)
resourceMissing = false
itemId = 0
assert(weapon.Current() == 0)
itemId = 65535
assert(weapon.Current() == 0)
itemId = 12345
equipped = nil
assert(weapon.Current() == 0)
equipped = { Index = 0 }
assert(weapon.Current() == 1) -- unarmed is hand-to-hand
playerIndex = 0
assert(weapon.Current() == 0)
playerIndex, equipped = 100, { Index = 0xB05 }
local latest, updates = nil, 0
gSingleDisplay = { UpdateBindings = function(_, value) latest = value; updates = updates + 1 end }
local b = require('bindings')
local function binding(label)
    return { ActionType = 'Command', Macro = T{ '/echo ' .. label }, Label = label, Image = '' }
end
b:LoadDefaults('Tester', 123, 3)
b:BindGlobal('shared', binding('global'))
b:BindJob('shared', binding('job'))
b:BindPalette('shared', binding('palette'))
b:BindSubjob('shared', binding('subjob'))
b:BindGlobal('globalOnly', binding('globalOnly'))
b:BindJob('jobOnly', binding('jobOnly'))
b:BindPalette('paletteOnly', binding('paletteOnly'))
b:BindSubjob('subOnly', binding('subOnly'))
assert(latest.shared.Label == 'subjob')
local sword = binding('Sword WS')
sword.Overrides = { Resting = { Enabled = true, Macro = T{ '/heal off' } } }
assert(b:BindWeapon('shared', sword))
assert(latest.shared.Label == 'Sword WS' and latest.shared.Scope == 5)
assert(latest.subOnly.Scope == 4 and latest.paletteOnly.Scope == 3 and latest.jobOnly.Scope == 2 and latest.globalOnly.Scope == 1)
-- Automatic detection refreshes the display only on a type change, on a 100ms poll.
local originalClock, now = os.clock, 100
os.clock = function() return now end
skill = 2
b:CheckWeapon()
assert(latest.shared.Label == 'subjob')
assert(b:BindWeapon('shared', binding('Dagger WS')))
local count = updates
now = now + 1
b:CheckWeapon()
assert(updates == count) -- same weapon skill does not rebuild displays
skill = 3
now = now + 1
b:CheckWeapon()
assert(latest.shared.Label == 'Sword WS')
-- Keep the original weapon category when saving a draft after changing equipment.
assert(b:BindWeapon('draft', binding('Sword draft'), 3))
assert(latest.draft.Label == 'Sword draft')
skill = 2
now = now + 1
b:CheckWeapon()
assert(latest.draft == nil and latest.shared.Label == 'Dagger WS')
assert(b:BindWeapon('draft', binding('Edited Sword draft'), 3))
assert(latest.draft == nil)
-- Save/reload includes weapon bindings and nested player-context overrides.
skill = 3
b:LoadDefaults('Tester', 123, 3)
assert(latest.shared.Label == 'Sword WS' and latest.shared.Overrides.Resting.Macro[1] == '/heal off')
assert(latest.draft.Label == 'Edited Sword draft')
assert(b:BindWeapon('shared', nil))
assert(latest.shared.Label == 'subjob')
b:LoadDefaults('Tester', 123, 3)
assert(latest.shared.Label == 'subjob')
-- Categories are local to the palette and main job.
b:HandleCommand({ '/tc', 'palette', 'add', 'Other' })
assert(latest.draft == nil)
b:BindWeapon('shared', binding('Other Sword WS'))
b:PreviousPalette()
assert(latest.shared.Label == 'subjob' and latest.draft.Label == 'Edited Sword draft')
b:LoadDefaults('Tester', 123, 4)
assert(latest.shared.Label == 'global' and latest.draft == nil)
-- Invalid equipment falls back safely and cannot create a category.
playerIndex = 0
now = now + 1
b:CheckWeapon()
assert(not b:BindWeapon('shared', binding('invalid')) and errors == 1)
os.clock, io.open = originalClock, originalOpen
print('tcrossbar weapon: skill detection, wardrobes, unarmed/invalid equipment, precedence, polling, draft category, persistence, deletion and isolation passed')
