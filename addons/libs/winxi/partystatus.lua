-- winxi.partystatus: the statuses of the player and of the five others of the player's own party, as
-- the game keeps them. Of anyone else the game keeps none: what lands on them is winxi.debuffs' to count.
--
--     partystatus.Own(list)               the player's own into list, in the game's order; none between areas
--     partystatus.Member(serverId, list)  one other member's into list; false when the game keeps none for them
--     partystatus.Party(lists)            all five others' at once into lists[1] to lists[5], each with .id
--                                         the member's server id (0 for an empty place)
--
-- Each list is filled from 1 with the statuses' numbers, list.count says how many, and anything after
-- them is taken out, so that #list says the same. The lists are the caller's, to be kept and filled again.
local bit = require('bit');

local partystatus = {};

local OTHERS     = 5;    -- the others of the player's party, whose statuses the game keeps
local SLOTS      = 32;   -- statuses kept for each
local ENTRY_SIZE = 0x30; -- one member's: the server id, then two bits of each status's number four to
                         -- a byte from 8, then the rest of each number a byte each from 16
local NONE       = 255;  -- an empty slot
local LAST       = 0x3FF; -- the highest number ten bits can hold

-- Ends list after count entries
local function Finish(list, count)
    for index = #list, count + 1, -1 do
        list[index] = nil;
    end
    list.count = count;
end

function partystatus.Own(list)
    local count = 0;
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (player ~= nil and player:GetIsZoning() == 0) then
        local ids = player:GetStatusIcons();
        if (type(ids) == 'table') then
            for slot = 1, SLOTS do
                local id = ids[slot];
                if (id ~= nil and id > 0 and id ~= NONE and id <= LAST) then
                    count = count + 1;
                    list[count] = id;
                end
            end
        end
    end
    Finish(list, count);
end

-- Where the game's list of the five begins, or 0. The pointer is looked for again until it is found.
local pointer = nil;

local function Base()
    if (pointer == nil or pointer == 0) then
        pointer = AshitaCore:GetPointerManager():Get('party.statusicons');
    end
    if (pointer == nil or pointer == 0) then
        return 0;
    end
    return ashita.memory.read_uint32(pointer) or 0;
end

-- A member's entry read in one as a table of its bytes from 1, where Ashita can (ashita.memory.read_array);
-- or nil, to be read a byte at a time instead
local function ReadEntry(at)
    local read = ashita.memory.read_array;
    if (read == nil) then
        return nil;
    end
    local ok, bytes = pcall(read, at, ENTRY_SIZE);
    if (not ok or type(bytes) ~= 'table' or #bytes < ENTRY_SIZE or type(bytes[1]) ~= 'number') then
        return nil;
    end
    return bytes;
end

local function IdOf(at, bytes)
    if (bytes ~= nil) then
        return bytes[1] + bytes[2] * 0x100 + bytes[3] * 0x10000 + bytes[4] * 0x1000000;
    end
    return ashita.memory.read_uint32(at) or 0;
end

-- The statuses of the entry at at into list
local function Decode(at, bytes, list)
    local count, high = 0, 0;
    for slot = 0, SLOTS - 1 do
        local pair = slot % 4;
        if (pair == 0) then
            local offset = 8 + slot / 4;
            high = bytes ~= nil and bytes[offset + 1] or ashita.memory.read_uint8(at + offset);
        end
        local low = bytes ~= nil and bytes[17 + slot] or ashita.memory.read_uint8(at + 16 + slot);
        local status = bit.band(bit.rshift(high, pair * 2), 0x03) * 256 + low;
        if (status > 0 and status ~= NONE) then
            count = count + 1;
            list[count] = status;
        end
    end
    Finish(list, count);
end

function partystatus.Member(serverId, list)
    local base = serverId ~= 0 and Base() or 0; -- an empty place, id 0, would match the empty entries
    if (base ~= 0) then
        for member = 0, OTHERS - 1 do
            local at = base + ENTRY_SIZE * member;
            if (ashita.memory.read_uint32(at) == serverId) then
                Decode(at, ReadEntry(at), list);
                return true;
            end
        end
    end
    Finish(list, 0);
    return false;
end

function partystatus.Party(lists)
    local base = Base();
    for member = 1, OTHERS do
        local list = lists[member];
        list.id = 0;
        if (base ~= 0) then
            local at = base + ENTRY_SIZE * (member - 1);
            local bytes = ReadEntry(at);
            list.id = IdOf(at, bytes);
            if (list.id ~= 0) then
                Decode(at, bytes, list);
            end
        end
        if (list.id == 0) then
            Finish(list, 0);
        end
    end
end

return partystatus;
