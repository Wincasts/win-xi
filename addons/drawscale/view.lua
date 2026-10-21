-- Three small changes to how the client sees the world: the zone's visibility lists (vis), the
-- projection's aspect constant (square) and its field of view (fov). Pure: every read and write goes
-- through the mem interface it is handed (find, read, read_u32, write, write_u32, read_float,
-- write_float, call), so the check can drive it over a table of bytes without the game.
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
-- Field of view. The projection is built by one function (as seen in the game on 2026-10-21) from the
-- game object's fields: aspect = 1 / (a * k), the vertical field of view 2 * atan(C / f), C a double
-- constant (192) and f, the focal length, at +0x2F4, then D3DXMatrixPerspectiveFovLH into +0x154 with
-- the near and far planes at +0x2DC and +0x2E0. The game sets f through a setter (242 in play, more
-- for a closer view) and builds the projection again; just before the function is an entry with no
-- arguments, mov ecx, [gGame]; jmp, that builds it from the fields as they are. So the field of view
-- is set by writing f, scaled from the game's own, and calling that entry; the game's other readers
-- of f, its own world-to-screen among them, see the same f the picture is drawn with. A new value
-- from the game is taken as its own and scaled in turn, so its closer views stay closer.
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

-- mov ecx, [gGame]; jmp +5; five nops; then the function: push esi; mov esi, ecx; push edi;
-- fld [esi+0x2F0]; fmul [esi+0x2E8]; mov eax, [esi+0x2E0]; mov ecx, [esi+0x2DC]; push eax; push ecx;
-- fdivr [one]; sub esp, 8; lea edi, [esi+0x154]; fstp [esp+4]; fld qword [C]; fld [esi+0x2F4]; fpatan
M.BUILD_PATTERN = '8B0D????????E9050000009090909090568BF157D986F0020000D88EE80200008B86E00200008B8EDC0200005051D83D????????83EC088DBE54010000D95C2404DD05????????D986F4020000D9F3'
-- Where the address of C sits, from the entry.
M.C_AT = 0x43

-- Where the focal length sits in the game object, and the game's value for it in play.
M.FOCAL_OFFSET = 0x2F4
M.FOCAL_NORMAL = 242

-- The field of view a setting asks for: from 20 to 100 degrees, vertically; 0 is the game's own.
M.FOV_MIN = 20
M.FOV_MAX = 100

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

-- The vertical field of view, in degrees, a focal length gives.
function M.fovOf(c, focal)
    if c == nil or focal == nil or focal <= 0 then return nil end
    return math.deg(2 * math.atan(c / focal))
end

-- How much the game's focal length is multiplied by for a field of view of degrees in play: 1 for 0.
function M.focalScale(c, degrees)
    if degrees == nil or degrees <= 0 or c == nil then return 1 end
    return c / (M.FOCAL_NORMAL * math.tan(math.rad(degrees) / 2))
end

local function close(a, b) return a ~= nil and b ~= nil and math.abs(a - b) <= math.abs(b) * 1e-5 end

-- Finds the sites. The vis site's first 6 bytes are kept as they were found, to put back; the game
-- pointer is the address of the global, not the game object, since the object may not exist yet;
-- the build entry is kept with C, both 0 when not found or C is not a likely one.
function M.find(mem)
    local state = { visSite = 0, visOriginal = nil, gamePointer = 0, buildEntry = 0, c = nil, focalStock = nil, focalOurs = nil }
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
        local c = M.double(mem.read(mem.read_u32(build + M.C_AT) or 0, 8))
        if c ~= nil and c > 1 and c < 10000 then
            state.buildEntry = build
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

-- Sets the focal length for a field of view of degrees in play (0 for the game's own), from the
-- game's value: a value that is not the one last written here is the game's, kept as its own. Writes
-- and builds the projection again only when the value is not already the wanted one. True when
-- written; false when the entry or the pointer was not found, the object is not there yet, or
-- nothing was to do. Cheap enough to call every frame.
function M.setFov(mem, state, degrees)
    if state == nil or state.gamePointer == 0 or state.buildEntry == 0 then return false end
    local game = mem.read_u32(state.gamePointer) or 0
    if game == 0 then return false end
    local at = game + M.FOCAL_OFFSET
    local focal = mem.read_float(at)
    if type(focal) ~= 'number' or not (focal > 0 and focal < 100000) then return false end
    if state.focalOurs == nil or not close(focal, state.focalOurs) then state.focalStock = focal end
    local want = state.focalStock * M.focalScale(state.c, degrees)
    if close(focal, want) then
        state.focalOurs = focal
        return false
    end
    mem.write_float(at, want)
    state.focalOurs = want
    mem.call(state.buildEntry)
    return true
end

-- The field of view in play now, from the game's object: vertical, in degrees; nil when not known.
function M.currentFov(mem, state)
    if state == nil or state.gamePointer == 0 or state.c == nil then return nil end
    local game = mem.read_u32(state.gamePointer) or 0
    if game == 0 then return nil end
    return M.fovOf(state.c, mem.read_float(game + M.FOCAL_OFFSET))
end

-- All back to stock, each by its own rules, so a second call finds nothing to do.
function M.restore(mem, state)
    M.setVis(mem, state, false)
    M.setSquare(mem, state, false)
    M.setFov(mem, state, 0)
end

return M
