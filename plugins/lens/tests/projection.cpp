// lens projection: the patterns found with wildcards, the loads of C found in both forms and others left out,
// C for a field of view and back, and the field of view that keeps a middle through the warp: the README's
// settings at 3440x1440, flat being the middle itself, and a middle beyond reach capped.
#include <stdio.h>
#include "../src/projection.h"
static int failures = 0;
static void Check(bool ok, const char* text) { printf("%s %s\n", ok ? "ok" : "FAIL", text); if (!ok) ++failures; }
static bool Near(double a, double b, double e) { return fabs(a - b) < e; }
static void Put(std::vector<uint8_t>& b, size_t at, const char* hex) {
    for (size_t i = 0; hex[i] && hex[i + 1]; i += 2) b[at + i / 2] = static_cast<uint8_t>(lens::HexDigit(hex[i]) * 16 + lens::HexDigit(hex[i + 1]));
}
static void Put32(std::vector<uint8_t>& b, size_t at, uint32_t v) { memcpy(&b[at], &v, 4); }

int main() {
    std::vector<uint8_t> code(0x400, 0x90);
    Put(code, 0x40, "A1112233440594000000C3");
    const lens::Pattern game(lens::GamePattern);
    Check(lens::Find(code.data(), code.size(), game) == 0x40, "the game pattern found past its wildcards");
    Check(lens::Find(code.data(), 0x4A, game) == -1, "and not when it runs past the end");
    Check(lens::U32(&code[0x41]) == 0x44332211, "the global read after it");

    // the build function with C at 0x00D00000, and the loads of C after it
    const uint32_t c = 0x00D00000, base = 0x00400000;
    std::vector<uint8_t> module(0x800, 0xCC);
    const lens::Pattern build(lens::BuildPattern);
    for (size_t i = 0; i < build.bytes.size(); ++i) module[0x100 + i] = build.any[i] ? 0 : build.bytes[i];
    Put32(module, 0x100 + lens::CAt, c);
    Check(lens::Find(module.data(), module.size(), build) == 0x100, "the build function found");
    Check(lens::U32(&module[0x100 + lens::CAt]) == c, "C's address where it is read");
    Put(module, 0x300, "DD0500000000D987F4020000D9F3"); Put32(module, 0x302, c);   // from an object, [edi+0x2F4]
    Put(module, 0x340, "DD0500000000D9442418D9F3"); Put32(module, 0x342, c);       // from the stack
    Put(module, 0x380, "DD0500000000D984F4020000D9F3"); Put32(module, 0x382, c);   // a SIB form: left out
    Put(module, 0x3C0, "DD0500000000D90500001000D9F3"); Put32(module, 0x3C2, c);   // a constant in place of f: left out
    Put(module, 0x400, "DD0500000000D987F4020000D9F3"); Put32(module, 0x402, c + 8); // another constant: left out
    std::vector<uintptr_t> sites;
    lens::FovSites(module.data(), module.size(), base, c, sites);
    Check(sites.size() == 3 && sites[0] == base + 0x100 + lens::CAt - 2 && sites[1] == base + 0x300 && sites[2] == base + 0x340,
        "the loads of C: the build function's own, from an object and from the stack, and no others");
    sites.clear();
    lens::FovSites(module.data(), 0x34B, base, c, sites);
    Check(sites.size() == 2, "a load running past the end is not read");

    Check(Near(lens::FovOf(192), 76.86, 0.01), "the game's 192 is 77 degrees up");
    Check(Near(lens::FovOf(lens::CFor(93)), 93, 1e-9) && Near(lens::CFor(lens::FovOf(192)), 192, 1e-9), "C for a field of view and back");

    // the README's settings at 3440x1440, each keeping about 77 up the middle
    const double aspect = (1 / 0.556459) / (1 / 1.260417);
    struct { lens::Mode mode; double strength, fov; const char* text; } readme[] = {
        { lens::Panini, 0.25, 93, "panini 25 keeps 77 at about 93" },
        { lens::Panini, 0.50, 110, "panini 50 at about 110" },
        { lens::Cylindrical, 0.50, 96, "cylindrical 50 at about 96" },
        { lens::Cylindrical, 0.75, 115, "cylindrical 75 at about 115" },
    };
    for (auto& r : readme) {
        bool capped = true;
        double fov = lens::MiddleFov(77, aspect, r.mode, r.strength, capped);
        printf("   %s: %.2f\n", r.text, fov);
        Check(!capped && Near(fov, r.fov, 1.5) && Near(lens::MiddleOf(fov, aspect, r.mode, r.strength), 77, 0.01), r.text);
    }
    bool capped = true;
    Check(Near(lens::MiddleFov(77, aspect, lens::Panini, 0, capped), 77, 0.01) && !capped, "flat, the middle is the field of view");
    Check(lens::MiddleOf(lens::FovMin, aspect, lens::Panini, 1) > 10 && lens::MiddleFov(10, aspect, lens::Panini, 1, capped) == lens::FovMin && !capped,
        "a middle the narrowest already shows: the narrowest");
    double widest = lens::MiddleFov(139, aspect, lens::Cylindrical, 1, capped);
    Check(capped && widest >= lens::FovMin && widest <= lens::FovMax && lens::MiddleOf(widest, aspect, lens::Cylindrical, 1) < 139,
        "a middle beyond reach: capped, at the field of view showing the most");
    printf(failures ? "%d FAILED\n" : "lens projection: all checks passed\n", failures);
    return failures;
}
