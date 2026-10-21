-- Looking for the field of view. Every world projection is built with aspect = 1 / (a * k), a at the
-- game object's +0x2F0 (the aspect addon writes it) and k at +0x2E8 (view.lua's square), so the code
-- that builds the projection reads those fields, and the field of view goes in beside them. This
-- module finds the x87 and mov instructions in the client that address the game object's fields
-- near them, the absolute constants an instruction reads, and the field of view a projection matrix
-- holds. Pure: works on tables of bytes, so the check can drive it without the game; the addon
-- writes what it finds to config/addons/drawscale/fov.txt for reading outside the game.
local M = {}

local floor = math.floor

-- The fields looked for, as offsets in the game object: k and a with their neighbours either side.
M.FIRST = 0x2D0
M.LAST = 0x300

-- The aspect addon's pattern: mov eax, [gGame]; test eax, eax; jz; fld [esp+4]; fmul [c]; fmul [c].
-- The function it lies in reads the game object, and xicamera patches the second constant as the
-- camera's least distance.
M.ASPECT_PATTERN = 'A1????????85C074??D9442404D80D????????D80D'

-- The opcodes whose ModRM operand is worth a look: x87 single and double, and mov to and from.
local OPCODES = { [0xD8] = 'x87', [0xD9] = 'x87', [0xDC] = 'x87', [0xDD] = 'x87', [0x8B] = 'mov', [0x89] = 'mov', [0xC7] = 'mov' }

local function u32(bytes, i)
    return bytes[i] + bytes[i + 1] * 256 + bytes[i + 2] * 65536 + bytes[i + 3] * 16777216
end

-- The instructions in bytes (bytes[1] at address base; count of them to scan, the rest a margin)
-- addressing [reg+disp32] with disp32 from first to last: { address, opcode, offset, reg }, reg being
-- the ModRM reg field (for x87 the operation, for mov the register). Only the simple form, a base
-- register and no SIB, which is how the client reaches an object's fields.
function M.fieldRefs(bytes, base, count, first, last)
    local out = {}
    for i = 1, count do
        local kind = OPCODES[bytes[i]]
        local modrm = bytes[i + 1]
        if kind and modrm and bytes[i + 5] then
            local mod, rm = floor(modrm / 64), modrm % 8
            if mod == 2 and rm ~= 4 then
                local disp = u32(bytes, i + 2)
                if disp >= first and disp <= last then
                    out[#out + 1] = { address = base + i - 1, opcode = bytes[i], offset = disp, reg = floor(modrm / 8) % 8 }
                end
            end
        end
    end
    return out
end

-- The absolute addresses the x87 instructions in bytes read ([disp32], mod 0 and rm 5): the
-- constants a function multiplies by. Each address once, in the order first seen.
function M.absoluteRefs(bytes)
    local out, seen = {}, {}
    for i = 1, #bytes - 5 do
        local op, modrm = bytes[i], bytes[i + 1]
        if (op == 0xD8 or op == 0xD9 or op == 0xDC or op == 0xDD) and modrm and floor(modrm / 64) == 0 and modrm % 8 == 5 then
            local addr = u32(bytes, i + 2)
            if not seen[addr] then
                seen[addr] = true
                out[#out + 1] = addr
            end
        end
    end
    return out
end

-- The horizontal and vertical fields of view a projection holds, in degrees: m11 and m22 are the
-- cotangents of half of each. nil for a matrix that is not a perspective one.
function M.fromProjection(m11, m22)
    if type(m11) ~= 'number' or type(m22) ~= 'number' or m11 <= 0 or m22 <= 0 then return nil end
    return math.deg(2 * math.atan(1 / m11)), math.deg(2 * math.atan(1 / m22))
end

-- The 32-bit float whose bits are v.
function M.float(v)
    local sign = v >= 2147483648 and -1 or 1
    local exp = floor(v / 8388608) % 256
    local frac = v % 8388608
    if exp == 255 then return frac == 0 and sign * math.huge or 0 / 0 end
    if exp == 0 then return sign * frac * 2 ^ -149 end
    return sign * (1 + frac / 8388608) * 2 ^ (exp - 127)
end

-- The fields in a dump of the game object (bytes[1] at offset from) as lines of four floats, with
-- the raw dword beside each, so a value that is not a float can still be read.
function M.fieldLines(bytes, from)
    local out = {}
    for i = 1, #bytes - 3, 16 do
        local parts = {}
        for j = i, math.min(i + 12, #bytes - 3), 4 do
            parts[#parts + 1] = ('+0x%03X %12.6g (%08X)'):format(from + j - 1, M.float(u32(bytes, j)), u32(bytes, j))
        end
        out[#out + 1] = table.concat(parts, '  ')
    end
    return out
end

return M
