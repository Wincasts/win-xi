-- uihook's mirror of the windows the game stacks over its chat log (mirror ABI 6, uihook 1.59): while this asks each
-- frame, those windows keep working as they are (their input, cursor and hit-tests the game's own) while what they
-- draw is measured, published and left undrawn, for nativeui to draw them again in the winxi look. Each is measured
-- where the native look draws it (the group's move, Menu Scale), so drawn from this it is where the game's mouse
-- works it. Revived from winxi.nativemirror (ABI 5, retired in winxi 43), which mirrored any window by its name.
--
--   local mirror = require('groupmirror').new()
--   mirror.Request({ 'comyn' })                   -- every frame: the group mirrored, but those named, kept for the game
--   for _, window in ipairs(mirror.Windows(width, height) or {}) do ... end
--   mirror.Stop()                                 -- switched off, unloaded: the game draws the group again
--
-- Windows(width, height) gives what the group drew in the last frame presented, in display pixels, the same table while
-- nothing has changed: { name, hidden, kept, focused, hasCursor, drewContent, rect, cursor, selection, scroll,
-- scrollPage, scrollCount, scrollTop, target, runs, quads } as winxi.nativemirror gave them; kept: one named to Request,
-- drawn by the game. Words(quads) reads the letters a window spells from the game's fonts back as words.
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
        uihook_mirror_quad_t Quads[1024];
        char Text[32768];
    } uihook_mirror_frame_t;
    typedef struct {
        char Magic[16]; uint32_t Version, Size, Frame, Supported;
        char Kept[16][16];
        uint32_t RequestFrame;
        uint32_t Serial, Dropped;
        uihook_mirror_frame_t Published;
    } uihook_mirror_t;
    int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char*, int, unsigned short*, int);
    int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const unsigned short*, int, char*, int, const char*, int*);
]]
local M = { Bitmap = 0, Scaled = 1, Font = 2, Kept = 16, Windows = 16,
    Frame = 0, Content = 1, Cursor = 2, Element = 3, Selection = 3, Scrollbar = 4, After = 5 }
local HAS_CURSOR, FOCUSED, HIDDEN, DREW_CONTENT, KEPT = 1, 2, 4, 8, 16
local VERSION = 6
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

