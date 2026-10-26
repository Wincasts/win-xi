-- Keys kept from the game's chat editor, through uihook (independent keys ABI 1, magic UIHOOK-KEYS, uihook 1.61 or
-- newer). The editor reads each key in the game's own message loop, before the window procedure Ashita's key event
-- comes from, and sends the line on Enter's character: blocking the key event keeps nothing from it. uihook keeps a
-- press of each key named here from the game whole (its press, repeats, character and release), begun while it is
-- named; Ashita, imgui and every addon still see the key. The keys are named again each frame (Hold), or uihook gives
-- them back to the game three frames after the last.
--
--   local keys = require('winxi.gamekeys').new()
--   keys.Hold({ [13] = true, [9] = true }) -- virtual keys to keep, nil or {} for none; true where uihook keeps them
--   keys.Ready()                           -- true while uihook can keep keys from the game
--   keys.Status()
local ffi = require('ffi')
ffi.cdef[[typedef struct {
    char Magic[16]; uint32_t Version, Size, Frame, Supported;
    uint32_t Hold[8];
    volatile uint32_t HoldFrame;
    uint32_t Kept;
} uihook_keys_t;]]
local M = {}
function M.new()
    local block, base, looked = nil, nil, -1
    local reason = 'Load uihook 1.61 or newer to keep keys from the game\'s chat editor.'
    local function Find()
        if not AshitaCore:GetPluginManager():IsLoaded('uihook') then
            block, base, looked = nil, nil, -1
            reason = 'Load uihook 1.61 or newer to keep keys from the game\'s chat editor.'
            return nil
        end
        local current = ashita.memory.get_base('uihook.dll')
        if current ~= base then block, base, looked = nil, current, -1 end
        if not current or current == 0 then reason = 'uihook DLL is not ready.'; return nil end
        if not block then
            if os.clock() - looked < 1 then return nil end
            looked = os.clock()
            local at = ashita.memory.find('uihook.dll', 0, '5549484F4F4B2D4B4559530000000000', 0, 0)
            if not at or at == 0 then reason = 'Update uihook to 1.61 or newer: keys cannot be kept from the game.'; return nil end
            local found = ffi.cast('uihook_keys_t*', at)
            if found.Version ~= 1 or found.Size ~= ffi.sizeof('uihook_keys_t') then
                reason = 'uihook keys ABI mismatch; install the matching DLL.'; return nil
            end
            block = found
        end
        if block.Supported == 0 then reason = 'uihook did not find the game\'s input handler.'; return nil end
        return block
    end
    local hook = {}
    function hook.Ready() return Find() ~= nil end
    -- The words are written before HoldFrame, the commit uihook reads them by. Bit 31 is summed as a positive
    -- value: a negative bit.lshift(1, 31) stored in a uint32 came out 0 in Ashita's LuaJIT.
    function hook.Hold(keys)
        local b = Find()
        if not b then return false end
        local words = { 0, 0, 0, 0, 0, 0, 0, 0 }
        for vk, on in pairs(keys or {}) do
            vk = tonumber(vk)
            if on and vk and vk >= 0 and vk <= 255 and vk == math.floor(vk) then
                local word, at = math.floor(vk / 32) + 1, vk % 32
                if math.floor(words[word] / 2 ^ at) % 2 == 0 then words[word] = words[word] + 2 ^ at end
            end
        end
        for i = 1, 8 do b.Hold[i - 1] = words[i] end
        b.HoldFrame = b.Frame
        reason = ('Keeping keys from the game\'s chat editor; %d messages kept so far.'):format(tonumber(b.Kept))
        return true
    end
    function hook.Status()
        Find()
        return reason
    end
    return hook
end
return M
