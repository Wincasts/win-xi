package.path = 'addons/chatbox/?.lua;' .. package.path
local appearance = require('appearance')
local T = function(t) return t end
local theme = {BackgroundColor={0.1,0.2,0.3,0.8},BorderColor={0.4,0.5,0.6,1},TextColor={1,1,1,1},TitleColor={0.7,0.8,0.9,1}}
local options = appearance.Defaults(T, theme)
assert(not options.log.own.background[1] and not options.input.own.background[1])
assert(options.log.colors.background ~= theme.BackgroundColor and options.input.colors.background ~= options.log.colors.background,
    'saved colours do not alias the theme or the other window')
local target = appearance.Apply({}, options.log)
assert(target.background == nil and target.border == nil and target.textColor == nil and target.titleColor == nil)
options.log.own.background[1],options.log.own.border[1] = true,true
appearance.Apply(target, options.log)
assert(target.background == options.log.colors.background and target.border == options.log.colors.border)
assert(appearance.Apply({},options.input).background == nil, 'input follows theme independently')
options.log.own.background[1] = false
appearance.Apply(target,options.log)
assert(target.background == nil, 'disabling override clears a reused window option')
local bad = {log={own={background='bad'},colors={background={-4,2,0/0,math.huge}}},input=false}
bad = appearance.Repair(bad,T,theme)
assert(not bad.log.own.background[1] and bad.log.colors.background[1] == 0 and bad.log.colors.background[2] == 1)
assert(bad.log.colors.background[3] == 0.3 and bad.log.colors.background[4] == 0.8)
assert(not bad.input.own.border[1], 'missing/malformed legacy settings migrate safely')
local saved, picked = 0, {}
local clicked = 'Own Color##chatbox.appearance.input.background'
package.loaded.imgui = {
    Checkbox=function(id,value) if id == clicked then value[1]=true; return true end return false end,
    SameLine=function() end, ColorEdit4=function(id) picked[id]=true end,
    IsItemDeactivatedAfterEdit=function() return true end,
    Button=function(id) return id == clicked end, TextDisabled=function() end,
}
package.loaded['winxi.widgets'] = {Header=function() return true end,Label=function() end}
ImGuiColorEditFlags_NoInputs = 0
appearance.Draw(options,function() saved=saved+1 end)
assert(options.input.own.background[1] and picked['##chatbox.appearance.input.background'] and saved > 0)
clicked = 'Follow WinXI Theme##chatbox.appearance.input.reset'
appearance.Draw(options,function() saved=saved+1 end)
assert(not options.input.own.background[1] and options.log.own.border[1], 'reset affects only its own window')
print('Chatbox appearance: independent overrides, defaults, migration, alpha bounds, controls and theme restoration passed')
