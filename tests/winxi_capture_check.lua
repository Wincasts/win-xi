-- Run through tests/harness.lua party addons/party/party.lua.
H.load()
local imgui = require('imgui')
local window = require('winxi.window')
local borders = require('winxi.borders')
local stage, ended = 0, false
local drawBorder, endWindow = borders.Draw, imgui.End
borders.Draw = function(...) assert(stage==1); stage=2; return drawBorder(...) end
imgui.End = function(...) assert(stage==3); ended=true; return endWindow(...) end
assert(window.Plain('winxi.capture.test', nil, 0, function() stage=1 end, {
    shadow=false,
    capture=function() assert(stage==2, 'border must precede capture'); stage=3 end,
}))
assert(ended, 'capture must precede End')
stage, ended = 0, false
local ok, err = pcall(window.Plain, 'winxi.capture.error', nil, 0, function() stage=1 end, {
    shadow=false,
    capture=function() stage=3; error('capture failure') end,
})
assert(not ok and tostring(err):find('capture failure') and ended, 'capture failure still unwinds window/stacks')
borders.Draw, imgui.End = drawBorder, endWindow
-- a captured window's shadow goes on its own list, to be captured with it; an ordinary one's does not
local shadow = require('winxi.shadow')
local drawShadow, shadowCaptured = shadow.Draw, nil
shadow.Draw = function(captured) shadowCaptured = captured end
window.Plain('winxi.capture.shadow', nil, 0, function() end, { capture = function() end })
assert(shadowCaptured == true, 'captured window: captured shadow')
window.Plain('winxi.capture.plain', nil, 0, function() end)
assert(shadowCaptured == false, 'ordinary window: ordinary shadow')
shadow.Draw = drawShadow
H.print('window.capture: after complete decoration, before End, error cleanup, captured shadow', true)

-- Per-window colours reach both plain style and complete captured decoration without theme writes.
local theme = require('winxi.theme')
local look = theme.Get()
local oldBackground, oldBorder, oldText, oldTitle = look.BackgroundColor, look.BorderColor, look.TextColor, look.TitleColor
local own = {background={0.1,0.2,0.3,0.4},border={0.4,0.3,0.2,0.6},textColor={0.7,0.8,0.9,1},titleColor={1,0.5,0.2,1},shadow=false,title='Own Title'}
local colors, borderSeen, titleSeen = {}, false, false
local pushColor, drawTitle = imgui.PushStyleColor, require('winxi.titles').Draw
imgui.PushStyleColor=function(slot,color) colors[slot]=color; return pushColor(slot,color) end
borders.Draw=function(texture,a,b,tint) borderSeen=tint == own.border; return drawBorder(texture,a,b,tint) end
require('winxi.titles').Draw=function(words,options) titleSeen=words == own.title and options == own; return drawTitle(words,options) end
assert(window.Plain('winxi.colours.test',nil,0,function() end,own))
assert(colors[ImGuiCol_Border] == own.border and colors[ImGuiCol_Text] == own.textColor and borderSeen and titleSeen)
assert(look.BackgroundColor == oldBackground and look.BorderColor == oldBorder and look.TextColor == oldText and look.TitleColor == oldTitle)
imgui.PushStyleColor, borders.Draw, require('winxi.titles').Draw = pushColor, drawBorder, drawTitle
-- Untitled plain borders must still be drawn when explicitly overridden, as must tinted border art.
local getList = imgui.GetWindowDrawList
local rectangles, images = 0,0
local tint = imgui.GetColorU32(own.border)
imgui.GetWindowDrawList=function() return {
    AddRect=function(_,a,b,color) assert(color == tint); rectangles=rectangles+1 end,
    AddImage=function(_,texture,a,b,uvA,uvB,color) assert(color == tint); images=images+1 end,
} end
borders.Draw(nil,nil,nil,own.border)
borders.Draw(77,nil,nil,own.border)
assert(rectangles == 1 and images == 8, 'override draws untitled plain border and tints all eight art slices')
imgui.GetWindowDrawList=getList
H.print('window colours: local background/border/text/title, capture forwarding, plain border and art tint',true)
