-- The client's draw-distance scale function, seen from outside: who calls it, what each caller hands
-- it and does with the answer, and a stub that re-scales one caller's answer. Pure: works on tables
-- of bytes and addresses, so the check can drive it without the game.
--
-- The function (found by the bytes 8B C1 48 74 08 D8 0D, as the drawdistance addon finds it) takes a
-- distance on the stack and a selector in ecx (1: the entity multiplier, anything else: the world
-- multiplier), answers in st(0) and does ret 4. Everything that scales with the draw distance (the far
-- clip, the fog, the zone-object ranges, the entity cull) goes through it.
local M = {}

local floor = math.floor

local function u32(v) return v % 4294967296 end

-- The bytes of v, lowest first.
function M.le32(v)
    v = u32(v)
    return { v % 256, floor(v / 256) % 256, floor(v / 65536) % 256, floor(v / 16777216) % 256 }
end

-- The rel32 of a 5-byte call at from reaching to.
function M.rel32(from, to) return M.le32(to - (from + 5)) end

-- A signed 32-bit value read at i (1-based) of bytes.
function M.readInt32(bytes, i)
    local v = bytes[i] + bytes[i + 1] * 256 + bytes[i + 2] * 65536 + bytes[i + 3] * 16777216
    if v >= 2147483648 then v = v - 4294967296 end
    return v
end

function M.readUInt32(bytes, i)
    return bytes[i] + bytes[i + 1] * 256 + bytes[i + 2] * 65536 + bytes[i + 3] * 16777216
end

