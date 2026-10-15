-- Live equipment monitor, inspired by the functionality of references/equipmon.
-- Uses Winxi windows and the shared icon atlas rather than separate D3D textures/assets.
local bit = require('bit')
local imgui = require('imgui')
local window = require('winxi.window')
local style = require('winxi.style')
local widgets = require('winxi.widgets')
local itemicons = require('winxi.itemicons')

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
local gridSize = { 0, 0 }
local white, blocked = { 1, 1, 1, 1 }, { 1, 0.2, 0.2, 0.8 }
local slotLabels = {
    'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Neck', 'L.Ear', 'R.Ear',
    'Body', 'Hands', 'L.Ring', 'R.Ring', 'Back', 'Waist', 'Legs', 'Feet',
}
-- A light, brushed lavender tile like the game's equipment menu. All of this is
-- slot artwork, drawn beneath icons, not a separate child/window background.
local backdropColors = {
    { 0.68, 0.67, 0.78, 0.65 }, -- top
    { 0.32, 0.34, 0.46, 0.75 }, -- bottom
    { 0.91, 0.91, 1.00, 0.40 }, -- bevel / brushed streaks
    { 0.13, 0.14, 0.22, 0.65 }, -- lower bevel / text shadow
    { 0.95, 0.95, 1.00, 0.70 }, -- lettering
}
local backdropTints = {}
local transparent = { 0, 0, 0, 0 }
local open = { true }
local windowStyle = { shadow = false, title = 'Equipment' }
-- Resource Rare/Exclusive flags, not container Flags (which describe slot state).
local qualityColors = {
    { 0.65, 0.65, 0.65, 1 }, -- normal
    { 0.30, 0.65, 1.00, 1 }, -- Rare
    { 0.30, 0.85, 0.45, 1 }, -- Exclusive
    { 1.00, 0.75, 0.20, 1 }, -- Rare/Exclusive
}
local qualityTints = {}
local wardrobeNumbers = { [8] = 1, [10] = 2, [11] = 3, [12] = 4, [13] = 5, [14] = 6, [15] = 7, [16] = 8 }
local wardrobeLabels = { 'W1', 'W2', 'W3', 'W4', 'W5', 'W6', 'W7', 'W8' }
local badgeColor = { 0.08, 0.12, 0.20, 0.95 }
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
    packed.tint, packed.cross, packed.badge = imgui.GetColorU32(white), imgui.GetColorU32(blocked), imgui.GetColorU32(badgeColor)
    for i, color in ipairs(backdropColors) do backdropTints[i] = imgui.GetColorU32(color) end
    for i, color in ipairs(qualityColors) do qualityTints[i] = imgui.GetColorU32(color) end
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

