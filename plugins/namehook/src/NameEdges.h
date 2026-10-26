#pragma once
// The order a drawing's edge copies go down in (1.50): its quads' shadows and their eight halo copies, grouped by
// texture, so that a name of letters and an icon or two is a draw call for each texture's edges, not one for
// each texture change in each of ten passes (Jeuno, 2026-10-26: 524 draw calls for 24 names, ~22 a name).
//
// Grouping changes nothing drawn where the edges are of one colour, as they are: every copy is the drawing's
// EdgeColor (its shadow the same, fainter), times its texture, and same-coloured layers blended over one another
// come out the same in any order (a1 then a2 and a2 then a1 both leave c(1 - (1-a1)(1-a2)) + d(1-a1)(1-a2)). With
// a dark edge, the usual, an icon's copies are as dark as a letter's. Only where an icon's and a letter's copies
// overlap under a coloured edge could the two differ by a little. The quads themselves still go down after
// every edge, in their own order.
#include <stdint.h>

namespace NameEdges {
    // emit(i, pass) for each edge copy of quad i: pass -1 is its shadow, 0 to 7 its halo copies. Only quads
    // with a radius (radii[i] > 0); textures in the order each is first met, each texture's shadows then its
    // halo copies, offset by offset, quads in their order.
    template<class Quad, class Emit>
    void ByTexture(const Quad* quads, const float* radii, uint32_t count, Emit emit) {
        uint32_t textures[64];
        uint32_t textureCount = 0;
        for (uint32_t i = 0; i < count; i++) {
            if (!(radii[i] > 0)) continue;
            bool known = false;
            for (uint32_t t = 0; t < textureCount && !known; t++) known = textures[t] == quads[i].Texture;
            if (!known && textureCount < 64) textures[textureCount++] = quads[i].Texture;
        }
        for (uint32_t t = 0; t < textureCount; t++) {
            const uint32_t texture = textures[t];
            for (uint32_t i = 0; i < count; i++) {
                if (radii[i] > 0 && quads[i].Texture == texture && quads[i].EdgeShadow()) emit(i, -1);
            }
            for (int pass = 0; pass < 8; pass++) {
                for (uint32_t i = 0; i < count; i++) {
                    if (radii[i] > 0 && quads[i].Texture == texture) emit(i, pass);
                }
            }
        }
    }
}