-- The letters of the game's menu font (the 256x256 sheet the main and command menus spell their labels from, one
-- element a letter): each one's box in the sheet, in texels, as the game cuts it. Read from the sheet and the
-- game's own boxes (uihook's /uihook mirror labels); a quad whose uv is within LETTER_SLACK texels of one on
-- every side is that letter. A sheet of another size (a font replaced) matches nothing and is drawn as art.
local LETTERS = {
    '!',14,0,16,10, '"',21,0,27,10, '#',30,0,38,10, '$',42,0,49,10, '%',51,0,60,10, '&',61,0,70,10,
    '\'',74,0,77,10, '(',82,0,86,10, ')',95,0,99,10, '*',101,0,110,10, '+',112,0,118,10, ',',3,14,6,24,
    '-',12,14,17,24, '.',24,14,27,24, '/',32,14,38,24, '0',42,14,48,24, '1',52,14,56,24, '2',62,14,68,24,
    '3',72,14,78,24, '4',81,14,88,24, '5',92,14,98,24, '6',101,14,108,24, '7',112,14,118,24, '8',1,27,8,37,
    '9',10,27,17,37, ':',20,27,23,37, ';',26,27,29,37, '<',32,27,36,37, '=',41,27,46,37, '>',49,27,54,37,
    '?',57,27,64,37, '@',67,27,75,37, 'A',77,26,86,37, 'B',89,27,96,37, 'C',98,27,104,37, 'D',109,27,115,37,
    '...',118,27,123,37, 'E',0,39,9,50, 'F',13,40,18,49, 'G',21,40,28,49, 'H',33,40,39,49, 'I',42,39,48,50,
    'J',50,40,56,49, 'K',60,40,66,49, 'L',69,39,78,50, 'M',80,39,89,50, 'N',93,40,100,49, 'O',103,40,111,49,
    'P',113,39,122,50, 'Q',1,53,8,63, 'R',11,52,21,63, 'S',22,52,31,64, 'T',31,52,40,63, 'U',43,53,49,63,
    'V',53,53,60,63, 'W',64,53,71,63, 'X',78,53,85,63, 'Y',89,53,96,63, 'Z',100,53,107,63, '[',115,53,119,63,
    '\\',3,66,8,77, ']',14,66,18,77, '^',22,66,28,77, '_',32,66,39,77, '`',43,66,47,77, 'a',49,67,57,76,
    'b',58,65,67,76, 'c',68,67,77,76, 'd',78,65,87,76, 'e',89,67,98,76, 'f',99,65,106,76, 'g',107,67,116,79,
    'h',0,78,9,89, 'i',10,78,15,89, 'j',18,79,22,90, 'k',25,78,34,89, 'l',35,78,41,89, 'm',42,80,51,89,
    'n',56,80,65,89, 'o',66,80,75,89, 'p',76,80,85,92, 'q',87,80,96,92, 'r',98,80,105,89, 's',106,80,115,89,
    '©',117,79,126,90, 't',0,92,6,102, 'u',7,93,16,102, 'v',18,92,24,104, 'w',28,92,35,104, 'x',40,92,47,104,
    'y',50,93,59,105, 'z',61,92,67,104, '{',72,92,77,104, '}',93,92,98,104, 
    '|',3,117,6,127, '~',9,117,16,127
}
-- The serif italic letters of a window's title ("Commands"), from another sheet of the same size; their boxes lie
-- apart from the menu font's, so a box is one font's or the other's
local TITLE_LETTERS = {
    'A',3,161,11,170, 'B',13,161,21,170, 'C',24,161,32,170, 'D',34,161,43,170, 'E',45,161,53,170, 'F',55,161,63,170,
    'G',66,161,74,170, 'H',76,161,85,170, 'I',87,161,92,170, 'J',94,161,102,170, 'K',104,161,113,170, 'L',115,161,122,170,
    'M',124,161,135,170, 'N',137,161,146,170, 'O',148,161,156,170, 'P',158,161,166,170, 'Q',169,161,177,172, 'R',179,161,188,170,
    'S',191,161,198,170, 'T',201,161,208,170, 'U',211,161,219,170, 'V',221,161,230,170, 'W',231,161,242,170, 'X',243,161,253,170,
    'Y',4,173,12,182, 'Z',13,173,21,182, 'a',23,175,29,182, 'b',32,173,38,182, 'c',41,175,47,182, 'd',50,173,56,182,
    'e',59,175,65,182, 'f',68,173,74,182, 'g',75,174,82,184, 'h',83,173,90,182, 'i',93,173,98,182, 'j',99,173,105,184,
    'k',107,173,114,182, 'l',116,173,121,182, 'm',123,175,133,182, 'n',136,175,143,182, 'o',146,175,153,182, 'p',155,175,162,184,
    'q',165,175,171,184, 'r',174,175,180,182, 's',181,175,187,182, 't',191,173,195,182, 'u',198,175,204,182, 'v',207,175,215,182,
    'w',217,175,226,182, 'x',227,175,235,182, 'y',236,175,244,184, 'z',246,175,252,182
}
local LETTER_SLACK = 3
local SHEET = 256
local letterAt, letterCache, letterCacheCount = {}, {}, 0
for font, list in pairs({ menu = LETTERS, title = TITLE_LETTERS }) do
    for i = 1, #list, 5 do
        local row = math.floor(list[i + 2] / 13) -- the boxes bucketed by rows of 13
        letterAt[row] = letterAt[row] or {}
        table.insert(letterAt[row], { list[i], list[i + 1], list[i + 2], list[i + 3], list[i + 4], font })
    end
end

-- The game's text font, drawn a cell a letter from a sheet of 32x32 cells, 64 to a row (2048x4096), the cell of a
-- character its code less 32: the top bar's help line and the menu's name box ("Items"). A space is a cell too.
local GRID_COLUMNS, GRID_ROWS = 64, 128
local function GridLetter(uv)
    local du, dv = (uv[3] - uv[1]) * GRID_COLUMNS, (uv[4] - uv[2]) * GRID_ROWS
    if math.abs(du - 1) > 0.02 or math.abs(dv - 1) > 0.02 then return nil end
    local column, row = uv[1] * GRID_COLUMNS, uv[2] * GRID_ROWS
    local c, r = math.floor(column + 0.5), math.floor(row + 0.5)
    if math.abs(column - c) > 0.05 or math.abs(row - r) > 0.05 then return nil end
    local code = 32 + r * GRID_COLUMNS + c
    if code < 32 or code > 126 then return nil end
    return string.char(code)
