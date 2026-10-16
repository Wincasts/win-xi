#pragma once
#include <stdint.h>
#include "placement.h"

// No ImTextureID or Direct3D pointer ever passes through Lua. Submit captures the current window's
// ImDrawList synchronously, on the render thread; it returns 1 only after a complete, retained copy.
// index 0..2: party/alliance; 3..5: main/sub/target-of-target (replayed together at targetwi).
// capture=1 copies and consumes its drawing, 0 submits empty, -1 releases only this slot.
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
#define PARTY_MAX_VERTICES 196608
#define PARTY_MAX_COMMANDS 4096
#define PARTY_FRESH_FRAMES 2
