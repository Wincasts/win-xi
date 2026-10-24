// The game's projection, changed where it is built: its field of view (fov, middle) and its aspect constant
// (square), moved here from drawscale 1.9 so that the warp and the view it bends are set in one place. Pure:
// byte spans and numbers, so the check can run it.
//
// Field of view. Every world projection is built (as seen in the game on 2026-10-21) from the game object's
// fields: aspect = 1 / (a * k), the vertical field of view 2 * atan(C / f), C a double constant (192) and f the
// focal length at +0x2F4 (242 in play, more for a closer view), then D3DXMatrixPerspectiveFovLH. Four places
// build one, each loading C with fld qword [C] just before f and fpatan. Writing f did not hold, so it is C that
// is changed: those loads are pointed at a double of lens's own, 242 * tan(fov / 2), which puts the usual view at
// the field of view asked for and the game's closer views closer by as much. Another load of C (a fixed view of
// its own, a constant in place of f) is left alone. C's address is read from the one build function found by
// its bytes (BuildPattern), as drawscale did.
//
// Square pixels. aspect = 1 / (a * k), a from the window and k a constant 0.791 at +0x2E8 in the game object,
// which leaves the 3D picture about 5.5% wider than true; at 0.75 the aspect is the window's exactly. The game
// object is reached through a global, read out of mov eax, [gGame]; add eax, 0x94; ret (GamePattern), and is 0
// until the game object exists.
//
// Middle. A stronger warp shows less up and down the middle than the world is drawn with (warp.h MiddleHeight);
// MiddleFov finds the field of view that gives back a chosen angle there, for the mode, strength and the
// picture's proportions.
#pragma once
#include <math.h>
#include <stdint.h>
#include <string.h>
#include <vector>
#include "warp.h"

namespace lens {

// mov ecx, [gGame]; jmp +5; five nops; push esi; mov esi, ecx; push edi; fld [esi+0x2F0]; fmul [esi+0x2E8];
// mov eax, [esi+0x2E0]; mov ecx, [esi+0x2DC]; push eax; push ecx; fdivr [one]; sub esp, 8;
// lea edi, [esi+0x154]; fstp [esp+4]; fld qword [C]; fld [esi+0x2F4]; fpatan
static const char BuildPattern[] = "8B0D????????E9050000009090909090568BF157D986F0020000D88EE80200008B86E00200008B8EDC0200005051D83D????????83EC088DBE54010000D95C2404DD05????????D986F4020000D9F3";
static const size_t CAt = 0x43;   // where C's address sits, from the build function's start
// mov eax, [gGame]; add eax, 0x94; ret
static const char GamePattern[] = "A1????????0594000000C3";
static const size_t KOffset = 0x2E8;
static const uint32_t KStock = 0x3F4A7EFA, KSquare = 0x3F400000;   // 0.791 and 0.75 as a float's bits
static const double FocalNormal = 242;
static const int FovMin = 20, FovMax = 140;

inline int HexDigit(char c) { return c >= '0' && c <= '9' ? c - '0' : c >= 'A' && c <= 'F' ? c - 'A' + 10 : c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1; }

// A pattern of hex pairs, ?? for any byte, as bytes and a mask.
struct Pattern {
    std::vector<uint8_t> bytes;
    std::vector<bool> any;
    explicit Pattern(const char* text) {
        for (size_t i = 0; text[i] && text[i + 1]; i += 2) {
            bool wild = text[i] == '?';
            bytes.push_back(wild ? 0 : static_cast<uint8_t>(HexDigit(text[i]) * 16 + HexDigit(text[i + 1])));
            any.push_back(wild);
        }
    }
};

// The offset of the first match of p in bytes[0..size), or -1.
inline ptrdiff_t Find(const uint8_t* bytes, size_t size, const Pattern& p) {
    const size_t n = p.bytes.size();
    if (n == 0 || size < n) return -1;
    for (size_t i = 0; i + n <= size; ++i) {
        if (bytes[i] != p.bytes[0] && !p.any[0]) continue;
        size_t j = 1;
        while (j < n && (p.any[j] || bytes[i + j] == p.bytes[j])) ++j;
        if (j == n) return static_cast<ptrdiff_t>(i);
    }
    return -1;
}

inline uint32_t U32(const uint8_t* b) { uint32_t v; memcpy(&v, b, 4); return v; }

// The loads of C at cAddr in bytes (bytes[0] at address base) that a projection's field of view is made from:
// fld qword [C] followed by the load of f, from an object (fld dword [reg+0x2F4], reg not esp) or the stack
// (fld dword [esp+d8]), and fpatan. Each the address of its fld qword, whose operand is 2 bytes in.
inline void FovSites(const uint8_t* bytes, size_t size, uintptr_t base, uint32_t cAddr, std::vector<uintptr_t>& out) {
    for (size_t i = 0; i + 14 <= size; ++i) {
        if (bytes[i] != 0xDD || bytes[i + 1] != 0x05 || U32(bytes + i + 2) != cAddr || bytes[i + 6] != 0xD9) continue;
        const uint8_t m = bytes[i + 7];
        bool fromObject = m >= 0x80 && m <= 0x87 && m != 0x84 && U32(bytes + i + 8) == 0x2F4 && bytes[i + 12] == 0xD9 && bytes[i + 13] == 0xF3;
        bool fromStack = m == 0x44 && bytes[i + 8] == 0x24 && bytes[i + 10] == 0xD9 && bytes[i + 11] == 0xF3;
        if (fromObject || fromStack) out.push_back(base + i);
    }
}

// The C that puts the usual view (f of 242) at a vertical field of view of degrees, and back.
inline double CFor(double degrees) { return FocalNormal * tan(degrees * 3.14159265358979323846 / 360); }
inline double FovOf(double c) { return 2 * atan(c / FocalNormal) * 180 / 3.14159265358979323846; }

// What the screen shows up the middle, in degrees, of a picture drawn fov degrees up at the proportions aspect
// (tanH / tanV), through the warp at mode and strength (0 to 1).
inline double MiddleOf(double fov, double aspect, Mode mode, double strength) {
    const double tanV = tan(fov * 3.14159265358979323846 / 360);
    return 2 * atan(tanV * MiddleHeight(aspect * tanV, tanV, mode, strength)) * 180 / 3.14159265358979323846;
}

// The vertical field of view, from FovMin to FovMax, whose middle through the warp is middle degrees: the
// narrowest that reaches it, by steps of half a degree and then halving between the two either side. A full
// cylindrical warp's middle stops growing and shrinks as the field of view widens, so it is the first that
// reaches, not any. capped says that none does, and the answer is then the one showing the most.
inline double MiddleFov(double middle, double aspect, Mode mode, double strength, bool& capped) {
    capped = false;
    double best = FovMin, bestMiddle = -1, last = FovMin;
    for (double fov = FovMin; fov <= FovMax + 1e-9; fov += 0.5) {
        double m = MiddleOf(fov, aspect, mode, strength);
        if (m >= middle) {
            if (fov == FovMin) return FovMin;
            double lo = last, hi = fov;
            for (int i = 0; i < 40; ++i) {
                double mid = (lo + hi) / 2;
                if (MiddleOf(mid, aspect, mode, strength) < middle) lo = mid; else hi = mid;
            }
            return hi;
        }
        if (m > bestMiddle) { bestMiddle = m; best = fov; }
        last = fov;
    }
    capped = true;
    return best;
}

} // namespace lens
