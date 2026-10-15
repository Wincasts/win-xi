-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_equipment_performance_check.lua
-- This measures Lua + mocked ImGui, NOT actual Ashita/GPU frame time.
local imgui = require('imgui')
local icons = require('winxi.itemicons')
local equipment = require('equipment')
local function check(text, ok) H.print(text, ok); assert(ok, text) end
local o = H.options()
local e = o.equipment
local inv = AshitaCore:GetMemoryManager():GetInventory()
local order = { 0, 1, 2, 3, 4, 9, 11, 12, 5, 6, 13, 14, 15, 10, 7, 8 }
local measures, packs, resources, reads, atlasFrames = 0, 0, 0, 0, 0
local seen, seenIndex, ammoText = {}, 0, nil
local imageCount, splitBatch, equipmentBeforeBagScan = 0, false, true
local resourceManager = AshitaCore.GetResourceManager
AshitaCore.GetResourceManager = function(self)
    local res = resourceManager(self)
    local get = res.GetItemById
    res.GetItemById = function(...) resources = resources + 1; return get(...) end
    return res
end
local measure, color = imgui.CalcTextSize, imgui.GetColorU32
imgui.CalcTextSize = function(...)
    if debug.getinfo(2, 'n').name == 'Measure' then measures = measures + 1 end
    return measure(...)
end
imgui.GetColorU32 = function(...)
    if debug.getinfo(2, 'n').name == 'Colors' then packs = packs + 1 end
    return color(...)
end
local getItem = inv.GetContainerItem
local pendingEquipmentRead = false
inv.GetContainerItem = function(self, bag, slot)
    if pendingEquipmentRead then
        reads = reads + 1
        pendingEquipmentRead = false
    elseif seenIndex == 0 then
        equipmentBeforeBagScan = false
    end
    return getItem(self, bag, slot)
end
local getEquipped = inv.GetEquippedItem
inv.GetEquippedItem = function(...)
    pendingEquipmentRead = true
    return getEquipped(...)
end
icons.Frame = function() atlasFrames = atlasFrames + 1; return 123 end
icons.Place = function(id)
    seenIndex = seenIndex % 16 + 1
    seen[seenIndex] = id
    return { 0, 0, 1, 1 }
end
local draw = imgui.GetWindowDrawList()
local image, rect, text = draw.AddImage, draw.AddRect, draw.AddText
function draw:AddImage(...)
    imageCount = imageCount + 1
    return image(self, ...)
end
function draw:AddRect(...)
    if imageCount > 0 and imageCount < 16 then splitBatch = true end
    return rect(self, ...)
end
function draw:AddText(pos, tint, value, ...)
    if imageCount > 0 and imageCount < 16 then splitBatch = true end
    if value:match('^%d+$') then ammoText = value end
    return text(self, pos, tint, value, ...)
end
local function frame()
    seenIndex, imageCount, ammoText = 0, 0, nil
    H.frames(1)
end
local sets = { {}, {} }
for n = 1, 16 do
    sets[1][n] = { 30000 + n, 1 }
    sets[2][n] = { 31000 + n, 1 }
end
sets[1][4], sets[2][4] = { 88, 99 }, { 89, 50 }
H.bag(8, 80, sets[1]); H.bag(10, 80, sets[2])
local function equipSet(set)
    local bag = set == 1 and 8 or 10
    for slot = 0, 15 do H.equip(slot, bag, slot + 1) end
end
local function matches(set)
    if seenIndex ~= 16 then return false end
    for n, slot in ipairs(order) do
        if seen[n] ~= sets[set][slot + 1][1] then return false end
    end
    return ammoText == tostring(sets[set][4][2])
end
H.play(true)
o.isVisible[1], o.fadeInOut[1], o.treasurePool[1], e.enabled[1] = false, false, false, true
equipSet(1); frame()
check('equipment read and icon requests precede bag polling', equipmentBeforeBagScan)
check('all sixteen icons and ammo correct on first frame', matches(1))
equipSet(2); frame()
check('entire replacement set appears on the very next frame', matches(2))
check('icons form one uninterrupted atlas batch', not splitBatch and imageCount == 16)
local knownResources, knownMeasures, knownPacks = resources, measures, packs
local startReads, startEquipped = reads, H.calls.GetEquippedItem
for i = 1, 120 do
    local set = i % 2 + 1
    equipSet(set)
    -- A continual inventory packet burst never delays the equipment monitor.
    H.packet(0x01F)
    frame()
    assert(matches(set), 'stale equipment on rapid swap frame ' .. i)
