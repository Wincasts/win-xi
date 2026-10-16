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
static int textX=0,textY=0;
static void* iconSprite=nullptr; static int32_t iconX=0,iconY=0; static uint32_t iconColor=0;
static void __fastcall IconReplacement(void* sprite,void*,int32_t x,int32_t y,uint32_t color,uint32_t,uint32_t) {
    iconSprite=sprite; iconX=x; iconY=y; iconColor=color;
}
static void __cdecl TextReplacement(int32_t x,int32_t y,const char*,uint32_t) { textX=x; textY=y; }
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
    Check(!found.text,"no text call: the clock is still found, replaced whole");
    auto* textAt=clock+0x40; auto* textRoutine=image+0xe00;
    Pattern(textAt,CLOCK_TEXT_PATTERN); Relative(textAt+CLOCK_TEXT_CALL,textRoutine);
    found=FindHud(image,8192);
    Check(found.clock==clock && found.text==textAt+CLOCK_TEXT_CALL && found.textTarget==textRoutine,
        "the clock's text call found inside Clock::Draw, and what it calls");
    Pattern(image+0x1800,CLOCK_TEXT_PATTERN); Relative(image+0x1800+CLOCK_TEXT_CALL,textRoutine);
    Check(!FindHud(image,8192).text && FindHud(image,8192).clock,"a second text call anywhere: not taken, the clock kept");
    memset(image+0x1800,0xcc,32);
    memset(textAt,0xcc,32);
    Pattern(clock+0x120,CLOCK_TEXT_PATTERN); Relative(clock+0x120+CLOCK_TEXT_CALL,textRoutine);
    Check(!FindHud(image,8192).text,"a text call past Clock::Draw's start is not its own");
    memset(clock+0x120,0xcc,32);
    Pattern(textAt,CLOCK_TEXT_PATTERN); Relative(textAt+CLOCK_TEXT_CALL,textRoutine);
    // the three icon calls, each to the one sprite routine
    auto* spriteRoutine=image+0xe40;
    uint8_t* iconAt[3]={clock+0x60,clock+0x80,clock+0xe0};
    const char* iconPatterns[3]={CLOCK_DAY_ICON_PATTERN,CLOCK_WEATHER_ICON_PATTERN,CLOCK_SECOND_ICON_PATTERN};
    const unsigned iconCalls[3]={CLOCK_DAY_ICON_CALL,CLOCK_WEATHER_ICON_CALL,CLOCK_SECOND_ICON_CALL};
    for (unsigned i=0;i<2;i++) { Pattern(iconAt[i],iconPatterns[i]); Relative(iconAt[i]+iconCalls[i],spriteRoutine); }
    found=FindHud(image,8192);
    Check(found.clock==clock && !found.icons[0] && !found.iconTarget,"two of the three icon calls: none taken, the clock kept");
    Pattern(iconAt[2],iconPatterns[2]); Relative(iconAt[2]+iconCalls[2],spriteRoutine+1);
    Check(!FindHud(image,8192).iconTarget,"an icon call to another routine: none taken");
    Relative(iconAt[2]+iconCalls[2],spriteRoutine);
    found=FindHud(image,8192);
    Check(found.iconTarget==spriteRoutine && found.icons[0]==iconAt[0]+iconCalls[0] && found.icons[1]==iconAt[1]+iconCalls[1]
        && found.icons[2]==iconAt[2]+iconCalls[2],"the day, weather and second weather icon calls found, and the sprite routine");
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
    Check(sizeof(HudShared)==152,"HUD ABI 4 is 152 bytes, separate from Party ABI 3");
    // The text call: aimed at ours as a CALL, which takes the four arguments, and given back
    memset(image,0xcc,8192);
    uint8_t caller[]={0x68,0x80,0x80,0x80,0x80,0x6a,0x00,0x6a,0x07,0x6a,0xf6,0xe8,0,0,0,0,0x83,0xc4,0x10,0xc3};
    memcpy(image,caller,sizeof(caller));
    auto* routine=image+0x100; routine[0]=0xc3;
    Relative(image+11,routine);
    uint8_t before[20]; memcpy(before,image,20);
    ClockTextCall text;
    Check(!TakeClockText(text,image+11,routine+1,reinterpret_cast<void*>(&TextReplacement)) && !memcmp(image,before,20),
        "a call to something else is not written");
    Check(TakeClockText(text,image+11,routine,reinterpret_cast<void*>(&TextReplacement)) && image[11]==0xe8,
        "the text call taken, still a CALL");
    reinterpret_cast<void(*)()>(image)();
    Check(textX==-10 && textY==7 && text.original==reinterpret_cast<ClockText>(routine),"ours is given the game's x and y, cdecl");
    GiveClockText(text);
    Check(!memcmp(image,before,20) && !text.call,"given back as it was");
    // An icon call: thiscall with five stack words the callee clears (ret 0x14). Three callers, one
    // routine; ours is given the sprite and its arguments, and the stack is as it was after: each
    // caller returns ebp-esp after the call, 0 when the five words were cleared.
    memset(image,0xcc,8192);
    auto* sprite=image+0x400; sprite[0]=0xc2; sprite[1]=0x14; sprite[2]=0x00;
    uint8_t* callers[3];
    for (unsigned i=0;i<3;i++) {
        uint8_t* at=image+i*0x40;
        const uint8_t code[]={0x55,0x89,0xe5,0x6a,0x00,0x6a,0x00,0x68,0x80,0x80,0x80,0x80,0x6a,static_cast<uint8_t>(10+i),
            0x6a,static_cast<uint8_t>(0xf0-i),0xb9,0x44,0x33,0x22,0x11,0xe8,0,0,0,0,0x89,0xe8,0x29,0xe0,0x5d,0xc3};
        memcpy(at,code,sizeof(code)); callers[i]=at+21; Relative(callers[i],sprite);
    }
    uint8_t iconBefore[0x100]; memcpy(iconBefore,image,0x100);
    ClockIconCalls icons;
    uint8_t* const wrong[3]={callers[0],callers[1],callers[2]+1};
    void* const replacements[3]={reinterpret_cast<void*>(&IconReplacement),reinterpret_cast<void*>(&IconReplacement),reinterpret_cast<void*>(&IconReplacement)};
    Check(!TakeClockIcons(icons,wrong,sprite,replacements) && !memcmp(image,iconBefore,0x100),"one call not where said: none written");
    Check(TakeClockIcons(icons,callers,sprite,replacements),"the three icon calls taken, still CALLs");
    bool all=true;
    for (unsigned i=0;i<3;i++) {
        const int stackLeft=reinterpret_cast<int(*)()>(image+i*0x40)();
        all=all && stackLeft==0 && iconSprite==reinterpret_cast<void*>(0x11223344) && iconX==-16-int32_t(i)
            && iconY==int32_t(10+i) && iconColor==0x80808080u;
    }
    Check(all,"ours is given the sprite, x, y and colour, and clears the five words as the game's does");
    GiveClockIcons(icons);
    Check(!memcmp(image,iconBefore,0x100) && !icons.original,"the icon calls given back as they were");
    VirtualFree(image,0,MEM_RELEASE);
    return failures?1:0;
}
