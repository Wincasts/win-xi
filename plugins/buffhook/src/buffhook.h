// buffhook: what the buff addon and the plugin share. See README.md.
#pragma once

#include <stdint.h>

#define BUFF_VERSION 4
#define BUFF_TEXTURES 48   // the textures a bar can be drawn from
#define BUFF_QUADS 1024    // and the rectangles it can be drawn with
#define BUFF_DRAW_FRAMES 2 // how long what the addon wrote is good for, in frames
#define BUFF_SOLID 0xFFFFFFFF // a quad's Texture for one of its colour alone
// A texture's address the addon cannot give: imgui's font texture, which the plugin reads for itself
// as it draws. Its id is 64 bits, and a Lua integer in this game 32: once the texture is above 2 GB,
// as it can be after a while on Windows, Ashita cannot hand it to Lua at all.
#define BUFF_TEXTURE_FONT 1
#define BUFF_NO_STATUS 0xFFFF

// One rectangle of the bar: an icon, or a letter of a time.
struct BuffQuad {
    float X0, Y0, X1, Y1; // its corners, in pixels of the game's picture, from where the game puts its first icon
    float U0, V0, U1, V1; // and the same corners in its texture
    uint32_t Color;       // as 0xAARRGGBB
    uint32_t Texture;     // which of BuffShared::Textures, or BUFF_SOLID
};

// The block an addon reads and writes: found in this DLL by its first 16 bytes.
struct BuffShared {
    char Magic[16];
    uint32_t Version;     // BUFF_VERSION
    uint32_t Size;        // of this: an addon that has it otherwise does not read on
    uint32_t Hooked;      // 1 while the game's drawing of its status icons is in this plugin's hands

    // Written by the plugin
    uint32_t Frame;       // counts the frames presented
    uint32_t DrawnFrame;  // the Frame the game last drew its status icons in: 0 if it has not
    float OriginX;        // where it put the first of them then, in pixels of its picture
    float OriginY;
    float Width;          // and the size of the picture
    float Height;
    int32_t Cursor;       // which of them the game's cursor is on, for the buff selector
    uint32_t CursorStatus; // and its status, or BUFF_NO_STATUS
    uint32_t FontTexture; // imgui's font texture as BUFF_TEXTURE_FONT was last drawn from: 0 for none

    // Written by the addon. While SubmitFrame is within BUFF_DRAW_FRAMES of Frame, the quads are
    // drawn where the game would have drawn its icons, and the game draws none of its own. Sequence
    // goes up each time the quads or textures are written afresh: a bar handed over again as it was
    // leaves it, and the plugin draws from what it made of them last.
    uint32_t SubmitFrame;
    uint32_t Sequence;
    uint32_t Count;
    uint32_t Textures[BUFF_TEXTURES]; // Direct3D textures' addresses, BUFF_TEXTURE_FONT, or 0 for none
    BuffQuad Quads[BUFF_QUADS];
};
