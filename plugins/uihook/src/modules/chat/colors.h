// The game's chat colours, read as it has them: each chat mode's category and each category's colour (what the
// game draws a message in, and what a 1F code names), and the inline palette's first colours (1E 00 to 1E 10;
// a 1E code past those names a category). The user's configured colours live in these tables. Nothing is written.
#pragma once
#include <windows.h>
#include <stdint.h>
#include <string.h>
#include "chat.h"
#include "windows.h"

// The category colour lookup (032E9D00): entries of a category byte and, at +4, its colour, 8 bytes each, ended
// by a zero category; the table's address is the first instruction's immediate, the byte it loads
#define CHAT_CATEGORY_COLOR_PATTERN "A0 ?? ?? ?? ?? 33 C9 84 C0 74 1A 0F BF 54 24 04 25 FF 00 00 00 3B C2 74 12 8A 04 CD"
// The inline palette lookup (03321FD0): slots 0 to 16 from a table of 17 colours (its address at +18), others
// as categories
#define CHAT_INLINE_PALETTE_PATTERN "0F BF 44 24 04 99 33 C2 2B C2 83 F8 11 7D 08 8B 04 85"
#define CHAT_INLINE_COLORS 17
#define CHAT_CATEGORY_ENTRIES 256 // read no further than this many categories

struct ChatColorTables {
    uint8_t* modes=nullptr;      // the chat-mode table (mode word, category byte, one more)
    uint8_t* categories=nullptr; // the category colour table
    uint8_t* palette=nullptr;    // the inline palette
    bool cached=false;
    uint32_t serial=0;
    uint32_t inlineColors[CHAT_INLINE_COLORS]={};
    uint32_t categoryColors[256]={};
    uint8_t modeCategory[256]={};
    bool Ready() const { return modes && categories && palette; }
    void Clear() { *this=ChatColorTables(); }
};

static bool DiscoverChatColors(uint8_t* begin,size_t size,ChatColorTables& out) {
    out.Clear();
    if (!begin || size<64) return false;
    auto* lookup=UniquePattern(begin,size,CHAT_MODE_LOOKUP_PATTERN);
    auto* category=UniquePattern(begin,size,CHAT_CATEGORY_COLOR_PATTERN);
    auto* palette=UniquePattern(begin,size,CHAT_INLINE_PALETTE_PATTERN);
    if (!lookup || !category || !palette || size_t(lookup-begin)>size-5 || size_t(category-begin)>size-5 || size_t(palette-begin)>size-22) return false;
    auto* modes=ChatWindowsInside(begin,size,lookup+1,4);
    auto* categories=ChatWindowsInside(begin,size,category+1,8);
    auto* colors=ChatWindowsInside(begin,size,palette+18,4*CHAT_INLINE_COLORS);
    if (!modes || !categories || !colors) return false;
    out.modes=modes; out.categories=categories; out.palette=colors;
    return true;
}
// The tables as they are this frame: each mode's category, each category's colour and the inline palette, published
// with a serial that moves only when any of it changes. Nothing published where any of it cannot be read.
static void SampleChatColors(ChatColorTables& tables,ChatShared& shared,uint32_t frame) {
    shared.ColorFrame=0;
    if (!tables.Ready()) return;
    uint32_t inlineColors[CHAT_INLINE_COLORS]; uint32_t categoryColors[256]={}; uint8_t modeCategory[256]={};
    if (!ChatRead(tables.palette,inlineColors,sizeof(inlineColors))) return;
    // each table copied whole, as far as it can be read, then walked to its end: an entry past what was read fails
    uint8_t categoryTable[CHAT_CATEGORY_ENTRIES*8], modeTable[CHAT_MODE_ENTRIES*4];
    const size_t categoryBytes=ChatReadSpan(tables.categories,categoryTable,sizeof(categoryTable));
    for (unsigned i=0;i<CHAT_CATEGORY_ENTRIES;i++) {
        if ((i+1)*8>categoryBytes) return;
        const uint8_t* entry=categoryTable+i*8;
        if (!entry[0]) break;
        if (!categoryColors[entry[0]]) memcpy(&categoryColors[entry[0]],entry+4,4); // the first entry for a category counts
    }
    const size_t modeBytes=ChatReadSpan(tables.modes,modeTable,sizeof(modeTable));
    for (unsigned i=0;i<CHAT_MODE_ENTRIES;i++) {
        if ((i+1)*4>modeBytes) return;
        const uint8_t* entry=modeTable+i*4;
        uint16_t word=0; memcpy(&word,entry,2);
        if (!word) break;
        if (word<256 && !modeCategory[word]) modeCategory[word]=entry[2];
    }
    if (!tables.cached || memcmp(inlineColors,tables.inlineColors,sizeof(inlineColors)) || memcmp(categoryColors,tables.categoryColors,sizeof(categoryColors))
        || memcmp(modeCategory,tables.modeCategory,sizeof(modeCategory))) {
        memcpy(tables.inlineColors,inlineColors,sizeof(inlineColors)); memcpy(tables.categoryColors,categoryColors,sizeof(categoryColors));
        memcpy(tables.modeCategory,modeCategory,sizeof(modeCategory));
        tables.cached=true; tables.serial++;
    }
    memcpy(shared.InlineColors,tables.inlineColors,sizeof(tables.inlineColors));
    memcpy(shared.CategoryColors,tables.categoryColors,sizeof(tables.categoryColors));
    memcpy(shared.ModeCategory,tables.modeCategory,sizeof(tables.modeCategory));
    shared.ColorSerial=tables.serial;
    shared.ColorFrame=frame;
}
