-- The uihook plugin's menu mirror (mirror ABI 1, uihook 0.97): a window of the game's, named here, keeps
-- working as it is, its input, cursor and hit-tests the game's own, while what it draws is measured and,
-- if asked, left undrawn; the addon draws its own from what the game would have.
--
--   local nativemirror = require('winxi.nativemirror')
--   local mirror = nativemirror.new()
--   -- every frame, while mirroring:
--   mirror.Request({ { name = 'inventor', hide = true }, { name = 'iteminfo', hide = false } })
--   for _, window in ipairs(mirror.Windows(width, height) or {}) do ... end
--   -- when done (switched off, unloading):
--   mirror.Stop()
--
-- A name is the game's menu name without its "menu    " (at most 8 letters). A hidden window is left
-- undrawn by the game; a watched one (hide false) is drawn as ever and still published. Requests hold four
-- frames after the last; then the game draws them all again.
--
-- Windows(width, height) gives what the requested windows drew in the last frame presented, in display
-- pixels (width and height the display's), the same table while nothing has changed:
--   { name, hidden, focused, hasCursor, drewContent,
--     rect = { left, top, right, bottom },          the window's frame
--     cursor, selection, scroll = { ... } or nil,    the game's cursor, the element it is on, the scrollbar
--     scrollPage, scrollCount, scrollTop,            the scrollbar's rows shown, rows and rows above, where read
--     target = { x, y, width, height },              the game's layout target, in its own units
--     runs = { { text, raw, route, color = { r, g, b, a }, rect = { ... } or nil, x, y, phase } },
--     quads = { { rect, uv = { u1, v1, u2, v2 }, texture, color, phase } } }
-- A run's text is UTF-8, its raw the game's bytes; its rect where its glyphs were drawn (nil where none were
-- measured), x and y where the game was told to print it, in its units. A quad is a draw of the game's art: in
-- the contents (phase Content: an item's icon), or one of the window's own elements (phase Element: a label of
-- a menu whose words are pictures, a button), the one the cursor is on drawn tinted. texture is the game's
-- IDirect3DBaseTexture8 as a number, held by uihook for two frames presented, for imgui's AddImage; with the
-- window's name, uv is a label's lasting key.
local ffi = require('ffi')
local bit = require('bit')
ffi.cdef[[
    typedef struct {
        float Rect[4]; uint32_t Window, Route, Colour, Offset, Length, Phase; int16_t X, Y;
    } uihook_mirror_run_t;
    typedef struct {
        float Rect[4]; float UV[4]; uint32_t Window, Texture, Colour, Phase;
    } uihook_mirror_quad_t;
    typedef struct {
        char Name[16]; uint32_t Flags;
        float Rect[4], Cursor[4], Selection[4], Scroll[4];
        uint32_t CursorFrame, SelectionFrame, ScrollFrame;
        uint32_t ScrollPage, ScrollCount, ScrollTop;
        int16_t Target[4];
        uint32_t FirstRun, Runs, FirstQuad, Quads;
    } uihook_mirror_window_t;
    typedef struct {
        uint32_t Frame, WindowCount, RunCount, QuadCount, TextUsed;
        uihook_mirror_window_t Windows[16];
        uihook_mirror_run_t Runs[512];
        uihook_mirror_quad_t Quads[512];
        char Text[32768];
    } uihook_mirror_frame_t;
    typedef struct {
        char Magic[16]; uint32_t Version, Size, Frame, Supported;
        uint32_t RequestFrame, Hide;
        char Requests[32][16];
        uint32_t Serial, Dropped;
        uihook_mirror_frame_t Published;
    } uihook_mirror_t;
    int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char*, int, unsigned short*, int);
    int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const unsigned short*, int, char*, int, const char*, int*);
]]
local M = { Bitmap = 0, Scaled = 1, Font = 2, Requests = 32, Windows = 16,
    Frame = 0, Content = 1, Cursor = 2, Element = 3, Selection = 3, Scrollbar = 4, After = 5 }
local HAS_CURSOR, FOCUSED, HIDDEN, DREW_CONTENT = 1, 2, 4, 8
local MAGIC = '5549484F4F4B2D4D4952524F52000000' -- "UIHOOK-MIRROR", zeros to 16

