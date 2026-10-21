-- Three small changes to how the client sees the world: the zone's visibility lists (vis), the
-- projection's aspect constant (square) and its field of view (fov). Pure: every read and write goes
-- through the mem interface it is handed (find, read, read_u32, write, write_u32, alloc), so the check can drive it over a table of bytes without the game.
--
-- Visibility lists. A zone carries, for each area of it, a precomputed list of the objects visible from
-- there. When the camera's area has one, the renderer draws only what is on it, so terrain the zone's
-- author did not expect to be seen is never drawn however far the draw distance reaches, and it pops in
-- as the camera crosses into the next area. The renderer reads the current list with
-- mov eax, [ebp+0x3912C] (8B 85 2C 91 03 00), found by that mov and the lea ecx, [ebp+0x98] after it.
-- With vis on, those 6 bytes become xor eax, eax and four nops, so the renderer sees no list and falls
-- back to its quadtree walk, which culls by the frustum and the distance only.
--
-- Square pixels. Every world projection is built with aspect = 1 / (a * k), a being the value the
-- aspect addon writes from the window size and k a constant 0.791 kept in the game object at +0x2E8,
-- which leaves the 3D picture about 5.5% wider than true. With k at 0.75 the aspect is the window's
-- exactly. The game object is reached through a global pointer, read out of
-- mov eax, [gGame]; add eax, 0x94; ret, and the global is 0 until the game object exists, so the
-- value is looked for again on each call until it is there.
--
-- Field of view. Every world projection is built (as seen in the game on 2026-10-21) from the game
-- object's fields: aspect = 1 / (a * k), the vertical field of view 2 * atan(C / f), C a double
-- constant (192) and f, the focal length, at +0x2F4 (242 in play, more for a closer view), then
-- D3DXMatrixPerspectiveFovLH. Four places build one, each pass of the frame, loading C with
-- fld qword [C] just before f and fpatan. Writing f did not hold (2026-10-21), so it is C that is
-- changed: those loads are pointed at a double of the addon's own, 242 * tan(fov / 2), which puts the
-- usual view at the field of view asked for and the game's closer views closer by as much. Other
-- loads of C (one makes a fixed view of its own with a constant in place of f) are left alone.
local M = {}

local floor = math.floor

