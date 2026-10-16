// buffhook: the game's two functions that draw its status icons, by their first bytes.
#pragma once

// The status icon menu's callback for each icon: push ebp; push esi; push edi; call ...;
// mov ebp,[esp+10]; lea eax,[eax+eax*2]; ... The first 8 bytes are moved, a call among them at 3.
#define ICON_PATTERN "55 56 57 E8 ?? ?? ?? ?? 8B 6C 24 10 8D 04 40 8B CD 8D 34 80 8B 44 24 20 50 C1 E6 02 E8"
#define ICON_STOLEN 8
#define ICON_CALL_AT 3

// And for each icon's time: sub esp,10; push ebx; push esi; push edi; push C3 (the game's setting for
// status timers); call ... The first 6 bytes are moved, with no call among them.
#define TIME_PATTERN "83 EC 10 53 56 57 68 C3 00 00 00 E8 ?? ?? ?? ?? 83 C4 04 85 C0 0F 84 ?? ?? ?? ?? E8 ?? ?? ?? ?? 8B 7C 24 30"
#define TIME_STOLEN 6
#define TIME_CALL_AT -1
