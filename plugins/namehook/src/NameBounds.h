#pragma once
#include <initializer_list>

#include "Nameplate.h"
#include "NameGeometry.h"

// Local pixel bounds of the complete drawing, including stars, detail lines and
// the plugin's outline offsets. No Direct3D dependency: test this independently.
struct NameBounds {
    float Left = 0, Top = 0, Right = 0, Bottom = 0;

    static NameBounds Measure(const HookDrawing& drawing, const HookQuad* quads, float horizontalFit = 1.0f) {
        NameBounds bounds;
        const float edge = drawing.Edge > 0.0f ? (drawing.Edge > 8.0f ? 8.0f : drawing.Edge) : 0.0f;
        for (uint32_t i = 0; i < drawing.Count; i++) {
            const HookQuad& quad = quads[i];
            const bool edged = (quad.Flags & QUAD_EDGED) != 0;
            const float pad = edged ? quad.EdgeRadius(edge) : ((quad.Flags & QUAD_SOFT_RECT) != 0 ? 1.0f : 0.0f);
            const float shadow = quad.EdgeShadow() && pad > 0 ? NameGeometry::ShadowDrop : 0.0f;
            const float left = (quad.X0 < quad.X1 ? quad.X0 : quad.X1) - pad * horizontalFit;
            const float right = (quad.X0 > quad.X1 ? quad.X0 : quad.X1) + pad * horizontalFit;
            const float top = (quad.Y0 < quad.Y1 ? quad.Y0 : quad.Y1) - pad;
            const float bottom = (quad.Y0 > quad.Y1 ? quad.Y0 : quad.Y1) + pad + shadow;
            if (i == 0 || left < bounds.Left) { bounds.Left = left; }
            if (i == 0 || right > bounds.Right) { bounds.Right = right; }
            if (i == 0 || top < bounds.Top) { bounds.Top = top; }
            if (i == 0 || bottom > bounds.Bottom) { bounds.Bottom = bottom; }
        }
        return bounds;
    }

    // Transform all four corners, not just left/right: Lens can shear and
    // expand a drawing whose anchor is outside the viewport. The screen-space
    // fringe covers soft rectangles even when the transform contracts a side.
    NameBounds Transformed(float a, float b, float c, float d, float fringe = 1) const {
        NameBounds out;
        bool first = true;
        for (float x : { Left, Right }) {
            for (float y : { Top, Bottom }) {
                const float tx = a * x + b * y, ty = c * x + d * y;
                if (first || tx < out.Left) out.Left = tx;
                if (first || tx > out.Right) out.Right = tx;
                if (first || ty < out.Top) out.Top = ty;
                if (first || ty > out.Bottom) out.Bottom = ty;
                first = false;
            }
        }
        // SoftRectangle expands in final perpendicular screen pixels. A nearly
        // parallel pair of transformed axes can require more than one pixel at
        // a corner; transforming the local padding alone is not sufficient.
        float padX = fringe, padY = fringe;
        const double determinant = std::fabs(double(a) * d - double(b) * c);
        if (determinant > 0) {
            const double al = std::hypot(double(a), double(c)), bl = std::hypot(double(b), double(d));
            const double x = 0.5 * (std::fabs(a) * bl + std::fabs(b) * al) / determinant;
            const double y = 0.5 * (std::fabs(c) * bl + std::fabs(d) * al) / determinant;
            padX += static_cast<float>(x);
            padY += static_cast<float>(y); // extra screen slack also absorbs float rounding
        }
        out.Left -= padX; out.Right += padX;
        out.Top -= padY; out.Bottom += padY;
        return out;
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
    float Edge = 0, HorizontalFit = 1;
    NameBounds Bounds;

    const NameBounds& Get(const HookDrawing& drawing, const HookQuad* quads, float horizontalFit = 1.0f) {
        if (!Valid || Frame != drawing.Frame || First != drawing.First
                || Count != drawing.Count || Edge != drawing.Edge || HorizontalFit != horizontalFit) {
            Bounds = NameBounds::Measure(drawing, quads, horizontalFit);
            Frame = drawing.Frame;
            First = drawing.First;
            Count = drawing.Count;
            Edge = drawing.Edge;
            HorizontalFit = horizontalFit;
            Valid = true;
        }
        return Bounds;
    }
};