-- The game's text to UTF-8: its colour codes (1E/1F and the byte after) and bitmap-font escapes (85 and the byte
-- after) taken out, then CP932 transcoded where there is anything past ASCII. Kept by the bytes, 512 at most.
local kernel -- loaded when first wanted; false where it cannot be (not Windows)
local decoded, decodedCount = {}, 0
local function Transcode(text)
    if kernel == nil then
        local ok, loaded = pcall(ffi.load, 'kernel32')
        kernel = ok and loaded or false
    end
    if not kernel then return nil end
    local count = kernel.MultiByteToWideChar(932, 0, text, #text, nil, 0)
    if count <= 0 then return nil end
    local wide = ffi.new('unsigned short[?]', count)
    if kernel.MultiByteToWideChar(932, 0, text, #text, wide, count) ~= count then return nil end
    local size = kernel.WideCharToMultiByte(65001, 0, wide, count, nil, 0, nil, nil)
    if size <= 0 then return nil end
    local output = ffi.new('char[?]', size)
    if kernel.WideCharToMultiByte(65001, 0, wide, count, output, size, nil, nil) ~= size then return nil end
    return ffi.string(output, size)
end
function M.Decode(raw)
    local known = decoded[raw]
    if known then return known end
    local text = raw
    if text:find('[\30\31\133]') then
        text = text:gsub('[\30\31\133].', '')
    end
    if text:find('[\128-\255]') then
        text = Transcode(text) or text:gsub('[\128-\255]', '?')
    end
    if decodedCount >= 512 then decoded, decodedCount = {}, 0 end
    decoded[raw], decodedCount = text, decodedCount + 1
    return text
end
-- The game's colour, components of 0x80 as one, as imgui's 0-1
function M.Color(value)
    local function part(shift) return math.min(1, bit.band(bit.rshift(value, shift), 0xff) / 128) end
    return { part(16), part(8), part(0), part(24) }
end

-- A name as the game keeps it: "menu    " and the name, padded with spaces to 16
local function Padded(name)
    if type(name) ~= 'string' or name == '' or #name > 8 or name:find('[^%w_]') then return nil end
    return 'menu    ' .. name .. (' '):rep(8 - #name)
end

function M.new()
    local block, base, looked, owned = nil, nil, -1, false
    local reason = 'Load uihook 0.97 or newer for menu mirroring.'
    local cached, cachedSerial, cachedWidth, cachedHeight = nil, -1, 0, 0
    local function Find()
        if not AshitaCore:GetPluginManager():IsLoaded('uihook') then
            block, base, looked, owned = nil, nil, -1, false
            reason = 'Load uihook 0.97 or newer for menu mirroring.'
            return nil
        end
        local current = ashita.memory.get_base('uihook.dll')
        if current ~= base then block, base, looked, owned, cachedSerial = nil, current, -1, false, -1 end
        if not current or current == 0 then reason = 'uihook DLL is not ready.'; return nil end
        if not block then
            if os.clock() - looked < 1 then return nil end
            looked = os.clock()
            -- the block among the places the magic is found, by its version and size
            for which = 0, 3 do
                local at = ashita.memory.find('uihook.dll', 0, MAGIC, 0, which)
                if not at or at == 0 then break end
                local found = ffi.cast('uihook_mirror_t*', at)
                if found.Version == 2 and found.Size == ffi.sizeof('uihook_mirror_t') then block = found; break end
            end
            if not block then reason = 'Update uihook: menu mirroring (mirror ABI 2) is unavailable.'; return nil end
        end
        if block.Supported == 0 then reason = 'uihook did not recognise the game\'s menu drawing; menus unchanged.'; return nil end
        return block
    end
    local hook = {}
    -- The windows to mirror this frame: { { name = 'inventor', hide = true }, ... }, at most 32
    function hook.Request(list)
        local b = Find()
        if not b then return false end
        local hide, count = 0, 0
        for i = 0, M.Requests - 1 do ffi.fill(b.Requests[i], 16) end
        for _, entry in ipairs(type(list) == 'table' and list or {}) do
            local name = type(entry) == 'table' and Padded(entry.name)
            if name and count < M.Requests then
                ffi.copy(b.Requests[count], name, 16)
                if entry.hide then hide = bit.bor(hide, bit.lshift(1, count)) end
                count = count + 1
            end
        end
        b.Hide = hide
        b.RequestFrame = count > 0 and b.Frame or 0 -- the commit, after the names
        owned = count > 0
        reason = count > 0 and ('Mirroring %d menu window%s.'):format(count, count == 1 and '' or 's') or 'Nothing asked.'
        return true
    end
    function hook.Stop()
        if not owned then return end
        local b = Find()
        if b then b.RequestFrame = 0 end
        owned = false
    end
    local function Rect(r, width, height)
        for i = 0, 3 do
            if r[i] ~= r[i] or math.abs(r[i]) > 4 then return nil end
        end
        if r[2] <= r[0] or r[3] <= r[1] then return nil end
        return { tonumber(r[0]) * width, tonumber(r[1]) * height, tonumber(r[2]) * width, tonumber(r[3]) * height }
    end
    -- What the requested windows drew in the last frame presented, or nil where nothing is fresh
    function hook.Windows(width, height)
        local b = Find()
        if not b or type(width) ~= 'number' or type(height) ~= 'number' or width <= 0 or height <= 0 then return nil end
        local frame = b.Published
        if frame.Frame == 0 or b.Frame - frame.Frame > 2 then return nil end
        if cached and b.Serial == cachedSerial and width == cachedWidth and height == cachedHeight then return cached end
        local windows = {}
        for i = 0, math.min(frame.WindowCount, M.Windows) - 1 do
            local w = frame.Windows[i]
            local flags = w.Flags
            local name = ffi.string(w.Name, 16):sub(9):gsub(' +$', '')
            local out = { name = name, hidden = bit.band(flags, HIDDEN) ~= 0, focused = bit.band(flags, FOCUSED) ~= 0,
                hasCursor = bit.band(flags, HAS_CURSOR) ~= 0, drewContent = bit.band(flags, DREW_CONTENT) ~= 0,
                rect = Rect(w.Rect, width, height),
                cursor = w.CursorFrame ~= 0 and Rect(w.Cursor, width, height) or nil,
                selection = w.SelectionFrame ~= 0 and Rect(w.Selection, width, height) or nil,
                scroll = w.ScrollFrame ~= 0 and Rect(w.Scroll, width, height) or nil,
                scrollPage = w.ScrollPage, scrollCount = w.ScrollCount, scrollTop = w.ScrollTop,
                target = { w.Target[0], w.Target[1], w.Target[2], w.Target[3] },
                runs = {}, quads = {} }
            for r = w.FirstRun, math.min(w.FirstRun + w.Runs, frame.RunCount) - 1 do
                local run = frame.Runs[r]
                if run.Offset + run.Length <= frame.TextUsed then
                    local raw = ffi.string(frame.Text + run.Offset, run.Length)
                    out.runs[#out.runs + 1] = { raw = raw, text = M.Decode(raw), route = run.Route, color = M.Color(run.Colour),
                        rect = Rect(run.Rect, width, height), x = run.X, y = run.Y, phase = run.Phase }
                end
            end
            for q = w.FirstQuad, math.min(w.FirstQuad + w.Quads, frame.QuadCount) - 1 do
                local quad = frame.Quads[q]
                local rect = Rect(quad.Rect, width, height)
                if rect then
                    out.quads[#out.quads + 1] = { rect = rect, uv = { quad.UV[0], quad.UV[1], quad.UV[2], quad.UV[3] },
                        texture = quad.Texture ~= 0 and tonumber(quad.Texture) or nil, color = M.Color(quad.Colour), phase = quad.Phase }
                end
            end
            windows[#windows + 1] = out
        end
        cached, cachedSerial, cachedWidth, cachedHeight = windows, b.Serial, width, height
        return windows
    end
    function hook.Supported() return Find() ~= nil end
    function hook.Status() Find(); return reason end
    return hook
end
return M
