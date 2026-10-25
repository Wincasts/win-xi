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
-- the preview is on the Health Bars tab, not the Names one, and is the session's alone
local originalCheckbox, seen = imgui.Checkbox, {}
imgui.Checkbox = function(label) seen[label] = true; return false end
customSettings.DrawSettings(o)
assert(not seen['##name.healthBarPreview'], 'no preview among the names\' settings')
o.showHealthBar[1] = true
customSettings.DrawHealthBars(o)
assert(seen['##name.healthBarPreview'], 'Health Bars has a Preview')
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

-- textures: winxi's sets, packed with the special signs into a sheet of the addon's own
local barArt, special, image = require('bar_art'), require('special'), require('gdi.image')
assert(barArt.Choices()[1].key == 'plain' and barArt.Valid('glass') and not barArt.Valid('nonesuch'))
assert(o.healthBarTexture[1] == 'plain' and o.castBarTexture[1] == 'plain', 'plain to begin with')
o.healthBarTexture[1], o.castBarTexture[1] = 'nonesuch', 42
custom.Settle(o)
assert(o.healthBarTexture[1] == 'plain' and o.castBarTexture[1] == 'plain', 'unknown textures settle to plain')
local loads, sizes = {}, { back = { 220, 28 }, fill = { 204, 28 }, front = { 226, 28 } }
local originalLoad, originalUpload, originalFree = barArt.LoadImage, barArt.Upload, barArt.Free
local freed = 0
barArt.Free = function(texture) assert(texture.packed); freed = freed + 1 end
barArt.LoadImage = function(path)
    loads[#loads + 1] = path
    if path:find('special.png', 1, true) then return image.new(256, 128) end
    for part, size in pairs(sizes) do
        if path:find(part .. '.png', 1, true) then return image.new(size[1], size[2]) end
    end
end
local uploads = 0
barArt.Upload = function(packed) uploads = uploads + 1; return { packed = packed }, 0x1000 + uploads end
assert(barArt.Begin(o) == nil and #loads == 0, 'no sheet while every bar is plain')
assert(select(1, special.UV(0)) == 0, 'the signs as they are')
o.healthBarTexture[1] = 'glass'
local at = barArt.Begin(o)
assert(at == 0x1001 and #loads == 4, 'the signs and the set\'s three images, once')
assert(loads[2]:find('glass\\back.png', 1, true), 'from winxi\'s folder of bar art')
assert(barArt.Begin(o) == at and uploads == 1, 'made once')
local signs = barArt.Sheet().signs
local u0, v0, u1, v1 = special.UV(special.Vendor)
assert(u0 > signs.u0 and u1 <= signs.u1 and v0 >= signs.v0 and v1 <= signs.v1, 'the signs are where the sheet has them')
o.showHealthBar[1] = false
assert(barArt.Begin(o) == nil and special.UV(0) == 0 and freed == 1, 'let go when no bar wants it')
o.showHealthBar[1] = true

local function textured(height, fraction)
    quads = {}
    barArt.Begin(o)
    return healthbar.Bar(-40, 40, 20, 1, fraction, 0xFF4080C0, 60, height, nil, 'glass')
end
local foot = textured(6, 0.5)
assert(#quads == 7, 'back and front in three, and the fill')
for _, quad in ipairs(quads) do
    assert(quad[10] == special.Slot and quad[9] == 0xFF4080C0 and quad[11] == false, 'from the shared sheet, tinted')
end
assert(quads[1][1] == -30 and quads[3][3] == 30 and foot == quads[1][4], 'the plain bar\'s place and size')
assert(quads[1][3] == quads[2][1] and quads[2][3] == quads[3][1], 'the back\'s pieces meet')
local edge = 8 * 6 / 28
assert(math.abs(quads[4][1] - (-30 + edge)) < 1e-9 and math.abs(quads[4][3] - quads[4][1] - (60 - 2 * edge) * 0.5) < 1e-9,
    'the fill from the inset, as far as the HP goes')
assert(quads[4][13] == true and quads[1][13] == nil, 'the fill softened, the pieces not (they would seam)')
local regions = barArt.Sheet().regions
local function heightOf(quad)
    for key, found in pairs(regions) do
        if found.u0 == quad[5] and found.v0 == quad[6] and found.u1 == quad[7] and found.v1 == quad[8] then return found.h, key end
    end
end
assert(heightOf(quads[4]) == 7, 'a 6 px bar from the quarter-size copy')
textured(12, 0.5)
assert(heightOf(quads[4]) == 14, 'a 12 px bar from the half-size copy')
textured(20, 0.5)
assert(heightOf(quads[4]) == 28, 'a 20 px bar from the art as it is')
textured(6, 0)
assert(#quads == 6, 'no fill when empty')
quads = {}
assert(healthbar.Write(name, entities, -40, 40, 20, 1, 0xFF4080C0, 60, 6, true, 'glass') > 20 and #quads == 7,
    'Write passes the texture on')
quads = {}
healthbar.Write(name, entities, -40, 40, 20, 1, 0xFF4080C0, 60, 6, true, 'plain')
assert(#quads == 3, 'plain as before')
o.healthBarTexture[1], o.castBarTexture[1], o.showCastBar[1] = 'plain', 'tube', true
barArt.Begin(o)
quads = {}
assert(healthbar.Bar(-40, 40, 20, 1, 0.5, 0xFF4080C0, 60, 6, nil, 'glass') > 20 and #quads == 3,
    'a set not in the sheet draws plain')
-- a sheet that cannot be made: plain bars, and not tried again at once
barArt.LoadImage = function() return nil end
o.castBarTexture[1] = 'chrome'
assert(barArt.Begin(o) == nil and barArt.Sheet() == nil and special.UV(0) == 0)
local tries = 0
barArt.LoadImage = function(...) tries = tries + 1; return nil end
barArt.Begin(o)
assert(tries == 0, 'not tried again every frame')
barArt.Release()
barArt.LoadImage, barArt.Upload, barArt.Free = originalLoad, originalUpload, originalFree
o.showCastBar[1], o.castBarTexture[1], o.showHealthBar[1] = false, 'plain', false
plates.Quad, imgui.GetFontTexUvWhitePixel = originalQuad, originalUV
H.print('shared health bars: dimensions, preview, textures, NPC support, fill and safe HP validation', true)
