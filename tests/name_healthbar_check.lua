local imgui = require('imgui')
local plates = require('winxi.nameplates')
local healthbar = require('healthbar')
local types = require('name_types')
local custom = require('custom')
local customSettings = require('custom_settings')
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
for _, quad in ipairs(quads) do
    assert(quad[13] == true and quad[5] == quad[7] and quad[6] == quad[8],
        'every bar layer requests the constant-UV antialias fringe')
end
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
hp = 0.1
assert(draw() > 20 and quads[3][3] > quads[3][1], 'tiny HP stays fractional for antialiased coverage')
quads = {}
healthbar.Write(name, entities, -40, 40, 20.37, 0.75, 0xFF4080C0, 120, 7)
assert(quads[1][2] == math.floor(quads[1][2]), 'bar baseline is aligned to render-target pixels')
hp = 0
assert(draw() > 20 and #quads == 2)
hp, id = 50, 456
assert(draw() == 20 and #quads == 0)
id = 123
assert(healthbar.Write(name, nil, -40, 40, 20, 1) == 20)
imgui.GetFontTexUvWhitePixel = function() return { x = 0.5, y = 0.75 } end
assert(draw() > 20 and quads[1][5] == 0.5)
-- the preview is on the Bars tab, not the Names one, and is the session's alone
local originalCheckbox, seen = imgui.Checkbox, {}
imgui.Checkbox = function(label) seen[label] = true; return false end
customSettings.DrawSettings(o)
assert(not seen['##name.barPreview'], 'no preview among the names\' settings')
o.showHealthBar[1] = true
customSettings.DrawBars(o)
assert(seen['##name.barPreview'], 'Bars has a Preview')
imgui.Checkbox = originalCheckbox
assert(types.Preview == nil and o.healthBarPreview == nil, 'never a saved setting')
hp = 100
assert(draw() == 20 and #quads == 0)
assert(healthbar.Write(name, nil, -40, 40, 20, 1, nil, nil, nil, true) == 20,
    'legacy preview argument must not bypass entity validation')

-- the preview: a bar at full health, going down and up, each name apart; only while its control is drawn
healthbar.Preview[1] = true
local function previewAt(now)
    healthbar.PreviewVisible(now)
    healthbar.Begin(nil, now)
    assert(healthbar.previewing, 'previewing while its control is drawn')
    assert(draw() > 20, 'a bar whatever the HP while previewing')
    return #quads == 3 and quads[3][3] - quads[3][1] or 0
end
-- entity 300 is 111 seconds into its six (0.37 apart each): half way, empty, at the start
assert(previewAt(10) == 0, 'empty half way')
assert(previewAt(11.5) == 59, 'half full a quarter on (inside the border)')
assert(previewAt(13) == 118, 'full again')
name.EntityIndex = 301
assert(previewAt(13) ~= 118, 'each name a little apart')
name.EntityIndex = 300
assert(healthbar.Write(name, nil, -40, 40, 20, 1) == 20, 'and never without the entity')
healthbar.Begin(nil, 13 + 0.3)
assert(not healthbar.previewing and draw() == 20, 'gone once its control is no longer drawn')
healthbar.Preview[1] = false
healthbar.PreviewVisible(12)
healthbar.Begin(nil, 12)
assert(not healthbar.previewing)

-- Bar Texture went in 1.80: a saved one is dropped
o.healthBarTexture, o.castBarTexture = { 'glass' }, { 'chrome' }
custom.Settle(o)
assert(o.healthBarTexture == nil and o.castBarTexture == nil, 'saved bar textures dropped')
plates.Quad, imgui.GetFontTexUvWhitePixel = originalQuad, originalUV
H.print('shared health bars: dimensions, preview, NPC support, fill and safe HP validation', true)
