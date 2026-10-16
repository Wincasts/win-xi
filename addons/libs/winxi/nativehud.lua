-- Uihook's independent clock/compass capture slots. No ImGui or texture pointers cross Lua.
local ffi = require('ffi')
local bit = require('bit')
ffi.cdef[[
    typedef struct {
        char Magic[16];
        uint32_t Version, Size, SupportedMask, Frame, Submit;
        uint32_t DrawnFrame[2], NativeFrame[2];
        uint32_t Weather;
        float ClockRect[4];
        uint32_t ClockRectFrame;
        char Grid[12];
        float IconRect[3][4];
        uint32_t IconFrame[3];
        uint32_t HideIcons;
    } uihook_hud_t;
    typedef int32_t (__cdecl *uihook_hud_submit_t)(int32_t index, int32_t capture);
]]
local M = { Clock = 0, Compass = 1, DayIcon = 0, WeatherIcon = 1, SecondWeatherIcon = 2, HideDay = 1, HideWeather = 2 }
function M.new(index)
    assert(index == 0 or index == 1, 'native HUD slot must be clock or compass')
    local block, submit, base, looked = nil, nil, nil, -1
    local reason = 'Load /load uihook (clock/compass support required).'
    local owned = false
    local function Find()
        if not AshitaCore:GetPluginManager():IsLoaded('uihook') then
            block, submit, base, looked = nil, nil, nil, -1
            reason = 'Load /load uihook (clock/compass support required).'
            return nil
        end
        local current = ashita.memory.get_base('uihook.dll')
        if current ~= base then block, submit, base, looked = nil, nil, current, -1 end
        if not current or current == 0 then reason = 'uihook DLL is not ready.'; return nil end
        if not block then
            if os.clock() - looked < 1 then return nil end
            looked = os.clock()
            local address = ashita.memory.find('uihook.dll', 0, '5549484F4F4B2D485544000000000000', 0, 0)
            if not address or address == 0 then reason = 'Update uihook: clock/compass shared block not found.'; return nil end
            local found = ffi.cast('uihook_hud_t*', address)
            if found.Version ~= 4 or found.Size ~= ffi.sizeof('uihook_hud_t') or found.Submit == 0 then
                reason = 'uihook clock/compass ABI mismatch; install the matching DLL.'; return nil
            end
            block, submit = found, ffi.cast('uihook_hud_submit_t', found.Submit)
        end
        if bit.band(block.SupportedMask, bit.lshift(1, index)) == 0 then
            reason = 'uihook did not recognise this client\'s ' .. (index == 0 and 'clock.' or 'compass.')
            return nil
        end
        return block
    end
    local hook = {}
    function hook.Begin()
        if not Find() then return false end
        owned = submit(index, 0) ~= 0
        reason = owned and 'Native replacement ready; visibility follows the client.' or 'uihook rejected the frame.'
        return owned
    end
    function hook.Capture()
        if not owned or not Find() then return false end
        local ok = submit(index, 1) ~= 0
        if not ok then reason = 'uihook could not capture the window; native HUD remains available.' end
        return ok
    end
    function hook.Stop()
        if owned and Find() then
            submit(index, -1)
            if index == 0 then block.HideIcons = 0 end
        end
        owned = false
    end
    function hook.Weather()
        local found = Find()
        if not found or found.NativeFrame[0] == 0 or
            (tonumber(found.Frame) - tonumber(found.NativeFrame[0])) % 4294967296 > 2 or found.Weather > 19 then return nil end
        return tonumber(found.Weather)
    end
    -- Frames since the game last reached this slot's native draw, and since uihook last drew the
    -- replacement there; nil for never. Within 2 counts as current, as the plugin's freshness does.
    function hook.Ages()
        local found = Find()
        if not found then return nil, nil end
        local function Age(at)
            at = tonumber(at)
            if at == 0 then return nil end
            return (tonumber(found.Frame) - at) % 4294967296
        end
        return Age(found.NativeFrame[index]), Age(found.DrawnFrame[index])
    end
    -- Where the game drew its clock's text, in ImGui display pixels (left, top, right, bottom), while
    -- current; nil otherwise. The replacement anchors to it, so it is drawn where the clock is and
    -- under what the game draws after it (the chat log). The game's day and weather icons are its
    -- own and stay where they are.
    function hook.ClockRect()
        local found = Find()
        if not found or index ~= 0 or found.ClockRectFrame == 0 or
            (tonumber(found.Frame) - tonumber(found.ClockRectFrame)) % 4294967296 > 2 then return nil end
        local r = found.ClockRect
        for i = 0, 3 do if r[i] ~= r[i] or math.abs(r[i]) > 100000 then return nil end end
        if r[2] <= r[0] or r[3] <= r[1] then return nil end
        return tonumber(r[0]), tonumber(r[1]), tonumber(r[2]), tonumber(r[3])
    end
    -- Where the game drew one of its clock's icons (M.DayIcon, M.WeatherIcon, M.SecondWeatherIcon),
    -- as ClockRect, while it is drawing it; nil otherwise (no weather icon under a clear sky).
    function hook.IconRect(icon)
        local found = Find()
        if not found or index ~= 0 or icon < 0 or icon > 2 or found.IconFrame[icon] == 0 or
            (tonumber(found.Frame) - tonumber(found.IconFrame[icon])) % 4294967296 > 2 then return nil end
        local r = found.IconRect[icon]
        for i = 0, 3 do if r[i] ~= r[i] or math.abs(r[i]) > 100000 then return nil end end
        if r[2] <= r[0] or r[3] <= r[1] then return nil end
        return tonumber(r[0]), tonumber(r[1]), tonumber(r[2]), tonumber(r[3])
    end
    -- Which of the game's clock icons the addon draws its own of (M.HideDay, M.HideWeather), each
    -- frame its line is handed over; the game's are left undrawn only while that line is drawn.
    function hook.HideIcons(mask)
        local found = Find()
        if not found or index ~= 0 then return false end
        found.HideIcons = mask
        return true
    end
    -- The map grid the game prints after the time, "(H-9)", while current; nil otherwise.
    function hook.Grid()
        local found = Find()
        if not found or index ~= 0 or found.ClockRectFrame == 0 or
            (tonumber(found.Frame) - tonumber(found.ClockRectFrame)) % 4294967296 > 2 then return nil end
        local grid = ffi.string(found.Grid, 8):match('^[^%z]*')
        if not grid:match('^[%w%s%(%)%-]+$') then return nil end
        return grid
    end
    function hook.Status()
        local found = Find() -- detects unload, DLL replacement and capability loss before exposing a stale status
        if not found or not owned then return reason end
        local name = index == 0 and 'clock' or 'compass'
        local native, drawn = hook.Ages()
        if not native or native > 2 then
            return ('Ready, but the game is not drawing its %s, so neither it nor the replacement is shown (last seen: %s). Unload hidecompass and check the %s is on in the game\'s config.')
                :format(name, native and (native .. ' frames ago') or 'never', name)
        end
        if not drawn or drawn > 2 then
            return ('The game draws its %s, but uihook could not draw the replacement over it (last drawn: %s); the stock %s should show.')
                :format(name, drawn and (drawn .. ' frames ago') or 'never', name)
        end
        return ('Drawn in place of the game\'s %s (the game drew it %d frames ago).'):format(name, native)
    end
    return hook
end
return M
