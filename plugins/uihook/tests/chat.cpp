#include <stdio.h>
#include "../src/modules/party/detour.h"
#include "../src/modules/party/target.h"
#include "../src/modules/chat/chat.h"
static int failures=0;
static void Check(bool ok,const char* text) { printf("%s %s\n",ok?"ok":"FAIL",text); if(!ok) ++failures; }
static void Pattern(uint8_t* at,const char* text) {
    while (*text) {
        if (*text==' ') { ++text; continue; }
        if (*text=='?') { *at++=0; text+=2; }
        else { char hex[3]={text[0],text[1],0}; *at++=static_cast<uint8_t>(strtoul(hex,nullptr,16)); text+=2; }
    }
}
int main() {
    uint8_t image[2048]={},owner[0x70]={},split[0x70]={},menu[0xf0]={},other[0xf0]={},header[128]={};
    auto* p=image+32; Pattern(p,CHAT_PATTERN);
    void** first=reinterpret_cast<void**>(image+256);
    void** second=reinterpret_cast<void**>(image+260);
    uint32_t a=reinterpret_cast<uintptr_t>(first),b=reinterpret_cast<uintptr_t>(second);
    memcpy(p+1,&a,4); memcpy(p+11,&b,4);
    ChatModule chat;
    Check(chat.Discover(image,sizeof(image)),"unique signature and in-module globals");
    Check(chat.Identify(menu)==-1 && chat.Identify(nullptr)==-1,"null owners/windows harmless");
    *first=owner; *second=split;
    *reinterpret_cast<void**>(owner+8)=menu;
    *reinterpret_cast<void**>(split+8)=other;
    *reinterpret_cast<void**>(menu+4)=header;
    *reinterpret_cast<void**>(other+4)=header;
    memcpy(header+0x46,"menu    logwindo",16);
    Check(chat.Identify(menu)==0 && chat.Identify(other)==1,"primary and split independent");
    header[0x46]='x'; Check(chat.Identify(menu)==-1,"wrong menu rejected (expanded log untouched)"); header[0x46]='m';
    *reinterpret_cast<void**>(owner+8)=nullptr;
    Check(chat.Identify(menu)==-1,"destroyed child not cached");
    *reinterpret_cast<void**>(owner+8)=menu;
    Check(chat.Identify(menu)==0,"recreated child followed");
    *first=reinterpret_cast<void*>(1);
    Check(chat.Identify(menu)==-1,"unreadable owner rejected"); *first=owner;
    Pattern(image+80,CHAT_PATTERN);
    Check(!chat.Discover(image,sizeof(image)) && chat.Identify(menu)==-1,"ambiguous discovery clears prior slots");
    memset(image+80,0,22); b=a; memcpy(p+11,&b,4);
    Check(!chat.Discover(image,sizeof(image)),"aliased slots rejected");
    b=1; memcpy(p+11,&b,4);
    Check(!chat.Discover(image,sizeof(image)),"out-of-module slot rejected");
    b=reinterpret_cast<uintptr_t>(second); memcpy(p+11,&b,4);
    Check(chat.Discover(image,sizeof(image)) && !chat.InputSupported(),"missing input signature leaves logs working");
    uint8_t input[0xf0]={},inputHeader[128]={};
    *reinterpret_cast<void**>(input+4)=inputHeader;
    memcpy(inputHeader+0x46,"menu    inline  ",16);
    auto** active=reinterpret_cast<void**>(image+264);
    uint32_t activeAddress=reinterpret_cast<uintptr_t>(active);
    Pattern(image+320,CHAT_INPUT_PATTERN); memcpy(image+336,&activeAddress,4);
    Check(chat.Discover(image,sizeof(image)) && chat.InputSupported(),"independent input capability discovered");
    *active=input;
    Check(chat.Identify(input)==2 && chat.Identify(menu)==0,"input and log slots independent");
    *active=nullptr; Check(chat.Identify(input)==-1,"closed input never replayed");
    *active=input; inputHeader[0x46]='x';
    Check(chat.Identify(input)==-1,"active unrelated menu not hidden"); inputHeader[0x46]='m';
    inputHeader[0x46+14]=inputHeader[0x46+15]=0;
    Check(chat.Identify(input)==2,"null padded inline name accepted");
    Pattern(image+368,CHAT_INPUT_PATTERN);
    Check(chat.Discover(image,sizeof(image)) && !chat.InputSupported() && chat.Identify(menu)==0,"ambiguous input disables input only");
    memset(image+368,0,16);
    activeAddress=1; memcpy(image+336,&activeAddress,4);
    Check(chat.Discover(image,sizeof(image)) && !chat.InputSupported(),"invalid input slot rejected");
    activeAddress=reinterpret_cast<uintptr_t>(active); memcpy(image+336,&activeAddress,4);
    uint8_t fullOwner[0xe4]={},fullWindow[0xf0]={},fullHeader[128]={};
    auto** full=reinterpret_cast<void**>(image+268); *full=fullOwner;
    *reinterpret_cast<void**>(fullOwner+8)=fullWindow;
    *reinterpret_cast<void**>(fullWindow+4)=fullHeader;
    memcpy(fullHeader+0x46,"menu    fulllog ",16);
    Pattern(image+512,CHAT_FULL_PATTERN);
    uint32_t vtable=reinterpret_cast<uintptr_t>(image+1024);
    memcpy(image+560,&vtable,4); memcpy(fullOwner,&vtable,4);
    uint32_t update=reinterpret_cast<uintptr_t>(image+1360); memcpy(image+1064,&update,4);
    Pattern(image+576,CHAT_FULL_INIT_PATTERN); Pattern(image+1408,CHAT_FULL_FIELDS_PATTERN);
    Pattern(image+1600,CHAT_FULL_DRAW_PATTERN);
    uint32_t draw=reinterpret_cast<uintptr_t>(image+1600); memcpy(image+1040,&draw,4);
    Pattern(image+1880,CHAT_LINES_UPDATE_PATTERN); Pattern(image+1920,CHAT_LINES_GROW_PATTERN);
    Pattern(image+608,CHAT_STATE_PATTERN);
    uint32_t manager=reinterpret_cast<uintptr_t>(image+1100);
    memcpy(image+612,&manager,4);
    auto* registry=image+672;
    memcpy(registry,"menu    logwindo",16); memcpy(registry+44,"menu    logwin2 ",16); memcpy(registry+88,"menu    fulllog ",16);
    uint32_t pointers[]={a,b,reinterpret_cast<uintptr_t>(full)};
    for (unsigned j=0;j<3;j++) memcpy(registry+44*j+32,&pointers[j],4);
    Check(chat.Discover(image,sizeof(image)) && chat.ExpandedSupported(),"full-log registry cross-checked against log globals, state and layout signatures");
    Check(chat.ExpandedDraw()==image+1600,"expanded content signature must match full-log vtable Draw entry");
    uint32_t wrongDraw=draw+1; memcpy(image+1040,&wrongDraw,4);
    Check(chat.Discover(image,sizeof(image)) && !chat.ExpandedDraw() && chat.ExpandedSupported(),
        "wrong Draw entry disables skin only, not native state/compact support");
    memcpy(image+1040,&draw,4);
    Pattern(image+1664,CHAT_FULL_DRAW_PATTERN);
    Check(chat.Discover(image,sizeof(image)) && !chat.ExpandedDraw(),"ambiguous content signature never hooked");
    memset(image+1664,0,20); chat.Discover(image,sizeof(image));
    Detour content={CHAT_FULL_DRAW_PATTERN,5,-1,reinterpret_cast<void*>(image+1800),nullptr,nullptr,{}};
    Check(Take(content,image,sizeof(image)) && content.target==image+1600 && content.trampoline,
        "content detour uses the same unique verified entry");
    const uint8_t prefix[]={0x83,0xec,0x0c,0x53,0x55};
    Check(content.trampoline && !memcmp(content.trampoline,prefix,5) && content.trampoline[5]==0xe9,
        "content trampoline preserves whole stack/local/register instructions");
    Give(content);
    Check(!memcmp(image+1600,prefix,5) && !content.target && !content.trampoline,
        "content hook unload restores bytes and frees trampoline");
    ChatShared state={};
    *active=menu; menu[0x62]=menu[0x63]=1;
    chat.Sample(state,12);
    Check(state.StateFrame==12 && state.StateFlags==CHAT_SELECTED_PRIMARY,"native window focus and cursor enable select the primary panel");
    menu[0x63]=0; chat.Sample(state,12);
    Check(state.StateFlags==0,"no highlight without native cursor focus");
    *active=other; other[0x62]=other[0x63]=1; chat.Sample(state,12);
    Check(state.StateFlags==CHAT_SELECTED_SPLIT,"split-log focus selects combined replacement");
    *active=input; chat.Sample(state,12);
    Check(state.StateFlags==0,"typing is not window selection");
    image[1100+0xf1]=3;
    *reinterpret_cast<int32_t*>(fullOwner+0x1c)=20;
    *reinterpret_cast<int32_t*>(fullOwner+0x58)=20;
    *active=menu; chat.Sample(state,12);
    Check(state.StateFlags==CHAT_EXPANDED,"opening: focus still on the log window is not history browsing");
    *active=nullptr; chat.Sample(state,12);
    Check(state.StateFlags==CHAT_EXPANDED,"opening: no focus yet is not history browsing");
    *reinterpret_cast<void**>(fullOwner+8)=nullptr; *active=menu; chat.Sample(state,12);
    Check(state.StateFlags==CHAT_EXPANDED,"opening: full log not made yet");
    *active=input; chat.Sample(state,12);
    Check(state.StateFlags==(CHAT_EXPANDED|CHAT_NATIVE_BROWSE),"another menu before the full log is made stays native");
    *reinterpret_cast<void**>(fullOwner+8)=fullWindow;
    *active=fullWindow; chat.Sample(state,12);
    Check(chat.Identify(fullWindow)==3 && state.StateFlags==CHAT_EXPANDED && state.FullPageRows==20,"native expanded newest/all view recognised");
    *reinterpret_cast<int32_t*>(fullOwner+0x1c)=19; chat.Sample(state,12);
    Check(state.StateFlags==CHAT_EXPANDED && state.FullCursor==19,"mouse hover cursor movement keeps the native content and frame skin");
    *reinterpret_cast<int32_t*>(fullOwner+0x1c)=1; chat.Sample(state,12);
    Check(state.StateFlags==CHAT_EXPANDED && state.FullCursor==1,"hovering the oldest visible row keeps native content");
    *active=input; chat.Sample(state,12);
    Check(state.StateFlags==(CHAT_EXPANDED|CHAT_NESTED_MENU) && state.FullCursor==1,"a menu opened from a hovered row: the log keeps its skin under it, the menu noted");
    state.SupportedMask=CHAT_FULL_SKIN_SUPPORTED;
    Check(ChatReplayAllowed(state,true),"the skin is replayed under a row's action menu");
    state.SupportedMask=0;
    *active=fullWindow;
    *reinterpret_cast<int32_t*>(fullOwner+0x1c)=20;
    *reinterpret_cast<int32_t*>(fullOwner+0x20)=1; chat.Sample(state,12);
    Check(state.StateFlags==CHAT_EXPANDED && state.FullScroll==1,"scrolled history retains frame-only skin and native contents");
    *reinterpret_cast<int32_t*>(fullOwner+0x20)=0;
    *reinterpret_cast<int32_t*>(fullOwner+0x54)=9; chat.Sample(state,12);
    Check(state.StateFlags==CHAT_EXPANDED && state.FullFilter==9,"channel filters are diagnostic; native tabs and content remain in control");
    *reinterpret_cast<int32_t*>(fullOwner+0x20)=1; chat.Sample(state,12);
    Check(state.StateFlags==CHAT_EXPANDED,"older channel pages retain the skin without replacing rows");
    *reinterpret_cast<int32_t*>(fullOwner+0x20)=0;
    *reinterpret_cast<int32_t*>(fullOwner+0x54)=16; chat.Sample(state,12);
    Check(state.StateFlags & CHAT_NATIVE_BROWSE,"an unknown filter value is invalid layout data");
    *reinterpret_cast<int32_t*>(fullOwner+0x54)=0;
    *active=input; chat.Sample(state,12);
    Check(state.StateFlags==(CHAT_EXPANDED|CHAT_NESTED_MENU),"input open over the live full log keeps its skin");
    *reinterpret_cast<uint32_t*>(fullOwner)=0;
    Check(chat.Identify(fullWindow)==-1,"wrong full-log vtable never claimed"); memcpy(fullOwner,&vtable,4);
    memcpy(image+840,registry,132);
    Check(chat.Discover(image,sizeof(image)) && !chat.ExpandedSupported() && chat.Identify(menu)==0,"ambiguous registry disables expansion only");
    memset(image+840,0,132); memset(image+512,0,59);
    Check(chat.Discover(image,sizeof(image)) && !chat.ExpandedSupported(),"missing verified layout leaves expanded history native");
    chat.Clear();
    Check(chat.Identify(menu)==-1,"release clears recognition");
    Check(sizeof(ChatShared)==71684,"chat ABI 13: the rows of text, the two log windows' bounds, routing, lines and the game's colours");
    // each window's lines now, most and fewest, read from its owner with the fields' sense checked
    chat.Discover(image,sizeof(image));
    Check(chat.LinesSupported(),"the owners' line fields pinned by the Update and grow signatures");
    *first=owner; *second=split;
    auto fill=[](uint8_t* at,int8_t now,int16_t most,int16_t fewest,int16_t row,int32_t height) {
        at[0x31]=uint8_t(now); memcpy(at+0x4e,&most,2); memcpy(at+0x50,&fewest,2); memcpy(at+0x54,&row,2); memcpy(at+0x34,&height,4); };
    fill(owner,3,8,0,16,48); fill(split,0,6,0,16,0);
    ChatShared lines={}; chat.SampleLines(lines,21);
    Check(lines.LinesFrame==21 && lines.Lines[0][0]==3 && lines.Lines[0][1]==8 && lines.Lines[0][2]==0 && lines.Lines[1][0]==0 && lines.Lines[1][1]==6,"the first at three of eight lines, the second at none of six");
    fill(owner,9,8,0,16,144); chat.SampleLines(lines,22);
    Check(lines.LinesFrame==22 && lines.Lines[0][0]==9,"a row more than most, the one scrolling in, is allowed");
    fill(owner,10,8,0,16,160); chat.SampleLines(lines,23);
    Check(lines.LinesFrame==0,"more than that makes no sense: nothing published");
    fill(owner,3,8,9,16,48); chat.SampleLines(lines,24);
    Check(lines.LinesFrame==0,"fewest past most: nothing");
    fill(owner,3,8,0,2,48); chat.SampleLines(lines,25);
    Check(lines.LinesFrame==0,"a row height of two: nothing");
    fill(owner,3,8,0,16,48); *second=nullptr; chat.SampleLines(lines,26);
    Check(lines.LinesFrame==0,"a missing owner: nothing"); *second=split;
    chat.SampleLines(lines,27); Check(lines.LinesFrame==27,"whole again");
    Pattern(image+1960,CHAT_LINES_GROW_PATTERN); chat.Discover(image,sizeof(image));
    Check(!chat.LinesSupported(),"an ambiguous grow signature leaves the lines unread");
    chat.SampleLines(lines,28); Check(lines.LinesFrame==0,"and nothing published");
    memset(image+1960,0,24); chat.Discover(image,sizeof(image));
    ChatShared shared={}; shared.SupportedMask=1; shared.Frame=10;
    shared.PrimaryRectFrame=shared.ReplacementRectFrame=shared.NativeFrame[0]=shared.DrawnFrame[0]=10;
    shared.PrimaryRect[0]=0.1f; shared.PrimaryRect[1]=0.5f; shared.PrimaryRect[2]=0.7f; shared.PrimaryRect[3]=0.9f;
    shared.ReplacementRect[0]=100; shared.ReplacementRect[1]=300; shared.ReplacementRect[2]=700; shared.ReplacementRect[3]=900;
    float dx=0,dy=0;
    Check(ChatClockOffset(shared,1000,1000,dx,dy) && dx==0 && dy==-200,"whole clock follows replacement top, preserving stock gap");
    const float primaryBox[]={100,300,700,900}, upperBox[]={120,100,620,300};
    ChatClockAnchor(shared,0,primaryBox);
    ChatClockAnchor(shared,1,upperBox);
    Check(shared.ReplacementRect[0]==120 && shared.ReplacementRect[1]==100 && shared.ReplacementRect[2]==620,
        "stacked split supplies the clock top edge and width");
    shared.SplitRectFrame=shared.NativeFrame[1]=shared.DrawnFrame[1]=10;
    shared.SplitRect[0]=0.1f; shared.SplitRect[1]=0.25f; shared.SplitRect[2]=0.7f; shared.SplitRect[3]=0.5f;
    Check(ChatClockOffset(shared,1000,1000,dx,dy) && dx==20 && dy==-150,
        "clock preserves gap from upper native log, not lower primary");
    ChatClockAnchor(shared,0,primaryBox);
    Check(shared.ReplacementRect[1]==300,"primary recapture resets vanished split anchor");
    const float beside[]={710,100,900,300}, below[]={100,900,700,1000};
    ChatClockAnchor(shared,1,beside);
    Check(shared.ReplacementRect[0]==100 && shared.ReplacementRect[1]==300,"side-by-side log leaves primary anchor");
    ChatClockAnchor(shared,1,below);
    Check(shared.ReplacementRect[1]==300,"split below primary leaves primary anchor");
    shared.Frame=11; ChatClockAnchor(shared,1,upperBox);
    Check(shared.ReplacementRectFrame==10,"split cannot revive a missing primary capture"); shared.Frame=10;
    shared.SplitRectFrame=shared.NativeFrame[1]=shared.DrawnFrame[1]=0;
    Check(!ChatDeferPrimary(shared,true),"no second log drawn: the first is not held back");
    shared.NativeFrame[1]=9;
    Check(ChatDeferPrimary(shared,true),"second log replaced last frame: the first waits to be drawn over it");
    Check(!ChatDeferPrimary(shared,false),"second log not captured: the first drawn in its turn");
    shared.NativeFrame[1]=10;
    Check(!ChatDeferPrimary(shared,true),"second log already drawn this frame: the first is on top in its turn");
    shared.NativeFrame[1]=8;
    Check(!ChatDeferPrimary(shared,true),"second log gone a frame: the first not held for it");
    shared.NativeFrame[1]=9; shared.StateFlags=CHAT_EXPANDED;
    Check(!ChatDeferPrimary(shared,true),"full log open: nothing held back");
    shared.NativeFrame[1]=0;
    Check(!ChatClockOffset(shared,1000,1000,dx,dy),"expanded log cannot relocate the compact clock group");
    Check(!ChatReplayAllowed(shared,false),"compact capture cannot cover a newly expanded native log");
    Check(!ChatReplayAllowed(shared,true),"missing content capability cannot hide native expanded rows");
    shared.SupportedMask |= CHAT_FULL_SKIN_SUPPORTED;
    Check(ChatReplayAllowed(shared,true),"expanded frame-only capture allowed with verified content hook");
    shared.StateFlags=CHAT_SELECTED_PRIMARY;
    Check(ChatReplayAllowed(shared,false) && !ChatReplayAllowed(shared,true),"compact ignores stale expanded captures");
    shared.StateFlags=CHAT_EXPANDED|CHAT_NATIVE_BROWSE;
    Check(!ChatReplayAllowed(shared,true) && !ChatReplayAllowed(shared,false),"nested native menus cannot be suppressed");
    bool blocked=true;
    ChatNativeContent(false,false,blocked); Check(blocked,"non-expanded rendering stays blocked");
    ChatNativeContent(true,true,blocked); Check(blocked,"a mirrored full log stays blocked: its content, cursor and scrollbar undrawn");
    ChatNativeContent(true,false,blocked); Check(!blocked,"native expanded content, then cursor and scrollbar, draw unblocked");
    Check(ChatReplaceGranted(CHAT_REPLACE_TABS|CHAT_REPLACE_SCROLL|CHAT_REPLACE_TEXT|CHAT_REPLACE_ALL,true,true)==15,"all of it granted with every hook");
    Check(ChatReplaceGranted(CHAT_REPLACE_TABS|CHAT_REPLACE_TEXT|CHAT_REPLACE_ALL,true,true)==(CHAT_REPLACE_TABS|CHAT_REPLACE_TEXT|CHAT_REPLACE_ALL),
        "the whole log without the scrollbar asked: the game draws none where every row fits");
    Check(ChatReplaceGranted(CHAT_REPLACE_TABS|CHAT_REPLACE_SCROLL|CHAT_REPLACE_TEXT|CHAT_REPLACE_ALL,true,false)==(CHAT_REPLACE_TABS|CHAT_REPLACE_SCROLL),
        "no row site: neither the text nor the whole log");
    Check(ChatReplaceGranted(CHAT_REPLACE_SCROLL|CHAT_REPLACE_TEXT|CHAT_REPLACE_ALL,true,true)==(CHAT_REPLACE_SCROLL|CHAT_REPLACE_TEXT),
        "the whole log only with the addon's tabs as well");
    Check(ChatReplaceGranted(CHAT_REPLACE_TABS|CHAT_REPLACE_TEXT|CHAT_REPLACE_ALL,false,true)==CHAT_REPLACE_TEXT,"no control hooks: the text alone");
    shared.StateFlags=0;
    shared.Frame=13;
    Check(!ChatClockOffset(shared,1000,1000,dx,dy) && dx==0 && dy==0,"stale log cannot move clock"); shared.Frame=10;
    shared.DrawnFrame[0]=0;
    Check(!ChatClockOffset(shared,1000,1000,dx,dy),"log not replayed cannot move clock"); shared.DrawnFrame[0]=10;
    shared.ReplacementRectFrame=0;
    Check(!ChatClockOffset(shared,1000,1000,dx,dy),"released/empty log restores native clock"); shared.ReplacementRectFrame=10;
    // the game's own stamps are fresh; the addon's place for its log is eight frames old, then nine
    shared.Frame=18; shared.PrimaryRectFrame=shared.NativeFrame[0]=shared.DrawnFrame[0]=18;
    Check(ChatClockOffset(shared,1000,1000,dx,dy),"the clock still follows a log the addon placed a few frames ago");
    shared.Frame=19; shared.PrimaryRectFrame=shared.NativeFrame[0]=shared.DrawnFrame[0]=19;
    Check(!ChatClockOffset(shared,1000,1000,dx,dy),"nor past eight");
    shared.Frame=shared.PrimaryRectFrame=shared.NativeFrame[0]=shared.DrawnFrame[0]=10;
    shared.ReplacementRect[1]=NAN;
    Check(!ChatClockOffset(shared,1000,1000,dx,dy),"invalid bounds cannot move clock");
    float verts[]={10,20,123,30,40,456};
    Check(ChatTranslateVertices(verts,2,12,5,-10) && verts[0]==15 && verts[1]==10 && verts[2]==123
        && verts[3]==35 && verts[4]==30 && verts[5]==456,"clock translation preserves other vertex fields");
    Check(!ChatTranslateVertices(verts,4097,12,0,1),"clock translation geometry bounded");
    // reads are served from the regions found readable this frame: one past a region's end is refused
    // whether or not the region is cached, and one inside a cached region is served
    {
        auto* page=static_cast<uint8_t*>(VirtualAlloc(nullptr,4096,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE));
        uint32_t word=0;
        ChatReadReset();
        Check(page && ChatRead(page+4092,&word,4),"a read ending at a region's end served");
        Check(!ChatRead(page+4094,&word,4),"a read past the region refused once it is cached");
        Check(ChatRead(page,&word,4) && ChatRead(page+100,&word,4),"reads inside a cached region served");
        Check(!ChatRead(nullptr,&word,4) && !ChatRead(page,&word,0),"null and empty reads refused");
        VirtualFree(page,0,MEM_RELEASE);
        ChatReadReset();
    }
    return failures?1:0;
}
