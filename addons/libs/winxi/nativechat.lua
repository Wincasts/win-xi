-- Primary/split native chat and input replacement. Capture inside an ImGui window on the render thread.
local ffi = require('ffi')
local bit = require('bit')
ffi.cdef[[
    typedef struct {
        char Magic[16];
        uint32_t Version, Size, SupportedMask, Frame, Submit;
        uint32_t DrawnFrame[3], NativeFrame[3];
        float InputRect[4];
        uint32_t InputRectFrame;
        float PrimaryRect[4];
        uint32_t PrimaryRectFrame;
        float ReplacementRect[4];
        uint32_t ReplacementRectFrame;
        float ExpandedRect[4];
        uint32_t ExpandedRectFrame;
        uint32_t StateFlags, StateFrame;
        uint32_t FullScroll, FullCursor, FullPageRows, FullFilter;
        uint32_t ControlStyleFrame;
        float ControlColors[4][4];
        uint32_t ReplaceControls;
        uint32_t TabFrame, TabCount;
        struct { float Rect[4]; uint32_t Channel, Selected; } Tabs[12];
        uint32_t ScrollFrame, ScrollPage, ScrollCount, ScrollTop;
        float ScrollRect[4];
    } uihook_chat_t;
    typedef int32_t (__cdecl *uihook_chat_submit_t)(int32_t index, int32_t capture);
]]
local M = { Primary = 0, Secondary = 1, Input = 2 }
function M.new(index)
    assert(index == 0 or index == 1 or index == 2, 'native chat slot must be primary, secondary or input')
    local block, submit, base, looked, owned = nil, nil, nil, -1, false
    local reason = 'Load /load uihook with chat support.'
    local function Find()
        if not AshitaCore:GetPluginManager():IsLoaded('uihook') then
            block, submit, base, looked, owned = nil, nil, nil, -1, false
            reason = 'Load /load uihook with chat support.'
            return nil
        end
        local current = ashita.memory.get_base('uihook.dll')
        if current ~= base then
            block, submit, base, looked, owned = nil, nil, current, -1, false
        end
        if not current or current == 0 then reason = 'uihook DLL is not ready.'; return nil end
        if not block then
            if os.clock() - looked < 1 then return nil end
            looked = os.clock()
            local at = ashita.memory.find('uihook.dll', 0, '5549484F4F4B2D434841540000000000', 0, 0)
            if not at or at == 0 then reason = 'Update uihook: chat shared block not found.'; return nil end
            local found = ffi.cast('uihook_chat_t*', at)
            if found.Version ~= 9 or found.Size ~= ffi.sizeof('uihook_chat_t') or found.Submit == 0 then
                reason = 'uihook chat ABI mismatch; install the matching DLL.'; return nil
            end
            block, submit = found, ffi.cast('uihook_chat_submit_t', found.Submit)
        end
        if block.Submit == 0 or bit.band(block.SupportedMask, bit.lshift(1, index)) == 0 then
            reason = 'uihook did not recognise this client\'s chat window.'
            return nil
        end
        return block
    end
    local hook = {}
    -- Renew an intentionally hidden log. Call every frame, also before Capture.
    function hook.Begin()
        if not Find() then return false end
        owned = submit(index, 0) ~= 0
        reason = owned and 'Native chat replacement ready.' or 'uihook rejected the frame.'
        return owned
    end
    -- Copy/consume this ImGui window's GPU commands, leaving its layout/hit testing intact.
    -- For the expanded log: controls, the theme's colours for the game's own controls (highlight, tab,
    -- cursor, scrollbar), and replace, which of them the addon draws itself, { tabs = true, scrollbar = true }:
    -- those the game leaves undrawn, their hit-tests still its own. Tabs() and Scrollbar() say where.
    function hook.Capture(expandedFrame, controls, replace)
        local found = Find()
        if not found or not owned then return false end
        if expandedFrame and (index ~= M.Primary or bit.band(found.SupportedMask,16) == 0) then
            hook.Stop()
            reason = 'Update uihook: native expanded-chat frame support unavailable.'
            return false
        end
        -- Publish colours atomically via the final frame stamp. Invalid/missing styles simply
        -- leave native artwork untinted; they must never compromise native chat rendering.
        if index == M.Primary then
            found.ControlStyleFrame = 0
            found.ReplaceControls = 0
            if expandedFrame and bit.band(found.SupportedMask,64) ~= 0 and type(replace) == 'table' then
                found.ReplaceControls = (replace.tabs and 1 or 0) + (replace.scrollbar and 2 or 0)
            end
            if expandedFrame and bit.band(found.SupportedMask,32) ~= 0 and type(controls) == 'table' then
                local valid = true
                for i=1,4 do
                    for j=1,4 do
                        local n = type(controls[i]) == 'table' and tonumber(controls[i][j]) or nil
                        if not n or n ~= n or n < 0 or n > 1 then valid = false
                        else found.ControlColors[i-1][j-1] = n end
                    end
                end
                if valid then found.ControlStyleFrame = found.Frame end
            end
        end
        local ok = submit(index, expandedFrame and 2 or 1) ~= 0
        if not ok then
            submit(index, -1) -- never leave Begin's empty hide behind after a failed capture
            owned = false
            reason = 'Chat capture failed; native chat restored.'
        end
        return ok
    end
    function hook.Stop()
        local found = Find()
        if found and index == M.Primary then found.ControlStyleFrame = 0; found.ReplaceControls = 0 end
        if found and owned then submit(index, -1) end
        owned = false
    end
    function hook.Ages()
        local found = Find()
        if not found then return nil, nil end
        local function Age(frame)
            frame = tonumber(frame)
            if frame == 0 then return nil end
            return (tonumber(found.Frame) - frame) % 4294967296
        end
        return Age(found.NativeFrame[index]), Age(found.DrawnFrame[index])
    end
    -- Native focus/expansion only: no button interception or native menu/state writes.
    function hook.State()
        local found = Find()
        if not found or found.StateFrame == 0 or (tonumber(found.Frame)-tonumber(found.StateFrame)) % 4294967296 > 2 then return nil end
        local flags = tonumber(found.StateFlags)
        return { selected = bit.band(flags,3) ~= 0, expanded = bit.band(flags,4) ~= 0,
            nativeBrowse = bit.band(flags,8) ~= 0, expandedSupported = bit.band(found.SupportedMask,8) ~= 0,
            nativeContent = bit.band(found.SupportedMask,16) ~= 0,
            nativeControls = bit.band(found.SupportedMask,32) ~= 0,
            nativeReplace = bit.band(found.SupportedMask,64) ~= 0,
            scroll = tonumber(found.FullScroll), cursor = tonumber(found.FullCursor),
            pageRows = tonumber(found.FullPageRows), filter = tonumber(found.FullFilter) }
    end
    -- Fresh: stamped within the last two frames. Display: a size to scale normalized bounds to.
    local function Fresh(found, stamp)
        stamp = tonumber(stamp)
        return stamp ~= 0 and (tonumber(found.Frame) - stamp) % 4294967296 <= 2
    end
    local function Display(width, height)
        return type(width) == 'number' and type(height) == 'number' and width == width and height == height
            and width > 0 and height > 0 and width <= 32768 and height <= 32768
    end
    -- Normalized bounds scaled to the display, or nil where they are not a rectangle
    local function Scaled(r, width, height)
        for i = 0, 3 do
            if r[i] ~= r[i] or math.abs(r[i]) > 4 then return nil end
        end
        if r[2] <= r[0] or r[3] <= r[1] then return nil end
        return tonumber(r[0]) * width, tonumber(r[1]) * height, tonumber(r[2]) * width, tonumber(r[3]) * height
    end
    -- Native primary/input bounds; expanded=true selects fulllog on the primary slot.
    function hook.Rect(width, height, expanded)
        local found = Find()
        if not found or (index ~= M.Primary and index ~= M.Input) then return nil end
        if expanded and (index ~= M.Primary or bit.band(found.SupportedMask,8) == 0) then return nil end
        if not Fresh(found, expanded and found.ExpandedRectFrame or index == M.Primary and found.PrimaryRectFrame or found.InputRectFrame) then return nil end
        if not Display(width, height) then return nil end
        return Scaled(expanded and found.ExpandedRect or index == M.Primary and found.PrimaryRect or found.InputRect, width, height)
    end
    -- The game's tab strip as it last drew it in the skinned full log: each tab's bounds in display pixels,
    -- in the order the game drew them (they overlap at their edges, each drawn over the ones before it),
    -- its channel (the filter's number, 0 to 10; nil where the sprite was none of the known tabs) and
    -- whether it was drawn chosen. nil when there is none, or none fresh.
    function hook.Tabs(width, height)
        local found = Find()
        if not found or index ~= M.Primary or bit.band(found.SupportedMask,64) == 0 then return nil end
        if not Fresh(found, found.TabFrame) or not Display(width, height) then return nil end
        local list = {}
        for i = 0, math.min(tonumber(found.TabCount), 12) - 1 do
            local tab = found.Tabs[i]
            local left, top, right, bottom = Scaled(tab.Rect, width, height)
            if left then
                local channel = tonumber(tab.Channel)
                list[#list + 1] = { left = left, top = top, right = right, bottom = bottom,
                    channel = channel <= 10 and channel or nil, selected = tab.Selected ~= 0 }
            end
        end
        if #list == 0 then return nil end
        return list
    end
    -- The game's scrollbar as it last drew it there: its bounds in display pixels, and its rows, page
    -- (shown at once), count (in all) and above (scrolled past, above the view). nil when the game drew
    -- none (every row fits), or none fresh.
    function hook.Scrollbar(width, height)
        local found = Find()
        if not found or index ~= M.Primary or bit.band(found.SupportedMask,64) == 0 then return nil end
        if not Fresh(found, found.ScrollFrame) or not Display(width, height) then return nil end
        local left, top, right, bottom = Scaled(found.ScrollRect, width, height)
        if not left then return nil end
        local page, count, above = tonumber(found.ScrollPage), tonumber(found.ScrollCount), tonumber(found.ScrollTop)
        if page < 1 or count < 0 or above < 0 or above > count then return nil end
        return { left = left, top = top, right = right, bottom = bottom, page = page, count = count, above = above }
    end
    function hook.Status()
        if not Find() then return reason end
        if not owned then return 'Native chat is not claimed by this bridge.' end
        local native = hook.Ages()
        if not native or native > 2 then return 'Ready; the game is not drawing this chat log (closed, zoning, split chat disabled or input inactive).' end
        return reason
    end
    return hook
end
return M