end

-- The letter a quad's uv cuts from the menu font, the title font or the text font, and which ('menu', 'title' or
-- 'text'); or nil
function M.Letter(uv)
    local grid = GridLetter(uv)
    if grid then return grid, 'text' end
    local x0, y0 = math.floor(uv[1] * SHEET + 0.5), math.floor(uv[2] * SHEET + 0.5)
    local x1, y1 = math.floor(uv[3] * SHEET + 0.5), math.floor(uv[4] * SHEET + 0.5)
    if x0 < 0 or y0 < 0 or x1 > SHEET or y1 > SHEET or x1 - x0 > 16 or y1 - y0 > 16 then return nil end
    local key = ((x0 * 512 + y0) * 512 + x1) * 512 + y1
    local known = letterCache[key]
    if known ~= nil then if known then return known[1], known[2] end return nil end
    local found = false
    local row = math.floor(y0 / 13)
    for r = row - 1, row + 1 do
        for _, box in ipairs(letterAt[r] or {}) do
            if math.abs(box[2] - x0) <= LETTER_SLACK and math.abs(box[3] - y0) <= LETTER_SLACK
                and math.abs(box[4] - x1) <= LETTER_SLACK and math.abs(box[5] - y1) <= LETTER_SLACK then found = { box[1], box[6] } end
        end
    end
    if letterCacheCount >= 4096 then letterCache, letterCacheCount = {}, 0 end
    letterCache[key], letterCacheCount = found, letterCacheCount + 1
    if found then return found[1], found[2] end
    return nil
end