-- mov eax, [ebp+0x3912C]; lea ecx, [ebp+0x98]
M.VIS_PATTERN = '8B852C9103008D8D98000000'
-- mov eax, [gGame]; add eax, 0x94; ret (the dword after A1 is the global's address)
M.GAME_PATTERN = 'A1????????0594000000C3'

-- The constant k as the bits of a 32-bit float: stock 0.791, and 0.75 for square pixels.
M.K_STOCK = 0x3F4A7EFA
M.K_SQUARE = 0x3F400000

-- Where k sits in the game object.
M.K_OFFSET = 0x2E8

-- One of the four, where C is found: mov ecx, [gGame]; jmp +5; five nops; then the function:
-- push esi; mov esi, ecx; push edi; fld [esi+0x2F0]; fmul [esi+0x2E8]; mov eax, [esi+0x2E0];
-- mov ecx, [esi+0x2DC]; push eax; push ecx; fdivr [one]; sub esp, 8; lea edi, [esi+0x154];
-- fstp [esp+4]; fld qword [C]; fld [esi+0x2F4]; fpatan
M.BUILD_PATTERN = '8B0D????????E9050000009090909090568BF157D986F0020000D88EE80200008B86E00200008B8EDC0200005051D83D????????83EC088DBE54010000D95C2404DD05????????D986F4020000D9F3'
-- Where the address of C sits, from the entry.
M.C_AT = 0x43

-- The game's focal length in play (at +0x2F4 in the game object).
M.FOCAL_NORMAL = 242

-- The field of view a setting asks for: from 20 to 140 degrees, vertically (over 77 for lens to squeeze
-- back); 0 is the game's own.
M.FOV_MIN = 20
M.FOV_MAX = 140

-- xor eax, eax and four nops: the renderer's list read as none.
M.VIS_PATCH = { 0x31, 0xC0, 0x90, 0x90, 0x90, 0x90 }

local function copy(bytes)
    local out = {}
    for i = 1, #bytes do out[i] = bytes[i] end
    return out
end

local function same(a, b)
    if a == nil or b == nil or #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- The double whose bytes, lowest first, are bytes.
function M.double(bytes)
    if bytes == nil or #bytes < 8 then return nil end
    local hi = bytes[5] + bytes[6] * 256 + bytes[7] * 65536 + bytes[8] * 16777216
    local lo = bytes[1] + bytes[2] * 256 + bytes[3] * 65536 + bytes[4] * 16777216
    local sign = hi >= 2147483648 and -1 or 1
    local exp = floor(hi / 1048576) % 2048
    local frac = (hi % 1048576) * 4294967296 + lo
    if exp == 2047 then return frac == 0 and sign * math.huge or 0 / 0 end
    if exp == 0 then return sign * frac * 2 ^ -1074 end
    return sign * (1 + frac / 2 ^ 52) * 2 ^ (exp - 1023)
end

-- The bytes of the double x, lowest first; x a positive normal number.
function M.doubleBytes(x)
    local m, e = math.frexp(x)            -- x = m * 2^e, m from 0.5 to 1
    local frac = (m * 2 - 1) * 2 ^ 52     -- the 52 bits after the leading 1
    local hi = (e - 1 + 1023) * 1048576 + floor(frac / 4294967296)
    local lo = frac % 4294967296
    local out = {}
    for i = 0, 3 do out[i + 1] = floor(lo / 256 ^ i) % 256 end
    for i = 0, 3 do out[i + 5] = floor(hi / 256 ^ i) % 256 end
    return out
end

local function le32(v)
    return { v % 256, floor(v / 256) % 256, floor(v / 65536) % 256, floor(v / 16777216) % 256 }
end

-- The vertical field of view, in degrees, a focal length gives.
function M.fovOf(c, focal)
    if c == nil or focal == nil or focal <= 0 then return nil end
    return math.deg(2 * math.atan(c / focal))
end

-- The C that puts the usual view (f of 242) at a field of view of degrees.
function M.cFor(degrees)
    return M.FOCAL_NORMAL * math.tan(math.rad(degrees) / 2)
end

-- The loads of C at cAddr in bytes (bytes[1] at address base; count of them to scan, the rest a
-- margin) that a projection's field of view is made from: fld qword [C] followed by the load of f,
-- from an object (fld dword [reg+0x2F4]) or the stack (fld dword [esp+d8]), and fpatan. The
-- addresses of the fld qword, whose operand is 2 bytes in.
function M.fovSites(bytes, base, count, cAddr)
    local out = {}
    local c = le32(cAddr)
    for i = 1, count do
        if bytes[i] == 0xDD and bytes[i + 1] == 0x05 and bytes[i + 2] == c[1] and bytes[i + 3] == c[2]
            and bytes[i + 4] == c[3] and bytes[i + 5] == c[4] and bytes[i + 6] == 0xD9 then
            local m = bytes[i + 7]
            local fromObject = m ~= nil and m >= 0x80 and m <= 0x87 and m ~= 0x84 and bytes[i + 8] == 0xF4
                and bytes[i + 9] == 0x02 and bytes[i + 10] == 0x00 and bytes[i + 11] == 0x00
                and bytes[i + 12] == 0xD9 and bytes[i + 13] == 0xF3
            local fromStack = m == 0x44 and bytes[i + 8] == 0x24 and bytes[i + 10] == 0xD9 and bytes[i + 11] == 0xF3
            if fromObject or fromStack then out[#out + 1] = base + i - 1 end
        end
    end
    return out
end

-- Finds the sites. The vis site's first 6 bytes are kept as they were found, to put back; the game
-- pointer is the address of the global, not the game object, since the object may not exist yet;
-- C is read where the build function loads it, nil when not found or not a likely one. The loads of
-- C to change (sites) are found by the caller over the whole module, with fovSites.
function M.find(mem)
    local state = { visSite = 0, visOriginal = nil, gamePointer = 0, cAddr = 0, c = nil, sites = {}, cMem = 0, fov = 0 }
    local vis = mem.find(M.VIS_PATTERN) or 0
    if vis ~= 0 then
        local bytes = mem.read(vis, 6)
        if bytes ~= nil and #bytes == 6 then
            state.visSite = vis
            state.visOriginal = copy(bytes)
        end
    end
    local game = mem.find(M.GAME_PATTERN) or 0
    if game ~= 0 then
        state.gamePointer = mem.read_u32(game + 1) or 0
    end
    local build = mem.find(M.BUILD_PATTERN) or 0
    if build ~= 0 then
        local cAddr = mem.read_u32(build + M.C_AT) or 0
        local c = M.double(mem.read(cAddr, 8))
        if c ~= nil and c > 1 and c < 10000 then
            state.cAddr = cAddr
            state.c = c
        end
    end
    return state
end

-- Writes the xor and nops (on) or the original bytes (off) at the vis site, when it was found and the
-- bytes there are not already the wanted ones. True when something was written.
function M.setVis(mem, state, on)
    if state == nil or state.visSite == 0 or state.visOriginal == nil then return false end
    local want = on and M.VIS_PATCH or state.visOriginal
    if same(mem.read(state.visSite, 6), want) then return false end
    return mem.write(state.visSite, copy(want)) == true
end

-- Sets k to 0.75 (on) or 0.791 (off) when the game object exists and k holds one of the two, leaving
-- any other value alone since something else has set it. True when written; false when the pointer
-- was not found, the object is not there yet, k is already the wanted value, or it is neither.
-- Cheap enough to call every frame.
function M.setSquare(mem, state, on)
    if state == nil or state.gamePointer == 0 then return false end
    local game = mem.read_u32(state.gamePointer) or 0
    if game == 0 then return false end
    local at = game + M.K_OFFSET
    local k = mem.read_u32(at)
    local want = on and M.K_SQUARE or M.K_STOCK
    if k == want or (k ~= M.K_STOCK and k ~= M.K_SQUARE) then return false end
    mem.write_u32(at, want)
    return true
end

-- Points the loads of C at a double of the addon's own holding cFor(degrees), or back at C for 0 (the
-- game's own). Writes only what is not already so. True when something was written; false when C or
-- its loads were not found, the double could not be had, or nothing was to do.
function M.setFov(mem, state, degrees)
    if state == nil or state.c == nil or #state.sites == 0 then return false end
    degrees = degrees or 0
    if degrees == state.fov then return false end
    local target = state.cAddr
    if degrees > 0 then
        if state.cMem == 0 then state.cMem = mem.alloc(8) or 0 end
        if state.cMem == 0 then return false end
        mem.write(state.cMem, M.doubleBytes(M.cFor(degrees)))
        target = state.cMem
    end
    local want = le32(target)
    for _, site in ipairs(state.sites) do
        if not same(mem.read(site + 2, 4), want) then mem.write(site + 2, copy(want)) end
    end
    state.fov = degrees
    return true
end

-- The field of view of the usual view now, vertical, in degrees; nil when C was not found.
function M.currentFov(state)
    if state == nil or state.c == nil then return nil end
    if (state.fov or 0) > 0 and #state.sites > 0 then return M.fovOf(M.cFor(state.fov), M.FOCAL_NORMAL) end
    return M.fovOf(state.c, M.FOCAL_NORMAL)
end

-- All back to stock, each by its own rules, so a second call finds nothing to do.
function M.restore(mem, state)
    M.setVis(mem, state, false)
    M.setSquare(mem, state, false)
    M.setFov(mem, state, 0)
end

return M
