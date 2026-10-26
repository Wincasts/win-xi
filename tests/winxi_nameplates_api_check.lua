-- winxi.nameplates' smaller calls, each kept for 1.0 though no addon of ours uses it yet, against a block of
-- namehook's stood in for: Count, Name, Text, Has; the categories hidden (Hidden, SetAllHidden, IsHidden,
-- SetHidden) and the target always shown (AlwaysTarget, SetAlwaysTarget), each only its own bits; one entity's
-- name shown or hidden whatever its category (Override, ClearOverrides), only in range; and each harmless
-- with no namehook.
package.path = 'addons/libs/?.lua;' .. package.path
local ffi = require('ffi')

local failures = 0
local function check(ok, what) if not ok then failures = failures + 1; print('FAILED: ' .. what) end end

local loaded, clock = false, 0
os.clock = function() clock = clock + 2; return clock end
local address = 0
AshitaCore = { GetPluginManager = function() return { IsLoaded = function() return loaded end } end }
ashita = { memory = { find = function(_, _, magic) return magic == '4E414D45484F4F4B0000000000000000' and address or 0 end } }

local plates = require('winxi.nameplates')
plates.Module = function() return 1, 0, 0 end

-- with no namehook: nothing, and nothing thrown
check(plates.Count() == 0 and plates.Hidden() == 0 and not plates.AlwaysTarget() and not plates.IsHidden(plates.Category.Player), 'no namehook: none')
plates.SetAllHidden(0xFF); plates.SetHidden(1, true); plates.SetAlwaysTarget(true); plates.Override(5, true); plates.ClearOverrides()

local hook = ffi.new('namehook_t')
hook.Version, hook.Size, hook.NameSize, hook.Hooked = 3, ffi.sizeof(hook), ffi.sizeof('namehook_name_t'), 1
hook.Options = 0x80000000 -- a bit of the plugin's own, never touched by these
address = tonumber(ffi.cast('uintptr_t', ffi.cast('void*', hook)))
loaded = true

hook.Count = 2
ffi.copy(hook.Names[0].Name, 'Lobo')
ffi.copy(hook.Names[0].Text, '\x8e Lobo')
hook.Names[0].Flags = plates.Flag.Wanted + plates.Flag.Target
check(plates.Count() == 2, 'Count')
check(plates.Name(hook.Names[0]) == 'Lobo' and plates.Text(hook.Names[0]) == '\x8e Lobo', 'Name and Text')
check(plates.Has(hook.Names[0], plates.Flag.Target) and not plates.Has(hook.Names[0], plates.Flag.Drawn), 'Has')

plates.SetAllHidden(0x1FF)
check(plates.Hidden() == 0xFF, 'SetAllHidden: the categories alone')
plates.SetAllHidden(0)
plates.SetHidden(plates.Category.Npc, true)
plates.SetHidden(plates.Category.Monster, true)
check(plates.IsHidden(plates.Category.Npc) and plates.IsHidden(plates.Category.Monster) and not plates.IsHidden(plates.Category.Player), 'SetHidden and IsHidden')
plates.SetHidden(plates.Category.Npc, false)
check(plates.Hidden() == plates.Category.Monster, 'SetHidden off: that one alone')

plates.SetAlwaysTarget(true)
check(plates.AlwaysTarget() and hook.Options == 0x80000001, 'SetAlwaysTarget: its bit alone')
plates.SetAlwaysTarget(false)
check(not plates.AlwaysTarget() and hook.Options == 0x80000000, '... and off')

plates.Override(0x401, true); plates.Override(0x402, false); plates.Override(0x403, true); plates.Override(0x403, nil)
check(hook.Override[0x401] == 1 and hook.Override[0x402] == 2 and hook.Override[0x403] == 0, 'Override: shown, hidden, by its category again')
plates.Override(-1, true); plates.Override(0x900, true)
check(hook.Override[0] == 0 and hook.Override[0x8FF] == 0, 'out of range: nothing written')
plates.ClearOverrides()
check(hook.Override[0x401] == 0 and hook.Override[0x402] == 0, 'ClearOverrides')

if failures == 0 then
    print('winxi nameplates api: Count, Name, Text, Has, the categories hidden, the target always shown and one name overridden, each only its own, harmless without namehook passed')
else
    os.exit(1)
end
