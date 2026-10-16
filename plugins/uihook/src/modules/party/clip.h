// CPU clipping: D3D8 has no scissor rectangle. Clip each ImGui triangle, interpolating UVs/colour.
#pragma once
#include <stdint.h>
struct PartyVertex { float x, y, z, rhw; uint32_t color; float u, v; };
struct PartyClip { float left, top, right, bottom; };
static PartyVertex Mix(const PartyVertex& a, const PartyVertex& b, float t) {
    PartyVertex v = { a.x+(b.x-a.x)*t, a.y+(b.y-a.y)*t, 0, 1, 0,
        a.u+(b.u-a.u)*t, a.v+(b.v-a.v)*t };
    for (unsigned shift=0; shift<32; shift+=8) {
        float x = float((a.color>>shift)&255), y = float((b.color>>shift)&255);
        v.color |= uint32_t(x+(y-x)*t+0.5f)<<shift;
    }
    return v;
}
// At most seven vertices (a triangle clipped to a rectangle); returned as a convex polygon.
static unsigned ClipTriangleFull(const PartyVertex* triangle, PartyClip clip, PartyVertex* result) {
    PartyVertex a[12], b[12];
    for (unsigned i=0;i<3;i++) a[i]=triangle[i];
    unsigned count=3;
    const float edge[4]={clip.left,clip.right,clip.top,clip.bottom};
    for (unsigned e=0;e<4 && count;e++) {
        unsigned n=0;
        for (unsigned i=0;i<count;i++) {
            const PartyVertex& p=a[i]; const PartyVertex& q=a[(i+1)%count];
            float pv=e<2?p.x:p.y, qv=e<2?q.x:q.y;
            bool pin=(e==0||e==2)?pv>=edge[e]:pv<=edge[e];
            bool qin=(e==0||e==2)?qv>=edge[e]:qv<=edge[e];
            if (pin) b[n++]=p;
            if (pin!=qin) b[n++]=Mix(p,q,(edge[e]-pv)/(qv-pv));
        }
        count=n;
        for (unsigned i=0;i<n;i++) a[i]=b[i];
    }
    for (unsigned i=0;i<count;i++) result[i]=a[i];
    return count;
}
static unsigned ClipTriangle(const PartyVertex* triangle, PartyClip clip, PartyVertex* result) {
    // Most HUD geometry is wholly inside the window. Avoid four polygon passes for those triangles,
    // and reject triangles entirely on one side without interpolating or copying temporary polygons.
    unsigned any=0, common=15;
    for (unsigned i=0;i<3;i++) {
        const auto& v=triangle[i];
        unsigned code=(v.x<clip.left ? 1u:0u)|(v.x>clip.right ? 2u:0u)
            |(v.y<clip.top ? 4u:0u)|(v.y>clip.bottom ? 8u:0u);
        any|=code; common&=code;
    }
    if (common) return 0;
    if (!any) { for (unsigned i=0;i<3;i++) result[i]=triangle[i]; return 3; }
    return ClipTriangleFull(triangle,clip,result);
}
