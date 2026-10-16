addon.name = 'clock'
addon.author = 'win'
addon.version = '0.1.0'
addon.desc = 'Basic Vana\'diel clock at the native clock render boundary (uihook).'
local winxiNeeded = 5
do
    local ok, found = pcall(require, 'winxi.version')
    local number = ok and type(found) == 'table' and found.Number or 0
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number)
        print('[clock] ' .. text)
        error(text, 0)
    end
end
require('common')
local imgui = require('imgui')
local bit = require('bit')
local settings = require('settings')
local native = require('winxi.nativehud')
local hook = native.new(native.Clock)
local format = require('display')
local options = settings.load({ enabled = true, x = 20, y = -1 })
local time, timeError
local nextSample, lines = 0, nil
local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize,
    ImGuiWindowFlags_NoMove, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoSavedSettings,
    ImGuiWindowFlags_NoInputs, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoBringToFrontOnFocus)

settings.register('settings', 'clock_settings', function(value)
    options = value
    hook.Stop()
    nextSample, lines = 0, nil
end)
ashita.events.register('load', 'clock_load', function()
    local ok, value = pcall(require, 'ffxi.time')
    if ok then time = value else timeError = tostring(value) end
    if timeError then print('[clock] Ashita ffxi.time unavailable: ' .. timeError) end
    print('[clock] Requires /load uihook. Unload hidecompass; /clock status or /clock help.')
end)
ashita.events.register('unload', 'clock_unload', function()
    hook.Stop()
    settings.save()
end)
ashita.events.register('command', 'clock_command', function(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/clock' then return end
    e.blocked = true
    local command = args[2] and args[2]:lower() or 'status'
    if (command == 'on' or command == 'off') and #args == 2 then
        options.enabled = command == 'on'
        if not options.enabled then hook.Stop() end
        settings.save()
    elseif command == 'pos' and #args == 3 and args[3]:lower() == 'native' then
        options.x, options.y = 20, -1
        settings.save()
    elseif command == 'pos' and #args == 4 then
        local x, y = tonumber(args[3]), tonumber(args[4])
        if x and y and x == x and y == y and math.abs(x) < 100000 and math.abs(y) < 100000 then
            options.x, options.y = x, y
            settings.save()
        else print('[clock] Position must be finite screen coordinates.') end
    elseif command == 'status' and #args <= 2 then
        print('[clock] ' .. (not options.enabled and 'Off (stock clock restored).' or
            timeError and ('Time unavailable: ' .. timeError) or hook.Status()))
    else
        print('[clock] /clock on|off|status; /clock pos <x> <y>, or /clock pos native for the game\'s clock\'s place (the default).')
    end
end)
ashita.events.register('d3d_present', 'clock_present', function()
    if not options.enabled or not time then hook.Stop(); return end
    local now = os.clock()
    if now >= nextSample then
        nextSample = now + 0.25
        local weather
        local id = hook.Weather()
        if id then
            local ok, name = pcall(function() return AshitaCore:GetResourceManager():GetString('weather', id) end)
            weather = ok and type(name) == 'string' and #name > 0 and name or ('ID ' .. id)
        end
        local ok, value = pcall(format.Read, time, weather)
        if not ok then
            timeError = tostring(value)
            lines = nil
            hook.Stop()
            return
        end
        lines, timeError = value, nil
    end
    if not lines or not hook.Begin() then return end
    -- y -1 (the default): where the game draws its clock, the window's bottom-left on the clock's,
    -- growing up from it. It is drawn as the game draws its clock, under what the game draws after
    -- (the chat log), so a place of its own below the clock would be drawn over.
    local left, _, _, bottom = hook.ClockRect()
    if options.y == -1 and left then
        imgui.SetNextWindowPos({ left, bottom }, ImGuiCond_Always, { 0, 1 })
    else
        local display = imgui.GetIO().DisplaySize
        local height = display.y or display[2] or 0
        imgui.SetNextWindowPos({ options.x, options.y == -1 and math.max(0, height - 105) or options.y }, ImGuiCond_Always)
    end
    if imgui.Begin('clock.native', { true }, flags) then
        for i = 1, #lines do imgui.TextUnformatted(lines[i]) end
        hook.Capture() -- current window's background and text, never a pointer passed from Lua
    end
    imgui.End()
end)
