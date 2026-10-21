// The world laid onto the screen through a Panini projection. The game draws its world to a texture
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
#pragma once
#include <math.h>
#include <stdint.h>
#include <vector>

namespace lens {

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
// and tanV are the source's half fields of view as tangents (1 / _11 and 1 / _22 of its projection),
// d the Panini distance.
inline void Build(const Quad& q, double tanH, double tanV, double d, int cols, int rows, std::vector<Vertex>& vertices, std::vector<uint16_t>& indices) {
    vertices.clear();
    indices.clear();
    double halfH = atan(tanH);
    double xEdge = PaniniX(halfH, d);          // the source's horizontal edge on the Panini plane
    double yEdge = xEdge * tanV / tanH;        // the screen's top, at the source's proportions
    for (int r = 0; r <= rows; ++r) {
        for (int c = 0; c <= cols; ++c) {
            double s = double(c) / cols, t = double(r) / rows;
            double tx, ty;
            PaniniInverse(xEdge * (2 * s - 1), yEdge * (2 * t - 1), d, tx, ty);
            double us = 0.5 + 0.5 * tx / tanH, vs = 0.5 + 0.5 * ty / tanV;
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
inline double MiddleHeight(double tanH, double d) {
    double halfH = atan(tanH);
    return PaniniX(halfH, d) / tanH;
}

} // namespace lens
