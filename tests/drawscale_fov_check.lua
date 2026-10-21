-- drawscale fov: finds the instructions addressing the game object's fields near k (and not other
-- forms or offsets), the constants a function reads, the field of view a projection holds, and the
-- floats of a dump. Run from the repo root:
-- luajit tests/drawscale_fov_check.lua
package.path = 'addons/drawscale/?.lua;' .. package.path
local fov = require('fov')

local function check(label, ...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    print(label .. '\t' .. table.concat(parts, ' '))
    for i = 1, select('#', ...) do assert(select(i, ...) ~= false, label) end
end

local function near(a, b) return math.abs(a - b) < 1e-4 end

-- fmul dword [ecx+0x2E8]; fld dword [esi+0x2F0]; mov eax, [edx+0x2EC]; fld dword [esp+0x2E8] (SIB,
-- left out); fld dword [ecx+0x100] (out of range); fld dword [ecx+0x2E8] in the margin (left out)
local bytes = {
    0xD8, 0x89, 0xE8, 0x02, 0x00, 0x00,
    0xD9, 0x86, 0xF0, 0x02, 0x00, 0x00,
    0x8B, 0x82, 0xEC, 0x02, 0x00, 0x00,
    0xD9, 0x84, 0x24, 0xE8, 0x02, 0x00, 0x00,
    0xD9, 0x81, 0x00, 0x01, 0x00, 0x00,
    0xD9, 0x81, 0xE8, 0x02, 0x00, 0x00,
}
local refs = fov.fieldRefs(bytes, 0x1000, 31, fov.FIRST, fov.LAST)
check('three found', #refs == 3)
check('fmul k', refs[1].address == 0x1000, refs[1].opcode == 0xD8, refs[1].reg == 1, refs[1].offset == 0x2E8)
check('fld a', refs[2].address == 0x1006, refs[2].opcode == 0xD9, refs[2].reg == 0, refs[2].offset == 0x2F0)
check('mov beside', refs[3].address == 0x100C, refs[3].opcode == 0x8B, refs[3].offset == 0x2EC)

-- fld [esp+4]; fmul [0x00401000]; fmul [0x00401004]; fmul [0x00401000] again
local fn = { 0xD9, 0x44, 0x24, 0x04, 0xD8, 0x0D, 0x00, 0x10, 0x40, 0x00, 0xD8, 0x0D, 0x04, 0x10, 0x40, 0x00, 0xD8, 0x0D, 0x00, 0x10, 0x40, 0x00, 0xC3 }
local abs = fov.absoluteRefs(fn)
check('constants once each', #abs == 2, abs[1] == 0x00401000, abs[2] == 0x00401004)

-- a 90 degree vertical field of view at 16:9
local m22 = 1 / math.tan(math.rad(45))
local m11 = m22 * 9 / 16
local h, v = fov.fromProjection(m11, m22)
check('fov from the matrix', near(v, 90), near(h, math.deg(2 * math.atan(16 / 9))))
check('not a perspective', fov.fromProjection(0, 1) == nil, fov.fromProjection(nil, 1) == nil)

check('floats', fov.float(0x3F400000) == 0.75, near(fov.float(0x3F4A7EFA), 0.791), fov.float(0xBF800000) == -1, fov.float(0) == 0)
local lines = fov.fieldLines({ 0x00, 0x00, 0x40, 0x3F, 0, 0, 0, 0, 0, 0, 0x80, 0x3F, 0, 0, 0, 0, 0x00, 0x00, 0x00, 0x40 }, 0x2E8)
check('dump lines', #lines == 2, lines[1]:find('+0x2E8', 1, true) ~= nil, lines[1]:find('0.75', 1, true) ~= nil, lines[2]:find('+0x2F8', 1, true) ~= nil)

print('drawscale fov check passed')
