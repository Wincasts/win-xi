#pragma once
#include <stdint.h>
#include "placement.h"

// No ImTextureID or Direct3D pointer ever passes through Lua. Submit captures the current window's
// ImDrawList synchronously, on the render thread; it returns 1 only after a complete, retained copy.
// index 0..2: party/alliance; 3..5: main/sub/target-of-target (replayed together at targetwi).
// capture=1 copies and consumes its drawing, 0 submits empty, -1 releases only this slot.
// PARTY_PASS_OUTSIDE added to 0 or 1 (party/alliance only, where SupportedMask has PARTY_PASS_SUPPORTED): the
// game's own drawing that falls wholly away from the window (PARTY_PASS_REACH) is let through, the rest replaced as ever (a hooked
// fish's stamina gauge, which the game draws with its party list in the middle of the screen).
// index=-1: release all submissions immediately (addon unload, disabled, organize).
// Visibility-rule hiding instead renews empty submissions so native lists remain suppressed.
typedef int32_t(__cdecl* PartySubmit)(int32_t index, int32_t capture);
struct PartyShared {
    char Magic[16];
    uint32_t Version, Size, Hooked, SupportedMask, Frame;
    uint32_t DrawnFrame[6];
    uint32_t Submit; // PartySubmit; callable only while this DLL is loaded and ABI matches
    uint32_t CapturedVertices, BlockedCalls, Replays, Failures;
    uint32_t TargetCursorCalls; // original main/sub overhead arrow calls allowed through suppression
    uint32_t GeometryReady;
    NativeRect Rects[4]; // viewport-normalized party1, alliance2, alliance3, target; read-only
};
#define PARTY_VERSION 3
#define PARTY_PASS_OUTSIDE 4
#define PARTY_PASS_SUPPORTED 0x10u
#define PARTY_PASS_REACH 0.125f // the share of the viewport's height round the window still taken as its own (its edges, shadow, pet bar)
#define PARTY_MAX_VERTICES 196608
#define PARTY_MAX_COMMANDS 4096
// How long a submission is replayed without another. Eight frames, not two: under TrueFPS the game can
// present a few frames before the addons are next run, and two let the game's own windows through for one.
#define PARTY_FRESH_FRAMES 8
// A texture's address from the id imgui holds for it (ImTextureID, 64 bits), in this 32-bit game: the
// pointer, zero-extended, or sign-extended, as a pointer above 2 GB is once it has been read as a signed
// integer on its way through a renderer or a binding, and as the font texture's can be after a while (the
// addons draw with it as ever). 0 for anything else: a null, a mark
// (1, the addons' word for the font texture), a value no 32-bit pointer could give.
static inline uint32_t TextureAddress(uint64_t id) {
    const uint32_t low=static_cast<uint32_t>(id), high=static_cast<uint32_t>(id>>32);
    if (high!=0 && !(high==0xFFFFFFFFu && (low & 0x80000000u))) return 0;
    return low<0x10000 ? 0 : low;
}
