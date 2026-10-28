-- Run: luajit tests/tcrossbar_context_check.lua
package.path = 'forks/addons/tcrossbar/?.lua;' .. package.path
local context = require('bindingcontext')
local normal, alternate = { '/target <stnpc>' }, { '/attack <stnpc>', '/wait 0.2', '/echo switched' }
local binding = { Macro = normal, Overrides = { Engaged = { Enabled = true, Macro = alternate } } }
assert(context.ResolveMacro(nil, {})[1] == nil)
assert(context.ResolveMacro({ Macro = normal }, { Engaged = true }) == normal)
assert(context.ResolveMacro(binding, { Engaged = false }) == normal)
assert(context.ResolveMacro(binding, { Engaged = true }) == alternate)
binding.Overrides.Engaged.Enabled = false
assert(context.ResolveMacro(binding, { Engaged = true }) == normal)
binding.Overrides.Engaged.Enabled = true
binding.Overrides.Engaged.Macro = {}
assert(context.ResolveMacro(binding, { Engaged = true }) == normal)
binding.Overrides.Engaged.Macro = alternate
-- Each additional status has an independent macro and enable toggle.
for _,definition in ipairs(context.Definitions) do
    local macro = { '/echo ' .. definition.Key }
    binding.Overrides[definition.Key] = { Enabled = true, Macro = macro }
    assert(context.ResolveMacro(binding, { [definition.Key] = true }) == macro)
    binding.Overrides[definition.Key].Enabled = false
    assert(context.ResolveMacro(binding, { [definition.Key] = true }) == normal)
    binding.Overrides[definition.Key].Enabled = true
end
binding.Overrides.Engaged.Macro = alternate
local index, status = 123, 1
local queued, sleeps = {}, {}
AshitaCore = {
    GetMemoryManager = function() return {
        GetParty = function() return { GetMemberTargetIndex = function() return index end } end,
        GetEntity = function() return { GetStatus = function(_, i) assert(i == 123); return status end } end,
    } end,
    GetChatManager = function() return { QueueCommand = function(_, _, command) queued[#queued + 1] = command end } end,
}
assert(context.Capture().Engaged)
for _,definition in ipairs(context.Definitions) do
    status = definition.Status
    local captured = context.Capture()
    for _,other in ipairs(context.Definitions) do
        assert(captured[other.Key] == (other.Key == definition.Key))
    end
    assert(context.ResolveMacro(binding, captured) == binding.Overrides[definition.Key].Macro)
end
local function AssertNormal()
    local captured = context.Capture()
    for _,definition in ipairs(context.Definitions) do assert(not captured[definition.Key]) end
    assert(context.ResolveMacro(binding, captured) == normal)
end
for _, value in ipairs({ 2, 3, 4, 85, 999 }) do status = value; AssertNormal() end
status = nil
AssertNormal()
index = 0
AssertNormal()
index = nil
AssertNormal()
index, status = 123, 1
-- Exercise the real activation path without graphics or Ashita's scheduler.
function T(t) return setmetatable(t or {}, { __index = { append = function(self, v) self[#self + 1] = v end } }) end
for _, name in ipairs({ 'cooldown', 'frameborder', 'frameshadow', 'gdifonts.include', 'gloss', 'recasttext',
    'updaters.ability', 'updaters.command', 'updaters.empty', 'updaters.item', 'updaters.spell', 'updaters.trust', 'updaters.weaponskill' }) do
    package.preload[name] = function() return {} end
end
package.preload['d3d8'] = function() return { D3DCOLOR_ARGB = function() return 0 end } end
package.preload['gdifonts.encoding'] = function() return { UTF8_To_ShiftJIS = function(_, v) return v end } end
package.loaded.ffi = { new = function() return {} end }
local pending
local oldMeta = debug.getmetatable(function() end)
debug.setmetatable(function() end, { __index = { bind1 = function(fn, arg)
    return { oncef = function() pending = function() fn(arg) end end }
end } })
coroutine.sleep = function(value) sleeps[#sleeps + 1] = value end
coroutine.sleepf = function(value) sleeps[#sleeps + 1] = value end
local element = require('element')
local slot = setmetatable({ Binding = binding }, { __index = element })
slot:Activate()
-- Changing state or editing the binding after the button press must not alter the pending macro.
status = 0
alternate[1] = '/echo edited'
pending()
assert(#queued == 2 and queued[1] == '/attack <stnpc>' and queued[2] == '/echo switched')
assert(sleeps[1] == 0.2)
queued = {}
slot:Activate()
pending()
assert(#queued == 1 and queued[1] == '/echo Idle')
queued = {}
status = 33
slot:Activate()
status = 1
pending()
assert(#queued == 1 and queued[1] == '/echo Resting')
-- Disable just the resting override; other configured contexts must not take its place.
queued = {}
status = 33
binding.Overrides.Resting.Enabled = false
slot:Activate()
pending()
assert(#queued == 1 and queued[1] == '/target <stnpc>')
debug.setmetatable(function() end, oldMeta)
print('tcrossbar context: legacy fallback, enabled/disabled overrides, empty fallback, idle/engaged/resting detection, activation snapshot and waits passed')
