#pragma once

#include "Nameplate.h"

// Local pixel bounds of the complete drawing, including stars, detail lines and
// the plugin's outline offsets. No Direct3D dependency: test this independently.
struct NameBounds {
    float Left = 0, Top = 0, Right = 0, Bottom = 0;

    static NameBounds Measure(const HookDrawing& drawing, const HookQuad* quads) {
        NameBounds bounds;
        const float edge = drawing.Edge > 0.0f ? (drawing.Edge > 8.0f ? 8.0f : drawing.Edge) : 0.0f;
        for (uint32_t i = 0; i < drawing.Count; i++) {
            const HookQuad& quad = quads[i];
            const float pad = (quad.Flags & 1) != 0 ? edge : 0.0f;
            const float left = (quad.X0 < quad.X1 ? quad.X0 : quad.X1) - pad;
            const float right = (quad.X0 > quad.X1 ? quad.X0 : quad.X1) + pad;
            const float top = (quad.Y0 < quad.Y1 ? quad.Y0 : quad.Y1) - pad;
            const float bottom = (quad.Y0 > quad.Y1 ? quad.Y0 : quad.Y1) + pad;
            if (i == 0 || left < bounds.Left) { bounds.Left = left; }
            if (i == 0 || right > bounds.Right) { bounds.Right = right; }
            if (i == 0 || top < bounds.Top) { bounds.Top = top; }
            if (i == 0 || bottom > bounds.Bottom) { bounds.Bottom = bottom; }
        }
        return bounds;
    }

    bool Intersects(float anchorX, float anchorY, float x, float y, float width, float height) const {
        // Keep boundary-touching drawings conservatively; only reject those
        // wholly outside. An off-screen anchor does not imply an off-screen name.
        return !(anchorX + Right < x || anchorX + Left > x + width
            || anchorY + Bottom < y || anchorY + Top > y + height);
    }
};

struct NameBoundsCache {
    bool Valid = false;
    uint32_t Frame = 0, First = 0, Count = 0;
    float Edge = 0;
    NameBounds Bounds;

    const NameBounds& Get(const HookDrawing& drawing, const HookQuad* quads) {
        if (!Valid || Frame != drawing.Frame || First != drawing.First
                || Count != drawing.Count || Edge != drawing.Edge) {
            Bounds = NameBounds::Measure(drawing, quads);
            Frame = drawing.Frame;
            First = drawing.First;
            Count = drawing.Count;
            Edge = drawing.Edge;
            Valid = true;
        }
        return Bounds;
    }
};
