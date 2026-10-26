// buffhook's checks: the game's two functions are found by their patterns, and a function taken over
// runs ours, can still run its own from the trampoline, and is itself again once given back. Run by
// run.sh under wine: no game is needed.
#include <stdio.h>

#include "../src/modules/buffs/detour.h"
#include "../src/modules/buffs/game.h"

static int failures = 0;

static void Check(bool ok, const char* what) {
    printf("%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
}

// The first bytes of the two functions as they are in FFXiMain.dll, as Phoenix's client has it
static const uint8_t IconBytes[] = {
    0x55, 0x56, 0x57, 0xE8, 0x68, 0xBA, 0xED, 0xFF, 0x8B, 0x6C, 0x24, 0x10, 0x8D, 0x04, 0x40, 0x8B,
    0xCD, 0x8D, 0x34, 0x80, 0x8B, 0x44, 0x24, 0x20, 0x50, 0xC1, 0xE6, 0x02, 0xE8, 0x9F, 0xF9, 0xFF,
    0xFF, 0x8B, 0xF8, 0x85, 0xFF, 0x0F, 0x84, 0xDB, 0x00, 0x00, 0x00, 0x53, 0x68, 0xC3, 0x00, 0x00,
};
static const uint8_t TimeBytes[] = {
    0x83, 0xEC, 0x10, 0x53, 0x56, 0x57, 0x68, 0xC3, 0x00, 0x00, 0x00, 0xE8, 0xC0, 0xB7, 0xF6, 0xFF,
    0x83, 0xC4, 0x04, 0x85, 0xC0, 0x0F, 0x84, 0x08, 0x01, 0x00, 0x00, 0xE8, 0x40, 0xB9, 0xED, 0xFF,
    0x8B, 0x7C, 0x24, 0x30, 0x8B, 0x5C, 0x24, 0x20, 0x8D, 0x04, 0x40, 0x57, 0x8B, 0xCB, 0x8D, 0x34,
};

// and of the window's cursor offset setter, and its neighbour that sets the cursor's scale
static const uint8_t OffsetBytes[] = {
    0x51, 0x56, 0x8D, 0x71, 0x14, 0x8B, 0xCE, 0xE8, 0x64, 0xB9, 0x00, 0x00, 0x85, 0xC0, 0x89, 0x44,
    0x24, 0x04, 0x74, 0x33, 0x8D, 0x44, 0x24, 0x04, 0x8B, 0xCE, 0x50, 0xE8, 0x90, 0xB9, 0x00, 0x00,
    0x0F, 0xBF, 0x08, 0x83, 0xE9, 0x02, 0x74, 0x0D, 0x8B, 0x44, 0x24, 0x04, 0x85, 0xC0, 0x75, 0xE4,
    0x5E, 0x59, 0xC2, 0x08, 0x00, 0x66, 0x8B, 0x4C, 0x24, 0x0C, 0x66, 0x8B, 0x54, 0x24, 0x10, 0x66,
    0x89, 0x48, 0x28, 0x66, 0x89, 0x50, 0x2A, 0x5E, 0x59, 0xC2,
};
static const uint8_t ScaleBytes[] = {
    0x51, 0x56, 0x8D, 0x71, 0x14, 0x8B, 0xCE, 0xE8, 0xB4, 0xB9, 0x00, 0x00, 0x85, 0xC0, 0x89, 0x44,
    0x24, 0x04, 0x74, 0x28, 0x8D, 0x44, 0x24, 0x04, 0x8B, 0xCE, 0x50, 0xE8, 0xE0, 0xB9, 0x00, 0x00,
    0x0F, 0xBF, 0x08, 0x83, 0xE9, 0x02, 0x74, 0x0D, 0x8B, 0x44, 0x24, 0x04, 0x85, 0xC0, 0x75, 0xE4,
    0x5E, 0x59, 0xC2, 0x04, 0x00, 0x8B, 0x4C, 0x24, 0x0C, 0x89, 0x48, 0x24, 0x5E, 0x59, 0xC2, 0x04,
};

static void CheckPatterns() {
    uint8_t image[512];
    memset(image, 0xCC, sizeof(image));
    memcpy(image + 100, IconBytes, sizeof(IconBytes));
    memcpy(image + 300, TimeBytes, sizeof(TimeBytes));
    Check(FindPattern(image, sizeof(image), ICON_PATTERN) == image + 100, "the icon callback is found by its pattern");
    Check(FindPattern(image, sizeof(image), TIME_PATTERN) == image + 300, "the time callback is found by its pattern");
    Check(IconBytes[ICON_CALL_AT] == 0xE8, "the icon callback's moved bytes have their call where said");
    image[300 + 7] = 0xC2; // another setting than the timers'
    Check(FindPattern(image, sizeof(image), TIME_PATTERN) == nullptr, "a function like it that is not it is not found");

    uint8_t window[256];
    memset(window, 0xCC, sizeof(window));
    memcpy(window + 10, ScaleBytes, sizeof(ScaleBytes));
    memcpy(window + 120, OffsetBytes, sizeof(OffsetBytes));
    Check(FindPattern(window, sizeof(window), CURSOR_OFFSET_PATTERN) == window + 120, "the cursor offset setter is found, not its neighbour that sets the scale");
}

// Functions shaped as the game's are at their start, written into memory that can be run:
//   shaped like the icon callback: push ebp; push esi; push edi; call answer; pop edi; pop esi; pop ebp; ret
//   shaped like the time callback: sub esp,10; push ebx; push esi; push edi; mov eax,7; pop edi; pop esi;
//                                  pop ebx; add esp,10; ret
//   answer:                        mov eax,42; ret
typedef int(__cdecl* Function)();
static Detour* Running = nullptr;

static int __cdecl Replacement() {
    return reinterpret_cast<Function>(Running->trampoline)() + 100;
}

static void CheckTaking() {
    uint8_t* code = static_cast<uint8_t*>(VirtualAlloc(nullptr, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    memset(code, 0xCC, 4096);
    uint8_t* answer = code + 2000;
    const uint8_t answerBytes[] = { 0xB8, 0x2A, 0x00, 0x00, 0x00, 0xC3 };
    memcpy(answer, answerBytes, sizeof(answerBytes));

    uint8_t* icon = code + 16;
    const uint8_t iconBytes[] = { 0x55, 0x56, 0x57, 0xE8, 0, 0, 0, 0, 0x5F, 0x5E, 0x5D, 0xC3 };
    memcpy(icon, iconBytes, sizeof(iconBytes));
    const int32_t toAnswer = Distance(icon + 8, answer);
    memcpy(icon + 4, &toAnswer, 4);

    uint8_t* time = code + 64;
    const uint8_t timeBytes[] = { 0x83, 0xEC, 0x10, 0x53, 0x56, 0x57, 0xB8, 0x07, 0x00, 0x00, 0x00, 0x5F, 0x5E, 0x5B, 0x83, 0xC4, 0x10, 0xC3 };
    memcpy(time, timeBytes, sizeof(timeBytes));

    Check(reinterpret_cast<Function>(icon)() == 42 && reinterpret_cast<Function>(time)() == 7, "the made functions run as made");

    Detour iconDetour = { "55 56 57 E8 ?? ?? ?? ?? 5F 5E 5D C3", ICON_STOLEN, ICON_CALL_AT, reinterpret_cast<void*>(&Replacement), nullptr, nullptr, {} };
    Detour timeDetour = { "83 EC 10 53 56 57 B8 07", TIME_STOLEN, TIME_CALL_AT, reinterpret_cast<void*>(&Replacement), nullptr, nullptr, {} };

    Check(Take(iconDetour, code, 1000), "a function shaped like the icon callback is taken");
    Running = &iconDetour;
    Check(reinterpret_cast<Function>(icon)() == 142, "it runs ours, which runs its own from the trampoline, its call aimed again");
    Give(iconDetour);
    Check(memcmp(icon, iconBytes, 4) == 0 && reinterpret_cast<Function>(icon)() == 42, "given back, it is as it was");

    Check(Take(timeDetour, code, 1000), "a function shaped like the time callback is taken");
    Running = &timeDetour;
    Check(reinterpret_cast<Function>(time)() == 107, "it runs ours, which runs its own from the trampoline");
    Give(timeDetour);
    Check(memcmp(time, timeBytes, sizeof(timeBytes)) == 0 && reinterpret_cast<Function>(time)() == 7, "given back, it is as it was");

    VirtualFree(code, 0, MEM_RELEASE);
}

static void CheckSteady() {
    Check(SteadyFirst(143, 0) == 143 && SteadyFirst(49, 0) == 49, "the first icon with the cursor on it: where the game puts it");
    Check(SteadyFirst(144, 1) == 143 && SteadyFirst(50, 1) == 49, "the cursor on the second: the bar where the first is with the cursor on it");
    Check(SteadyFirst(144, -1) == 143, "the cursor on none: the same");
}

int main() {
    CheckPatterns();
    CheckTaking();
    CheckSteady();
    printf(failures == 0 ? "all passed\n" : "%d failed\n", failures);
    return failures == 0 ? 0 : 1;
}
