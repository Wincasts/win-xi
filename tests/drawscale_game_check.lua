-- drawscale against a stand-in client: a small module holding the scale function, the fog's two
-- calls, the object range's call, the projection's build function and another load of C, the game
-- pointer and the vis read. The load reads the module once, finding the callers and the loads of C
-- together; a frame touches only the world float while nothing changes, rewrites the ratios when
-- something else moves world, and leaves the game object alone with square off.
local scan = require('scan')
local view = require('view')
local printCheck = H.print
H.print = function(label, ...)
    printCheck(label, ...)
    for i = 1, select('#', ...) do assert(select(i, ...) ~= false, label) end
end

local BASE, SIZE = 0x10000000, 0x4000
local FN, WORLD, ENTITY = BASE + 0x200, BASE + 0x3000, BASE + 0x3004
local BUILD, C, SITE2 = BASE + 0x1000, BASE + 0x3100, BASE + 0x2000
local GAME_FN, GLOBAL, OBJECT, VIS = BASE + 0x1100, BASE + 0x3200, BASE + 0x3300, BASE + 0x1200

local bytes, floats = {}, {}
local function put(addr, list) for i, b in ipairs(list) do bytes[addr + i - 1] = b end end
local function putHex(addr, hex, fill)
    local list = {}
    for pair in hex:gmatch('..') do list[#list + 1] = pair == '??' and 0 or tonumber(pair, 16) end
    put(addr, list)
    for at, v in pairs(fill or {}) do put(addr + at, scan.le32(v)) end
end
local function call(at, to) local rel = scan.rel32(at, to) put(at, { 0xE8, rel[1], rel[2], rel[3], rel[4] }) end

-- the scale function, with world at +7 and entity at +0x0F
putHex(FN, '8BC1487408D80D????????D9E8D80D????????C20400', { [7] = WORLD, [0x0F] = ENTITY })
-- the fog's two calls: push 0, call, fmul dword [ecx]
for _, at in ipairs({ FN - 0x50, FN - 0x30 }) do put(at, { 0x6A, 0x00 }); call(at + 2, FN); put(at + 7, { 0xD8, 0x09 }) end
-- the object range's: call, fstp dword [ebp+0x39428]
call(BASE + 0x800, FN); put(BASE + 0x805, { 0xD9, 0x9D, 0x28, 0x94, 0x03, 0x00 })
-- the build function, loading C (192) once, and another load of C before f from an object
putHex(BUILD, view.BUILD_PATTERN:gsub('%?%?', '00'), { [2] = GLOBAL, [0x43] = C })
put(C, view.doubleBytes(192))
putHex(SITE2, 'DD05????????D986F4020000D9F3', { [2] = C })
putHex(GAME_FN, 'A1????????0594000000C3', { [1] = GLOBAL })
put(GLOBAL, scan.le32(OBJECT))
put(OBJECT + view.K_OFFSET, scan.le32(view.K_STOCK))
putHex(VIS, view.VIS_PATTERN)
floats[WORLD], floats[ENTITY] = 1.0, 1.0

local count = { chunks = 0, global = 0, ratioWrites = 0 }
local stubs, nextAlloc = {}, 0x20000000
local function byte(a) return bytes[a] or 0 end
local function u32(a) return byte(a) + byte(a + 1) * 256 + byte(a + 2) * 65536 + byte(a + 3) * 16777216 end
ashita.memory = {
    find = function(_, _, pattern)
        local want = {}
        for pair in pattern:gmatch('..') do want[#want + 1] = pair ~= '??' and tonumber(pair, 16) or false end
        for at = BASE, BASE + SIZE - #want do
            local ok = true
            for i, b in ipairs(want) do if b and byte(at + i - 1) ~= b then ok = false; break end end
            if ok then return at end
        end
        return 0
    end,
    get_base = function() return BASE end,
    get_size = function() return SIZE end,
    read_array = function(addr, n)
        if n >= 4096 then count.chunks = count.chunks + 1 end
        local out = {}
        for i = 1, n do out[i] = byte(addr + i - 1) end
        return out
    end,
    write_array = function(addr, list) put(addr, list) end,
    read_uint8 = byte,
    read_uint16 = function(a) return byte(a) + byte(a + 1) * 256 end,
    read_uint32 = function(a) if a == GLOBAL then count.global = count.global + 1 end return u32(a) end,
    read_int32 = function(a) local v = u32(a) return v >= 2147483648 and v - 4294967296 or v end,
    write_uint32 = function(a, v) put(a, scan.le32(v)) end,
    read_float = function(a) return floats[a] or 0 end,
    write_float = function(a, v)
        if a >= 0x20000000 and (a - 0x20000000) % scan.STUB_SIZE == scan.RATIO_OFFSET then count.ratioWrites = count.ratioWrites + 1 end
        floats[a] = v
    end,
    alloc = function(n) local at = nextAlloc nextAlloc = nextAlloc + n + (16 - n % 16) return at end,
    unprotect = function() return true, 0 end,
    protect = function() end,
}
-- the report goes nowhere
local realOpen = io.open
io.open = function(p, mode)
    if type(p) == 'string' and p:find('drawscale\\', 1, true) then return { write = function() end, close = function() end } end
    return realOpen(p, mode)
end

H.load()
local said = table.concat(H.printed, '\n')
H.print('the module read once', count.chunks == SIZE / 4096, '| callers and the loads of C together', said:find('(2 places)', 1, true) ~= nil)
H.print('the fog and the object range found', said:find('fog calls not found', 1, true) == nil, said:find('range call not found', 1, true) == nil)

-- world x2 by the setting: the fog's stubs at fog / world
H.command('/drawscale world 2')
local fogRatios = 0
for a, v in pairs(floats) do if a >= 0x20000000 and v == 0.5 then fogRatios = fogRatios + 1 end end
H.print('world x2: the fog\'s ratios a half', fogRatios == 2, '| world written', floats[WORLD] == 2)

count.ratioWrites, count.global = 0, 0
H.frames(10)
H.print('ten frames, nothing changed: no ratio written', count.ratioWrites == 0, '| the game object not read with square off', count.global == 0)

floats[WORLD] = 4 -- drawdistance, or anything else
H.frames(1)
local quarter = 0
for a, v in pairs(floats) do if a >= 0x20000000 and v == 0.25 then quarter = quarter + 1 end end
H.print('world moved by another: the next frame puts the fog back', quarter == 2)
count.ratioWrites = 0
H.frames(5)
H.print('and then leaves them', count.ratioWrites == 0)

H.command('/drawscale square on')
H.print('square on: k at 0.75', u32(OBJECT + view.K_OFFSET) == view.K_SQUARE)
put(OBJECT + view.K_OFFSET, scan.le32(view.K_STOCK)) -- a new game object, k stock again
H.frames(1)
H.print('square on: kept by the frame', u32(OBJECT + view.K_OFFSET) == view.K_SQUARE)
H.command('/drawscale square off')
H.print('square off: k back', u32(OBJECT + view.K_OFFSET) == view.K_STOCK)
H.frames(1)
count.global = 0
H.frames(5)
H.print('square off again: the game object left alone', count.global == 0)

H.command('/drawscale fov 60')
local target = u32(SITE2 + 2)
H.print('fov 60: both loads at the addon\'s double', target ~= C, u32(BUILD + 0x43) == target,
    '| holding C for 60', math.abs(view.double(ashita.memory.read_array(target, 8)) - view.cFor(60)) < 1e-9)
H.unload()
H.print('unload: C back at both', u32(SITE2 + 2) == C, u32(BUILD + 0x43) == C, '| world stock', floats[WORLD] == 1)
