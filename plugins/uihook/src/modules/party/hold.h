// While imgui makes its font texture again (the atlas grown or made afresh, as when an addon loads a
// font and writes new sizes with it), a window's draw commands point at a texture not yet made, and a
// capture of them is refused. Rather than nothing, or the game's own window, for those frames, the
// slot's last capture is drawn again, for up to PARTY_HOLD_FRAMES frames in a row: its vertices are
// of the old atlas and its runs hold the old texture (AppendRun's AddRef), so it is drawn as it was.
#pragma once
#include <stdint.h>
#include "../../slots.h"
#define PARTY_HOLD_FRAMES 8
// Whether a slot refused for why keeps its last capture: only for the texture, only a fresh one, and
// only so many frames in a row (held, those already kept)
static inline bool HoldCapture(uint8_t why, bool fresh, uint32_t held) {
    return why == REFUSED_TEXTURE_NOT_READY && fresh && held < PARTY_HOLD_FRAMES;
}
