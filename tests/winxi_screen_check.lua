-- winxi.screen: a window any of which is off the screen is moved back on, against the edge it went
-- over; one on the screen is left alone; one bigger than the screen goes to its top left. Every
-- winxi.window is kept so, before its content is drawn.
local imgui = require('imgui')
local screen = require('winxi.screen')
local window = require('winxi.window')
local function check(label, ok) H.print(label, ok); assert(ok, label) end

local at, size = { 0, 0 }, { 300, 150 }
local moved = nil
imgui.GetIO = function() return { DisplaySize = { x = 1920, y = 1080 } } end
imgui.GetWindowPos = function() return at[1], at[2] end
imgui.GetWindowSize = function() return size[1], size[2] end
imgui.SetWindowPos = function(name, point) moved = { name, point[1], point[2] }; at[1], at[2] = point[1], point[2] end
local function keep(x, y, w, h)
    at[1], at[2], size[1], size[2], moved = x, y, w or 300, h or 150, nil
    return screen.Keep('test')
end

check('on the screen: left alone', not keep(100, 200) and moved == nil)
check('against the edges exactly: left alone', not keep(1620, 930) and moved == nil)
check('past the right and bottom: back against them', keep(2098, 1215) and moved[2] == 1620 and moved[3] == 930)
check('past the left and top: back against them', keep(-40, -10) and moved[2] == 0 and moved[3] == 0)
check('only the side that is over moves', keep(1900, 300) and moved[2] == 1620 and moved[3] == 300)
check('bigger than the screen: its top left', keep(500, 500, 2500, 1300) and moved[2] == 0 and moved[3] == 0)
imgui.GetIO = function() return { DisplaySize = { x = 0, y = 0 } } end
check('no screen yet: left alone', not keep(5000, 5000) and moved == nil)
imgui.GetIO = function() return { DisplaySize = { x = 1920, y = 1080 } } end

-- through winxi.window, before the content is drawn
local placedFirst = nil
at[1], at[2], size[1], size[2], moved = 2400, 100, 300, 150, nil
window.Plain('winxi.screen.test', { true }, 0, function() placedFirst = moved ~= nil and at[1] == 1620 end)
check('winxi.window: kept on the screen before its content is drawn', placedFirst == true and moved[1] == 'winxi.screen.test')
H.print('screen: off-screen windows moved back on, against the edge they went over; on-screen ones left alone', true)
