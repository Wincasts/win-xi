-- Run: luajit tests/hideparty_cursor_check.lua
-- hideparty's target cursor against stand-ins for Ashita, the device and winxi.cursor: drawn only while
-- the target frame is hidden, from anc_l, its corners laid around the tip, the sub cursor tinted on the
-- grey copy, and a cursor that will not load said once.
package.path = 'forks/addons/hideparty/?.lua;addons/libs/?.lua;' .. package.path
local realffi = require('ffi')
realffi.cdef[[
    typedef struct IDirect3DTexture8 IDirect3DTexture8;
    typedef struct ID3DXSprite ID3DXSprite;
    typedef struct { long left, top, right, bottom; } RECT;
    typedef struct { float _11, _12, _13, _14, _21, _22, _23, _24, _31, _32, _33, _34, _41, _42, _43, _44; } D3DXMATRIX;
]]
package.loaded['ffi'] = setmetatable({ C = { S_OK = 0, D3DTS_VIEW = 2, D3DTS_PROJECTION = 3,
    D3DXCreateSprite = function() return 0 end } }, { __index = realffi })

local function check(label, ...)
    H_print(label, ...)
    for i = 1, select('#', ...) do assert(select(i, ...), label) end
end

-- what Ashita's 'common' and 'chat' give
package.preload['common'] = function() return true end
string.args = function(s) local a = {} for w in s:gmatch('%S+') do a[#a + 1] = w end return a end
string.any = function(s, ...) for _, v in ipairs({ ... }) do if s == v then return true end end return false end
string.append = function(s, t) return s .. tostring(t) end
package.preload['chat'] = function() return setmetatable({}, { __index = function() return function(t) return tostring(t or '') end end }) end
local printed = {}
print, H_print = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end, print

-- the device: identity transforms, so a point's screen place is plain to work out
local identity = { _11 = 1, _12 = 0, _13 = 0, _14 = 0, _21 = 0, _22 = 1, _23 = 0, _24 = 0,
                   _31 = 0, _32 = 0, _33 = 1, _34 = 0, _41 = 0, _42 = 0, _43 = 0, _44 = 1 }
local device = { GetViewport = function() return 0, { Width = 1920, Height = 1080 } end,
                 GetTransform = function() return 0, identity end }
local drawn = {}
local sprite = { DrawTransform = function(_, texture, rect, m, color)
    local function at(u, v) return u * m._11 + v * m._21 + m._41, u * m._12 + v * m._22 + m._42 end
    local w, h = tonumber(rect.right - rect.left), tonumber(rect.bottom - rect.top)
    local x1, y1 = at(0, 0)
    local x2, y2 = at(w, h)
    drawn[#drawn + 1] = { texture = tonumber(realffi.cast('uint32_t', texture)), color = color,
        left = math.min(x1, x2), right = math.max(x1, x2), top = math.min(y1, y2), bottom = math.max(y1, y2), m33 = m._33 }
end }
package.preload['d3d8'] = function() return { get_device = function() return device end,
    gc_safe_release = function() return sprite end, D3DCOLOR_ARGB = function(a, r, g, b) return { a, r, g, b } end } end

-- the cursor: anc_l as 51.DAT has it, or a failure
local asked, failing = {}, nil
package.loaded['winxi.cursor'] = { Get = function(force, group, neutral)
    asked[#asked + 1] = { group = group, neutral = neutral and true or false }
    if failing then return nil, failing end
    return neutral and 992 or 991, { 0, 1/64, 0.5, 21/64, 32, 20, rect = { 0, 1, 32, 21 }, corners = { 10, -32, 10, 0, -10, -32, -10, 0 } }
end }

-- the game: one target at index 5 standing at the middle of the screen
local flags, sub = 0xFFFFFFFF, 0
local target = { GetIsSubTargetActive = function() return sub end, GetIsActive = function() return 1 end,
    GetTargetIndex = function(_, slot) return slot == 1 and 7 or 5 end, GetSubTargetFlags = function() return flags end,
    GetActionTargetActive = function() return 0 end }
local entity = { GetType = function() return 1 end, GetRenderFlags0 = function() return 1 end,
    GetActorPointer = function() return 0 end, GetLocalPositionX = function() return 0 end,
    GetLocalPositionY = function() return 0.5 end, GetLocalPositionZ = function() return 0 end }
AshitaCore = { GetMemoryManager = function() return { GetTarget = function() return target end,
    GetEntity = function() return entity end, GetParty = function() return { GetMemberTargetIndex = function() return 1 end } end } end,
    GetPointerManager = function() return { Get = function() return 0 end } end }
local handlers, written = {}, {}
ashita = { events = { register = function(e, _, f) handlers[e] = f end },
    memory = { find = function() return 0x1000 end, read_uint32 = function(p) return p == 0x1000 + 0x23 and 0x2000 or (p == 0x2000 and 0x3000) or (p == 0x3008 and 0x4000) or 0 end,
               write_uint8 = function(p, v) written[p] = v end } }
addon = { name = 'hideparty' }

dofile('forks/addons/hideparty/hideparty.lua')
handlers.load()
local function frame() drawn, asked = {}, {} handlers.d3d_present() end
local function command(text) handlers.command({ command = text, blocked = false }) end

frame()
check('shown: the game draws its own, nothing drawn', #drawn == 0, #asked == 0, written[0x4000 + 0x69] == 1)

command('/hideparty hide')
frame()
local d = drawn[1]
check('hidden: target frame hidden and one cursor drawn', written[0x4000 + 0x69] == 0, #drawn == 1)
check('from anc_l, the game colours untinted', asked[1].group == 'anc_l' and not asked[1].neutral, d.texture == 991,
    d.color[1] == 255 and d.color[2] == 255 and d.color[3] == 255 and d.color[4] == 255)
check('20 wide, 32 tall, tip at the target', d.left == 950 and d.right == 970 and d.top == 508 and d.bottom == 540, d.m33 == 1)

flags = 16
frame()
d = drawn[1]
check('selecting: the sub cursor, grey copy tinted in-range blue', asked[1].neutral, d.texture == 992,
    d.color[2] == 121 and d.color[3] == 107 and d.color[4] == 255)

flags, sub = 0xFFFFFFFF, 1
frame()
check('sub-targeting: the target and a sub cursor ten pixels up', #drawn == 2, drawn[2].bottom == 530)
sub = 0

failing = 'DAT read: could not open ROM/119/51.DAT'
frame(); frame()
local said = 0
for _, line in ipairs(printed) do if line:find('Cannot load the target cursor', 1, true) then said = said + 1 end end
check('a cursor that will not load: nothing drawn, said once', #drawn == 0, said == 1)
failing = nil

command('/hideparty show')
frame()
check('shown again: nothing drawn', #drawn == 0, written[0x4000 + 0x69] == 1)
H_print('hideparty target cursor: drawn only while hidden, from anc_l around its tip, tinted sub cursor and failure passed')
