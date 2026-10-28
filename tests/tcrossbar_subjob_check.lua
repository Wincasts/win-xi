-- Run: luajit tests/tcrossbar_subjob_check.lua
package.path = 'forks/addons/tcrossbar/?.lua;' .. package.path
local methods = {
    append = function(self, value) self[#self + 1] = value end,
    contains = function(self, value)
        for _, entry in ipairs(self) do if entry == value then return true end end
        return false
    end,
}
function T(value) return setmetatable(value or {}, { __index = methods }) end
local files, writes = {}, {}
local originalOpen = io.open
io.open = function(path, mode)
    assert(mode == 'w')
    local parts = {}
    return {
        write = function(_, value) parts[#parts + 1] = value end,
        close = function() writes[path] = table.concat(parts) end,
    }
end
function LoadFile_s(path)
    if writes[path] then return assert(loadstring(writes[path]))() end
    return files[path]
end
ashita = { fs = { exists = function() return true end, create_directory = function() end } }
addon = { name = 'tcrossbar' }
local detected = 1
local tracked = { SubJob = 1 }
package.loaded['state.player'] = { GetJobData = function() return tracked end }
AshitaCore = {
    GetInstallPath = function() return '/fake/' end,
    GetResourceManager = function() return { GetString = function(_, _, job) return 'JOB' .. job end } end,
    GetMemoryManager = function() return { GetPlayer = function() return { GetSubJob = function() return detected end } end } end,
}
local errorCount = 0
function Error(_) errorCount = errorCount + 1 end
function Message(_) end
gSettings = { AutoDetectSubjob = true, BindingSubjob = 2 }
gBindingGUI = { GetActive = function() return false end }
local latest
gSingleDisplay = { UpdateBindings = function(_, value) latest = value end }
local base = '/fake/config/addons/tcrossbar/Tester_123/bindings/'
local function binding(label)
    return { ActionType = 'Command', Macro = T{ '/echo ' .. label }, Label = label, Image = '' }
end
files[base .. 'globals.lua'] = T{ shared = binding('global'), globalOnly = binding('globalOnly') }
files[base .. 'JOB3.lua'] = T{
    Default = T{ shared = binding('job'), jobOnly = binding('jobOnly') },
    Palettes = T{
        { Name = 'Base', Bindings = T{ shared = binding('palette'), paletteOnly = binding('paletteOnly') } },
        { Name = 'Other', Bindings = T{} },
    },
}
local b = require('bindings')
b:LoadDefaults('Tester', 123, 3)
assert(latest.shared.Label == 'palette' and latest.shared.Scope == 3)
b:BindSubjob('shared', binding('WAR'))
assert(latest.shared.Label == 'WAR' and latest.shared.Scope == 4)
assert(latest.paletteOnly.Scope == 3 and latest.jobOnly.Scope == 2 and latest.globalOnly.Scope == 1)
-- Packet tracker takes precedence over stale memory.
tracked.SubJob = 2
b:Update()
assert(latest.shared.Label == 'palette')
b:BindSubjob('shared', binding('MNK'))
assert(latest.shared.Label == 'MNK')
tracked.SubJob = 1
b:Update()
assert(latest.shared.Label == 'WAR')
-- Manual selection ignores equipped subjob and can be changed immediately.
gSettings.AutoDetectSubjob = false
b:Update()
assert(latest.shared.Label == 'MNK')
gSettings.BindingSubjob = 1
b:Update()
assert(latest.shared.Label == 'WAR')
-- Overrides belong to their palette, not the whole main job.
b:NextPalette()
assert(latest.shared.Label == 'job')
b:BindSubjob('shared', binding('Other WAR'))
b:PreviousPalette()
assert(latest.shared.Label == 'WAR')
-- Serialized files load with both palettes and both subjobs intact.
assert(writes[base .. 'JOB3.lua']:find('Subjobs = T{', 1, true))
b:LoadDefaults('Tester', 123, 3)
assert(latest.shared.Label == 'WAR')
gSettings.BindingSubjob = 2
b:Update()
assert(latest.shared.Label == 'MNK')
b:BindSubjob('shared', nil)
assert(latest.shared.Label == 'palette')
b:LoadDefaults('Tester', 123, 3)
assert(latest.shared.Label == 'palette')
gSettings.BindingSubjob = 0
b:BindSubjob('shared', binding('invalid'))
assert(errorCount == 1 and latest.shared.Label == 'palette')
-- A different main job has no overrides from the first.
b:LoadDefaults('Tester', 123, 4)
assert(latest.shared.Label == 'global')
-- Memory fallback during player tracker initialization.
package.loaded['state.player'] = nil
gSettings.AutoDetectSubjob = true
assert(b:GetSelectedSubjob() == detected)
-- Optional context macros survive every binding scope's writer, including disabled drafts.
local function contextual(enabled)
    local value = binding('context')
    value.Overrides = { Engaged = { Enabled = enabled, Macro = T{ '/attack <stnpc>', '/echo "quoted" \\ text' } } }
    value.Overrides.Idle = { Enabled = not enabled, Macro = T{ '/echo idle', '/wait 0.2' } }
    value.Overrides.Resting = { Enabled = enabled, Macro = T{ '/heal off', '/echo resting' } }
    return value
end
gSettings.AutoDetectSubjob = false
gSettings.BindingSubjob = 2
b:LoadDefaults('Tester', 123, 3)
b:BindGlobal('context', contextual(true))
b:BindJob('context', contextual(false))
b:BindPalette('context', contextual(true))
b:BindSubjob('context', contextual(false))
local savedJob = LoadFile_s(base .. 'JOB3.lua')
local savedGlobal = LoadFile_s(base .. 'globals.lua')
assert(savedGlobal.context.Overrides.Engaged.Enabled == true)
assert(savedJob.Default.context.Overrides.Engaged.Enabled == false)
assert(savedJob.Palettes[1].Bindings.context.Overrides.Engaged.Enabled == true)
assert(savedJob.Palettes[1].Subjobs[2].context.Overrides.Engaged.Enabled == false)
assert(savedJob.Palettes[1].Subjobs[2].context.Overrides.Engaged.Macro[2] == contextual(false).Overrides.Engaged.Macro[2])
b:LoadDefaults('Tester', 123, 3)
assert(latest.context.Overrides.Engaged.Macro[1] == '/attack <stnpc>')
for _,saved in ipairs({ savedGlobal.context, savedJob.Default.context, savedJob.Palettes[1].Bindings.context, savedJob.Palettes[1].Subjobs[2].context }) do
    local overrides = saved.Overrides
    assert(overrides.Idle.Enabled == not overrides.Engaged.Enabled)
    assert(overrides.Resting.Enabled == overrides.Engaged.Enabled)
    assert(overrides.Idle.Macro[1] == '/echo idle' and overrides.Idle.Macro[2] == '/wait 0.2')
    assert(overrides.Resting.Macro[1] == '/heal off' and overrides.Resting.Macro[2] == '/echo resting')
end
assert(latest.context.Overrides.Idle.Enabled == true and latest.context.Overrides.Resting.Enabled == false)
io.open = originalOpen
print('tcrossbar subjob: precedence, detection, manual selection, palette/main-job isolation, persistence, deletion and legacy files passed')
