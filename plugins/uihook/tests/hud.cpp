#include <stdio.h>
#include "../src/modules/party/detour.h"
#include "../src/modules/party/target.h"
#include "../src/modules/party/hud.h"
static int failures=0;
static void Check(bool ok,const char* text) { printf("%s %s\n",ok?"ok":"FAIL",text); if(!ok) ++failures; }
static void Pattern(uint8_t* at,const char* text) {
    while (*text) {
        if (*text==' ') { ++text; continue; }
        if (*text=='?') { *at++=0; text+=2; }
        else { char hex[3]={text[0],text[1],0}; *at++=static_cast<uint8_t>(strtoul(hex,nullptr,16)); text+=2; }
    }
}
static void Relative(uint8_t* at,uint8_t* target,uint8_t opcode=0xe8) {
    *at=opcode; int32_t rel=static_cast<int32_t>(target-at-5); memcpy(at+1,&rel,4);
}
static void* seenThis=nullptr;
static int32_t seenX=0,seenY=0;
static int __fastcall Replacement(void* self,void*,int32_t x,int32_t y) {
    seenThis=self; seenX=x; seenY=y; return 99;
}
int main() {
    auto* image=static_cast<uint8_t*>(VirtualAlloc(nullptr,8192,MEM_COMMIT|MEM_RESERVE,PAGE_EXECUTE_READWRITE));
    memset(image,0xcc,8192);
    auto* step=image+0x80; auto* compass=image+0x100; auto* clock=image+0xb00;
    auto* compact=compass+0x60; auto* radar=compass+0x600; auto* visible=image+0xd00;
    Pattern(step,COMPASS_STEP_PATTERN); Pattern(compass,COMPASS_DRAW_PATTERN); Pattern(clock,CLOCK_DRAW_PATTERN);
    Pattern(compact,CLOCK_SMALL_PATTERN); Pattern(radar,CLOCK_RADAR_PATTERN); Pattern(visible,RADAR_VISIBLE_PATTERN);
    Pattern(clock+0xc8,CLOCK_WEATHER_PATTERN);
    uint32_t global=reinterpret_cast<uintptr_t>(image+0x1f00);
    memcpy(step+2,&global,4); memcpy(step+31,&global,4);
    uint32_t weather=global+4; memcpy(clock+0xca,&weather,4);
    Relative(step+35,compass,0xe9); Relative(compact+4,clock); Relative(radar+8,clock); Relative(compass+0x44,visible);
    auto found=FindHud(image,8192);
    Check(found.compass==compass && found.clock==clock && found.global==reinterpret_cast<void**>(global),
        "clock and compass independently identified from hidecompass step + both clock calls");
    Check(found.radarVisible==visible && found.weather==reinterpret_cast<uint16_t*>(weather),
        "native radar visibility query and weather source independently verified");
    Relative(radar+8,clock+1);
    Check(!FindHud(image,8192).clock,"mismatched clock callee rejects discovery without patching");
    Relative(radar+8,clock);
    step[31]^=4;
    Check(!FindHud(image,8192).clock,"inconsistent live compass globals rejected");
    step[31]^=4;
    uint32_t invalid=1; memcpy(step+2,&invalid,4); memcpy(step+31,&invalid,4);
    Check(!FindHud(image,8192).clock,"out-of-module globals rejected");
    memcpy(step+2,&global,4); memcpy(step+31,&global,4);
    Pattern(image+0x1400,CLOCK_DRAW_PATTERN);
    Check(!FindHud(image,8192).clock,"ambiguous clock signature rejected");
    memset(image+0x1400,0xcc,64);
    visible[0]=0xcc;
    found=FindHud(image,8192);
    Check(found.clock==clock && !found.radarVisible,"missing radar query leaves clock available but disables compass");
    Pattern(visible,RADAR_VISIBLE_PATTERN);
    memcpy(clock+0xca,&invalid,4);
    found=FindHud(image,8192);
    Check(found.clock==clock && !found.weather,"missing/invalid weather source is optional, never disables clock");
    for (int outer=0;outer<2;outer++) for (int inner=0;inner<2;inner++) {
        bool blocking=false,target=true;
        { HudDrawScope compassScope(blocking,target);
          blocking=outer!=0;
          { HudDrawScope clockScope(blocking,target);
            Check(!blocking && !target,"clock escapes enclosing compass suppression before replay");
            blocking=inner!=0;
          }
          Check(blocking==(outer!=0) && !target,"clock exit restores only enclosing compass suppression");
        }
        Check(!blocking && target,"HUD scope exit restores previous GPU/target flags");
    }
    // Native Clock::Draw is thiscall(this, int32 x, int32 y), callee cleans eight stack bytes.
    memset(image,0xcc,8192);
    uint8_t native[]={0x8a,0x41,0x2e,0x83,0xec,0x40,0x83,0xc4,0x40,
        0x8b,0x44,0x24,0x04,0x03,0x44,0x24,0x08,0xc2,0x08,0x00};
    memcpy(image,native,sizeof(native));
    Detour detour={"8A 41 2E 83 EC 40",6,-1,reinterpret_cast<void*>(&Replacement),nullptr,nullptr,{}};
    Check(Take(detour,image,8192),"clock detour steals exactly two whole non-relative instructions");
    using ClockCall=int(__fastcall*)(void*,void*,int32_t,int32_t);
    uint8_t object[0x40]={};
    Check(reinterpret_cast<ClockCall>(image)(object,nullptr,-20,47)==99 && seenThis==object && seenX==-20 && seenY==47,
        "clock detour preserves this and both signed stack coordinates");
    Check(reinterpret_cast<ClockCall>(detour.trampoline)(object,nullptr,-20,47)==27,"clock trampoline preserves original execution and ret 8 ABI");
    Give(detour);
    Check(!memcmp(image,native,sizeof(native)) && reinterpret_cast<ClockCall>(image)(object,nullptr,-20,47)==27,
        "unload restores native clock bytes and execution");
    Check(sizeof(HudShared)==76,"HUD ABI 2 is 76 bytes, separate from Party ABI 3");
    VirtualFree(image,0,MEM_RELEASE);
    return failures?1:0;
}
