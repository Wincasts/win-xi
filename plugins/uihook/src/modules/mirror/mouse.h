// The mouse on a mirrored menu: the game reads each mouse message in its own message loop, straight from the
// MSG (its position in lParam, client pixels), before Translate and DispatchMessage. That one call is taken
// (MIRROR_INPUT_PATTERN, the handler's first bytes, given its MSG by value), and a message whose place is on a
// menu an addon draws somewhere else, or larger, is given to the game at the same place on the game's own: so
// the game's hover, clicks and hit-tests work the menu where it is drawn. Ashita, imgui and every addon see the
// message as it was, the copy given to the game alone changed.
#pragma once
#include <windows.h>
#include <stdint.h>
#include <math.h>

#define MIRROR_INPUT_PATTERN "83 EC 2C 53 8B 5C 24 38 55 56 8B 74 24 44 57 8B 7C 24 4C 81 FB 0F 01 00 00"
#define MIRROR_INPUT_STOLEN 8 // sub esp,2C; push ebx; mov ebx,[esp+38]

// A message whose lParam is a place in the client area: moves, presses, releases, double clicks of every
// button. Not the wheel's, whose place is the screen's (the game scrolls where its own cursor is).
static bool MirrorMouseMessage(uint32_t message) {
    return message>=WM_MOUSEMOVE && message<=WM_XBUTTONDBLCLK && message!=WM_MOUSEWHEEL;
}

// A place, normalized to the viewport, on a menu as the addon drew it, moved to the same place on the game's own:
// the first drawn under it, of those renewed in the last MIRROR_REQUEST_FRAMES. False where it is on none.
static bool MirrorMapPoint(const MirrorShared& shared,float& x,float& y) {
    const uint32_t at=shared.MouseFrame;
    if (!at || shared.Frame-at>MIRROR_REQUEST_FRAMES) return false;
    const uint32_t count=shared.MouseCount<MIRROR_MOUSE ? shared.MouseCount : MIRROR_MOUSE;
    for (uint32_t i=0;i<count;i++) {
        const float* drawn=shared.Mouse[i];
        const float* native=shared.Mouse[i]+4;
        if (!(drawn[2]>drawn[0] && drawn[3]>drawn[1] && native[2]>native[0] && native[3]>native[1])) continue;
        if (x<drawn[0] || x>=drawn[2] || y<drawn[1] || y>=drawn[3]) continue;
        x=native[0]+(x-drawn[0])*(native[2]-native[0])/(drawn[2]-drawn[0]);
        y=native[1]+(y-drawn[1])*(native[3]-native[1])/(drawn[3]-drawn[1]);
        return true;
    }
    return false;
}

// A mouse message's place moved as MirrorMapPoint says, in a client area width by height; its pt (the screen's)
// moved as far. False, and the message as it was, where it is on no menu drawn elsewhere.
static bool MirrorMapMessage(const MirrorShared& shared,MSG& message,int width,int height) {
    if (!MirrorMouseMessage(message.message) || width<=0 || height<=0) return false;
    const int x=static_cast<short>(LOWORD(message.lParam)),y=static_cast<short>(HIWORD(message.lParam));
    float nx=(float(x)+0.5f)/float(width),ny=(float(y)+0.5f)/float(height);
    if (!MirrorMapPoint(shared,nx,ny)) return false;
    const int mx=int(floorf(nx*float(width))),my=int(floorf(ny*float(height)));
    message.lParam=MAKELPARAM(static_cast<WORD>(static_cast<short>(mx)),static_cast<WORD>(static_cast<short>(my)));
    message.pt.x+=mx-x; message.pt.y+=my-y;
    return true;
}
