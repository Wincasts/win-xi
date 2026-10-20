-- Two small patches to how the client sees the world, each a toggle: the zone's visibility lists
-- (vis) and the projection's aspect constant (square). Pure: every read and write goes through the
-- mem interface it is handed (find, read, read_u32, write, write_u32), so the check can drive it over
-- a table of bytes without the game.
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
local M = {}

-- mov eax, [ebp+0x3912C]; lea ecx, [ebp+0x98]
M.VIS_PATTERN = '8B852C9103008D8D98000000'
-- mov eax, [gGame]; add eax, 0x94; ret (the dword after A1 is the global's address)
M.GAME_PATTERN = 'A1????????0594000000C3'

-- The constant k as the bits of a 32-bit float: stock 0.791, and 0.75 for square pixels.
M.K_STOCK = 0x3F4A7EFA
M.K_SQUARE = 0x3F400000

-- Where k sits in the game object.
M.K_OFFSET = 0x2E8

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

-- Finds both sites. The vis site's first 6 bytes are kept as they were found, to put back; the game
-- pointer is the address of the global, not the game object, since the object may not exist yet.
function M.find(mem)
    local state = { visSite = 0, visOriginal = nil, gamePointer = 0 }
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

-- Both back to stock, each by its own rules, so a second call finds nothing to do.
function M.restore(mem, state)
    M.setVis(mem, state, false)
    M.setSquare(mem, state, false)
end

return M
