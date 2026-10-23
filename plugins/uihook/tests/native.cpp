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
static bool Near(float a,float b) { return fabsf(a-b)<0.01f; }
int main() {
    // where a window's draws go, on a 1000x800 display
    const float topLeft[4]={100,50,300,250}; float place[4]={};
    Check(NativePlace(topLeft,40,30,1,1000,800,place) && Near(place[2],40) && Near(place[3],30),"moved as asked");
    Check(NativePlace(topLeft,0,0,2,1000,800,place) && Near(place[0],100) && Near(place[1],50),"grown from its top left, the corner it is nearest");
    const float bottomRight[4]={700,600,900,780};
    Check(NativePlace(bottomRight,0,0,2,1000,800,place) && Near(place[0],900) && Near(place[1],780),"one near the bottom right grown from there");
    Check(NativePlace(topLeft,-500,-500,1,1000,800,place) && Near(place[2],-100) && Near(place[3],-50),"kept on the display");
    Check(NativePlace(topLeft,2000,0,1,1000,800,place) && Near(place[2],700),"not past the right edge");
    const float none[4]={0,0,0,0}; Check(!NativePlace(none,10,10,1,1000,800,place),"no bounds, no place");

    struct V { float x,y,z,w; uint32_t colour; float u,v; } vertices[2]={{100,50,0,1,0x80808080,0,0},{300,250,0,1,0x80808080,1,1}};
    NativePlace(topLeft,10,20,2,1000,800,place);
    NativeMoveVertices(vertices,2,sizeof(V),place,2);
    Check(Near(vertices[0].x,110) && Near(vertices[0].y,70) && Near(vertices[1].x,510) && Near(vertices[1].y,470),"vertices grown about the corner and moved");
    Check(vertices[0].colour==0x80808080 && Near(vertices[1].u,1),"their colours and texture places kept");

    char name[16]; Check(NativeName("iuse",name) && !memcmp(name,"menu    iuse    ",16),"a name padded as the game keeps it");
    Check(!NativeName("toolongname",name) && !NativeName("",name),"too long or empty refused");

    // a window named: its draws' bounds gathered each frame, placed by the frame before's
    NativeLook look;
    Check(look.Move("inventor",50,-20),"asked to move");
    Check(!look.Scale("inventor",5) && look.Scale("inventor",1.5f),"a scale from 0.5 to 3");
    NativeLook::Saved saved=look.Enter("menu    inventor",1);
    Check(!look.Placing(1000,800,place),"the first frame: no bounds yet, drawn as the game does");
    V drawn[2]={{100,50,0,1,0,0,0},{300,250,0,1,0,0,0}};
    look.Gather(drawn,2,sizeof(V));
    look.Leave(saved);
    saved=look.Enter("menu    inventor",2);
    Check(look.Placing(1000,800,place) && Near(place[0],100) && Near(place[2],50) && Near(place[3],-20),"the next: placed by the frame before's bounds");
    NativeLook::Saved inner=look.Enter("menu    equip   ",2);
    Check(!look.Placing(1000,800,place),"a window inside it not named: drawn as the game does");
    look.Unmoved(); look.Leave(inner);
    look.Unmoved(); Check(look.entries[0].unmoved==1,"a vertex buffer draw in it counted, the other window's not");
    look.Leave(saved);
    Check(!look.Placing(1000,800,place),"outside any window: nothing placed");

    // its frame's draws: what it is placed by; a draw wholly outside it (the inventory's count) kept back
    NativeLook framed;
    framed.Move("inventor",10,10); framed.Scale("inventor",2);
    saved=framed.Enter("menu    inventor",1);
    V frameDraw[2]={{100,50,0,1,0,0,0},{300,250,0,1,0,0,0}};
    framed.Gather(frameDraw,2,sizeof(V));
    framed.Phase(MIRROR_CONTENT);
    V countDraw[2]={{90,10,0,1,0,0,0},{130,30,0,1,0,0,0}};
    framed.Gather(countDraw,2,sizeof(V));
    framed.Leave(saved);
    saved=framed.Enter("menu    inventor",2);
    Check(framed.Placing(1000,800,place) && Near(place[0],100) && Near(place[1],50),"grown from its frame's corner, not the count's");
    framed.Phase(MIRROR_CONTENT);
    Check(!framed.Within(countDraw,2,sizeof(V)),"the count, wholly outside its frame, kept back");
    V rowDraw[2]={{120,60,0,1,0,0,0},{200,72,0,1,0,0,0}};
    V edgeDraw[2]={{90,60,0,1,0,0,0},{104,72,0,1,0,0,0}};
    Check(framed.Within(rowDraw,2,sizeof(V)) && framed.Within(edgeDraw,2,sizeof(V)),"a row, and the hand over its edge, moved");
    framed.Leave(saved);

    // the tint: only the frame of the window named, not its contents, elements or text
    Check(look.Tint("inventor",0xffff4040),"asked to tint");
    uint32_t colour=0;
    saved=look.Enter("menu    inventor",3);
    Check(look.Tinting(colour) && colour==0xffff4040,"its frame tinted");
    MirrorPhase was=look.Phase(MIRROR_CONTENT); Check(!look.Tinting(colour) && look.Placing(1000,800,place),"its contents not tinted, but moved");
    look.Phase(MIRROR_ELEMENT); Check(!look.Tinting(colour),"not its elements"); look.Phase(was);
    look.text++; Check(!look.Tinting(colour) && look.Placing(1000,800,place),"text in its frame moved, not tinted"); look.text--;
    look.Leave(saved);
    Check(look.Clear("inventor")==1 && !look.Any(),"cleared");
    // the group over the chat log
    NativeLook group;
    group.Group(0,-300);
    Check(group.Any(),"a group set: windows are looked at");
    const int16_t log[4]={16,1290,658,134},command[4]={16,1200,112,88},yesno[4]={130,1200,252,88},right[4]={3312,47,112,202},high[4]={16,100,112,88};
    group.Note("menu    menuwind",command,1);
    Check(!group.Find("menu    menuwind",false),"the log not yet seen: none of the group");
    group.Note("menu    logwindo",log,1);
    Check(group.logFrame==1 && group.logTop==1290 && !group.Find("menu    logwindo",false),"the log's place noted, it none of the group");
    group.Note("menu    menuwind",command,2); group.Note("menu    comyn   ",yesno,2); group.Note("menu    equip   ",high,2);
    NativeEntry* cm=group.Find("menu    menuwind",false);
    Check(cm && cm->group && cm->member && cm->dy==-300 && group.Find("menu    comyn   ",false) && !group.Find("menu    equip   ",false),
        "the windows on the log's top of the group, one placed elsewhere not");
    group.Note("menu    menuwind",right,3);
    Check(!cm->member,"the same name placed elsewhere: not of the group this frame");
    saved=group.Enter("menu    menuwind",3);
    V cd[2]={{3312,47,0,1,0,0,0},{3424,249,0,1,0,0,0}}; group.Gather(cd,2,sizeof(V)); group.Leave(saved);
    saved=group.Enter("menu    menuwind",4);
    Check(!group.Placing(3440,1440,place),"and so not moved");
    group.Leave(saved);
    group.Note("menu    menuwind",command,5);
    saved=group.Enter("menu    menuwind",5);
    Check(group.Placing(3440,1440,place) && Near(place[3],-47),"of it again: moved, kept on the screen");
    group.Leave(saved);
    group.Group(10,-100);
    Check(cm->dx==10 && cm->dy==-100,"a new offset for every one of it");
    Check(group.GroupOff()==2 && !group.Any(),"the group off: its entries gone");
    // the sides brought in
    NativeLook sides;
    sides.Inset(100);
    Check(sides.Any(),"an inset set: windows are looked at");
    auto frameOf=[&](const char* name,float l,float r,uint32_t frame) {
        NativeLook::Saved was=sides.Enter(name,frame);
        V f[2]={{l,10,0,1,0,0,0},{r,40,0,1,0,0,0}}; sides.Gather(f,2,sizeof(V)); sides.Leave(was);
    };
    frameOf("menu    titlewin",15,127,1); frameOf("menu    helpwind",129,3309,1); frameOf("menu    netstat ",3311,3423,1);
    frameOf("menu    dialog  ",1600,1840,1); frameOf("menu    logwindo",15,674,1);
    float pinch=-1;
    saved=sides.Enter("menu    titlewin",2);
    Check(sides.Placing(3440,1440,place,&pinch) && pinch<0 && Near(place[2],100),"a window on the left half: moved right");
    sides.Leave(saved);
    saved=sides.Enter("menu    netstat ",2);
    Check(sides.Placing(3440,1440,place,&pinch) && Near(place[2],-100),"one on the right half: moved left");
    sides.Leave(saved);
    saved=sides.Enter("menu    helpwind",2);
    Check(sides.Placing(3440,1440,place,&pinch) && Near(pinch,1720),"the bar across the top: its ends brought in");
    sides.Leave(saved);
    V bar[4]={{129,10,0,1,0,0,0},{3309,10,0,1,0,0,0},{200,20,0,1,0,0,0},{3000,20,0,1,0,0,0}};
    NativePinchVertices(bar,4,sizeof(V),1720,100,0);
    Check(Near(bar[0].x,229) && Near(bar[1].x,3209) && Near(bar[2].x,300) && Near(bar[3].x,2900),"each vertex toward the middle: the bar 200 shorter, what is on it moved with its end");
    saved=sides.Enter("menu    dialog  ",2);
    Check(!sides.Placing(3440,1440,place,&pinch),"a narrower one over the middle: left");
    sides.Leave(saved);
    saved=sides.Enter("menu    logwindo",2);
    Check(!sides.Placing(3440,1440,place,&pinch),"the chat log: left, chatbox placing it");
    sides.Leave(saved);
    bool whole=false;
    saved=sides.Enter("menu    netstat ",2);
    Check(sides.Placing(3440,1440,place,&pinch,&whole) && whole,"moved by the inset alone: every draw of it moved, none kept back");
    sides.Leave(saved);
    V words[2]={{40,20,0,1,0,0,0},{90,32,0,1,0,0,0}},world[2]={{500,500,0,1,0,0,0},{540,520,0,1,0,0,0}};
    NativeEntry* owner=sides.Orphan(words,2,sizeof(V),2);
    Check(owner && !memcmp(owner->name,"menu    titlewin",16),"words drawn after the title box, within it: its");
    Check(!sides.Orphan(world,2,sizeof(V),2),"a draw within no window moved: none");
    Check(!sides.Orphan(words,2,sizeof(V),9),"a window not drawn lately: none");
    sides.Inset(0);
    saved=sides.Enter("menu    titlewin",3);
    Check(!sides.Placing(3440,1440,place,&pinch),"no inset: as the game puts it");
    sides.Leave(saved);
    printf("%d failures\n",failures);
    return failures ? 1 : 0;
}
