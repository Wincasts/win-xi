-- A second addon drawing names through namehook 1.45's claim slots, as winxi.nameplates gives them: slots
-- taken (one each, the same again for the same owner, none when all are taken), claims renewed, names drawn
-- into the slot's own buffer and not the plugin's own, a slot lost to another noticed, released and cleared;
-- none from an older namehook.
package.path = 'addons/libs/?.lua;' .. package.path
local ffi = require('ffi')

local failures = 0
local function check(ok, what) if not ok then failures = failures + 1; print('FAILED: ' .. what) end end

local clock = 0
os.clock = function() clock = clock + 2; return clock end
local addresses, loaded = {}, true
AshitaCore = { GetPluginManager = function() return { IsLoaded = function() return loaded end } end }
ashita = { memory = { find = function(module, _, magic) return addresses[module .. ':' .. magic] or 0 end } }
package.loaded.imgui = { GetIO = function() return { DisplaySize = { x = 1920, y = 1080 } } end }

local nameplates = require('winxi.nameplates')
nameplates.Module = function() return 1, 0, 0 end

-- below 4 GB, as the plugin's addresses of them are 32 bits
pcall(ffi.cdef, 'void* mmap(void*, size_t, int, int, int, long);')
local function low(ctype) return ffi.cast(ctype .. '*', ffi.C.mmap(nil, ffi.sizeof(ctype), 3, 0x62, -1, 0)) end
local function at(p) return tonumber(ffi.cast('uintptr_t', ffi.cast('void*', p))) end

local names = low('namehook_t')
names.Version, names.Size, names.NameSize, names.Hooked, names.Frame = 3, ffi.sizeof('namehook_t'), ffi.sizeof('namehook_name_t'), 1, 50
names.TargetWidth, names.TargetHeight, names.Width, names.Height = 1920, 1080, 1920, 1080
local own = low('namehook_draw_t')
names.Draw = at(own)
addresses['namehook.dll:4E414D45484F4F4B0000000000000000'] = at(names)

local owner = nameplates.OwnerOf('platesplus')
check(nameplates.TakeSlot(owner) == nil and select(2, nameplates.TakeSlot(owner)):find('1.45', 1, true) ~= nil, 'an older namehook: no slot, and it says so')

local claims = low('namehook_claims_t')
claims.Version, claims.Size, claims.SlotSize, claims.SlotsMax, claims.SharedPriority = 1, ffi.sizeof('namehook_claims_t'), ffi.sizeof('namehook_claim_slot_t'), 3, 100
local draws = {}
for i = 0, 2 do draws[i] = low('namehook_draw_t'); draws[i].QuadsMax = 16384; claims.Slots[i].Draw = at(draws[i]) end
addresses['namehook.dll:4E414D45484F4F4B434C41494D530000'] = at(claims)

local slot = nameplates.TakeSlot(owner, 200)
check(slot == 1 and claims.Slots[0].Owner == owner and claims.Slots[0].Priority == 200, 'the first free slot taken')
check(nameplates.TakeSlot(owner, 200) == 1, 'the same owner: the same slot')
check(nameplates.TakeSlot(nameplates.OwnerOf('b')) == 2 and nameplates.TakeSlot(nameplates.OwnerOf('c')) == 3, 'others take the others')
check(nameplates.TakeSlot(nameplates.OwnerOf('d')) == nil, 'all taken: none')

check(nameplates.ClaimSlot(slot, owner, 0x80) and claims.Slots[0].Categories == 0x80 and claims.Slots[0].ClaimFrame == 50, 'the claim renewed')
check(not nameplates.ClaimSlot(slot, nameplates.OwnerOf('b'), 0x80), 'not by another owner')
check(nameplates.BeginDrawing(nameplates.SlotDrawing(slot), true) ~= nil, 'drawing into the slot')
check(nameplates.SetTexture(0, 0x1234), 'a texture given')
check(nameplates.BeginName(0x401, 1, 1, 0xFF000000), 'a name begun')
nameplates.Quad(0, 0, 10, 10, 0, 0, 1, 1, 0xFFFFFFFF, 0)
nameplates.EndName()
check(draws[0].Frame == 50 and draws[0].QuadCount == 1 and draws[0].Entities[0x401].Count == 1 and draws[0].Textures[0] == 0x1234, 'into the slot\'s own buffer')
check(own.QuadCount == 0 and own.Textures[0] == 0, 'and not the plugin\'s own claim\'s')

-- the claim lapsed and another took the slot: noticed, and the drawing is not the other's to lose
claims.Slots[0].Owner = nameplates.OwnerOf('e')
check(not nameplates.ClaimSlot(slot, owner, 0x80), 'a slot another has taken is noticed')
nameplates.ReleaseSlot(slot, owner)
check(claims.Slots[0].Owner == nameplates.OwnerOf('e') and draws[0].QuadCount == 1, 'nor released from under it')
claims.Slots[0].Owner = owner
nameplates.ReleaseSlot(slot, owner)
check(claims.Slots[0].Owner == 0 and claims.Slots[0].Categories == 0 and draws[0].QuadCount == 0 and draws[0].Textures[0] == 0, 'released: free, its drawing cleared')
check(nameplates.TakeSlot(owner) == 1, 'and taken again')

if failures == 0 then
    print('winxi slots: taken, the same again, none when full, claims renewed, names drawn into the slot\'s own buffer, a lost slot noticed, released and cleared, none before namehook 1.45 passed')
else
    os.exit(1)
end
