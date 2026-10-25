local custom = require('custom')
local format = require('format')
local inline = require('inline_tokens')
local plates = require('winxi.nameplates')
local icons = require('icons')
local function old(shown)
    local options = {}
    custom.Defaults(options)
    options.nameFormat[1], options.showIcons = '[name] ([distance]y)', { shown } -- as a file saved before the formats has it
    options.npcFormat[1] = '[name]'
    options.iconSize[1], options.iconSpacing[1] = 90, 7
    return options
end
local o = old(true)
custom.Settle(o)
local parts = format.Compile(o.nameFormat[1])
assert(parts[1].kind == 'party' and parts[1].space == 2 and parts[2].kind == 'icons' and parts[2].size == 90 and parts[2].space == 7,
    'migration preserves visible icons and legacy size/spacing, Party Icons Beside before them')
assert(o.npcFormat[1] == '[vendor: space=7][name]' and o.partyIcons == nil and o.showVendorIcons == nil,
    'Vendor Icons becomes [vendor] with the old spacing, and the switches go')
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
-- Party Icons and Vendor Icons as they were saved: each mode brought into the formats once
local function signs(mode, coin, player)
    local options = {}
    custom.Defaults(options)
    options.signFormatVersion = nil
    options.nameFormat[1], options.npcFormat[1] = player or '[icons: space=4][name]', '[name]'
    options.partyIcons, options.showVendorIcons = mode and { mode }, coin ~= nil and { coin } or nil
    options.iconSpacing[1] = 4
    custom.Settle(options)
    return options
end
o = signs('beside', true)
assert(o.nameFormat[1] == '[party: space=2][icons: space=4][name]' and o.npcFormat[1] == '[vendor: space=4][name]', 'beside, coin on')
o = signs('replace', false)
assert(o.nameFormat[1] == '[party: replace, space=4][icons: space=4][name]' and o.npcFormat[1] == '[name]', 'replace, coin off')
assert(format.Compile(o.nameFormat[1]).partyReplace, 'replace is an attribute of [party]')
o = signs('off', nil)
assert(o.nameFormat[1] == '[icons: space=4][name]' and o.npcFormat[1] == '[vendor: space=4][name]', 'off; the coin was on by default')
o = signs('sideways', true, '[name] [icons: gap=3]')
assert(o.nameFormat[1] == '[name] [party: space=3][icons: gap=3]', 'an unknown mode is Beside, as far off as the icons are apart')
o = signs('beside', true, '[name]')
assert(o.nameFormat[1] == '[name]', 'no [icons], no sign, as before')
o = signs(nil, nil); local again = o.nameFormat[1]; o.nameFormat[1] = '[name]'; custom.Settle(o)
assert(again == '[party: space=2][icons: space=4][name]' and o.nameFormat[1] == '[name]', 'once only: a removed [party] stays removed')
o = {}; custom.Defaults(o); custom.Settle(o)
assert(o.nameFormat[1] == '[party: space=2][icons: space=4][name]' and o.npcFormat[1] == '[vendor: space=4][name]', 'fresh formats are as they were')
assert(format.Compile('[party: replace=maybe]')[1].kind == 'text', 'a bad replace is text')
local sign = format.Compile('[vendor: size=150, space=4]')[1]
local sw, ss = inline.SignWidth(sign, 1, 20, 2, 90, 7)
assert(sw == 38 and ss == 30 and inline.SignWidth(sign, nil, 20, 2, 90, 7) == 0, 'a sign is one icon and its space, or nothing at all')

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
