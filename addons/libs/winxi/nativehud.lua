-- Uihook's independent clock/compass capture slots. No ImGui or texture pointers cross Lua.
local ffi = require('ffi')
local bit = require('bit')
ffi.cdef[[
    typedef struct {
        char Magic[16];
        uint32_t Version, Size, SupportedMask, Frame, Submit;
        uint32_t DrawnFrame[2], NativeFrame[2];
        uint32_t Weather;
    } uihook_hud_t;
    typedef int32_t (__cdecl *uihook_hud_submit_t)(int32_t index, int32_t capture);
]]
local M = { Clock = 0, Compass = 1 }
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
            if found.Version ~= 1 or found.Size ~= ffi.sizeof('uihook_hud_t') or found.Submit == 0 then
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
        if owned and Find() then submit(index, -1) end
        owned = false
    end
    function hook.Weather()
        local found = Find()
        if not found or found.NativeFrame[0] == 0 or
            (tonumber(found.Frame) - tonumber(found.NativeFrame[0])) % 4294967296 > 2 or found.Weather > 19 then return nil end
        return tonumber(found.Weather)
    end
    function hook.Status()
        Find() -- detects unload, DLL replacement and capability loss before exposing a stale status
        return reason
    end
    return hook
end
return M
