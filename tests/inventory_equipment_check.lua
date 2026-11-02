-- Run with: luajit tests/harness.lua winventory addons/winventory/winventory.lua tests/inventory_equipment_check.lua
local imgui = require('imgui')
local window = require('winxi.window')
local icons = require('winxi.itemicons')
local bit = require('bit')
local function check(text, ok) H.print(text, ok); assert(ok, text) end
local o = H.options()
local e = o.equipment
local full, flags, background, alpha = window.Full, nil, nil, nil
local windows, images, lines, texts, sizes, slots = 0, {}, 0, {}, {}, {}
local title, paddingY = nil, nil
local backdrops, bevels, slotNames, backdropFirst = 0, 0, {}, true
local slotCaptions = { Main = true, Sub = true, Range = true, Ammo = true, Head = true, Neck = true,
    ['L.Ear'] = true, ['R.Ear'] = true, Body = true, Hands = true, ['L.Ring'] = true,
    ['R.Ring'] = true, Back = true, Waist = true, Legs = true, Feet = true }
local setCursorY = imgui.SetCursorPosY
imgui.SetCursorPosY = function(y) paddingY = y; return setCursorY(y) end
local atlasFrames = 0
icons.Frame = function() atlasFrames = atlasFrames + 1; return 123 end
icons.Place = function(id) images[#images + 1] = id; return { 0, 0, 1, 1 } end
-- the place given to the next window, and the one the monitor's was given as it was drawn
local nextPos, monitorAt = nil, nil
do
    local setPos = imgui.SetNextWindowPos
    imgui.SetNextWindowPos = function(pos, cond) nextPos = { pos[1], pos[2], cond }; return setPos(pos, cond) end
end
window.Full = function(name, open, f, draw, style)
    if name == 'winxi.inventory.equipment' then
        monitorAt, nextPos = nextPos, nil
        -- Lock, and being attached, is winxi.window's locked option: counted with the flags
        windows, flags, background, alpha = windows + 1, bit.bor(f, style.locked and ImGuiWindowFlags_NoMove or 0), style.background, style.alpha
        title = style.title
    end
    return full(name, open, f, draw, style)
end
local dummy = imgui.Dummy
imgui.Dummy = function(size) sizes[#sizes + 1] = { size[1], size[2] }; return dummy(size) end
local draw = imgui.GetWindowDrawList()
local addLine, addText, face, quad = draw.AddLine, draw.AddText, draw.AddRectFilled, draw.AddQuadFilled
function draw:AddRectFilled(minimum, maximum, ...)
    if maximum[1] - minimum[1] == 32 and maximum[2] - minimum[2] == 32 then
        backdrops = backdrops + 1
        backdropFirst = backdropFirst and #images == 0
    end
    return face(self, minimum, maximum, ...)
end
function draw:AddQuadFilled(...)
    bevels = bevels + 1
    backdropFirst = backdropFirst and #images == 0
    return quad(self, ...)
end
function draw:AddLine(from, to, color, thickness)
    if thickness == 2 then lines = lines + 1 end -- encumbrance, not backdrop brush strokes
    return addLine(self, from, to, color, thickness)
end
function draw:AddText(pos, color, text, ...)
    if slotCaptions[text] then
        slotNames[#slotNames + 1] = text
        backdropFirst = backdropFirst and #images == 0
    end
    if text:match('^%d+$') then texts[#texts + 1] = text end -- ammo, not frame-title lettering
    return addText(self, pos, color, text, ...)
end
local inv = AshitaCore:GetMemoryManager():GetInventory()
local readEquipped = inv.GetEquippedItem
inv.GetEquippedItem = function(self, slot) slots[#slots + 1] = slot; return readEquipped(self, slot) end
local function frame()
    windows, images, lines, texts, sizes, slots = 0, {}, 0, {}, {}, {}
    paddingY = nil
    backdrops, bevels, slotNames, backdropFirst = 0, 0, {}, true
    H.frames(1)
end
local function hasSize(size)
    for _, v in ipairs(sizes) do if v[1] == size and v[2] == size then return true end end
    return false
end
H.play(true)
o.isVisible[1], o.fadeInOut[1], o.treasurePool[1] = false, false, false
H.bag(8, 80, { { 20100 } }) -- a wardrobe, not the main inventory
H.bag(0, 80, { { 88, 37 } }) -- stackable ammunition
H.equip(0, 8, 1)
H.equip(3, 0, 1)
frame()
check('equipment disabled by default with no polling', not e.enabled[1] and windows == 0 and #slots == 0)
check('hidden inventory and disabled equipment do not prepare the icon atlas', atlasFrames == 0)
e.enabled[1] = true
-- the wardrobe's number is a digit too: its marks are inventory_equipment_decorations_check's
e.wardrobeMarkers[1] = false
-- a window of its own since 1.2: the first time the inventory window is drawn, it is put under it
-- (here at 100, 200, 300 by 150), as it was attached before, and stays where it is put from then on
check('not yet placed to begin with', e.detached[1] == false)
frame()
check('not yet placed: no monitor, no reads and no atlas while the inventory is hidden', windows == 0 and #slots == 0
    and atlasFrames == 0)
o.isVisible[1] = true
frame(); frame()
check('placed under the inventory window, its left edge in line, once', windows == 1 and e.detached[1] == true
    and monitorAt ~= nil and monitorAt[1] == 100 and monitorAt[2] == 200 + 150 + 6)
local freeFlags = flags
e.lockMovement[1] = true
frame()
check('Lock holds it still', flags ~= freeFlags)
e.lockMovement[1] = false
local equipment = require('equipment')
check('nothing of it is attached any more', equipment.Rect == nil)
o.isVisible[1] = false
frame()
check('not pinned: hidden with the inventory', windows == 0)
-- pinned, it stays where it is when the inventory is toggled off
e.pos[1], e.pos[2] = 500, 600
e.pinned[1] = true
frame()
check('pinned: stays, where it was put', windows == 1 and #slots == 16
    and monitorAt ~= nil and monitorAt[1] == 500 and monitorAt[2] == 600)
o.treasurePool[1], o.treasureShowEmpty[1], o.treasurePinned[1] = true, true, true
local poolAt = nil
do
    local setPos = imgui.SetNextWindowPos
    imgui.SetNextWindowPos = function(pos, cond) poolAt = { pos[1], pos[2] }; return setPos(pos, cond) end
    frame()
    imgui.SetNextWindowPos = setPos
end
check('a pinned treasure pool takes the hidden inventory\'s corner', poolAt ~= nil and poolAt[1] == o.pos[1] and poolAt[2] == o.pos[2])
e.pinned[1] = false
o.isVisible[1], o.treasurePool[1], o.treasureShowEmpty[1], o.treasurePinned[1] = false, false, false, false
e.pinned[1] = true
e.pos[1], e.pos[2] = 40, 60
local beforeAtlas = atlasFrames
frame()
check('pinned again: shown with the inventory hidden, where it was put', windows == 1 and #slots == 16
    and monitorAt[1] == 40 and monitorAt[2] == 60)
check('icon atlas advanced only once per addon frame', atlasFrames == beforeAtlas + 1)
check('equipment screen uses reference 4x4 slot order', table.concat(slots, ',') == '0,1,2,3,4,9,11,12,5,6,13,14,15,10,7,8')
check('equipment resolves inventory and wardrobe indices', #images == 2 and images[1] == 20100 and images[2] == 88)
check('default four by four dimensions', hasSize(143))
check('all sixteen slots have game-style sunken faces, each with four bevelled edges', backdrops == 16 and bevels == 64)
check('backdrops include all slot captions with shadows', #slotNames == 32 and slotNames[1] == 'Main' and slotNames[32] == 'Feet')
check('backdrops and captions are drawn beneath equipment icons', backdropFirst)
check('equipment uses Winxi frame title', title == 'Equipment')
check('equipment has no extra top padding so its grid stays square', paddingY == nil)
check('stackable ammo count shown', table.concat(texts, ',') == '37')
local unlocked = flags
e.lockMovement[1], e.background[1], e.opacity[1] = true, false, 0.5
frame()
check('monitor has independent movement lock', flags == bit.bor(unlocked, ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoBackground))
check('transparent background and opacity applied', background and background[4] == 0 and alpha == 0.5)
e.scale[1], e.spacing[1] = 2, 6
frame()
check('scale and spacing resize the equipment grid, the spacing scaled too', hasSize(64 + 3 * (64 + 12)))
e.scale[1], e.spacing[1], e.showEncumbrance[1] = 1, 5, true
-- Main and Feet are encumbered (bits 0 and 8).
H.packetData(0x01B, string.rep('\0', 0x60) .. string.char(1, 1, 0, 0))
frame()
check('encumbrance draws a cross for each blocked slot including empty slots', lines == 4)
e.showEncumbrance[1], e.showAmmoCount[1] = false, false
frame()
check('encumbrance and ammo controls suppress overlays', lines == 0 and #texts == 0)
e.showEncumbrance[1], e.showAmmoCount[1] = true, true
H.packetData(0x01B, 'short')
frame()
check('truncated jobs packet safely ignored', lines == 4)
H.packet(0x00A)
frame()
check('zoning clears stale encumbrance', lines == 0)
H.bag(0, 80, { { 88, 12 } })
frame()
check('ammo count updates without reopening monitor', table.concat(texts, ',') == '12')
H.equip(0)
frame()
check('unequipped items disappear immediately', #images == 1 and images[1] == 88)
H.equip(0, 8, 80)
frame()
check('stale equipped index safely treated as empty', #images == 1)
H.ret.IsWindowHovered, H.ret.GetMousePos = { true }, { 15, 25 }
local tips, tip = require('winxi.tooltip'), nil
tips.Show = function(text) tip = text end -- shown through winxi.tooltip
frame()
check('empty slot tooltip identifies slot', tip == 'Main: Empty')
o.isVisible[1] = true
local beforeBoth = atlasFrames
frame()
check('inventory and equipment together share one icon atlas frame', atlasFrames == beforeBoth + 1)
o.isVisible[1] = false
e.slotBackgrounds[1] = false
frame()
check('Slot Backgrounds toggle removes backdrop art and captions', backdrops == 0 and #slotNames == 0)
H.play(false)
frame()
check('monitor follows shared visibility rules while logged out', windows == 0 and #slots == 0)
H.play(true)
e.enabled[1] = false
frame()
check('disabling monitor stops polling immediately', windows == 0 and #slots == 0)
H.unload()
