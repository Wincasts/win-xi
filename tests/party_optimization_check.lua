H.load()
local o, imgui = H.options(), require('imgui')
local windows, pets, geometry = require('windows'), require('pets'), require('geometry')
local organize = require('winxi.organize')
require('game').StPartyIndex = function() return nil end
require('winxi.game').IsHidden = function() return false end
require('roster').Counts = function() return 0, 0, 0 end
require('target').Indexes = function() return 0, 0, 0 end
local depth, faded, petReads, layouts, reserved = 0, false, 0, 0, nil
organize.BeginFrame = function() depth = depth + 1 end
organize.EndFrame = function() depth = depth - 1 end
windows.UpdateFade = function() end
windows.IsFadedOut = function() return faded end
windows.Lingers = function() return false end
windows.UpdatePositions = function(main, target, alliance)
    assert(main == 600 and target == 60 and alliance == 250)
end
pets.Lines = function() petReads = petReads + 1; return { 1, 2, 3, 4, 5, 6 } end
geometry.Reserve = function(_, _, _, _, count)
    layouts, reserved = layouts + 1, count
    return 600, 60, 250
end
o.automaticPositioning[1], o.party.enabled[1], o.target.enabled[1] = true, false, false
H.frames(100)
assert(petReads == 0 and layouts == 0 and depth == 0, 'disabled groups must skip pet/layout work')
o.party.enabled[1], o.target.enabled[1], faded = true, true, true
H.frames(100)
assert(petReads == 0 and layouts == 0 and depth == 0, 'faded groups must skip pet/layout work')
faded, o.party.enabled[1] = false, false
H.frames(1)
assert(petReads == 0 and layouts == 1 and reserved == o.pets.reserve[1], 'target-only layout must keep configured reservation without polling pets')
o.party.enabled[1] = true
H.frames(1)
assert(petReads == 1 and layouts == 2 and reserved == 6 and depth == 0, 'visible party must restore live reservation')
H.print('disabled/faded frames skip preparation; target-only and six-pet reservations preserved', true)

local details, reads = require('details'), 0
imgui.GetMousePos = function() reads = reads + 1; return 20, 30 end
details.BeginFrame(true)
for _ = 1, 100 do assert(details.Hover(0, 0, 40, 50)) end
assert(reads == 1, 'all hover rectangles must share one mouse read')
details.BeginFrame(false)
assert(not details.Hover(0, 0, 40, 50) and reads == 1, 'disabled hover must clear coordinates without reading')
o.style.hoverDetails[1], o.clickThrough[1] = true, false
H.frames(3)
assert(reads == 4, 'Present samples mouse once per visible frame')
o.clickThrough[1] = true
H.frames(3)
assert(reads == 7, 'clickthrough still samples the mouse once per visible frame, for tooltips')
o.style.hoverDetails[1] = false
H.frames(3)
assert(reads == 7, 'Show Tooltips off: the mouse not read')
H.print('hover coordinates sampled once per enabled frame, with or without clickthrough, never without Show Tooltips', true)

local statuses, perf = require('statuses'), require('perf')
local count, originalCount = 0, perf.Count
perf.Count = function(key) if key == 'status reorderings' then count = count + 1 end end
local a, b = { 40, 7, 4 }, { 33, 1 }
local style = { debuffsFirst = true, priorityStatuses = '4', hiddenStatuses = '7' }
local selectedA, selectedB = statuses.Select(a, style), statuses.Select(b, style)
assert(table.concat(selectedA, ',') == '4,40' and table.concat(selectedB, ',') == '1,33')
for _ = 1, 100 do
    assert(statuses.Select(a, style) == selectedA)
    assert(statuses.Select(b, style) == selectedB)
end
assert(count == 2, 'unchanged lists must not be reordered on each draw')
a[1] = 41
assert(table.concat(statuses.Select(a, style), ',') == '4,41' and count == 3)
a[3] = nil
assert(table.concat(statuses.Select(a, style), ',') == '41' and count == 4)
a[3] = 2
assert(table.concat(statuses.Select(a, style), ',') == '2,41' and count == 5)
style.hiddenStatuses = '2'
assert(table.concat(statuses.Select(a, style), ',') == '7,41' and count == 6)
style.debuffsFirst = false
assert(table.concat(statuses.Select(a, style), ',') == '41,7' and count == 7)
style.priorityStatuses = '7'
assert(table.concat(statuses.Select(a, style), ',') == '7,41' and count == 8)
assert(table.concat(selectedB, ',') == '1,33', 'other cached outputs must not share scratch storage')
perf.Count = originalCount
H.print('status cache: multiple lists, in-place edits, size changes and all ordering controls', true)

