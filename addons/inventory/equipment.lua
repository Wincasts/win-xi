-- Live equipment monitor, inspired by the functionality of references/equipmon.
-- Uses Winxi windows and the shared icon atlas rather than separate D3D textures/assets.
-- Attached (the default) it sits under the inventory window, its left edge in line with the
-- window's, as the treasure pool does beside it; detached in the settings, it is a window of its own
-- that can be moved. Either way /inv toggle shows and hides it with the inventory, unless it is
-- pinned: then it stays, and attached, with the inventory hidden, it takes the inventory's place.
local bit = require('bit')
local imgui = require('imgui')
local window = require('winxi.window')
local style = require('winxi.style')
local widgets = require('winxi.widgets')
local tooltip = require('winxi.tooltip')
local itemicons = require('winxi.itemicons')
local text = require('winxi.text')
local fade = require('winxi.fade')

local equipment = {}
local windowName = 'winxi.inventory.equipment'
-- The game's equipment screen order, not numeric slot order.
local slots = {
    { 0, 'Main' }, { 1, 'Sub' }, { 2, 'Range' }, { 3, 'Ammo' },
    { 4, 'Head' }, { 9, 'Neck' }, { 11, 'Left Ear' }, { 12, 'Right Ear' },
    { 5, 'Body' }, { 6, 'Hands' }, { 13, 'Left Ring' }, { 14, 'Right Ring' },
    { 15, 'Back' }, { 10, 'Waist' }, { 7, 'Legs' }, { 8, 'Feet' },
}
local encumbered = 0
local positionSettings = nil
local itemInfo = function() return nil end -- inventory's item cache, handed over by SetItemInfo
local minimum, maximum, uvMinimum, uvMaximum = {}, {}, {}, {}
local corner1, corner2, corner3, corner4 = {}, {}, {}, {} -- a bevel's four corners
local gridSize = { 0, 0 }
local white, blocked = { 1, 1, 1, 1 }, { 1, 0.2, 0.2, 0.8 }
local slotLabels = {
    'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Neck', 'L.Ear', 'R.Ear',
    'Body', 'Hands', 'L.Ring', 'R.Ring', 'Back', 'Waist', 'Legs', 'Feet',
}
-- A slot as the game's equipment menu draws it: a flat lavender-grey face sunk into the window,
-- its top and left edges in shadow, its right edge lit and its bottom edge a little less so, the
-- edges meeting on the diagonal, inside a thin dark rim. The slot's name is pale lettering with a
-- darker line under it. All of this is drawn beneath the icons.
local backdropColors = {
    { 0.055, 0.047, 0.145, 1 }, -- 1 rim
    { 0.463, 0.459, 0.565, 1 }, -- 2 face
    { 0.267, 0.263, 0.361, 1 }, -- 3 top edge
    { 0.290, 0.286, 0.384, 1 }, -- 4 left edge
    { 0.620, 0.616, 0.714, 1 }, -- 5 right edge
    { 0.522, 0.518, 0.624, 1 }, -- 6 bottom edge
    { 0.769, 0.761, 0.871, 1 }, -- 7 lettering
    { 0.518, 0.506, 0.620, 1 }, -- 8 lettering's shadow
}
local backdropTints = {}
local transparent = { 0, 0, 0, 0 }
local open = { true }
local windowStyle = { shadow = false, title = 'Equipment' }
local placed = { 0, 0 }
local attachedRect = { shown = false, 0, 0, 0, 0 } -- attached and showing: its window, { x, y, width, height }
-- High-quality gear has a white border, as the game gives it; anything else has none
local hqColor = { 1, 1, 1, 1 }
local wardrobeNumbers = { [8] = 1, [10] = 2, [11] = 3, [12] = 4, [13] = 5, [14] = 6, [15] = 7, [16] = 8 }
-- A wardrobe's mark, as the game's: its number in white, edged in black, in the top-right corner,
-- over a wash of the wardrobe's colour that is strongest along the top and right edges and fades
-- towards the middle of the slot. 1 to 3 are the game's colours; 4 to 8 are this addon's own.
local wardrobeLabels = { '1', '2', '3', '4', '5', '6', '7', '8' }
local wardrobeColors = {
    { 0.18, 0.18, 0.71 }, -- 1 blue
    { 0.71, 0.71, 0.00 }, -- 2 yellow
    { 0.18, 0.71, 0.18 }, -- 3 green
    { 0.75, 0.16, 0.16 }, -- 4 red
    { 0.50, 0.20, 0.72 }, -- 5 purple
    { 0.10, 0.62, 0.70 }, -- 6 teal
    { 0.82, 0.45, 0.08 }, -- 7 orange
    { 0.80, 0.30, 0.58 }, -- 8 pink
}
local markStrong, markWash, markClear = {}, {}, {} -- each wardrobe's colour, packed: edges, wash, faded out
local markColor = { 0, 0, 0, 0 }
local packed = {}
local labelMetrics, badgeMetrics, ammoMetrics = {}, {}, {}
local frameOptions, frameSheet, frameScale, frameSize, framePitch

