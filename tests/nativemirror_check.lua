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
block.Version, block.Size, block.Frame, block.Supported = 1, ffi.sizeof('uihook_mirror_t'), 50, 1
check('the block is the size uihook\'s is (mirror ABI 1)', ffi.sizeof('uihook_mirror_t') == 41188 and ffi.sizeof('uihook_mirror_run_t') == 44 and ffi.sizeof('uihook_mirror_window_t') == 132)
local mirror = native.new()

-- requests: names padded as the game keeps them, the hidden ones' bits, then the commit
check('asked', mirror.Request({ { name = 'inventor', hide = true }, { name = 'iteminfo' }, { name = 'far too long' }, { name = 'bank', hide = true } }))
check('names as the game keeps them', ffi.string(block.Requests[0], 16) == 'menu    inventor' and ffi.string(block.Requests[1], 16) == 'menu    iteminfo'
    and ffi.string(block.Requests[2], 16) == 'menu    bank    ')
check('a name past eight letters left out', block.Requests[3][0] == 0)
check('hidden bits for the first and third', block.Hide == 5)
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
block.Version = 2
check('another ABI: not asked', not mirror.Request({ { name = 'inventor' } }) and mirror.Status():find('Update uihook'))
block.Version = 1; now = 30
block.Supported = 0
check('not recognised in the client: not asked', not mirror.Request({ { name = 'inventor' } }) and mirror.Status():find('did not recognise'))
print('0 failures')
