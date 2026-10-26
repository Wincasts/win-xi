#include <stdio.h>
#include <cmath>
#include <d3d8.h>
#include "../src/modules/party/detour.h"
#include "../src/modules/party/target.h"
#include "../src/modules/chat/controls.h"
#include "../src/modules/window/window.h"
#include "../src/modules/window/mouse.h"
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
    { NativeTransform t; t.ax=place[0]; t.ay=place[1]; t.k=2; t.dx=place[2]; t.dy=place[3]; NativeTransformVertices(vertices,2,sizeof(V),t); }
    Check(Near(vertices[0].x,110) && Near(vertices[0].y,70) && Near(vertices[1].x,510) && Near(vertices[1].y,470),"vertices grown about the corner and moved");
    Check(vertices[0].colour==0x80808080 && Near(vertices[1].u,1),"their colours and texture places kept");

    // a window's draws' bounds gathered each frame, placed by the frame before's (the sides brought in)
    NativeLook look;
    look.Inset(50);
    NativeLook::Saved saved=look.Enter("menu    inventor",1);
    Check(!look.Placing(1000,800,place),"the first frame: no bounds yet, drawn as the game does");
    V drawn[2]={{100,50,0,1,0,0,0},{300,250,0,1,0,0,0}};
    look.Gather(drawn,2,sizeof(V));
    look.Leave(saved);
    saved=look.Enter("menu    inventor",2);
    Check(look.Placing(1000,800,place) && Near(place[2],50) && Near(place[3],0),"the next: placed by the frame before's bounds");
    NativeLook::Saved inner=look.Enter("menu    equip   ",2);
    Check(!look.Placing(1000,800,place),"a window inside it not yet drawn whole: drawn as the game does");
    look.Unmoved(); look.Leave(inner);
    look.Unmoved();
    Check(look.Find("menu    inventor",false)->unmoved==1 && look.Find("menu    equip   ",false)->unmoved==1,"a vertex buffer draw counted to the window it is in");
    look.Leave(saved);
    Check(!look.Placing(1000,800,place),"outside any window: nothing placed");

    // its frame's draws: what it is placed by; a draw wholly outside it (the inventory's count) kept back
    NativeLook framed;
    framed.MenuScale(2);
    saved=framed.Enter("menu    inventor",1);
    V frameDraw[2]={{100,50,0,1,0,0,0},{300,250,0,1,0,0,0}};
    framed.Gather(frameDraw,2,sizeof(V));
    framed.Phase(PHASE_CONTENT);
    V countDraw[2]={{90,10,0,1,0,0,0},{130,30,0,1,0,0,0}};
    framed.Gather(countDraw,2,sizeof(V));
    framed.Leave(saved);
    saved=framed.Enter("menu    inventor",2);
    Check(framed.Placing(1000,800,place) && Near(place[0],0) && Near(place[1],0),"grown from its frame's quarter of the screen, the top left");
    framed.Phase(PHASE_CONTENT);
    Check(!framed.Within(countDraw,2,sizeof(V)),"the count, wholly outside its frame, kept back");
    V rowDraw[2]={{120,60,0,1,0,0,0},{200,72,0,1,0,0,0}};
    V edgeDraw[2]={{90,60,0,1,0,0,0},{104,72,0,1,0,0,0}};
    Check(framed.Within(rowDraw,2,sizeof(V)) && framed.Within(edgeDraw,2,sizeof(V)),"a row, and the hand over its edge, moved");
    framed.Leave(saved);

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
    // a window opening: drawn within its layout target, which is over the log, before it reaches its place
    {
        NativeLook opening; opening.Group(0,-300);
        const int16_t logPlace[4]={16,1290,658,134},target[4]={16,1200,112,88};
        opening.Note("menu    logwindo",logPlace,1);
        const int16_t growing[4]={16,1230,112,30},elsewhere[4]={3312,47,112,202};
        Check(!opening.GroupMember("menu    menuwind",growing),"half grown, by its place alone: not of the group");
        Check(opening.GroupMember("menu    menuwind",growing,target),"half grown within its target over the log: of the group");
        Check(!opening.GroupMember("menu    menuwind",elsewhere,target),"drawn elsewhere with its target over the log (the Master menu): not of it");
        const int16_t away[4]={16,100,112,88};
        Check(!opening.GroupMember("menu    menuwind",growing,away),"a target not over the log: by its place alone");
        opening.Note("menu    menuwind",growing,2,target);
        Check(opening.Find("menu    menuwind",false) && opening.Find("menu    menuwind",false)->member,"noted with its target: its entry of the group");
    }
    // the group's frames drawn as panels: the group told with no move
    {
        NativeLook panels;
        NativePanelStyle style; style.fill=0xCC272743; style.border=0x66787A7C; style.rounding=3; style.thickness=1;
        panels.Frames(style);
        Check(panels.Any() && panels.Grouping() && !panels.groupOn,"frames on: the group told, not moved");
        panels.Note("menu    logwindo",log,1); panels.Note("menu    menuwind",command,1);
        NativeEntry* m=panels.Find("menu    menuwind",false);
        Check(m && m->group && m->member && m->dx==0 && m->dy==0,"the command menu of the group, where the game puts it");
        saved=panels.Enter("menu    menuwind",1);
        Check(panels.FrameDraw(),"its frame's draws may be the frame's art");
        panels.text++; Check(!panels.FrameDraw(),"not its title's text"); panels.text--;
        V fd[2]={{16,1200,0,1,0,0,0},{128,1288,0,1,0,0,0}}; panels.Gather(fd,2,sizeof(V));
        panels.Phase(PHASE_CONTENT); Check(!panels.FrameDraw(),"not its contents"); panels.Phase(PHASE_FRAME);
        panels.Leave(saved);
        saved=panels.Enter("menu    menuwind",2);
        float rect[4]={};
        Check(panels.PanelDue(3440,1440,2,rect) && Near(rect[0],16) && Near(rect[1],1200) && Near(rect[2],128) && Near(rect[3],1288),"its panel over its frame as last drawn");
        Check(!panels.PanelDue(3440,1440,2,rect),"once a frame");
        panels.Leave(saved);
        panels.Group(20,-40);
        saved=panels.Enter("menu    menuwind",3);
        Check(panels.PanelDue(3440,1440,3,rect) && Near(rect[0],36) && Near(rect[1],1160),"moved with the group");
        panels.Leave(saved);
        Check(panels.GroupOff()==1 && m->name[0] && m->dx==0 && m->dy==0 && panels.Grouping(),"the move off, frames on: the entry kept, not moved");
        saved=panels.Enter("menu    menuwind",4);
        panels.Note("menu    menuwind",right,4);
        Check(!panels.FrameDraw(),"placed elsewhere: the game's frame");
        panels.Leave(saved);
        Check(panels.FramesOff()==1 && !panels.Any(),"frames off too: its entries gone");
        std::vector<NativePanelVertex> tri;
        const float r[4]={10,20,110,70};
        NativePanel(r,style,tri);
        const unsigned perCorner=unsigned(3/2)+3,n=4*perCorner;
        Check(tri.size()==size_t(n)*3+size_t(n)*6,"a fill and a border of triangles round its rounded outline");
        float lo[2]={1e9f,1e9f},hi[2]={-1e9f,-1e9f};
        for (auto& v:tri) { lo[0]=(std::min)(lo[0],v.x); lo[1]=(std::min)(lo[1],v.y); hi[0]=(std::max)(hi[0],v.x); hi[1]=(std::max)(hi[1],v.y); }
        Check(Near(lo[0],9.5f) && Near(lo[1],19.5f) && Near(hi[0],109.5f) && Near(hi[1],69.5f),"within its rectangle, a pixel's middle at its .5");
        Check(tri[0].colour==style.fill && tri.back().colour==style.border && Near(tri[0].rhw,1),"the fill first, the border over it");
        style.border=0; NativePanel(r,style,tri);
        Check(tri.size()==size_t(n)*3,"a border wholly clear not drawn");
        style.rounding=0; NativePanel(r,style,tri);
        Check(tri.size()==12,"square: a point a corner");
        Check(NativeFrameHash(0x92C145C5u) && NativeFrameHash(0x72D3D795u) && !NativeFrameHash(0x30CDD9D4u) && !NativeFrameHash(0x9E2854A3u),"the frame's art, not the menu font or the buttons");
    }
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
    { NativeTransform t; t.pinch=true; t.middle=1720; t.width=3440; t.inset=100; NativeTransformVertices(bar,4,sizeof(V),t); }
    Check(Near(bar[0].x,229) && Near(bar[1].x,3209) && Near(bar[2].x,300) && Near(bar[3].x,2900),"each vertex toward the middle: the bar 200 shorter, what is on it moved with its end");
    saved=sides.Enter("menu    dialog  ",2);
    Check(!sides.Placing(3440,1440,place,&pinch),"a narrower one over the middle: left");
    sides.Leave(saved);
    saved=sides.Enter("menu    logwindo",2);
    Check(!sides.Placing(3440,1440,place,&pinch),"the chat log: left, chatbox placing it");
    sides.Leave(saved);
    // a window with no frame over the world (the target's arrow), and a tall one over the middle (the map): left
    {
        NativeLook::Saved was=sides.Enter("menu    cursor  ",5);
        sides.Phase(PHASE_CONTENT); V arrow[2]={{2400,300,0,1,0,0,0},{2416,316,0,1,0,0,0}}; sides.Gather(arrow,2,sizeof(V)); sides.Leave(was);
        frameOf("menu    mapframe",400,3000,5);
        V tall[2]={{400,900,0,1,0,0,0},{3000,1200,0,1,0,0,0}};
        was=sides.Enter("menu    mapframe",5); sides.Gather(tall,2,sizeof(V)); sides.Leave(was);
        was=sides.Enter("menu    cursor  ",6);
        Check(!sides.Placing(3440,1440,place,&pinch),"a window with no frame: left where the game puts it");
        sides.Leave(was);
        was=sides.Enter("menu    mapframe",6);
        Check(!sides.Placing(3440,1440,place,&pinch),"a tall framed one over the middle: left, not pinched");
        sides.Leave(was);
    }
    bool whole=false;
    saved=sides.Enter("menu    netstat ",2);
    Check(sides.Placing(3440,1440,place,&pinch,&whole) && whole,"moved by the inset alone: every draw of it moved, none kept back");
    sides.Leave(saved);
    // a window given an entry for the inset before the log was seen, then found to be of the group: the group's
    sides.Group(30,-200);
    saved=sides.Enter("menu    shopmain",3); sides.Leave(saved);
    NativeEntry* shop=sides.Find("menu    shopmain",false);
    Check(shop && !shop->group,"drawn before the log was seen: an entry for the inset");
    sides.Note("menu    logwindo",log,4);
    const int16_t buysell[4]={16,1248,112,40};
    sides.Note("menu    shopmain",buysell,4);
    Check(shop->group && shop->member && shop->dx==30 && shop->dy==-200,"then over the log: the group's, its offset given");
    sides.GroupOff();
    // the menu scale: each framed window from its quarter's corner, the bar from its ends, the log left
    Check(!sides.MenuScale(4) && sides.MenuScale(1.25f),"a menu scale from 0.5 to 3");
    NativeTransform mt;
    saved=sides.Enter("menu    netstat ",2);
    Check(sides.Transform(3440,1440,mt) && Near(mt.ax,3440) && Near(mt.ay,0) && Near(mt.k,1.25f) && Near(mt.dx,-100),"the network box: from the top right, brought in");
    { float x=3311,y=15; mt.Apply(x,y); Check(Near(x,3440-129*1.25f-100) && Near(y,18.75f),"its corner where the scale and the inset put it"); }
    sides.Leave(saved);
    saved=sides.Enter("menu    helpwind",2);
    Check(sides.Transform(3440,1440,mt) && mt.pinch,"the bar: by each end");
    { float l=129,r=3309,y=15; mt.Apply(l,y); float y2=15; mt.Apply(r,y2); Check(Near(l,129*1.25f+100) && Near(r,3440-131*1.25f-100),"its ends with the title box and the network box"); }
    sides.Leave(saved);
    // what the bar shows: by the end it is near, or left in the middle
    saved=sides.Enter("menu    helpwind",2);
    sides.Phase(PHASE_CONTENT);
    {
        V help[2]={{145,20,0,1,0,0,0},{400,32,0,1,0,0,0}},loading[2]={{1300,20,0,1,0,0,0},{2100,32,0,1,0,0,0}},title[2]={{3236,12,0,1,0,0,0},{3262,21,0,1,0,0,0}};
        NativeTransform h; sides.Transform(3440,1440,h); Check(sides.OnBar(help,2,sizeof(V),h) && !h.pinch && Near(h.ax,0) && Near(h.dx,100),"its help text, by its left end: with that end");
        V word[2]={{1000,20,0,1,0,0,0},{1010,32,0,1,0,0,0}};
        NativeTransform w; sides.Transform(3440,1440,w); Check(sides.OnBar(word,2,sizeof(V),w) && Near(w.dx,100),"a letter of its help text further along: with the left end as the rest");
        NativeTransform l; sides.Transform(3440,1440,l); sides.OnBar(loading,2,sizeof(V),l);
        sides.Leave(saved); saved=sides.Enter("menu    helpwind",3); sides.Phase(PHASE_CONTENT);
        V words[2]={{1300,20,0,1,0,0,0},{1500,32,0,1,0,0,0}};
        NativeTransform c; sides.Transform(3440,1440,c); Check(sides.OnBar(words,2,sizeof(V),c) && Near(c.ax,1720) && Near(c.dx,0),"while it shows something over its middle (loading): what is by it left in the middle");
        NativeTransform r; sides.Transform(3440,1440,r); Check(sides.OnBar(title,2,sizeof(V),r) && Near(r.ax,3440) && Near(r.dx,-100),"its title, by its right end: with that end");
        // no inset, scaled: "Hel" ends beyond the reach of the bar's end and "p" within it; all of it goes with the end
        sides.Inset(0);
        V hel[2]={{3236,12,0,1,0,0,0},{3254,21,0,1,0,0,0}},pee[2]={{3255,12,0,1,0,0,0},{3263,21,0,1,0,0,0}};
        NativeTransform th; sides.Transform(3440,1440,th); NativeTransform tp; sides.Transform(3440,1440,tp);
        Check(sides.OnBar(hel,2,sizeof(V),th) && Near(th.ax,3440) && sides.OnBar(pee,2,sizeof(V),tp) && Near(tp.ax,3440),"no inset: the whole title by its right end, \"Hel\" with its \"p\"");
        { float x=3236,y=12; th.Apply(x,y); Check(x<3440,"and \"Hel\" kept on the screen"); }
        sides.Inset(100);
    }
    sides.Phase(PHASE_FRAME);
    {
        V edge[2]={{129,15,0,1,0,0,0},{3309,20,0,1,0,0,0}};
        NativeTransform f; sides.Transform(3440,1440,f); Check(!sides.OnBar(edge,2,sizeof(V),f) && f.pinch,"its frame: pinched by each end");
    }
    sides.Leave(saved);
    saved=sides.Enter("menu    logwindo",2);
    Check(!sides.Transform(3440,1440,mt),"the chat log: as chatbox places it");
    sides.Leave(saved);
    // a window drawn the first time: placed at once by where the game draws it, not a frame late
    {
        const float place[4]={3311,47,3423,249};
        NativeLook::Saved was=sides.Enter("menu    newmenu ",7,place);
        float p[4]={};
        Check(sides.Placing(3440,1440,p) && Near(p[2],-100),"drawn the first time: moved with its side at once");
        V nf[2]={{3311,47,0,1,0,0,0},{3423,249,0,1,0,0,0}}; sides.Phase(PHASE_CONTENT); sides.Gather(nf,2,sizeof(V)); sides.Leave(was);
        was=sides.Enter("menu    newmenu ",8,place);
        Check(!sides.Placing(3440,1440,p),"drawing no frame of its own the frame before: the guess not kept");
        sides.Leave(was);
    }
    sides.MenuScale(1);
    sides.Inset(0);
    saved=sides.Enter("menu    titlewin",3);
    Check(!sides.Placing(3440,1440,place,&pinch),"no inset: as the game puts it");
    sides.Leave(saved);
    // the mouse: a place as drawn given back as the game's own
    {
        NativeTransform t; t.ax=100; t.ay=50; t.k=2; t.dx=10; t.dy=-20;
        float x=130,y=70; t.Apply(x,y); t.Invert(x,y);
        Check(Near(x,130) && Near(y,70),"a place moved and scaled, given back");
        NativeTransform b; b.pinch=true; b.middle=1720; b.width=3440; b.inset=100; b.k=1.25f;
        float l=400,ly=20,r=3000,ry=20; b.Apply(l,ly); b.Apply(r,ry); b.Invert(l,ly); b.Invert(r,ry);
        Check(Near(l,400) && Near(r,3000) && Near(ly,20),"on the bar, each side by its own end");
    }
    {
        NativeLook m;
        m.Group(0,-300);
        const int16_t log[4]={16,1290,658,134},command[4]={16,1200,112,88};
        m.Note("menu    logwindo",log,1);
        m.Note("menu    menuwind",command,1);
        NativeLook::Saved was=m.Enter("menu    menuwind",1);
        V cf[2]={{16,1200,0,1,0,0,0},{128,1288,0,1,0,0,0}}; m.Gather(cf,2,sizeof(V)); m.Leave(was);
        was=m.Enter("menu    menuwind",2); m.Gather(cf,2,sizeof(V)); m.Leave(was);
        float x=50,y=950;
        Check(m.MapPoint(3440,1440,3,x,y)==NATIVE_MOUSE_MOVED && Near(x,50) && Near(y,1250),"on the command menu drawn 300 up: the same place on the game's own");
        x=50; y=1250;
        Check(m.MapPoint(3440,1440,3,x,y)==NATIVE_MOUSE_KEPT && Near(y,1250),"where the game puts it, nothing drawn there: kept from the game");
        x=1500; y=500;
        Check(m.MapPoint(3440,1440,3,x,y)==NATIVE_MOUSE_AS_IS && Near(x,1500),"on no window: as it is");
        x=50; y=950;
        Check(m.MapPoint(3440,1440,9,x,y)==NATIVE_MOUSE_AS_IS && Near(y,950),"the menu not drawn for frames: as it is");
        // a window over it drawn after it, moved its own way (the sides brought in): the mouse is the one drawn last's
        m.Inset(100);
        V bf[2]={{20,850,0,1,0,0,0},{300,1000,0,1,0,0,0}};
        for (uint32_t f=3;f<=4;f++) {
            was=m.Enter("menu    menuwind",f); m.Gather(cf,2,sizeof(V)); m.Leave(was);
            was=m.Enter("menu    bazaar  ",f); m.Gather(bf,2,sizeof(V)); m.Leave(was);
        }
        x=125; y=950;
        Check(m.MapPoint(3440,1440,5,x,y)==NATIVE_MOUSE_MOVED && Near(x,25) && Near(y,950),"on both as drawn: the one drawn last, given back by its own move");
        x=60; y=930;
        Check(m.MapPoint(3440,1440,5,x,y)==NATIVE_MOUSE_MOVED && Near(x,60) && Near(y,1230),"on the command menu alone: by the group's move");
    }
    Check(MouseMessage(WM_LBUTTONDOWN) && MouseMessage(WM_MOUSEMOVE) && !MouseMessage(WM_MOUSEWHEEL) && !MouseMessage(WM_KEYDOWN),"which messages carry a place");
    Check(MouseRelease(WM_RBUTTONUP) && !MouseRelease(WM_RBUTTONDOWN),"a button let go");
    {
        // the game's mouse handler, its first bytes as the client has them: the pattern fits, and only what is stolen is whole instructions
        uint8_t handler[40]={0x83,0xEC,0x2C,0x53,0x8B,0x5C,0x24,0x38,0x55,0x56,0x8B,0x74,0x24,0x44,0x57,0x8B,0x7C,0x24,0x4C,0x81,0xFB,0x0F,0x01,0x00,0x00};
        Check(FindPattern(handler,sizeof(handler),GAME_INPUT_PATTERN)==handler && GAME_INPUT_STOLEN==8,"the mouse handler's pattern");
    }
    {
        MSG message={}; message.lParam=MAKELPARAM(100,200); message.pt.x=1100; message.pt.y=1200;
        MouseMove(message,40,70);
        Check(LOWORD(message.lParam)==40 && HIWORD(message.lParam)==70 && message.pt.x==1040 && message.pt.y==1070,"a message moved, its screen place as far");
    }
    printf("%d failures\n",failures);
    return failures ? 1 : 0;
}
