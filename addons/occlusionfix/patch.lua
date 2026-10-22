-- Turns off the client's pixel test for whether a character is hidden behind the scenery. Pure: every
-- read and write goes through the mem interface it is handed (find, read, write), so the check can drive
-- it over a table of bytes without the game.
--
-- Each character's on-screen rectangle is drawn against the world's depth buffer, an 8x8 sample of the
-- result is copied back from the card and the pixels that passed are counted (0x322C280 in the client
-- dumped 2026-10-22). A count of 0 hides the character until a later test passes. The sample is coarse
-- and is taken at the window's size, so a character beside a wall, a door frame or a counter is often
-- counted as covered when most of it is in plain view, and blinks out as the camera moves; the more the
-- 3D resolution exceeds the window, the worse it is.
--
-- The test is called from three places, each ending in a call the test returns from with ret 0x24
-- (nine arguments). Each call becomes
--
--     add esp, 0x24        83 C4 24      the arguments, as the test's ret would have popped them
--     or al, 1             0C 01         a count that is never 0
--
-- five bytes for five, so nothing is hidden by the test and the depth buffer alone keeps what is
-- really behind a wall out of sight. The three calls must reach the same function, which is how a
-- pattern that has come to match something else is told apart.
local M = {}

-- The bytes before each call, ending with the call's E8
M.SITES = {
    'D91C2450518D8EF0080000E8', -- a character's update; the count is kept at +0x9F4 for the frames between tests
    'D91C2451528D8EF0080000E8', -- a character's second test
    'D91C2451528D8E8C080000E8', -- the same test for another kind of actor, its rectangle at +0x88C
}

M.PASS = { 0x83, 0xC4, 0x24, 0x0C, 0x01 }

local function same(a, b)
    if a == nil or b == nil or #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

local function copy(t)
    local out = {}
    for i = 1, #t do out[i] = t[i] end
    return out
end

-- Where a five-byte call at addr goes, from its 32-bit relative operand
local function target(addr, bytes)
    local rel = bytes[2] + bytes[3] * 0x100 + bytes[4] * 0x10000 + bytes[5] * 0x1000000
    if rel >= 0x80000000 then rel = rel - 0x100000000 end
    return addr + 5 + rel
end

-- Finds the three calls. Returns { sites = { { address, original } ... } } with all three, or nil and
-- why not: a pattern not found, or calls that do not reach one function.
function M.find(mem)
    local sites, reached = {}, nil
    for _, pattern in ipairs(M.SITES) do
        local at = mem.find(pattern) or 0
        if at == 0 then
            return nil, ('not found: %s'):format(pattern)
        end
        local call = at + #pattern / 2 - 1
        local bytes = mem.read(call, 5)
        if bytes == nil or bytes[1] ~= 0xE8 then
            return nil, ('no call at %08X'):format(call)
        end
        local to = target(call, bytes)
        if reached ~= nil and to ~= reached then
            return nil, ('the calls reach %08X and %08X, not one function'):format(reached, to)
        end
        reached = to
        sites[#sites + 1] = { address = call, original = copy(bytes) }
    end
    return { sites = sites, test = reached }
end

-- Writes the replacement (on) or the original call (off) at every site. Returns how many were
-- written; a site already as asked is left alone.
function M.set(mem, state, on)
    if state == nil then return 0 end
    local written = 0
    for _, site in ipairs(state.sites) do
        local want = on and M.PASS or site.original
        if not same(mem.read(site.address, 5), want) then
            if mem.write(site.address, copy(want)) then written = written + 1 end
        end
    end
    return written
end

-- Whether every site holds the replacement
function M.active(mem, state)
    if state == nil then return false end
    for _, site in ipairs(state.sites) do
        if not same(mem.read(site.address, 5), M.PASS) then return false end
    end
    return true
end

return M