-- A window's letters spelled out: those among its quads (its elements and its contents) read as lines of words, each
-- { text, rect, color, lit, tall, font, element }, in its quads' places (tall the line's tallest letter; font
-- 'menu', 'title' for a window's title, or 'text'; element where any of its letters is an element, not contents), and a set of the quads read (letters and their shadows, which
-- the game draws a little down and right, fainter), for the caller to leave undrawn. lit where the game tinted
-- it (the cursor's). Quads that are no letter (buttons, a title in another font) are left to the caller.
function M.Words(quads)
    local letters, used = {}, {}
    for i, quad in ipairs(quads) do
        if (quad.phase == M.Element or quad.phase == M.Content) and quad.rect then
            local c, font = M.Letter(quad.uv)
            if c then letters[#letters + 1] = { c = c, font = font, quad = quad, i = i, element = quad.phase == M.Element } end
        end
    end
    if #letters == 0 then return {}, used end
    -- shadows: a fainter copy of a letter close by it, by its left and its bottom (the game trims a shadow's top
    -- differently)
    local kept = {}
    for _, a in ipairs(letters) do
        used[a.i] = true
        local ra, shadow = a.quad.rect, false
        local near = (ra[4] - ra[2]) * 0.4
        for _, b in ipairs(letters) do
            local rb = b.quad.rect
            if b ~= a and b.c == a.c and b.quad.color[4] > a.quad.color[4]
                and math.abs(rb[1] - ra[1]) <= near and math.abs(rb[4] - ra[4]) <= near then shadow = true; break end
        end
        if not shadow then kept[#kept + 1] = a end
    end
    -- lines: letters whose heights overlap by half the shorter, top to bottom; in each, left to right, a gap of a
    -- tenth of the line's height a space (the game's boxes for letters meet, its space is narrow), of two heights
    -- a new run
    table.sort(kept, function(a, b) return a.quad.rect[2] + a.quad.rect[4] < b.quad.rect[2] + b.quad.rect[4] end)
    local lines = {}
    for _, a in ipairs(kept) do
        local r, home = a.quad.rect, nil
        for _, line in ipairs(lines) do
            local overlap = math.min(line.bottom, r[4]) - math.max(line.top, r[2])
            if overlap >= math.min(line.bottom - line.top, r[4] - r[2]) / 2 then home = line; break end
        end
        if not home then home = { top = r[2], bottom = r[4], letters = {} }; lines[#lines + 1] = home end
        home.top, home.bottom = math.min(home.top, r[2]), math.max(home.bottom, r[4])
        table.insert(home.letters, a)
    end
    local words = {}
    for _, line in ipairs(lines) do
        table.sort(line.letters, function(a, b) return a.quad.rect[1] < b.quad.rect[1] end)
        local tall = 0
        for _, a in ipairs(line.letters) do tall = math.max(tall, a.quad.rect[4] - a.quad.rect[2]) end
        local word
        for _, a in ipairs(line.letters) do
            local r = a.quad.rect
            local gap = word and r[1] - word.rect[3] or math.huge
            if gap > tall * 2 or a.font ~= word.font then
                word = { text = '', rect = { r[1], r[2], r[3], r[4] }, color = a.quad.color, lit = false, tall = tall, font = a.font }
                words[#words + 1] = word
            elseif gap > tall / 10 and a.c ~= ' ' and word.text:sub(-1) ~= ' ' then word.text = word.text .. ' ' end
            if a.c ~= ' ' or word.text:sub(-1) ~= ' ' then word.text = word.text .. a.c end
            if a.element then word.element = true end
            local w = word.rect
            w[1], w[2], w[3], w[4] = math.min(w[1], r[1]), math.min(w[2], r[2]), math.max(w[3], r[3]), math.max(w[4], r[4])
            local col = a.quad.color
            if col[1] ~= col[3] or col[2] ~= col[3] then word.lit = true end
            if col[4] > word.color[4] then word.color = col end
        end
    end
    -- the spaces drawn as cells at either end let go, and a word of nothing but them
    local spelled = {}
    for _, word in ipairs(words) do
        word.text = word.text:match('^%s*(.-)%s*$')
        if word.text ~= '' then spelled[#spelled + 1] = word end
    end
    return spelled, used
end

-- A name as the game keeps it: "menu    " and the name, padded with spaces to 16
local function Padded(name)
    if type(name) ~= 'string' or name == '' or #name > 8 or name:find('[^%w_]') then return nil end
    return 'menu    ' .. name .. (' '):rep(8 - #name)
end

function M.new()
    local block, base, looked, owned = nil, nil, -1, false
    local reason = 'Load uihook 1.59 or newer.'
    local cached, cachedSerial, cachedWidth, cachedHeight = nil, -1, 0, 0
    local function Find()
        if not AshitaCore:GetPluginManager():IsLoaded('uihook') then
            block, base, looked, owned = nil, nil, -1, false
            reason = 'Load uihook 1.59 or newer.'
            return nil
        end
        local current = ashita.memory.get_base('uihook.dll')
        if current ~= base then block, base, looked, owned, cachedSerial = nil, current, -1, false, -1 end
        if not current or current == 0 then reason = 'uihook is not ready.'; return nil end
        if not block then
            if os.clock() - looked < 1 then return nil end
            looked = os.clock()
            -- the block among the places the magic is found (its words in the DLL's text too), by its version and size
            for which = 0, 3 do
                local at = ashita.memory.find('uihook.dll', 0, MAGIC, 0, which)
                if not at or at == 0 then break end
                local found = ffi.cast('uihook_mirror_t*', at)
                if found.Version == VERSION and found.Size == ffi.sizeof('uihook_mirror_t') then block = found; break end
            end
            if not block then reason = 'Update uihook to 1.59 or newer: its mirror of the menus over the chat log (ABI 6) is not there.'; return nil end
        end
        if block.Supported == 0 then reason = 'uihook did not recognise the game\'s window drawing: the game draws them.'; return nil end
        return block
    end
    local hook = {}
    -- The group mirrored this frame, but the windows named (at most 16), which the game draws
    function hook.Request(kept)
        local b = Find()
        if not b then return false end
        local count = 0
        for i = 0, M.Kept - 1 do ffi.fill(b.Kept[i], 16) end
        for _, name in ipairs(type(kept) == 'table' and kept or {}) do
            local padded = Padded(name)
            if padded and count < M.Kept then ffi.copy(b.Kept[count], padded, 16); count = count + 1 end
        end
        b.RequestFrame = b.Frame -- the commit, after the names
        owned = true
        reason = count > 0 and ('Drawn in winxi, but %d the game draws for now.'):format(count) or 'Drawn in winxi.'
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
    -- What the group drew in the last frame presented, or nil where nothing is fresh
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
            local out = { name = name, hidden = bit.band(flags, HIDDEN) ~= 0, kept = bit.band(flags, KEPT) ~= 0,
                focused = bit.band(flags, FOCUSED) ~= 0, hasCursor = bit.band(flags, HAS_CURSOR) ~= 0, drewContent = bit.band(flags, DREW_CONTENT) ~= 0,
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
