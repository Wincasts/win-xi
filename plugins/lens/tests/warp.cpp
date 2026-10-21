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
    lens::Build(q, tanH, tanV, 0, 8, 4, v, idx);
    bool flat = true;
    for (int r = 0; r <= 4; ++r) for (int c = 0; c <= 8; ++c) {
        const lens::Vertex& x = v[r * 9 + c];
        flat = flat && Near(x.u, c / 8.0) && Near(x.v, r / 4.0);
    }
    Check(flat, "strength 0 is the game's own picture");
    Check(v.size() == 45 && idx.size() == 8 * 4 * 6 && idx[0] == 0 && idx[1] == 1 && idx[2] == 9 && idx[5] == 9, "the grid's size and its first triangles");

    for (double d : { 0.25, 0.5, 1.0 }) {
        lens::Build(q, tanH, tanV, d, 8, 4, v, idx);
        bool corners = Near(v[0].u, 0) && Near(v[0].v, 0) && Near(v[8].u, 1) && Near(v[44].u, 1) && Near(v[44].v, 1) && Near(v[36].v, 1);
        Check(corners, d == 1.0 ? "corners on the source's corners at 1" : d == 0.5 ? "corners on the source's corners at 0.5" : "corners on the source's corners at 0.25");
    }
    lens::Build(q, tanH, tanV, 1, 8, 4, v, idx);
    double mh = lens::MiddleHeight(tanH, 1);
    Check(Near(v[4].v, 0.5 - 0.5 * mh) && Near(v[40].v, 0.5 + 0.5 * mh), "the middle column shows MiddleHeight of the source");
    Check(Near(v[22].u, 0.5) && Near(v[22].v, 0.5), "the middle stays the middle");
    Check(v[1].u > 1 / 8.0 && v[3].u > 3 / 8.0 , "the edges squeezed: the outer columns take in more of the source");
    Check(Near(lens::MiddleHeight(tanH, 0), 1) && lens::MiddleHeight(tanH, 0.5) > lens::MiddleHeight(tanH, 1), "stronger enlarges the middle more");

    bool round = true;
    for (double phi = -1.2; phi <= 1.2; phi += 0.3) for (double d : { 0.0, 0.5, 1.0 }) {
        double t = 0.4, s = (d + 1) / (d + cos(phi));
        double tx, ty;
        lens::PaniniInverse(lens::PaniniX(phi, d), s * t, d, tx, ty);
        round = round && Near(tx, tan(phi)) && Near(ty, t / cos(phi));
    }
    Check(round, "the inverse undoes the forward mapping");
    printf(failures ? "%d FAILED\n" : "lens warp: all checks passed\n", failures);
    return failures ? 1 : 0;
}
