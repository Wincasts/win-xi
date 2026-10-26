-- plugins/ABI.md's promise from the addons' side: a block is read when its Version is the addon's and it is at
-- least as large as the addon's copy, so a newer plugin that adds fields after its 1.0 layout is still read by
-- addons made before it; one smaller, or of another Version, is not. Has says whether a newer field is there.
-- Checked through winxi.abi itself and through real readers: nameplates, popups, lens and gamekeys, each handed
-- the block as 1.0 has it, as a future plugin would (larger, with something after), and as an older one.
package.path = 'addons/libs/?.lua;' .. package.path
local ffi = require('ffi')
local abi = require('winxi.abi')

local failures = 0
local function check(ok, what) if not ok then failures = failures + 1; print('FAILED: ' .. what) end end

-- winxi.abi alone, on a block of its own
ffi.cdef[[
    typedef struct { char Magic[16]; uint32_t Version, Size, A; } abi_test_t;
    typedef struct { char Magic[16]; uint32_t Version, Size, A, B; } abi_test_future_t;
]]
local now = ffi.new('abi_test_t', { Version = 2, Size = ffi.sizeof('abi_test_t') })
check(abi.Accepts(now, 'abi_test_t', 2), 'the 1.0 block is read')
check(not abi.Accepts(now, 'abi_test_t', 3), 'another Version is not')
check(not abi.Accepts(nil, 'abi_test_t', 2), 'nothing is not')
local future = ffi.new('abi_test_future_t', { Version = 2, Size = ffi.sizeof('abi_test_future_t') })
check(abi.Accepts(ffi.cast('abi_test_t*', future), 'abi_test_t', 2), 'a future plugin\'s larger block is read by an old addon')
check(abi.Has(future, 'abi_test_future_t', 'B'), 'a new addon finds the new field on the new plugin')
check(not abi.Has(ffi.cast('abi_test_future_t*', now), 'abi_test_future_t', 'B'), '... and not on an old plugin')
check(abi.Has(ffi.cast('abi_test_future_t*', now), 'abi_test_future_t', 'A'), '... where the old fields are still there')
check(not abi.Has(future, 'abi_test_future_t', 'NoSuchField'), 'a field neither has is not there')
now.Size = ffi.sizeof('abi_test_t') - 4
check(not abi.Accepts(now, 'abi_test_t', 2), 'a block smaller than the addon\'s copy is not read')

-- A block the size a plugin says, filled from a ctype, in memory a reader can be pointed at
local kept = {}
local function block(ctype, extra, fill)
    local size = ffi.sizeof(ctype) + extra
    local memory = ffi.new('uint8_t[?]', size + 16)
    kept[#kept + 1] = memory
    local b = ffi.cast(ctype .. '*', memory)
    fill(b, size)
    return tonumber(ffi.cast('uintptr_t', memory)), b
end

-- The readers, with Ashita stood in for
local loaded = { namehook = true, lens = true, uihook = true }
local addresses = {}
local clock = 0
os.clock = function() clock = clock + 2; return clock end -- each look a fresh one, past the once-a-second limit
AshitaCore = { GetPluginManager = function() return { IsLoaded = function(_, name) return loaded[name] == true end } end }
ashita = { memory = {
    find = function(module, _, magic) return addresses[module .. ':' .. magic] or 0 end,
    get_base = function(module) return addresses[module] end } }

local nameplates = require('winxi.nameplates')
nameplates.Module = function() return 1, 0, 0 end
local popups = require('winxi.popups')
local lensLib = require('winxi.lens')
local gamekeys = require('winxi.gamekeys')

-- namehook's 1.0 block ends where LoadId (1.42) begins: an addon now reads one that size too
local namesAt10 = ffi.offsetof('namehook_t', 'LoadId')
local function names(extra, version, id)
    local at, b = block('namehook_t', 0, function(b)
        b.Version, b.Size, b.NameSize, b.Hooked, b.LoadId = version or 3, namesAt10 + extra, ffi.sizeof('namehook_name_t'), 1, id or 0
    end)
    addresses['namehook.dll:4E414D45484F4F4B0000000000000000'] = at
    return b
end
local function popupBlock(extra, version)
    addresses['namehook.dll:4E414D45484F4F4B504F505550530000'] = block('namehook_popups_t', extra, function(b, size)
        b.Version, b.Size, b.PopupSize, b.Hooked = version or 1, size, ffi.sizeof('namehook_popup_t'), 1
    end)
end
local function warp(extra, version)
    addresses['lens.dll'] = (addresses['lens.dll'] or 0x1000) + 0x1000 -- a new DLL each time: looked for afresh
    addresses['lens.dll:4C454E532D5741525000000000000000'] = block('lens_warp_t', extra, function(b, size)
        b.Version, b.Size, b.Frame, b.WarpedFrame, b.Mode, b.Strength, b.TanH, b.TanV = version or 1, size, 10, 10, 0, 0.5, 2, 1
    end)
end
local function keys(extra, version)
    addresses['uihook.dll'] = (addresses['uihook.dll'] or 0x1000) + 0x1000
    addresses['uihook.dll:5549484F4F4B2D4B4559530000000000'] = block('uihook_keys_t', extra, function(b, size)
        b.Version, b.Size, b.Supported = version or 1, size, 1
    end)
end
local function reload() loaded.namehook = false; nameplates.Hook(); popups.Hook(); loaded.namehook = true end

for _, case in ipairs({ { 'as 1.0 has it', 0, nil, true }, { 'a future plugin\'s, 64 bytes larger', 64, nil, true },
                        { 'smaller than the addon\'s copy', -4, nil, false }, { 'of another Version', 0, 99, false } }) do
    local label, extra, version, read = case[1], case[2], case[3], case[4]
    reload()
    names(extra, version)
    check((nameplates.Hook() ~= nil) == read, 'nameplates, a block ' .. label)
    popupBlock(extra, version)
    check((popups.Hook() ~= nil) == read, 'popups, a block ' .. label)
    warp(extra, version)
    check((lensLib.Current() ~= nil) == read, 'lens, a block ' .. label)
    keys(extra, version)
    check(gamekeys.new().Ready() == read, 'gamekeys, a block ' .. label)
end

-- A newer addon on namehook 1.0: read, and what 1.0 did not have goes without
reload()
names(0)
check(nameplates.Hook() ~= nil and nameplates.Dropped().namesDropped == nil, 'namehook 1.0\'s block: read, its drop counts not there')
-- namehook 1.42 loaded again at the same address as the same build: its LoadId says so
reload()
local current = names(ffi.sizeof('namehook_t') - namesAt10, 3, 101)
local first = nameplates.Hook()
current.NamesDropped, current.DrawingsRefused = 2, 5
local d = nameplates.Dropped()
check(first ~= nil and d.namesDropped == 2 and d.drawingsRefused == 5, 'namehook 1.42\'s drop counts read')
local generation = nameplates.Generation()
current.LoadId = 202
check(nameplates.Hook() ~= nil and nameplates.Generation() == generation + 1, 'loaded again at the same address: let go of and found afresh')
check(nameplates.Generation() == generation + 1, '... once')

if failures == 0 then
    print('winxi abi: a newer plugin\'s larger block read by older addons, a smaller or other Version refused, newer fields found only where there; nameplates, popups, lens and gamekeys passed')
else
    os.exit(1)
end
