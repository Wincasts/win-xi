-- winxi.nativemirror against a block laid out as uihook's: requests written and committed, the published
-- frame read into display pixels, text decoded, staleness, unload and a mismatched ABI. No native code runs.
local ffi = require('ffi')
local loaded, base, now = true, 100, 10
local block
AshitaCore = { GetPluginManager = function() return { IsLoaded = function(_, name) assert(name == 'uihook'); return loaded end } end }
ashita = { memory = {
    get_base = function(name) assert(name == 'uihook.dll'); return base end,
    find = function(name, offset, pattern, _, which)
        assert(name == 'uihook.dll' and offset == 0)
        local marker = pattern:gsub('..', function(hex) return string.char(tonumber(hex, 16)) end)
        assert(marker == 'UIHOOK-MIRROR\0\0\0')
        return which == 0 and 1 or 0
    end } }
os.clock = function() return now end
local realCast = ffi.cast
local native = dofile('addons/libs/winxi/nativemirror.lua')
block = ffi.new('uihook_mirror_t')
ffi.cast = function(kind, at) if kind == 'uihook_mirror_t*' then return block end return realCast(kind, at) end
local function check(label, ok) print(label, ok); assert(ok, label) end

ffi.copy(block.Magic, 'UIHOOK-MIRROR')
block.Version, block.Size, block.Frame, block.Supported = 3, ffi.sizeof('uihook_mirror_t'), 50, 1
check('the block is the size uihook\'s is (mirror ABI 3)', ffi.sizeof('uihook_mirror_t') == 83080 and ffi.sizeof('uihook_mirror_run_t') == 44 and ffi.sizeof('uihook_mirror_window_t') == 132)
local mirror = native.new()

-- requests: names padded as the game keeps them, the hidden ones' bits, then the commit
check('asked', mirror.Request({ { name = 'inventor', hide = true }, { name = 'iteminfo' }, { name = 'far too long' }, { name = 'bank', hide = true } }))
check('names as the game keeps them', ffi.string(block.Requests[0], 16) == 'menu    inventor' and ffi.string(block.Requests[1], 16) == 'menu    iteminfo'
    and ffi.string(block.Requests[2], 16) == 'menu    bank    ')
check('a name past eight letters left out', block.Requests[3][0] == 0)
check('hidden bits for the first and third', block.Hide[0] == 5 and block.Hide[1] == 0)
check('committed at the block\'s frame', block.RequestFrame == 50)
-- forty asked, every one hidden: the bits past 31, the 32nd too (bit 31, which bit.lshift makes negative)
local many = {}
for i = 1, 40 do many[i] = { name = ('m%d'):format(i), hide = true } end
check('forty asked', mirror.Request(many) and ffi.string(block.Requests[39], 16) == 'menu    m40     ')
check('all forty hidden: 32 bits and 8', block.Hide[0] == 0xffffffff and block.Hide[1] == 0xff)
many[32].hide = false
mirror.Request(many)
check('the 32nd watched: its bit alone clear', block.Hide[0] == 0x7fffffff and block.Hide[1] == 0xff)
check('asked again', mirror.Request({ { name = 'inventor', hide = true }, { name = 'iteminfo' }, { name = 'far too long' }, { name = 'bank', hide = true } }))
check('committed at the block\'s frame', block.RequestFrame == 50)

-- nothing published yet
check('nothing published: nil', mirror.Windows(1000, 500) == nil)

