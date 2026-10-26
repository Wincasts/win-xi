// buffhook: taking over one of the game's functions, by having its first bytes jump to another.
#pragma once

#include <windows.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "../../../../common/CodePatch.h"

// One function of the game's, taken over by having its first bytes jump to ours. What they were is
// kept, and run from the trampoline before it jumps back to the rest, for when the game's own is wanted.
struct Detour {
    const char* pattern; // its first bytes, ?? for any
    uint32_t stolen;     // how many of them are moved to the trampoline: whole instructions, at least 5
    int32_t callAt;      // where among them a call (E8) is, whose distance is measured again, or -1
    void* replacement;

    uint8_t* target;
    uint8_t* trampoline;
    uint8_t saved[16];
    CodeSite<WindowsCodeMemory> site; // the function's first bytes, written and given back only while ours
};

// The first place in begin's size bytes that the pattern fits: its bytes in hex, ?? for any
static uint8_t* FindPattern(uint8_t* begin, size_t size, const char* pattern) {
    uint8_t bytes[64];
    bool any[64];
    uint32_t length = 0;
    for (const char* at = pattern; *at != '\0' && length < 64;) {
        if (*at == ' ') {
            at++;
            continue;
        }
        if (at[0] == '?') {
            any[length] = true;
            bytes[length++] = 0;
        } else {
            char hex[3] = { at[0], at[1], '\0' };
            any[length] = false;
            bytes[length++] = static_cast<uint8_t>(strtoul(hex, nullptr, 16));
        }
        at += 2;
    }

    for (size_t i = 0; i + length <= size; i++) {
        uint32_t j = 0;
        while (j < length && (any[j] || begin[i + j] == bytes[j])) {
            j++;
        }
        if (j == length) {
            return begin + i;
        }
    }
    return nullptr;
}

// Gives a site back; one something else has written over since is left, and this DLL kept loaded (StrandCode),
// as the client may still go through it into this DLL. False then.
static bool GiveSite(CodeSite<WindowsCodeMemory>& site) {
    if (site.Restore()) {
        return true;
    }
    StrandCode();
    return false;
}

static int32_t Distance(const uint8_t* from, const void* to) {
    return static_cast<int32_t>(reinterpret_cast<uintptr_t>(to) - reinterpret_cast<uintptr_t>(from));
}

// Finds the function in begin's size bytes and takes it over
static bool Take(Detour& detour, uint8_t* begin, size_t size) {
    detour.target = FindPattern(begin, size, detour.pattern);
    if (detour.target == nullptr) {
        return false;
    }
    detour.trampoline = static_cast<uint8_t*>(VirtualAlloc(nullptr, 32, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    if (detour.trampoline == nullptr) {
        detour.target = nullptr;
        return false;
    }

    // the trampoline: the stolen bytes, a call among them aimed again from where it now is, then back
    memcpy(detour.saved, detour.target, detour.stolen);
    memcpy(detour.trampoline, detour.target, detour.stolen);
    if (detour.callAt >= 0) {
        int32_t was;
        memcpy(&was, detour.target + detour.callAt + 1, 4);
        const uint8_t* callee = detour.target + detour.callAt + 5 + was;
        const int32_t now = Distance(detour.trampoline + detour.callAt + 5, callee);
        memcpy(detour.trampoline + detour.callAt + 1, &now, 4);
    }
    uint8_t* back = detour.trampoline + detour.stolen;
    back[0] = 0xE9;
    const int32_t rest = Distance(back + 5, detour.target + detour.stolen);
    memcpy(back + 1, &rest, 4);
    FlushInstructionCache(GetCurrentProcess(), detour.trampoline, 32);

    // and the function's start, a jump to ours
    uint8_t jump[16];
    memset(jump, 0x90, sizeof(jump));
    jump[0] = 0xE9;
    const int32_t to = Distance(detour.target + 5, detour.replacement);
    memcpy(jump + 1, &to, 4);
    if (!detour.site.Write(reinterpret_cast<uintptr_t>(detour.target), jump, detour.stolen)) {
        // not written: nothing goes through the trampoline. Written in part: the function is neither ours nor the
        // game's, and the trampoline and this DLL are kept for whatever runs it
        if (detour.site.Abandoned) {
            StrandCode();
        } else {
            VirtualFree(detour.trampoline, 0, MEM_RELEASE);
        }
        detour.trampoline = nullptr;
        detour.target = nullptr;
        return false;
    }
    return true;
}

static void Give(Detour& detour) {
    if (detour.target != nullptr) {
        // the jump given back only while it is ours; else left, and the trampoline kept, as whatever wrote over
        // the jump may still go through it
        if (!GiveSite(detour.site)) {
            detour.trampoline = nullptr;
        }
        detour.target = nullptr;
    }
    if (detour.trampoline != nullptr) {
        VirtualFree(detour.trampoline, 0, MEM_RELEASE);
        detour.trampoline = nullptr;
    }
}
