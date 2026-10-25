-- nativeui with uihook's mirror of the menus over the chat log stood in for (groupmirror's new), for
-- tests/nativeui_group_check.lua; its letters (Words) the real ones:
--     luajit tests/harness.lua nativeui tests/nativeui_group_stand_in.lua tests/nativeui_group_check.lua
-- GROUP holds what the check sets (the windows published) and what the addon asked (each frame's kept names, stops).
package.path = 'addons/nativeui/?.lua;' .. package.path
GROUP = { requests = {}, stops = 0, windows = {} }
local real = require('groupmirror')
real.new = function() return {
    Request = function(kept) GROUP.requests[#GROUP.requests + 1] = kept; return true end,
    Stop = function() GROUP.stops = GROUP.stops + 1 end,
    Windows = function() return GROUP.windows end,
    Status = function() return 'stood in' end,
    Supported = function() return true end,
} end
-- the game's hand: a frame 20 by 10 with its pivot (the fingertip) at its right, in its middle
package.loaded['winxi.cursor'] = { Get = function() return 0x77, { 0, 0, 1, 1, 20, 10, corners = { -20, -5, 0, -5, -20, 5, 0, 5 } } end }
-- what is drawn as a picture or a filled box, kept for the check: { texture, min, max } and { min, max, colour }
GROUP.images, GROUP.boxes = {}, {}
local imgui = require('imgui')
local list = imgui.GetWindowDrawList()
rawset(list, 'AddImage', function(_, texture, min, max) GROUP.images[#GROUP.images + 1] = { texture = texture, min = min, max = max } end)
rawset(list, 'AddRectFilled', function(_, min, max, colour, rounding) GROUP.boxes[#GROUP.boxes + 1] = { min = min, max = max, rounding = rounding } end)
dofile('addons/nativeui/nativeui.lua')
