-- drawscale: finds the calls to the scale function in a run of bytes, reads what each caller does,
-- builds the stub that re-scales one, and in the game's absence says so and still answers commands
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
H.print('/drawscale help is taken', H.command('/drawscale help') == true, '| and lists the commands', table.concat(H.printed, '\n'):find('/drawscale patch <n> <mult>', 1, true) ~= nil)
H.print('/drawscale patch without a number complains', H.command('/drawscale patch') == true, table.concat(H.printed, '\n'):find('Usage: /drawscale patch', 1, true) ~= nil)
H.print('/drawscale unpatch 3 with nothing patched', H.command('/drawscale unpatch 3') == true, table.concat(H.printed, '\n'):find('#3 was not patched', 1, true) ~= nil)
H.print('another command is left alone', H.command('/other') == false)
H.unload()
H.print('unloads cleanly', true)
-- the selector is what is pushed: push 1 is the entity multiplier, push 0 the world one, whatever ecx holds
H.print('a pushed selector: 1 is entity', scan.describe({ 0x8B, 0xCE, 0x6A, 0x01, 0x89, 0x17 }, {}).selector == 'entity',
    '| 0 is world', scan.describe({ 0x8B, 0xCE, 0x6A, 0x00, 0x89, 0x17 }, {}).selector == 'world',
    '| ecx alone is only a hint', scan.describe({ 0x8B, 0xCE }, {}).selector == 'from esi')
