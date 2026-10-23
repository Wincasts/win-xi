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
    printf("%d failures\n",failures);
    return failures ? 1 : 0;
}
