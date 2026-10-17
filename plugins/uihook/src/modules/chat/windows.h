// The game's two log windows: which chat modes each shows, read as the client decides it. Recognition of
// the client's keep check and a transcription of it; nothing native is written, no native code is called.
#pragma once
#include <windows.h>
#include <stdint.h>
#include <string.h>
#include "chat.h"
#include "../party/target.h"

// Each window owns a history ring; a message goes to a window only where the window's keep check says
// (032E9980: the first window's at filter 0, the second's at 8). The chat-mode table lookup (032E9CD0):
// entries of a mode word, a category byte and one more, ended by a zero mode word; the table's address
// is the first instruction's immediate.
#define CHAT_MODE_LOOKUP_PATTERN "A1 ?? ?? ?? ?? 33 C9 66 85 C0 74 18 66 8B 54 24 04 66 3B C2 74 11 66 8B 04 8D"
// The first window's keep check (032E9B40): everything while the second window is hidden (the second's
// owner's byte +4D, the owner the global the instruction names), a mode word with bit 15 set, else its
// config words (B9, BA) by the mode's category's bit, an unknown mode kept.
#define CHAT_FIRST_KEEP_PATTERN "A1 ?? ?? ?? ?? 8A 50 4D 84 D2 75 05 B0 01 C2 40 00 8B 44 24 04 84 E4 79 05 B0 01 C2 40 00 68 BA 00 00 00 68 B9 00 00 00"
// The second's (032E9B80): nothing with bit 15, else its config words (BB, BC), an unknown mode dropped.
#define CHAT_SECOND_KEEP_PATTERN "8B 44 24 04 84 E4 79 05 32 C0 C2 40 00 68 BC 00 00 00 68 BB 00 00 00"
// The category test (032E9BB0): the mode's entry, its category's index, the two config words, the index's bit.
#define CHAT_CATEGORY_TEST_PATTERN "8B 44 24 04 83 EC 08 56 50 E8 ?? ?? ?? ?? 83 C4 04 85 C0 74 14 33 C9 8A 48 02 51 E8"
// The category's index (032EA120): a jump table of 30 cases, categories 54 to 71, each a small constant or none.
#define CHAT_CATEGORY_INDEX_PATTERN "8B 44 24 04 83 C0 AC 83 F8 1D 0F 87 ?? ?? ?? ?? FF 24 85"
// The config value reader (03353850, and its twin with another callee): the manager's global, then the
// value (03355330) of the entry (033554D0: the array at the manager's +4, 44 bytes an entry) at its +8.
#define CHAT_CONFIG_READ_PATTERN "8B 0D ?? ?? ?? ?? 85 C9 74 0B 8B 44 24 04 50 E8 ?? ?? ?? ?? C3 83 C8 FF C3"
#define CHAT_CONFIG_VALUE_PATTERN "8B 44 24 04 50 E8 ?? ?? ?? ?? 85 C0 75 06 83 C8 FF C2 04 00 8B 40 08 C2 04 00"
#define CHAT_CONFIG_ENTRY_PATTERN "8B 49 04 85 C9 74 10 8B 44 24 04 8D 14 80 8D 04 50 8D 04 81 C2 04 00"
#define CHAT_CATEGORY_FIRST 0x54
#define CHAT_CATEGORY_COUNT 30
#define CHAT_CONFIG_FIRST_LOW 0xb9  // the first window's two config words, and the second's
#define CHAT_CONFIG_SECOND_LOW 0xbb
#define CHAT_CONFIG_STRIDE 44
#define CHAT_CONFIG_VALUE 8
#define CHAT_MODE_ENTRIES 512 // the table has about 200; read no further
#define CHAT_SECOND_SHOWN 0x4d // the second window's owner: shown (its filters route) or hidden (the first shows everything)

struct ChatWindowRoutes {
    uint8_t* table=nullptr;   // the chat-mode table
    void** manager=nullptr;   // the config manager's global
    void** secondOwner=nullptr; // the second window's owner global, as the first keep check names it
    int8_t index[CHAT_CATEGORY_COUNT]={}; // category to bit, or -1
    bool cached=false; uint8_t shown=0; uint32_t words[4]={};
    uint32_t modes[2][8]={};
    bool Ready() const { return table && manager && secondOwner; }
    void Clear() { *this=ChatWindowRoutes(); }
};

