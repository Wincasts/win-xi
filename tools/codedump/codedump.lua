-- codedump: writes FFXiMain.dll as it is in memory, unpacked, to a file, for reading its code
-- outside the game. It is a tool, not one of the addons: copy this folder into Ashita's addons
-- folder, unload buff (whose hidden icons change the code it looks for), then
--
--     /addon load codedump
--
-- It writes ffximain.bin and ffximain.txt beside itself, says so in the chat, and can be unloaded.
-- ffximain.txt has the module's base and size, and where the places buff patches are.
addon.name    = 'codedump';
addon.author  = 'win';
addon.version = '1.0';
addon.desc    = 'Writes FFXiMain.dll as it is in memory to a file.';

local bit = require('bit');
local ffi = require('ffi');
local chat = require('chat');

ffi.cdef[[
    typedef struct {
        void*    BaseAddress;
        void*    AllocationBase;
        uint32_t AllocationProtect;
        size_t   RegionSize;
        uint32_t State;
        uint32_t Protect;
        uint32_t Type;
    } codedump_mbi;
    size_t VirtualQuery(const void* address, codedump_mbi* buffer, size_t length);
]];

-- Whether a page can be read: committed, and neither no access nor a guard page
local MEM_COMMIT, PAGE_NOACCESS, PAGE_GUARD = 0x1000, 0x01, 0x100;
local mbi = ffi.new('codedump_mbi');
local function readable(address)
    if ffi.C.VirtualQuery(ffi.cast('const void*', address), mbi, ffi.sizeof(mbi)) == 0 then
        return false;
    end
    return mbi.State == MEM_COMMIT and bit.band(mbi.Protect, PAGE_NOACCESS) == 0 and bit.band(mbi.Protect, PAGE_GUARD) == 0;
end

-- The places buff's native.lua changes to hide the game's status icons
local places = {
    '75??8B4E0851B9',
    '7D??33C05EC20400C6',
    '85C00F??????????6A0232DBE8',
};

local function say(text)
    print(chat.header(addon.name):append(chat.message(text)));
end

ashita.events.register('load', 'codedump_load', function ()
    local base = ashita.memory.get_base('FFXiMain.dll');
    local size = ashita.memory.get_size('FFXiMain.dll');
    if base == nil or base == 0 or size == nil or size == 0 then
        say('FFXiMain.dll was not found.');
        return;
    end

    local bin = io.open(('%s\\ffximain.bin'):format(addon.path), 'wb');
    if bin == nil then
        say('ffximain.bin could not be written.');
        return;
    end
    -- a page at a time, so that one that cannot be read is left as zeroes rather than ending it
    local page, zero, unread = 0x1000, string.rep('\0', 0x1000), 0;
    for offset = 0, size - 1, page do
        local length = math.min(page, size - offset);
        local bytes;
        if readable(base + offset) then
            bytes = ffi.string(ffi.cast('const char*', base + offset), length);
        else
            bytes, unread = zero:sub(1, length), unread + 1;
        end
        bin:write(bytes);
    end
    bin:close();

    local lines = {
        ('base 0x%08X'):format(base),
        ('size 0x%08X'):format(size),
        ('unread pages %d'):format(unread),
    };
    for _, pattern in ipairs(places) do
        local at = ashita.memory.find('FFXiMain.dll', 0, pattern, 0, 0);
        lines[#lines + 1] = ('%s 0x%08X'):format(pattern, at or 0);
    end
    local txt = io.open(('%s\\ffximain.txt'):format(addon.path), 'w');
    if txt ~= nil then
        txt:write(table.concat(lines, '\n'), '\n');
        txt:close();
    end

    say(('Wrote ffximain.bin and ffximain.txt to %s. It can be unloaded.'):format(addon.path));
end);
