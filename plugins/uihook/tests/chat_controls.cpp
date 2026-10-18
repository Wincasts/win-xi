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
static const uint16_t* seenText=nullptr; static ChatRowHeader seenHeader; static uint32_t seenRow[6];
static void __cdecl ProbeRow(const uint16_t* text,ChatRowHeader header,int32_t x,int32_t y,uint32_t alpha,uint32_t flag,void* out,uint32_t zero) {
    seenText=text; seenHeader=header;
    const uint32_t args[]={uint32_t(x),uint32_t(y),alpha,flag,uint32_t(reinterpret_cast<uintptr_t>(out)),zero}; memcpy(seenRow,args,sizeof(args));
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
    Check(found.calls[CHAT_ART_TABS]==full+19 && found.targets[CHAT_ART_TABS]==tabs,
        "the fifth site is the full log's call to its tab strip, the strip the callee");
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
    void* replacements[]={image+5000,image+5100,image+5200,image+5300,image+5400};
    Call(scroll+10,tabSprite);
    Check(!TakeChatControls(hooks,found,replacements) && VerifyCall(tab+24,tabSprite),"all sites validated before any patch");
    Call(scroll+10,scrollDraw);
    Check(TakeChatControls(hooks,found,replacements),"verified controls can be redirected together");
    bool patched=true;
    for (unsigned i=0;i<CHAT_ART_COUNT;i++) patched &= VerifyCall(found.calls[i],static_cast<uint8_t*>(replacements[i]));
    Check(patched && tabSprite[0]==0x51 && sprite[0]==0x83 && scrollDraw[0]==0x83 && full[19]==0xe8,
        "redirected sites remain CALLs; shared sprite, scrollbar and tab strip functions untouched");
    GiveChatControls(hooks);
    Check(VerifyCall(tab+24,tabSprite) && VerifyCall(cursor+18,sprite) && VerifyCall(selection+14,sprite)
        && VerifyCall(scroll+10,scrollDraw) && VerifyCall(full+19,tabs) && !hooks.calls[0],"unload restores all native CALLs and clears ownership");

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
    // the addon's own tabs and scrollbar: whose tab a sprite is, the scrollbar's rows, the bounds normalized
    void* plain=image+6020;
    *reinterpret_cast<void**>(owner+0x80+7*8)=plain;
    uint32_t channel=99; bool chosenTab=true;
    Check(ChatTabChannel(owner,plain,channel,chosenTab) && channel==7 && !chosenTab,"a tab's plain sprite names its channel, not chosen");
    Check(ChatTabChannel(owner,chosen,channel,chosenTab) && channel==4 && chosenTab,"the chosen sprite names its channel, chosen");
    Check(!ChatTabChannel(owner,image+6030,channel,chosenTab) && !ChatTabChannel(nullptr,plain,channel,chosenTab),
        "a sprite that is none of the owner's tabs, or no owner, is no channel");
    uint8_t scrollObject[0x28]={};
    *reinterpret_cast<int32_t*>(scrollObject+0x0c)=20; *reinterpret_cast<int32_t*>(scrollObject+0x10)=75; *reinterpret_cast<int32_t*>(scrollObject+0x14)=30;
    ChatScrollInfo info;
    Check(ChatScrollRead(scrollObject,info) && info.page==20 && info.count==75 && info.top==30,"page rows, row count and rows above the view read from the scrollbar");
    *reinterpret_cast<int32_t*>(scrollObject+0x14)=80;
    Check(!ChatScrollRead(scrollObject,info),"more rows above the view than there are rows is no scrollbar");
    *reinterpret_cast<int32_t*>(scrollObject+0x14)=30; *reinterpret_cast<int32_t*>(scrollObject+0x0c)=0;
    Check(!ChatScrollRead(scrollObject,info) && !ChatScrollRead(reinterpret_cast<void*>(1),info),"an empty page, or an unreadable object, is no scrollbar");
    ChatBounds bounds;
    float rect[4];
    Check(!ChatNormalize(bounds,0,0,1000,500,rect),"nothing drawn gives no bounds");
    bounds.Add(100,50); bounds.Add(200,50); bounds.Add(200,80); bounds.Add(100,80);
    Check(ChatNormalize(bounds,0,0,1000,500,rect) && std::fabs(rect[0]-0.1005f)<1e-5f && std::fabs(rect[1]-0.101f)<1e-5f
        && std::fabs(rect[2]-0.2005f)<1e-5f && std::fabs(rect[3]-0.161f)<1e-5f,"bounds normalized to the viewport, the half pixel added");
    Check(ChatNormalize(bounds,100,50,1000,500,rect) && std::fabs(rect[0]-0.0005f)<1e-5f && std::fabs(rect[1]-0.001f)<1e-5f,"a viewport not at the origin is taken off first");
    Check(!ChatNormalize(bounds,0,0,0,500,rect),"an empty viewport gives no bounds");
    { const float lit[4]={0.1f,0.40f,0.9f,0.45f},inside[4]={0.12f,0.41f,0.5f,0.44f},edge[4]={0.12f,0.43f,0.5f,0.47f},below[4]={0.12f,0.46f,0.5f,0.49f};
      Check(ChatRowLit(inside,lit) && ChatRowLit(edge,lit) && !ChatRowLit(below,lit),"a row is lit where the selection art covers its middle"); }
    Check(ChatHidden(CHAT_REPLACE_TABS|CHAT_REPLACE_SCROLL,CHAT_REPLACE_TABS,true) && !ChatHidden(CHAT_REPLACE_SCROLL,CHAT_REPLACE_TABS,true)
        && !ChatHidden(CHAT_REPLACE_TABS,CHAT_REPLACE_TABS,false),"a control is hidden only when asked, and only in a skinned full log");
    void* current=chosen;
    { ChatOwnerScope first(current,owner); { ChatOwnerScope nested(current,nullptr); }
        Check(current==owner,"nested full-log drawing restores parent owner"); }
    Check(current==chosen,"content owner scope restores previous pointer on exit");

    // the rows of text: the drawer the content Draw calls at +AA, its one row-drawing call, cdecl with 22 words
    auto* drawer=image+6200; Pattern(drawer,CHAT_ROWS_DRAW_PATTERN);
    auto* rowSite=image+6300; Pattern(rowSite,CHAT_ROW_SITE_PATTERN);
    auto* rowDraw=image+6500; Pattern(rowDraw,CHAT_ROW_DRAW_PATTERN);
    Call(full+CHAT_ROWS_CALL,drawer); Call(rowSite+CHAT_ROW_SITE_CALL,rowDraw);
    memcpy(rowSite+CHAT_ROW_SITE_CALL+20,"\x83\xc4\x58",3); // the caller takes the words back once it has read its stack, as the client does
    auto textSite=DiscoverChatText(image,sizeof(image),full);
    Check(textSite.call==rowSite+CHAT_ROW_SITE_CALL && textSite.target==rowDraw,"the row site is the drawer's call to the row draw, the drawer the content Draw's callee at +AA");
    Call(full+CHAT_ROWS_CALL,image+4000);
    Check(!DiscoverChatText(image,sizeof(image),full).call,"the content Draw must call the drawer there");
    Call(full+CHAT_ROWS_CALL,drawer);
    Call(rowSite+CHAT_ROW_SITE_CALL,tabSprite);
    Check(!DiscoverChatText(image,sizeof(image),full).call,"the site's callee must be the row draw");
    Call(rowSite+CHAT_ROW_SITE_CALL,rowDraw);
    rowSite[CHAT_ROW_SITE_CALL+22]=0x54;
    Check(!DiscoverChatText(image,sizeof(image),full).call,"the caller must take back 22 words (add esp,58)");
    rowSite[CHAT_ROW_SITE_CALL+22]=0x58;
    Pattern(image+7000,CHAT_ROW_SITE_PATTERN);
    Check(!DiscoverChatText(image,sizeof(image),full).call,"an ambiguous row site is never patched");
    memset(image+7000,0,18);
    Check(!DiscoverChatText(image,sizeof(image),nullptr).call,"no content Draw, no text site");
    ChatTextSite textHook;
    Check(TakeChatText(textHook,DiscoverChatText(image,sizeof(image),full),image+5500) && VerifyCall(rowSite+CHAT_ROW_SITE_CALL,image+5500)
        && rowDraw[0]==0x8b && drawer[0]==0x83,"the row site redirected, the row draw and the drawer untouched");
    Check(!TakeChatText(textHook,textSite,image+5500),"a taken site is not taken twice");
    GiveChatText(textHook);
    Check(VerifyCall(rowSite+CHAT_ROW_SITE_CALL,rowDraw) && !textHook.call,"unload restores the row site");
    uint16_t rowText[4]={0x28,0x29,0x2a,0x2b}; ChatRowHeader header; for (unsigned i=0;i<60;i++) header.bytes[i]=uint8_t(i);
    ProbeRow(rowText,header,-3,17,0x7f,1,image+10,0);
    Check(seenText==rowText && !memcmp(seenHeader.bytes,header.bytes,60) && seenRow[0]==0xfffffffd && seenRow[1]==17 && seenRow[2]==0x7f
        && seenRow[3]==1 && seenRow[4]==uint32_t(reinterpret_cast<uintptr_t>(image+10)) && seenRow[5]==0,"the row draw's 22 words pass through by value, the header whole");
    // the row's header fields and its words decoded: the game's encoder round-trips through the decoder
    ChatRowInfo rowInfo; header.bytes[0]=9; header.bytes[0x10]=0x12; header.bytes[0x11]=0; header.bytes[0x12]=1; header.bytes[0x15]=0x40;
    Check(ChatRowFields(header,rowInfo) && rowInfo.mode==9 && rowInfo.words==0x12 && rowInfo.state==1 && rowInfo.marks==0x40,"the row's mode, words, cursor state and marks read from its header");
    header.bytes[0x10]=0xe3; header.bytes[0x11]=0x03;
    Check(!ChatRowFields(header,rowInfo),"more words than a row holds is no row");
    Check(ChatGlyphOf(0x81,0x40)==0x60 && ChatGlyphOf(0x88,0x9f)==0x400 && ChatGlyphOf(0x98,0x9f)==0xf95 && ChatGlyphOf(0xe0,0x40)==0x1517
        && ChatGlyphOf(0xed,0x40)==0x1fbe && ChatGlyphOf(0x87,0x7e)==0x3dd && ChatGlyphOf(0xef,0x1f)==CHAT_GLYPH_ICON_FIRST && ChatGlyphOf(0xfc,0xfc)==0xcb,
        "the encoder as the client has it: band starts, the pictographs and the overflow glyph");
    bool roundTrip=true; unsigned glyphs=0;
    for (unsigned lead=0x81;lead<=0xfc && roundTrip;lead++) {
        if (lead>0x9f && lead<0xe0) continue;
        for (unsigned trail=0x40;trail<=0xfc;trail++) {
            if (trail==0x7f) continue;
            const uint16_t glyph=ChatGlyphOf(uint8_t(lead),uint8_t(trail));
            uint8_t bytes[2]; const unsigned n=ChatGlyphBytes(glyph,bytes);
            if (n!=2 || ChatGlyphOf(bytes[0],bytes[1])!=glyph) { roundTrip=false; printf("  %02x %02x -> %x -> %u bytes %02x %02x\n",lead,trail,glyph,n,bytes[0],bytes[1]); break; }
            glyphs++;
        }
    }
    Check(roundTrip && glyphs==60*188,"every two-byte character decodes to bytes that encode to its glyph again");
    uint8_t one[2];
    bool ascii=true;
    for (unsigned c=0x20;c<0x7f;c++) if (ChatGlyphBytes(uint16_t(c-0x20),one)!=1 || one[0]!=c) ascii=false;
    Check(ascii && ChatGlyphBytes(0x5f,one)==1 && one[0]==0x20,"single bytes are their glyph and 20; glyph 5F, the name blank, a space");
    Check(ChatGlyphBytes(0x211d,one)==2 && one[0]==0xef && one[1]==0x27 && ChatGlyphBytes(CHAT_GLYPH_ICON_LAST,one)==2 && one[1]==0x4d,"the pictographs are EF 1F to EF 4D");
    Check(ChatGlyphBytes(CHAT_GLYPH_COUNT,one)==0 && ChatGlyphBytes(0x2950,one)==0,"a glyph past the font is no character");
    const uint16_t words[]={0x28,0x1fbe,0xfe00-0x0c,0x29,0xff00-0x50,0x2a,0xffcf,0x5f,0x211d,0x1f00,0x2b};
    char decoded[64]; bool cut=true;
    const uint32_t length=ChatDecodeRow(words,11,decoded,sizeof(decoded),cut);
    Check(length==14 && !cut && !memcmp(decoded,"H\xed\x40\x1f\x0cI\x1e\x50J \xef\x27?K",14),
        "a row's words decoded: characters, 1F and 1E colour codes, a 7F control left out, the blank, a pictograph, an unknown glyph a ?");
    Check(ChatDecodeRow(words,11,decoded,4,cut)==3 && cut,"no room for a whole character: cut there");
    Check(ChatDecodeRow(words,0,decoded,sizeof(decoded),cut)==0 && !cut,"an empty row");
    return failures?1:0;
}
