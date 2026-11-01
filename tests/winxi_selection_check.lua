-- luajit tests/winxi_selection_check.lua
-- The controller's selection box (winxi.selection): every Selection Style draws, keeps within
-- selection.Room of the thing it is round (the inventory clips round its items by that much), and an
-- unknown style is drawn as Bevel; satin and brushed draw their tab texture, or go on without it.
package.path = 'addons/libs/?.lua;' .. package.path
local look = { SelectionStyle = 'bevel', SelectionColor = { 1, 0.93, 0.72, 1 } }
local themeStub = { Get = function() return look end, Defaults = { SelectionColor = { 1, 0.93, 0.72, 1 } },
    SelectionStyles = {} }
package.loaded['winxi.theme'] = themeStub
local image = 7
package.loaded['winxi.tabs'] = { Image = function() return image end }
local box, drawn, images = nil, 0, 0
local function See(a, b)
    drawn = drawn + 1
    for _, p in ipairs({ a, b }) do
        box.l, box.t = math.min(box.l, p[1]), math.min(box.t, p[2])
        box.r, box.b = math.max(box.r, p[1]), math.max(box.b, p[2])
    end
end
local list = {
    AddRect = function(_, a, b) See(a, b) end, AddRectFilled = function(_, a, b) See(a, b) end,
    AddRectFilledMultiColor = function(_, a, b) See(a, b) end,
    AddImage = function(_, _, a, b) images = images + 1; See(a, b) end,
}
package.loaded.imgui = { GetColorU32 = function() return 1 end }
local selection = require('winxi.selection')

local x1, y1, x2, y2 = 100, 200, 132, 232
local room = selection.Room
for _, key in ipairs({ 'outline', 'glow', 'bevel', 'glass', 'satin', 'brushed', 'nonsense' }) do
    look.SelectionStyle = key
    box, drawn, images = { l = 1e9, t = 1e9, r = -1e9, b = -1e9 }, 0, 0
    selection.Draw(list, x1, y1, x2, y2)
    local inside = box.l >= x1 - room and box.t >= y1 - room and box.r <= x2 + room and box.b <= y2 + room
    print(key, 'drawn', drawn > 0, '| within the room', inside, '| texture', images)
    assert(drawn > 0 and inside, key)
    if key == 'satin' or key == 'brushed' then assert(images == 1, key .. ': its texture') end
end
package.loaded['winxi.selection'], package.loaded['winxi.tabs'] = nil, { Image = function() return nil end }
selection = require('winxi.selection')
look.SelectionStyle = 'satin'
box, drawn, images = { l = 1e9, t = 1e9, r = -1e9, b = -1e9 }, 0, 0
selection.Draw(list, x1, y1, x2, y2)
print('satin without its texture: drawn all the same', drawn > 0 and images == 0)
assert(drawn > 0 and images == 0)
print('winxi.selection: every style drawn within its room')
