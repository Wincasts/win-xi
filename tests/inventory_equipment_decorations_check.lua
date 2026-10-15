-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_equipment_decorations_check.lua
local imgui = require('imgui')
local icons = require('winxi.itemicons')
local text = require('winxi.text')
local function check(text, ok) H.print(text, ok); assert(ok, text) end
local o = H.options()
local e = o.equipment
local borders, markers, washes, tooltip = {}, {}, 0, nil
local reads = 0
local flags = { 0, 0x8000, 0x4000, 0xC000 }
local resourceManager = AshitaCore.GetResourceManager
AshitaCore.GetResourceManager = function(self)
    local manager = resourceManager(self)
    local get = manager.GetItemById
    manager.GetItemById = function(res, id)
        local item = get(res, id)
        reads = reads + 1
        item.Flags = flags[(id - 20101) % 4 + 1]
        return item
    end
    return manager
end
local color = imgui.GetColorU32
imgui.GetColorU32 = function(c, ...)
    if type(c) == 'table' then
        if c[1] == 0.65 and c[2] == 0.65 then return 101 end
        if c[1] == 0.30 and c[2] == 0.65 then return 102 end
        if c[1] == 0.30 and c[2] == 0.85 then return 103 end
        if c[1] == 1.00 and c[2] == 0.75 then return 104 end
    end
    return color(c, ...)
end
icons.Frame = function() return 123 end
icons.Place = function() return { 0, 0, 1, 1 } end
local draw = imgui.GetWindowDrawList()
local rect, gradient = draw.AddRect, draw.AddRectFilledMultiColor
function draw:AddRect(minimum, maximum, tint, rounding, f, thickness)
    if tint >= 101 and tint <= 104 and thickness == 2 then
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
local setTooltip = imgui.SetTooltip
imgui.SetTooltip = function(value) tooltip = value; return setTooltip(value) end
local function frame()
    borders, markers, washes, tooltip = {}, {}, 0, nil
    H.frames(1)
end
H.play(true)
o.isVisible[1], o.fadeInOut[1], o.treasurePool[1] = false, false, false
e.enabled[1] = true
local containers = { 8, 10, 11, 12, 13, 14, 15, 16 }
for n, bag in ipairs(containers) do
    H.bag(bag, 80, { { 20100 + n } })
    H.equip(n - 1, bag, 1)
end
frame()
check('quality borders and wardrobe markers enabled by default', e.qualityBorders[1] and e.wardrobeMarkers[1])
check('only occupied slots receive quality borders', #borders == 8)
check('normal, Rare, Exclusive and Rare/Exclusive colors use resource flags', borders[1][1] == 101
    and borders[2][1] == 102 and borders[3][1] == 103 and borders[4][1] == 104)
check('quality borders inset without increasing square window size', borders[1][2] == 11 and borders[1][3] == 21
    and borders[1][4] == 41 and borders[1][5] == 51)
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
check('decorations independent of slot backgrounds', #borders == 8 and #markers == 8)
e.qualityBorders[1] = false
frame()
check('quality border toggle does not affect wardrobe markers', #borders == 0 and #markers == 8)
e.qualityBorders[1], e.wardrobeMarkers[1] = true, false
frame()
check('wardrobe marker toggle does not affect quality borders', #borders == 8 and #markers == 0)
H.ret.IsWindowHovered, H.ret.GetMousePos = { true }, { 15, 25 }
frame()
check('storage tooltip retained when markers disabled', tooltip and tooltip:find('Stored in: Wardrobe 1', 1, true) ~= nil)
e.wardrobeMarkers[1] = true
H.bag(0, 80, { { 20200 } })
H.equip(0, 0, 1)
frame()
check('inventory equipment receives a quality border but no wardrobe badge', #borders == 8 and #markers == 7)
check('inventory tooltip identifies main inventory', tooltip and tooltip:find('Stored in: Inventory', 1, true) ~= nil)
H.equip(0)
frame()
check('unequipping removes both decorations', #borders == 7 and #markers == 7)
check('empty slot tooltip has no storage location', tooltip == 'Main: Empty')
H.unload()
