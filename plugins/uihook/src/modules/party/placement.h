// Native Window::GetRect's read-only coordinate source. Flags +0x99 select menu-manager
// width/640 and height/480 scaling; ordinary windows use their raw pixel rectangle.
#pragma once
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
