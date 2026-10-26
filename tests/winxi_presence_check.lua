-- winxi.presence with Windows's named mutexes stood in for: one addon announces, another sees it, for
-- this game's process alone, and no longer once it is withdrawn or its state is let go of.
package.path = 'addons/libs/?.lua;' .. package.path
local ffi = require('ffi')
local presence = require('winxi.presence')
assert(presence.Kernel == nil or ffi.os == 'Windows')
assert(not presence.Present('hideparty'), 'away from Windows nothing is present')
presence.Announce('hideparty') -- and nothing is announced, without failing

local mutexes, names, closed, pid = {}, {}, 0, 4242
local function handle(name)
    local h = ffi.new('char[1]')
    names[tonumber(ffi.cast('uintptr_t', ffi.cast('void*', h)))] = name
    mutexes[#mutexes + 1] = h -- kept alive for the test
    return ffi.cast('void*', h)
end
local open = {} -- name -> how many handles hold it
presence.Kernel = {
    winxi_presence_GetCurrentProcessId = function() return pid end,
    winxi_presence_CreateMutexA = function(_, _, name) open[name] = (open[name] or 0) + 1; return handle(name) end,
    winxi_presence_OpenMutexA = function(access, _, name)
        assert(access == 0x00100000, 'opened for SYNCHRONIZE alone')
        if (open[name] or 0) > 0 then open[name] = open[name] + 1; return handle(name) end
        return nil
    end,
    winxi_presence_CloseHandle = function(h)
        local name = names[tonumber(ffi.cast('uintptr_t', h))]
        open[name] = open[name] - 1
        closed = closed + 1
    end,
}
local now = 0
os.clock = function() return now end
assert(not presence.Present('hideparty'))
presence.Announce('hideparty')
assert(open['Local\\winxi-presence-4242-hideparty'] == 1, 'named for this game\'s process')
assert(not presence.Present('hideparty'), 'asked at most once a second')
now = 1.5
assert(presence.Present('hideparty') and open['Local\\winxi-presence-4242-hideparty'] == 1, 'present, and the handle opened to ask is closed')
pid = 9999
now = 3
assert(not presence.Present('hideparty'), 'another game\'s addon is not this one\'s')
pid = 4242
presence.Announce('hideparty')
assert(open['Local\\winxi-presence-4242-hideparty'] == 1, 'announced once')
presence.Withdraw('hideparty')
now = 4.5
assert(open['Local\\winxi-presence-4242-hideparty'] == 0 and not presence.Present('hideparty'), 'withdrawn: gone')
presence.Withdraw('hideparty') -- twice is nothing
presence.Announce('hideparty')
presence = nil
package.loaded['winxi.presence'] = nil
collectgarbage(); collectgarbage()
assert(open['Local\\winxi-presence-4242-hideparty'] == 0, 'a state let go of without Withdraw lets go of its mutex')
print('winxi presence: announced, seen once a second, this process alone, withdrawn, let go of with its state passed')
