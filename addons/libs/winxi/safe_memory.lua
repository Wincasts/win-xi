-- Read-only Windows memory access for diagnostic probes. pcall cannot catch access violations;
-- check every region before reading. No VirtualProtect and no writes.
local ffi = require('ffi');
local bit = require('bit');
ffi.cdef[[
    typedef struct {
        void* BaseAddress;
        void* AllocationBase;
        unsigned long AllocationProtect;
        size_t RegionSize;
        unsigned long State;
        unsigned long Protect;
        unsigned long Type;
    } winxi_memory_info;
    size_t __stdcall winxi_VirtualQuery(const void*, winxi_memory_info*, size_t) __asm__("VirtualQuery");
]];
local kernel = ffi.load('kernel32');
local info = ffi.new('winxi_memory_info[1]');
local readable = { [2]=true, [4]=true, [8]=true, [0x20]=true, [0x40]=true, [0x80]=true };
local M = {};
function M.read(address, length)
    if type(address) ~= 'number' or type(length) ~= 'number' or address ~= math.floor(address)
        or length ~= math.floor(length) or length < 1 or length > 4096
        or address < 0x10000 or address + length > 0x100000000 then
        return nil, 'invalid range';
    end
    local cursor, finish = address, address + length;
    while cursor < finish do
        if kernel.winxi_VirtualQuery(ffi.cast('const void*', cursor), info, ffi.sizeof(info[0])) == 0 then
            return nil, 'VirtualQuery failed';
        end
        local protect = tonumber(info[0].Protect);
        if tonumber(info[0].State) ~= 0x1000 or bit.band(protect, 0x100) ~= 0
            or not readable[bit.band(protect, 0xFF)] then
            return nil, 'region is not readable';
        end
        local nextAddress = tonumber(ffi.cast('uintptr_t', info[0].BaseAddress)) + tonumber(info[0].RegionSize);
        if nextAddress <= cursor then return nil, 'invalid region'; end
        cursor = math.min(finish, nextAddress);
    end
    return ffi.string(ffi.cast('const char*', address), length);
end
return M;
