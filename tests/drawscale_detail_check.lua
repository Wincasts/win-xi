-- drawscale detail: finds the four detail-level comparisons in a run of bytes, writes their stubs and
-- calls, sets k = 1 / lod^2 and puts the original bytes back, all through a fake memory
package.path = 'addons/drawscale/?.lua;' .. package.path
local detail = require('detail')

local function check(label, ...)
    local out = { label }
    for i = 1, select('#', ...) do out[#out + 1] = tostring((select(i, ...))) end
    print(table.concat(out, '\t'))
    for i = 1, select('#', ...) do assert(select(i, ...) ~= false, label) end
end

local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

local function fromHex(hex)
    local t = {}
    for i = 1, #hex, 2 do t[#t + 1] = tonumber(hex:sub(i, i + 1), 16) end
    return t
end

-- A fake memory: bytes at addresses, the code region searched by find, alloc handing out a region.
local function fakeMem(codeBase, code, allocBase)
    local m = { bytes = {}, floats = {}, writes = 0 }
    for i, b in ipairs(code) do m.bytes[codeBase + i - 1] = b end
    function m.find(pattern)
        local p = fromHex(pattern)
        for i = 1, #code - #p + 1 do
            local ok = true
            for j = 1, #p do
                if m.bytes[codeBase + i + j - 2] ~= p[j] then ok = false break end
            end
            if ok then return codeBase + i - 1 end
        end
        return 0
    end
    function m.read(addr, n)
        local t = {}
        for i = 1, n do t[i] = m.bytes[addr + i - 1] end
        return t
    end
    function m.write(addr, bytes)
        for i, b in ipairs(bytes) do m.bytes[addr + i - 1] = b end
        m.writes = m.writes + 1
        return true
    end
    function m.write_float(addr, v) m.floats[addr] = v end
    function m.alloc(n)
        if not allocBase then return 0 end
        for i = 0, n - 1 do m.bytes[allocBase + i] = 0xCC end
        return allocBase
    end
    return m
end

-- a run of code at codeBase with the four sites among other bytes
local codeBase = 0x10100000
local code, at = {}, {}
local function emit(bytes) for _, b in ipairs(bytes) do code[#code + 1] = b end end
local function filler(n) for i = 1, n do emit({ 0x90 + (i % 3) }) end end
filler(7)
for i, pattern in ipairs(detail.PATTERNS) do
    at[i] = codeBase + #code
    emit(fromHex(pattern))
    filler(11 + i)
end
local originalCode = {}
for i, b in ipairs(code) do originalCode[i] = b end

check('four patterns, 24-byte slots, allocation', #detail.PATTERNS == 4, detail.STUB_SIZE == 24,
    detail.ALLOC_SIZE >= 4 + 4 * 24, detail.ALLOC_SIZE)

-- all four found
local allocBase = 0x20000000
local mem = fakeMem(codeBase, code, allocBase)
local state = detail.find(mem)
local addrsOk = #state.sites == 4
for i = 1, 4 do addrsOk = addrsOk and state.sites[i].address == at[i] end
check('all four sites found', addrsOk, state.missing == 0)
check('site bytes read', same(state.sites[3].bytes, fromHex(detail.PATTERNS[3])))

-- the stub's bytes for site 3 (fld [esp+0x58]; fcomp [edi+0xCC])
local kAddr = 0x20000000
local stub = detail.stubBytes(0x20000008, kAddr, state.sites[3])
check('stub is 17 bytes', #stub == 17, #stub)
check('stub fld has esp displacement +4', same({ stub[1], stub[2], stub[3], stub[4] }, { 0xD9, 0x44, 0x24, 0x5C }))
check('stub fmul of k', same({ stub[5], stub[6], stub[7], stub[8], stub[9], stub[10] }, { 0xD8, 0x0D, 0x00, 0x00, 0x00, 0x20 }))
check('stub fcomp copied from site', same({ stub[11], stub[12], stub[13], stub[14], stub[15], stub[16] }, { 0xD8, 0x9F, 0xCC, 0x00, 0x00, 0x00 }))
check('stub ends with ret', stub[17] == 0xC3)
local stub1 = detail.stubBytes(0, kAddr, state.sites[1])
check('stub for site 1: fld [esp+0x18], fcomp [ecx+0xCC]', stub1[4] == 0x18, stub1[12] == 0x99, stub1[13] == 0xCC)

-- install
local base = mem.alloc(detail.ALLOC_SIZE)
local n = detail.install(mem, state, base)
check('install patches four', n == 4, n)
check('k starts at 1', mem.floats[detail.kAddress(base)] == 1.0)
local callsOk, stubsOk = true, true
for i, site in ipairs(state.sites) do
    local s = detail.stubAddress(base, i)
    local r = detail.rel32(site.address, s)
    local want = { 0xE8, r[1], r[2], r[3], r[4], 0x90, 0x90, 0x90, 0x90, 0x90 }
    callsOk = callsOk and same(mem.read(site.address, 10), want)
    stubsOk = stubsOk and same(mem.read(s, 17), detail.stubBytes(s, detail.kAddress(base), site))
end
check('each site is a call to its stub and five nops', callsOk)
check('each stub written in its slot', stubsOk)
-- rel32 by hand for site 1: stub above the site
local s1 = detail.stubAddress(base, 1)
local rel = s1 - (at[1] + 5)
check('rel32 by hand', same(detail.rel32(at[1], s1), { rel % 256, math.floor(rel / 256) % 256, math.floor(rel / 65536) % 256, math.floor(rel / 16777216) % 256 }))
check('slots inside the allocation', detail.stubAddress(base, 4) + detail.STUB_SIZE <= base + detail.ALLOC_SIZE,
    detail.kAddress(base) + 4 <= detail.stubAddress(base, 1))
check('install again changes nothing', detail.install(mem, state, base) == 4)

-- set
check('set lod 2 gives 0.25', detail.set(mem, state, 2) == 2, mem.floats[detail.kAddress(base)] == 0.25)
check('set lod 0.5 clamped to 1', detail.set(mem, state, 0.5) == 1, mem.floats[detail.kAddress(base)] == 1.0)
detail.set(mem, state, 3)
check('set lod 3 gives 1/9', math.abs(mem.floats[detail.kAddress(base)] - 1 / 9) < 1e-12)

-- restore
check('restore puts four back', detail.restore(mem, state) == 4)
check('code as it was', same(mem.read(codeBase, #originalCode), originalCode))
local writes = mem.writes
check('restore twice is safe', detail.restore(mem, state) == 0, mem.writes == writes,
    same(mem.read(codeBase, #originalCode), originalCode))

-- one site missing: the other three still patched, in their own slots
local partial = {}
for i, b in ipairs(originalCode) do partial[i] = b end
partial[at[2] - codeBase + 1 + 9] = 0x01  -- break the fcomp offset of site 2
local mem2 = fakeMem(codeBase, partial, allocBase)
local state2 = detail.find(mem2)
check('one missing reported', state2.missing == 1, #state2.sites == 3)
local base2 = mem2.alloc(detail.ALLOC_SIZE)
check('other three patched', detail.install(mem2, state2, base2) == 3)
check('site 2 left alone', mem2.read(at[2], 1)[1] == 0xD9,
    mem2.read(at[2], 10)[10] == 0x01)
check('site 4 uses slot 4', state2.sites[3].stub == detail.stubAddress(base2, 4),
    mem2.read(at[4], 1)[1] == 0xE8)

-- a rel32 that wraps: the stub below the site
local low = 0x00010000
local wrapped = detail.rel32(at[1], low)
local back = wrapped[1] + wrapped[2] * 256 + wrapped[3] * 65536 + wrapped[4] * 16777216
if back >= 2147483648 then back = back - 4294967296 end
check('rel32 wraps below the site', wrapped[4] == 0xEF, at[1] + 5 + back == low)
local mem3 = fakeMem(codeBase, originalCode, low)
local state3 = detail.find(mem3)
detail.install(mem3, state3, mem3.alloc(detail.ALLOC_SIZE))
local c = mem3.read(at[1], 5)
local r3 = c[2] + c[3] * 256 + c[4] * 65536 + c[5] * 16777216 - 4294967296
check('call to a stub below reaches it', c[1] == 0xE8, at[1] + 5 + r3 == detail.stubAddress(low, 1))

-- nothing allocated: nothing patched
local mem4 = fakeMem(codeBase, originalCode, nil)
local state4 = detail.find(mem4)
check('no allocation patches nothing', detail.install(mem4, state4, mem4.alloc(detail.ALLOC_SIZE)) == 0,
    same(mem4.read(codeBase, #originalCode), originalCode), detail.set(mem4, state4, 2) == nil)

print('drawscale detail: all checks passed')
