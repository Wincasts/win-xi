-- luajit tests/winxi_clip_check.lua
-- A clip opened past a window (winxi.clip) is kept on the screen: a window's title, shadow and controller
-- highlight, with the window at or past the screen's edge, never push a clip off it, which Direct3D 8 turns
-- into a refused viewport and the title stretched over the whole screen. A title's clip is the whole screen
-- itself (clip.Screen): one of its own, on the screen, was still seen stretched.
package.path = 'addons/libs/?.lua;' .. package.path
local look = { FrameTitles = true, TitleStyle = 'outline', TitleColor = { 1, 1, 1, 1 }, TitleOffsetX = 8,
    TitleOffsetY = 0, TitleSize = 0, ShadowEnabled = true, ShadowOpacity = 50, ShadowOffset = 4, ShadowBlur = 3,
    TextOutline = 1, TextOutlineColor = { 0, 0, 0, 1 } }
package.loaded['winxi.theme'] = { Get = function() return look end, GameBorderColor = function() return { 1, 1, 1, 1 } end }
package.loaded['winxi.fonts'] = { Get = function() return nil end }
local display = { x = 1280, y = 720 }
local winX, winY, winW, winH = 100, 100, 200, 80
local clips, depth, drawn, fontDepth = {}, 0, 0, 0
local list = {
    PushClipRect = function(_, a, b, intersect)
        depth = depth + 1
        clips[#clips + 1] = { a[1], a[2], b[1], b[2], intersect }
    end,
    PopClipRect = function() depth = depth - 1 end,
    AddText = function() drawn = drawn + 1 end,
    AddRect = function() drawn = drawn + 1 end,
    AddRectFilled = function() drawn = drawn + 1 end,
}
package.loaded.imgui = {
    GetIO = function() return { DisplaySize = display } end,
    GetWindowPos = function() return winX, winY end,
    GetWindowSize = function() return winW, winH end,
    GetWindowDrawList = function() return list end,
    GetBackgroundDrawList = function() return list end,
    CalcTextSize = function() return 60, 16 end,
    GetColorU32 = function(c) return c end,
    PushFont = function() fontDepth = fontDepth + 1 end,
    PopFont = function() fontDepth = fontDepth - 1 end,
    GetStyle = function() return { WindowRounding = 3 } end,
}
local clip = require('winxi.clip')
local titles = require('winxi.titles')
local shadow = require('winxi.shadow')

local function onScreen(what)
    assert(#clips > 0, what .. ': a clip is pushed')
    for _, c in ipairs(clips) do
        assert(c[1] >= 0 and c[2] >= 0 and c[3] <= display.x and c[4] <= display.y,
            ('%s: clip %g,%g..%g,%g off the screen'):format(what, c[1], c[2], c[3], c[4]))
        assert(c[3] > c[1] and c[4] > c[2], what .. ': no empty clip is pushed')
        assert(c[5] == false, what .. ': the window\'s clip is still replaced')
    end
    assert(depth == 0, what .. ': every clip popped')
end
local function reset() clips, depth, drawn = {}, 0, 0 end

-- clip.Push itself: cut to the screen, nothing pushed where nothing is left
reset()
assert(clip.Push(list, { -40, -10 }, { 50, 20 }) == true); list:PopClipRect()
assert(clips[1][1] == 0 and clips[1][2] == 0 and clips[1][3] == 50 and clips[1][4] == 20, 'cut at the top left')
reset()
assert(clip.Push(list, { 1200, 700 }, { 1400, 900 }) == true); list:PopClipRect()
assert(clips[1][3] == 1280 and clips[1][4] == 720, 'cut at the bottom right')
reset()
assert(clip.Push(list, { -100, -100 }, { -10, -10 }) == false and #clips == 0, 'wholly off the screen: nothing pushed')
reset()
assert(clip.Push(list, { 10, 10 }, { 20, 20 }) == true); list:PopClipRect()
assert(clips[1][1] == 10 and clips[1][3] == 20, 'on the screen: as given')

-- clip.Screen: the whole screen where any of what is drawn is on it, nothing where none is
reset()
assert(clip.Screen(list, { 300, 300 }, { 360, 320 }) == true); list:PopClipRect()
assert(clips[1][1] == 0 and clips[1][2] == 0 and clips[1][3] == 1280 and clips[1][4] == 720, 'the whole screen')
reset()
assert(clip.Screen(list, { -100, -100 }, { -10, -10 }) == false and #clips == 0, 'wholly off the screen: nothing pushed')

-- a title's clip is the whole screen, wherever its window is: a clip of its own, wholly on the screen,
-- was still seen stretched over it, and the whole screen's is drawn as it is whatever viewport it gets
local function wholeScreen(what)
    onScreen(what)
    for _, c in ipairs(clips) do
        assert(c[1] == 0 and c[2] == 0 and c[3] == display.x and c[4] == display.y, what .. ': the whole screen')
    end
end
winX, winY = 300, 300
reset(); titles.Draw('Alliance 2'); wholeScreen('title in the middle')
-- a title on a window at the top of the screen: half of it above, before, off the screen
winX, winY = 100, 0
reset(); titles.Draw('Party'); wholeScreen('title at the top'); assert(drawn > 0, 'the title is still drawn')
-- dragged off the left, the title at its right edge still partly on the screen
winX, winY = -150, 50
reset(); titles.Draw('Party'); wholeScreen('title off the left')
-- dragged off the right, the title across the edge
winX, winY = 1100, 50
reset(); titles.Draw('Party'); wholeScreen('title off the right')
-- wholly above the screen: nothing drawn, nothing pushed, the title's font let go
winX, winY = 100, -200
look.TitleSize = 20
reset(); titles.Draw('Party')
assert(#clips == 0 and drawn == 0 and depth == 0 and fontDepth == 0, 'title off the screen: nothing drawn, font popped')
look.TitleSize = 0
-- the break style's haze too
look.TitleStyle = 'breakshadow'
winX, winY = 0, 0
reset(); titles.Draw('Party'); wholeScreen('break with shadow at the corner')
look.TitleStyle = 'outline'

-- a captured shadow beside a window at the screen's edges
winX, winY, winW, winH = 0, 0, 200, 80
reset(); shadow.Draw(true); onScreen('shadow at the top left')
winX, winY = 1076, 636
reset(); shadow.Draw(true); onScreen('shadow at the bottom right')
winX, winY = 1400, 800
reset(); shadow.Draw(true)
assert(#clips == 0 and drawn == 0 and depth == 0, 'shadow wholly off the screen: nothing drawn')

print('Winxi clip: clips kept on the screen at every edge, titles clipped to the whole screen, passed')
