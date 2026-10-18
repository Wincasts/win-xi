-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_equipment_decorations_check.lua
local imgui = require('imgui')
local icons = require('winxi.itemicons')
local text = require('winxi.text')
local function check(text, ok) H.print(text, ok); assert(ok, text) end
local o = H.options()
local e = o.equipment
local borders, markers, washes, tooltip = {}, {}, 0, nil
local reads = 0
local resourceManager = AshitaCore.GetResourceManager
AshitaCore.GetResourceManager = function(self)
    local manager = resourceManager(self)
    local get = manager.GetItemById
    manager.GetItemById = function(res, id)
        local item = get(res, id)
        reads = reads + 1
        -- every other item is the HQ of its kind, named with +1 as the game names them
        if id % 2 == 0 then item.Name = { 'Item ' .. id .. ' +1' } end
        return item
    end
    return manager
end
icons.Frame = function() return 123 end
icons.Place = function() return { 0, 0, 1, 1 } end
local draw = imgui.GetWindowDrawList()
local rect, gradient = draw.AddRect, draw.AddRectFilledMultiColor
function draw:AddRect(minimum, maximum, tint, rounding, f, thickness)
    if thickness == 2 then
        borders[#borders + 1] = { tint, minimum[1], minimum[2], maximum[1], maximum[2] }
    end
    return rect(self, minimum, maximum, tint, rounding, f, thickness)
end
-- a wardrobe's number is written outlined, by winxi.text, over a wash of the wardrobe's colour
local packedText = text.Packed
text.Packed = function(drawList, x, y, tint, words, ...)
    if words:match('^[1-8]$') then markers[#markers + 1] = { words, x, y } end
    return packedText(drawList, x, y, tint, words, ...)
end
function draw:AddRectFilledMultiColor(...)
    washes = washes + 1
    return gradient(self, ...)
end
local tips = require('winxi.tooltip') -- shown through winxi.tooltip
local showTooltip = tips.Show
tips.Show = function(value) tooltip = value; return showTooltip(value) end
local function frame()
    borders, markers, washes, tooltip = {}, {}, 0, nil
    H.frames(1)
end
H.play(true)
o.isVisible[1], o.fadeInOut[1], o.treasurePool[1] = false, false, false
e.enabled[1] = true
e.detached[1], e.pinned[1] = true, true -- a window of its own, pinned: there with the inventory hidden
local containers = { 8, 10, 11, 12, 13, 14, 15, 16 }
for n, bag in ipairs(containers) do
    H.bag(bag, 80, { { 20100 + n } })
    H.equip(n - 1, bag, 1)
end
check('wardrobe markers on and quality borders off by default', not e.qualityBorders[1] and e.wardrobeMarkers[1])
-- the places below are worked out at the former 4 pixels between slots
e.qualityBorders[1], e.spacing[1] = true, 4
frame()
check('only high-quality gear has a border; other gear has none', #borders == 4)
-- the first HQ item is in Sub, the second slot: 46..78 across, 20..52 down
check('HQ borders inset without increasing square window size', borders[1][2] == 47 and borders[1][3] == 21
    and borders[1][4] == 77 and borders[1][5] == 51)
local names = {}
for _, marker in ipairs(markers) do names[#names + 1] = marker[1] end
-- Drawing order follows equipment slots, so Neck (slot 9) is not part of these eight entries.
check('all eight wardrobe containers numbered as the game numbers them', table.concat(names, ',') == '1,2,3,4,5,6,7,8')
-- the slot is 10..42 across and 20..52 down; the number (7 wide here) sits 2 in from its top-right
check('wardrobe number sits in the top-right corner', markers[1][2] == 32 and markers[1][3] == 22)
check('each wardrobe number has its corner wash and edges', washes == 8 * 3)
local firstReads = reads
frame()
check('quality metadata cached across frames', reads == firstReads)
e.slotBackgrounds[1] = false
frame()
check('decorations independent of slot backgrounds', #borders == 4 and #markers == 8)
e.qualityBorders[1] = false
frame()
check('quality border toggle does not affect wardrobe markers', #borders == 0 and #markers == 8)
e.qualityBorders[1], e.wardrobeMarkers[1] = true, false
frame()
check('wardrobe marker toggle does not affect quality borders', #borders == 4 and #markers == 0)
H.ret.IsWindowHovered, H.ret.GetMousePos = { true }, { 15, 25 }
frame()
check('storage tooltip retained when markers disabled', tooltip and tooltip:find('Stored in: Wardrobe 1', 1, true) ~= nil)
e.wardrobeMarkers[1] = true
H.bag(0, 80, { { 20200 } })
H.equip(0, 0, 1)
frame()
check('HQ gear from the inventory has its border but no wardrobe mark', #borders == 5 and #markers == 7)
check('inventory tooltip identifies main inventory', tooltip and tooltip:find('Stored in: Inventory', 1, true) ~= nil)
H.equip(0)
frame()
check('unequipping removes both decorations', #borders == 4 and #markers == 7)
check('empty slot tooltip has no storage location', tooltip == 'Main: Empty')
H.unload()
