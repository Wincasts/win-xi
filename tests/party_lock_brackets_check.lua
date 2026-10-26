-- Lock-On Brackets: while the player is locked on to the main target, its window has a [ at the left
-- and a ] at the right, in the Bracket Color; not without the lock, not on the sub-target's or the
-- target of target's window, and not with the setting off. The sample shows them, to see them by.
H.load()
local options = H.options()
local draw = require('draw')
options.party.enabled[1], options.pets.enabled[1], options.showConfig[1] = false, false, false
options.fade.Enabled = false
options.target.enabled[1], options.target.showMain[1] = true, true
options.target.showSub[1], options.target.showTot[1] = true, true
assert(options.target.lockBrackets[1] == true, 'brackets on to begin with')
require('winxi.game').IsHidden = function() return false end
local entities = { }
for i = 10, 12 do entities[i] = { Name = 'Target ' .. i, Distance = 64, HPPercent = 80, ServerId = 1000 + i } end
GetEntity = function(index) return entities[index] end
local target = require('target')

-- each rectangle in the Bracket Color, and the windows they are in
local packed, rect = draw.Packed, draw.Rect
local brackets, windows = 0, { }
draw.Packed = function(color, ...) if color == options.target.bracketColor then return 'bracket' end return packed(color, ...) end
-- each must stand wholly outside the window's frame, its own rectangle, touching none of it
local imgui, outside = require('imgui'), true
draw.Rect = function(x1, y1, x2, y2, color)
    if color == 'bracket' then
        brackets = brackets + 1
        local x, y = imgui.GetWindowPos()
        local width, height = imgui.GetWindowSize()
        outside = outside and (x2 <= x or x1 >= x + width or y2 <= y or y1 >= y + height)
    end
    return rect(x1, y1, x2, y2, color)
end
local function Count(main, sub, tot)
    target.Indexes = function() return main, sub, tot end
    brackets = 0
    H.frames(2)
    return brackets / 2 -- two frames
end

options.target.bracketColor = { 0, 1, 0, 1 }
H.lockOn(false)
assert(Count(10, 0, 0) == 0, 'not locked on: no brackets')
H.lockOn(true)
assert(Count(10, 0, 0) == 6, 'locked on: a bracket at each side, a bar and two ticks each')
assert(outside, 'the brackets stand outside the window\'s frame')
assert(Count(10, 11, 12) == 6, 'only the main target\'s window is bracketed')
assert(Count(0, 11, 12) == 0, 'no main target, no brackets')
options.target.lockBrackets[1] = false
assert(Count(10, 0, 0) == 0, 'setting off: no brackets')
options.target.lockBrackets[1] = true
H.lockOn(false)

local found
for _, tab in ipairs(require('options').Tabs) do
    for _, entry in ipairs(tab.entries) do
        if entry.kind == 'header' then found = tab.name .. ' -> ' .. entry.label end
        if entry.key == 'lockBrackets' or entry.key == 'bracketColor' then
            assert(found == 'Target -> Lock-On', entry.key .. ' under Target -> Lock-On')
        end
    end
end
H.print('lock-on brackets: on the main target while locked on, in their colour, under Target -> Lock-On', true)
