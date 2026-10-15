-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_bag_tabs_check.lua
-- In the unified view, a group of more than one bag has tabs under the grid: all of its bags, or one.
local imgui = require('imgui')
local tabs = require('winxi.tabs')
local icons = require('winxi.itemicons')
local function check(label, ok)
    H.print(label, ok)
    assert(ok, label)
end
local o = H.options()
local bars, images, texts = {}, 0, {}
local beginBar = tabs.BeginBar
tabs.BeginBar = function(id, ...) bars[id] = true; return beginBar(id, ...) end
icons.Frame = function() return 123 end
icons.Place = function() return { 0, 0, 1, 1 } end
local draw = imgui.GetWindowDrawList()
function draw:AddImage() images = images + 1 end
imgui.Text = function(t) texts[#texts + 1] = t end
imgui.TextColored = function(_, t) texts[#texts + 1] = t end
H.ret.GetCursorScreenPos, H.ret.GetWindowPos, H.ret.GetWindowSize = { 100, 200 }, { 100, 200 }, { 400, 4000 }
local function frame()
    H.frames(1) -- a tab chosen under the grid is drawn from the next frame
    bars, images, texts = {}, 0, {}
    H.frames(1)
end
local function wrote(t) for _, v in ipairs(texts) do if v == t then return true end end return false end
local sub = '##inv.bags.sub.wardrobe'

H.play(true); H.gil(100)
o.isVisible[1], o.isUnified[1], o.controller[1] = true, true, true
H.bag(0, 30, { { 1 } })
H.bag(8, 30, { { 20001 }, { 20002 }, { 20003 } })
H.bag(10, 30, { { 20011 }, { 20012 } })
H.packet(0x00A); H.frames(10)

H.tab(1); frame()
check('a group of one bag has no tabs under its grid', bars['##inv.bags.sub.bag'] == nil)

H.tab(3); H.tabIn(sub, 1); frame()
check('wardrobes: all of them together to begin with', bars[sub] and images == 5
    and wrote('wardrobe 1 03/30') and wrote('wardrobe 2 02/30'))
H.tabIn(sub, 2); frame()
check('wardrobe 1 alone, with its count alone', images == 3 and wrote('03/30') and not wrote('wardrobe 2 02/30'))
H.tabIn(sub, 3); frame()
check('wardrobe 2 alone, with its count alone', images == 2 and wrote('02/30') and not wrote('wardrobe 1 03/30'))

-- sorting with one bag chosen sorts that bag alone
H.tap(H.Button.X); H.tap(H.Button.A); H.frames(2)
local said = nil
for _, p in ipairs(H.printed) do if p:find('Sorted') then said = p end end
check('sorting with a bag chosen sorts that bag alone', said ~= nil and said:find('Sorted: wardrobe 2.', 1, true) ~= nil)

-- the bag chosen goes, and with it the choice
H.bag(10, 0, {}); H.packet(0x01C); H.frames(10)
H.tabIn(sub, 1); frame()
check('one wardrobe left: no tabs, and all of it shown', bars[sub] == nil and images == 3 and wrote('03/30'))

H.bag(10, 30, { { 20011 }, { 20012 } }); H.packet(0x01C); H.frames(10)
o.isUnified[1] = false; frame()
check('the separate view has no tabs under the grid', bars[sub] == nil and images == 5)
H.unload()
