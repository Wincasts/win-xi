// lens: return addresses read off a stack (each form of call, nothing outside the module, nothing not
// after a call), and the capture's matrices, runs and report.
#include <stdio.h>
#include "../src/capture.h"
#include "../src/stack.h"
static int failures = 0;
static void Check(bool ok, const char* text) { printf("%s %s\n", ok ? "ok" : "FAIL", text); if (!ok) ++failures; }
static bool Has(const std::string& s, const char* part) { return s.find(part) != std::string::npos; }

int main() {
    // calls of each form, each followed by the return address it leaves
    uint8_t code[128] = {};
    const uint8_t calls[][8] = {
        { 5, 0xE8, 1, 2, 3, 4 },                // call rel32
        { 2, 0xFF, 0xD1 },                      // call ecx
        { 2, 0xFF, 0x11 },                      // call [ecx]
        { 3, 0xFF, 0x51, 0x10 },                // call [ecx+0x10]
        { 4, 0xFF, 0x54, 0x24, 0x08 },          // call [esp+8]
        { 6, 0xFF, 0x91, 0x18, 0x01, 0, 0 },    // call [ecx+0x118], as the game calls the device
        { 6, 0xFF, 0x15, 0, 0x10, 0, 0 },       // call [0x1000]
        { 7, 0xFF, 0x94, 0x24, 0x10, 1, 0, 0 }, // call [esp+0x110]
    };
    size_t at = 8, ends[8];
    for (int i = 0; i < 8; ++i) { memcpy(code + at, calls[i] + 1, calls[i][0]); at += calls[i][0]; ends[i] = at; at += 2; }
    bool all = true;
    for (int i = 0; i < 8; ++i) all = all && lens::AfterCall(code, ends[i]);
    Check(all, "each form of call is one");
    code[100] = 0x90; code[101] = 0x90;
    Check(!lens::AfterCall(code, 102), "nops are not a call");
    Check(!lens::AfterCall(code, 3), "nothing read before the start");

    const uintptr_t base = 0x10000000;
    uint32_t stack[] = { 0x1234, (uint32_t)(base + 102), (uint32_t)(base + ends[5]), 0x20000000, (uint32_t)(base + ends[0]), (uint32_t)(base + ends[1]) };
    uint32_t out[2] = {};
    lens::ReturnAddresses(stack, 6, base, code, sizeof(code), out, 2);
    Check(out[0] == ends[5] && out[1] == ends[0], "the nearest two, skipping what is not after a call or not in the module");
    uint32_t none[2] = {};
    lens::ReturnAddresses(stack, 1, base, code, sizeof(code), none, 2);
    Check(none[0] == 0 && none[1] == 0, "none found leaves 0");

    // a 90 degree vertical perspective at 2:1, and an orthographic one
    lens::Matrix persp = {}, ortho = {};
    persp.m[5] = 1.0f; persp.m[0] = 0.5f; persp.m[10] = 1.0f; persp.m[11] = 1.0f; persp.m[14] = -0.1f;
    ortho.m[0] = 2.0f / 800; ortho.m[5] = 2.0f / 600; ortho.m[10] = 1.0f; ortho.m[15] = 1.0f;
    double h = 0, v = 0;
    Check(lens::Perspective(persp, h, v) && fabs(v - 90) < 1e-3 && fabs(h - 126.87) < 0.01, "a perspective's fields of view");
    Check(!lens::Perspective(ortho, h, v), "an orthographic one is not");
    lens::Matrix rh = persp;
    rh.m[11] = -1.0f;
    Check(lens::Perspective(rh, h, v) && fabs(v - 90) < 1e-3, "a right-handed one, as the game's, too");
    Check(lens::ScreenSpace(0x144) && !lens::ScreenSpace(0x152) && !lens::ScreenSpace(0x145), "XYZRHW is screen space; XYZ and a shader handle are not");

    lens::Capture c;
    lens::Draw world;
    world.kind = lens::DIP; world.prim = 4; world.count = 100; world.shader = 0x152; world.target = 0xA0; world.targetW = 3440; world.targetH = 1440;
    world.targetBack = true; world.vpW = 3440; world.vpH = 1440; world.zEnable = 1; world.zWrite = 1; world.proj = persp; world.caller[0] = 0x6F68; world.caller[1] = 0x1000;
    lens::Draw ui = world;
    ui.kind = lens::DPUP; ui.count = 2; ui.shader = 0x144; ui.zEnable = 0; ui.zWrite = 0; ui.proj = ortho; ui.caller[0] = 0x2000; ui.caller[1] = 0;
    lens::Draw ashita = ui;
    ashita.caller[0] = 0;
    c.Mark(lens::Capture::Event::BeginScene, true);
    c.Add(world); c.Add(world); c.Add(world);
    c.Add(ui); c.Add(ui);
    c.Mark(lens::Capture::Event::EndScene, true);
    c.Add(ashita);
    c.Mark(lens::Capture::Event::Present, true);
    Check(c.frames == 1 && c.draws.size() == 6 && c.projections.size() == 2 && c.targets.size() == 1 && c.views.size() == 1, "draws, frames and what they share kept once");
    Check(c.SameRun(0, 1) && !c.SameRun(2, 3) && !c.SameRun(4, 5), "runs part at the space and the caller");
    std::string r = c.Report("test\n");
    Check(Has(r, "1 frames, 6 draws, 2 projections"), "the summary");
    Check(Has(r, "P0 perspective: 126.87 across, 90.00 up"), "the perspective listed with its fields of view");
    Check(Has(r, "P1 other:"), "the orthographic listed as other");
    Check(Has(r, "T0 3440x1440 (back buffer)"), "the target and its size");
    Check(Has(r, "#0-#2 (3 draws, 300 prims) T0 3d P0 V0 z1w"), "the world's run");
    Check(Has(r, "#3-#4 (2 draws, 4 prims) T0 screen P1 V0 z0"), "the UI's run");
    Check(Has(r, "game+006F68<001000"), "the game's callers");
    Check(Has(r, "#5-#5 (1 draws, 2 prims)") && Has(r, "not the game"), "a draw not the game's");
    Check(Has(r, "-- BeginScene (back buffer)") && Has(r, "== Present (frame 0 ends)"), "the scene and frame markers");
    Check(Has(r, "#3 DPUP prim4 x2 fvf 00000144"), "a draw's own line");
    printf(failures ? "%d FAILED\n" : "lens capture: all checks passed\n", failures);
    return failures ? 1 : 0;
}
