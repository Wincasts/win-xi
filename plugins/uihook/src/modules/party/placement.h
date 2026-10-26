// Native Window::GetRect's read-only coordinate source. Flags +0x99 select menu-manager
// width/640 and height/480 scaling; ordinary windows use their raw pixel rectangle.
#pragma once
#include <string.h>
#define RECT_PATTERN "83 EC 0C 56 8B F1 8A 86 99 00 00 00 84 C0 0F 84 ?? ?? ?? ?? 8D 44 24 08 57 8D 4C 24 08 50 51 B9 ?? ?? ?? ?? E8 ?? ?? ?? ?? 0F BF 56 3A"
#define RECT_MANAGER_AT 32
struct NativeRect { float Left, Top, Right, Bottom; uint32_t Frame; };
static bool MakeNativeRect(const int16_t* rect,bool scaled,int menuWidth,int menuHeight,
    unsigned viewportWidth,unsigned viewportHeight,uint32_t frame,NativeRect& out) {
    if (!viewportWidth || !viewportHeight || rect[2]<=rect[0] || rect[3]<=rect[1]) return false;
    if (scaled && (menuWidth<=0 || menuHeight<=0 || menuWidth>16384 || menuHeight>16384)) return false;
    float sx=scaled ? float(menuWidth)/640.0f : 1.0f;
    float sy=scaled ? float(menuHeight)/480.0f : 1.0f;
    out={rect[0]*sx/viewportWidth,rect[1]*sy/viewportHeight,
        rect[2]*sx/viewportWidth,rect[3]*sy/viewportHeight,frame};
    return true;
}
// Whether a draw of pre-transformed vertices (x and y the first two floats of each) lies wholly outside a
// window's rectangle in pixels, grown by margin on every side: none of it overlaps the window. A draw with no
// vertices, or any vertex not a finite position, is not taken to be outside.
static bool DrawOutside(const void* data,unsigned count,unsigned stride,const NativeRect& rect,
    unsigned viewportWidth,unsigned viewportHeight,float margin) {
    if (!data || !count || stride<8) return false;
    const float left=rect.Left*viewportWidth-margin, top=rect.Top*viewportHeight-margin;
    const float right=rect.Right*viewportWidth+margin, bottom=rect.Bottom*viewportHeight+margin;
    float minX=0, minY=0, maxX=0, maxY=0;
    for (unsigned i=0;i<count;i++) {
        float xy[2]; memcpy(xy,static_cast<const uint8_t*>(data)+size_t(i)*stride,sizeof(xy));
        if (!(xy[0]==xy[0]) || !(xy[1]==xy[1]) || xy[0]>1e7f || xy[0]<-1e7f || xy[1]>1e7f || xy[1]<-1e7f) return false;
        if (!i || xy[0]<minX) minX=xy[0];
        if (!i || xy[1]<minY) minY=xy[1];
        if (!i || xy[0]>maxX) maxX=xy[0];
        if (!i || xy[1]>maxY) maxY=xy[1];
    }
    return maxX<=left || minX>=right || maxY<=top || minY>=bottom;
}
