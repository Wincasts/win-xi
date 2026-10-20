-- The zone objects' detail levels kept in step with the draw distance. Pure: touches memory only
-- through the mem interface it is handed (find, read, write, write_float, alloc), so the check can
-- drive it over a table of bytes without the game.
--
-- Each zone object (a tree, a prop, a building) carries three meshes of decreasing detail, and the
-- client picks one by comparing the object's squared distance with two squared thresholds stored on
-- the object, at +0xCC (the switch to the middle mesh) and +0xC8 (the switch to the coarsest). Nothing
-- scales those thresholds with the draw distance, so with the distance raised the objects still go
-- coarse at the stock distances. The comparisons are at four sites, each the ten bytes
--
--     fld dword [esp+d]              D9 44 24 d
--     fcomp dword [reg+threshold]    D8 99|9F C8|CC 00 00 00
--
-- and each is sent through a stub that multiplies the squared distance by k = 1 / lod^2 before the
-- comparison, which is the same as moving both thresholds out by lod: lod 2 swaps meshes at twice the
-- stock distance. The site becomes a five-byte call to its stub and five nops; the stub is
--
--     fld dword [esp+d+4]            D9 44 24 (d+4)   the call pushed a return address
--     fmul dword [k]                 D8 0D k
--     fcomp dword [reg+threshold]    the site's own six bytes, copied
--     ret                            C3
--
-- seventeen bytes in a slot of twenty-four. The allocation the caller makes (M.ALLOC_SIZE bytes) holds
-- k in its first four bytes, four bytes of padding, then the four slots one after another. The caller
-- allocates it so that it can leave it allocated at unload: a render thread may still be inside a stub.
local M = {}

local floor = math.floor

M.PATTERNS = {
    'D9442414D899CC000000', -- fld dword [esp+0x14]; fcomp dword [ecx+0xCC]
    'D9442414D899C8000000', -- fld dword [esp+0x14]; fcomp dword [ecx+0xC8]
    'D9442458D89FCC000000', -- fld dword [esp+0x58]; fcomp dword [edi+0xCC]
    'D9442458D89FC8000000', -- fld dword [esp+0x58]; fcomp dword [edi+0xC8]
}

M.SITE_SIZE = 10
M.STUB_SIZE = 24
M.K_OFFSET = 0
M.STUBS_OFFSET = 8
M.ALLOC_SIZE = M.STUBS_OFFSET + #M.PATTERNS * M.STUB_SIZE

-- The bytes of v as a 32-bit value, lowest first; a negative v wraps modulo 2^32.
local function le32(v)
    v = v % 4294967296
    return { v % 256, floor(v / 256) % 256, floor(v / 65536) % 256, floor(v / 16777216) % 256 }
end
M.le32 = le32

-- The rel32 of a five-byte call at from reaching to: the distance from the end of the call.
function M.rel32(from, to) return le32(to - (from + 5)) end

-- The address of k and of slot i (1-based) in an allocation at base.
function M.kAddress(base) return base + M.K_OFFSET end
function M.stubAddress(base, i) return base + M.STUBS_OFFSET + (i - 1) * M.STUB_SIZE end

-- The stub for a site, from the site's original ten bytes. The stub has no relative addressing (k is
-- an absolute address), so stubAddr only says where it goes; it is taken to keep the call alike for
-- anything later that needs it.
function M.stubBytes(stubAddr, kAddr, site)
    local b = site.bytes
    local k = le32(kAddr)
    return {
        0xD9, 0x44, 0x24, (b[4] + 4) % 256,   -- fld dword [esp+d+4]
        0xD8, 0x0D, k[1], k[2], k[3], k[4],   -- fmul dword [k]
        b[5], b[6], b[7], b[8], b[9], b[10],  -- fcomp dword [reg+threshold], as at the site
        0xC3,                                 -- ret
    }
end

-- The ten bytes that replace a site: the call to its stub and five nops.
function M.siteBytes(siteAddr, stubAddr)
    local r = M.rel32(siteAddr, stubAddr)
    return { 0xE8, r[1], r[2], r[3], r[4], 0x90, 0x90, 0x90, 0x90, 0x90 }
end

-- The four sites, each with its address and original bytes (nil address when the pattern is not
-- found), and the count missing. A site keeps its slot number so its stub's place does not depend on
-- which others were found.
function M.find(mem)
    local state = { sites = {}, missing = 0 }
    for i, pattern in ipairs(M.PATTERNS) do
        local addr = mem.find(pattern) or 0
        if addr ~= 0 then
            state.sites[#state.sites + 1] = { slot = i, pattern = pattern, address = addr, bytes = mem.read(addr, M.SITE_SIZE) }
        else
            state.missing = state.missing + 1
        end
    end
    return state
end

-- Writes k = 1 (stock) and every found site's stub into the allocation at base, then redirects each
-- site to its stub. The stub and k are in place before the call that reaches them is written, so a
-- render thread never reaches a half-written stub. Sites already patched are left as they are. Answers
-- how many sites are patched after the call.
function M.install(mem, state, base)
    if base == nil or base == 0 then return 0 end
    state.base = base
    state.k = M.kAddress(base)
    if not state.kWritten then
        mem.write_float(state.k, 1.0)
        state.kWritten = true
    end
    local patched = 0
    for _, site in ipairs(state.sites) do
        if not site.patched then
            site.stub = M.stubAddress(base, site.slot)
            if mem.write(site.stub, M.stubBytes(site.stub, state.k, site))
                and mem.write(site.address, M.siteBytes(site.address, site.stub)) then
                site.patched = true
            end
        end
        if site.patched then patched = patched + 1 end
    end
    state.patched = patched
    return patched
end

-- Sets the multiplier: k = 1 / lod^2, lod at least 1 (the module only moves the switches outward).
-- Answers the lod used, or nil when nothing is installed to set.
function M.set(mem, state, lod)
    lod = tonumber(lod) or 1
    if lod < 1 then lod = 1 end
    state.lod = lod
    if not state.k then return nil end
    mem.write_float(state.k, 1 / (lod * lod))
    return lod
end

-- Puts every patched site's original ten bytes back. The stubs and k stay where they are, for a thread
-- still inside one. Calling it again does nothing more. Answers how many sites were restored.
function M.restore(mem, state)
    local restored = 0
    for _, site in ipairs(state.sites or {}) do
        if site.patched and mem.write(site.address, site.bytes) then
            site.patched = false
            restored = restored + 1
        end
    end
    local left = 0
    for _, site in ipairs(state.sites or {}) do if site.patched then left = left + 1 end end
    state.patched = left
    return restored
end

return M
