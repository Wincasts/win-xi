package.path = 'addons/chatbox/?.lua;' .. package.path
local appearance = require('appearance')
local T = function(t) return t end
local theme = {BackgroundColor={0.1,0.2,0.3,0.8},BorderColor={0.4,0.5,0.6,1},TextColor={1,1,1,1},TitleColor={0.7,0.8,0.9,1}}
local options = appearance.Defaults(T, theme)
assert(not options.log.override[1] and not options.input.override[1], 'Override Colours off to begin with')
assert(options.log.colors.background ~= theme.BackgroundColor and options.input.colors.background ~= options.log.colors.background,
    'saved colours do not alias the theme or the other window')
local target = appearance.Apply({}, options.log)
assert(target.background == nil and target.border == nil and target.textColor == nil and target.titleColor == nil)
options.log.override[1] = true
appearance.Apply(target, options.log)
assert(target.background == options.log.colors.background and target.border == options.log.colors.border
    and target.textColor == options.log.colors.textColor and target.titleColor == options.log.colors.titleColor, 'on: every colour the window\'s own')
assert(appearance.Apply({},options.input).background == nil, 'input follows theme independently')
options.log.override[1] = false
appearance.Apply(target,options.log)
assert(target.background == nil, 'disabling override clears a reused window option')
local bad = {log={override='bad',colors={background={-4,2,0/0,math.huge}}},input=false}
bad = appearance.Repair(bad,T,theme)
assert(not bad.log.override[1] and bad.log.colors.background[1] == 0 and bad.log.colors.background[2] == 1)
assert(bad.log.colors.background[3] == 0.3 and bad.log.colors.background[4] == 0.8)
assert(not bad.input.override[1], 'missing/malformed legacy settings migrate safely')
-- settings from before the switch: an Own Color box for each colour; any on is the switch on, and the boxes are dropped
local old = {log={own={background={true},border={false}},colors={}},input={own={background={false},textColor={false}},colors={}}}
old = appearance.Repair(old,T,theme)
assert(old.log.override[1] == true and old.input.override[1] == false and old.log.own == nil and old.input.own == nil,
    'Own Color boxes become Override Colours: on where any was')
assert(old.log.colors.textColor[1] == 1 and old.input.colors.background[4] == 0.8, 'the colours never chosen the theme\'s')
local saved, picked = 0, {}
local clicked = '##chatbox.appearance.input.override'
package.loaded.imgui = {
    Checkbox=function(id,value) if id == clicked then value[1]=not value[1]; return true end return false end,
    SameLine=function() end, ColorEdit4=function(id) picked[id]=true end,
    IsItemDeactivatedAfterEdit=function() return true end,
    SmallButton=function() return false end, TextDisabled=function() end,
    IsItemHovered=function() return false end,
}
package.loaded['winxi.widgets'] = {Header=function() return true end,Label=function() end}
package.loaded['winxi.tooltip'] = {Hover=function() end}
ImGuiColorEditFlags_NoInputs = 0
appearance.Draw(options,function() saved=saved+1 end)
assert(options.input.override[1] and picked['##chatbox.appearance.input.background'] and picked['##chatbox.appearance.input.textColor']
    and not picked['##chatbox.appearance.input.titleColor'] and not picked['##chatbox.appearance.log.background'] and saved > 0,
    'the switch on shows that window\'s pickers (no Title for the input); the other window\'s stay hidden')
appearance.Draw(options,function() saved=saved+1 end)
assert(not options.input.override[1], 'off again: the colours kept')
assert(options.input.colors.background[4] == 0.8, 'the colours kept while off')
print('Chatbox appearance: Override Colours, defaults, migration, alpha bounds, controls and theme restoration passed')
