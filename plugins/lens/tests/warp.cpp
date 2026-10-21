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
    double ms, mt;
    lens::ScreenOf(0.5, 0.5, tanH, tanV, lens::Panini, 0.25, ms, mt);
    Check(Near(ms, 0.5) && Near(mt, 0.5), "the middle stays where it is");
    lens::ScreenOf(0.95, 0.5, tanH, tanV, lens::Panini, 0.25, ms, mt);
    Check(ms > 0.95 && Near(mt, 0.5), "a point near the edge of the picture is shown nearer the edge of the screen");
    printf(failures ? "%d FAILED\n" : "lens warp: all checks passed\n", failures);
    return failures ? 1 : 0;
}
