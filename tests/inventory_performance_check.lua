-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_performance_check.lua
local function check(label, ok)
    H.print(label, ok)
    assert(ok, label)
end
local o = H.options()
local inv = AshitaCore:GetMemoryManager():GetInventory()
local poolReads, resourceReads = 0, 0
local getPool = inv.GetTreasurePoolItem
inv.GetTreasurePoolItem = function(...)
    poolReads = poolReads + 1
    return getPool(...)
end
local getResources = AshitaCore.GetResourceManager
AshitaCore.GetResourceManager = function(...)
    local res = getResources(...)
    local get = res.GetItemById
    res.GetItemById = function(...)
        resourceReads = resourceReads + 1
        return get(...)
    end
    return res
end

H.play(true); H.gil(5000); H.bag(0, 80, { { 1, 2 } })
o.isVisible[1], o.controller[1], o.fadeInOut[1] = true, false, false
o.treasurePool[1], o.treasureDetached[1], o.treasureShowEmpty[1] = true, false, false
H.pool(10); H.frames(8)
local resources = resourceReads
H.frames(5)
check('treasure names cached across frames', resourceReads == resources)

H.pool(0); H.frames(1); H.pool(10); H.frames(1)
check('treasure names cached across slot reuse', resourceReads == resources)

o.isVisible[1] = false
local reads, begun = poolReads, H.calls.Begin
H.frames(8)
check('hidden attached treasure: no reads or windows', poolReads == reads and H.calls.Begin == begun)
o.treasureDetached[1] = true
H.frames(1)
check('hidden detached treasure, not pinned: no reads or windows', poolReads == reads and H.calls.Begin == begun)
o.treasurePinned[1] = true
H.frames(1)
check('pinned detached treasure still polls and draws', poolReads == reads + 10 and H.calls.Begin == begun + 1)
do
    -- detached, Lock holds it still as attached it always is
    local window = require('winxi.window')
    local full, flags = window.Full, nil
    window.Full = function(name, open, f, ...)
        if name == 'winxi.inventory.pool' then flags = f end
        return full(name, open, f, ...)
    end
    H.frames(1)
    local unlocked = flags
    o.treasureLock[1] = true
    H.frames(1)
    check('detached and locked: the pool cannot be dragged', flags == bit.bor(unlocked, ImGuiWindowFlags_NoMove))
    o.treasureLock[1] = false
    H.frames(1)
    check('unlocked again: it can', flags == unlocked)
    window.Full = full
    reads, begun = poolReads, H.calls.Begin
    H.frames(1)
end
o.treasureDetached[1] = false
reads, begun = poolReads, H.calls.Begin
H.frames(1)
check('pinned attached treasure too, with the inventory hidden', poolReads == reads + 10 and H.calls.Begin == begun + 1)
o.treasurePinned[1] = false
o.treasurePool[1] = false
reads = poolReads; H.frames(1)
check('disabled treasure does not poll', poolReads == reads)

-- A hidden attached pool keeps rendering while fading, then stops polling altogether.
o.treasurePool[1], o.treasureDetached[1], o.fadeInOut[1], o.isVisible[1] = true, false, true, true
H.frames(12)
o.isVisible[1] = false
reads, begun = poolReads, H.calls.Begin
H.frames(1)
check('attached treasure continues during fade-out', poolReads == reads + 10 and H.calls.Begin > begun)
H.frames(12); reads = poolReads; H.frames(5)
check('attached treasure stops polling after fade-out', poolReads == reads)
o.isVisible[1] = true; reads = poolReads; H.frames(12)
check('attached treasure resumes on reopen', poolReads > reads)

-- Isolate tab sheen costs (winxi.tabs' Sheen, the theme's to start with) from treasure, shell styling and controller drawing.
o.fadeInOut[1], o.treasurePool[1] = false, false
local imgui = require('imgui')
local style = { Alpha = 1, TabRounding = 0 }
local oldStyle = imgui.GetStyle
imgui.GetStyle = function() return style end
local colors = imgui.GetColorU32
local sheenColors = 0
imgui.GetColorU32 = function(color, ...)
    if debug.getinfo(2, 'n').name == 'DrawSheen' then sheenColors = sheenColors + 1 end
    return colors(color, ...)
end
local drawList = imgui.GetWindowDrawList()
local addRect = drawList.AddRectFilled
local sheenRects = 0
drawList.AddRectFilled = function(...)
    if debug.getinfo(2, 'n').name == 'DrawSheen' then sheenRects = sheenRects + 1 end
    return addRect(...)
end
H.frames(2)
sheenColors, sheenRects = 0, 0
H.frames(1)
check('steady tab sheen reuses packed colors', sheenColors == 0)
check('18-pixel tabs use 24 gradient strips', sheenRects == 24)
style.Alpha = 0.5; H.frames(1)
check('tab sheen repacks colors when fade changes', sheenColors > 0)
sheenColors = 0; H.frames(1)
check('unchanged fade reuses packed colors', sheenColors == 0)
style.TabRounding = 5; H.frames(1)
check('tab sheen rebuilds for changed rounding', sheenColors > 0)
sheenColors = 0
H.ret.GetItemRectMax = { 90, 44 }; H.frames(1)
check('tab sheen rebuilds for changed tab height', sheenColors > 0)
imgui.GetStyle = oldStyle
H.unload()
