local imgui = require('imgui')
local plates = require('winxi.nameplates')
local healthbar = require('healthbar')
local types = require('name_types')
local custom = require('custom')
local o = H.options()
local style = o
assert(not style.showHealthBar[1] and style.healthBarWidth[1] == 120 and style.healthBarHeight[1] == 7)
style.healthBarWidth[1], style.healthBarHeight[1] = 999, -1
custom.Settle(o)
assert(style.healthBarWidth[1] == 300 and style.healthBarHeight[1] == 3, 'shared dimensions clamped')
style.healthBarWidth[1], style.healthBarHeight[1] = 0/0, 'invalid'
custom.Settle(o)
assert(style.healthBarWidth[1] == 60 and style.healthBarHeight[1] == 6)
local quads = {}
local originalQuad, originalUV = plates.Quad, imgui.GetFontTexUvWhitePixel
plates.Quad = function(...) quads[#quads + 1] = { ... } end
imgui.GetFontTexUvWhitePixel = function() return 0.125, 0.25 end
local hp, id = 50, 123
local entities = { GetServerId = function() return id end, GetHPPercent = function() return hp end }
local name = { Category = plates.Category.Monster, EntityIndex = 300, ServerId = 123 }
local function draw()
    quads = {}
    return healthbar.Write(name, entities, -40, 40, 20, 1, 0xFF4080C0,
        style.healthBarWidth[1], style.healthBarHeight[1])
end
local under = draw()
assert(#quads == 3 and under > 20 and quads[1][2] > 20)
assert(quads[3][9] == 0xFF4080C0 and quads[1][11] == false)
assert(quads[1][3] - quads[1][1] == 60 and quads[1][4] - quads[1][2] == 6)
assert(quads[3][3] - quads[3][1] == (quads[2][3] - quads[2][1]) / 2)
style.healthBarWidth[1], style.healthBarHeight[1] = 120, 12
draw()
assert(quads[1][3] - quads[1][1] == 120 and quads[1][4] - quads[1][2] == 12)
quads = {}
healthbar.Write(name, entities, -10, 10, 20, 2, 0xFF4080C0, 120, 12)
assert(quads[1][3] - quads[1][1] == 240 and quads[1][4] - quads[1][2] == 24)
for _, category in pairs(plates.Category) do
    name.Category = category
    assert(draw() > 20 and #quads == 3, 'caller selects eligible types, including NPCs/pets')
end
for _, value in ipairs({ 100, 101, -1, 0/0 }) do
    hp = value
    assert(draw() == 20 and #quads == 0)
end
hp = 0
assert(draw() > 20 and #quads == 2)
hp, id = 50, 456
assert(draw() == 20 and #quads == 0)
id = 123
assert(healthbar.Write(name, nil, -40, 40, 20, 1) == 20)
imgui.GetFontTexUvWhitePixel = function() return { x = 0.5, y = 0.75 } end
assert(draw() > 20 and quads[1][5] == 0.5)
local originalCheckbox = imgui.Checkbox
imgui.Checkbox = function(label)
    assert(not label:find('healthBarPreview', 1, true), 'preview controls must be removed')
    return false
end
custom.DrawSettings(o)
imgui.Checkbox = originalCheckbox
assert(types.Preview == nil, 'no hidden session preview state')
hp = 100
assert(draw() == 20 and #quads == 0)
assert(healthbar.Write(name, nil, -40, 40, 20, 1, nil, nil, nil, true) == 20,
    'legacy preview argument must not bypass entity validation')
plates.Quad, imgui.GetFontTexUvWhitePixel = originalQuad, originalUV
H.print('shared health bars: dimensions, no preview controls, NPC support, fill and safe HP validation', true)
