// The two log windows' routing: discovery of the client's keep check and the masks made from its config.
#include <stdio.h>
#include "../src/modules/party/detour.h"
#include "../src/modules/party/target.h"
#include "../src/modules/chat/chat.h"
#include "../src/modules/chat/windows.h"
#include "../src/modules/chat/colors.h"
static int failures=0;
static void Check(bool ok,const char* text) { printf("%s %s\n",ok?"ok":"FAIL",text); if(!ok) ++failures; }
static void Pattern(uint8_t* at,const char* text) {
    while (*text) {
        if (*text==' ') { ++text; continue; }
        if (*text=='?') { *at++=0; text+=2; }
        else { char hex[3]={text[0],text[1],0}; *at++=static_cast<uint8_t>(strtoul(hex,nullptr,16)); text+=2; }
    }
}
static void Put(uint8_t* at,uint32_t value) { memcpy(at,&value,4); }
static uint32_t Address(const void* at) { return static_cast<uint32_t>(reinterpret_cast<uintptr_t>(at)); }
static void Call(uint8_t* at,const uint8_t* target) { at[0]=0xe8; Put(at+1,static_cast<uint32_t>(target-(at+5))); }
static bool Mode(const ChatShared& shared,unsigned window,unsigned mode) { return (shared.WindowModes[window][mode/32]>>(mode%32))&1; }
int main() {
    static uint8_t image[8192]={};
    // the chat-mode table: say 1/9 category 54, tell 4/C category 56, party 5/D category 57, a mode 20 whose
    // category 5F has no bit, a mode E0 with a category past the cases, a second entry for mode 1 with
    // party's category (the first entry is the one that counts), and no entry for mode 7
    auto* table=image+4096;
    const uint16_t modes[]={1,9,4,0xc,5,0xd,0x20,0xe0,1,0};
    const uint8_t categories[]={0x54,0x54,0x56,0x56,0x57,0x57,0x5f,0x73,0x57,0};
    for (unsigned i=0;i<10;i++) { memcpy(table+i*4,&modes[i],2); table[i*4+2]=categories[i]; }
    auto* lookup=image+64; Pattern(lookup,CHAT_MODE_LOOKUP_PATTERN); Put(lookup+1,Address(table));
    void** splitOwner=reinterpret_cast<void**>(image+4600);
    auto* first=image+128; Pattern(first,CHAT_FIRST_KEEP_PATTERN); Put(first+1,Address(splitOwner));
    auto* second=image+192; Pattern(second,CHAT_SECOND_KEEP_PATTERN);
    auto* test=image+256; Pattern(test,CHAT_CATEGORY_TEST_PATTERN); Call(test+9,lookup);
    auto* index=image+320; Pattern(index,CHAT_CATEGORY_INDEX_PATTERN);
    auto* jumps=image+4700; Put(index+19,Address(jumps));
    // cases: 54 -> bit 0, 55 -> 10, 56 -> 1, 57 -> 2, 5F (case 11) -> none, 60 (case 12) -> 33 (the high word), the rest zero
    auto* cases=image+5000;
    for (unsigned i=0;i<CHAT_CATEGORY_COUNT;i++) {
        auto* code=cases+i*8;
        if (i==11) { code[0]=0x83; code[1]=0xc8; code[2]=0xff; code[3]=0xc3; }
        else if (i==0 || i==1 || i==2 || i==3 || i==12) { code[0]=0xb8; Put(code+1,i==0 ? 0 : i==1 ? 10 : i==2 ? 1 : i==3 ? 2 : 33); code[5]=0xc3; }
        else { code[0]=0x33; code[1]=0xc0; code[2]=0xc3; }
        Put(jumps+i*4,Address(code));
    }
    auto* value=image+384; Pattern(value,CHAT_CONFIG_VALUE_PATTERN);
    auto* entry=image+448; Pattern(entry,CHAT_CONFIG_ENTRY_PATTERN); Call(value+5,entry);
    void** manager=reinterpret_cast<void**>(image+4604);
    auto* reader=image+512; Pattern(reader,CHAT_CONFIG_READ_PATTERN); Put(reader+2,Address(manager)); Call(reader+15,value);
    auto* twin=image+576; Pattern(twin,CHAT_CONFIG_READ_PATTERN); Put(twin+2,Address(manager)); Call(twin+15,image+700);
    ChatWindowRoutes routes;
    Check(DiscoverChatWindows(image,sizeof(image),splitOwner,routes) && routes.Ready(),"the keep check, its table, index cases and config reader found and consistent");
    Check(routes.table==table && routes.manager==manager && routes.secondOwner==splitOwner,"the table, the manager's global and the second window's owner");
    Check(routes.index[0]==0 && routes.index[1]==10 && routes.index[2]==1 && routes.index[3]==2 && routes.index[11]==-1 && routes.index[12]==33 && routes.index[29]==0,"each jump case read: a constant, none, or zero");
    static uint8_t ownerBytes[0x60]={}; *splitOwner=ownerBytes;
    static uint8_t managerBytes[16]={}; *manager=managerBytes;
    static uint8_t config[0xd0*CHAT_CONFIG_STRIDE]={}; Put(managerBytes+4,Address(config));
    auto word=[&](unsigned id)->uint32_t& { return *reinterpret_cast<uint32_t*>(config+id*CHAT_CONFIG_STRIDE+CHAT_CONFIG_VALUE); };
    word(0xb9)=1|2; word(0xba)=0; // the first window: say (bit 0) and tell (bit 1), not party (bit 2)
    word(0xbb)=4; word(0xbc)=2;  // the second: party, and the high word's bit 33
    ChatShared shared={};
    ownerBytes[CHAT_SECOND_SHOWN]=0;
    SampleChatWindows(routes,shared,7);
    Check(shared.WindowFrame==7 && shared.WindowFlags==0,"read, the second window hidden");
    bool all=true; for (unsigned m=0;m<256;m++) all=all && Mode(shared,0,m);
    Check(all,"the second window hidden: the first shows everything, whatever the config says");
    Check(Mode(shared,1,5) && Mode(shared,1,0xd) && !Mode(shared,1,1) && !Mode(shared,1,7),"the second's modes follow its config even while hidden: party, not say, not an unknown mode");
    ownerBytes[CHAT_SECOND_SHOWN]=1;
    SampleChatWindows(routes,shared,8);
    Check(shared.WindowFrame==8 && shared.WindowFlags==CHAT_SECOND_WINDOW,"the second window shown");
    Check(Mode(shared,0,1) && Mode(shared,0,9) && Mode(shared,0,4) && Mode(shared,0,0xc) && !Mode(shared,0,5) && !Mode(shared,0,0xd),"the first keeps say and tell, not party");
    Check(Mode(shared,0,7) && Mode(shared,0,0x20) && Mode(shared,0,0xe0),"an unknown mode, a category without a bit, a category past the cases: the first keeps them");
    Check(!Mode(shared,1,7) && !Mode(shared,1,0x20) && !Mode(shared,1,0xe0),"and the second drops them");
    Check(!Mode(shared,1,1) && Mode(shared,1,5),"a mode word in the table twice takes its first entry's category: say is not party");
    word(0xb9)=1|2|4;
    SampleChatWindows(routes,shared,9);
    Check(Mode(shared,0,5) && shared.WindowFrame==9,"the config changed: the masks made again");
    word(0xbc)=2; table[6*4+2]=0x60; // mode 20's category now the one with bit 33
    SampleChatWindows(routes,shared,10);
    Check(!Mode(shared,1,0x20),"the table is read again only when the config or the flag changes");
    word(0xbc)=3;
    SampleChatWindows(routes,shared,11);
    Check(Mode(shared,1,0x20),"bit 33: the high config word's bit 1");
    *manager=nullptr;
    SampleChatWindows(routes,shared,12);
    Check(shared.WindowFrame==12 && Mode(shared,0,5) && Mode(shared,1,1) && !Mode(shared,1,7),"no config manager: the reader's -1, every bit set, as the client would; an unknown mode still the window's default");
    *manager=managerBytes; *splitOwner=nullptr;
    SampleChatWindows(routes,shared,13);
    Check(shared.WindowFrame==0,"no second owner: nothing published");
    *splitOwner=ownerBytes;
    SampleChatWindows(routes,shared,14);
    Check(shared.WindowFrame==14,"back: published again");
    routes.Clear();
    SampleChatWindows(routes,shared,15);
    Check(shared.WindowFrame==0 && !routes.Ready(),"released: nothing published");
    // discovery refusals: each part missing, inconsistent or ambiguous
    Put(first+1,Address(splitOwner)+4);
    Check(!DiscoverChatWindows(image,sizeof(image),splitOwner,routes),"the keep check must name the split log's owner global");
    Put(first+1,Address(splitOwner));
    Put(twin+2,Address(manager)+4);
    Check(!DiscoverChatWindows(image,sizeof(image),splitOwner,routes),"every config reader must name one manager");
    Put(twin+2,Address(manager));
    Call(reader+15,image+700);
    Check(!DiscoverChatWindows(image,sizeof(image),splitOwner,routes),"a config reader must call the value");
    Call(reader+15,value);
    Call(test+9,image+700);
    Check(!DiscoverChatWindows(image,sizeof(image),splitOwner,routes),"the category test must call the lookup");
    Call(test+9,lookup);
    cases[4*8]=0x90;
    Check(!DiscoverChatWindows(image,sizeof(image),splitOwner,routes),"an unexpected jump case refuses the whole table");
    cases[4*8]=0x33;
    Put(cases+1,64);
    Check(!DiscoverChatWindows(image,sizeof(image),splitOwner,routes),"a bit past 63 refused");
    Put(cases+1,0);
    Pattern(image+640,CHAT_SECOND_KEEP_PATTERN);
    Check(!DiscoverChatWindows(image,sizeof(image),splitOwner,routes),"an ambiguous keep check refused");
    memset(image+640,0,32);
    Check(DiscoverChatWindows(image,sizeof(image),splitOwner,routes),"whole again");
    Check(!DiscoverChatWindows(image,sizeof(image),nullptr,routes) && !routes.Ready(),"no split owner known: nothing");
    Check(sizeof(ChatShared)==71684,"chat ABI 13: the second window's bounds, the two windows' routing, lines and the game's colours");
    // the game's colours: each mode's category, each category's colour, the inline palette; the serial moving only
    // with a change; nothing where a table cannot be read
    auto* categoryTable=image+5400; // entries of 8: category, pad, colour at +4
    const uint8_t cats[]={0x54,0x56,0x57,0x54,0};
    const uint32_t cols[]={0x80808080u,0x80D84C64u,0x803464FFu,0x11111111u,0};
    for (unsigned i=0;i<5;i++) { categoryTable[i*8]=cats[i]; memcpy(categoryTable+i*8+4,&cols[i],4); }
    auto* paletteTable=image+5500;
    for (unsigned i=0;i<CHAT_INLINE_COLORS;i++) { uint32_t c=i==2 ? 0x4040C000u : i==6 ? 0x60108080u : 0; memcpy(paletteTable+i*4,&c,4); }
    auto* categoryLookup=image+704; Pattern(categoryLookup,CHAT_CATEGORY_COLOR_PATTERN); Put(categoryLookup+1,Address(categoryTable));
    auto* paletteLookup=image+768; Pattern(paletteLookup,CHAT_INLINE_PALETTE_PATTERN); Put(paletteLookup+18,Address(paletteTable));
    ChatColorTables colors;
    Check(DiscoverChatColors(image,sizeof(image),colors) && colors.Ready() && colors.modes==table && colors.categories==categoryTable && colors.palette==paletteTable,"the mode, category and palette tables found");
    SampleChatColors(colors,shared,30);
    Check(shared.ColorFrame==30 && shared.ColorSerial==1,"read, the first serial");
    Check(shared.ModeCategory[1]==0x54 && shared.ModeCategory[9]==0x54 && shared.ModeCategory[4]==0x56 && shared.ModeCategory[5]==0x57 && shared.ModeCategory[7]==0,"each mode's category, none for a mode without an entry");
    Check(shared.CategoryColors[0x54]==0x80808080u && shared.CategoryColors[0x56]==0x80D84C64u && shared.CategoryColors[0x55]==0,"each category's colour, the first entry's where a category is listed twice, none where unlisted");
    Check(shared.InlineColors[2]==0x4040C000u && shared.InlineColors[6]==0x60108080u && shared.InlineColors[1]==0,"the inline palette");
    SampleChatColors(colors,shared,31);
    Check(shared.ColorFrame==31 && shared.ColorSerial==1,"nothing changed: the serial holds");
    memcpy(categoryTable+4,&cols[1],4); SampleChatColors(colors,shared,32);
    Check(shared.ColorSerial==2 && shared.CategoryColors[0x54]==0x80D84C64u,"a colour changed (the user's config): the serial moves");
    colors.categories=reinterpret_cast<uint8_t*>(uintptr_t(16)); SampleChatColors(colors,shared,33);
    Check(shared.ColorFrame==0,"a table that cannot be read: nothing published");
    colors.Clear(); SampleChatColors(colors,shared,34);
    Check(shared.ColorFrame==0 && !colors.Ready(),"released: nothing");
    Pattern(image+832,CHAT_INLINE_PALETTE_PATTERN);
    Check(!DiscoverChatColors(image,sizeof(image),colors),"an ambiguous palette lookup refused");
    memset(image+832,0,18);
    Check(DiscoverChatColors(image,sizeof(image),colors),"whole again");
    return failures?1:0;
}
