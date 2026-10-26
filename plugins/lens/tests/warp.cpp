// lens warp: strength 0 is the game's own picture, the screen's corners land on the source's at any
// strength, the middle is enlarged by the strength, the inverse undoes the forward mapping, the quad is
// read whatever the strip's order, and the grid's size and indices.
#include <stdio.h>
#include "../src/warp.h"
static int failures = 0;
static void Check(bool ok, const char* text) { printf("%s %s\n", ok ? "ok" : "FAIL", text); if (!ok) ++failures; }
static bool Near(double a, double b, double e = 1e-4) { return fabs(a - b) < e; }

int main() {
    const double tanH = 1 / 0.556459, tanV = 1 / 1.260417;   // the game's at 3440x1440
    lens::Vertex strip[4] = {
        { -0.5f, 1439.5f, 0, 1, 0xFFFFFFFF, 0, 1 },
        { -0.5f, -0.5f, 0, 1, 0xFFFFFFFF, 0, 0 },
        { 3439.5f, 1439.5f, 0, 1, 0xFFFFFFFF, 1, 1 },
        { 3439.5f, -0.5f, 0, 1, 0xFFFFFFFF, 1, 0 },
    };
    lens::Quad q = lens::QuadOf(strip);
    Check(q.left == -0.5f && q.top == -0.5f && q.right == 3439.5f && q.bottom == 1439.5f && q.u0 == 0 && q.v0 == 0 && q.u1 == 1 && q.v1 == 1, "the quad read from a strip in any order");

    std::vector<lens::Vertex> v;
    std::vector<uint16_t> idx;
    lens::Build(q, tanH, tanV, lens::Panini, 0, 8, 4, v, idx);
    bool flat = true;
    for (int r = 0; r <= 4; ++r) for (int c = 0; c <= 8; ++c) {
        const lens::Vertex& x = v[r * 9 + c];
        flat = flat && Near(x.u, c / 8.0) && Near(x.v, r / 4.0);
    }
    Check(flat, "strength 0 is the game's own picture");
    Check(v.size() == 45 && idx.size() == 8 * 4 * 6 && idx[0] == 0 && idx[1] == 1 && idx[2] == 9 && idx[5] == 9, "the grid's size and its first triangles");

    for (double d : { 0.25, 0.5, 1.0 }) {
        lens::Build(q, tanH, tanV, lens::Panini, d, 8, 4, v, idx);
        bool corners = Near(v[0].u, 0) && Near(v[0].v, 0) && Near(v[8].u, 1) && Near(v[44].u, 1) && Near(v[44].v, 1) && Near(v[36].v, 1);
        Check(corners, d == 1.0 ? "corners on the source's corners at 1" : d == 0.5 ? "corners on the source's corners at 0.5" : "corners on the source's corners at 0.25");
    }
    lens::Build(q, tanH, tanV, lens::Panini, 1, 8, 4, v, idx);
    double mh = lens::MiddleHeight(tanH, tanV, lens::Panini, 1);
    Check(Near(v[4].v, 0.5 - 0.5 * mh) && Near(v[40].v, 0.5 + 0.5 * mh), "the middle column shows MiddleHeight of the source");
    Check(Near(v[22].u, 0.5) && Near(v[22].v, 0.5), "the middle stays the middle");
    Check(v[1].u > 1 / 8.0 && v[3].u > 3 / 8.0 , "the edges squeezed: the outer columns take in more of the source");
    Check(Near(lens::MiddleHeight(tanH, tanV, lens::Panini, 0), 1) && lens::MiddleHeight(tanH, tanV, lens::Panini, 0.5) > lens::MiddleHeight(tanH, tanV, lens::Panini, 1), "stronger enlarges the middle more");
    Check(Near(mh, lens::PaniniX(atan(tanH), 1) / tanH) && Near(lens::ShownAcross(tanH, tanV, lens::Panini, 1), tanH), "Panini keeps the whole width");

    // cylindrical: 0 is the flat picture, 1 has every column the same angle wide, its corners on the
    // picture's top and bottom and inside its sides, giving up a little width
    lens::Build(q, tanH, tanV, lens::Cylindrical, 0, 8, 4, v, idx);
    bool cflat = true;
    for (int r = 0; r <= 4; ++r) for (int c = 0; c <= 8; ++c) cflat = cflat && Near(v[r * 9 + c].u, c / 8.0) && Near(v[r * 9 + c].v, r / 4.0);
    Check(cflat, "cylindrical at 0 is the game's own picture");
    double phiE = lens::CylinderEdge(tanH);
    Check(Near(phiE / cos(phiE), tanH) && phiE < atan(tanH), "the cylinder's edge: its corner's ray the picture's corner");
    lens::Build(q, tanH, tanV, lens::Cylindrical, 1, 8, 4, v, idx);
    Check(Near(v[0].v, 0) && Near(v[44].v, 1) && v[0].u > 0 && v[44].u < 1, "corners on the picture's top and bottom, inside its sides");
    bool even = true;
    for (int c = 0; c <= 8; ++c) {
        double tx = (2 * v[18 + c].u - 1) * tanH;           // the middle row's columns
        even = even && Near(atan(tx), phiE * (2 * c / 8.0 - 1));
    }
    Check(even, "every column the same angle wide");
    Check(lens::MiddleHeight(tanH, tanV, lens::Cylindrical, 1) < lens::MiddleHeight(tanH, tanV, lens::Panini, 1), "cylindrical enlarges the middle more than Panini");
    Check(Near(atan(lens::ShownAcross(tanH, tanV, lens::Cylindrical, 1)), phiE) && Near(lens::ShownAcross(tanH, tanV, lens::Cylindrical, 0), tanH), "it shows across to its edge; at 0, all of it");
    bool inside = true;
    for (const lens::Vertex& x : v) inside = inside && x.u >= -1e-6 && x.u <= 1 + 1e-6 && x.v >= -1e-6 && x.v <= 1 + 1e-6;
    Check(inside, "nothing read from outside the picture");

    bool round = true;
    for (double phi = -1.2; phi <= 1.2; phi += 0.3) for (double d : { 0.0, 0.5, 1.0 }) {
        double t = 0.4, s = (d + 1) / (d + cos(phi));
        double tx, ty;
        lens::PaniniInverse(lens::PaniniX(phi, d), s * t, d, tx, ty);
        round = round && Near(tx, tan(phi)) && Near(ty, t / cos(phi));
    }
    Check(round, "the inverse undoes the forward mapping");
    // the inverse without acos and tan (0.94) gives what it gave with them
    bool inverse = true;
    for (double d : { 0.0, 0.1, 0.25, 0.5, 1.0, 2.0 }) for (double px = -1.5; px <= 1.5; px += 0.01) for (double py : { -1.0, -0.3, 0.0, 0.7 }) {
        double k = px * px / ((d + 1) * (d + 1));
        double disc = k * k * d * d - (k + 1) * (k * d * d - 1);
        double c = (-k * d + sqrt(disc > 0 ? disc : 0)) / (k + 1);
        if (c > 1) c = 1;
        if (c < 1e-6) c = 1e-6;
        double phi = (px < 0 ? -1 : 1) * acos(c);
        double ox = tan(phi), oy = (py / ((d + 1) / (d + c))) / c;
        double tx, ty;
        lens::PaniniInverse(px, py, d, tx, ty);
        inverse = inverse && fabs(tx - ox) <= 1e-9 * (1 + fabs(ox)) && fabs(ty - oy) <= 1e-9 * (1 + fabs(oy));
    }
    Check(inverse, "the inverse without acos and tan gives what it did with them");
    // the Panini edges worked out once for a grid map as worked out at each point
    bool edges = true;
    for (double d : { 0.0, 0.25, 1.0 }) {
        const lens::PaniniEdges e = lens::PaniniEdgesOf(tanH, tanV, d);
        for (double s0 = 0; s0 <= 1; s0 += 0.125) for (double t0 = 0; t0 <= 1; t0 += 0.25) {
            double a, b, c, f;
            lens::SourceOf(s0, t0, tanH, tanV, lens::Panini, d, a, b);
            lens::SourceOf(s0, t0, tanH, tanV, lens::Panini, d, 0, e, c, f);
            edges = edges && a == c && b == f;
        }
    }
    Check(edges, "the Panini edges handed in map as worked out each time");
    // ScreenOf undoes SourceOf: where the warp shows a point of the flat picture, for overlays
    bool back = true;
    for (lens::Mode mode : { lens::Panini, lens::Cylindrical }) for (double k : { 0.0, 0.25, 0.5, 0.75 })
        for (double s0 = 0.05; s0 < 1; s0 += 0.15) for (double t0 = 0.05; t0 < 1; t0 += 0.15) {
            double ss, tt, us, vs;
            lens::ScreenOf(s0, t0, tanH, tanV, mode, k, ss, tt);
            lens::SourceOf(ss, tt, tanH, tanV, mode, k, us, vs);
            back = back && Near(us, s0, 1e-6) && Near(vs, t0, 1e-6);
        }
    Check(back, "ScreenOf undoes SourceOf for both modes and every strength");
    // the edge worked out once and handed in maps as it does worked out each time
    bool edge = Near(lens::EdgeOf(tanH, lens::Cylindrical), phiE, 1e-12) && lens::EdgeOf(tanH, lens::Panini) == 0;
    for (lens::Mode mode : { lens::Panini, lens::Cylindrical }) for (double s0 : { 0.1, 0.5, 0.9 }) {
        const double e = lens::EdgeOf(tanH, mode);
        double a, b, c, d;
        lens::SourceOf(s0, 0.3, tanH, tanV, mode, 0.5, a, b);
        lens::SourceOf(s0, 0.3, tanH, tanV, mode, 0.5, e, c, d);
        edge = edge && a == c && b == d;
        lens::ScreenOf(s0, 0.3, tanH, tanV, mode, 0.5, a, b);
        lens::ScreenOf(s0, 0.3, tanH, tanV, mode, 0.5, e, c, d);
        edge = edge && a == c && b == d;
    }
    Check(edge, "EdgeOf handed to SourceOf and ScreenOf maps as without it");
    double ms, mt;
    lens::ScreenOf(0.5, 0.5, tanH, tanV, lens::Panini, 0.25, ms, mt);
    Check(Near(ms, 0.5) && Near(mt, 0.5), "the middle stays where it is");
    lens::ScreenOf(0.95, 0.5, tanH, tanV, lens::Panini, 0.25, ms, mt);
    Check(ms > 0.95 && Near(mt, 0.5), "a point near the edge of the picture is shown nearer the edge of the screen");
    // Counter: an offset put through it, drawn in the picture, comes out of the warp as it was
    const double W = 5160, H = 2160;
    double cm[4];
    lens::Counter(0.5, 0.5, W, H, tanH, tanV, lens::Panini, 0, cm);
    Check(cm[0] == 1 && cm[1] == 0 && cm[2] == 0 && cm[3] == 1, "no warp, no counter");
    bool kept = true;
    for (lens::Mode mode : { lens::Panini, lens::Cylindrical }) for (double k : { 0.25, 0.5 })
        for (double s0 : { 0.05, 0.3, 0.5, 0.9 }) for (double t0 : { 0.1, 0.5, 0.85 }) {
            lens::Counter(s0, t0, W, H, tanH, tanV, mode, k, cm);
            double ps, pt, qs, qt;
            const double dx = 40, dy = -25;   // a name's corner, in picture pixels
            lens::ScreenOf(s0, t0, tanH, tanV, mode, k, ps, pt);
            lens::ScreenOf(s0 + (cm[0] * dx + cm[1] * dy) / W, t0 + (cm[2] * dx + cm[3] * dy) / H, tanH, tanV, mode, k, qs, qt);
            kept = kept && Near((qs - ps) * W, dx, 1) && Near((qt - pt) * H, dy, 1);
        }
    Check(kept, "an offset through Counter comes out of the warp as it was, within a pixel (the warp curves over a name's width)");
    lens::Counter(0.95, 0.5, W, H, tanH, tanV, lens::Panini, 0.5, cm);
    Check(cm[0] > 1, "near the edge, where the warp squeezes, a name is drawn wider");
    // Taps: four reads over the patch of the picture each pixel covers
    std::vector<lens::Tapped> tv;
    lens::Taps(q, tanH, tanV, lens::Panini, 0, 8, 4, 0.25, tv);
    lens::Build(q, tanH, tanV, lens::Panini, 0, 8, 4, v, idx);
    bool same = tv.size() == v.size();
    for (size_t i = 0; same && i < v.size(); ++i) same = tv[i].x == v[i].x && tv[i].y == v[i].y && Near(tv[i].u, v[i].u, 1e-6) && Near(tv[i].v, v[i].v, 1e-6);
    Check(same, "set 4, the read by itself, is the grid's own point");
    const lens::Tapped& m = tv[22];
    Check(Near(m.tap[1][0] - m.tap[0][0], 0.5 / 3440, 1e-7) && Near(m.tap[2][1] - m.tap[0][1], 0.5 / 1440, 1e-7)
        && Near(m.tap[1][1], m.tap[0][1], 1e-7) && Near(m.tap[2][0], m.tap[0][0], 1e-7), "flat: the taps half a screen pixel apart, square to the screen");
    bool centred = true;
    for (const lens::Tapped& x : tv) {
        double cu = 0, cv = 0;
        for (int k = 0; k < 4; ++k) { cu += x.tap[k][0] / 4; cv += x.tap[k][1] / 4; }
        centred = centred && Near(cu, x.u, 1e-6) && Near(cv, x.v, 1e-6);
    }
    Check(centred, "the taps are centred on the point");
    // a picture twice the screen's size: a pixel centre is a texel corner, and the taps the four texels' middles
    const double px = 1000;   // a pixel's centre, x = 1000
    double ut = (px + 0.5) / 3440 * 6880;
    Check(Near(ut, 2001) && Near((m.tap[1][0] - m.tap[0][0]) * 6880, 1, 1e-4), "at twice the screen, each tap a texel's middle, one texel apart");
    lens::Taps(q, tanH, tanV, lens::Panini, 0.5, 8, 4, 0.25, tv);
    double middle = tv[22].tap[1][0] - tv[22].tap[0][0], side = tv[26].tap[1][0] - tv[26].tap[0][0];
    Check(middle < 0.5 / 3440 && side > 0.5 / 3440, "warped: the taps closer where the middle is enlarged, further where the edges are squeezed");
    lens::Taps(q, tanH, tanV, lens::Panini, 0.5, 8, 4, 0, tv);
    bool one = true;
    for (const lens::Tapped& x : tv) for (int k = 0; k < 4; ++k) one = one && x.tap[k][0] == x.u && x.tap[k][1] == x.v;
    Check(one, "spread 0 puts every tap on the point");
    std::vector<uint16_t> idx2;
    lens::Indices(8, 4, idx2);
    Check(idx2 == idx, "Indices gives Build's triangles");
    printf(failures ? "%d FAILED\n" : "lens warp: all checks passed\n", failures);
    return failures ? 1 : 0;
}
