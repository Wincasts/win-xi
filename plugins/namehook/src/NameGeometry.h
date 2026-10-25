#pragma once

#include <cmath>

// CPU-only helpers shared by the renderer and geometry tests. Coordinates here
// are final render-target pixels, AFTER the local Lens counter-transform.
namespace NameGeometry {
    struct Point { float x, y; };
    constexpr float ShadowDrop = 0.75f;
    constexpr float ShadowOpacity = 0.35f;
    constexpr Point Halo[8] = {
        { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
        { -0.70710678f, -0.70710678f }, { 0.70710678f, -0.70710678f },
        { -0.70710678f, 0.70710678f }, { 0.70710678f, 0.70710678f },
    };
    // Eight halo copies, one shadow and the fill; soft solid rectangles need
    // just five (centre plus four perimeter strips). Never combine both modes.
    constexpr unsigned CopiesPerQuad = 10;

    struct SoftRectangle {
        Point Inner[4], Outer[4]; // clockwise: top-left, top-right, bottom-right, bottom-left
        // Where each point is within the quad, 0..1 across and down, for its texture
        // coordinates. The fringe outside takes the edge's own, never past the quad's.
        Point InnerAt[4], OuterAt[4];
        float Coverage = 1;

        bool Make(Point origin, Point right, Point bottom) {
            const Point a{ right.x - origin.x, right.y - origin.y };
            const Point b{ bottom.x - origin.x, bottom.y - origin.y };
            const float al = std::sqrt(a.x * a.x + a.y * a.y);
            const float bl = std::sqrt(b.x * b.x + b.y * b.y);
            const float area = std::fabs(a.x * b.y - a.y * b.x);
            if (!std::isfinite(al) || !std::isfinite(bl) || !std::isfinite(area)
                    || al <= 0 || bl <= 0 || area <= 0.000001f) { return false; }
            // Perpendicular spans, not edge lengths: a half-pixel ramp stays
            // a half-pixel ramp under rotation, scaling and Lens shear.
            const float width = area / bl, height = area / al;
            const float ou = 0.5f / width, ov = 0.5f / height;
            const float iu = ou < 0.5f ? ou : 0.5f;
            const float iv = ov < 0.5f ? ov : 0.5f;
            // A subpixel sliver must get fainter, not become an opaque fat line.
            Coverage = (width < 1 ? width : 1) * (height < 1 ? height : 1);
            auto at = [&](float u, float v) -> Point {
                return { origin.x + a.x * u + b.x * v, origin.y + a.y * u + b.y * v };
            };
            Inner[0] = at(iu, iv); Inner[1] = at(1 - iu, iv);
            Inner[2] = at(1 - iu, 1 - iv); Inner[3] = at(iu, 1 - iv);
            Outer[0] = at(-ou, -ov); Outer[1] = at(1 + ou, -ov);
            Outer[2] = at(1 + ou, 1 + ov); Outer[3] = at(-ou, 1 + ov);
            InnerAt[0] = { iu, iv }; InnerAt[1] = { 1 - iu, iv };
            InnerAt[2] = { 1 - iu, 1 - iv }; InnerAt[3] = { iu, 1 - iv };
            OuterAt[0] = { 0, 0 }; OuterAt[1] = { 1, 0 }; OuterAt[2] = { 1, 1 }; OuterAt[3] = { 0, 1 };
            return true;
        }
    };
}
