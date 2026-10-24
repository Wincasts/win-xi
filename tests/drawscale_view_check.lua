-- drawscale view: finds the vis site, toggles the visibility lists off and back exactly, and restores
-- twice safely. Run from the repo root:
-- luajit tests/drawscale_view_check.lua
package.path = 'addons/drawscale/?.lua;' .. package.path
local view = require('view')

local function check(label, ...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    print(label .. '\t' .. table.concat(parts, ' '))
    for i = 1, select('#', ...) do assert(select(i, ...) ~= false, label) end
end

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
    function m.write(addr, bytes) m.writes = m.writes + 1; m.load(addr, bytes); return true end
    return m
end

local VIS_SITE = 0x1000
local VIS_BYTES = { 0x8B, 0x85, 0x2C, 0x91, 0x03, 0x00, 0x8D, 0x8D, 0x98, 0x00, 0x00, 0x00 }
local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

local function build(withVis)
    local m = newMem()
    m.load(0x0F00, { 0x55, 0x8B, 0xEC })
    if withVis then m.load(VIS_SITE, VIS_BYTES) end
    m.load(0x5000, { 0xCC })
    return m
end

-- found, and missing
local mem = build(true)
local state = view.find(mem)
check('found', state.visSite == VIS_SITE, same(state.visOriginal, { 0x8B, 0x85, 0x2C, 0x91, 0x03, 0x00 }))
local noVis = view.find(build(false))
check('missing', noVis.visSite == 0, noVis.visOriginal == nil)

-- vis on writes the xor and nops, the lea after untouched; off restores the exact original
check('vis on', view.setVis(mem, state, true) == true,
    same(mem.read(VIS_SITE, 12), { 0x31, 0xC0, 0x90, 0x90, 0x90, 0x90, 0x8D, 0x8D, 0x98, 0x00, 0x00, 0x00 }))
check('vis on again is a no-op', view.setVis(mem, state, true) == false)
check('vis off restores', view.setVis(mem, state, false) == true, same(mem.read(VIS_SITE, 12), VIS_BYTES))

-- setVis when not found returns false and writes nothing
local m2 = build(false)
local s2 = view.find(m2)
local before = m2.writes
check('vis not found', view.setVis(m2, s2, true) == false, view.setVis(m2, s2, false) == false,
    m2.writes == before)

-- restore twice: everything back, the second time nothing written
view.setVis(mem, state, true)
view.restore(mem, state)
check('restore', same(mem.read(VIS_SITE, 12), VIS_BYTES))
before = mem.writes
view.restore(mem, state)
check('restore twice', mem.writes == before, same(mem.read(VIS_SITE, 12), VIS_BYTES))

-- restore with nothing found is safe
local m3 = build(false)
local s3 = view.find(m3)
view.restore(m3, s3)
check('restore with nothing found', m3.writes == 0)

print('drawscale view: all checks passed')
