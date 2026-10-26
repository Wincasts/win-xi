-- winxi.presence: whether another addon is loaded in this game. Each addon runs in a Lua state of its own
-- and Ashita has no list of them, so an addon that others must know about announces itself with a named
-- mutex of Windows's, named for this game's process, held while it is loaded:
--
--   presence.Announce(name)   while this addon is loaded (kept until Withdraw, or the state is closed)
--   presence.Withdraw(name)   no longer
--   presence.Present(name)    whether some addon in this game has announced name; asked of Windows at
--                             most once a second for each name
--
-- Away from Windows (the tests) nothing is announced and nothing is present, unless presence.Kernel is
-- given a stand-in with the four functions below.
local ffi = require('ffi');

pcall(ffi.cdef, [[
    void* __stdcall winxi_presence_CreateMutexA(void*, int, const char*) __asm__("CreateMutexA");
    void* __stdcall winxi_presence_OpenMutexA(unsigned long, int, const char*) __asm__("OpenMutexA");
    int __stdcall winxi_presence_CloseHandle(void*) __asm__("CloseHandle");
    unsigned long __stdcall winxi_presence_GetCurrentProcessId(void) __asm__("GetCurrentProcessId");
]]);

local presence = {};

local SYNCHRONIZE = 0x00100000;
local ASK_EVERY = 1; -- seconds between asking Windows again whether a name is present

presence.Kernel = nil;
if (ffi.os == 'Windows') then
    local ok, kernel = pcall(ffi.load, 'kernel32');
    if (ok) then presence.Kernel = kernel; end
end

local held = {};   -- name -> the mutex this state holds for it
local asked = {};  -- name -> { at = os.clock(), present = bool }

local function NameOf(name)
    return ('Local\\winxi-presence-%d-%s'):format(tonumber(presence.Kernel.winxi_presence_GetCurrentProcessId()), name);
end

local function Valid(handle)
    return handle ~= nil and tonumber(ffi.cast('uintptr_t', handle)) ~= 0;
end

function presence.Announce(name)
    if (presence.Kernel == nil or held[name] ~= nil) then return; end
    local kernel = presence.Kernel;
    local ok, handle = pcall(kernel.winxi_presence_CreateMutexA, nil, 0, NameOf(name));
    if (ok and Valid(handle)) then
        held[name] = ffi.gc(handle, function (h) kernel.winxi_presence_CloseHandle(h); end);
    end
end

function presence.Withdraw(name)
    local handle = held[name];
    if (handle == nil) then return; end
    held[name] = nil;
    ffi.gc(handle, nil);
    presence.Kernel.winxi_presence_CloseHandle(handle);
end

function presence.Present(name)
    if (presence.Kernel == nil) then return false; end
    local now = os.clock();
    local last = asked[name];
    if (last ~= nil and now - last.at < ASK_EVERY) then return last.present; end
    local found = false;
    local ok, handle = pcall(presence.Kernel.winxi_presence_OpenMutexA, SYNCHRONIZE, 0, NameOf(name));
    if (ok and Valid(handle)) then
        found = true;
        presence.Kernel.winxi_presence_CloseHandle(handle);
    end
    asked[name] = { at = now, present = found };
    return found;
end

return presence;
