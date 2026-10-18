// The first log window's history, read once when an addon asks: the game's ring of 100 lines (the first window
// owner's +18), each a 60-byte header and its glyph words, decoded back to the bytes the game was given. Recognition
// only: nothing is called or written. The game keeps each message as the lines it wrapped it into; a line after a
// message's first has its header's +38 cleared and its flags (+15) masked to 0xB0 (the wrap, 032E8CE0), published
// as they are so an addon may tell.
#pragma once
#include "chat.h"
#include "glyphs.h"

// The ring: +14 the newest line's index, +16 the oldest's, +1A how many, then 100 lines of 2 KB from +20 (the
// insert 032E7280 and the steps 032E92E0 / 032E9330)
#define CHAT_RING_LINES 100
#define CHAT_RING_LINE_BYTES 0x800
#define CHAT_HISTORY_TEXT 65536
struct ChatHistoryLine { uint32_t Offset, Length, Mode, Serial, Flags, Extra; };
struct ChatHistoryShared {
    char Magic[16];
    uint32_t Version, Size, Frame, Supported;
    volatile uint32_t RequestFrame; // Lua: a read is wanted (served once for each new request)
    uint32_t Serial, ReadFrame;     // moved with each read served, and the frame it was
    uint32_t Count, Used;           // lines read, oldest first, and their text's bytes
    ChatHistoryLine Lines[CHAT_RING_LINES];
    char Text[CHAT_HISTORY_TEXT];   // each line's bytes at its Offset: CP932 with the game's 1E/1F colour codes
};
static_assert(sizeof(ChatHistoryShared)==16+4*9+24*CHAT_RING_LINES+CHAT_HISTORY_TEXT,"history ABI 1");

// The ring's lines, oldest to newest, into out: its mode word (+00, whole), serial (+0C), word count (+10), flags
// (+15) and +38, and its words decoded. False, and nothing published, where the ring's indices make no sense or its
// header cannot be read; a line whose words cannot be read is published empty.
static bool ChatReadHistory(const uint8_t* ring,ChatHistoryShared& out) {
    out.Count=out.Used=0;
    int16_t indices[4]={};
    if (!ring || !ChatRead(ring+0x14,indices,8)) return false;
    const int newest=indices[0],oldest=indices[1],count=indices[3];
    if (newest<0 || newest>=CHAT_RING_LINES || oldest<0 || oldest>=CHAT_RING_LINES || count<0 || count>CHAT_RING_LINES) return false;
    if (!count) return true;
    static uint16_t words[CHAT_ROW_WORDS];
    int at=oldest;
    for (int n=0;n<CHAT_RING_LINES;n++) {
        const uint8_t* line=ring+0x20+size_t(at)*CHAT_RING_LINE_BYTES;
        ChatRowHeader header;
        if (!ChatRead(line,header.bytes,sizeof(header.bytes))) return false;
        ChatRowInfo info; ChatRowFields(header,info);
        ChatHistoryLine& entry=out.Lines[out.Count];
        entry=ChatHistoryLine();
        entry.Mode=uint32_t(header.bytes[0]) | (uint32_t(header.bytes[1])<<8);
        memcpy(&entry.Serial,header.bytes+0x0c,4);
        entry.Flags=header.bytes[0x15];
        memcpy(&entry.Extra,header.bytes+0x38,4);
        entry.Offset=out.Used;
        if (info.words && info.words<=CHAT_ROW_WORDS && ChatRead(line+0x3c,words,info.words*2)) {
            bool cut=false;
            entry.Length=ChatDecodeRow(words,info.words,out.Text+out.Used,CHAT_HISTORY_TEXT-out.Used,cut);
            out.Used+=entry.Length;
        }
        out.Count++;
        if (at==newest || out.Count>=CHAT_RING_LINES) break;
        at=(at+1)%CHAT_RING_LINES;
    }
    return true;
}
