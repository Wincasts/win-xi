-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_sort_check.lua
-- A group's bags together (the unified view's all tab) are in the same order whether they were all
-- sorted again or only the bag that changed was, and merged with the others still in order.
local icons = require('winxi.itemicons')
local function check(label, ok)
    H.print(label, ok)
    assert(ok, label)
end
local o = H.options()
local placed = {}
icons.Frame = function() return 123 end
icons.Place = function(id) placed[#placed + 1] = id; return { 0, 0, 1, 1 } end
H.ret.GetContentRegionAvail = { 1000, 1000 }
H.ret.GetWindowPos, H.ret.GetWindowSize = { 10, 20 }, { 400, 40000 } -- every row of the grid in view
H.play(true); H.gil(100)
o.isVisible[1], o.isUnified[1], o.controller[1], o.treasurePool[1] = true, true, false, false
o.gridRows[1] = 30
H.tabIn('##inv.bags.unified', 3) -- the wardrobes, their all tab
-- four wardrobes, their items' ids interleaved, two stacks of one item in different wardrobes
local wardrobes = { 8, 10, 11, 12 }
local function fill(extra)
    for n, bag in ipairs(wardrobes) do
        local items = {}
        for i = 1, 20 do items[i] = { 20000 + i * 4 + n } end
        if n == 2 then items[#items + 1] = { 20009 } end -- the same as the first wardrobe's second
        if extra and n == 3 then items[#items + 1] = { 20001 } end
        H.bag(bag, 80, items)
    end
end
local function shown()
    placed = {}
    H.frames(1)
    local drawn = placed
    placed = {}
    return drawn
end
local function inOrder(list)
    for i = 2, #list do if list[i] < list[i - 1] then return false end end
    return #list > 0
end
fill(false)
H.packet(0x00A); H.frames(10)
local all = shown()
check('all the wardrobes together, in order', #all == 81 and inOrder(all))

-- one wardrobe changes: only it is read and sorted again; the rest are merged with it
fill(true)
H.packetData(0x01F, string.rep('\0', 0x0A) .. string.char(11) .. string.rep('\0', 20))
H.frames(10)
local after = shown()
check('one changed: still in order, with its new item first', #after == 82 and inOrder(after) and after[1] == 20001)

-- the same bags all read again give the same order
H.packet(0x00A); H.frames(10)
local again = shown()
check('the same as all sorted again', table.concat(again, ',') == table.concat(after, ','))
H.unload()
