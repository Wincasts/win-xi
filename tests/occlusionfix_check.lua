-- occlusionfix patch: finds the three calls to the occlusion test, refuses when one is missing or they
-- reach different functions, replaces each with add esp, 0x24; or al, 1 and puts the calls back exactly,
-- twice safely. Run from the repo root:
-- luajit tests/occlusionfix_check.lua
package.path = 'addons/occlusionfix/?.lua;' .. package.path
local patch = require('patch')

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
    function m.load(addr, bytes)
        for i = 1, #bytes do
            local a = addr + i - 1
            m.bytes[a] = bytes[i]
            if a < m.lo then m.lo = a end
            if a > m.hi then m.hi = a end
        end
    end
    function m.find(pattern)
        local pat = {}
        for hx in pattern:gmatch('%S%S') do pat[#pat + 1] = tonumber(hx, 16) end
        for a = m.lo, m.hi - #pat + 1 do
            local ok = true
            for i = 1, #pat do
                if m.bytes[a + i - 1] ~= pat[i] then ok = false break end
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

local function bytesOf(hex)
    local out = {}
    for hx in hex:gmatch('%S%S') do out[#out + 1] = tonumber(hx, 16) end
    return out
end

-- E8 and the relative operand that reaches to from a call at call
local function callTo(call, to)
    local rel = to - (call + 5)
    if rel < 0 then rel = rel + 0x100000000 end
    return { 0xE8, rel % 256, floor(rel / 256) % 256, floor(rel / 65536) % 256, floor(rel / 16777216) % 256 }
end

local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

local TEST = 0x5000
local STARTS = { 0x1000, 0x2000, 0x3000 }

-- The three sites, each its pattern (less the E8) and a call; skip leaves one out, stray points the
-- last at another function.
local function build(skip, stray)
    local m = newMem()
    m.load(0x0F00, { 0x55, 0x8B, 0xEC })
    for i, pattern in ipairs(patch.SITES) do
        if i ~= skip then
            local lead = bytesOf(pattern)
            lead[#lead] = nil
            m.load(STARTS[i], lead)
            m.load(STARTS[i] + #lead, callTo(STARTS[i] + #lead, (stray and i == 3) and TEST + 0x40 or TEST))
            m.load(STARTS[i] + #lead + 5, { 0x89, 0x86 }) -- what follows the call
        end
    end
    m.load(TEST, { 0xA1 })
    return m
end

local m = build()
local state, why = patch.find(m)
check('all three found', state ~= nil, why == nil, state and #state.sites == 3)
check('they reach the test', state.test == TEST)
check('site 1 is its call', state.sites[1].address == STARTS[1] + 11, state.sites[1].original[1] == 0xE8)
check('not active yet', not patch.active(m, state))

local originals = {}
for i, site in ipairs(state.sites) do originals[i] = m.read(site.address, 5) end

check('on writes three', patch.set(m, state, true) == 3)
check('active', patch.active(m, state))
for i, site in ipairs(state.sites) do
    check(('site %d is add esp, 0x24; or al, 1'):format(i), same(m.read(site.address, 5), { 0x83, 0xC4, 0x24, 0x0C, 0x01 }))
    check(('site %d leaves what follows'):format(i), same(m.read(site.address + 5, 2), { 0x89, 0x86 }))
end
local writes = m.writes
check('on again writes nothing', patch.set(m, state, true) == 0, m.writes == writes)

check('off writes three', patch.set(m, state, false) == 3)
for i, site in ipairs(state.sites) do
    check(('site %d is its call again'):format(i), same(m.read(site.address, 5), originals[i]))
end
check('not active', not patch.active(m, state))
writes = m.writes
check('off again writes nothing', patch.set(m, state, false) == 0, m.writes == writes)
check('found again after restoring', patch.find(m) ~= nil)

local missing, whyMissing = patch.find(build(2))
check('a missing site refuses', missing == nil, whyMissing:find('not found') ~= nil)

local stray, whyStray = patch.find(build(nil, true))
check('calls to two functions refuse', stray == nil, whyStray:find('not one function') ~= nil)

check('nothing found, nothing set', patch.set(m, nil, true) == 0, not patch.active(m, nil))

print('occlusionfix patch checks passed')
