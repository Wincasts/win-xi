-- The zone's visibility lists (vis). Pure: every read and write goes through the mem interface it is handed
-- (find, read, write), so the check can drive it over a table of bytes without the game. The field of view and
-- the aspect constant (fov and square) were here until drawscale 2.0 and are the lens plugin's now.
--
-- Visibility lists. A zone carries, for each area of it, a precomputed list of the objects visible from
-- there. When the camera's area has one, the renderer draws only what is on it, so terrain the zone's
-- author did not expect to be seen is never drawn however far the draw distance reaches, and it pops in
-- as the camera crosses into the next area. The renderer reads the current list with
-- mov eax, [ebp+0x3912C] (8B 85 2C 91 03 00), found by that mov and the lea ecx, [ebp+0x98] after it.
-- With vis on, those 6 bytes become xor eax, eax and four nops, so the renderer sees no list and falls
-- back to its quadtree walk, which culls by the frustum and the distance only.
local M = {}

-- mov eax, [ebp+0x3912C]; lea ecx, [ebp+0x98]
M.VIS_PATTERN = '8B852C9103008D8D98000000'

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

-- Finds the vis site; its first 6 bytes are kept as they were found, to put back.
function M.find(mem)
    local state = { visSite = 0, visOriginal = nil }
    local vis = mem.find(M.VIS_PATTERN) or 0
    if vis ~= 0 then
        local bytes = mem.read(vis, 6)
        if bytes ~= nil and #bytes == 6 then
            state.visSite = vis
            state.visOriginal = copy(bytes)
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

-- Back to stock, so a second call finds nothing to do.
function M.restore(mem, state)
    M.setVis(mem, state, false)
end

return M
