// lens's LENS-WARP block as namehook and uihook read it (shared.h Live): live while warped within two frames,
// and read the same from a newer lens whose block has grown past the 1.0 layout (plugins/ABI.md); not from
// one of another Version or smaller than 1.0's.
#include <stdio.h>
#include <string.h>
#include "../src/shared.h"
static int failures = 0;
static void Check(bool ok, const char* text) { printf("%s %s\n", ok ? "ok" : "FAIL", text); if (!ok) ++failures; }
struct Future { lens::Shared old; uint32_t Later[4]; };
int main() {
    lens::Shared s = { "LENS-WARP", 1, sizeof(lens::Shared), 10, 9, 0, 0.5f, 2, 1 };
    Check(lens::Live(&s), "the 1.0 block, warped last frame: live");
    s.WarpedFrame = 7;
    Check(!lens::Live(&s), "warped three frames ago: not");
    s.WarpedFrame = 9;
    Future f = {};
    f.old = s;
    f.old.Size = sizeof(Future);
    Check(lens::Live(&f.old), "a newer lens's larger block: live, read as ever");
    s.Size = sizeof(lens::Shared) - 4;
    Check(!lens::Live(&s), "a block smaller than 1.0's: not");
    s.Size = sizeof(lens::Shared); s.Version = 2;
    Check(!lens::Live(&s), "another Version: not");
    Check(!lens::Live(nullptr), "no lens: not");
    return failures ? 1 : 0;
}
