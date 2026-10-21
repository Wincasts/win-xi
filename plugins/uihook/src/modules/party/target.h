// Preserve the client's own overhead target/subtarget arrows while suppressing targetwi's HUD.
// Only the TWO calls that draw anc_l in Target::Draw are redirected, not the general sprite renderer.
#pragma once
#include <cmath>
// the lens plugin's warp, which bends the world under the menu layer the arrows are drawn on
#include "../../../../lens/src/warp.h"
#include "../../../../lens/src/shared.h"
using SpriteDraw = void(__fastcall*)(void*,void*,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
#define TARGET_GLOBAL_AT 0x23
#define SPRITE_PATTERN "83 EC 0C 53 55 56 8B F1 57 8B 6E 14 8D 4E 04 89 6C 24 18 89 4C 24 14 E8"
#define MAIN_ARROW_PATTERN "33 C9 8A 8E BA 00 00 00 68 80 80 80 E0 0F BF C0 8B 4C 8E 78 68 00 00 80 3F 68 00 00 80 3F 52 50 E8 ?? ?? ?? ??"
#define MAIN_ARROW_CALL 32
#define SUB_ARROW_PATTERN "33 C9 8A 8E BA 00 00 00 57 68 00 00 80 3F 68 00 00 80 3F 8B 4C 8E 78 52 50 E8 ?? ?? ?? ??"
#define SUB_ARROW_CALL 25

static uint8_t* UniquePattern(uint8_t* begin,size_t size,const char* pattern) {
    uint8_t* at=FindPattern(begin,size,pattern);
    if (!at) return nullptr;
    size_t next=static_cast<size_t>(at-begin)+1;
    return FindPattern(begin+next,size-next,pattern) ? nullptr : at;
}
static void** TargetGlobal(uint8_t* begin,size_t size,uintptr_t expected) {
    if (!expected) return nullptr;
    uint8_t* match=nullptr;
    for (size_t i=0;i+44<=size;i++) {
        const uint8_t* at=begin+i;
        if (memcmp(at,"menu    targetwi",16)) continue;
        bool padding=true;
        for (unsigned j=16;j<32;j++) if (at[j]) padding=false;
        uint32_t address=0; memcpy(&address,at+32,4);
        uintptr_t low=reinterpret_cast<uintptr_t>(begin);
        if (!padding || address!=expected || address<low || address>low+size-4 || address%4) continue;
        if (match) return nullptr;
        match=begin+i;
    }
    return match ? reinterpret_cast<void**>(expected) : nullptr;
}
// Scope only the two native anc_l calls; always restore suppression on return/unwind.
struct ArrowScope {
    bool& blocking;
    bool was;
    ArrowScope(bool& value,bool target) : blocking(value), was(value) { if (target) blocking=false; }
    ~ArrowScope() { blocking=was; }
};
struct ArrowCalls {
    uint8_t* main=nullptr;
    uint8_t* sub=nullptr;
    uint8_t* sprite=nullptr;
    uint8_t mainSaved[5]={}, subSaved[5]={};
};
static bool VerifyCall(uint8_t* call,uint8_t* target) {
    if (!call || call[0]!=0xe8) return false;
    int32_t distance=0; memcpy(&distance,call+1,4);
    return call+5+distance==target;
}
static void GiveArrows(ArrowCalls& arrows) {
    if (arrows.main) WriteCode(arrows.main,arrows.mainSaved,5);
    if (arrows.sub) WriteCode(arrows.sub,arrows.subSaved,5);
    arrows.main=arrows.sub=arrows.sprite=nullptr;
}
static bool TakeArrows(ArrowCalls& arrows,uint8_t* begin,size_t size,void* replacement) {
    uint8_t* main=UniquePattern(begin,size,MAIN_ARROW_PATTERN);
    uint8_t* sub=UniquePattern(begin,size,SUB_ARROW_PATTERN);
    uint8_t* sprite=UniquePattern(begin,size,SPRITE_PATTERN);
    if (!main || !sub || !sprite) return false;
    main+=MAIN_ARROW_CALL; sub+=SUB_ARROW_CALL;
    if (!VerifyCall(main,sprite) || !VerifyCall(sub,sprite)) return false;
    // Verify BOTH before writing either. E8 remains E8: this preserves the caller's return address.
    arrows.main=main; arrows.sub=sub; arrows.sprite=sprite;
    memcpy(arrows.mainSaved,main,5); memcpy(arrows.subSaved,sub,5);
    uint8_t* calls[2]={main,sub};
    for (uint8_t* call : calls) {
        uint8_t jump[5]={0xe8,0,0,0,0};
        int32_t distance=Distance(call+5,replacement); memcpy(jump+1,&distance,4);
        WriteCode(call,jump,5);
    }
    return true;
}

// Where lens's warp shows the point an arrow's tip is at: x and y in pixels of the menu layer (menuW
// by menuH, stretched over the whole screen, as the world picture is), moved in place. The game puts
// the arrow's tip at the target's place by the flat projection, and the anc_l sprite is drawn about
// its tip, so moving the one point moves the arrow. Nothing changes without a live warp. True when moved.
inline bool WarpArrow(int32_t& x,int32_t& y,int menuW,int menuH,const lens::Shared* warp) {
    if (!lens::Live(warp) || warp->Strength<=0.0f || warp->TanH<=0.0f || warp->TanV<=0.0f || menuW<=0 || menuH<=0) return false;
    double s=0,t=0;
    lens::ScreenOf(double(x)/menuW,double(y)/menuH,warp->TanH,warp->TanV,
        warp->Mode==lens::Cylindrical ? lens::Cylindrical : lens::Panini,warp->Strength,s,t);
    x=static_cast<int32_t>(std::lround(s*menuW));
    y=static_cast<int32_t>(std::lround(t*menuH));
    return true;
}
// The block lens.dll exports, while lens is loaded; nullptr otherwise.
inline const lens::Shared* LensBlock() {
    HMODULE module=GetModuleHandleA("lens.dll");
    return module ? reinterpret_cast<const lens::Shared*>(GetProcAddress(module,"LensWarp")) : nullptr;
}
