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
        uint32_t TextFrame, TextCount, TextSerial;
        struct { float Rect[4]; uint32_t Offset, Length, Mode, Flags; } Rows[128];
        char Text[65536];
        float SplitRect[4];
        uint32_t SplitRectFrame;
        uint32_t WindowFrame, WindowFlags;
        uint32_t WindowModes[2][8];
        uint32_t LinesFrame;
        uint32_t Lines[2][3];
        uint32_t ColorFrame, ColorSerial;
        uint32_t InlineColors[17];
        uint32_t CategoryColors[256];
        uint8_t ModeCategory[256];
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
            if found.Version ~= 13 or found.Size ~= ffi.sizeof('uihook_chat_t') or found.Submit == 0 then
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
    -- cursor, scrollbar), and replace, which of them the addon draws itself, { tabs = true, scrollbar = true,
    -- text = true, all = true }: those the game leaves undrawn, their hit-tests still its own; all, with the tabs
    -- and text, leaves nothing of the full log drawn (its row light, cursor and marks as well). Tabs(), Scrollbar()
    -- and Rows() say where.
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
            if expandedFrame and type(replace) == 'table' then
                local bits = 0
                if bit.band(found.SupportedMask,64) ~= 0 then bits = (replace.tabs and 1 or 0) + (replace.scrollbar and 2 or 0) end
                if bit.band(found.SupportedMask,128) ~= 0 and replace.text then bits = bits + 4 end
                -- all of it: the row light, cursor and marks too, only with the addon's tabs and text
                if bit.band(found.SupportedMask,2048) ~= 0 and replace.all and bit.band(bits,5) == 5 then bits = bits + 8 end
                found.ReplaceControls = bits
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
    -- Native focus/expansion only: no button interception or native menu/state writes. nested: a menu (a
    -- row's actions, the input line) is open over the live full log, which is still drawn under it.
    -- selectedWindow: which log window the game's focus is on, 1 or 2, or nil.
    function hook.State()
        local found = Find()
        if not found or found.StateFrame == 0 or (tonumber(found.Frame)-tonumber(found.StateFrame)) % 4294967296 > 2 then return nil end
        local flags = tonumber(found.StateFlags)
        return { selected = bit.band(flags,3) ~= 0, selectedWindow = bit.band(flags,1) ~= 0 and 1 or bit.band(flags,2) ~= 0 and 2 or nil,
            expanded = bit.band(flags,4) ~= 0,
            nativeBrowse = bit.band(flags,8) ~= 0, nested = bit.band(flags,16) ~= 0, expandedSupported = bit.band(found.SupportedMask,8) ~= 0,
            nativeContent = bit.band(found.SupportedMask,16) ~= 0,
            nativeControls = bit.band(found.SupportedMask,32) ~= 0,
            nativeReplace = bit.band(found.SupportedMask,64) ~= 0,
            nativeText = bit.band(found.SupportedMask,128) ~= 0,
            nativeMirror = bit.band(found.SupportedMask,2048) ~= 0,
            nativeWindows = bit.band(found.SupportedMask,256) ~= 0,
            nativeLines = bit.band(found.SupportedMask,512) ~= 0,
            nativeColors = bit.band(found.SupportedMask,1024) ~= 0,
            scroll = tonumber(found.FullScroll), cursor = tonumber(found.FullCursor),
            pageRows = tonumber(found.FullPageRows), filter = tonumber(found.FullFilter) }
    end
    -- Fresh: stamped within the last two frames, or as many as given. Display: a size to scale normalized bounds to.
    local function Fresh(found, stamp, frames)
        stamp = tonumber(stamp)
        return stamp ~= 0 and (tonumber(found.Frame) - stamp) % 4294967296 <= (frames or 2)
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
    -- Topmost stacked compact replacement frame in display pixels (primary for side-by-side
    -- logs; the upper split for stacked logs), only while it is also eligible to
    -- relocate the native clock (same freshness/visibility rules as ChatClockOffset in uihook).
    -- Read-only: observing the primary slot never claims or stops its replacement.
    function hook.ClockAnchor()
        local found = Find()
        if not found or index ~= M.Primary or bit.band(found.StateFlags, 4) ~= 0 then return nil end
        for _, stamp in ipairs({ found.PrimaryRectFrame, found.NativeFrame[0], found.DrawnFrame[0] }) do
            if not Fresh(found, stamp) then return nil end
        end
        -- the replacement's place is sent with it: good for uihook's CHAT_REQUEST_FRAMES (8)
        if not Fresh(found, found.ReplacementRectFrame, 8) then return nil end
        for _, r in ipairs({ found.PrimaryRect, found.ReplacementRect }) do
            for i = 0, 3 do
                if r[i] ~= r[i] or math.abs(r[i]) == math.huge then return nil end
            end
            if r[2] <= r[0] or r[3] <= r[1] then return nil end
        end
        local r = found.ReplacementRect
        return tonumber(r[0]), tonumber(r[1]), tonumber(r[2]), tonumber(r[3])
    end
    -- Native primary/split/input bounds; expanded=true selects fulllog on the primary slot. The split log's
    -- bounds (the game's second log window) need uihook's window routing.
    function hook.Rect(width, height, expanded)
        local found = Find()
        if not found then return nil end
        if expanded and (index ~= M.Primary or bit.band(found.SupportedMask,8) == 0) then return nil end
        if index == M.Secondary and bit.band(found.SupportedMask,256) == 0 then return nil end
        local stamp = expanded and found.ExpandedRectFrame or index == M.Primary and found.PrimaryRectFrame
            or index == M.Secondary and found.SplitRectFrame or found.InputRectFrame
        if not Fresh(found, stamp) or not Display(width, height) then return nil end
        return Scaled(expanded and found.ExpandedRect or index == M.Primary and found.PrimaryRect
            or index == M.Secondary and found.SplitRect or found.InputRect, width, height)
    end
    -- This log window's lines as the game has them now: shown, how many lines it shows at the moment (the game adds a
    -- row for each message and takes rows away, down to its fewest, while none come; 0, nothing shown), most, the
    -- lines it grows to, and fewest. The same table while they hold. nil without the lines hooks, or nothing fresh,
    -- or on the input slot.
    local linesList
    function hook.Lines()
        local found = Find()
        if not found or index == M.Input or bit.band(found.SupportedMask,512) == 0 then return nil end
        if not Fresh(found, found.LinesFrame) then return nil end
        local shown, most, fewest = tonumber(found.Lines[index][0]), tonumber(found.Lines[index][1]), tonumber(found.Lines[index][2])
        if not linesList or linesList.shown ~= shown or linesList.most ~= most or linesList.fewest ~= fewest then
            linesList = { shown = shown, most = most, fewest = fewest }
        end
        return linesList
    end
    -- The game's chat colours as it has them now, the user's configuration included: Mode(mode), the colour it draws
    -- a message of that chat mode in (white, as the game's, for a mode it has no entry for); Inline(bank, slot), the
    -- colour a 1E (bank 30) or 1F (bank 31) code names, or nil where the code returns to the row's own colour (1E 00,
    -- 1E 01, and the palette's unset slots). Each is { r, g, b, a } in 0 to 1, the game's components (of 80 as one)
    -- clamped. The same table while the colours hold. nil without the colour hooks, or nothing fresh.
    local colorsSerial, colorsList
    function hook.Colors()
        local found = Find()
        if not found or index ~= M.Primary or bit.band(found.SupportedMask,1024) == 0 then return nil end
        if not Fresh(found, found.ColorFrame) then return nil end
        local serial = tonumber(found.ColorSerial)
        if colorsList and colorsSerial == serial then return colorsList end
        local function Color(value)
            value = tonumber(value) or 0
            if value == 0 then return nil end
            local a, r, g, b = bit.band(bit.rshift(value, 24), 255), bit.band(bit.rshift(value, 16), 255), bit.band(bit.rshift(value, 8), 255), bit.band(value, 255)
            return { math.min(1, r / 128), math.min(1, g / 128), math.min(1, b / 128), math.min(1, a / 128) }
        end
        local unknown = Color(0x80808080) -- what the game draws a mode or category it has no entry for in: white
        local categories, modes, inline30, inline31 = {}, {}, {}, {}
        for i = 0, 255 do categories[i] = Color(found.CategoryColors[i]) end
        for mode = 0, 255 do
            local category = tonumber(found.ModeCategory[mode])
            modes[mode] = category ~= 0 and categories[category] or unknown
        end
        for slot = 0, 255 do
            if slot < 17 then inline30[slot] = Color(found.InlineColors[slot]) else inline30[slot] = categories[slot] or unknown end
            inline31[slot] = modes[slot]
        end
        inline31[1] = nil -- 1F 01, as 1E 01: the row's own colour
        colorsSerial, colorsList = serial, { serial = serial,
            Mode = function(mode) mode = tonumber(mode); return mode and modes[bit.band(mode, 255)] or nil end,
            Inline = function(bank, slot)
                slot = tonumber(slot)
                if not slot then return nil end
                if bank == 0x1e then return inline30[bit.band(slot, 255)] end
                if bank == 0x1f then return inline31[bit.band(slot, 255)] end
                return nil
            end }
        return colorsList
    end
    -- The game's routing of messages between its two log windows, as uihook reads it from the game's config each
    -- frame: split, whether the second window is shown (then each message goes where the game's Log Window
    -- settings send it; hidden, the first shows everything); first and second, the set of chat modes (the low
    -- byte) each window's filters keep. M.Shows applies them. The same table while the routing holds. nil without
    -- the routing hooks, or nothing fresh.
    local routesWords, routesList
    function hook.Routes()
        local found = Find()
        if not found or index ~= M.Primary or bit.band(found.SupportedMask,256) == 0 then return nil end
        if not Fresh(found, found.WindowFrame) then return nil end
        local split = bit.band(tonumber(found.WindowFlags), 1) ~= 0
        local same = routesList ~= nil and routesList.split == split
        if same then
            for i = 1, 16 do
                if routesWords[i] ~= tonumber(found.WindowModes[math.floor((i - 1) / 8)][(i - 1) % 8]) then same = false; break end
            end
        end
        if same then return routesList end
        local words, sets = {}, { {}, {} }
        for w = 0, 1 do
            for i = 0, 7 do
                local word = tonumber(found.WindowModes[w][i])
                words[w * 8 + i + 1] = word
                for b = 0, 31 do
                    if bit.band(word, bit.lshift(1, b)) ~= 0 then sets[w + 1][i * 32 + b] = true end
                end
            end
        end
        routesWords, routesList = words, { split = split, first = sets[1], second = sets[2] }
        return routesList
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
    -- The game's rows of text as it last drew them in the skinned full log, in the order it drew them (the
    -- newest first): each with its bounds in display pixels (left, top, right, bottom; nil where the row drew
    -- nothing and the game's place for it was not known), its text as the game was given it (CP932 bytes with
    -- the game's 1E/1F colour codes; '' for an empty row), its chat mode, and cursor (the game's cursor is on
    -- it), pressed (held down on it), lit (under the game's row highlight), marked (the game marks it) and cut (longer than the room to publish it). The same table again while
    -- the rows are what they were. nil when there are none, or none fresh.
    local rowsSerial, rowsWidth, rowsHeight, rowsList
    function hook.Rows(width, height)
        local found = Find()
        if not found or index ~= M.Primary or bit.band(found.SupportedMask,128) == 0 then return nil end
        if not Fresh(found, found.TextFrame) or not Display(width, height) then return nil end
        local serial = tonumber(found.TextSerial)
        if rowsList and rowsSerial == serial and rowsWidth == width and rowsHeight == height then return rowsList end
        local list = {}
        for i = 0, math.min(tonumber(found.TextCount), 128) - 1 do
            local row = found.Rows[i]
            local flags, offset, length = tonumber(row.Flags), tonumber(row.Offset), tonumber(row.Length)
            local text = ''
            if length > 0 and offset + length <= 65536 then text = ffi.string(found.Text + offset, length) end
            local entry = { text = text, mode = tonumber(row.Mode), cursor = bit.band(flags, 1) ~= 0,
                pressed = bit.band(flags, 2) ~= 0, marked = bit.band(flags, 4) ~= 0, cut = bit.band(flags, 8) ~= 0,
                lit = bit.band(flags, 32) ~= 0 }
            if bit.band(flags, 16) ~= 0 then entry.left, entry.top, entry.right, entry.bottom = Scaled(row.Rect, width, height) end
            list[#list + 1] = entry
        end
        if #list == 0 then return nil end
        rowsSerial, rowsWidth, rowsHeight, rowsList = serial, width, height, list
        return list
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
-- Whether the game's window (1 or 2) shows a message of that chat mode, by routes from Routes(): the game's own
-- rule, a mode word with bit 15 set to the first window alone, else the window's set by the mode's low byte;
-- without routes, or with the second window hidden, the first shows everything and the second nothing.
function M.Shows(routes, window, mode)
    mode = tonumber(mode) or 0
    if not routes or not routes.split then return window == 1 end
    if bit.band(mode, 0x8000) ~= 0 then return window == 1 end
    local set = window == 1 and routes.first or window == 2 and routes.second or nil
    return set ~= nil and set[bit.band(mode, 0xff)] == true
end
return M
