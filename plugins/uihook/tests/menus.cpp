#include <stdio.h>
#include "../src/modules/party/detour.h"
#include "../src/modules/party/target.h"
#include "../src/modules/chat/chat.h"
#include "../src/modules/chat/menus.h"
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
    Check(sizeof(MenuShared)==108,"independent menu ABI size");
    MenuShared state={"UIHOOK-MENUS",1,sizeof(MenuShared),100,1,100,0,{20,700,660,718},0,0,0,{},0,{},0,0,0};
    ChatShared chat={}; chat.DrawnFrame[0]=100;
    Check(MenuFresh(state,chat,100),"fresh successful host capture");
    Check(!MenuFresh(state,chat,103),"expired source cannot move menus");
    state.HostSlot=3; Check(!MenuFresh(state,chat,100),"invalid host rejected"); state.HostSlot=0;
    chat.StateFlags=CHAT_EXPANDED; Check(!MenuFresh(state,chat,100),"expanded chat restores menus"); chat.StateFlags=0;
    chat.DrawnFrame[0]=0; Check(!MenuFresh(state,chat,100),"no native capture replay, no anchor"); chat.DrawnFrame[0]=100;
    int dimensions[2]={1280,960}; int16_t original[4]={0,700,120,100},xy[2]={};
    float panel[4]={20,700,660,718};
    Check(MenuPosition(original,false,dimensions,1280,960,panel,xy) && xy[0]==20 && xy[1]==598,"raw native geometry clears panel by two pixels");
    Check(MenuPosition(original,true,dimensions,1280,960,panel,xy) && xy[0]==10 && xy[1]==249,"scaled native geometry uses menu manager, not viewport guessing");
    original[3]=900; Check(!MenuPosition(original,false,dimensions,1280,960,panel,xy),"oversized list stays native, not clipped"); original[3]=100;
    panel[0]=-1; Check(!MenuPosition(original,false,dimensions,1280,960,panel,xy),"offscreen panel rejected"); panel[0]=20;
    panel[0]=NAN; Check(!MenuPosition(original,false,dimensions,1280,960,panel,xy),"NaN rejected"); panel[0]=20;
    auto* image=static_cast<uint8_t*>(VirtualAlloc(nullptr,4096,MEM_COMMIT|MEM_RESERVE,PAGE_EXECUTE_READWRITE));
    auto* updater=image+256; Pattern(updater,MENU_UPDATE_PATTERN); Pattern(updater+0x150,MENU_TARGET_PROOF);
    // Callable fixture: original prologue, helper returns zero, then native early-out epilogue.
    int32_t relative=0x110-14; memcpy(updater+10,&relative,4);
    relative=0x100-26; memcpy(updater+22,&relative,4);
    const uint8_t end[]={0x5e,0x83,0xc4,0x08,0xc3}; memcpy(updater+0x100,end,sizeof(end));
    updater[0x110]=0x33; updater[0x111]=0xc0; updater[0x112]=0xc3;
    auto* renderer=image+32; renderer[9]=0xe8; relative=static_cast<int32_t>(updater-(renderer+14)); memcpy(renderer+10,&relative,4);
    auto* row=image+1280; memcpy(row,"menu    playermo",16);
    auto** global=reinterpret_cast<void**>(image+2048); uintptr_t address=reinterpret_cast<uintptr_t>(global); memcpy(row+32,&address,4);
    auto* secondRow=row+44; memcpy(secondRow,"menu    magselec",16);
    auto** secondGlobal=reinterpret_cast<void**>(image+2052); address=reinterpret_cast<uintptr_t>(secondGlobal); memcpy(secondRow+32,&address,4);
    uint8_t owner[128]={},window[0xa0]={},header[128]={},other[0xa0]={},magicOwner[128]={},magicWindow[0xa0]={};
    *secondGlobal=magicOwner; void* magic=magicWindow; memcpy(magicOwner+8,&magic,4);
    magic=header; memcpy(magicWindow+4,&magic,4);
    int16_t magicTarget[4]={80,400,160,200}; memcpy(magicWindow+0x8c,magicTarget,8);
    *global=owner;
    void* ptr=window; memcpy(owner+8,&ptr,4); ptr=header; memcpy(window+4,&ptr,4);
    memcpy(header+0x46,"menu    comwin  ",16); memcpy(window+0x8c,original,8);
    int32_t animation=8; memcpy(window+0x94,&animation,4);
    MenuModule menus;
    Check(menus.Discover(image,4096,renderer),"unique update, exact Render call, four layout fields and live registry");
    menus.Before(other,state,true,dimensions,1280,960);
    Check(state.Applied==0,"unregistered windows never moved");
    menus.Before(window,state,true,dimensions,1280,960);
    int16_t target[4]; memcpy(target,window+0x8c,8); memcpy(&animation,window+0x94,4);
    Check(target[0]==20 && target[1]==598 && target[2]==120 && target[3]==100 && animation==-1,"native target moves before its own single Update; size unchanged");
    Check(state.Applied==1 && !memcmp(state.LastName,"menu    playermo",16),"menu diagnostics");
    menus.Before(window,state,true,dimensions,1280,960);
    Check(state.Applied==1,"stable target not rewritten or reticked each frame");
    menus.Before(magicWindow,state,true,dimensions,1280,960);
    memcpy(target,magicWindow+0x8c,8);
    Check(target[0]==20 && target[1]==498 && target[2]==160 && target[3]==200,"submenu keeps native dimensions and independently clears panel");
    menus.Stop(state); memcpy(target,window+0x8c,8);
    Check(target[0]==0 && target[1]==700 && state.Restored==2,"stop restores native target and rebuilds native geometry");
    menus.Before(window,state,true,dimensions,1280,960);
    int16_t gameX=44; memcpy(window+0x8c,&gameX,2);
    menus.Stop(state); memcpy(target,window+0x8c,8);
    Check(target[0]==44 && target[1]==700,"restoration never overwrites a newer native x value");
    menus.Before(window,state,true,dimensions,1280,960);
    *global=nullptr; menus.Stop(state);
    Check(state.Restored==3,"destroyed owner not dereferenced or restored"); *global=owner;
    // The expanded log, placed by its bottom-left: the same move, its size the game's, kept on the screen
    int16_t logTarget[4]={0,100,320,400},placed[2]={};
    float place[2]={20,700};
    Check(LogPosition(logTarget,false,dimensions,1280,960,place,placed) && placed[0]==20 && placed[1]==300,"the log's bottom-left where asked");
    Check(LogPosition(logTarget,true,dimensions,1280,960,place,placed) && placed[0]==10 && placed[1]==0,
        "scaled units; a log that would rise past the top is kept at it");
    place[0]=1200; Check(LogPosition(logTarget,false,dimensions,1280,960,place,placed) && placed[0]==960,"moved left to stay on the screen"); place[0]=20;
    logTarget[3]=1000; Check(!LogPosition(logTarget,false,dimensions,1280,960,place,placed),"taller than the screen: left where the game puts it"); logTarget[3]=400;
    place[1]=NAN; Check(!LogPosition(logTarget,false,dimensions,1280,960,place,placed),"NaN rejected"); place[1]=700;
    state.LogRequestFrame=100; Check(LogFresh(state,102) && !LogFresh(state,103),"a request two frames old at most");
    uint8_t logOwner[128]={},logWindow[0xa0]={},logHeader[128]={};
    auto** logGlobal=reinterpret_cast<void**>(image+2060); *logGlobal=logOwner;
    ptr=logWindow; memcpy(logOwner+8,&ptr,4); ptr=logHeader; memcpy(logWindow+4,&ptr,4);
    memcpy(logHeader+0x46,"menu    fulllog ",16); memcpy(logWindow+0x8c,logTarget,8);
    state.LogPlace[0]=20; state.LogPlace[1]=700;
    menus.BeforeLog(logWindow,state,true,dimensions,1280,960);
    Check(state.LogApplied==0,"no owner global from the chat module: never moved");
    menus.Log(logGlobal);
    menus.BeforeLog(window,state,true,dimensions,1280,960);
    Check(state.LogApplied==0,"another window is not the log");
    menus.BeforeLog(logWindow,state,true,dimensions,1280,960);
    memcpy(target,logWindow+0x8c,8); memcpy(&animation,logWindow+0x94,4);
    Check(target[0]==20 && target[1]==300 && target[2]==320 && target[3]==400 && animation==-1 && state.LogApplied==1,
        "the log's target moved before its own Update, its size kept");
    menus.BeforeLog(logWindow,state,true,dimensions,1280,960);
    Check(state.LogApplied==1,"held there, not rewritten each frame");
    state.LogPlace[1]=650; menus.BeforeLog(logWindow,state,true,dimensions,1280,960); memcpy(target,logWindow+0x8c,8);
    Check(target[1]==250 && state.LogApplied==2,"a new place followed");
    menus.Stop(state); memcpy(target,logWindow+0x8c,8);
    Check(target[1]==250,"giving the menus back leaves the log alone");
    menus.BeforeLog(logWindow,state,false,dimensions,1280,960); memcpy(target,logWindow+0x8c,8);
    Check(target[0]==0 && target[1]==100 && state.LogRestored==1,"no request: the game's place given back");
    menus.BeforeLog(logWindow,state,true,dimensions,1280,960);
    *logGlobal=nullptr; menus.StopLog(state); memcpy(target,logWindow+0x8c,8);
    Check(target[1]==250 && state.LogRestored==1,"a log the game has let go is not written"); *logGlobal=logOwner;
    Pattern(image+3000,MENU_UPDATE_PATTERN);
    Check(!menus.Discover(image,4096,renderer),"ambiguous updater disables all menu writes"); memset(image+3000,0,32);
    updater[0x150]=0;
    Check(!menus.Discover(image,4096,renderer),"missing native field proof disables menu writes"); Pattern(updater+0x150,MENU_TARGET_PROOF);
    memcpy(image+1400,row,44); address=reinterpret_cast<uintptr_t>(image+2052); memcpy(image+1432,&address,4);
    Check(!menus.Discover(image,4096,renderer),"ambiguous root registry disables menu writes");
    VirtualFree(image,0,MEM_RELEASE);
    return failures ? 1 : 0;
}
