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
dofile('addons/nativeui/nativeui.lua')
