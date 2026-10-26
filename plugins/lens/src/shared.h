// What lens is doing, for others that place things over the world: the block lens.dll exports as
// LensWarp (and that winxi.lens finds by its magic, LENS-WARP). Frame counts Presents; WarpedFrame is
// the Frame the game's copy was last warped in, so the warp is live while the two are within a frame
// or two of each other. Mode is lens::Mode; Strength 0 to 1; TanH and TanV the picture's half fields
// of view as tangents.
#pragma once
#include <stdint.h>

namespace lens {

struct Shared {
    char Magic[16];
    uint32_t Version, Size, Frame, WarpedFrame, Mode;
    float Strength, TanH, TanV;
};
static_assert(sizeof(Shared) == 48, "LENS-WARP ABI 1");

// Whether the block says the warp is live. A newer lens may add fields after these (plugins/ABI.md): its
// Size is then larger, and what is here is read as ever.
inline bool Live(const Shared* s) {
    return s != nullptr && s->Version == 1 && s->Size >= sizeof(Shared) && s->WarpedFrame != 0 && s->Frame - s->WarpedFrame <= 2;
}

} // namespace lens
