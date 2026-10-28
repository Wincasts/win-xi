-- Run: luajit tests/tcrossbar_settings_check.lua
-- Smoke-test both settings renderers without Ashita, including all editor tabs and collapsed windows.
package.path = 'forks/addons/tcrossbar/?.lua;' .. package.path
local methods = {
    contains = function(self, v) for _,x in ipairs(self) do if x == v then return true end end return false end,
    append = function(self, v) self[#self + 1] = v end,
}
function T(t) return setmetatable(t or {}, { __index = methods }) end
local calls, labels, colors, widths = {}, {}, 0, 0
local drawWindow = true
local imgui = setmetatable({
    Begin = function() error('settings must use winxi.window') end,
    End = function() error('winxi.window owns End') end,
    BeginTabBar = function() return true end,
    BeginTabItem = function(name) calls[name] = true; return true end,
    BeginCombo = function() return false end,
    BeginChild = function() end,
    Button = function() return false end,
    Checkbox = function() return false end,
    SliderFloat = function() return false end,
    SliderInt = function() return false end,
    ColorEdit4 = function() return false end,
    PushStyleColor = function() colors = colors + 1 end,
    PopStyleColor = function() colors = colors - 1 end,
    GetCursorPosY = function() return 0 end,
    GetCursorPosX = function() return 0 end,
}, { __index = function() return function() end end })
package.preload.imgui = function() return imgui end
local windows = {}
package.preload['winxi.window'] = function() return {
    Settings = 'settings', Full = function(name, open, flags, draw, options)
        assert(open[1] and options.kind == 'settings')
        windows[#windows + 1] = name
        if drawWindow then draw() end
    end,
} end
package.preload['winxi.widgets'] = function() return {
    HeaderColor = { 1, 1, 1, 1 },
    BeginLabels = function() end, Label = function(name) labels[name] = true end,
    Gap = function() end,
    PushControlWidth = function() widths = widths + 1 end,
    PopControlWidth = function() widths = widths - 1 end,
    BeginThemeTab = function() error('Winxi Theme tab must not be shown') end,
} end
package.preload['winxi.theme'] = function() return { Get = function() return {
    SettingsHeaderColor = { 0.4, 0.4, 0.6, 1 }, SettingsTextColor = { 1, 1, 1, 1 },
} end } end
package.preload.d3d8 = function() return { get_device = function() return {} end } end
for _,name in ipairs({ 'gdifonts.encoding', 'state.inventory', 'state.player', 'resources.wsmap' }) do
    package.preload[name] = function() return {} end
end
package.preload.frameborder = function() return { Label = function() return 'None' end } end
package.preload.recasttext = function() return { MinSize = 8, MaxSize = 40 } end
package.preload.scaling = function() return {} end
addon = { name = 'tcrossbar', version = 'test' }
ImGuiTabBarFlags_NoCloseWithMiddleMouseButton = 0
ImGuiCol_Text = 0
ImGuiSliderFlags_AlwaysClamp = 0
gSettings = { Controller = 'test', Controls = { test = {} }, AutoDetectSubjob = true }
gSingleDisplay = { Valid = false }
gDoubleDisplay = { Valid = false }
gController = { Layout = { ButtonMap = {} } }
gBindings = { GetSelectedSubjob = function() return 0 end }
AshitaCore = { GetResourceManager = function() return {} end }
local function State(module)
    for i = 1, 100 do
        local name, value = debug.getupvalue(module.Render, i)
        if name == 'state' then return value end
        if not name then break end
    end
    error('renderer state not found')
end
local editor = require('bindinggui')
local state = State(editor)
state.IsOpen = { true }
state.MacroState, state.MacroButton, state.SelectedIndex = 1, 1, 1
state.Combos = { Scope = T{ 'Global' }, Type = T{ 'Command' }, Action = T{} }
state.Indices = { Scope = 1, Type = 1, Action = 1 }
state.MacroText, state.MacroLabel, state.MacroImage = { '/echo test' }, { 'test' }, { '' }
state.Components, state.CostOverride = {}, { '' }
state.SelectedContext, state.ContextEditors = 1, {}
for _,definition in ipairs(require('bindingcontext').Definitions) do
    state.ContextEditors[definition.Key] = { Enabled = { false }, MacroText = { '' } }
end
editor:Render()
assert(calls['Binding##BindingTab'] and calls['Appearance##AppearanceTab'] and calls['Context##ContextTab'])
assert(labels.Scope and labels['Macro Button'] and labels['Player Context'] and labels['SC Animation'])
-- Reordering the dropdown must not change which storage scope gets saved/deleted.
local attemptBind
for i = 1,100 do
    local name, value = debug.getupvalue(editor.HandleButton, i)
    if name == 'AttemptBind' then attemptBind = value; break end
    if not name then break end
end
assert(attemptBind)
local savedScope
for _,name in ipairs({ 'Global', 'Job', 'Weapon', 'Subjob', 'Palette' }) do
    local scopeName = name
    gBindings['Bind' .. name] = function() savedScope = scopeName; return true end
end
for index,name in ipairs({ 'Global', 'Job', 'Weapon', 'Subjob', 'Palette' }) do
    state.Indices.Scope = index
    state.Combos.Type = T{ 'Command' }
    assert(attemptBind() and savedScope == name)
    state.Combos.Type = T{ 'Empty' }
    assert(attemptBind() and savedScope == name)
end
local config = require('configgui')
local configState = State(config)
configState.IsOpen = { true }
configState.Layouts, configState.Controllers = { 'classic' }, { 'test' }
configState.SingleLayout, configState.DoubleLayout, configState.SelectedController = 1, 1, 1
configState.SingleScale, configState.DoubleScale = { 1 }, { 1 }
config:Render()
assert(#windows == 2 and widths == 0 and colors == 0)
drawWindow = false
editor:Render()
config:Render()
assert(#windows == 4 and widths == 0 and colors == 0)
print('tcrossbar settings: themed binding/config windows, all editor tabs, aligned labels, balanced stacks, collapsed windows and no theme tabs passed')
