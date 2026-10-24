// The game's windows as they are drawn: what every module that changes or studies their drawing hears, and where.
//
// Window::Render draws a window in three parts: its frame, then its contents through its owner's vtable +10, then
// the cursor, row highlight and scrollbar. The one call to the contents is taken (WINDOW_CONTENT_PATTERN, five bytes,
// mov edx,[ecx]; call [edx+10], made a call to ours), so every draw is known to be the frame's, the contents', or a
// control's (WindowPhase). Text reaches the screen through three routines (TextRoute), each taken to be heard and
// passed straight on to the game's own. The native look (native.h) tells a window's frame by these; the census
// (census.h) lists what each window prints.
#pragma once
#include <stdint.h>

// The bitmap-font text routine: cdecl (x, y, text, colour, scale x, scale y, centred), the x it ends
// at returned. x and y are shorts (movsx), the rest of their stack words whatever the caller left. Each glyph is a
// Sprite::Draw. Its first eight bytes are whole instructions.
#define TEXT_BITMAP_PATTERN "83 EC 08 53 8B 5C 24 18 55 56 85 DB 75 0C 0F BF 44 24 18 5E 5D 5B 83 C4 08 C3"
#define TEXT_BITMAP_STOLEN 8
// Its scaled sibling: cdecl (x, y, text, colour, flag, scale x, scale y). Six bytes whole.
#define TEXT_SCALED_PATTERN "51 56 8B 74 24 14 85 F6 75 08 0F BF 44 24 0C 5E 59 C3 53 57 6A 00 E8"
#define TEXT_SCALED_STOLEN 6
// The rendered-font routine: thiscall on the font object (x, y, text, ?, colour, flags, scale x,
// scale y), ret 20. Seven bytes whole.
#define TEXT_FONT_PATTERN "83 EC 08 53 55 56 57 8B 7C 24 30 8B E9 8B C7 8B CF C1 F8 06 C1 F9 02 83 E0 03"
#define TEXT_FONT_STOLEN 7
enum TextRoute { TEXT_BITMAP, TEXT_SCALED, TEXT_FONT, TEXT_ROUTES };
static const char* const TextRouteNames[TEXT_ROUTES] = { "bitmap", "scaled", "font" };

// Window::Render's call to the contents, +20 into this pattern, checked to lie in Window::Render
#define WINDOW_CONTENT_PATTERN "8B 4D 0C 85 C9 74 ?? 8A 45 6A 84 C0 74 ?? 83 7D 10 0E 74 ?? 8B 11 FF 52 10"
#define WINDOW_CONTENT_AT 20
#define WINDOW_CONTENT_WITHIN 0x800

// Window fields, from Window::Render: its content owner, whose vtable +10 draws the contents, drawn
// while +6A is set and +10 is not E; cursor enabled +62, focused +63; its name at +46; the layout
// target's origin and size at +8C (four shorts, the game's units). Its name is its header's (+4), at +46.
#define WINDOW_OWNER 0x0c
#define WINDOW_KIND 0x10
#define WINDOW_DRAWS 0x6a
#define WINDOW_CURSOR 0x62
#define WINDOW_FOCUS 0x63
#define WINDOW_HEADER 0x04
#define WINDOW_NAME 0x46
#define WINDOW_TARGET 0x8c

// What a draw belongs to. An element is one of the window's own sprites, drawn by Window::Render before the
// contents from its list of elements: the labels of a menu whose words are pictures (the main menu, the command
// menu), its buttons and icons; the one the cursor is on drawn tinted.
enum WindowPhase : uint32_t { PHASE_FRAME, PHASE_CONTENT, PHASE_CURSOR, PHASE_ELEMENT, PHASE_SCROLL, PHASE_AFTER };
