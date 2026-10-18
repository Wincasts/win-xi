// Every line given to the game's chat log, recorded as Ashita hands it to a plugin: the bytes given and the bytes
// kept, its modes, its flags, round the ring.
#include <stdio.h>
#include <string.h>
#include "../src/modules/chat/texttap.h"
static int failures=0;
static void Check(bool ok,const char* text) { printf("%s %s\n",ok?"ok":"FAIL",text); if(!ok) ++failures; }
static bool Same(const char* bytes,uint32_t length,const char* wanted) { return length==strlen(wanted) && !memcmp(bytes,wanted,length); }
int main() {
    static TextTapShared tap={"UIHOOK-TEXT",1,sizeof(TextTapShared),0,0,{}};
    Check(sizeof(TextTapShared)==16+16+64*(24+8192),"text ABI 1: 64 lines of 4096 bytes each way");
    // a line no plugin or addon touched: Ashita's modified buffer empty, the final the original
    int32_t finalMode=9; bool finalIndent=false; char modified[4096]={};
    ChatTapRecord(tap,9,false,"Ann : hi",&finalMode,&finalIndent,modified,false,false);
    Check(tap.Serial==1 && tap.Events[0].Serial==1,"the first line is serial 1, at the ring's first place");
    Check(Same(tap.Events[0].Original,tap.Events[0].OriginalLength,"Ann : hi") && Same(tap.Events[0].Final,tap.Events[0].FinalLength,"Ann : hi"),
        "untouched: the final is the original");
    Check(tap.Events[0].Mode==9 && tap.Events[0].FinalMode==9 && tap.Events[0].Flags==0,"its mode both ways, no flags");
    // stamped by an addon loaded before uihook, its mode changed, indented: the final as it left it
    finalMode=151; finalIndent=true; strcpy(modified,"\x1e\x51[12:00:00]\x1e\x01 Ann : hi");
    ChatTapRecord(tap,150,false,"Ann : hi",&finalMode,&finalIndent,modified,false,false);
    Check(tap.Serial==2 && Same(tap.Events[1].Final,tap.Events[1].FinalLength,"\x1e\x51[12:00:00]\x1e\x01 Ann : hi") && Same(tap.Events[1].Original,tap.Events[1].OriginalLength,"Ann : hi"),
        "changed: the final as the addon left it, the original kept beside it");
    Check(tap.Events[1].Mode==150 && tap.Events[1].FinalMode==151 && tap.Events[1].Flags==(TEXT_TAP_MODIFIED|TEXT_TAP_INDENT),"the modes both ways; modified and indented");
    // an addon's own line, and one blocked by a filter
    finalMode=11; finalIndent=false; modified[0]=0;
    ChatTapRecord(tap,11,false,"[chatbox] hello",&finalMode,&finalIndent,modified,true,false);
    Check(tap.Events[2].Flags==TEXT_TAP_INJECTED,"an injected line says so");
    ChatTapRecord(tap,20,false,"The Crab hits you.",&finalMode,&finalIndent,modified,false,true);
    Check(tap.Events[3].Flags==TEXT_TAP_BLOCKED && Same(tap.Events[3].Final,tap.Events[3].FinalLength,"The Crab hits you."),"a blocked line says so, its text still there");
    // the same bytes written to the modified buffer: not a change
    strcpy(modified,"same"); finalMode=1;
    ChatTapRecord(tap,1,false,"same",&finalMode,&finalIndent,modified,false,false);
    Check(tap.Events[4].Flags==0,"the modified buffer holding the same bytes is no change");
    // Ashita's pointers missing: the originals stand
    ChatTapRecord(tap,5,true,"bare",nullptr,nullptr,nullptr,false,false);
    Check(tap.Events[5].FinalMode==5 && tap.Events[5].Flags==TEXT_TAP_INDENT && Same(tap.Events[5].Final,tap.Events[5].FinalLength,"bare"),"without modified pointers the given mode, indent and text stand");
    // a line longer than a place holds: cut, and said to be
    static char longLine[6000]; memset(longLine,'x',sizeof(longLine)-1); longLine[sizeof(longLine)-1]=0;
    modified[0]=0;
    ChatTapRecord(tap,1,false,longLine,&finalMode,&finalIndent,modified,false,false);
    Check(tap.Events[6].OriginalLength==4096 && tap.Events[6].FinalLength==4096 && (tap.Events[6].Flags&TEXT_TAP_CUT),"a longer line cut to the place, and flagged");
    // round the ring: the 65th line takes the first place, with its own serial
    for (int i=8;i<=64;i++) ChatTapRecord(tap,1,false,"filler",&finalMode,&finalIndent,modified,false,false); // seven so far
    Check(tap.Serial==64 && tap.Events[63].Serial==64,"64 lines fill the ring");
    ChatTapRecord(tap,2,false,"round",&finalMode,&finalIndent,modified,false,false);
    Check(tap.Serial==65 && tap.Events[0].Serial==65 && Same(tap.Events[0].Final,tap.Events[0].FinalLength,"round") && tap.Events[1].Serial==2,
        "the 65th at the first place, serial 65; the second still serial 2");
    printf(failures?"texttap: %d failed\n":"texttap: all passed\n",failures);
    return failures?1:0;
}
