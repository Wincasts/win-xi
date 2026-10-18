local custom = require('custom')
local format = require('format')
local inline = require('inline_tokens')
local plates = require('winxi.nameplates')
local icons = require('icons')
local function old(shown)
    local options = {}
    custom.Defaults(options)
    options.nameFormat[1], options.showIcons[1] = '[name] ([distance]y)', shown
    options.iconSize[1], options.iconSpacing[1] = 90, 7
    return options
end
local o = old(true)
custom.Settle(o)
local parts = format.Compile(o.nameFormat[1])
assert(parts[1].kind == 'icons' and parts[1].size == 90 and parts[1].space == 7,
    'migration preserves visible icons and legacy size/spacing')
o.nameFormat[1] = '[name]'
custom.Settle(o)
assert(o.nameFormat[1] == '[name]', 'migration must not put icons back after user removes the token')
o = old(false)
custom.Settle(o)
assert(not format.Compile(o.nameFormat[1]).icons, 'migration preserves hidden icons')
o = {}; custom.Defaults(o); custom.Settle(o)
assert(format.Compile(o.nameFormat[1]).icons, 'fresh player format includes icons')
local npc = o.npcFormat[1]
o.nameFormat[1] = '[name][icons: space=4]'
custom.Settle(o)
assert(o.nameFormat[1] == '[name][icons: space=4]' and o.npcFormat[1] == npc,
    'settling must not reorder explicit icon tokens or affect NPC formats')
local written = { icons = { 0x92, 0xAC } }
local token = format.Compile('[icons: size=150 gap=3 space=4]')[1]
local width, size = inline.IconWidth(token, written, 20, 2, 90, 7)
assert(width == 74 and size == 30, 'width = two icons, scaled internal gap and trailing space')
local quads = {}
local originalQuad, originalPlace = plates.Quad, icons.Place
plates.Quad = function(...) quads[#quads + 1] = { ... } end
icons.Place = function() return { 0, 0, 1, 1 } end
assert(inline.WriteIcons(token, written, 10, 0, 20, 2, 90, 7, 0xFFAABBCC) == width)
assert(#quads == 3 and quads[1][9] == 0xFFAABBCC, 'pearl colour and composite status badge must be retained')
assert(quads[3][3] - quads[3][1] == 15 and quads[3][4] - quads[3][2] == 15,
    'status star badge must be half-size, never a full-size overlay on seeking-party')
assert(quads[3][1] == quads[2][1] - 30/16 and quads[3][2] == quads[2][2] - 30/16,
    'badge must use the game font shape offset relative to the base')
assert(quads[3][5] == 0.75 and quads[3][6] == 0.25, 'composite badge uses exported overlay UVs')
quads = {}
inline.WriteIcons(token, { icons = { 0x91 } }, 10, 0, 20, 2, 90, 7, 0xFFAABBCC)
assert(#quads == 1, 'ordinary seeking-party status must not acquire a star badge')
quads = {}
inline.WriteIcons(token, written, 10, 0, 20, 2, 90, 7, 0xFFAABBCC)
assert(quads[2][1] - quads[1][3] == 6 and quads[1][4] - quads[1][2] == 30)
assert(inline.IconWidth(token, { icons = {} }, 20, 2, 90, 7) == 0, 'empty icons must not leave spacing')
plates.Quad, icons.Place = originalQuad, originalPlace
local distance = { distanceValue = 12.346, far = '12.3' }
assert(inline.Distance({ decimals = 0 }, distance) == '12')
assert(inline.Distance({}, distance) == '12.3')
assert(inline.Distance({ decimals = 2 }, distance) == '12.35')
distance.distanceValue = 12.356
assert(inline.Distance({ decimals = 2 }, distance) == '12.36', 'precision cache must update within a tenth')
H.print('token options: icon migration, geometry, empty tokens, pearl/overlay colours and distance precision', true)
