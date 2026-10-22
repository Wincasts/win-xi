-- tcrossbar's recast timer (forks/addons/tcrossbar/recasttext.lua): centred on the icon in the Winxi
-- Theme's font and Text Color with winxi.text's edge, at Recast Size; false without winxi.
-- Run alone: luajit tests/tcrossbar_recast_check.lua
package.path = 'forks/addons/tcrossbar/?.lua;' .. package.path

local calls = {}
local drawList = { AddText = function(_, pos, color, words) calls[#calls + 1] = { x = pos[1], y = pos[2], color = color, words = words } end }
local pushed = {}
local imgui = {
    GetBackgroundDrawList = function() return drawList end,
    PushFont = function(font, size) pushed[#pushed + 1] = { font = font, size = size } end,
    PopFont = function() pushed[#pushed + 1] = 'pop' end,
    CalcTextSize = function(words) return #words * pushed[#pushed].size / 2, pushed[#pushed].size end,
    GetColorU32 = function(c) return c end,
}
package.preload['imgui'] = function() return imgui end
local current = { FontFile = 'arial.ttf', TextColor = { 1, 1, 1, 1 }, TextOutline = 1, TextOutlineColor = { 0, 0, 0, 0.9 } }
package.preload['winxi.theme'] = function() return { Get = function() return current end } end
package.preload['winxi.fonts'] = function() return { Get = function(file) return 'font:' .. file end } end
package.path = 'addons/libs/?.lua;' .. package.path

local recasttext = require('recasttext')
print('drawn', recasttext.Draw('1:23', 100, 50, 20) == true, '| in the theme font at its size', pushed[1].font == 'font:arial.ttf' and pushed[1].size == 20, '| popped', pushed[2] == 'pop')
local last = calls[#calls]
print('centred: 40 by 20 about (100, 50)', last.x == 80 and last.y == 40, '| theme Text Color on top', last.color == current.TextColor and last.words == '1:23')
print('a dark edge behind, four ways', #calls == 5 and calls[1].color[4] == 0.9 and calls[1].color[1] == 0 and calls[1].x == 79 and calls[1].y == 39)
pushed = {}; recasttext.Draw('5', 0, 0, 200); recasttext.Draw('5', 0, 0, 1); recasttext.Draw('5', 0, 0)
print('kept within 8 to 40, 16 when unset', pushed[1].size == 40 and pushed[3].size == 8 and pushed[5].size == 16)

-- without winxi
package.loaded['recasttext'] = nil
package.preload['winxi.theme'] = function() error('no winxi') end
package.loaded['winxi.theme'], package.loaded['winxi.text'] = nil, nil
print('false without winxi', require('recasttext').Draw('1:23', 0, 0, 16) == false)