static uint8_t* ChatWindowsCallee(uint8_t* begin,size_t size,uint8_t* call) {
    if (!call || call<begin || size<5 || size_t(call-begin)>size-5 || call[0]!=0xe8) return nullptr;
    int32_t distance=0; memcpy(&distance,call+1,4);
    const intptr_t offset=intptr_t(call-begin)+5+distance;
    return offset>=0 && size_t(offset)<size ? begin+offset : nullptr;
}
// An address an instruction names, inside the module
static uint8_t* ChatWindowsInside(uint8_t* begin,size_t size,const uint8_t* at,size_t room) {
    uintptr_t address=0; memcpy(&address,at,4);
    const uintptr_t low=reinterpret_cast<uintptr_t>(begin);
    if (address<low || size<room || address-low>size-room) return nullptr;
    return reinterpret_cast<uint8_t*>(address);
}
// The whole chain must be found, unique and consistent, or none of it is used: the second window's owner
// the first keep check names must be the split log's global the chat module found.
static bool DiscoverChatWindows(uint8_t* begin,size_t size,void** splitOwner,ChatWindowRoutes& out) {
    out.Clear();
    if (!begin || !splitOwner || size<64) return false;
    auto* lookup=UniquePattern(begin,size,CHAT_MODE_LOOKUP_PATTERN);
    auto* first=UniquePattern(begin,size,CHAT_FIRST_KEEP_PATTERN);
    auto* second=UniquePattern(begin,size,CHAT_SECOND_KEEP_PATTERN);
    auto* test=UniquePattern(begin,size,CHAT_CATEGORY_TEST_PATTERN);
    auto* index=UniquePattern(begin,size,CHAT_CATEGORY_INDEX_PATTERN);
    auto* value=UniquePattern(begin,size,CHAT_CONFIG_VALUE_PATTERN);
    auto* entry=UniquePattern(begin,size,CHAT_CONFIG_ENTRY_PATTERN);
    if (!lookup || !first || !second || !test || !index || !value || !entry) return false;
    if (size_t(lookup-begin)>size-5 || size_t(first-begin)>size-5 || size_t(index-begin)>size-23) return false;
    // the test's first call is the lookup, the value's first call the entry
    if (ChatWindowsCallee(begin,size,test+9)!=lookup || ChatWindowsCallee(begin,size,value+5)!=entry) return false;
    auto* table=ChatWindowsInside(begin,size,lookup+1,4);
    auto* owner=ChatWindowsInside(begin,size,first+1,4);
    if (!table || !owner || reinterpret_cast<void**>(owner)!=splitOwner) return false;
    // every config reader (the value's, and its twin) names the same manager global, and one calls the value
    void** manager=nullptr; bool valued=false;
    size_t at=0;
    while (at<size) {
        auto* reader=FindPattern(begin+at,size-at,CHAT_CONFIG_READ_PATTERN);
        if (!reader) break;
        if (size_t(reader-begin)>size-25) return false;
        auto* global=ChatWindowsInside(begin,size,reader+2,4);
        if (!global || (manager && reinterpret_cast<void**>(global)!=manager)) return false;
        if (ChatWindowsCallee(begin,size,reader+15)==value) valued=true;
        manager=reinterpret_cast<void**>(global);
        at=size_t(reader-begin)+1;
    }
    if (!manager || !valued) return false;
    // the jump table: each case a small constant (mov eax,imm; ret), zero (xor eax,eax; ret) or none (or eax,-1; ret)
    auto* jumps=ChatWindowsInside(begin,size,index+19,4*CHAT_CATEGORY_COUNT);
    if (!jumps) return false;
    for (unsigned i=0;i<CHAT_CATEGORY_COUNT;i++) {
        auto* target=ChatWindowsInside(begin,size,jumps+i*4,6);
        if (!target) return false;
        if (target[0]==0xb8 && target[5]==0xc3) {
            int32_t bit=0; memcpy(&bit,target+1,4);
            if (bit<0 || bit>63) return false;
            out.index[i]=static_cast<int8_t>(bit);
        } else if (target[0]==0x33 && target[1]==0xc0 && target[2]==0xc3) out.index[i]=0;
        else if (target[0]==0x83 && target[1]==0xc8 && target[2]==0xff && target[3]==0xc3) out.index[i]=-1;
        else return false;
    }
    out.table=table; out.manager=manager; out.secondOwner=reinterpret_cast<void**>(owner);
    return true;
}
// The client's category test for one mode: its entry (the first with that mode word), the category's bit in
// the window's two config words; a mode without an entry or a category without a bit takes the window's default.
static bool ChatWindowKeeps(const uint8_t* table,unsigned entries,const int8_t* index,uint32_t low,uint32_t high,bool fallback,unsigned mode) {
    for (unsigned i=0;i<entries;i++) {
        uint16_t word=0; memcpy(&word,table+i*4,2);
        if (word!=mode) continue;
        const unsigned category=table[i*4+2];
        if (category<CHAT_CATEGORY_FIRST || category>=CHAT_CATEGORY_FIRST+CHAT_CATEGORY_COUNT) return fallback;
        const int bit=index[category-CHAT_CATEGORY_FIRST];
        if (bit<0) return fallback;
        return ((bit<32 ? low : high)>>(bit&31))&1;
    }
    return fallback;
}
// The game's routing this frame: the second window shown or not, and each window's modes (by the low byte;
// a mode word with bit 15 set goes to the first window alone, whatever these say). Nothing published when
// any of it cannot be read. The masks are made again only when the config or the flag changes.
static void SampleChatWindows(ChatWindowRoutes& routes,ChatShared& shared,uint32_t frame) {
    shared.WindowFrame=0;
    if (!routes.Ready()) return;
    void* owner=nullptr; uint8_t shown=0;
    if (!ChatRead(routes.secondOwner,&owner,4) || !owner || !ChatRead(static_cast<uint8_t*>(owner)+CHAT_SECOND_SHOWN,&shown,1)) return;
    void* manager=nullptr; void* array=nullptr; uint32_t words[4];
    if (!ChatRead(routes.manager,&manager,4)) return;
    if (manager && !ChatRead(static_cast<uint8_t*>(manager)+4,&array,4)) return;
    for (unsigned i=0;i<4;i++) {
        const unsigned id=CHAT_CONFIG_FIRST_LOW+i; // B9, BA, BB, BC
        if (!manager || !array) { words[i]=0xffffffffu; continue; } // the reader's -1 for no manager or no entries
        if (!ChatRead(static_cast<uint8_t*>(array)+id*CHAT_CONFIG_STRIDE+CHAT_CONFIG_VALUE,&words[i],4)) return;
    }
    shown=shown ? 1 : 0;
    if (!routes.cached || shown!=routes.shown || memcmp(words,routes.words,sizeof(words))) {
        uint8_t table[CHAT_MODE_ENTRIES*4];
        unsigned entries=0;
        for (;entries<CHAT_MODE_ENTRIES;entries++) {
            if (!ChatRead(routes.table+entries*4,table+entries*4,4)) return;
            uint16_t word=0; memcpy(&word,table+entries*4,2);
            if (!word) break;
        }
        memset(routes.modes,0,sizeof(routes.modes));
        for (unsigned mode=0;mode<256;mode++) {
            const bool first=!shown || ChatWindowKeeps(table,entries,routes.index,words[0],words[1],true,mode);
            const bool second=ChatWindowKeeps(table,entries,routes.index,words[2],words[3],false,mode);
            if (first) routes.modes[0][mode/32]|=1u<<(mode%32);
            if (second) routes.modes[1][mode/32]|=1u<<(mode%32);
        }
        routes.cached=true; routes.shown=shown; memcpy(routes.words,words,sizeof(words));
    }
    memcpy(shared.WindowModes,routes.modes,sizeof(routes.modes));
    shared.WindowFlags=shown ? CHAT_SECOND_WINDOW : 0;
    shared.WindowFrame=frame;
}
