-- The map grid, "(H-9)", worked out by the game's own function for it, for the times the game does not draw its
-- clock (fishing, events, its HUD hidden), when the grid the clock last printed is not current. It is the function
-- the clock itself asks, every second or so, as it draws: the player's place on the zone's map, its letter and
-- number; nothing but the game's own buffer for the words is written. Found through the clock's call to it, and
-- asked as the clock asks (honouring the zone's own "no grid"), so the grid is the clock's.
--
--   grid.Read()     the grid, as the clock would print it; nil where there is none or the function is not found
--   grid.Status()   why there is none, or nil
local ffi = require('ffi')
local grid = {}

-- The clock's grid getter (033E0350): on its timer, the grid function called with 1, its words copied after
local CLOCK_GETTER = '8A0D????????6A01884E10E8????????83C40485C07509884611'
local CALL_AT = 11 -- the E8's place in it
-- The grid function's own start (033B7600), checked at the call's target: the game's object, player, then the zone's flags
local FUNCTION_START = { 0xA1, nil, nil, nil, nil, 0x83, 0xEC, 0x14, 0x85, 0xC0, 0x0F, 0x84 }

local function_, problem, retry = nil, nil, 0

local function Find()
    if function_ then return function_ end
    if os.clock() < retry then return nil end
    retry = os.clock() + 5
    local memory = ashita.memory
    local at = memory.find('FFXiMain.dll', 0, CLOCK_GETTER, 0, 0)
    if not at or at == 0 then problem = 'the clock\'s grid call was not found'; return nil end
    local relative = memory.read_uint32(at + CALL_AT + 1) or 0
    if relative >= 0x80000000 then relative = relative - 0x100000000 end
    local target = at + CALL_AT + 5 + relative
    for i, byte in ipairs(FUNCTION_START) do
        if byte and memory.read_uint8(target + i - 1) ~= byte then problem = 'the grid function is not the one known'; return nil end
    end
    function_ = ffi.cast('const char* (__cdecl *)(int32_t)', target)
    problem = nil
    return function_
end

function grid.Read()
    local ok, words = pcall(function()
        local read = Find()
        if not read then return nil end
        local found = read(1)
        if found == nil then return nil end -- no player, or a zone without a grid
        return ffi.string(found)
    end)
    if not ok then problem = 'the grid could not be read'; return nil end
    -- as the clock's own is taken: its eight characters at most, and only what a grid is made of (not "(?-?)", off the map)
    if type(words) ~= 'string' or #words > 8 or not words:match('^[%w%s%(%)%-]+$') then return nil end
    return words
end

function grid.Status() return problem end

return grid
