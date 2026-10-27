-- vis: finds the calls to the scale function in a run of bytes, reads what each caller does,
-- builds the stub that re-scales one, and in the game's absence says so and still answers commands
package.path = 'addons/libs/?.lua;' .. package.path; require('winxi.gamedata').Root((package.searchpath('winxi.gamedata', package.path):gsub('gamedata%.lua$', 'data/'))) -- the server's sets, beside the winxi loaded: the repository's, or a release's own
local scan = require('scan')
local printCheck = H.print
H.print = function(label, ...)
    printCheck(label, ...)
    for i = 1, select('#', ...) do assert(select(i, ...) ~= false, label) end
end

local function le32(v) return scan.le32(v) end
local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- a run of client code at base, with three calls to the scale function (one landing 3 bytes before
-- the pattern, as a call to a function with a short prologue would) and one call elsewhere
local base, target = 0x00500000, 0x00400010
local code = {}
local function emit(bytes) for _, b in ipairs(bytes) do code[#code + 1] = b end end
local function call(to) local rel = scan.rel32(base + #code, to) emit({ 0xE8, rel[1], rel[2], rel[3], rel[4] }) end
emit({ 0xB9, 0x00, 0x00, 0x00, 0x00 })        -- mov ecx, 0
emit({ 0xFF, 0x74, 0x24, 0x10 })              -- push dword [esp+0x10]
local first = base + #code
call(target)
emit({ 0xD9, 0x9D, 0x28, 0x94, 0x03, 0x00 })  -- fstp dword [ebp+0x39428]
emit({ 0x33, 0xC9 })                          -- xor ecx, ecx
emit({ 0xFF, 0x35, 0x00, 0x10, 0x40, 0x00 })  -- push dword [0x00401000]
local second = base + #code
call(target - 3)
emit({ 0xD9, 0x5D, 0xF8 })                    -- fstp dword [ebp-8]
emit({ 0x8B, 0x0D, 0x44, 0x33, 0x22, 0x11 })  -- mov ecx, [0x11223344]
emit({ 0xDD, 0xD8 })                          -- fstp st(0)
local other = base + #code
call(0x00450000)                              -- some other function
emit({ 0xB9, 0x01, 0x00, 0x00, 0x00 })        -- mov ecx, 1
emit({ 0x51 })                                -- push ecx
local third = base + #code
call(target)
emit({ 0xD8, 0x0D, 0x00, 0x20, 0x40, 0x00 })  -- fmul dword [0x00402000]
emit({ 0xC2, 0x04, 0x00 })                    -- ret 4

local found = scan.callers(code, base, target, #code, 16)
H.print('callers: three found', #found == 3, '| the first', found[1] and found[1].address == first, '| exact', found[1] and found[1].delta == 0,
    '| the second', found[2] and found[2].address == second, '| landing 3 before', found[2] and found[2].delta == 3,
    '| the third', found[3] and found[3].address == third, '| not the other', not (found[2] and found[2].address == other))
H.print('callers: none beyond reach', #scan.callers(code, base, target, #code, 2) == 2,
    '| a call in the margin is still read', #scan.callers(code, base, target, third - base, 16) == 2,
    '| and read whole when the count reaches its first byte', #scan.callers(code, base, target, third - base + 1, 16) == 3)

-- a thunk that jumps to the function, and a pointer table holding its address
local thunkCode, thunkBase = {}, 0x00600000
local function emitT(bytes) for _, b in ipairs(bytes) do thunkCode[#thunkCode + 1] = b end end
local thunk = thunkBase
do local rel = scan.rel32(thunkBase, target) emitT({ 0xE9, rel[1], rel[2], rel[3], rel[4] }) end
local pointerAt = thunkBase + #thunkCode
emitT(scan.le32(target))
emitT(scan.le32(0x00450000))
local viaThunk = thunkBase + #thunkCode
do local rel = scan.rel32(viaThunk, thunk) emitT({ 0xE8, rel[1], rel[2], rel[3], rel[4] }) end
local jumps = scan.jumps(thunkCode, thunkBase, target, #thunkCode, 16)
H.print('jumps: the thunk found', #jumps == 1, jumps[1] and jumps[1].address == thunk, '| no calls to the function here', #scan.callers(thunkCode, thunkBase, target, #thunkCode, 16) == 0,
    '| a call to the thunk', #scan.callers(thunkCode, thunkBase, thunk, #thunkCode, 0) == 1 and scan.callers(thunkCode, thunkBase, thunk, #thunkCode, 0)[1].address == viaThunk)
local refs = scan.references(thunkCode, thunkBase, target, #thunkCode)
H.print('references: the pointer found', #refs == 1, refs[1] == pointerAt, '| not the other', #scan.references(thunkCode, thunkBase, 0x00450000, #thunkCode) == 1,
    '| none in plain code', #scan.references(code, base, target, #code) == 0)

local function around(address)
    local before, after = {}, {}
    for i = 1, 24 do before[i] = code[address - base - 24 + i] or 0x90 end
    for i = 1, 24 do after[i] = code[address - base + 5 + i] or 0x90 end
    return scan.describe(before, after)
end
local d1, d2, d3 = around(first), around(second), around(third)
H.print('first caller: world', d1.selector == 'world', d1.ecx == 0, '| pushes [esp+0x10]', d1.push == 'dword [esp+0x10]',
    '| stores to the object range', d1.sink == 'fstp dword [ebp+0x39428]')
H.print('second caller: world by xor', d2.selector == 'world', d2.ecx == 0, '| pushes [0x00401000]', d2.push == 'dword [0x00401000]',
    '| stores to a local', d2.sink == 'fstp dword [ebp-0x8]')
H.print('third caller: entity', d3.selector == 'entity', d3.ecx == 1, '| pushes ecx', d3.push == 'ecx', '| multiplies', d3.sink == 'fmul dword [0x00402000]',
    '| then returns', d3.after[2] == 'ret 4')
local unknown = scan.describe({ 0x0F, 0x0B, 0x0F, 0x0B }, { 0x0F, 0x0B })
H.print('unreadable bytes: nothing decoded', #unknown.before == 0, #unknown.after == 0, unknown.selector == 'unknown', unknown.push == nil, unknown.sink == nil)
H.print('a selector read from memory', scan.describe({ 0x8B, 0x0D, 0x44, 0x33, 0x22, 0x11 }, {}).selector == 'from [0x11223344]')

-- operands
local text, len = scan.modrm({ 0x44, 0x24, 0x10 }, 1)
H.print('modrm: [esp+disp8]', text == '[esp+0x10]', len == 3)
text, len = scan.modrm({ 0x9D, 0x28, 0x94, 0x03, 0x00 }, 1)
H.print('modrm: [ebp+disp32]', text == '[ebp+0x39428]', len == 5)
text, len = scan.modrm({ 0x0D, 0x44, 0x33, 0x22, 0x11 }, 1)
H.print('modrm: [disp32]', text == '[0x11223344]', len == 5)
text, len = scan.modrm({ 0x4C, 0x88, 0x20 }, 1)
H.print('modrm: [eax+ecx*4+disp8]', text == '[eax+ecx*4+0x20]', len == 3)
text, len = scan.modrm({ 0x04, 0x24 }, 1)
H.print('modrm: [esp]', text == '[esp]', len == 2)
text, len = scan.modrm({ 0x04, 0x8D, 0x00, 0x10, 0x00, 0x00 }, 1)
H.print('modrm: [ecx*4+disp32] with no base', text == '[ecx*4+0x1000]', len == 6)
H.print('modrm: short bytes', scan.modrm({ 0x9D, 0x28 }, 1) == nil, scan.modrm({}, 1) == nil)

-- the stub: push [esp+4]; call target; fmul [stub+24]; ret 4
local stub = 0x10000000
local bytes = scan.stub(stub, target)
local rel = le32(target - (stub + 9))
local ratio = le32(stub + 24)
H.print('stub: 18 bytes', #bytes == 18, '| push [esp+4]', same({ bytes[1], bytes[2], bytes[3], bytes[4] }, { 0xFF, 0x74, 0x24, 0x04 }),
    '| call from +4', bytes[5] == 0xE8 and same({ bytes[6], bytes[7], bytes[8], bytes[9] }, rel),
    '| fmul the ratio at +24', bytes[10] == 0xD8 and bytes[11] == 0x0D and same({ bytes[12], bytes[13], bytes[14], bytes[15] }, ratio),
    '| ret 4', same({ bytes[16], bytes[17], bytes[18] }, { 0xC2, 0x04, 0x00 }))
H.print('rel32: a backward call wraps', same(scan.rel32(0x10000004, 0x00400010), { 0x07, 0x00, 0x40, 0xF0 }),
    '| and reads back', scan.readInt32({ 0x07, 0x00, 0x40, 0xF0 }, 1) == 0x00400010 - 0x10000009)
H.print('ratio: 1 at world 2 is a half', scan.ratio(1, 2) == 0.5, '| 1.3 at world 0 is 1.3', scan.ratio(1.3, 0) == 1.3, '| nil world too', scan.ratio(2, nil) == 2)

-- in the harness there is no client: the load says so, and the commands still answer
H.load()
local said = table.concat(H.printed, '\n')
H.print('load without the client: says the function was not found', said:find('not found', 1, true) ~= nil)
H.print('/vis help is taken', H.command('/vis help') == true, '| and lists the commands', table.concat(H.printed, '\n'):find('/vis patch <n> <mult>', 1, true) ~= nil)
H.print('/vis patch without a number complains', H.command('/vis patch') == true, table.concat(H.printed, '\n'):find('Usage: /vis patch', 1, true) ~= nil)
H.print('/vis unpatch 3 with nothing patched', H.command('/vis unpatch 3') == true, table.concat(H.printed, '\n'):find('#3 was not patched', 1, true) ~= nil)
H.print('/vis fovscan is gone', H.command('/vis fovscan zoomed') == true, table.concat(H.printed, '\n'):find('fovscan', 1, true) == nil)
H.print('another command is left alone', H.command('/other') == false)
-- an event that errors is caught and said once, and the addon keeps going: Ashita would unload it
-- without its unload event, leaving the game patched
local errOk = pcall(H.command, nil)
local errOk2 = pcall(H.command, nil)
local _, failures = table.concat(H.printed, '\n'):gsub('The command event failed', '')
H.print('an erroring event is caught', errOk, errOk2, '| said once', failures == 1, '| still answers', H.command('/vis help') == true)
H.unload()
H.print('unloads cleanly', true)
-- the selector is what is pushed: push 1 is the entity multiplier, push 0 the world one, whatever ecx holds
H.print('a pushed selector: 1 is entity', scan.describe({ 0x8B, 0xCE, 0x6A, 0x01, 0x89, 0x17 }, {}).selector == 'entity',
    '| 0 is world', scan.describe({ 0x8B, 0xCE, 0x6A, 0x00, 0x89, 0x17 }, {}).selector == 'world',
    '| ecx alone is only a hint', scan.describe({ 0x8B, 0xCE }, {}).selector == 'from esi')

-- the fog's two calls, by their shape: in the function before the entry, push 0, fmul after; as seen
-- in the game, the entry 92 before the pattern, the calls 0x4D and 0x34 before the entry, and a
-- push 1 call before them that is not the fog, plus a group landing 492 before that is another function
local pattern = 0x0334930C
local entry = pattern - 92
local function rec(address, delta, push, after)
    local before = push and { 0x6A, push, 0x89, 0x17 } or { 0x8B, 0xCE }
    return { address = address, delta = delta, pattern = pattern, info = scan.describe(before, after) }
end
local fmulEdi, fmulEbp, fstp = { 0xD8, 0x0F, 0x8B, 0xCE }, { 0xD8, 0x4D, 0x00, 0xD9 }, { 0xD9, 0x9D, 0x28, 0x94, 0x03, 0x00 }
local records = {
    rec(0x0333BF53, 92, nil, fstp),                 -- the object range, after the entry's own neighbourhood
    rec(0x0333D436, 492, nil, { 0x8B, 0x15 }),      -- the other function's callers
    rec(entry - 0xC5, 92, 1, fmulEdi),              -- push 1: the entity branch, not the fog
    rec(entry - 0x4D, 92, 0, fmulEdi),              -- fog start
    rec(entry - 0x34, 92, 0, fmulEbp),              -- fog end
    rec(0x0334B901, 92, nil, { 0x8B, 0x46, 0x1C }), -- the helper
    rec(0x0334BA52, 492, nil, { 0x5E }),
}
local fog = scan.fogCallers(records, 512)
H.print('fog: two calls found', fog ~= nil and #fog == 2, '| the start', fog and fog[1].address == entry - 0x4D, '| the end', fog and fog[2].address == entry - 0x34)
local three = { records[3], records[4], records[5], rec(entry - 0x20, 92, 0, fmulEdi) }
H.print('fog: three world calls there is not the fog', scan.fogCallers(three, 512) == nil,
    '| one is not either', scan.fogCallers({ records[4] }, 512) == nil,
    '| a call after the entry is not counted', scan.fogCallers({ records[4], rec(entry + 0x10, 92, 0, fmulEdi) }, 512) == nil,
    '| nor one beyond the window', scan.fogCallers({ records[4], rec(entry - 600, 92, 0, fmulEdi) }, 512) == nil)

-- the settings commands, without the client: saved and said, the fog calls reported not found
local function lastSaid() local n = #H.printed return table.concat({ H.printed[n - 4] or '', H.printed[n - 3] or '', H.printed[n - 2] or '', H.printed[n - 1] or '', H.printed[n] or '' }, '\n') end -- the status is five lines
H.print('status without the client', H.command('/vis') == true, table.concat(H.printed, '\n'):find('fog calls not found', 1, true) ~= nil)
local saves = H.saves()
H.print('/vis fog 1.5 is saved', H.command('/vis fog 1.5') == true, H.saves() == saves + 1, H.options().fog == 1.5,
    '| and said', lastSaid():find('fog x1.50', 1, true) ~= nil)
H.print('/vis world 2', H.command('/vis world 2') == true, H.options().world == 2, lastSaid():find('world x2.00', 1, true) ~= nil)
H.print('/vis entity 3', H.command('/vis entity 3') == true, H.options().entity == 3)
H.print('a bad value is refused', H.command('/vis fog x') == true, H.options().fog == 1.5, lastSaid():find('Usage: /vis fog', 1, true) ~= nil,
    '| so is zero', H.command('/vis world 0') == true, H.options().world == 2)
H.print('/vis fog alone shows the values', H.command('/vis fog') == true, lastSaid():find('fog x1.50', 1, true) ~= nil)

-- the extras: objects and detail (0 = the same as world), terrain (a toggle), saved and said; fov and square are lens's
H.print('/vis objects 3', H.command('/vis objects 3') == true, H.options().objects == 3, lastSaid():find('objects x3.00', 1, true) ~= nil)
H.print('/vis objects 0 is the same as world', H.command('/vis objects 0') == true, H.options().objects == 0, lastSaid():find('objects x2.00 (same as world)', 1, true) ~= nil)
H.print('/vis detail 4', H.command('/vis detail 4') == true, H.options().detail == 4, lastSaid():find('detail x4.00', 1, true) ~= nil,
    '| too much refused', H.command('/vis detail 101') == true, H.options().detail == 4)
H.print('terrain off to begin with', H.options().terrain == false, H.options().terrainOff == true)
H.command('/vis terrain on')
H.print('/vis terrain off', H.command('/vis terrain off') == true, H.options().terrain == false, lastSaid():find('terrain off', 1, true) ~= nil,
    '| terrain alone toggles', H.command('/vis terrain') == true, H.options().terrain == true, '| a bad word refused', H.command('/vis terrain maybe') == true, H.options().terrain == true)
H.print('/vis fov points to lens', H.command('/vis fov 60') == true, H.options().fov == nil, lastSaid():find('fov is the lens plugin\'s now: /lens fov <n>', 1, true) ~= nil,
    '| and square', H.command('/vis square on') == true, H.options().square == nil, lastSaid():find('/lens square on|off', 1, true) ~= nil,
    '| a preset takes neither', H.command('/vis dungeon fov 50') == true, H.options().kinds.dungeon.fov == nil)
H.print('help says where they went', H.command('/vis help') == true, table.concat(H.printed, '\n'):find('/lens fov, /lens middle and /lens square', 1, true) ~= nil,
    table.concat(H.printed, '\n'):find('/vis fov <n>', 1, true) == nil)

-- the real bytes, from the game's report of 2026-10-20 (drawscale 0.3): the fog's calls and the object
-- range's, recognised as they lie, the fog end's push 0 four instructions before its call
local function hexBytes(s) local t = {} for b in s:gmatch('%x%x') do t[#t + 1] = tonumber(b, 16) end return t end
local function real(address, delta, before, after)
    return { address = address, delta = delta, pattern = 0x0334930C, info = scan.describe(hexBytes(before), hexBytes(after)) }
end
local realCallers = {
    real(0x0333BF53, 92, '95 20 94 03 00 D9 C0 D8 C9 53 D9 9D 24 94 03 00 8B 0D 04 CB 81 03 DD D8', 'D9 9D 28 94 03 00 A1 FC 68 61 03 8B 8D 20 94 03 00 D9 05 98 A6 4E 03 D8'),
    real(0x0333D436, 492, '00 8D 85 3C 93 03 00 8D 9D 38 93 03 00 6A 00 8D B5 34 93 03 00 50 53 56', '8B 15 6C 66 61 03 8B 42 0C 8B 16 52 6A 22 8B 08 50 FF 91 C8 00 00 00 8B'),
    real(0x033491EB, 92, 'C6 44 24 1B 00 8B 44 24 18 89 01 8B CE E8 5B DD FF FF 8B 10 6A 01 89 17', 'D8 0F 8B CE D9 1F E8 55 DD FF FF 6A 01 EB 76 8B CE E8 8A DD FF FF D9 40'),
    real(0x03349263, 92, 'C6 44 24 1B 00 8B 44 24 18 89 01 8B CE E8 53 DD FF FF 8B 10 6A 00 89 17', 'D8 0F 8B CE D9 1F E8 4D DD FF FF 6A 00 8B 00 8B CE 89 45 00 E8 2F 00 00'),
    real(0x0334927C, 92, '48 00 00 00 D8 0F 8B CE D9 1F E8 4D DD FF FF 6A 00 8B 00 8B CE 89 45 00', 'D8 4D 00 D9 5D 00 D9 07 D8 5D 00 DF E0 F6 C4 41 7A 0B D9 45 00 D8 05 1C'),
    real(0x0334B901, 92, '6E 69 FF 50 18 C3 90 51 8B 44 24 08 56 50 8B F1 C7 44 24 08 00 00 C8 42', '8B 46 1C D9 5C 24 0C 85 C0 74 0B 8B CE E8 08 B7 FF FF D9 5C 24 04 D9 44'),
    real(0x0334BA52, 492, '8B C6 8B 4C 24 14 8B 54 24 10 51 8B 4C 24 10 52 8B 54 24 10 51 52 8B C8', '5E C2 14 00 90 90 90 90 90 8B 0D 24 1F 7F 03 E9 15 CD FE FF 90 90 90 90'),
}
H.print('real: the fog end reads push 0 four back', realCallers[5].info.push == '0', realCallers[5].info.selector == 'world',
    '| the fog start', realCallers[4].info.push == '0', realCallers[4].info.selector == 'world',
    '| the entity branch', realCallers[3].info.push == '1', realCallers[3].info.selector == 'entity')
local realFog = scan.fogCallers(realCallers, 512)
H.print('real: the fog is callers at 0x03349263 and 0x0334927C', realFog ~= nil and #realFog == 2, realFog and realFog[1].address == 0x03349263, realFog and realFog[2].address == 0x0334927C)
local realObject = scan.objectCaller(realCallers)
H.print('real: the object range is the caller at 0x0333BF53', realObject ~= nil and realObject.address == 0x0333BF53,
    '| whose selector is not an immediate there', tonumber(realCallers[1].info.push or '') == nil,
    '| two of them is none', scan.objectCaller({ realCallers[1], realCallers[1] }) == nil)

-- three layers: the general values, a preset for the zone's kind (every zone a city, outdoors or
-- a dungeon by the server's zonekinds set), and the zone's own; the zone from the zone-in packet
local function said() return table.concat(H.printed, '\n') end
local function zoneIn(id) H.packetData(0x00A, ('\0'):rep(0x30) .. string.char(id % 256, math.floor(id / 256)) .. ('\0'):rep(0x80)) end
local store = H.options()
H.print('settings: the layers to begin with', type(store.zones) == 'table', next(store.zones) == nil, type(store.kinds) == 'table',
    '| cities and dungeons seeded with world x2', store.kinds.city.world == 2, store.kinds.dungeon.world == 2, next(store.kinds.outdoors) == nil, store.seeded == true)
H.command('/vis')
H.print('status before a zone: no zone known', said():find('No zone known yet', 1, true) ~= nil, said():find('All from the general values', 1, true) ~= nil)
H.print('/vis zone world 2 before a zone is refused', H.command('/vis zone world 2') == true, said():find('No zone known yet; try once', 1, true) ~= nil)
H.command('/vis world 3')
H.print('the general values', store.world == 3)
zoneIn(100)
H.command('/vis')
H.print('in 100, outdoors: the general values', said():find('In zone 100 (100), outdoors', 1, true) ~= nil, said():find('world x3.00', 1, true) ~= nil,
    said():find('All from the general values', 1, true) ~= nil)
zoneIn(230)
H.print('into 230, a city: said as it arrives', said():find('zone 230: the city preset world x2.00', 1, true) ~= nil)
H.command('/vis')
H.print('in 230: world x2 from the city preset', said():find('In zone 230 (230), a city', 1, true) ~= nil, said():find('world x2.00', 1, true) ~= nil,
    said():find('From the city preset: world x2.00', 1, true) ~= nil)
H.command('/vis world 4')
H.print('the general value set from a city stays beneath the preset', store.world == 4, said():find('world x2.00', 1, true) ~= nil, said():find('From the city preset: world x2.00', 1, true) ~= nil)
local savesBefore = H.saves()
H.print('/vis city world 1.5', H.command('/vis city world 1.5') == true, store.kinds.city.world == 1.5, H.saves() == savesBefore + 1,
    '| shown', said():find('The city preset: world x1.50; the rest from the general values', 1, true) ~= nil, said():find('world x1.50', 1, true) ~= nil)
local before = #H.printed
H.print('/vis dungeon terrain off from a city', H.command('/vis dungeon terrain off') == true, store.kinds.dungeon.terrain == false,
    said():find('The dungeon preset: world x2.00, terrain off', 1, true) ~= nil, '| not in force here, so no status', #H.printed == before + 1)
H.print('/vis outdoors alone shows it empty', H.command('/vis outdoors') == true, said():find('The outdoors preset holds nothing; the outdoors draws with the general values', 1, true) ~= nil)
H.print('/vis zone world 3 gives 230 its own', H.command('/vis zone world 3') == true, store.zones['230'] ~= nil and store.zones['230'].world == 3,
    said():find('From its own: world x3.00. From the city preset: world x1.50', 1, true) ~= nil, said():find('world x3.00', 1, true) ~= nil)
H.print('/vis zone terrain toggles from the value in force', H.command('/vis zone terrain') == true, store.zones['230'].terrain == false,
    said():find('From its own: world x3.00, terrain off', 1, true) ~= nil)
H.command('/vis zone list')
H.print('/vis zone list', said():find('zone 230 (230, a city): world x3.00, terrain off', 1, true) ~= nil)
H.print('/vis zone world clear takes one out', H.command('/vis zone world clear') == true, store.zones['230'].world == nil, store.zones['230'].terrain == false,
    said():find('From its own: terrain off. From the city preset: world x1.50', 1, true) ~= nil)
H.print('clearing the last one drops the set', H.command('/vis zone terrain clear') == true, store.zones['230'] == nil)
H.command('/vis zone world 3')
zoneIn(39)
H.print('into 39, a dungeon: its preset said', said():find('zone 39: the dungeon preset world x2.00, terrain off', 1, true) ~= nil)
H.command('/vis')
H.print('in 39: the dungeon preset over the general', said():find('In zone 39 (39), a dungeon', 1, true) ~= nil, said():find('world x2.00', 1, true) ~= nil, said():find('terrain off', 1, true) ~= nil,
    said():find('From the dungeon preset: world x2.00, terrain off', 1, true) ~= nil)
H.print('/vis dungeon clear empties it', H.command('/vis dungeon clear') == true, next(store.kinds.dungeon) == nil, said():find('The dungeon preset holds nothing; every dungeon draws with the general values', 1, true) ~= nil)
H.command('/vis')
H.print('then the general values apply in 39', said():find('world x4.00', 1, true) ~= nil, said():find('All from the general values', 1, true) ~= nil)
zoneIn(999)
H.command('/vis')
H.print('a zone of no known kind: the general values', said():find('In zone 999 (999), of no known kind', 1, true) ~= nil, said():find('world x4.00', 1, true) ~= nil)
zoneIn(230)
H.print('back in 230: its own and the preset said', said():find('zone 230: its own world x3.00; the city preset world x1.50', 1, true) ~= nil)
H.print('the same zone again is not re-entered', (function() local n = #H.printed zoneIn(230) return #H.printed == n end)())
H.print('/vis zone clear drops the set', H.command('/vis zone clear') == true, store.zones['230'] == nil, said():find('zone 230 has nothing of its own now', 1, true) ~= nil)
H.print('/vis zone clear with none is quiet about it', H.command('/vis zone clear') == true, store.zones['230'] == nil)
H.print('/vis zone list with none', H.command('/vis zone list') == true, said():find('No zone has values of its own', 1, true) ~= nil)
H.print('/vis zone sideways complains', H.command('/vis zone sideways') == true, said():find('Usage: /vis zone <setting>', 1, true) ~= nil)
H.print('/vis city sideways complains', H.command('/vis city sideways') == true, said():find('Usage: /vis city <setting>', 1, true) ~= nil)
H.print('/vis city world 200 refused', H.command('/vis city world 200') == true, said():find('Usage: /vis city world <n>, n from 0.1 to 100, or clear', 1, true) ~= nil, store.kinds.city.world == 1.5)
H.print('/vis world clear refused on the general values', H.command('/vis world clear') == true, said():find('Usage: /vis world <n>, n from 0.1 to 100.', 1, true) ~= nil, store.world == 4)
H.print('/vis zone alone is the status', H.command('/vis zone') == true, said():find('In zone 230 (230), a city', 1, true) ~= nil)
H.print('a short zone packet is ignored', (function() H.packetData(0x00A, 'abc') return true end)())
H.print('help names the layers', H.command('/vis help') == true, said():find('/vis city|outdoors|dungeon <setting> <value>', 1, true) ~= nil, said():find('/vis zone <setting> <value>', 1, true) ~= nil)

-- a saved file: a zone's set with a value out of range and one that is not a table, a preset
-- with a bad value, and seeded already so the presets are left as they are
store.zones = { ['230'] = { world = 4, entity = 'x', vis = 'yes', square = true }, ['231'] = { vis = false }, ['abc'] = { world = 2 }, ['5'] = 7 }
store.fov, store.square, store.vis, store.terrain = 93, true, false, nil
store.kinds = { city = {}, dungeon = { world = 300, fog = 0.5 }, outdoors = 'no' }
store.world = 1.5
H.resettle()
H.print('settled: fov and square said as lens commands', said():find('to keep yours: /lens fov 93, /lens square on. A zone\'s or preset\'s own fov or square is no more.', 1, true) ~= nil,
    '| and dropped', store.fov == nil, store.square == nil, store.zones['230'].square == nil)
H.print('settled: vis read as terrain', store.terrain == false, store.vis == nil, store.zones['231'].terrain == false, store.zones['231'].vis == nil,
    '| a bad one dropped all the same', store.zones['230'].vis == nil)
store.terrain = true
H.print('settled: the zone\'s set kept', store.zones['230'] ~= nil and store.zones['230'].world == 4, '| bad values dropped', store.zones['230'].entity == nil, store.zones['230'].terrain == nil,
    '| not a zone', store.zones['abc'] == nil, '| not a table', store.zones['5'] == nil,
    '| presets: the bad value dropped', store.kinds.dungeon.world == nil, store.kinds.dungeon.fog == 0.5, '| not reseeded', next(store.kinds.city) == nil, '| a preset that was not a table', type(store.kinds.outdoors) == 'table')
H.command('/vis')
H.print('after settling, in 230, its own apply', said():find('In zone 230 (230), a city', 1, true) ~= nil, said():find('world x4.00', 1, true) ~= nil)

-- terrain off by default from 2.2: a terrain on saved by 2.1 is turned off once, and said; one set after is kept
store.terrainOff, store.terrain = nil, true
local n = #H.printed
H.resettle()
local note = table.concat(H.printed, '\n', n + 1)
H.print('a 2.1 terrain on turned off', store.terrain == false, store.terrainOff == true, '| and said', note:find('terrain is off now, the default from vis 2.2', 1, true) ~= nil)
H.command('/vis terrain on')
n = #H.printed
H.resettle()
H.print('a terrain on set after stays on', store.terrain == true, '| and nothing said', table.concat(H.printed, '\n', n + 1):find('terrain is off now', 1, true) == nil)
store.terrainOff, store.terrain = nil, false
n = #H.printed
H.resettle()
H.print('a 2.1 terrain off is quiet', store.terrain == false, store.terrainOff == true, table.concat(H.printed, '\n', n + 1):find('terrain is off now', 1, true) == nil)
