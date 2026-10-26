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
-- A reloaded DLL can restart Sequence and can reuse the original block address.
hook.Sequence,hook.Count=1,1
hook.Names[0].EntityIndex=11
assert(plates.Find(11).EntityIndex==11)
reset()
hook.Names[0].EntityIndex=22
assert(plates.Find(11)==nil and plates.Find(22).EntityIndex==22,
    'observed reload must invalidate places even at the same address/sequence')
local replacement=ffi.new('namehook_t')
replacement.Sequence,replacement.Count=1,1
replacement.Names[0].EntityIndex=33
assert(plates.Find(33,replacement).EntityIndex==33 and plates.Find(22,replacement)==nil,
    'explicit hook owners with equal sequences must not share lookup caches')
replacement.Names[0].EntityIndex=44
assert(plates.Find(33,replacement)==nil, 'lookup must never return a different entity')
-- An observed unload must discard cached writers without dereferencing them.
local stale={Textures={[0]=123}}
for i=1,20 do
    if debug.getupvalue(plates.SetTexture,i)=='draw' then debug.setupvalue(plates.SetTexture,i,stale);break end
end
loaded=false;assert(plates.Hook()==nil)
plates.SetTexture(0,456)
assert(stale.Textures[0]==123, 'unload must drop stale writer pointers')
loaded=true
-- Unloaded and loaded again between two looks, at another address or as another build: Ashita says
-- it is loaded throughout, and what was found in the old DLL is let go of all the same, popups too
do
    local base, stamp = 0x10000000, 1
    local module = plates.Module
    plates.Module = function() return base, stamp, 0x40000 end
    local popupsLib = require('winxi.popups')
    local popupBlock = ffi.new('namehook_popups_t')
    popupBlock.Version, popupBlock.Size, popupBlock.PopupSize = 1, ffi.sizeof(popupBlock), ffi.sizeof('namehook_popup_t')
    local find = ashita.memory.find
    local popupScans = 0
    ashita.memory.find = function(m, o, signature, ...)
        if signature == '4E414D45484F4F4B504F505550530000' then
            popupScans = popupScans + 1
            return tonumber(ffi.cast('uintptr_t', ffi.cast('void*', popupBlock)))
        end
        return find(m, o, signature, ...)
    end
    local function at(p) return tonumber(ffi.cast('uintptr_t', ffi.cast('void*', p))) end
    now = now + 2
    local first = assert(plates.Hook())
    assert(at(first) == at(hook) and popupsLib.Hook() ~= nil and popupScans == 1)
    local generation = plates.Generation()
    for _ = 1, 10 do assert(at(plates.Hook()) == at(hook) and popupsLib.Hook() ~= nil) end
    assert(plates.Generation() == generation and popupScans == 1, 'the same DLL: kept, not looked for again')

    local moved = ffi.new('namehook_t')
    moved.Version, moved.Size, moved.NameSize, moved.Hooked = 3, ffi.sizeof(moved), ffi.sizeof('namehook_name_t'), 1
    moved.Sequence, moved.Count = 1, 1
    moved.Names[0].EntityIndex = 55
    local old = hook
    hook, base = moved, 0x20000000
    assert(at(plates.Hook()) == at(moved), 'loaded again elsewhere: the new block, never the old')
    assert(plates.Generation() == generation + 1 and plates.Find(55).EntityIndex == 55)
    assert(popupsLib.Hook() ~= nil and popupScans == 2, 'popups let their block go with it')

    hook, stamp = old, 2
    assert(at(plates.Hook()) == at(old) and plates.Generation() == generation + 2, 'another build at the same address')
    assert(popupsLib.Hook() ~= nil and popupScans == 3)

    base = nil
    assert(plates.Hook() == nil and plates.Generation() == generation + 3, 'no DLL to be found: nothing kept')
    base = 0x10000000
    ashita.memory.find, plates.Module = find, module
end

package.loaded['winxi.version']={Number=45}
addon={}
local ok,reason=pcall(dofile,'addons/name/name.lua')
assert(not ok and tostring(reason):match('needs winxi %d+ or newer'), 'outdated WinXI must fail before loading newer modules')
print('namehook capabilities: old ABI retained, missing/malformed/unknown features rejected, bounded scans, lookup ownership, stale writers and reload recovery passed')
