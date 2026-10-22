-- menus with uihook's mirror stood in for: one window of the game's, measured, as the bridge would give it;
-- the addon's event handlers kept for the check to fire (a mouse); imgui's mouse where the check puts it.
MENUS = { requests = {}, stops = 0, windows = {}, handlers = {}, mouse = { x = 0, y = 0 }, captured = false }
package.loaded['winxi.nativemirror'] = { Content = 1, Element = 3, new = function() return {
    Request = function(list) MENUS.requests[#MENUS.requests + 1] = list; return true end,
    Stop = function() MENUS.stops = MENUS.stops + 1 end,
    Windows = function() return MENUS.windows end,
    Status = function() return 'stood in' end,
} end }
local register = ashita.events.register
ashita.events.register = function(event, name, f)
    MENUS.handlers[event] = f
    return register(event, name, f)
end
local imgui = require('imgui')
rawset(imgui, 'GetIO', function()
    return { DisplaySize = { x = 1920, y = 1080 }, MousePos = { x = MENUS.mouse.x, y = MENUS.mouse.y }, WantCaptureMouse = MENUS.captured }
end)
dofile('addons/menus/menus.lua')
