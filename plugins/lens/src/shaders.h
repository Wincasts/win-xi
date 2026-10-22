// The pixel shaders the grid is drawn with when it averages four taps (warp.h Taps): ps_1_1, written
// out as tokens since there is no assembler for Direct3D 8 here. Each samples the world's texture at
// the four coordinate sets and averages them with _d2 (half the sum) twice, which stays inside the
// range ps_1_1 keeps between instructions on any card. tests/shaders.cpp assembles the same text with
// Wine's d3dx9 and checks the tokens against these.
#pragma once
#include <stdint.h>

namespace lens {

// ps_1_1
// tex t0
// tex t1
// tex t2
// tex t3
// add_d2 r0, t0, t1
// add_d2 r1, t2, t3
// add_d2 r0, r0, r1
static const uint32_t AverageShader[] = {
    0xFFFF0101,
    0x00000042, 0xB00F0000,
    0x00000042, 0xB00F0001,
    0x00000042, 0xB00F0002,
    0x00000042, 0xB00F0003,
    0x00000002, 0x8F0F0000, 0xB0E40000, 0xB0E40001,
    0x00000002, 0x8F0F0001, 0xB0E40002, 0xB0E40003,
    0x00000002, 0x8F0F0000, 0x80E40000, 0x80E40001,
    0x0000FFFF,
};

// The same, then mul r0, r0, v0: for a copy whose texture is modulated by its vertices' colour.
static const uint32_t AverageModulateShader[] = {
    0xFFFF0101,
    0x00000042, 0xB00F0000,
    0x00000042, 0xB00F0001,
    0x00000042, 0xB00F0002,
    0x00000042, 0xB00F0003,
    0x00000002, 0x8F0F0000, 0xB0E40000, 0xB0E40001,
    0x00000002, 0x8F0F0001, 0xB0E40002, 0xB0E40003,
    0x00000002, 0x8F0F0000, 0x80E40000, 0x80E40001,
    0x00000005, 0x800F0000, 0x80E40000, 0x90E40000,
    0x0000FFFF,
};

} // namespace lens
