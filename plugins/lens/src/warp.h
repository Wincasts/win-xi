// The world laid onto the screen through a Panini or a cylindrical projection. The game draws its world to a texture
// with a flat (rectilinear) projection and copies it onto the back buffer with one quad; lens draws a
// grid in its place whose texture coordinates come from the Panini mapping, so the edges are squeezed
// back from the stretch a flat projection gives them at a wide field of view, and verticals stay
// straight. Pure: no Direct3D, so the check can run it.
//
// Panini with distance d (Sharpless et al.): a ray at azimuth phi and height t (its rise over its
// distance from the vertical axis) lands at x = S sin phi, y = S t, with S = (d + 1) / (d + cos phi).
// d = 0 is the flat projection itself; d = 1 is the classic Panini. The width is kept: the source's
// horizontal edge lands on the screen's, and the height follows at the source's own proportions, which
// puts the screen's corners exactly on the source's corners. The middle is enlarged by as much as the
// edges are squeezed, so a wider field of view in the game keeps as much in view up and down.
//
// Cylindrical: a ray at azimuth phi and height t lands at x = phi, y = t, every degree across the
// same width. It squeezes the edges more than Panini, and lines running toward the middle bow. At its
// own proportions its corners would need rays from beyond the flat picture, so it gives up a little
// width instead: the screen's edge is at the azimuth phiE where the corner's ray is the picture's
// corner (phiE / cos phiE = tanH). Its strength blends from the flat picture (0) to it (1).
#pragma once
#include <math.h>
#include <stdint.h>
#include <vector>

