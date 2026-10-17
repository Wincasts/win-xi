#include <stdio.h>
#include "../src/modules/party/detour.h"
#include "../src/modules/party/target.h"
#include "../src/modules/chat/controls.h"
static int failures=0;
static void Check(bool ok,const char* text) { printf("%s %s\n",ok?"ok":"FAIL",text); if(!ok) ++failures; }
static void Pattern(uint8_t* at,const char* text) {
    while (*text) {
        if (*text==' ') { ++text; continue; }
        if (*text=='?') { *at++=0; text+=2; }
        else { char hex[3]={text[0],text[1],0}; *at++=static_cast<uint8_t>(strtoul(hex,nullptr,16)); text+=2; }
    }
}
static void Call(uint8_t* at,void* target) {
    at[0]=0xe8; const int32_t distance=Distance(at+5,target); memcpy(at+1,&distance,4);
}
static void* seenObject=nullptr;
static uint32_t seen[8]={};
static bool* probeBlocking=nullptr;
static bool seenBlocking=false;
static void __fastcall ProbeTab(void* object,void*,uint32_t x,uint32_t y,uint32_t color,uint32_t a,uint32_t b) {
    seenObject=object; const uint32_t args[]={x,y,color,a,b}; memcpy(seen,args,sizeof(args));
}
static void __fastcall ProbeWindow(void* object,void*,uint32_t x,uint32_t y,uint32_t sx,uint32_t sy,uint32_t color,uint32_t a,uint32_t b,uint32_t c) {
    seenObject=object; const uint32_t args[]={x,y,sx,sy,color,a,b,c}; memcpy(seen,args,sizeof(args));
    seenBlocking=probeBlocking && *probeBlocking;
}
static ChatScrollArt seenScroll;
static void __fastcall ProbeScroll(void* object,void*) {
    seenObject=object; memcpy(seenScroll.bytes,object,sizeof(seenScroll));
}
int main() {
    uint8_t image[8192]={};
    auto* window=image+64;
    auto* full=image+2304; Pattern(full,CHAT_FULL_DRAW_PATTERN);
    auto* tabs=image+2600; Call(full+19,tabs);
    auto* tab=image+2700; Pattern(tab,CHAT_TAB_ART_PATTERN);
    auto* selection=image+128; Pattern(selection,CHAT_SELECTION_ART_PATTERN);
    auto* cursor=image+256; Pattern(cursor,CHAT_CURSOR_ART_PATTERN);
    auto* scroll=image+384; Pattern(scroll,CHAT_SCROLL_ART_PATTERN);
    auto* tabSprite=image+3100; Pattern(tabSprite,CHAT_TAB_SPRITE_PATTERN);
    auto* sprite=image+3300; Pattern(sprite,SPRITE_PATTERN);
    auto* scrollDraw=image+3500; Pattern(scrollDraw,CHAT_SCROLL_DRAW_PATTERN);
    Call(tab+24,tabSprite); Call(selection+14,sprite); Call(cursor+18,sprite); Call(scroll+10,scrollDraw);
    auto found=DiscoverChatControls(image,sizeof(image),window,full);
    Check(found.calls[CHAT_ART_TAB]==tab+24 && found.calls[CHAT_ART_SELECTION]==selection+14
        && found.calls[CHAT_ART_CURSOR]==cursor+18 && found.calls[CHAT_ART_SCROLL]==scroll+10,
        "four control call sites unique and cross-checked against native parent functions/callees");
    Check(found.targets[0]==tabSprite && found.targets[1]==sprite && found.targets[2]==sprite && found.targets[3]==scrollDraw,
        "five-word tab, eight-word window sprites and no-argument scrollbar have independent ABIs");
    Call(cursor+18,tabSprite);
    Check(!DiscoverChatControls(image,sizeof(image),window,full).calls[0],"wrong cursor callee rejects whole optional group");
    Call(cursor+18,sprite);
    Pattern(image+4000,CHAT_TAB_ART_PATTERN);
    Check(!DiscoverChatControls(image,sizeof(image),window,full).calls[0],"ambiguous tab site rejects group without guessing");
    memset(image+4000,0,25);
    Check(!DiscoverChatControls(image,sizeof(image),image+1000,full).calls[0],"unrelated window's sites cannot be patched");
    Call(full+19,image+4000);
    Check(!DiscoverChatControls(image,sizeof(image),window,full).calls[0],"tab drawing must be the full-log content's first callee");
    Call(full+19,tabs);
    Check(!ChatCallee(image,sizeof(image),image+sizeof(image)-1),"truncated CALL safely rejected");
    ChatControlCalls hooks;
    void* replacements[]={image+5000,image+5100,image+5200,image+5300};
    Call(scroll+10,tabSprite);
    Check(!TakeChatControls(hooks,found,replacements) && VerifyCall(tab+24,tabSprite),"all sites validated before any patch");
    Call(scroll+10,scrollDraw);
    Check(TakeChatControls(hooks,found,replacements),"verified controls can be redirected together");
    bool patched=true;
    for (unsigned i=0;i<4;i++) patched &= VerifyCall(found.calls[i],static_cast<uint8_t*>(replacements[i]));
    Check(patched && tabSprite[0]==0x51 && sprite[0]==0x83 && scrollDraw[0]==0x83,
        "redirected sites remain CALLs; shared sprite and scrollbar functions untouched");
    GiveChatControls(hooks);
    Check(VerifyCall(tab+24,tabSprite) && VerifyCall(cursor+18,sprite) && VerifyCall(selection+14,sprite)
        && VerifyCall(scroll+10,scrollDraw) && !hooks.calls[0],"unload restores all native CALLs and clears ownership");

    ChatShared shared={}; shared.Frame=10; shared.ControlStyleFrame=10;
    for (unsigned i=0;i<4;i++) { shared.ControlColors[i][0]=0.25f; shared.ControlColors[i][1]=0.5f;
        shared.ControlColors[i][2]=1; shared.ControlColors[i][3]=0.5f; }
    ChatControlStyle style;
    Check(style.Read(shared),"valid current-frame theme is captured");
    Check(style.Tint(CHAT_COLOR_HIGHLIGHT,0x80808080)==0x40204080,"native sprite unity is 128; RGBA packed in ARGB order");
    Check(style.Tint(CHAT_COLOR_CURSOR,0x40808080)==0x20204080,"native cursor fade/pulse alpha preserved");
    shared.ControlColors[0][0]=1;
    Check(style.Tint(0,0x80808080)==0x40204080,"render uses captured colours, not mutable shared values");
    shared.ControlStyleFrame=9; Check(!style.Read(shared),"stale styles cannot attach to a new capture");
    shared.ControlStyleFrame=10; shared.ControlColors[0][0]=NAN;
    Check(!style.Read(shared),"NaN styles rejected");
    shared.ControlColors[0][0]=INFINITY; Check(!style.Read(shared),"infinite styles rejected");
    shared.ControlColors[0][0]=1.1f; Check(!style.Read(shared),"out-of-range styles rejected");
    shared.ControlColors[0][0]=0.25f;
    Check(style.Read(shared),"valid style recovers after malformed input");
    Check(ChatSelectionColor(0x80805020) && ChatSelectionColor(0x40402810) && !ChatSelectionColor(0x80808080),
        "only verified native row-selection tints bypass frame suppression");
    bool blocking=true;
    { ArrowScope allow(blocking,true); Check(!blocking,"selected row artwork bypasses frame GPU suppression"); }
    Check(blocking,"row-selection bypass restores outer GPU suppression");

    uint8_t owner[0xe4]={}; void* chosen=image+6000;
    *reinterpret_cast<int32_t*>(owner+0x54)=4;
    *reinterpret_cast<void**>(owner+0x84+4*8)=chosen;
    Check(ChatSelectedTab(owner,chosen) && !ChatSelectedTab(owner,image+6010),"selected native tab identified by actual sprite, not tab-order guesses");
    *reinterpret_cast<int32_t*>(owner+0x54)=15;
    Check(!ChatSelectedTab(owner,chosen) && !ChatSelectedTab(nullptr,chosen),"unknown/invalid owner layouts leave tabs unselected without unsafe indexing");
    uint8_t nativeScroll[0x28];
    for (unsigned i=0;i<sizeof(nativeScroll);i++) nativeScroll[i]=uint8_t(i);
    uint32_t colors[]={0x80808080,0x40808080}; memcpy(nativeScroll+0x18,colors,8);
    uint8_t saved[0x28]; memcpy(saved,nativeScroll,sizeof(saved));
    ChatScrollArt copy;
    Check(ChatScrollCopy(nativeScroll,copy,style),"native scrollbar copied for presentation only");
    Check(!memcmp(saved,nativeScroll,sizeof(saved)) && !memcmp(copy.bytes,nativeScroll,0x18)
        && !memcmp(copy.bytes+0x20,nativeScroll+0x20,8),"scrollbar position, range, page, offset, scale and source memory untouched");
    uint32_t tinted[2]; memcpy(tinted,copy.bytes+0x18,8);
    Check(tinted[0]==0x40204080 && tinted[1]==0x20204080,"both native scrollbar colours follow theme, retaining alpha differences");
    Check(!ChatScrollCopy(reinterpret_cast<void*>(1),copy,style),"unreadable scrollbar falls back without writes");
    *reinterpret_cast<int32_t*>(owner+0x54)=4;
    ForwardChatTab(ProbeTab,true,style,owner,chosen,0xfffffffd,17,0x80808080,23,42);
    Check(seenObject==chosen && seen[0]==0xfffffffd && seen[1]==17 && seen[2]==0x40204080 && seen[3]==23 && seen[4]==42,
        "tab wrapper preserves this, signed coordinates and both stack flags; only colour changes");
    ForwardChatTab(ProbeTab,false,style,owner,chosen,11,17,0x80808080,23,42);
    Check(seen[2]==0x80808080,"outside styled full-log scope the tab is byte-for-byte native");
    blocking=true; probeBlocking=&blocking;
    ForwardChatWindowArt(ProbeWindow,true,true,style,false,blocking,chosen,13,29,0x3f800000,0x3f400000,0x80805020,3,7,11);
    Check(seenObject==chosen && seen[0]==13 && seen[1]==29 && seen[2]==0x3f800000 && seen[3]==0x3f400000
        && seen[4]==0x40204080 && seen[5]==3 && seen[6]==7 && seen[7]==11 && !seenBlocking && blocking,
        "selection wrapper preserves all geometry/float bits/flags, bypassing suppression only for the draw");
    ForwardChatWindowArt(ProbeWindow,true,true,style,false,blocking,chosen,13,29,1,2,0x80808080,3,7,11);
    Check(seenBlocking && seen[4]==0x80808080 && blocking,"ordinary background art cannot bypass suppression or be recoloured");
    ForwardChatWindowArt(ProbeWindow,false,false,style,true,blocking,chosen,13,29,1,2,0x40402810,3,7,11);
    Check(seenBlocking && seen[4]==0x40402810,"other windows' cursor calls retain original colour and suppression");
    ForwardChatScroll(ProbeScroll,true,style,nativeScroll);
    Check(seenObject!=nativeScroll && !memcmp(seenScroll.bytes,copy.bytes,sizeof(copy)) && !memcmp(saved,nativeScroll,sizeof(saved)),
        "scrollbar wrapper forwards tinted local presentation without modifying native state");
    ForwardChatScroll(ProbeScroll,false,style,nativeScroll);
    Check(seenObject==nativeScroll && !memcmp(seenScroll.bytes,nativeScroll,sizeof(seenScroll)),"unthemed scrollbar forwards original object");
    void* current=chosen;
    { ChatOwnerScope first(current,owner); { ChatOwnerScope nested(current,nullptr); }
        Check(current==owner,"nested full-log drawing restores parent owner"); }
    Check(current==chosen,"content owner scope restores previous pointer on exit");
    return failures?1:0;
}