-- a frame published: one window, two runs, a quad
local f = block.Published
f.Frame, f.WindowCount, f.RunCount, f.QuadCount = 50, 1, 2, 1
local w = f.Windows[0]
ffi.copy(w.Name, 'menu    inventor', 16)
w.Flags = 1 + 2 + 4 + 8
w.Rect[0], w.Rect[1], w.Rect[2], w.Rect[3] = 0.1, 0.2, 0.3, 0.6
w.CursorFrame = 50; w.Cursor[0], w.Cursor[1], w.Cursor[2], w.Cursor[3] = 0.08, 0.3, 0.1, 0.32
w.ScrollFrame = 50; w.Scroll[0], w.Scroll[1], w.Scroll[2], w.Scroll[3] = 0.28, 0.2, 0.3, 0.6
w.ScrollPage, w.ScrollCount, w.ScrollTop = 10, 30, 5
w.FirstRun, w.Runs, w.FirstQuad, w.Quads = 0, 2, 0, 1
local words = 'Automat. Oil +1' .. '\30\2Bird\30\1 Egg'
ffi.copy(f.Text, words, #words); f.TextUsed = #words
local r = f.Runs[0]
r.Rect[0], r.Rect[1], r.Rect[2], r.Rect[3] = 0.12, 0.3, 0.2, 0.32
r.Window, r.Route, r.Colour, r.Offset, r.Length, r.X, r.Y = 0, 2, 0x80509050, 0, 15, 221, 72
r = f.Runs[1]
r.Window, r.Route, r.Colour, r.Offset, r.Length = 0, 2, 0x80808080, 15, #words - 15
local q = f.Quads[0]
q.Rect[0], q.Rect[1], q.Rect[2], q.Rect[3] = 0.1, 0.3, 0.11, 0.32
q.UV[0], q.UV[1], q.UV[2], q.UV[3] = 0, 0, 0.5, 0.5
q.Texture, q.Colour, q.Phase = 0x1234, 0x80808080, 1
block.Serial = 7

local windows = mirror.Windows(1000, 500)
check('one window', windows and #windows == 1)
local got = windows[1]
check('its name without menu', got.name == 'inventor')
check('its flags', got.hidden and got.focused and got.hasCursor and got.drewContent)
check('its frame in pixels', math.abs(got.rect[1] - 100) < 1e-3 and math.abs(got.rect[2] - 100) < 1e-3 and math.abs(got.rect[3] - 300) < 1e-3 and math.abs(got.rect[4] - 300) < 1e-3)
check('its cursor and scrollbar', got.cursor and got.scroll and got.scrollPage == 10 and got.scrollCount == 30 and got.scrollTop == 5)
check('no row highlight drawn: nil', got.selection == nil)
check('two runs', #got.runs == 2)
check('the first run\'s text, place and the game\'s colour', got.runs[1].text == 'Automat. Oil +1' and got.runs[1].x == 221 and got.runs[1].y == 72
    and math.abs(got.runs[1].color[1] - 0.625) < 1e-6 and got.runs[1].color[2] == 1 and got.runs[1].color[4] == 1)
check('the second: colour codes taken out, its raw kept, no place measured', got.runs[2].text == 'Bird Egg' and got.runs[2].raw == '\30\2Bird\30\1 Egg' and got.runs[2].rect == nil)
check('the quad: its texture, corners and place', got.quads[1].texture == 0x1234 and got.quads[1].uv[3] == 0.5 and math.abs(got.quads[1].rect[3] - 110) < 1e-3)
check('the same table while nothing changes', mirror.Windows(1000, 500) == windows)
block.Serial = 8
check('a new frame: a new table', mirror.Windows(1000, 500) ~= windows)

-- a run past the text used is left out
f.Runs[1].Length = 200
block.Serial = 9
check('a run past the text left out', #mirror.Windows(1000, 500)[1].runs == 1)

-- stale: three frames on, nothing
block.Frame = 53
check('stale: nil', mirror.Windows(1000, 500) == nil)
block.Frame = 50

-- bitmap escapes and CP932 past ASCII (transcoded on Windows; here, a ? for each byte)
check('a bitmap escape taken out', native.Decode('12\133\1x') == '12x')

-- stop: the commit cleared
mirror.Stop()
check('stopped: nothing asked', block.RequestFrame == 0)
check('asking nothing commits nothing', mirror.Request({}) and block.RequestFrame == 0)

-- unloaded, or the ABI not uihook's: nothing asked of it
loaded = false
check('uihook not loaded: not asked', not mirror.Request({ { name = 'inventor' } }) and mirror.Status():find('Load uihook'))
loaded = true; base = 200; now = 20
block.Version = 1
check('another ABI: not asked', not mirror.Request({ { name = 'inventor' } }) and mirror.Status():find('Update uihook'))
block.Version = 3; now = 30
block.Supported = 0
check('not recognised in the client: not asked', not mirror.Request({ { name = 'inventor' } }) and mirror.Status():find('did not recognise'))

-- letters: the menu font's boxes as the game cuts them, read back as words
local function uv(x0, y0, x1, y1) return { x0 / 256, y0 / 256, x1 / 256, y1 / 256 } end
check('a letter by the game\'s box', native.Letter(uv(22, 52, 31, 64)) == 'S')
check('a letter within the slack', native.Letter(uv(24, 53, 32, 63)) == 'S')
check('no letter past it', native.Letter(uv(26, 52, 35, 64)) == nil)
check('a box larger than a letter is none', native.Letter({ 0.25, 0, 1, 0.25 }) == nil)
local plain, faint, tint = { 1, 1, 1, 1 }, { 1, 1, 1, 0.38 }, { 1, 0.625, 0.25, 1 }
local boxes = { S = { 22, 52, 31, 64 }, t = { 0, 92, 6, 102 }, a = { 49, 67, 57, 76 }, u = { 7, 93, 16, 102 }, s = { 106, 80, 115, 89 },
    P = { 113, 39, 122, 50 }, r = { 98, 80, 105, 89 }, y = { 50, 93, 59, 105 }, E = { 0, 39, 9, 50 }, i = { 10, 78, 15, 89 } }
local quads = {}
local function spell(word, x, y, color, shadow)
    for c in word:gmatch('.') do
        if c ~= ' ' then
            local b = boxes[c]
            if shadow then quads[#quads + 1] = { phase = native.Element, uv = uv(unpack(b)), color = faint, rect = { x + 1, y + 1, x + 10, y + 13 } } end
            quads[#quads + 1] = { phase = native.Element, uv = uv(unpack(b)), color = color, rect = { x, y + (c == 'a' and 2 or 0), x + 9, y + 12 } }
        end
        x = x + (c == ' ' and 6 or 8)
    end
end
spell('Status', 100, 50, tint, true)
spell('Party', 100, 64, plain, true)
spell('Eta', 100, 78, plain, false); spell('Pi', 200, 78, plain, false) -- far apart: two runs
spell('Pa rty', 100, 92, plain, false)
quads[#quads + 1] = { phase = native.Element, uv = { 0.25, 0, 1, 0.25 }, color = plain, rect = { 90, 48, 180, 62 } } -- a bar
quads[#quads + 1] = { phase = native.Content, uv = uv(22, 52, 31, 64), color = plain, rect = { 0, 0, 9, 12 } } -- contents are not labels
local words, used = native.Words(quads)
local texts = {}
for _, w in ipairs(words) do texts[#texts + 1] = w.text end
check('words read in lines, top to bottom: ' .. table.concat(texts, '|'), table.concat(texts, '|') == 'Status|Party|Eta|Pi|Pa rty')
check('the tinted word lit, the others not', words[1].lit and not words[2].lit)
check('a word\'s colour its letters\', not its shadow\'s', words[2].color[4] == 1)
check('a word placed where its letters are', words[1].rect[1] == 100 and words[1].rect[2] == 50 and words[3].rect[3] == 100 + 2 * 8 + 9)
local count = 0
for i in pairs(used) do count = count + 1; assert(quads[i].phase == native.Element and native.Letter(quads[i].uv)) end
check('letters and shadows read, the bar and the contents left', count == #quads - 2 and not used[#quads] and not used[#quads - 1])
check('nothing spelled, nothing read', #native.Words({ quads[#quads - 1] }) == 0)
print('0 failures')