-- Cache only presentation data. Equipped indices, item ids and counts are ALWAYS read live.
local function Measure(cache, key, text, font, size)
    if cache.font ~= font or cache.size ~= size then
        cache.font, cache.size, cache.values = font, size, {}
    end
    local entry = cache.values[key]
    if entry == nil then entry = {}; cache.values[key] = entry end
    if entry.text ~= text then
        entry.text = text
        entry.width, entry.height = imgui.CalcTextSize(text)
    end
    return entry.width, entry.height
end

local function Colors(alpha)
    if packed.alpha == alpha then return end
    packed.alpha = alpha
    packed.tint, packed.cross = imgui.GetColorU32(white), imgui.GetColorU32(blocked)
    packed.outline = imgui.GetColorU32(text.OutlineColor)
    for i, color in ipairs(backdropColors) do backdropTints[i] = imgui.GetColorU32(color) end
    packed.hq = imgui.GetColorU32(hqColor)
    for i, color in ipairs(wardrobeColors) do
        markColor[1], markColor[2], markColor[3] = color[1], color[2], color[3]
        markColor[4] = 1; markStrong[i] = imgui.GetColorU32(markColor)
        markColor[4] = 0.9; markWash[i] = imgui.GetColorU32(markColor)
        markColor[4] = 0; markClear[i] = imgui.GetColorU32(markColor)
    end
end

function equipment.Reset()
    encumbered = 0
    positionSettings = nil
    labelMetrics, badgeMetrics, ammoMetrics = {}, {}, {}
    for _, slot in ipairs(slots) do slot.ammoCount, slot.ammoText = nil, nil end
end

ashita.events.register('packet_in', 'inv_equipment_packet', function(e)
    if e.id == 0x00A or e.id == 0x00B then
        -- A new area clears only the encumbrance; item info and text sizes stay good.
        encumbered = 0
    elseif e.id == 0x001B then
        -- Jobs Update: a little-endian 32-bit equipment-slot mask at offset 0x60.
        local data = e.data_modified or e.data
        if type(data) == 'string' and #data >= 0x64 then
            local a, b, c, d = data:byte(0x61, 0x64)
            encumbered = a + b * 256 + c * 65536 + d * 16777216
        end
    end
end)