end
check('120 consecutive full-set changes displayed without packet debounce', true)
check('rapid swaps read exactly sixteen live indices and sixteen live items per frame',
    reads - startReads == 120 * 16 and H.calls.GetEquippedItem - startEquipped == 120 * 16)
check('known gear metadata reused across rapid swaps', resources == knownResources)
check('fixed labels and badges not remeasured during swaps', measures - knownMeasures == 119) -- changing ammo only; first frame repeats set 2
check('unchanged opacity reuses packed decoration colors', packs == knownPacks)
-- Same packed index, new container contents: an index-only cache would show stale gear/counts.
equipSet(1)
sets[1][1], sets[1][4] = { 32001, 1 }, { 90, 37 }
H.bag(8, 80, sets[1]); frame()
check('same indices with different item ids update immediately', matches(1))
sets[1][4][2] = 36
H.bag(8, 80, sets[1]); frame()
check('same ammo id/index with new count updates immediately', ammoText == '36')
frame()
knownMeasures, knownPacks, knownResources = measures, packs, resources
startReads, startEquipped = reads, H.calls.GetEquippedItem
for _ = 1, 60 do frame() end
check('steady full monitor performs zero decoration text measurements', measures == knownMeasures)
check('steady full monitor performs zero resource lookups or color repacks', resources == knownResources and packs == knownPacks)
check('presentation caching never throttles live gear polling', reads - startReads == 60 * 16
    and H.calls.GetEquippedItem - startEquipped == 60 * 16)
e.scale[1] = 1.5
frame()
check('slot-label measurements invalidate on scale change', measures > knownMeasures)
knownMeasures = measures
local fontSize = H.ret.GetFontSize
H.ret.GetFontSize = { 18 }
frame()
check('badge and ammo measurements invalidate on font size change', measures > knownMeasures)
H.ret.GetFontSize = fontSize
knownPacks = packs
e.opacity[1] = 0.5
frame()
check('color cache invalidates on opacity change', packs > knownPacks)
-- Disabled and hidden monitors must not poll; reopening immediately reads the new set.
e.enabled[1] = false
startEquipped = H.calls.GetEquippedItem
frame()
check('disabled monitor performs zero equipment reads', H.calls.GetEquippedItem == startEquipped)
e.enabled[1] = true
H.play(false); frame()
check('hidden monitor performs zero equipment reads', H.calls.GetEquippedItem == startEquipped)
H.play(true); equipSet(2); frame()
check('reopening immediately reads latest equipment', matches(2))
-- Emulate a cold atlas with its real 48-new-icon/frame budget and a large bag competing
-- for uploads. All 16 current equipment icons must be requested before inventory icons.
local frameIcons, placeIcon = icons.Frame, icons.Place
local requests = {}
icons.Frame = function() requests = {}; return frameIcons() end
icons.Place = function(id)
    requests[#requests + 1] = id
    if #requests > 48 then return nil end
    return placeIcon(id)
end
local bagItems = {}
for i = 1, 80 do bagItems[i] = { 40000 + i } end
H.bag(0, 80, bagItems); H.gil(5000)
o.isVisible[1] = true
H.ret.GetWindowPos, H.ret.GetWindowSize = { 0, 0 }, { 1000, 1000 }
local beforeAtlas = atlasFrames
frame()
local first = true
for n, slot in ipairs(order) do first = first and requests[n] == sets[2][slot + 1][1] end
check('cold equipment icons get upload priority over a full bag', first and #requests > 48)
check('equipment and inventory still share exactly one atlas frame', atlasFrames == beforeAtlas + 1)
o.isVisible[1] = false
icons.Frame, icons.Place = frameIcons, placeIcon
-- Bounded CPU/allocation sample of the equipment path itself with all visual features on.
-- Reset frame bookkeeping each iteration; no growing event log in the timed section.
for _ = 1, 100 do equipment.Draw(o, 123) end
collectgarbage('collect'); collectgarbage('stop')
local memory = collectgarbage('count')
local start = H.cpuClock()
local iterations = 1000
for _ = 1, iterations do
    seenIndex, imageCount = 0, 0
    equipment.Draw(o, 123)
end
local elapsed = H.cpuClock() - start
local allocated = (collectgarbage('count') - memory) / iterations
collectgarbage('restart'); collectgarbage('collect')
H.print(('equipment mocked CPU sample: %.3f ms/frame; %.2f KiB/frame; 16 live slot reads/frame'):format(elapsed * 1000 / iterations, allocated))
H.unload()
