#pragma once
#include <cstdint>

// CPU-only run construction shared with tests. Slots may alias one texture;
// merging adjacent aliases preserves vertex order, blending and depth exactly.
struct NameRun {
    uint32_t texture, first, count, maxAlpha;
    bool doubled; // drawn with its colour doubled (QUAD_DOUBLED)
    bool WritesDepth(uint32_t threshold) const { return maxAlpha >= threshold; }
};

namespace NameSubmission {
    inline bool Visible(uint32_t color) { return (color >> 24) != 0; }

    template<class Texture>
    void Append(NameRun* runs, uint32_t& runCount, uint32_t slot,
            uint32_t first, uint32_t vertices, uint32_t color, Texture* const* textures, bool doubled = false) {
        if (runCount == 0 || textures[runs[runCount - 1].texture] != textures[slot] || runs[runCount - 1].doubled != doubled) {
            runs[runCount++] = { slot, first, 0, 0, doubled };
        }
        auto& run = runs[runCount - 1];
        run.count += vertices;
        const uint32_t alpha = color >> 24;
        if (alpha > run.maxAlpha) run.maxAlpha = alpha;
    }
}
