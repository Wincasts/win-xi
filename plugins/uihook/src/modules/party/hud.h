// Clock and compass boundaries, verified against a private unpacked client dump.
// Compass::Draw calls Clock::Draw in both radar-enabled and radar-disabled paths.
#pragma once
#include <stdint.h>

#define HUD_VERSION 3
#define HUD_CLOCK 1u
#define HUD_COMPASS 2u
struct HudShared {
    char Magic[16];
    uint32_t Version, Size, SupportedMask, Frame, Submit;
    uint32_t DrawnFrame[2], NativeFrame[2];
    uint32_t Weather; // native weather ID, 0xffff if unavailable; sampled at NativeFrame[0]
    // Where the game drew its clock (its screen-space draws), in ImGui display pixels: left, top,
    // right, bottom; current at ClockRectFrame. Drawn or replaced, the game's draws still say where.
    float ClockRect[4];
    uint32_t ClockRectFrame;
    // The map grid the game prints after the time, "(H-9)", from the clock's object; current at
    // ClockRectFrame. Eight characters at most, then zeros.
    char Grid[12];
};
static_assert(sizeof(HudShared)==88, "HUD ABI 3");
// Submit(index, capture): index 0 clock, 1 compass; capture 1=current ImGui window,
// 0=renew empty replacement, -1=release that slot. index -1 releases ONLY these two slots.

#define COMPASS_STEP_PATTERN "8B 0D ?? ?? ?? ?? 85 C9 74 1E E8 ?? ?? ?? ?? B9 ?? ?? ?? ?? E8 ?? ?? ?? ?? 3C 01 74 0B 8B 0D ?? ?? ?? ?? E9 ?? ?? ?? ?? C3"
#define COMPASS_DRAW_PATTERN "81 EC 9C 00 00 00 53 55 56 8B D9 57 89 5C 24 40 E8 ?? ?? ?? ?? 8B CB E8 ?? ?? ?? ?? 8B CB E8 ?? ?? ?? ?? 8A 43 0D 84 C0"
#define CLOCK_DRAW_PATTERN "8A 41 2E 83 EC 40 84 C0 53 56 57 0F 84 ?? ?? ?? ?? E8 ?? ?? ?? ?? 50 E8 ?? ?? ?? ?? 50 E8"
#define CLOCK_WEATHER_PATTERN "66 A1 ?? ?? ?? ?? 66 3D 04 00 72 7E 66 3D 14 00 73 78"
#define RADAR_VISIBLE_PATTERN "A0 ?? ?? ?? ?? 84 C0 75 03 32 C0 C3 8B 0D ?? ?? ?? ?? 85 C9 75 03 32 C0 C3 33 C0 66 8B 81 7C 0D 04 00"
#define CLOCK_SMALL_PATTERN "56 57 8B CB E8 ?? ?? ?? ?? 5F 5E 5D 5B 81 C4 9C 00 00 00 C3"
// Clock::Draw's one text call, Text(x-50, y+26, "%d:%02d  %s", colour), cdecl with four arguments.
// Redirected alone, the game's text can be hidden and measured while its day and weather icons,
// drawn after it, are left to the game.
#define CLOCK_TEXT_PATTERN "68 80 80 80 80 8D 57 1A 51 8D 43 CE 52 50 E8 ?? ?? ?? ??"
#define CLOCK_TEXT_CALL 14
#define CLOCK_GRID_AT 0x11
#define CLOCK_RADAR_PATTERN "8B 44 24 28 8B CB 50 57 E8 ?? ?? ?? ?? E8 ?? ?? ?? ?? 85 C0 89 44 24 24"

