// Finding where the game keeps the mouse, so that the place it picks things in the world by can be
// moved through the warp while its menus keep theirs. The cursor's place in the window is looked for
// in memory as a pair, x then y, in four forms (32-bit and 16-bit integers, floats, and floats as a
// fraction of the window); a second look with the cursor elsewhere keeps only the places that moved
// with it, as a memory scanner does. Then the code that reads what is left. Pure: works on bytes.
#pragma once
#include <math.h>
#include <stdint.h>
#include <string.h>
#include <vector>

namespace lens {

enum PairKind : uint8_t { I32, I16, F32, Fraction };
static const char* const PairKindNames[] = { "int32", "int16", "float", "fraction" };

struct Candidate { uintptr_t address; uint8_t kind; };

// Whether the bytes at p hold the pair (x, y) in the given form; width and height for a fraction.
inline bool Holds(const uint8_t* p, uint8_t kind, int x, int y, int width, int height) {
    switch (kind) {
    case I32: { int32_t v[2]; memcpy(v, p, 8); return v[0] == x && v[1] == y; }
    case I16: { int16_t v[2]; memcpy(v, p, 4); return v[0] == x && v[1] == y; }
    case F32: { float v[2]; memcpy(v, p, 8); return v[0] == float(x) && v[1] == float(y); }
    case Fraction: {
        if (width <= 0 || height <= 0) return false;
        float v[2]; memcpy(v, p, 8);
        return fabsf(v[0] - float(x) / width) < 1e-4f && fabsf(v[1] - float(y) / height) < 1e-4f;
    }
    }
    return false;
}

inline size_t PairSize(uint8_t kind) { return kind == I16 ? 4 : 8; }

// Every place in bytes (base its address, count of them to scan; the pair may run past count into
// the margin) holding the pair, 2-aligned for 16-bit, 4-aligned otherwise, until out holds cap.
// A pair of zeros or of equal small values is too common to be worth anything, so (x, y) should not be.
inline void FindPairs(const uint8_t* bytes, size_t count, size_t size, uintptr_t base, int x, int y, int width, int height,
                      std::vector<Candidate>& out, size_t cap) {
    for (size_t i = 0; i < count && out.size() < cap; i += 2) {
        uintptr_t at = base + i;
        for (uint8_t kind = I32; kind <= Fraction; ++kind) {
            if (kind != I16 && (at & 3)) continue;
            if (i + PairSize(kind) > size) continue;
            if (Holds(bytes + i, kind, x, y, width, height)) out.push_back({ at, kind });
        }
    }
}

// The candidates still holding the pair now, read through read(address, buffer, size) -> bool.
template <class Read>
inline void KeepPairs(std::vector<Candidate>& candidates, Read read, int x, int y, int width, int height) {
    size_t kept = 0;
    for (const Candidate& c : candidates) {
        uint8_t buffer[8];
        if (read(c.address, buffer, PairSize(c.kind)) && Holds(buffer, c.kind, x, y, width, height)) candidates[kept++] = c;
    }
    candidates.resize(kept);
}

// The places in an image (base its address) holding a 32-bit value from low to high: as an absolute
// operand of an instruction reading a global, or a pointer to an object the value lies in.
inline void FindDwords(const uint8_t* image, size_t size, uintptr_t base, uint32_t low, uint32_t high, std::vector<uintptr_t>& out, size_t cap) {
    for (size_t i = 0; i + 4 <= size && out.size() < cap; ++i) {
        uint32_t v;
        memcpy(&v, image + i, 4);
        if (v >= low && v <= high) out.push_back(base + i);
    }
}

} // namespace lens
