// The first log window's history: the game's ring read oldest to newest, its lines decoded.
#include <stdio.h>
#include <stdlib.h>
#include "../src/modules/party/detour.h"
#include "../src/modules/party/target.h"
#include "../src/modules/chat/history.h"
static int failures=0;
static void Check(bool ok,const char* text) { printf("%s %s\n",ok?"ok":"FAIL",text); if(!ok) ++failures; }
// A line of the ring: its mode word, serial, flags, +38 and text (single bytes encode to themselves less 0x20)
static void Line(uint8_t* ring,int at,uint16_t mode,uint32_t serial,uint8_t flags,uint32_t extra,const char* text) {
    uint8_t* line=ring+0x20+size_t(at)*CHAT_RING_LINE_BYTES;
    memset(line,0,CHAT_RING_LINE_BYTES);
    memcpy(line,&mode,2); memcpy(line+0x0c,&serial,4); line[0x15]=flags; memcpy(line+0x38,&extra,4);
    uint16_t count=0;
    for (const char* c=text;*c;c++) {
        uint16_t word=uint16_t(uint8_t(*c)-0x20);
        if (*c=='\x1f') { word=uint16_t(0xfe00-uint8_t(c[1])); c++; }
        memcpy(line+0x3c+count*2,&word,2); count++;
    }
    memcpy(line+0x10,&count,2);
}
static void Indices(uint8_t* ring,int16_t newest,int16_t oldest,int16_t count) {
    memcpy(ring+0x14,&newest,2); memcpy(ring+0x16,&oldest,2); memcpy(ring+0x1a,&count,2);
}
static bool Text(const ChatHistoryShared& h,uint32_t i,const char* wanted) {
    return h.Lines[i].Length==strlen(wanted) && !memcmp(h.Text+h.Lines[i].Offset,wanted,h.Lines[i].Length);
}
int main() {
    auto* ring=static_cast<uint8_t*>(calloc(1,0x20+CHAT_RING_LINES*CHAT_RING_LINE_BYTES));
    static ChatHistoryShared history={};
    Indices(ring,0,0,0);
    Check(ChatReadHistory(ring,history) && history.Count==0,"an empty ring: nothing, and no failure");
    // wrapping past the last line: 98, 99, then 0
    Line(ring,98,1,7,0x41,0x1234,"Ann : hi"); Line(ring,99,1,8,0x00,0,"there"); Line(ring,0,0x8005,9,0x10,0,"\x1f\x05(Bo) yo");
    Indices(ring,0,98,3);
    Check(ChatReadHistory(ring,history) && history.Count==3,"three lines, oldest to newest, round the ring's end");
    Check(Text(history,0,"Ann : hi") && Text(history,1,"there") && Text(history,2,"\x1f\x05(Bo) yo"),"each decoded to the bytes the game was given, colour codes kept");
    Check(history.Lines[0].Mode==1 && history.Lines[2].Mode==0x8005 && history.Lines[0].Serial==7 && history.Lines[2].Serial==9,"each line's whole mode word and serial");
    Check(history.Lines[0].Flags==0x41 && history.Lines[0].Extra==0x1234 && history.Lines[1].Flags==0 && history.Lines[1].Extra==0,
        "its flags and +38, as the game leaves them on a message's first line and clears on the rest");
    Check(history.Used==8+5+9,"the text packed one after another");
    Indices(ring,100,0,3); Check(!ChatReadHistory(ring,history) && history.Count==0,"an index past the ring: nothing");
    Indices(ring,0,-1,3); Check(!ChatReadHistory(ring,history),"a negative index: nothing");
    Check(!ChatReadHistory(nullptr,history),"no ring: nothing");
    // a full ring: all 100, from the oldest round to the newest
    for (int i=0;i<CHAT_RING_LINES;i++) Line(ring,i,1,uint32_t(i),0,0,"x");
    Indices(ring,41,42,100);
    Check(ChatReadHistory(ring,history) && history.Count==100 && history.Lines[0].Serial==42 && history.Lines[99].Serial==41,"a full ring, the oldest first");
    free(ring);
    printf("%d failures\n",failures);
    return failures ? 1 : 0;
}
