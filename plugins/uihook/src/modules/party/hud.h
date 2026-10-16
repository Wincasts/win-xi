// Clock and compass boundaries, verified against a private unpacked client dump.
// Compass::Draw calls Clock::Draw in both radar-enabled and radar-disabled paths.
#pragma once
#include <stdint.h>

#define HUD_VERSION 6
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
    // The game's clock icons, as ClockRect: 0 the day's, 1 the weather's, 2 the second weather icon
    // of a double weather. Each current at its IconFrame; a frame it was not drawn in, it is not.
    float IconRect[3][4];
    uint32_t IconFrame[3];
    // Written by the addon: HUD_ICON_DAY and HUD_ICON_WEATHER for icons it draws its own of. Only
    // while its clock replacement is fresh and drawn are the game's left undrawn (both weather icons
    // for HUD_ICON_WEATHER); they are measured either way.
    uint32_t HideIcons;
    // Written by the addon, honoured as HideIcons is: WeatherShift moves the game's weather icons
    // down (up, below 0) by that many of the game's units; PreviewWeather draws the game's own icons
    // of the weathers named (bit 0 fire, 1 ice, 2 wind, 3 earth, 4 thunder, 5 water, 6 light, 7 dark,
    // the order of its weather sprites) side by side from the weather icon's place, each in its own
    // place whichever are named, to see them all.
    int32_t WeatherShift;
    uint32_t PreviewWeather;
    // Written by the addon, honoured as HideIcons is: how large the game's weather icons are drawn,
    // its preview's among them, about each icon's middle (0 or 1 as the game draws them)
    float WeatherScale;
};
static_assert(sizeof(HudShared)==164, "HUD ABI 6");
#define HUD_SCALE_LEAST 0.25f
#define HUD_SCALE_MOST 4.0f
#define HUD_SHIFT_MOST 200
#define HUD_ICON_DAY 1u
#define HUD_ICON_WEATHER 2u
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
// Clock::Draw's three icon calls, Sprite::Draw(this=sprite, x, y, colour, 0, 0): thiscall, five
// stack words it clears itself (ret 0x14). The day's at (x-68, y+26), the weather's at (x-68, y-42),
// and the second weather icon a sprite's width on. Each pattern ends at its CALL.
#define CLOCK_DAY_ICON_PATTERN "6A 00 6A 00 83 C0 1A 68 80 80 80 80 83 EA 44 50 52 E8 ?? ?? ?? ??"
#define CLOCK_DAY_ICON_CALL 17
#define CLOCK_WEATHER_ICON_PATTERN "68 80 80 80 80 8D 4B BC 57 51 8B CE E8 ?? ?? ?? ??"
#define CLOCK_WEATHER_ICON_CALL 12
#define CLOCK_SECOND_ICON_PATTERN "68 80 80 80 80 8D 54 18 BC 57 52 8B CE E8 ?? ?? ?? ??"
#define CLOCK_SECOND_ICON_CALL 13
// The sprite banks' getter, Bank(n): cdecl, banks[n] for n below 18, else 0; Clock::Draw asks it for
// its day icons (4) and its weather icons (14), a bank's first word its sprites. Each pattern ends at
// the push of the bank's number, its CALL two on.
#define CLOCK_DAY_BANK_PATTERN "6A 04 E8 ?? ?? ?? ?? 8B F0 83 C4 28"
#define CLOCK_WEATHER_BANK_PATTERN "6A 0E E8 ?? ?? ?? ?? 8B C8 83 C4 04 85 C9"
#define CLOCK_BANK_CALL 2
#define CLOCK_WEATHER_BANK 14
#define CLOCK_WEATHER_ABOVE_DAY 68 // the weather icon's y above the day icon's, in the game's units
#define CLOCK_RADAR_PATTERN "8B 44 24 28 8B CB 50 57 E8 ?? ?? ?? ?? E8 ?? ?? ?? ?? 85 C0 89 44 24 24"

