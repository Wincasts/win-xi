-- The theme's tab style: nothing for Plain, the sheen kept inside the tab's rounded top, an image's
-- edges and repeated middle across the whole tab and stretched only down it, an image that will not
-- load drawing nothing, a tab narrower than its edges, and tabs.Begin
H.load()
local imgui = require('imgui')
local theme = require('winxi.theme')
local tabs = require('winxi.tabs')
local look = theme.Get()

-- every choice is one the generator made, or one drawn
for _, choice in ipairs(theme.TabStyles) do
    if choice.key ~= 'plain' and choice.key ~= 'sheen' then
        local image = io.open(('addons/libs/winxi/assets/tabs/%s.png'):format(choice.key), 'rb')
        assert(image, 'no image for ' .. choice.key)
        image:close()
    end
end
assert(look.TabStyle == 'sheen', 'Sheen to start with, as inventory had')

local list, counts, rects, images = {}, {}, {}, {}
for _, name in ipairs({ 'AddRectFilled', 'AddImage' }) do
    list[name] = function(_, ...)
        counts[name] = (counts[name] or 0) + 1
        if name == 'AddImage' then
            local _, a, b, uvA, uvB = ...
            images[#images + 1] = { a[1], a[2], b[1], b[2], uvA[1], uvA[2], uvB[1], uvB[2] }
        else
            local a, b = ...
            rects[#rects + 1] = { a[1], a[2], b[1], b[2] }
        end
    end
end
local getList, getStyle, rectMin, rectMax = imgui.GetWindowDrawList, imgui.GetStyle, imgui.GetItemRectMin, imgui.GetItemRectMax
imgui.GetWindowDrawList = function() return list end
imgui.GetStyle = function() return { TabRounding = 4, Alpha = 1 } end
-- a tab 150 wide and 20 high
imgui.GetItemRectMin = function() return 10, 20 end
imgui.GetItemRectMax = function() return 160, 40 end
local function Reset() counts, rects, images = {}, {}, {} end

look.TabStyle = 'plain'; Reset(); tabs.Draw()
assert(next(counts) == nil, 'plain: nothing')

look.TabStyle = 'sheen'; Reset(); tabs.Draw()
assert(counts.AddRectFilled > 4 and counts.AddImage == nil)
for _, r in ipairs(rects) do
    assert(r[1] >= 10 and r[3] <= 160 and r[2] >= 20 and r[4] <= 40, 'inside the tab')
end
assert(rects[1][1] > 10 and rects[1][3] < 160, 'the top row is pulled in by the rounded corners')

local load = tabs.Load
tabs.Load = function(name) return name ~= 'satin' and 88 or false end
for _, style in ipairs({ 'glass', 'bevel', 'brushed', 'grain', 'lined' }) do
    look.TabStyle = style; Reset(); tabs.Draw()
    assert(counts.AddImage ~= nil and counts.AddRectFilled == nil, style)
    -- the band under the rounded rows covers the tab from edge to edge, without a gap or an overlap
    local covered, top = 0, nil
    for _, image in ipairs(images) do
        assert(image[1] >= 10 and image[3] <= 160 and image[2] >= 20 and image[4] <= 40, 'inside the tab')
        -- across, a pixel of the tab is a pixel of the image: never stretched that way
        assert(math.abs((image[3] - image[1]) / 64 - (image[7] - image[5])) < 1e-9, 'not stretched across')
        if image[4] == 40 then covered = covered + image[3] - image[1]; top = image[6] end
    end
    assert(covered == 150, 'the straight part covered once')
    assert(math.abs(top - 4 / 20) < 1e-9, 'stretched down the tab')
    -- the edges are the image's own first and last columns
    local first, last = images[1], images[#images]
    assert(last[3] == 160 and last[7] == 1 and first[5] >= 0)
end
-- an image that will not load: nothing
look.TabStyle = 'satin'; Reset(); tabs.Draw()
assert(next(counts) == nil)

-- a tab narrower than its two edges is still covered just once
look.TabStyle = 'glass'; Reset()
imgui.GetItemRectMax = function() return 16, 40 end
tabs.Draw()
local covered = 0
for _, image in ipairs(images) do if image[4] == 40 then covered = covered + image[3] - image[1] end end
assert(covered == 6, 'narrow tab covered once')
imgui.GetItemRectMax = function() return 160, 40 end

-- tabs.Begin begins the tab and draws over it
local begun
local beginTab = imgui.BeginTabItem
imgui.BeginTabItem = function(label, open, flags) begun = { label, open, flags }; return true end
look.TabStyle = 'bevel'; Reset()
assert(tabs.Begin('bag', 7) == true and begun[1] == 'bag' and begun[2] == 0 and begun[3] == 7 and counts.AddImage ~= nil)
imgui.BeginTabItem = beginTab

look.TabStyle, tabs.Load = 'sheen', load
imgui.GetWindowDrawList, imgui.GetStyle, imgui.GetItemRectMin, imgui.GetItemRectMax = getList, getStyle, rectMin, rectMax
H.print('tabs: plain draws nothing, sheen inside the rounded top, images edge to edge and only stretched down, missing image, narrow tab, Begin', true)