-- What is known of an item (inventory's Info: shortName, stackMax, quality), false or nil if unknown
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

local function DrawSlotBackdrop(draw, left, top, size, label, font, fontSize)
    minimum[1], minimum[2], maximum[1], maximum[2] = left, top, left + size, top + size
    draw:AddRectFilledMultiColor(minimum, maximum,
        backdropTints[1], backdropTints[1], backdropTints[2], backdropTints[2])
    -- Parallel, diagonal highlights suggest the original menu's brushed texture.
    for band = 1, 3 do
        local offset = band * size / 4
        -- Trim the line geometrically instead of adding a clip command per tile.
        local length = math.min(size, offset / 0.45)
        uvMinimum[1], uvMinimum[2], uvMaximum[1], uvMaximum[2] = left, top + offset, left + length, top + offset - length * 0.45
        draw:AddLine(uvMinimum, uvMaximum, backdropTints[3], 1)
    end
    draw:AddRect(minimum, maximum, backdropTints[4], 0.0)
    uvMinimum[1], uvMinimum[2], uvMaximum[1], uvMaximum[2] = left + 1, top + size - 1, left + 1, top + 1
    draw:AddLine(uvMinimum, uvMaximum, backdropTints[3], 1)
    uvMinimum[1], uvMinimum[2], uvMaximum[1], uvMaximum[2] = left + 1, top + 1, left + size - 1, top + 1
    draw:AddLine(uvMinimum, uvMaximum, backdropTints[3], 1)
    local width, height = Measure(labelMetrics, label, label, font, fontSize)
    local clipped = width > size or height > size
    if clipped then draw:PushClipRect(minimum, maximum, true) end
    uvMinimum[1], uvMinimum[2] = left + (size - width) / 2 + 1, top + (size - height) / 2 + 1
    draw:AddText(uvMinimum, backdropTints[4], label)
    uvMinimum[1], uvMinimum[2] = uvMinimum[1] - 1, uvMinimum[2] - 1
    draw:AddText(uvMinimum, backdropTints[5], label)
    if clipped then draw:PopClipRect() end
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
    local tint, cross, badge = packed.tint, packed.cross, packed.badge
    if o.slotBackgrounds[1] then
        imgui.PushFont(nil, 9 * scale)
        local font = imgui.GetFont()
        for i, label in ipairs(slotLabels) do
            DrawSlotBackdrop(draw, x + (i - 1) % 4 * pitch,
                y + math.floor((i - 1) / 4) * pitch, size, label, font, 9 * scale)
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
    local font, fontSize = imgui.GetFont(), imgui.GetFontSize()
    local hovered = imgui.IsWindowHovered()
    local mx, my = imgui.GetMousePos()
    for i, slot in ipairs(slots) do
        local left, top = x + (i - 1) % 4 * pitch, y + math.floor((i - 1) / 4) * pitch
        minimum[1], minimum[2], maximum[1], maximum[2] = left, top, left + size, top + size
        local info, wardrobe = slot.info, wardrobeNumbers[slot.container]
        if info ~= nil and o.qualityBorders[1] then
            uvMinimum[1], uvMinimum[2], uvMaximum[1], uvMaximum[2] = left + 1, top + 1, left + size - 1, top + size - 1
            draw:AddRect(uvMinimum, uvMaximum, qualityTints[info.quality], 0.0, 0, 2)
        end
        if slot.id ~= nil and wardrobe ~= nil and o.wardrobeMarkers[1] then
            local text = wardrobeLabels[wardrobe]
            local width, height = Measure(badgeMetrics, wardrobe, text, font, fontSize)
            uvMinimum[1], uvMinimum[2], uvMaximum[1], uvMaximum[2] = left + size - width - 4, top, left + size, top + height + 2
            draw:AddRectFilled(uvMinimum, uvMaximum, badge)
            uvMinimum[1], uvMinimum[2] = left + size - width - 2, top + 1
            draw:AddText(uvMinimum, tint, text)
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
    o.pos[1], o.pos[2] = imgui.GetWindowPos()
end

function equipment.Draw(options, sheet)
    local o = options.equipment
    if not o.enabled[1] then return end
    frameOptions, frameSheet = o, sheet
    frameScale = math.max(0.5, math.min(3, o.scale[1]))
    frameSize = 32 * frameScale
    framePitch = frameSize + math.max(0, math.min(20, o.spacing[1]))
    gridSize[1], gridSize[2] = frameSize + framePitch * 3, frameSize + framePitch * 3
    -- Restore per-character positioning even when ImGui remembers the old window.
    imgui.SetNextWindowPos(o.pos, positionSettings ~= o.pos and ImGuiCond_Always or ImGuiCond_FirstUseEver)
    positionSettings = o.pos
    local flags = style.TitlelessFlags()
    if o.lockMovement[1] then flags = bit.bor(flags, ImGuiWindowFlags_NoMove) end
    if not o.background[1] then flags = bit.bor(flags, ImGuiWindowFlags_NoBackground) end
    windowStyle.alpha = math.max(0.125, math.min(1, o.opacity[1]))
    windowStyle.background = not o.background[1] and transparent or nil
    window.Full(windowName, open, flags, DrawContent, windowStyle)
end

function equipment.DrawSettings(options)
    local o = options.equipment
    if widgets.Header('Equipment Monitor', true) then
        widgets.Label('Show Equipment')
        imgui.Checkbox('##inv.equipment.enabled', o.enabled)
        widgets.Label('Lock Drag to Move')
        imgui.Checkbox('##inv.equipment.lock', o.lockMovement)
        widgets.Label('Position')
        imgui.SetNextItemWidth(widgets.NumberWidth(2))
        if imgui.InputInt2('##inv.equipment.pos', o.pos) then imgui.SetWindowPos(windowName, o.pos) end
        widgets.Label('Scale')
        imgui.SliderFloat('##inv.equipment.scale', o.scale, 0.5, 3, '%.2f')
        widgets.Label('Spacing')
        imgui.SliderFloat('##inv.equipment.spacing', o.spacing, 0, 20, '%.1f')
        widgets.Label('Opacity')
        imgui.SliderFloat('##inv.equipment.opacity', o.opacity, 0.125, 1, '%.3f')
        widgets.Label('Window Background')
        imgui.Checkbox('##inv.equipment.background', o.background)
    end
    if widgets.Header('Slots') then
        widgets.Label('Slot Backgrounds')
        imgui.Checkbox('##inv.equipment.slots', o.slotBackgrounds)
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Draw game-style beveled slot backdrops and faint slot names beneath equipment icons.')
        end
        widgets.Label('Quality Borders')
        imgui.Checkbox('##inv.equipment.quality', o.qualityBorders)
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Item borders: normal grey, Rare blue, Exclusive green, Rare/Exclusive gold. Uses resource flags, not item-name guesses.')
        end
        widgets.Label('Wardrobe Markers')
        imgui.Checkbox('##inv.equipment.wardrobe', o.wardrobeMarkers)
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Show W1-W8 in the top-right corner for gear stored in a wardrobe. Inventory items have no marker.')
        end
        widgets.Label('Show Encumbrance')
        imgui.Checkbox('##inv.equipment.encumbrance', o.showEncumbrance)
        widgets.Label('Show Ammo Count')
        imgui.Checkbox('##inv.equipment.ammo', o.showAmmoCount)
    end
end

return equipment