static uint8_t* HudCallee(uint8_t* begin,size_t size,uint8_t* call,uint8_t opcode) {
    if (!call || call<begin || size<5 || static_cast<size_t>(call-begin)>size-5 || *call!=opcode) return nullptr;
    int32_t rel=0; memcpy(&rel,call+1,4);
    int64_t offset=static_cast<int64_t>(call-begin)+5+rel;
    return offset>=0 && static_cast<uint64_t>(offset)<size ? begin+offset : nullptr;
}
struct HudDiscovery { uint8_t* compass=nullptr; uint8_t* clock=nullptr; void** global=nullptr; uint8_t* radarVisible=nullptr; uint16_t* weather=nullptr; uint8_t* text=nullptr; uint8_t* textTarget=nullptr;
    uint8_t* icons[3]={}; uint8_t* iconTarget=nullptr; uint8_t* bank=nullptr; };
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
    // Optional, and all three or none: each inside Clock::Draw, each calling the one sprite routine.
    const char* iconPatterns[3]={CLOCK_DAY_ICON_PATTERN,CLOCK_WEATHER_ICON_PATTERN,CLOCK_SECOND_ICON_PATTERN};
    const unsigned iconCalls[3]={CLOCK_DAY_ICON_CALL,CLOCK_WEATHER_ICON_CALL,CLOCK_SECOND_ICON_CALL};
    uint8_t* icons[3]={}; uint8_t* sprite=nullptr; bool iconsOk=true;
    for (unsigned i=0;i<3 && iconsOk;i++) {
        auto* at=UniquePattern(begin,size,iconPatterns[i]);
        if (!at || at<=clock || at-clock>=0x160) { iconsOk=false; break; }
        auto* target=HudCallee(begin,size,at+iconCalls[i],0xe8);
        if (!target || (sprite && target!=sprite)) { iconsOk=false; break; }
        sprite=target; icons[i]=at+iconCalls[i];
    }
    if (iconsOk) { for (unsigned i=0;i<3;i++) out.icons[i]=icons[i]; out.iconTarget=sprite; }
    // Optional, for the preview alone: both of Clock::Draw's bank calls, to the one getter
    auto* dayBank=UniquePattern(begin,size,CLOCK_DAY_BANK_PATTERN);
    auto* weatherBank=UniquePattern(begin,size,CLOCK_WEATHER_BANK_PATTERN);
    if (dayBank && weatherBank && dayBank>clock && weatherBank>clock && dayBank-clock<0x160 && weatherBank-clock<0x160) {
        auto* getter=HudCallee(begin,size,dayBank+CLOCK_BANK_CALL,0xe8);
        if (getter && getter==HudCallee(begin,size,weatherBank+CLOCK_BANK_CALL,0xe8)) out.bank=getter;
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
// The three icon calls, each aimed at its own replacement, which knows which icon it is drawing.
using ClockIcon = void(__fastcall*)(void*,void*,int32_t,int32_t,uint32_t,uint32_t,uint32_t);
struct ClockIconCalls { uint8_t* calls[3]={}; ClockIcon original=nullptr; uint8_t saved[3][5]={}; };
static bool TakeClockIcons(ClockIconCalls& icons,uint8_t* const calls[3],uint8_t* target,void* const replacements[3]) {
    if (!target) return false;
    for (unsigned i=0;i<3;i++) if (!calls[i] || !VerifyCall(calls[i],target)) return false;
    icons.original=reinterpret_cast<ClockIcon>(target);
    for (unsigned i=0;i<3;i++) {
        icons.calls[i]=calls[i]; memcpy(icons.saved[i],calls[i],5);
        uint8_t jump[5]={0xe8,0,0,0,0};
        int32_t distance=Distance(calls[i]+5,replacements[i]); memcpy(jump+1,&distance,4);
        WriteCode(calls[i],jump,5);
    }
    return true;
}
static void GiveClockIcons(ClockIconCalls& icons) {
    for (unsigned i=0;i<3;i++) if (icons.calls[i]) WriteCode(icons.calls[i],icons.saved[i],5);
    icons=ClockIconCalls();
}
static void GiveClockText(ClockTextCall& text) {
    if (text.call) WriteCode(text.call,text.saved,5);
    text=ClockTextCall();
}
// Screen-space vertices (x, y the first two floats of each) grown or shrunk about (cx, cy), in place;
// the colours, texture places and the rest of each vertex untouched
static void ScaleScreenVertices(uint8_t* bytes,unsigned count,unsigned stride,float cx,float cy,float scale) {
    for (unsigned i=0;i<count;i++) {
        float v[2]; memcpy(v,bytes+size_t(i)*stride,sizeof(v));
        v[0]=cx+(v[0]-cx)*scale; v[1]=cy+(v[1]-cy)*scale;
        memcpy(bytes+size_t(i)*stride,v,sizeof(v));
    }
}
// Restore the enclosing filter even through nested native boundaries / C++ unwinding.
struct HudDrawScope {
    bool &blocking, &target;
    bool wasBlocking, wasTarget;
    HudDrawScope(bool& b,bool& t) : blocking(b),target(t),wasBlocking(b),wasTarget(t) { blocking=false; target=false; }
    ~HudDrawScope() { blocking=wasBlocking; target=wasTarget; }
};
