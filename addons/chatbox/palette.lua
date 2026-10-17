-- Standard FFXI palette approximations (RGB), not ImGui's theme palette.
-- Slot RGB observations: https://github.com/Citrus333/FancyChatXI/blob/main/utils.lua
-- Kept as data only; no FancyChat parser or renderer is used. These cannot reflect
-- custom DAT palettes or the game's user-configured channel colours.
local data = {
    [30] = [[
02:94ff33 03:9493ff 04:9493ff 05:ff58ff 06:37ffff 07:ffffed 08:ff9471
09:b2ffed 0a:b3ffed 0b:aeffe7 0c:adffe7 0d:adffe6 0e:adffe7 0f:aeffe8 10:aaffe2
41:ffffc9 43:9392b2 44:ff6c9b 45:ffff56 46:94b0ff 47:75b0ff 48:f036ff
49:ff91ff 4c:ff5673 4e:dadeae 4f:18ff37 50:f0ffff 51:ffffc9 52:55ffff
53:37ffb5 55:ffb1b4 56:ff91ff 57:58ffff 58:b2fff2 59:cbb2ff 5c:cdffff
5d:ff94b0 60:ffffce 66:ffffb5 67:f2eeff 68:ffff58 69:ffceff 6a:ffffd4
6b:ffffd4 6c:ff9297 6d:ffffb3 6e:daff58 6f:19ff3a 70:18b0ff 71:ffffcd 8f:ff55f0
]],
    [31] = [[
02:ffb4c2 03:ff96a3 04:ff96ff 05:5bffff 06:b8ffff 07:d7b4ff 08:ffd3ff
0a:ffb4c2 0b:ff94a0 0c:ff96ff 0d:59ffff 0e:b3fffa 0f:d1b7ff 10:ffcdff
15:f6f2ff 1a:eff2ff 1c:ff9bc2 1e:d7ffff 1f:d1ffff 21:f7f2ff 24:ffff67
25:e7e3c4 26:ff71ad 27:ff5a86 29:f0f2ff 32:ffff68 33:ffff68 34:ffff68
35:e7e4c5 37:ffff68 3a:ffff68 3b:ffffdf 3e:ffff68 3f:ffffc1 42:ffff69
43:ffffc6 44:ffffc6 45:ffffc6 47:f8f3ff 48:f8f3ff 50:ffff69 53:ffff6b
55:ffff6b 58:ffff6b 59:f1f7ff 5a:ffff6b 5d:ffff6a 5e:f1f7ff 64:ffff6c
67:ffff6c 69:ffff6c 6c:ffff6c 6d:f9f4ff 6e:ffff6c 71:ffffdf 72:f2f1ff
79:ffffe4 7a:ffff6c 7b:ff73ae 7c:ff73af 7d:ff74af 7e:ff73ae 7f:ffffe4
80:ffffe3 81:ffffe5 82:ffffe5 83:ffffe5 84:ffffe5 85:ffffe5 86:ffffe5
87:ffffe5 88:ffffe5 89:ffffe5 8a:ffffe6 8b:ffffe5 8c:ffffea 8d:ffff6d
9a:ffff6e 9b:ffff6e 9c:ffff6e 9e:21ff50 9f:ffff6e a0:9d9acc a1:ffffe2
 a4:f3f3ff a6:e4e4c9 a7:ff5d8d a8:ffff6f a9:ffff6f aa:ffffcd ab:ffff6f
ac:ffff6f ad:f3f6ff b1:ffffe3 b3:ffff70 b4:ffff70 b5:f4f3ff b8:f4f3ff
ba:f4f3ff bd:ffffca c8:bd5fff c9:bd5fff cc:22ff53 cd:bdffff ce:ffffee
cf:9abaff d0:dcbfff d1:ffffe5 d2:5fffff d3:ffffca d4:ffffca d5:deff72
d6:deff72 d7:23ff54 d8:23ff54 d9:deff72 da:23ff54 db:23bdff dc:23baff
dd:23f7ff de:23f7ff
]],
}
local colors, white = {}, {1,1,1,1}
for bank, text in pairs(data) do
    colors[bank] = {}
    for slot, r, g, b in text:gmatch('(%x%x):(%x%x)(%x%x)(%x%x)') do
        colors[bank][tonumber(slot,16)] = {tonumber(r,16)/255,tonumber(g,16)/255,tonumber(b,16)/255,1}
    end
end
local M = {}
-- The second palette is indexed by native chat mode as well as by inline colour code.
-- Unlisted native modes are white. Unlike an inline slot 1 (reset), mode 1 is Say.
function M.Mode(mode)
    if type(mode) ~= 'number' or mode < 0 or mode > 255 or mode ~= math.floor(mode) then return nil end
    return colors[31][mode] or white
end
function M.Color(bank, slot)
    if not colors[bank] or not slot or slot < 2 or slot > 255 then return nil end
    return colors[bank][slot] or white
end
return M
