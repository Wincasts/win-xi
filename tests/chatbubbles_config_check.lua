-- chatbubbles: the settings window in winxi's style, the settings made good, the presets and the
-- commands. Run via tests/harness.lua.
local imgui, widgets = require('imgui'), require('winxi.widgets')
local config, modes, skin = require('config'), require('modes'), require('skin')
local o = H.options()
assert(config.options == o, 'the settings are the shell\'s, kept by config as they are loaded')
assert(#modes.All == 42 and config.Enabled())
local function allows(mode)
    return mode.source == 'text' and config.AllowsNpc(mode.id) or (mode.source ~= 'text' and config.Allows(mode.id))
end
for _, mode in ipairs(modes.All) do assert(allows(mode) == mode.default) end
assert(config.AllowsNpc(150) and config.AllowsNpc(151) and not config.Allows(150) and not config.Allows(255))
assert(o.appearance.background[1] > 0.9 and o.appearance.gameTextColors[1] == true, 'white bubbles to begin with')
assert(o.appearance.skin[1] == 'plain' and o.appearance.border[1] == 'none' and o.appearance.font == ''
    and o.appearance.fontSize[1] == 0 and o.appearance.padding[1] == 10 and o.appearance.arrow[1] == true)

-- the window: its tabs, sections and controls, as the shell draws them
local headers, tabs, ids, marks, labels = {}, {}, {}, 0, {}
local button, checkbox = nil, nil
widgets.Header = function(text) headers[#headers + 1] = text; return true end
local realLabel = widgets.Label
widgets.Label = function(text, ...) labels[#labels + 1] = text; return realLabel(text, ...) end
local originalTab = imgui.BeginTabItem
imgui.BeginTabItem = function(label, ...) tabs[#tabs + 1] = label; return originalTab(label, ...) end
imgui.Checkbox = function(id, value) ids[id] = true; if id == checkbox then value[1] = not value[1]; return true end return false end
imgui.Button = function(id) ids[id] = true; return id == button end
imgui.BeginCombo, imgui.InputInt, imgui.SliderInt, imgui.ColorEdit4 = function(id) ids[id] = true; return false end, function(id) ids[id] = true; return false end, function(id) ids[id] = true; return false end, function(id) ids[id] = true; return false end
imgui.TextDisabled = function(text) if text == '(?)' then marks = marks + 1 end end
local function clear() headers, tabs, ids, marks, labels = {}, {}, {}, 0, {} end
H.command('/chatbubbles'); H.frames(1); clear(); H.frames(1)
assert(table.concat(tabs, '|') == 'Appearance|Chat Modes', table.concat(tabs, '|'))
assert(table.concat(headers, '|') == 'Bubbles|Skin|Text|Behaviour', table.concat(headers, '|'))
assert(ids['##chatbubbles.enabled'] and ids['##chatbubbles.skin'] and ids['##chatbubbles.background'] and ids['##chatbubbles.border']
    and ids['##chatbubbles.gameTextColors'] and ids['##chatbubbles.text'] and ids['##chatbubbles.font'] and ids['##chatbubbles.fontSize']
    and ids['##chatbubbles.padding'] and ids['##chatbubbles.arrow'] and ids['##chatbubbles.onScreen'] and ids['Preview##chatbubbles.preview'])
assert(not ids['##chatbubbles.skinTop'] and not ids['##chatbubbles.borderColor'], 'the parchment\'s and the border\'s colours wait for them')
assert(marks >= 10, 'every control has its help mark')
for _, label in ipairs(labels) do
    for word in label:gmatch('%a+') do assert(word:sub(1, 1):match('%u') or word == 'px', 'Title Case: ' .. label) end
end
H.tab(2); clear(); H.frames(1)
assert(table.concat(headers, '|') == 'Channels|Player Chat|NPC Text', table.concat(headers, '|'))
assert(ids['##chatbubbles.mode.0'] and ids['##chatbubbles.mode.npc:150'] and ids['Enable All##chatbubbles.modes.all'])
H.tab(1)

-- the presets, from their buttons, and Preview
local saves = H.saves()
button = 'Parchment##chatbubbles.preset.parchment'; H.frames(1); button = nil
assert(o.appearance.skin[1] == 'parchment' and o.appearance.border[1] == 'ffxi' and o.appearance.text[1] == skin.Text[1] and H.saves() > saves)
clear(); H.frames(1)
assert(ids['##chatbubbles.skinTop'] and ids['##chatbubbles.skinBottom'] and ids['##chatbubbles.borderColor'] and not ids['##chatbubbles.background'])
button = 'Dark##chatbubbles.preset.dark'; H.frames(1); button = nil
assert(o.appearance.skin[1] == 'plain' and o.appearance.border[1] == 'none' and o.appearance.background[1] < 0.1 and o.appearance.text[1] == 1)
button = 'White##chatbubbles.preset.white'; H.frames(1); button = nil
assert(o.appearance.background[1] == 1 and o.appearance.text[1] == 0.05)
button = 'Preview##chatbubbles.preview'; H.frames(1); button = nil
assert(config.preview[1] == true)
clear(); H.frames(1)
assert(ids['Stop Preview##chatbubbles.preview'])
H.command('/chatbubbles'); H.frames(1)
assert(config.preview[1] == false, 'closing the settings stops the preview')

-- a channel's box, and Enable All / Disable All
H.command('/chatbubbles'); H.tab(2); H.frames(1)
checkbox = '##chatbubbles.mode.3'; H.frames(1); checkbox = nil
assert(config.Allows(3) and not config.Allows(1))
button = 'Disable All##chatbubbles.modes.none'; H.frames(1); button = nil
for _, mode in ipairs(modes.All) do assert(not allows(mode)) end
button = 'Enable All##chatbubbles.modes.all'; H.frames(1); button = nil
for _, mode in ipairs(modes.All) do assert(allows(mode)) end
H.command('/chatbubbles')

-- the settings loaded again, from a file with bad and old values: each made good, the font of 0.93 brought over
o.enabled, o.modes = { 'yes' }, { ['3'] = { true } }
o.appearance = { background = { 2, -1, 0 / 0, 0.5 }, text = false, skin = { 'velvet' }, border = { 'lace' },
    font = { 'arial.ttf' }, fontSize = { 99 }, padding = { -3 }, arrow = { 'on' } }
H.resettle()
assert(config.options == H.options() and config.Enabled() and config.Allows(3) and config.Allows(0), 'Say, missing from the file, gains its default')
assert(config.AllowsNpc(150) and config.AllowsNpc(151), 'old settings gain the NPC defaults')
local a = o.appearance
assert(a.background[1] == 1 and a.background[2] == 0 and a.background[3] == 1 and a.background[4] == 0.5 and a.text[1] == 0.05)
assert(a.skin[1] == 'plain' and a.border[1] == 'none' and a.font == 'arial.ttf' and a.fontSize[1] == 72 and a.padding[1] == 0 and a.arrow[1] == true)
assert(a.gameTextColors[1] == true and a.onScreen[1] == false)

-- the commands: on and off, and a verb that is not one
H.command('/chatbubbles off'); assert(not config.Enabled())
H.command('/chatbubbles on'); assert(config.Enabled())
H.command('/chatbubbles status')
H.print('chatbubbles settings: winxi\'s window, two tabs, Title Case labels with help marks, presets, preview, channels, settled on load and the commands', true)
