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

// The status icon list, as the two callbacks are handed it: its window, the item the cursor is on, its
// statuses' numbers (one 16-bit number an item), and how many items it has
#define LIST_WINDOW 0x08
#define LIST_CURSOR 0x30
#define LIST_STATUSES 0x290
#define LIST_COUNT 0x374
#define LIST_ITEMS_MOST 32

// The window's setting for where its cursor (the hand) goes, from the corner of the item it is on:
// __thiscall (window, short x, short y). Only the status icon list sets it, to -5, -5, as it is made.
#define CURSOR_OFFSET_PATTERN "51 56 8D 71 14 8B CE E8 ?? ?? ?? ?? 85 C0 89 44 24 04 74 ?? 8D 44 24 04 8B CE 50 E8 ?? ?? ?? ?? 0F BF 08 83 E9 02 74 0D 8B 44 24 04 85 C0 75 E4 5E 59 C2 08 00 66 8B 4C 24 0C 66 8B 54 24 10 66 89 48 28 66 89 50 2A"
#define CURSOR_OFFSET_X -5
#define CURSOR_OFFSET_Y -5
#define CURSOR_AWAY -30000 // so far off the picture the hand is never seen