-- The 5-byte calls in bytes (bytes[1] at address base; count of them to scan, the rest a margin) whose
-- target is within reach bytes before target or target itself: { address, delta }, delta being how
-- far before target the call lands (0 when exact). The margin lets a call that begins in the last
-- bytes scanned still be read whole.
function M.callers(bytes, base, target, count, reach)
    reach = reach or 0
    local found = {}
    for i = 1, count or #bytes do
        if bytes[i] == 0xE8 and bytes[i + 4] ~= nil then
            local site = base + i - 1
            local to = u32(site + 5 + M.readInt32(bytes, i + 1))
            local delta = u32(target) - to
            if delta >= 0 and delta <= reach then
                found[#found + 1] = { address = site, delta = delta }
            end
        end
    end
    return found
end

-- Hex of bytes[from..to], spaced.
function M.hex(bytes, from, to)
    local out = {}
    for i = from, to do
        if bytes[i] == nil then break end
        out[#out + 1] = ('%02X'):format(bytes[i])
    end
    return table.concat(out, ' ')
end

local regs = { 'eax', 'ecx', 'edx', 'ebx', 'esp', 'ebp', 'esi', 'edi' }

local function signed8(b) return b >= 128 and b - 256 or b end

local function dispText(d)
    if d == 0 then return '' end
    if d < 0 then return ('-0x%X'):format(-d) end
    return ('+0x%X'):format(d)
end

-- A ModRM operand at i: its text, its length (ModRM, SIB and displacement), the reg field, and
-- whether it is memory. nil when the bytes run out.
function M.modrm(bytes, i)
    local b = bytes[i]
    if b == nil then return nil end
    local mod, reg, rm = floor(b / 64), floor(b / 8) % 8, b % 8
    if mod == 3 then return regs[rm + 1], 1, reg, false end
    local len, base, index, scale = 1, nil, nil, 1
    if rm == 4 then
        local sib = bytes[i + 1]
        if sib == nil then return nil end
        len = 2
        scale, index, base = 2 ^ floor(sib / 64), floor(sib / 8) % 8, sib % 8
        if index == 4 then index = nil end
        if base == 5 and mod == 0 then base = nil else base = regs[base + 1] end
    elseif not (mod == 0 and rm == 5) then
        base = regs[rm + 1]
    end
    local disp = 0
    if mod == 1 then
        if bytes[i + len] == nil then return nil end
        disp = signed8(bytes[i + len])
        len = len + 1
    elseif mod == 2 or (mod == 0 and base == nil) then
        if bytes[i + len + 3] == nil then return nil end
        disp = M.readInt32(bytes, i + len)
        len = len + 4
    end
    local parts = {}
    if base then parts[#parts + 1] = base end
    if index then parts[#parts + 1] = regs[index + 1] .. (scale > 1 and ('*' .. scale) or '') end
    local text
    if #parts == 0 then
        text = ('[0x%08X]'):format(u32(disp))
    else
        text = '[' .. table.concat(parts, '+') .. dispText(disp) .. ']'
    end
    return text, len, reg, true
end

local x87d8 = { 'fadd', 'fmul', 'fcom', 'fcomp', 'fsub', 'fsubr', 'fdiv', 'fdivr' }
local x87d9 = { [0] = 'fld', [2] = 'fst', [3] = 'fstp', [5] = 'fldcw', [7] = 'fnstcw' }
local x87dd = { [0] = 'fld qword', [2] = 'fst qword', [3] = 'fstp qword' }
local x87dc = { 'fadd qword', 'fmul qword', 'fcom qword', 'fcomp qword', 'fsub qword', 'fsubr qword', 'fdiv qword', 'fdivr qword' }
local x87d9reg = { [0xC0] = 'fld st(%d)', [0xC8] = 'fxch st(%d)' }
local x87d9one = { [0xE0] = 'fchs', [0xE1] = 'fabs', [0xE8] = 'fld1', [0xEE] = 'fldz', [0xC9] = 'fxch', [0xE4] = 'ftst', [0xE5] = 'fxam' }
local x87de = { [0xC1] = 'faddp', [0xC9] = 'fmulp', [0xD9] = 'fcompp', [0xE9] = 'fsubp', [0xE1] = 'fsubrp', [0xF9] = 'fdivp', [0xF1] = 'fdivrp' }

-- The instruction beginning at i, as text and length, for the forms that matter around a call to the
-- scale function; nil for anything else.
function M.decode(bytes, i)
    local b = bytes[i]
    if b == nil then return nil end
    local b2 = bytes[i + 1]
    -- pushes
    if b >= 0x50 and b <= 0x57 then return 'push ' .. regs[b - 0x50 + 1], 1 end
    if b >= 0x58 and b <= 0x5F then return 'pop ' .. regs[b - 0x58 + 1], 1 end
    if b == 0x68 and bytes[i + 4] then
        local v = M.readUInt32(bytes, i + 1)
        return ('push 0x%08X'):format(v), 5
    end
    if b == 0x6A and b2 then return ('push %d'):format(signed8(b2)), 2 end
    if b == 0xFF and b2 then
        local text, len, reg = M.modrm(bytes, i + 1)
        if text and reg == 6 then return 'push dword ' .. text, 1 + len end
        if text and reg == 2 then return 'call ' .. text, 1 + len end
    end
    -- mov r32, r/m32 and mov r/m32, r32
    if b == 0x8B and b2 then
        local text, len, reg = M.modrm(bytes, i + 1)
        if text then return ('mov %s, %s'):format(regs[reg + 1], text), 1 + len end
    end
    if b == 0x89 and b2 then
        local text, len, reg = M.modrm(bytes, i + 1)
        if text then return ('mov %s, %s'):format(text, regs[reg + 1]), 1 + len end
    end
    if b >= 0xB8 and b <= 0xBF and bytes[i + 4] then
        return ('mov %s, 0x%X'):format(regs[b - 0xB8 + 1], M.readUInt32(bytes, i + 1)), 5
    end
    if (b == 0x33 or b == 0x31) and b2 then
        local text, len, reg = M.modrm(bytes, i + 1)
        if text then return ('xor %s, %s'):format(b == 0x33 and regs[reg + 1] or text, b == 0x33 and text or regs[reg + 1]), 1 + len end
    end
    if b == 0x85 and b2 then
        local text, len, reg = M.modrm(bytes, i + 1)
        if text then return ('test %s, %s'):format(text, regs[reg + 1]), 1 + len end
    end
    if b == 0x83 and b2 and bytes[i + 2] then
        local text, len, reg = M.modrm(bytes, i + 1)
        local ops = { 'add', 'or', 'adc', 'sbb', 'and', 'sub', 'xor', 'cmp' }
        if text then return ('%s %s, %d'):format(ops[reg + 1], text, signed8(bytes[i + 1 + len])), 1 + len + 1 end
    end
    if b == 0xE8 and bytes[i + 4] then return ('call 0x%08X'):format(0), 5 end -- the caller fills the target in
    if b == 0xC3 then return 'ret', 1 end
    if b == 0xC2 and bytes[i + 2] then return ('ret %d'):format(b2 + bytes[i + 2] * 256), 3 end
    if b == 0xEB and b2 then return ('jmp short %+d'):format(signed8(b2)), 2 end
    if b == 0x74 and b2 then return ('jz short %+d'):format(signed8(b2)), 2 end
    if b == 0x75 and b2 then return ('jnz short %+d'):format(signed8(b2)), 2 end
    if b == 0x9E then return 'sahf', 1 end
    -- x87
    if b == 0xD8 and b2 then
        if b2 >= 0xC0 then return ('%s st, st(%d)'):format(x87d8[floor((b2 - 0xC0) / 8) + 1], b2 % 8), 2 end
        local text, len, reg = M.modrm(bytes, i + 1)
        if text then return ('%s dword %s'):format(x87d8[reg + 1], text), 1 + len end
    end
    if b == 0xD9 and b2 then
        if b2 >= 0xC0 then
            if x87d9one[b2] then return x87d9one[b2], 2 end
            local form = x87d9reg[b2 - b2 % 8]
            if form then return form:format(b2 % 8), 2 end
            return ('x87 D9 %02X'):format(b2), 2
        end
        local text, len, reg = M.modrm(bytes, i + 1)
        if text and x87d9[reg] then return ('%s dword %s'):format(x87d9[reg], text), 1 + len end
    end
    if b == 0xDD and b2 then
        if b2 >= 0xD8 and b2 <= 0xDF then return ('fstp st(%d)'):format(b2 - 0xD8), 2 end
        if b2 >= 0xC0 and b2 <= 0xC7 then return ('ffree st(%d)'):format(b2 - 0xC0), 2 end
        local text, len, reg = M.modrm(bytes, i + 1)
        if text and x87dd[reg] then return ('%s %s'):format(x87dd[reg], text), 1 + len end
    end
    if b == 0xDC and b2 then
        if b2 >= 0xC0 then return ('%s st(%d), st'):format(x87d8[floor((b2 - 0xC0) / 8) + 1], b2 % 8), 2 end
        local text, len, reg = M.modrm(bytes, i + 1)
        if text then return ('%s %s'):format(x87dc[reg + 1], text), 1 + len end
    end
    if b == 0xDE and b2 and x87de[b2] then return x87de[b2], 2 end
    if b == 0xDE and b2 and b2 >= 0xC0 then return ('x87 DE %02X'):format(b2), 2 end
    if b == 0xDF and b2 == 0xE0 then return 'fnstsw ax', 2 end
    if b == 0xDA and b2 and b2 >= 0xE8 and b2 <= 0xEF then return ('fucomi st, st(%d)'):format(b2 - 0xE8), 2 end
    if b == 0xDB and b2 and b2 >= 0xE8 and b2 <= 0xEF then return ('fucomip st, st(%d)'):format(b2 - 0xE8), 2 end
    if b == 0xDB and b2 and b2 >= 0xF0 and b2 <= 0xF7 then return ('fcomip st, st(%d)'):format(b2 - 0xF0), 2 end
    return nil
end

-- Up to count instructions beginning at i, as text, stopping at the first unknown.
function M.forward(bytes, i, count)
    local out = {}
    while #out < count do
        local text, len = M.decode(bytes, i)
        if text == nil then break end
        if bytes[i] == 0xE8 then
            local target = u32((i - 1) + 5 + M.readInt32(bytes, i + 1)) -- relative to bytes[1] at 0
            text = ('call (bytes[1]+0x%X)'):format(target)
        end
        out[#out + 1] = text
        i = i + len
    end
    return out
end

-- Up to count instructions ending exactly at last (the byte before a call), found by trying every
-- length that decodes to an instruction of that length, nearest first; stops at the first position
-- where nothing fits. A heuristic: bytes can decode more than one way, which is why the raw hex is
-- shown beside it.
function M.backward(bytes, last, count)
    local out = {}
    local stop = last
    while #out < count and stop >= 1 do
        local hit, hitLen
        for len = 1, 7 do
            local start = stop - len + 1
            if start < 1 then break end
            local text, decodedLen = M.decode(bytes, start)
            if text and decodedLen == len then hit, hitLen = text, len; break end
        end
        if hit == nil then break end
        table.insert(out, 1, hit)
        stop = stop - hitLen
    end
    return out
end

-- What a caller does: the instructions before and after it, and the selector in ecx when it can be
-- read (1 is the entity multiplier, anything else the world one), the operand pushed, and where the
-- answer goes first. before: the bytes preceding the call (before[#before] is the byte just before
-- it); after: the bytes following it.
function M.describe(before, after)
    local pre = M.backward(before, #before, 3)
    local post = M.forward(after, 1, 3)
    local ecx, push, sink
    for _, text in ipairs(pre) do
        local v = text:match('^mov ecx, 0x(%x+)$')
        if v then ecx = tonumber(v, 16) end
        if text == 'xor ecx, ecx' then ecx = 0 end
        if text:match('^mov ecx, ') and not v then ecx = text:sub(10) end
        if text:match('^push ') then push = text:sub(6) end
    end
    for _, text in ipairs(post) do
        if sink == nil and (text:match('^fstp ') or text:match('^fst ') or text:match('^fmul ') or text:match('^fadd ')
            or text:match('^fcomp ') or text:match('^fcom ') or text:match('^fsub') or text:match('^fdiv')) then
            sink = text
        end
    end
    local selector
    if ecx == 1 then selector = 'entity'
    elseif type(ecx) == 'number' then selector = 'world'
    elseif type(ecx) == 'string' then selector = 'from ' .. ecx
    else selector = 'unknown' end
    return { before = pre, after = post, ecx = ecx, selector = selector, push = push, sink = sink }
end

-- The stub a patched caller is sent through instead of the scale function: it calls the function
-- with the same operand and multiplies the answer by the float at stub+24, so the caller sees
-- distance x stock scale x (ratio / world). 18 bytes of code; the float lives at +24.
--
--     push dword [esp+4]      FF 74 24 04
--     call target             E8 rel32 (from stub+4)
--     fmul dword [stub+24]    D8 0D imm32
--     ret 4                   C2 04 00
function M.stub(stub, target)
    local rel = M.rel32(stub + 4, target)
    local ratio = M.le32(stub + M.RATIO_OFFSET)
    return {
        0xFF, 0x74, 0x24, 0x04,
        0xE8, rel[1], rel[2], rel[3], rel[4],
        0xD8, 0x0D, ratio[1], ratio[2], ratio[3], ratio[4],
        0xC2, 0x04, 0x00,
    }
end

M.RATIO_OFFSET = 24
M.STUB_SIZE = 32

-- The ratio that leaves a caller at mult times stock when the world multiplier is world.
function M.ratio(mult, world)
    if world == nil or world == 0 then return mult end
    return mult / world
end

return M