namespace lens {

enum Mode { Panini, Cylindrical };

// The game's copy quad's vertex: XYZRHW, DIFFUSE, TEX1 (FVF 0x144).
struct Vertex { float x, y, z, rhw; uint32_t color; float u, v; };

// Where on the Panini plane the ray at azimuth phi, on the horizon, lands.
inline double PaniniX(double phi, double d) { return (d + 1) * sin(phi) / (d + cos(phi)); }

// The ray landing at (px, py) on the Panini plane, as the flat projection's tangents (tx, ty): where it
// lies in the source picture, 1 being 45 degrees off the middle.
inline void PaniniInverse(double px, double py, double d, double& tx, double& ty) {
    double k = px * px / ((d + 1) * (d + 1));
    double disc = k * k * d * d - (k + 1) * (k * d * d - 1);
    double c = (-k * d + sqrt(disc > 0 ? disc : 0)) / (k + 1);   // cos phi
    if (c > 1) c = 1;
    if (c < 1e-6) c = 1e-6;
    double phi = (px < 0 ? -1 : 1) * acos(c);
    double s = (d + 1) / (d + c);
    tx = tan(phi);
    ty = (py / s) / c;
}

// The azimuth of the cylindrical view's edge: phi / cos phi = tanH, by halving.
inline double CylinderEdge(double tanH) {
    double lo = 0, hi = atan(tanH);
    for (int i = 0; i < 60; ++i) {
        double mid = (lo + hi) / 2;
        if (mid / cos(mid) < tanH) lo = mid; else hi = mid;
    }
    return lo;
}

// Where the screen point (s, t), each 0 to 1 across the quad, reads the source, each 0 to 1 across
// the picture: tanH and tanV are the picture's half fields of view as tangents.
inline void SourceOf(double s, double t, double tanH, double tanV, Mode mode, double strength, double& us, double& vs) {
    double tx, ty;
    if (mode == Panini) {
        double xEdge = PaniniX(atan(tanH), strength);   // the source's horizontal edge on the Panini plane
        double yEdge = xEdge * tanV / tanH;             // the screen's top, at the source's proportions
        PaniniInverse(xEdge * (2 * s - 1), yEdge * (2 * t - 1), strength, tx, ty);
        us = 0.5 + 0.5 * tx / tanH;
        vs = 0.5 + 0.5 * ty / tanV;
        return;
    }
    double phiE = CylinderEdge(tanH);
    double phi = phiE * (2 * s - 1), y = phiE * tanV / tanH * (2 * t - 1);
    tx = tan(phi);
    ty = y / cos(phi);
    us = s + strength * (0.5 + 0.5 * tx / tanH - s);
    vs = t + strength * (0.5 + 0.5 * ty / tanV - t);
}

// Where the warp shows what the flat picture has at (s0, t0), each 0 to 1 across the picture: the
// screen point (s, t) whose SourceOf is (s0, t0). Panini by its forward mapping; cylindrical, a blend,
// by Newton's method from the point itself. For overlays drawn over the world, and anything else that
// places itself by the flat projection.
inline void ScreenOf(double s0, double t0, double tanH, double tanV, Mode mode, double strength, double& s, double& t) {
    if (mode == Panini) {
        double xEdge = PaniniX(atan(tanH), strength), yEdge = xEdge * tanV / tanH;
        double tx = (2 * s0 - 1) * tanH, ty = (2 * t0 - 1) * tanV;
        double phi = atan(tx), height = ty * cos(phi);
        double scale = (strength + 1) / (strength + cos(phi));
        s = 0.5 + 0.5 * scale * sin(phi) / xEdge;
        t = 0.5 + 0.5 * scale * height / yEdge;
        return;
    }
    s = s0; t = t0;
    for (int i = 0; i < 12; ++i) {
        double us, vs, ua, va, ub, vb;
        const double h = 1e-5;
        SourceOf(s, t, tanH, tanV, mode, strength, us, vs);
        double fu = us - s0, fv = vs - t0;
        if (fabs(fu) < 1e-9 && fabs(fv) < 1e-9) break;
        SourceOf(s + h, t, tanH, tanV, mode, strength, ua, va);
        SourceOf(s, t + h, tanH, tanV, mode, strength, ub, vb);
        double a = (ua - us) / h, b = (ub - us) / h, c = (va - vs) / h, d = (vb - vs) / h;
        double det = a * d - b * c;
        if (fabs(det) < 1e-12) break;
        s -= (d * fu - b * fv) / det;
        t -= (a * fv - c * fu) / det;
    }
}

// What undoes the warp's stretch around a point of the flat picture, for something drawn into the
// picture that should come out of the warp at its own shape (a name over a head): the 2x2 matrix m
// (row-major) to put each offset (dx, dy) from the point through, in pixels of a width by height
// picture, before drawing. The warp near the point is its Jacobian J; m is J's inverse. The identity
// without a warp, and where J cannot be inverted.
inline void Counter(double s0, double t0, double width, double height, double tanH, double tanV, Mode mode, double strength, double m[4]) {
    m[0] = 1; m[1] = 0; m[2] = 0; m[3] = 1;
    if (strength <= 0 || width <= 0 || height <= 0) return;
    const double h = 1e-4;
    double sa, ta, sb, tb, sc, tc, sd, td;
    ScreenOf(s0 + h, t0, tanH, tanV, mode, strength, sa, ta);
    ScreenOf(s0 - h, t0, tanH, tanV, mode, strength, sb, tb);
    ScreenOf(s0, t0 + h, tanH, tanV, mode, strength, sc, tc);
    ScreenOf(s0, t0 - h, tanH, tanV, mode, strength, sd, td);
    // in pixels: x = s * width, y = t * height, on both sides
    double a = (sa - sb) / (2 * h), b = (sc - sd) / (2 * h) * width / height;
    double c = (ta - tb) / (2 * h) * height / width, d = (tc - td) / (2 * h);
    double det = a * d - b * c;
    if (fabs(det) < 1e-9) return;
    m[0] = d / det; m[1] = -b / det; m[2] = -c / det; m[3] = a / det;
}

// The game's quad: its screen rectangle and the texture coordinates at its top left and bottom right,
// with what each vertex carries besides.
struct Quad { float left, top, right, bottom, u0, v0, u1, v1, z, rhw; uint32_t color; };

// The quad from the game's four vertices, whichever order the strip has them in.
inline Quad QuadOf(const Vertex* v) {
    int tl = 0, br = 0;
    for (int i = 1; i < 4; ++i) {
        if (v[i].x + v[i].y < v[tl].x + v[tl].y) tl = i;
        if (v[i].x + v[i].y > v[br].x + v[br].y) br = i;
    }
    return { v[tl].x, v[tl].y, v[br].x, v[br].y, v[tl].u, v[tl].v, v[br].u, v[br].v, v[0].z, v[0].rhw, v[0].color };
}

// The grid in the quad's place: (cols + 1) x (rows + 1) vertices and a triangle list over them. tanH
// and tanV are the source's half fields of view as tangents (1 / _11 and 1 / _22 of its projection);
// strength is the Panini distance, or for cylindrical how far from the flat picture to go, 0 to 1.
inline void Build(const Quad& q, double tanH, double tanV, Mode mode, double strength, int cols, int rows, std::vector<Vertex>& vertices, std::vector<uint16_t>& indices) {
    vertices.clear();
    indices.clear();
    for (int r = 0; r <= rows; ++r) {
        for (int c = 0; c <= cols; ++c) {
            double s = double(c) / cols, t = double(r) / rows;
            double us, vs;
            SourceOf(s, t, tanH, tanV, mode, strength, us, vs);
            Vertex v;
            v.x = float(q.left + (q.right - q.left) * s);
            v.y = float(q.top + (q.bottom - q.top) * t);
            v.z = q.z; v.rhw = q.rhw; v.color = q.color;
            v.u = float(q.u0 + (q.u1 - q.u0) * us);
            v.v = float(q.v0 + (q.v1 - q.v0) * vs);
            vertices.push_back(v);
        }
    }
    for (int r = 0; r < rows; ++r) {
        for (int c = 0; c < cols; ++c) {
            uint16_t a = uint16_t(r * (cols + 1) + c), b = uint16_t(a + 1), e = uint16_t(a + cols + 1), f = uint16_t(e + 1);
            indices.insert(indices.end(), { a, b, e, b, f, e });
        }
    }
}

// How much of the source's height the middle of the screen shows, 1 being all of it: the price of
// the squeezed edges.
inline double MiddleHeight(double tanH, double tanV, Mode mode, double strength) {
    double us, vs;
    SourceOf(0.5, 0, tanH, tanV, mode, strength, us, vs);
    return 1 - 2 * vs;
}

// How far across the screen shows, as the tangent of its half: tanH unless cylindrical gives some up.
inline double ShownAcross(double tanH, double tanV, Mode mode, double strength) {
    double us, vs;
    SourceOf(1, 0.5, tanH, tanV, mode, strength, us, vs);
    return (2 * us - 1) * tanH;
}

} // namespace lens
