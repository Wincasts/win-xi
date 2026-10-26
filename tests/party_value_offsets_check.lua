-- Advanced: Value Positioning: the party's HP, MP and TP offsets on the Party tab (kept in style, as they
-- were), and the target's own HP % and distance offsets on the Target tab; settings from before take the
-- party's TP offset for the target once, so its figures stay where they were.
H.load()
local options=require('options')
local function Section(tabName, label)
    for _, tab in ipairs(options.Tabs) do
        if tab.name == tabName then
            local found, keys = false, {}
            for _, entry in ipairs(tab.entries) do
                if entry.kind == 'header' then
                    if found then break end
                    found = entry.label == label
                elseif found then
                    keys[#keys + 1] = entry.section .. '.' .. entry.key
                end
            end
            return found and table.concat(keys, ' ') or nil
        end
    end
end
assert(Section('Style', 'Advanced: Value Positioning') == nil, 'gone from Style')
assert(Section('Party', 'Advanced: Value Positioning') == 'style.hpOffset style.mpOffset style.tpOffset', 'on Party, kept in style')
assert(Section('Target', 'Advanced: Value Positioning') == 'target.hpOffset target.distanceOffset', 'the target\'s own')

-- settings from before: the target's figures take the party's TP offset, once
local saved = H.options()
saved.target.ownOffsets = nil
saved.style.tpOffset[1], saved.style.tpOffset[2] = 5, 7
options.Complete(saved)
assert(saved.target.hpOffset[1] == 0 and saved.target.hpOffset[2] == 7, 'HP % level with the old TP offset')
assert(saved.target.distanceOffset[1] == 5 and saved.target.distanceOffset[2] == 7, 'distance where the TP offset put it')
assert(saved.target.ownOffsets == true)
saved.target.hpOffset[1], saved.style.tpOffset[2] = 9, -4
options.Complete(saved)
assert(saved.target.hpOffset[1] == 9 and saved.target.hpOffset[2] == 7, 'not done again')

-- drawn: a target's figures move with its own offsets and not the party's TP offset
local frames, draw = require('frames'), require('draw')
local texts = {}
local text = draw.Text
draw.Text = function(x, y, color, words) texts[words] = { x, y } end
local line = { { name = 'Mob', hp = -1, hpp = 75, hpText = '75%', tp = 0, tpText = '8.0m', isInZone = true, plainHp = true } }
local function Target()
    texts = {}
    local style = options.Style(saved)
    style.showTp = true
    frames.Draw(line, 'target', nil, style)
    return texts['75%'], texts['8.0m']
end
saved.target.hpOffset[1], saved.target.hpOffset[2] = 0, 0
saved.target.distanceOffset[1], saved.target.distanceOffset[2] = 0, 0
local hp, distance = Target()
assert(hp and distance, 'both figures drawn')
saved.style.tpOffset[1], saved.style.tpOffset[2] = 20, 20
saved.style.hpOffset[1], saved.style.hpOffset[2] = 20, 20
local hp2, distance2 = Target()
assert(hp2[1] == hp[1] and hp2[2] == hp[2] and distance2[1] == distance[1] and distance2[2] == distance[2],
    'the party\'s offsets leave the target alone')
saved.target.distanceOffset[1], saved.target.distanceOffset[2] = 10, 10
local hp3, distance3 = Target()
assert(hp3[1] == hp[1] and hp3[2] == hp[2], 'distance offset leaves the HP % alone')
assert(distance3[1] > distance[1] and distance3[2] > distance[2], 'distance moved right and down')
saved.target.hpOffset[1], saved.target.hpOffset[2] = -10, -10
local hp4 = Target()
assert(hp4[1] < hp[1] and hp4[2] < hp[2], 'HP % moved left and up')
draw.Text = text

-- the sliders reach across a whole frame, either way, and past a line's top and bottom
local imgui, widgets, config = require('imgui'), require('winxi.widgets'), require('config')
local header, slider = widgets.Header, imgui.SliderInt
local ranges = {}
widgets.Header = function() return true end
imgui.SliderInt = function(id, box, min, max) ranges[id] = { min, max }; return false end
for _, tab in ipairs(config.Tabs) do
    if tab.name == 'Party' or tab.name == 'Target' then tab.draw(saved) end
end
widgets.Header, imgui.SliderInt = header, slider
for _, id in ipairs({ 'target.hpOffset', 'target.distanceOffset', 'style.hpOffset', 'style.mpOffset', 'style.tpOffset' }) do
    local x, y = ranges['##xiframes.' .. id .. 'X'], ranges['##xiframes.' .. id .. 'Y']
    assert(x and x[1] == -140 and x[2] == 140, id .. ' across: ' .. tostring(x and x[2]))
    assert(y and y[1] == -40 and y[2] == 40, id .. ' down')
end
local frameUnits = 163.2 / options.Unit
assert(140 >= frameUnits, 'across is at least a frame\'s width')
H.print('Value positioning: party offsets on Party, the target\'s own on Target, taken once from the TP offset, drawn apart, reaching across a whole frame', true)
