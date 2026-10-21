// lens mousescan: the cursor's place found in each of its four forms where aligned, kept only where
// it moved with the cursor, and the dwords pointing at or before a place.
#include <stdio.h>
#include "../src/mousescan.h"
static int failures = 0;
static void Check(bool ok, const char* text) { printf("%s %s\n", ok ? "ok" : "FAIL", text); if (!ok) ++failures; }

int main() {
    alignas(4) uint8_t mem[256] = {};
    const int x = 1234, y = 567, w = 3440, h = 1440;
    int32_t i32[2] = { x, y }; memcpy(mem + 16, i32, 8);
    int16_t i16[2] = { x, y }; memcpy(mem + 42, i16, 4);           // 2-aligned
    float f32[2] = { float(x), float(y) }; memcpy(mem + 64, f32, 8);
    float fr[2] = { float(x) / w, float(y) / h }; memcpy(mem + 96, fr, 8);
    memcpy(mem + 129, i32, 8);                                       // not aligned: not found
    const uintptr_t base = 0x400000;
    std::vector<lens::Candidate> found;
    lens::FindPairs(mem, sizeof(mem), sizeof(mem), base, x, y, w, h, found, 100);
    bool kinds = found.size() == 4 && found[0].address == base + 16 && found[0].kind == lens::I32 && found[1].address == base + 42 && found[1].kind == lens::I16
        && found[2].address == base + 64 && found[2].kind == lens::F32 && found[3].address == base + 96 && found[3].kind == lens::Fraction;
    Check(kinds, "each form found where aligned, the unaligned one not");

    // the cursor moves: the int32 and the fraction follow it, the others stay
    const int x2 = 2000, y2 = 300;
    int32_t moved[2] = { x2, y2 }; memcpy(mem + 16, moved, 8);
    float fr2[2] = { float(x2) / w, float(y2) / h }; memcpy(mem + 96, fr2, 8);
    lens::KeepPairs(found, [&](uintptr_t a, void* b, size_t n) { memcpy(b, mem + (a - base), n); return true; }, x2, y2, w, h);
    Check(found.size() == 2 && found[0].address == base + 16 && found[1].address == base + 96, "kept only where it moved with the cursor");

    uint32_t pointer = base + 16 - 8; memcpy(mem + 200, &pointer, 4);
    std::vector<uintptr_t> refs;
    lens::FindDwords(mem, sizeof(mem), base, base + 16 - 0x40, base + 16, refs, 10);
    Check(refs.size() == 1 && refs[0] == base + 200, "a dword pointing just before the place");
    printf(failures ? "%d FAILED\n" : "lens mousescan: all checks passed\n", failures);
    return failures ? 1 : 0;
}
