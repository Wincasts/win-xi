// The game's chat rows: each a 60-byte header and 16-bit words, a glyph index (0 and up) for each character
// and a negative word for each colour code, decoded back to the bytes the game was given (CP932, with its
// 1E/1F colour codes). The client's encoder (the function that builds a row from a message) is transcribed
// here, and the decoder is its exact inverse, built from it once: glyph by glyph, the lowest SJIS code that
// draws it. The client's own glyph-to-character routine is not used: it is off by one at a band's start and
// maps some glyphs to other characters.
#pragma once
#include <stdint.h>
#include <string.h>

// A row's header as the drawer copies it onto the stack for the per-row draw: 60 bytes
struct ChatRowHeader { uint8_t bytes[60]; };
static_assert(sizeof(ChatRowHeader)==60, "a chat row's header");
#define CHAT_ROW_WORDS 994   // (2048 - 60) / 2: the most words a row of the 2 KB ring holds
#define CHAT_GLYPH_COUNT 0x2950 // one past the highest glyph a two-byte character encodes to
#define CHAT_GLYPH_ICON_FIRST 0x2115 // the game's pictographs, EF 1F to EF 4D: drawn from a table, not the font
#define CHAT_GLYPH_ICON_LAST 0x2143

// What the header says: the message's chat mode (+00), the words (+10), the cursor state (+12; 1 the
// cursor's row) and the marks (+15; 0x40 marked). False where the words would not fit a row.
struct ChatRowInfo { uint32_t mode=0, words=0, state=0, marks=0; };
static inline bool ChatRowFields(const ChatRowHeader& header,ChatRowInfo& out) {
    out.mode=header.bytes[0];
    out.words=uint32_t(header.bytes[0x10]) | (uint32_t(header.bytes[0x11])<<8);
    out.state=header.bytes[0x12]; out.marks=header.bytes[0x15];
    return out.words<=CHAT_ROW_WORDS;
}

// The glyph a two-byte character encodes to: the client's own piecewise formula on the JIS row and column
// (a single byte encodes to itself less 0x20). Transcribed from the private client; the fixture round-trips it.
static inline uint16_t ChatGlyphOf(uint8_t lead,uint8_t trail) {
    int row=(lead>0x9f ? int(lead)-0xb1 : int(lead)-0x71)*2|1;
    int col=trail;
    if (col>0x7f) col--;
    if (col>=0x9e) { row++; col-=0x7d; } else col-=0x1f;
    const uint32_t code=(uint32_t(row)<<8)|uint32_t(col);
    const int wide=col+94*row;
    if (code>=0x9320) return 0xcb;
    if (code>=0x7921) return uint16_t(wide-0xcd1);
    if (code>=0x5021) return uint16_t(wide-0xdec);
    if (code>=0x3021) return uint16_t(wide-0xdc1);
    const int narrow=col+row;
    struct Band { uint32_t from; int add; };
    static const Band bands[]={{0x2f21,0x21e},{0x2e21,0x271},{0x2d5f,0x351},{0x2d40,0x359},{0x2d21,0x35a},
        {0x2a21,0x223},{0x2921,0x276},{0x2821,0x203},{0x2751,0x1b3},{0x2721,0x1c2},{0x2641,0x18b},{0x2621,0x193},
        {0x2521,0x13e},{0x2421,0xec},{0x2361,0x93},{0x2341,0x99},{0x2330,0xa0}};
    for (const auto& band : bands) if (code>=band.from) return uint16_t(narrow+band.add);
    if (code==0x227f) return 0xf2;
    if (code>=0x2272) return uint16_t(narrow+0x56);
    if (code>=0x225c) return uint16_t(narrow+0x5d);
    if (code>=0x224a) return uint16_t(narrow+0x68);
    if (code>=0x223a) return uint16_t(narrow+0x70);
    return uint16_t(wide-0xbdf);
}
// Each glyph's character: the lowest SJIS code (lead 81-9F or E0-FC, trail 40-7E or 80-FC) encoding to it,
// built once from the encoder; 0 where no character does
static inline const uint16_t* ChatGlyphCodes() {
    static uint16_t codes[CHAT_GLYPH_COUNT];
    static bool built=false;
    if (!built) {
        memset(codes,0,sizeof(codes));
        for (unsigned lead=0x81;lead<=0xfc;lead++) {
            if (lead>0x9f && lead<0xe0) continue;
            for (unsigned trail=0x40;trail<=0xfc;trail++) {
                if (trail==0x7f) continue;
                const uint16_t glyph=ChatGlyphOf(uint8_t(lead),uint8_t(trail));
                if (glyph<CHAT_GLYPH_COUNT && !codes[glyph]) codes[glyph]=uint16_t((lead<<8)|trail);
            }
        }
        built=true;
    }
    return codes;
}
// The bytes a glyph stands for, as the game was given them: 1 or 2, or 0 for a glyph no character encodes
// to. Glyph 5F, DEL's, is what the game writes for 81 3F, the blank between an enemy's name's words: a space.
static inline unsigned ChatGlyphBytes(uint16_t glyph,uint8_t out[2]) {
    if (glyph<0x60) { out[0]=glyph==0x5f ? 0x20 : uint8_t(glyph+0x20); return 1; }
    if (glyph>=CHAT_GLYPH_ICON_FIRST && glyph<=CHAT_GLYPH_ICON_LAST) { out[0]=0xef; out[1]=uint8_t(0x1f+glyph-CHAT_GLYPH_ICON_FIRST); return 2; }
    if (glyph>=CHAT_GLYPH_COUNT) return 0;
    const uint16_t code=ChatGlyphCodes()[glyph];
    if (!code) return 0;
    out[0]=uint8_t(code>>8); out[1]=uint8_t(code); return 2;
}
// A row's words as the bytes the game was given: each glyph's, 1E or 1F and the colour's byte for each colour
// word (FF00 less the byte, FE00 less the byte), the 7F controls (negative words of a byte, which draw nothing)
// left out, a glyph no character encodes to a '?'. How many bytes were written; cut, whether room ran out.
static inline uint32_t ChatDecodeRow(const uint16_t* words,uint32_t count,char* out,uint32_t room,bool& cut) {
    uint32_t used=0; cut=false;
    for (uint32_t i=0;i<count;i++) {
        const uint16_t word=words[i];
        uint8_t bytes[2]; unsigned n=0;
        if (word<0x8000) { n=ChatGlyphBytes(word,bytes); if (!n) { bytes[0]='?'; n=1; } }
        else if (word>0xff00) continue;
        else if (word>0xfe00) { bytes[0]=0x1e; bytes[1]=uint8_t(0xff00-word); n=2; }
        else { const uint32_t v=0xfe00u-word; if (v>0xff) continue; bytes[0]=0x1f; bytes[1]=uint8_t(v); n=2; }
        if (used+n>room) { cut=true; break; }
        memcpy(out+used,bytes,n); used+=n;
    }
    return used;
}
