-- drawscale view: finds the vis site and the game pointer (with wildcards), toggles the visibility
-- lists off and back exactly, sets k for square pixels only when the game object exists and k is one
-- of the two constants, and restores twice safely. Run from the repo root:
-- luajit tests/drawscale_view_check.lua
package.path = 'addons/drawscale/?.lua;' .. package.path
local view = require('view')

local function check(label, ...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    print(label .. '\t' .. table.concat(parts, ' '))
    for i = 1, select('#', ...) do assert(select(i, ...) ~= false, label) end
end

local floor = math.floor

-- A fake memory: a sparse table of bytes, with the interface the module is given and a count of
-- writes so a no-op can be seen to be one.
local function newMem()
    local m = { bytes = {}, writes = 0, lo = math.huge, hi = 0 }
    local function put(addr, b)
        m.bytes[addr] = b
        if addr < m.lo then m.lo = addr end
        if addr > m.hi then m.hi = addr end
    end
    function m.load(addr, bytes) for i = 1, #bytes do put(addr + i - 1, bytes[i]) end end
    function m.loadU32(addr, v)
        m.load(addr, { v % 256, floor(v / 256) % 256, floor(v / 65536) % 256, floor(v / 16777216) % 256 })
    end
    function m.find(pattern)
        local pat = {}
        -- a wildcard is false, so it matches any byte
        for hx in pattern:gmatch('%S%S') do
            if hx == '??' then pat[#pat + 1] = false else pat[#pat + 1] = tonumber(hx, 16) end
        end
        for a = m.lo, m.hi - #pat + 1 do
            local ok = true
            for i = 1, #pat do
                if pat[i] and m.bytes[a + i - 1] ~= pat[i] then ok = false break end
            end
            if ok then return a end
        end
        return 0
    end
    function m.read(addr, n)
        local out = {}
        for i = 1, n do out[i] = m.bytes[addr + i - 1] or 0 end
        return out
    end
    function m.read_u32(addr)
        local b = m.read(addr, 4)
        return b[1] + b[2] * 256 + b[3] * 65536 + b[4] * 16777216
    end
    function m.write(addr, bytes) m.writes = m.writes + 1; m.load(addr, bytes); return true end
    function m.write_u32(addr, v) m.writes = m.writes + 1; m.loadU32(addr, v); return true end
    return m
end

local VIS_SITE, GAME_SITE, GLOBAL, OBJECT = 0x1000, 0x2000, 0x3000, 0x4000
local VIS_BYTES = { 0x8B, 0x85, 0x2C, 0x91, 0x03, 0x00, 0x8D, 0x8D, 0x98, 0x00, 0x00, 0x00 }
local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

local function build(withVis, withGame)
    local m = newMem()
    m.load(0x0F00, { 0x55, 0x8B, 0xEC })
    if withVis then m.load(VIS_SITE, VIS_BYTES) end
    if withGame then
        -- mov eax, [GLOBAL]; add eax, 0x94; ret: the pointer's bytes are not the pattern's
        m.load(GAME_SITE, { 0xA1, 0x00, 0x30, 0x00, 0x00, 0x05, 0x94, 0x00, 0x00, 0x00, 0xC3 })
    end
    m.loadU32(GLOBAL, 0)
    m.loadU32(OBJECT + view.K_OFFSET, view.K_STOCK)
    m.load(0x5000, { 0xCC })
    return m
end

-- both found, and each missing on its own
local mem = build(true, true)
local state = view.find(mem)
check('both found', state.visSite == VIS_SITE, state.gamePointer == GLOBAL,
    same(state.visOriginal, { 0x8B, 0x85, 0x2C, 0x91, 0x03, 0x00 }))
local noVis = view.find(build(false, true))
check('vis missing alone', noVis.visSite == 0, noVis.visOriginal == nil, noVis.gamePointer == GLOBAL)
local noGame = view.find(build(true, false))
check('game missing alone', noGame.visSite == VIS_SITE, noGame.gamePointer == 0)

-- vis on writes the xor and nops, the lea after untouched; off restores the exact original
check('vis on', view.setVis(mem, state, true) == true,
    same(mem.read(VIS_SITE, 12), { 0x31, 0xC0, 0x90, 0x90, 0x90, 0x90, 0x8D, 0x8D, 0x98, 0x00, 0x00, 0x00 }))
check('vis on again is a no-op', view.setVis(mem, state, true) == false)
check('vis off restores', view.setVis(mem, state, false) == true, same(mem.read(VIS_SITE, 12), VIS_BYTES))

-- setVis when not found returns false and writes nothing
local m2 = build(false, true)
local s2 = view.find(m2)
local before = m2.writes
check('vis not found', view.setVis(m2, s2, true) == false, view.setVis(m2, s2, false) == false,
    m2.writes == before)

-- square: false while the global is 0, then writes 0.75 once the object exists
local kAt = OBJECT + view.K_OFFSET
before = mem.writes
check('square before the object', view.setSquare(mem, state, true) == false, mem.writes == before,
    mem.read_u32(kAt) == view.K_STOCK)
mem.loadU32(GLOBAL, OBJECT)
check('square on', view.setSquare(mem, state, true) == true, mem.read_u32(kAt) == 0x3F400000)
check('square on again is a no-op', view.setSquare(mem, state, true) == false)
check('square off', view.setSquare(mem, state, false) == true, mem.read_u32(kAt) == 0x3F4A7EFA)

-- a third value is left alone, on and off
mem.loadU32(kAt, 0x3F800000)
before = mem.writes
check('third value left alone', view.setSquare(mem, state, true) == false,
    view.setSquare(mem, state, false) == false, mem.read_u32(kAt) == 0x3F800000, mem.writes == before)

-- off from stock writes nothing
mem.loadU32(kAt, view.K_STOCK)
check('off from stock is a no-op', view.setSquare(mem, state, false) == false)

-- square when the pointer was not found
check('square without the pointer', view.setSquare(mem, noGame, true) == false)

-- restore twice: everything back, the second time nothing written
view.setVis(mem, state, true)
view.setSquare(mem, state, true)
view.restore(mem, state)
check('restore', same(mem.read(VIS_SITE, 12), VIS_BYTES), mem.read_u32(kAt) == view.K_STOCK)
before = mem.writes
view.restore(mem, state)
check('restore twice', mem.writes == before, same(mem.read(VIS_SITE, 12), VIS_BYTES),
    mem.read_u32(kAt) == view.K_STOCK)

-- restore with nothing found is safe
local m3 = build(false, false)
local s3 = view.find(m3)
view.restore(m3, s3)
check('restore with nothing found', m3.writes == 0)

-- fov: C found where the build function loads it; its loads before f and fpatan found as they lie in
-- the game (2026-10-21), from an object and from the stack, and the fixed view's left alone; the loads
-- pointed at the addon's double and back
local BUILD, CONST, ALLOC = 0x6000, 0x7000, 0x9000
local function withBuild(cBytes)
    local m = build(false, true)
    local bytes = {}
    for hx in view.BUILD_PATTERN:gmatch('%S%S') do bytes[#bytes + 1] = hx == '??' and 0 or tonumber(hx, 16) end
    m.load(BUILD, bytes)
    m.loadU32(BUILD + view.C_AT, CONST)
    m.load(CONST, cBytes)
    function m.alloc() return ALLOC end
    return m
end
local C192 = { 0, 0, 0, 0, 0, 0, 0x68, 0x40 }
check('double bytes', same(view.doubleBytes(192), C192), view.double(view.doubleBytes(139.7)) == 139.7)
local fm = withBuild(C192)
local fs = view.find(fm)
check('C found', fs.cAddr == CONST, fs.c == 192)
check('a C not likely is refused', view.find(withBuild({ 0, 0, 0, 0, 0, 0, 0, 0 })).c == nil)
check('no build', view.find(build(false, true)).c == nil)

local function hexBytes(h) local t = {} for b in h:gmatch('%x%x') do t[#t + 1] = tonumber(b, 16) end return t end
-- the four of the game's, with CONST in place of 0x034E9D40, and the fixed view (fld qword [C];
-- fld qword [other]; fpatan) and an fld qword [C] going elsewhere
local code = hexBytes(table.concat({
    'DD 05 00 70 00 00 D9 86 F4 02 00 00 D9 F3 DC C0 D9 1C 24 57',   -- the build function, f from esi
    'DD 05 00 70 00 00 D9 80 F4 02 00 00 D9 F3 DC C0 D9 5C 24 1C',   -- each pass, f from eax
    'DD 05 00 70 00 00 DD 05 80 B0 4E 03 D9 F3 A1 24 1F 7F 03 C6',   -- the fixed view: left
    'DD 05 00 70 00 00 D9 80 F4 02 00 00 D9 F3 DC C0 D9 1C 24 52',
    'DD 05 00 70 00 00 D9 44 24 20 D9 F3 DC C0 D9 1C 24 50 E8 2A',   -- f from the stack
    'DD 05 00 70 00 00 D9 84 24 F4 02 00 00 D9 F3 90 90 90 90 90',   -- a SIB form: not the shape
    'DD 05 00 80 00 00 D9 80 F4 02 00 00 D9 F3 90 90 90 90 90 90',   -- another constant
}, ' '))
local CODE = 0x8000
fm.load(CODE, code)
fs.sites = view.fovSites(code, CODE, #code, CONST)
check('the four found', #fs.sites == 4, fs.sites[1] == CODE, fs.sites[2] == CODE + 20, fs.sites[3] == CODE + 60, fs.sites[4] == CODE + 80)
check('none past the count', #view.fovSites(code, CODE, 40, CONST) == 2)

local function operand(site) return fm.read_u32(site + 2) end
local function near(a, b) return math.abs(a - b) < 1e-3 end
check('the game\'s 76.86 degrees', near(view.currentFov(fs), 76.856))
check('fov 60', view.setFov(fm, fs, 60) == true, operand(CODE) == ALLOC, operand(CODE + 80) == ALLOC,
    operand(CODE + 40) == CONST, operand(CODE + 100) == CONST,
    near(view.double(fm.read(ALLOC, 8)), 242 * math.tan(math.rad(30))), near(view.currentFov(fs), 60))
before = fm.writes
check('fov 60 again is a no-op', view.setFov(fm, fs, 60) == false, fm.writes == before)
check('fov 45 writes the double only', view.setFov(fm, fs, 45) == true, fm.writes == before + 1, near(view.currentFov(fs), 45))
check('fov 0 points them back', view.setFov(fm, fs, 0) == true, operand(CODE) == CONST, operand(CODE + 20) == CONST, operand(CODE + 80) == CONST,
    near(view.currentFov(fs), 76.856))
check('fov without the sites', view.setFov(fm, view.find(withBuild(C192)), 60) == false)
local noAlloc = view.find(withBuild(C192))
noAlloc.sites = { CODE }
local nm = withBuild(C192)
function nm.alloc() return 0 end
check('fov without memory for the double', view.setFov(nm, noAlloc, 60) == false)
view.setFov(fm, fs, 50)
view.restore(fm, fs)
check('restore points them back', operand(CODE) == CONST, operand(CODE + 60) == CONST)
before = fm.writes
view.restore(fm, fs)
check('restore twice writes nothing', fm.writes == before)

print('drawscale view: all checks passed')