static uint8_t* HudCallee(uint8_t* begin,size_t size,uint8_t* call,uint8_t opcode) {
    if (!call || call<begin || size<5 || static_cast<size_t>(call-begin)>size-5 || *call!=opcode) return nullptr;
    int32_t rel=0; memcpy(&rel,call+1,4);
    int64_t offset=static_cast<int64_t>(call-begin)+5+rel;
    return offset>=0 && static_cast<uint64_t>(offset)<size ? begin+offset : nullptr;
}
struct HudDiscovery { uint8_t* compass=nullptr; uint8_t* clock=nullptr; void** global=nullptr; uint8_t* radarVisible=nullptr; uint16_t* weather=nullptr; uint8_t* text=nullptr; uint8_t* textTarget=nullptr; };
static HudDiscovery FindHud(uint8_t* begin,size_t size) {
    HudDiscovery out;
    auto* step=UniquePattern(begin,size,COMPASS_STEP_PATTERN);
    auto* compass=UniquePattern(begin,size,COMPASS_DRAW_PATTERN);
    auto* clock=UniquePattern(begin,size,CLOCK_DRAW_PATTERN);
    if (!step || !compass || !clock || HudCallee(begin,size,step+35,0xe9)!=compass) return out;
    uint32_t first=0,second=0; memcpy(&first,step+2,4); memcpy(&second,step+31,4);
    uintptr_t low=reinterpret_cast<uintptr_t>(begin);
    if (first!=second || first%4 || first<low || size<4 || first-low>size-4) return out;
    auto* compact=UniquePattern(begin,size,CLOCK_SMALL_PATTERN);
    auto* radar=UniquePattern(begin,size,CLOCK_RADAR_PATTERN);
    if (!compact || !radar || compact<compass || radar<compass || compact-compass>0x900 || radar-compass>0x900
        || HudCallee(begin,size,compact+4,0xe8)!=clock || HudCallee(begin,size,radar+8,0xe8)!=clock) return out;
    out.compass=compass; out.clock=clock; out.global=reinterpret_cast<void**>(static_cast<uintptr_t>(first));
    // This pure native query handles the user's radar switch and zones where radar is unavailable.
    // Missing query recognition disables compass replacement, not the independently verified clock.
    auto* visible=UniquePattern(begin,size,RADAR_VISIBLE_PATTERN);
    if (visible && HudCallee(begin,size,compass+0x44,0xe8)==visible) out.radarVisible=visible;
    // Optional: without it the whole clock is replaced, icons and all, as before.
    auto* text=UniquePattern(begin,size,CLOCK_TEXT_PATTERN);
    if (text && text>clock && text-clock<0x100) {
        auto* target=HudCallee(begin,size,text+CLOCK_TEXT_CALL,0xe8);
        if (target) { out.text=text+CLOCK_TEXT_CALL; out.textTarget=target; }
    }
    auto* weather=UniquePattern(begin,size,CLOCK_WEATHER_PATTERN);
    if (weather && weather>=clock && weather-clock<0x160) {
        uint32_t address=0; memcpy(&address,weather+2,4);
        if (address>=low && size>=2 && address-low<=size-2)
            out.weather=reinterpret_cast<uint16_t*>(static_cast<uintptr_t>(address));
    }
    return out;
}
using ClockText = void(__cdecl*)(int32_t,int32_t,const char*,uint32_t);
struct ClockTextCall { uint8_t* call=nullptr; ClockText original=nullptr; uint8_t saved[5]={}; };
// E8 stays E8, so the game's return address is kept; checked to call the text routine before writing.
static bool TakeClockText(ClockTextCall& text,uint8_t* call,uint8_t* target,void* replacement) {
    if (!call || !target || !VerifyCall(call,target)) return false;
    text.call=call; text.original=reinterpret_cast<ClockText>(target);
    memcpy(text.saved,call,5);
    uint8_t jump[5]={0xe8,0,0,0,0};
    int32_t distance=Distance(call+5,replacement); memcpy(jump+1,&distance,4);
    WriteCode(call,jump,5);
    return true;
}
static void GiveClockText(ClockTextCall& text) {
    if (text.call) WriteCode(text.call,text.saved,5);
    text=ClockTextCall();
}
// Restore the enclosing filter even through nested native boundaries / C++ unwinding.
struct HudDrawScope {
    bool &blocking, &target;
    bool wasBlocking, wasTarget;
    HudDrawScope(bool& b,bool& t) : blocking(b),target(t),wasBlocking(b),wasTarget(t) { blocking=false; target=false; }
    ~HudDrawScope() { blocking=wasBlocking; target=wasTarget; }
};
