-- Shared API compatibility: optional capability sidecar does not alter ABI 3.
package.path = 'addons/libs/?.lua;' .. package.path
local ffi = require('ffi')
local plates = require('winxi.nameplates')
local hook = ffi.new('namehook_t')
ffi.copy(hook.Magic, 'NAMEHOOK', 8)
hook.Version, hook.Size, hook.NameSize, hook.Hooked = 3, ffi.sizeof(hook), ffi.sizeof('namehook_name_t'), 1
local caps = dofile('tests/fixtures/namehook_capabilities.lua')
local loaded, available, now, scans = true, false, 0, 0
os.clock = function() return now end
AshitaCore = { GetPluginManager = function() return { IsLoaded = function() return loaded end } end }
ashita = { memory = { find = function(_, _, signature)
    local data = hook
    if signature == '4E414D45484F4F4B4341505300000000' then
        scans = scans + 1
        if not available then return 0 end
        data = caps
    end
    return tonumber(ffi.cast('uintptr_t', ffi.cast('void*', data)))
end } }
assert(plates.Hook(), 'old ABI-3 plugins remain available to older consumers')
assert(not plates.Supports(plates.Feature.IconOutline))
assert(plates.Problem() == nil and plates.Problem(plates.Feature.IconOutline):find('1.35',1,true))
for _=1,100 do assert(not plates.Supports(1)) end
assert(scans==1, 'missing capability blocks must not be scanned per frame')
available,now=true,2
assert(plates.Supports(1) and plates.Supports(7) and not plates.Supports(8))
local metadata=assert(plates.Capabilities())
assert(metadata.build==135 and metadata.version==1 and metadata.features==7)
metadata.features=0;assert(plates.Supports(1), 'public metadata must not mutate the DLL capability block')
local warm=scans
for _=1,100 do assert(plates.Supports(1)) end
assert(scans==warm and plates.Problem(1)==nil)
local function reset()
    loaded=false;assert(not plates.Hook());loaded=true;now=now+2
end
caps.Size=1;reset();assert(not plates.Supports(1))
caps.Size=ffi.sizeof(caps);caps.Version=2;reset();assert(not plates.Supports(1))
caps.Version=1;caps.Features=0;reset();assert(not plates.Supports(1))
caps.Features=7;reset();assert(plates.Supports(1))
loaded=false;assert(not plates.Supports(1))
loaded=true;assert(plates.Supports(1), 'unload/reload clears capability ownership and scan throttle')
package.loaded['winxi.version']={Number=45}
addon={}
local ok,reason=pcall(dofile,'addons/name/name.lua')
assert(not ok and tostring(reason):find('needs winxi 48',1,true), 'outdated WinXI must fail before loading newer modules')
print('namehook capabilities: old ABI retained, missing/malformed/unknown features rejected, bounded scans and reload recovery passed')
