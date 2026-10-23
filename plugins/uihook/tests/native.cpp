#include <stdio.h>
#include <cmath>
#include <d3d8.h>
#include "../src/modules/party/detour.h"
#include "../src/modules/party/target.h"
#include "../src/modules/chat/controls.h"
#include "../src/modules/mirror/census.h"
#include "../src/modules/mirror/mirror.h"
#include "../src/modules/native/native.h"
static int failures=0;
static void Check(bool ok,const char* text) { printf("%s %s\n",ok?"ok":"FAIL",text); if(!ok) ++failures; }
int main() {
    // the move in the window's units
    int dimensions[2]={1280,960}; int16_t original[2]={100,200},out[2]={};
    Check(NativeOffset(original,false,dimensions,30,-40,out) && out[0]==130 && out[1]==160,"a raw window moved by pixels");
    Check(NativeOffset(original,true,dimensions,30,-40,out) && out[0]==115 && out[1]==180,"a scaled one by pixels in 640x480 units");
    Check(!NativeOffset(original,false,dimensions,-101,0,out),"not past the units' range");
    int bad[2]={0,0}; Check(!NativeOffset(original,true,bad,1,1,out),"no menu manager dimensions, no scaled move");
    // the tint, the game's colours multiplied
    Check(NativeTint(0x80808080,0xffffffff)==0x80808080,"white leaves the game's colour");
    Check(NativeTint(0x80808080,0xff808080)==0x80404040,"half the colour, the alpha kept");
    Check(NativeTint(0x80808080,0x80ffffff)==0x40808080,"half the alpha");
    struct V { float x,y,z,w; uint32_t colour; float u,v; } vertices[2]={{0,0,0,1,0x80808080,0,0},{1,1,0,1,0x40404040,1,1}};
    Check(NativeTintVertices(vertices,2,sizeof(V),16,0xff00ff00) && vertices[0].colour==0x80008000 && vertices[1].colour==0x40004000,"each vertex's diffuse tinted");
    Check(!NativeTintVertices(vertices,2,16,16,0xffffffff),"a stride without a colour refused");
    char name[16]; Check(NativeName("iuse",name) && !memcmp(name,"menu    iuse    ",16),"a name padded as the game keeps it");
    Check(!NativeName("toolongname",name) && !NativeName("",name),"too long or empty refused");

    // a window: its header's name at +46, its target at +8C, its dirty mark at +94, scaled at +99
    alignas(4) uint8_t header[0x60]={}; memcpy(header+0x46,"menu    inventor",16);
    alignas(4) uint8_t window[0x9a]={}; void* h=header; memcpy(window+4,&h,4);
    const int16_t target[4]={100,200,120,80}; memcpy(window+0x8c,target,8);
    NativeLook look;
    Check(look.Move("inventor",50,-20),"asked to move");
    look.Before(window,header,window,dimensions,10);
    int16_t now[2]; int32_t dirty=0; memcpy(now,window+0x8c,4); memcpy(&dirty,window+0x94,4);
    Check(now[0]==150 && now[1]==180 && dirty==-1 && look.applied==1,"moved before the game lays it out, marked for it");
    memset(window+0x94,0,4);
    look.Before(window,header,window,dimensions,11);
    memcpy(&dirty,window+0x94,4); Check(dirty==0 && look.applied==1,"already there: not written again");
    // the game lays it out afresh (opened again): the new place is the one moved from
    const int16_t fresh[2]={300,400}; memcpy(window+0x8c,fresh,4);
    look.Before(window,header,window,dimensions,12);
    memcpy(now,window+0x8c,4); Check(now[0]==350 && now[1]==380,"laid out afresh by the game: moved from there");
    // another window of another name: left alone
    alignas(4) uint8_t other[0x60]={}; memcpy(other+0x46,"menu    equip   ",16);
    alignas(4) uint8_t second[0x9a]={}; void* o=other; memcpy(second+4,&o,4); memcpy(second+0x8c,target,8);
    look.Before(second,other,second,dimensions,12);
    memcpy(now,second+0x8c,4); Check(now[0]==100 && now[1]==200,"a window not named: not moved");
    // cleared: put back the next time it is drawn, and the entry done with
    Check(look.Clear("inventor")==1,"cleared");
    look.Before(window,header,window,dimensions,13);
    memcpy(now,window+0x8c,4); Check(now[0]==300 && now[1]==400 && look.restored==1,"put back where the game had it");
    Check(!look.Any(),"nothing left once put back");

    // the tint: only the frame of the window named, not its contents, elements or text
    Check(look.Tint("inventor",0xff8080ff),"asked to tint");
    uint32_t colour=0;
    NativeLook::Saved saved=look.Enter("menu    inventor");
    Check(look.Tinting(colour) && colour==0xff8080ff,"its frame tinted");
    MirrorPhase was=look.Phase(MIRROR_CONTENT); Check(!look.Tinting(colour),"not its contents");
    look.Phase(MIRROR_ELEMENT); Check(!look.Tinting(colour),"not its elements"); look.Phase(was);
    look.text++; Check(!look.Tinting(colour),"not text in its frame"); look.text--;
    NativeLook::Saved inner=look.Enter("menu    equip   "); Check(!look.Tinting(colour),"a window inside it not named: not tinted");
    look.Leave(inner); Check(look.Tinting(colour),"back in it after");
    look.Leave(saved); Check(!look.Tinting(colour),"outside any window: nothing");
    printf("%d failures\n",failures);
    return failures ? 1 : 0;
}
