// Theme the client's expanded controls without replacing their geometry or hit-tests, or, asked by the
// addon, leave its tab strip, scrollbar and rows of text undrawn where it draws its own: measured as the
// game draws them, so the addon's stand where the game's hit-tests are. Only six verified CALL sites are
// redirected; the shared sprite, scrollbar, tab-strip and row-drawing routines are never patched.
#pragma once
#include "chat.h"
#include "glyphs.h"
#include <algorithm>
#define CHAT_TAB_SPRITE_PATTERN "51 53 55 56 8B 71 14 8D 59 04 57 8B CB E8"
#define CHAT_TAB_ART_PATTERN "6A 00 8D 44 42 20 68 80 80 80 80 0F BF CE 8B 3C 87 0F BF C5 50 51 8B CF E8"
#define CHAT_SELECTION_ART_PATTERN "0F BF 44 24 38 0F BF D7 52 50 8B 4C 24 3C E8"
#define CHAT_CURSOR_ART_PATTERN "50 68 00 00 80 3F 0F BF D3 68 00 00 80 3F 51 52 8B CE E8"
#define CHAT_SCROLL_ART_PATTERN "8B 41 10 8B 51 0C 3B C2 7E 05 E8"
#define CHAT_SCROLL_DRAW_PATTERN "83 EC 0C 56 8B F1 8B 46 10 85 C0 0F 84 ?? ?? ?? ?? DB 06 D9 46 20"
enum { CHAT_ART_TAB, CHAT_ART_SELECTION, CHAT_ART_CURSOR, CHAT_ART_SCROLL, CHAT_ART_TABS, CHAT_ART_COUNT };
enum { CHAT_COLOR_HIGHLIGHT, CHAT_COLOR_TAB, CHAT_COLOR_CURSOR, CHAT_COLOR_SCROLL, CHAT_COLOR_COUNT };
using ChatTabSprite = void(__fastcall*)(void*,void*,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
using ChatWindowSprite = void(__fastcall*)(void*,void*,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
using ChatScrollDraw = void(__fastcall*)(void*,void*);
// FullLog::Draw's first call, the whole tab strip: thiscall(owner) with the filter on the stack, ret 4.
using ChatTabStrip = void(__fastcall*)(void*,void*,uint32_t);
struct ChatControlDiscovery { uint8_t* calls[CHAT_ART_COUNT]={}; uint8_t* targets[CHAT_ART_COUNT]={}; };
static uint8_t* ChatCallee(uint8_t* begin,size_t size,uint8_t* call) {
    if (!call || call<begin || size<5 || size_t(call-begin)>size-5 || call[0]!=0xe8) return nullptr;
    int32_t distance=0; memcpy(&distance,call+1,4);
    const intptr_t offset=intptr_t(call-begin)+5+distance;
    return offset>=0 && size_t(offset)<size ? begin+offset : nullptr;
}
static bool ChatWithin(uint8_t* at,uint8_t* start,size_t length) {
    return at && start && at>=start && size_t(at-start)<length;
}
static ChatControlDiscovery DiscoverChatControls(uint8_t* begin,size_t size,uint8_t* window,uint8_t* fullDraw) {
    ChatControlDiscovery out;
    if (!window || !fullDraw || !ChatWithin(window,begin,size) || !ChatWithin(fullDraw,begin,size)) return out;
    auto* tabs=ChatCallee(begin,size,fullDraw+19); // FullLog::Draw's first call draws its tab strip.
    auto* tab=UniquePattern(begin,size,CHAT_TAB_ART_PATTERN);
    auto* selection=UniquePattern(begin,size,CHAT_SELECTION_ART_PATTERN);
    auto* cursor=UniquePattern(begin,size,CHAT_CURSOR_ART_PATTERN);
    auto* scroll=UniquePattern(begin,size,CHAT_SCROLL_ART_PATTERN);
    auto* tabSprite=UniquePattern(begin,size,CHAT_TAB_SPRITE_PATTERN);
    auto* windowSprite=UniquePattern(begin,size,SPRITE_PATTERN);
    auto* scrollDraw=UniquePattern(begin,size,CHAT_SCROLL_DRAW_PATTERN);
    if (!ChatWithin(tab,tabs,0x200) || !ChatWithin(selection,window,0x800)
        || !ChatWithin(cursor,window,0x800) || !ChatWithin(scroll,window,0x800)
        || !tabSprite || !windowSprite || !scrollDraw) return out;
    uint8_t* calls[]={tab+24,selection+14,cursor+18,scroll+10,fullDraw+19};
    uint8_t* targets[]={tabSprite,windowSprite,windowSprite,scrollDraw,tabs};
    for (unsigned i=0;i<CHAT_ART_COUNT;i++)
        if (ChatCallee(begin,size,calls[i])!=targets[i]) return out;
    memcpy(out.calls,calls,sizeof(calls)); memcpy(out.targets,targets,sizeof(targets));
    return out;
}
struct ChatControlCalls : ChatControlDiscovery { uint8_t saved[CHAT_ART_COUNT][5]={}; };
static bool TakeChatControls(ChatControlCalls& out,const ChatControlDiscovery& found,void* const replacements[CHAT_ART_COUNT]) {
    // Validate the entire group before changing even one site. E8 stays E8 (same native return address).
    for (unsigned i=0;i<CHAT_ART_COUNT;i++)
        if (out.calls[i] || !found.calls[i] || !found.targets[i] || !replacements[i]
            || !VerifyCall(found.calls[i],found.targets[i])) return false;
    for (unsigned i=0;i<CHAT_ART_COUNT;i++) {
        out.calls[i]=found.calls[i]; out.targets[i]=found.targets[i]; memcpy(out.saved[i],out.calls[i],5);
        uint8_t patch[5]={0xe8,0,0,0,0};
        const int32_t distance=Distance(out.calls[i]+5,replacements[i]); memcpy(patch+1,&distance,4);
        WriteCode(out.calls[i],patch,5);
    }
    return true;
}
static void GiveChatControls(ChatControlCalls& out) {
    for (unsigned i=0;i<CHAT_ART_COUNT;i++) if (out.calls[i]) WriteCode(out.calls[i],out.saved[i],5);
    out=ChatControlCalls();
}
struct ChatControlStyle {
    float colors[CHAT_COLOR_COUNT][4]={};
    bool Read(const ChatShared& shared) {
        if (!shared.ControlStyleFrame || shared.ControlStyleFrame!=shared.Frame) return false;
        for (unsigned i=0;i<CHAT_COLOR_COUNT;i++) for (unsigned j=0;j<4;j++)
            if (!std::isfinite(shared.ControlColors[i][j]) || shared.ControlColors[i][j]<0 || shared.ControlColors[i][j]>1) return false;
        memcpy(colors,shared.ControlColors,sizeof(colors)); return true;
    }
    // FFXI sprite colours use 0x80 as unity, not 0xff. Retain native fade/pulse alpha.
    uint32_t Tint(unsigned index,uint32_t source) const {
        const auto& c=colors[index];
        uint32_t result=uint32_t(std::lround(c[3]*float((source>>24)&255)))<<24;
        result |= uint32_t(std::lround(c[0]*128))<<16;
        result |= uint32_t(std::lround(c[1]*128))<<8;
        return result | uint32_t(std::lround(c[2]*128));
    }
};
static bool ChatSelectedTab(void* owner,void* sprite) {
    int32_t filter=-1; void* selected=nullptr;
    // The verified tab Draw indexes owner[0x20 + channel*2 + chosen] (DWORD slots).
    return owner && sprite && ChatRead(static_cast<uint8_t*>(owner)+0x54,&filter,4) && filter>=0 && filter<=10
        && ChatRead(static_cast<uint8_t*>(owner)+0x84+filter*8,&selected,4) && selected==sprite;
}
static bool ChatSelectionColor(uint32_t color) { return color==0x80805020 || color==0x40402810; }
// Scrollbar::Draw only reads +00..+27. Forward a local copy with changed colours, never write the
// native object: its height, page/count/offset, scale and all mouse state remain exactly the game's.
struct ChatScrollArt { uint8_t bytes[0x28]; };
static bool ChatScrollCopy(void* native,ChatScrollArt& out,const ChatControlStyle& style) {
    if (!ChatRead(native,out.bytes,sizeof(out.bytes))) return false;
    uint32_t colors[2]; memcpy(colors,out.bytes+0x18,8);
    for (unsigned i=0;i<2;i++) colors[i]=style.Tint(CHAT_COLOR_SCROLL,colors[i]);
    memcpy(out.bytes+0x18,colors,8); return true;
}
struct ChatOwnerScope {
    void*& current; void* previous;
    ChatOwnerScope(void*& value,void* owner) : current(value),previous(value) { current=owner; }
    ~ChatOwnerScope() { current=previous; }
};
static void ForwardChatTab(ChatTabSprite original,bool styled,const ChatControlStyle& style,void* owner,
    void* sprite,uint32_t x,uint32_t y,uint32_t color,uint32_t a,uint32_t b) {
    if (styled) color=style.Tint(ChatSelectedTab(owner,sprite) ? CHAT_COLOR_HIGHLIGHT : CHAT_COLOR_TAB,color);
    original(sprite,nullptr,x,y,color,a,b);
}
static void ForwardChatWindowArt(ChatWindowSprite original,bool skin,bool styled,const ChatControlStyle& style,
    bool cursor,bool& blocking,void* sprite,uint32_t x,uint32_t y,uint32_t sx,uint32_t sy,uint32_t color,uint32_t a,uint32_t b,uint32_t c) {
    const bool selection=!cursor && ChatSelectionColor(color);
    ArrowScope nativeSelection(blocking,skin && selection);
    if (styled && (cursor || selection)) color=style.Tint(cursor ? CHAT_COLOR_CURSOR : CHAT_COLOR_HIGHLIGHT,color);
    original(sprite,nullptr,x,y,sx,sy,color,a,b,c);
}
static void ForwardChatScroll(ChatScrollDraw original,bool styled,const ChatControlStyle& style,void* object) {
    ChatScrollArt copy;
    void* drawn=styled && ChatScrollCopy(object,copy,style) ? &copy : object;
    original(drawn,nullptr);
}
// Whose tab a sprite is: the strip draws owner[0x80 + channel*8], or owner[0x84 + channel*8] for the chosen one.
static bool ChatTabChannel(void* owner,void* sprite,uint32_t& channel,bool& selected) {
    if (!owner || !sprite) return false;
    for (uint32_t c=0;c<=10;c++) for (unsigned chosen=0;chosen<2;chosen++) {
        void* at=nullptr;
        if (ChatRead(static_cast<uint8_t*>(owner)+0x80+c*8+chosen*4,&at,4) && at==sprite) { channel=c; selected=chosen==1; return true; }
    }
    return false;
}
// FullLog::Update writes its scrollbar's page rows to +0C, its row count to +10 and the rows above the view
// to +14 (the verified field pattern); read for the addon's own thumb, never written.
struct ChatScrollInfo { uint32_t page=0, count=0, top=0; };
static bool ChatScrollRead(void* object,ChatScrollInfo& out) {
    int32_t fields[3]={};
    if (!object || !ChatRead(static_cast<uint8_t*>(object)+0xc,fields,sizeof(fields))) return false;
    if (fields[0]<1 || fields[0]>4096 || fields[1]<0 || fields[1]>1048576 || fields[2]<0 || fields[2]>fields[1]) return false;
    out.page=uint32_t(fields[0]); out.count=uint32_t(fields[1]); out.top=uint32_t(fields[2]);
    return true;
}
// The screen bounds of what a native control's draw submitted, from its screen-space vertices
struct ChatBounds {
    uint32_t vertices=0; float left=0, top=0, right=0, bottom=0;
    void Add(float x,float y) {
        if (!vertices++) { left=right=x; top=bottom=y; }
        left=(std::min)(left,x); right=(std::max)(right,x);
        top=(std::min)(top,y); bottom=(std::max)(bottom,y);
    }
};
// Normalized to the viewport the control was drawn in, as the chat rectangles are; D3D8's half pixel added
static bool ChatNormalize(const ChatBounds& from,float x,float y,float width,float height,float out[4]) {
    if (!from.vertices || !(width>0) || !(height>0)) return false;
    out[0]=(from.left-x+0.5f)/width; out[1]=(from.top-y+0.5f)/height;
    out[2]=(from.right-x+0.5f)/width; out[3]=(from.bottom-y+0.5f)/height;
    for (unsigned i=0;i<4;i++) if (!std::isfinite(out[i]) || out[i]<-4 || out[i]>4) return false;
    return out[2]>out[0] && out[3]>out[1];
}
// A native control is left undrawn only inside a skinned full log whose capture asked for it
static inline bool ChatHidden(uint32_t replace,uint32_t bit,bool active) { return active && (replace & bit)!=0; }

// The full log's rows of text: its content Draw's last call, at +AA, is to the log drawer it shares with the
// compact logs (thiscall, six stack words), and inside the drawer one call draws a row: cdecl with the row's
// text, its 60-byte header by value, x, y, an alpha, the cursor flag, an out pointer and a zero, 22 words the
// caller takes back (add esp,58, within the 40 bytes after the call, once it has read what it keeps from the
// stack). That one site is redirected, a sixth; the drawer and the row draw are not.
#define CHAT_ROWS_DRAW_PATTERN "83 EC 0C A1 ?? ?? ?? ?? 89 4C 24 00 53 55 8A 48 08 56 84 C9 57 0F 84"
#define CHAT_ROW_SITE_PATTERN "6A 7F 51 52 B9 0F 00 00 00 83 EC 3C 8B FC 55 F3 A5 E8"
#define CHAT_ROW_DRAW_PATTERN "8B 44 24 58 8B 4C 24 54 8B 54 24 50 50 8B 44 24 50 51 8B 4C 24 50 52 8B 54 24 50 50"
#define CHAT_ROWS_CALL 0xaa
#define CHAT_ROW_SITE_CALL 17
using ChatRowDraw = void(__cdecl*)(const uint16_t*,ChatRowHeader,int32_t,int32_t,uint32_t,uint32_t,void*,uint32_t);
struct ChatTextSite { uint8_t* call=nullptr; uint8_t* target=nullptr; uint8_t saved[5]={}; };
static ChatTextSite DiscoverChatText(uint8_t* begin,size_t size,uint8_t* fullDraw) {
    ChatTextSite out;
    if (!fullDraw || !ChatWithin(fullDraw,begin,size)) return out;
    auto* rows=UniquePattern(begin,size,CHAT_ROWS_DRAW_PATTERN);
    auto* site=UniquePattern(begin,size,CHAT_ROW_SITE_PATTERN);
    auto* row=UniquePattern(begin,size,CHAT_ROW_DRAW_PATTERN);
    if (!rows || !site || !row || ChatCallee(begin,size,fullDraw+CHAT_ROWS_CALL)!=rows) return out;
    auto* call=site+CHAT_ROW_SITE_CALL;
    if (!ChatWithin(call,rows,0x200) || size_t(call-begin)+40>size || ChatCallee(begin,size,call)!=row) return out;
    bool cleaned=false;
    for (unsigned i=5;i+3<=40;i++) if (call[i]==0x83 && call[i+1]==0xc4 && call[i+2]==0x58) cleaned=true;
    if (!cleaned) return out;
    out.call=call; out.target=row;
    return out;
}
static bool TakeChatText(ChatTextSite& out,const ChatTextSite& found,void* replacement) {
    if (out.call || !found.call || !found.target || !replacement || !VerifyCall(found.call,found.target)) return false;
    out.call=found.call; out.target=found.target; memcpy(out.saved,out.call,5);
    uint8_t patch[5]={0xe8,0,0,0,0};
    const int32_t distance=Distance(out.call+5,replacement); memcpy(patch+1,&distance,4);
    WriteCode(out.call,patch,5);
    return true;
}
static void GiveChatText(ChatTextSite& out) {
    if (out.call) WriteCode(out.call,out.saved,5);
    out=ChatTextSite();
}
