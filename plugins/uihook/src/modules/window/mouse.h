// The game's mouse: it reads each mouse message in its own message loop, straight from the MSG (its place in lParam,
// client pixels), before Translate and DispatchMessage. That one call is taken (GAME_INPUT_PATTERN, the handler's
// first bytes, given its MSG by value), so a message can be given to the game at another place, or kept from it,
// while Ashita, imgui and every addon see it as it was: the copy given to the game alone is changed. The native look
// (nativemodule.h) moves a message on a window drawn moved to the same place on the game's own.
#pragma once
#include <windows.h>
#include <stdint.h>
#include <math.h>

#define GAME_INPUT_PATTERN "83 EC 2C 53 8B 5C 24 38 55 56 8B 74 24 44 57 8B 7C 24 4C 81 FB 0F 01 00 00"
#define GAME_INPUT_STOLEN 8 // sub esp,2C; push ebx; mov ebx,[esp+38]

// A message whose lParam is a place in the client area: moves, presses, releases, double clicks of every
// button. Not the wheel's, whose place is the screen's (the game scrolls where its own cursor is).
static bool MouseMessage(uint32_t message) {
    return message>=WM_MOUSEMOVE && message<=WM_XBUTTONDBLCLK && message!=WM_MOUSEWHEEL;
}
// A button let go: always given to the game, so that no press it was given is left held
static bool MouseRelease(uint32_t message) {
    return message==WM_LBUTTONUP || message==WM_RBUTTONUP || message==WM_MBUTTONUP || message==WM_XBUTTONUP;
}
// A message's place moved to (x, y) in the client area, its pt (the screen's) as far
static void MouseMove(MSG& message,int x,int y) {
    const int was[2]={static_cast<short>(LOWORD(message.lParam)),static_cast<short>(HIWORD(message.lParam))};
    message.lParam=MAKELPARAM(static_cast<WORD>(static_cast<short>(x)),static_cast<WORD>(static_cast<short>(y)));
    message.pt.x+=x-was[0]; message.pt.y+=y-was[1];
}