-- What is known of an item (inventory's Info: shortName, stackMax, isHQ), false or nil if unknown
function equipment.SetItemInfo(lookup)
    itemInfo = lookup
end

local function Equipped(inv, slot)
    local entry = inv:GetEquippedItem(slot)
    if entry == nil or entry.Index == 0 then return nil end
    local index = entry.Index
    local container = bit.band(bit.rshift(index, 8), 0xFF)
    local item = inv:GetContainerItem(container, bit.band(index, 0xFF))
    if item == nil or item.Id == nil or item.Id <= 0 or item.Id == 65535 then return nil end
    return item, container
end

local function Quad(draw, x1, y1, x2, y2, x3, y3, x4, y4, color)
    corner1[1], corner1[2], corner2[1], corner2[2] = x1, y1, x2, y2
    corner3[1], corner3[2], corner4[1], corner4[2] = x3, y3, x4, y4
    draw:AddQuadFilled(corner1, corner2, corner3, corner4, color)
end

local function DrawSlotBackdrop(draw, left, top, size, bevel, label, font, fontSize)
    minimum[1], minimum[2], maximum[1], maximum[2] = left, top, left + size, top + size
    draw:AddRectFilled(minimum, maximum, backdropTints[2])
    draw:AddRect(minimum, maximum, backdropTints[1], 0.0)
    -- the edges, inside the rim, as four quads that meet on the diagonals
    local l, t, r, b = left + 1, top + 1, left + size - 1, top + size - 1
    local il, it, ir, ib = l + bevel, t + bevel, r - bevel, b - bevel
    Quad(draw, l, t, r, t, ir, it, il, it, backdropTints[3]) -- top
    Quad(draw, l, t, il, it, il, ib, l, b, backdropTints[4]) -- left
    Quad(draw, r, t, r, b, ir, ib, ir, it, backdropTints[5]) -- right
    Quad(draw, l, b, il, ib, ir, ib, r, b, backdropTints[6]) -- bottom
    local width, height = Measure(labelMetrics, label, label, font, fontSize)
    local clipped = width > size or height > size
    if clipped then draw:PushClipRect(minimum, maximum, true) end
    uvMinimum[1], uvMinimum[2] = left + math.floor((size - width) / 2), top + math.floor((size - height) / 2) + 1
    draw:AddText(uvMinimum, backdropTints[8], label)
    uvMinimum[2] = uvMinimum[2] - 1
    draw:AddText(uvMinimum, backdropTints[7], label)
    if clipped then draw:PopClipRect() end
end

-- A wardrobe's mark over the top-right corner of a slot, over its icon
local function DrawWardrobeMark(draw, left, top, size, wardrobe, font, fontSize, scale)
    local strong, wash, clear = markStrong[wardrobe], markWash[wardrobe], markClear[wardrobe]
    local right = left + size - 1
    local reach, edge = size * 0.7, math.max(2, math.floor(2 * scale + 0.5))
    -- the wash: a corner of the slot, fading from the corner out
    minimum[1], minimum[2], maximum[1], maximum[2] = right - reach, top + 1, right, top + 1 + reach
    draw:AddRectFilledMultiColor(minimum, maximum, clear, wash, clear, clear)
    -- the edges, strong in the corner and fading along the top and down the right
    minimum[1], minimum[2], maximum[1], maximum[2] = right - reach, top + 1, right, top + 1 + edge
    draw:AddRectFilledMultiColor(minimum, maximum, clear, strong, strong, clear)
    minimum[1], minimum[2], maximum[1], maximum[2] = right - edge, top + 1, right, top + 1 + reach
    draw:AddRectFilledMultiColor(minimum, maximum, strong, strong, clear, clear)
    local label = wardrobeLabels[wardrobe]
    local width = Measure(badgeMetrics, wardrobe, label, font, fontSize)
    text.Packed(draw, right - width - math.floor(2 * scale + 0.5), top + math.floor(2 * scale + 0.5),
        packed.tint, label, 1, packed.outline)
end

local function DrawContent()
    local o, sheet, scale, size, pitch = frameOptions, frameSheet, frameScale, frameSize, framePitch
    local x, y = imgui.GetCursorScreenPos()
    imgui.Dummy(gridSize)
    local draw = imgui.GetWindowDrawList()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    -- Snapshot every slot before doing decorative work. Do not retain live memory pointers,
    -- debounce equipment packets, or skip reads just because a packed index is unchanged:
    -- its container item id/count can change underneath it during rapid gear swaps.
    for _, slot in ipairs(slots) do
        local item, container = Equipped(inv, slot[1])
        slot.id, slot.count, slot.container = item and item.Id, item and item.Count, container
    end
    Colors(imgui.GetStyle().Alpha or windowStyle.alpha)
    local tint, cross = packed.tint, packed.cross
    if o.slotBackgrounds[1] then
        imgui.PushFont(nil, 9 * scale)
        local font = imgui.GetFont()
        local bevel = math.max(2, math.floor(3 * scale + 0.5))
        for i, label in ipairs(slotLabels) do
            DrawSlotBackdrop(draw, x + (i - 1) % 4 * pitch,
                y + math.floor((i - 1) / 4) * pitch, size, bevel, label, font, 9 * scale)
        end
        imgui.PopFont()
    end
    -- All atlas icons together: borders/badges/text no longer split the icon draw batch.
    for i, slot in ipairs(slots) do
        slot.info = slot.id and itemInfo(slot.id) or nil
        if slot.id ~= nil and sheet ~= nil then
            local uv = itemicons.Place(slot.id)
            if uv ~= nil then
                local left, top = x + (i - 1) % 4 * pitch, y + math.floor((i - 1) / 4) * pitch
                minimum[1], minimum[2], maximum[1], maximum[2] = left, top, left + size, top + size
                uvMinimum[1], uvMinimum[2], uvMaximum[1], uvMaximum[2] = uv[1], uv[2], uv[3], uv[4]
                draw:AddImage(sheet, minimum, maximum, uvMinimum, uvMaximum, tint)
            end
        end
    end
    if o.wardrobeMarkers[1] then
        imgui.PushFont(nil, 10 * scale)
        local font = imgui.GetFont()
        for i, slot in ipairs(slots) do
            local wardrobe = slot.id ~= nil and wardrobeNumbers[slot.container]
            if wardrobe then
                DrawWardrobeMark(draw, x + (i - 1) % 4 * pitch, y + math.floor((i - 1) / 4) * pitch,
                    size, wardrobe, font, 10 * scale, scale)
            end
        end
        imgui.PopFont()
    end
    local font, fontSize = imgui.GetFont(), imgui.GetFontSize()
    local hovered = imgui.IsWindowHovered()
    local mx, my = imgui.GetMousePos()
    for i, slot in ipairs(slots) do
        local left, top = x + (i - 1) % 4 * pitch, y + math.floor((i - 1) / 4) * pitch
        minimum[1], minimum[2], maximum[1], maximum[2] = left, top, left + size, top + size
        local info, wardrobe = slot.info, wardrobeNumbers[slot.container]
        if info ~= nil and info.isHQ and o.qualityBorders[1] then
            uvMinimum[1], uvMinimum[2], uvMaximum[1], uvMaximum[2] = left + 1, top + 1, left + size - 1, top + size - 1
            draw:AddRect(uvMinimum, uvMaximum, packed.hq, 0.0, 0, 2)
        end
        if o.showEncumbrance[1] and bit.band(encumbered, bit.lshift(1, slot[1])) ~= 0 then
            draw:AddLine(minimum, maximum, cross, 2)
            uvMinimum[1], uvMinimum[2], uvMaximum[1], uvMaximum[2] = left + size, top, left, top + size
            draw:AddLine(uvMinimum, uvMaximum, cross, 2)
        end
        if slot[1] == 3 and o.showAmmoCount[1] and info ~= nil and info.stackMax > 1 then
            if slot.ammoCount ~= slot.count then
                slot.ammoCount, slot.ammoText = slot.count, tostring(slot.count)
            end
            local width, height = Measure(ammoMetrics, 1, slot.ammoText, font, fontSize)
            uvMinimum[1], uvMinimum[2] = left + size - width - 1, top + size - height
            draw:AddText(uvMinimum, tint, slot.ammoText)
        end
        if hovered and mx ~= nil and my ~= nil and mx >= left and mx < left + size and my >= top and my < top + size then
            local text = slot[2] .. ': ' .. (info and info.shortName or 'Empty')
            if slot.id ~= nil then
                text = text .. '\nStored in: ' .. (wardrobe and ('Wardrobe ' .. wardrobe) or 'Inventory')
            end
            if bit.band(encumbered, bit.lshift(1, slot[1])) ~= 0 then text = text .. '\nEncumbered' end
            imgui.SetTooltip(text)
        end
    end
    if o.detached[1] then
        o.pos[1], o.pos[2] = imgui.GetWindowPos()
    else
        local rect = attachedRect
        rect[1], rect[2] = imgui.GetWindowPos()
        rect[3], rect[4] = imgui.GetWindowSize()
        rect.shown = true
    end
end

-- Once a frame. invShown is whether the inventory window is to be shown; the monitor is shown with
-- it, or pinned without it. at is where the monitor goes attached ({ x, y }, or nil before the
-- inventory has a place). sheet is the icon atlas, or what gives it, asked for only once the monitor
-- is to be drawn
function equipment.Draw(options, sheet, at, invShown)
    local o = options.equipment
    attachedRect.shown = false
    if not o.enabled[1] then return end
    local detached = o.detached[1]
    if not detached and at == nil then return end
    local wanted = invShown or o.pinned[1]
    local shown = wanted and 1 or 0
    if options.fadeInOut[1] then
        shown = fade.Presence(windowName, wanted)
    end
    if shown <= 0.01 then return end
    local alpha = math.max(0.125, math.min(1, o.opacity[1])) * shown
    if type(sheet) == 'function' then sheet = sheet() end
    frameOptions, frameSheet = o, sheet
    frameScale = math.max(0.5, math.min(3, o.scale[1]))
    frameSize = 32 * frameScale
    framePitch = frameSize + math.max(0, math.min(20, o.spacing[1]))
    gridSize[1], gridSize[2] = frameSize + framePitch * 3, frameSize + framePitch * 3
    local flags = style.TitlelessFlags()
    if detached then
        -- Restore per-character positioning even when ImGui remembers the old window.
        imgui.SetNextWindowPos(o.pos, positionSettings ~= o.pos and ImGuiCond_Always or ImGuiCond_FirstUseEver)
        positionSettings = o.pos
        if o.lockMovement[1] then flags = bit.bor(flags, ImGuiWindowFlags_NoMove) end
    else
        placed[1], placed[2] = at[1], at[2]
        imgui.SetNextWindowPos(placed, ImGuiCond_Always)
        positionSettings = nil -- detached again, it goes back where it was
        flags = bit.bor(flags, ImGuiWindowFlags_NoMove)
    end
    if not o.background[1] then flags = bit.bor(flags, ImGuiWindowFlags_NoBackground) end
    windowStyle.alpha = alpha
    windowStyle.background = not o.background[1] and transparent or nil
    window.Full(windowName, open, flags, DrawContent, windowStyle)
end

-- Attached and showing: where the monitor's window is ({ x, y, width, height }), as of the last time it
-- was drawn, so that what goes under or beside it can go there; otherwise nil
function equipment.Rect()
    return attachedRect.shown and attachedRect or nil
end

-- Its tab of the settings, laid out as the treasure pool's: what turns it on, whether it is attached to
-- the inventory window, its pin and where it is; then how it looks, and what its slots show
function equipment.DrawSettings(options)
    local o = options.equipment
    if widgets.Header('Equipment Monitor', true) then
        widgets.Label('Enable')
        imgui.Checkbox('##inv.equipment.enabled', o.enabled)
        tooltip.Hover('The gear worn in each of the sixteen slots, as the game\'s equipment menu lays it out.')
        if not o.enabled[1] then return end
        widgets.Label('Detach From Inventory')
        imgui.Checkbox('##inv.equipment.detached', o.detached)
        tooltip.Hover('Attached, the monitor sits under the inventory window, in line with its left edge.\nDetached, it is a window of its own that can be moved.\nEither way /inv toggle shows and hides it with the inventory, unless it is pinned.')
        widgets.Label('Pin Equipment')
        imgui.Checkbox('##inv.equipment.pinned', o.pinned)
        tooltip.Hover('Keeps the monitor on screen when /inv toggle hides the inventory.\nAttached, it then takes the inventory window\'s place, at its top-left corner.')
        if o.detached[1] then
            widgets.Label('Position')
            imgui.SetNextItemWidth(widgets.NumberWidth(2))
            if imgui.InputInt2('##inv.equipment.pos', o.pos) then imgui.SetWindowPos(windowName, o.pos) end
            widgets.Label('Lock Drag to Move')
            imgui.Checkbox('##inv.equipment.lock', o.lockMovement)
            tooltip.Hover('Prevent dragging the monitor. The Position fields can still move it.')
        end
    end
    if not o.enabled[1] then return end

    if widgets.Header('Display') then
        widgets.Label('Scale')
        imgui.SliderFloat('##inv.equipment.scale', o.scale, 0.5, 3, '%.2fx')
        tooltip.Hover('How large the slots are: 1 is the game\'s 32 pixels.')
        widgets.Label('Spacing')
        imgui.SliderFloat('##inv.equipment.spacing', o.spacing, 0, 20, '%.0f px')
        tooltip.Hover('The gap between slots, in pixels.')
        widgets.Label('Opacity')
        imgui.SliderFloat('##inv.equipment.opacity', o.opacity, 0.125, 1, '%.2f')
        tooltip.Hover('How opaque the whole monitor is, from 0.125 to 1.')
        widgets.Label('Window Background')
        imgui.Checkbox('##inv.equipment.background', o.background)
        tooltip.Hover('The monitor\'s window behind the slots; off, the slots float over the game.')
    end

    if widgets.Header('Slots') then
        widgets.Label('Slot Backgrounds')
        imgui.Checkbox('##inv.equipment.slots', o.slotBackgrounds)
        tooltip.Hover('Draw each slot as the game\'s equipment menu does: a sunken lavender tile with its name, beneath the icon.')
        widgets.Label('Quality Borders')
        imgui.Checkbox('##inv.equipment.quality', o.qualityBorders)
        tooltip.Hover('A white border around high-quality gear, as the game draws it; other gear has none. An item is high quality when its name ends in +1, +2 or +3.')
        widgets.Label('Wardrobe Markers')
        imgui.Checkbox('##inv.equipment.wardrobe', o.wardrobeMarkers)
        tooltip.Hover('Mark gear kept in a wardrobe as the game does: the wardrobe\'s number in the top-right corner, over a wash of its colour. Gear in the inventory has no mark.')
        widgets.Label('Show Encumbrance')
        imgui.Checkbox('##inv.equipment.encumbrance', o.showEncumbrance)
        tooltip.Hover('A red cross over each slot that encumbrance has locked.')
        widgets.Label('Show Ammo Count')
        imgui.Checkbox('##inv.equipment.ammo', o.showAmmoCount)
        tooltip.Hover('How many are left of stacking ammunition, in the corner of the Ammo slot.')
    end
end

return equipment
