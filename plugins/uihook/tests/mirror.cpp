#include <stdio.h>
#include <cmath>
#include <d3d8.h>
#include "../src/modules/party/detour.h"
#include "../src/modules/party/target.h"
#include "../src/modules/chat/controls.h"
#include "../src/modules/window/window.h"
#include "../src/modules/native/native.h"
#include "../src/modules/native/mirror.h"
static int failures=0;
static void Check(bool ok,const char* text) { printf("%s %s\n",ok?"ok":"FAIL",text); if(!ok) ++failures; }
static bool Near(float a,float b) { return std::fabs(a-b)<1e-4f; }

// A texture that counts its references, standing in for the game's
struct FakeTexture : IDirect3DBaseTexture8 {
    ULONG refs=1;
    STDMETHOD(QueryInterface)(REFIID,void**) override { return E_NOINTERFACE; }
    STDMETHOD_(ULONG,AddRef)() override { return ++refs; }
    STDMETHOD_(ULONG,Release)() override { return --refs; }
    STDMETHOD(GetDevice)(IDirect3DDevice8**) override { return E_FAIL; }
    STDMETHOD(SetPrivateData)(REFGUID,const void*,DWORD,DWORD) override { return E_FAIL; }
    STDMETHOD(GetPrivateData)(REFGUID,void*,DWORD*) override { return E_FAIL; }
    STDMETHOD(FreePrivateData)(REFGUID) override { return E_FAIL; }
    STDMETHOD_(DWORD,SetPriority)(DWORD) override { return 0; }
    STDMETHOD_(DWORD,GetPriority)() override { return 0; }
    STDMETHOD_(void,PreLoad)() override {}
    STDMETHOD_(D3DRESOURCETYPE,GetType)() override { return D3DRTYPE_TEXTURE; }
    STDMETHOD_(DWORD,SetLOD)(DWORD) override { return 0; }
    STDMETHOD_(DWORD,GetLOD)() override { return 0; }
    STDMETHOD_(DWORD,GetLevelCount)() override { return 1; }
};
// A window as Window::Render has one: its header (+4) naming it at +46, cursor and focus at +62, layout at +8C
struct FakeWindow {
    uint8_t window[0xa0]={}; uint8_t header[0x60]={};
    FakeWindow(const char* name,bool cursor,bool focus) {
        uint8_t* at=header; memcpy(window+WINDOW_HEADER,&at,4);
        memcpy(header+WINDOW_NAME,name,16);
        window[WINDOW_CURSOR]=cursor; window[WINDOW_FOCUS]=focus;
        const int16_t target[4]={200,48,182,190}; memcpy(window+WINDOW_TARGET,target,8);
    }
};
// XYZRHW, diffuse, one texture: 28 bytes a vertex
struct Vertex { float x,y,z,rhw; uint32_t colour; float u,v; };
static const DWORD FVF=D3DFVF_XYZRHW|D3DFVF_DIFFUSE|D3DFVF_TEX1;
static void Quad(Vertex* out,float l,float t,float r,float b,uint32_t colour,float u0=0,float v0=0,float u1=1,float v1=1) {
    out[0]={l,t,0,1,colour,u0,v0}; out[1]={r,t,0,1,colour,u1,v0}; out[2]={l,b,0,1,colour,u0,v1};
    out[3]={r,t,0,1,colour,u1,v0}; out[4]={r,b,0,1,colour,u1,v1}; out[5]={l,b,0,1,colour,u0,v1};
}

int main() {
    static MirrorShared block; memcpy(block.Magic,"UIHOOK-MIRROR",14); block.Version=6; block.Size=sizeof(block);
    block.Supported=1; block.Frame=10; block.RequestFrame=10;
    memcpy(block.Kept[0],"menu    iteminfo",16);
    static Mirror mirror; mirror.shared=&block;
    Check(mirror.Wanted() && mirror.Kept("menu    iteminfo") && !mirror.Kept("menu    menuwind"),"asked for, one window kept for the game");
    const D3DVIEWPORT8 view={0,0,1000,500,0,1};
    FakeWindow command("menu    menuwind",true,true), info("menu    iteminfo",false,false), other("menu    equip   ",true,true);

    // a window of the group: its frame, its text, its icons, its elements, its cursor, measured; left undrawn
    mirror.Viewport(view);
    Mirror::Saved saved;
    // Render begun: what is under way kept; the window taken at its first draw
    Check(!(mirror.Hold(saved),mirror.Begin(command.window,"menu    menuwind",false,nullptr,nullptr)) && !mirror.Active(),"a window not of the group: not mirrored");
    mirror.End(saved);
    Check((mirror.Hold(saved),mirror.Begin(command.window,"menu    menuwind",true,nullptr,nullptr)) && mirror.Active() && mirror.Hiding(),"one of the group: left undrawn, and mirrored");
    Vertex v[6];
    Quad(v,100,100,300,300,0x80808080); mirror.Record(FVF,nullptr,v,sizeof(Vertex),6);
    FakeTexture font;
    mirror.Element(0x80808080); font.AddRef(); Quad(v,110,110,118,120,0x80808080,0.3f,0.1f,0.33f,0.14f); mirror.Record(FVF,&font,v,sizeof(Vertex),6);
    mirror.Element(0x80805020); font.AddRef(); Quad(v,110,130,118,140,0x80805020); mirror.Record(FVF,&font,v,sizeof(Vertex),6);
    mirror.Phase(PHASE_FRAME);
    mirror.Phase(PHASE_CONTENT);
    mirror.TextBegin(TEXT_FONT,221,72,"Attack\nthe next line",0x80808080);
    mirror.TextBegin(TEXT_BITMAP,0,0,"nested",0x80808080); // a text call within one: part of it, no run of its own
    Quad(v,120,150,180,160,0x80808080); mirror.Record(FVF,nullptr,v,sizeof(Vertex),6);
    mirror.TextEnd();
    mirror.TextEnd();
    mirror.Phase(PHASE_AFTER);
    mirror.Phase(PHASE_CURSOR); Quad(v,80,150,98,162,0x80808080); mirror.Record(FVF,nullptr,v,sizeof(Vertex),6); mirror.Phase(PHASE_AFTER);
    mirror.Scrollbar(ChatScrollInfo{10,30,5});
    {
        Mirror::Saved inner;
        Check(!(mirror.Hold(inner),mirror.Begin(other.window,"menu    equip   ",false,nullptr,nullptr)) && !mirror.Active(),"a window not of it drawn within it: not mirrored");
        mirror.Record(FVF,nullptr,v,sizeof(Vertex),6);
        mirror.End(inner);
    }
    Check(mirror.Active() && mirror.Hiding(),"the outer window mirrored again after it");
    mirror.End(saved);
    Check(!mirror.Active(),"the window drawn: nothing mirrored");

    // one the addon keeps for the game: drawn by it, still published; and one drawn moved by the native look
    Check(!(mirror.Hold(saved),mirror.Begin(info.window,"menu    iteminfo",true,nullptr,nullptr)) && mirror.Active() && !mirror.Hiding(),"a window kept: the game draws it, and it is published");
    mirror.End(saved);
    NativeTransform move; move.dx=50; move.dy=-20; move.k=2; move.ax=100; move.ay=100;
    Check((mirror.Hold(saved),mirror.Begin(other.window,"menu    equip   ",true,&move,nullptr)),"one moved and larger");
    Quad(v,100,100,200,150,0x80808080); mirror.Record(FVF,nullptr,v,sizeof(Vertex),6);
    mirror.End(saved);

    mirror.Publish(10);
    const MirrorFrameData& f=block.Published;
    Check(f.Frame==10 && f.WindowCount==3 && block.Serial==1 && mirror.windowsMirrored==2,"three windows published at frame 10, two drawn by the addon");
    const MirrorWindow& w=f.Windows[0];
    Check(!memcmp(w.Name,"menu    menuwind",16) && w.Flags==(MIRROR_HAS_CURSOR|MIRROR_FOCUSED|MIRROR_HIDDEN|MIRROR_DREW_CONTENT),"its name and flags");
    Check(Near(w.Rect[0],0.1005f) && Near(w.Rect[1],0.201f) && Near(w.Rect[2],0.3005f) && Near(w.Rect[3],0.601f),"its frame's place, normalized with the half pixel");
    Check(w.CursorFrame==10 && Near(w.Cursor[0],0.0805f),"its cursor's place");
    Check(w.SelectionFrame==10 && Near(w.Selection[1],0.261f),"the element the cursor is on, by its tint");
    Check(w.ScrollPage==10 && w.ScrollCount==30 && w.ScrollTop==5 && !w.ScrollFrame,"the scrollbar's rows, though none of it was drawn");
    Check(w.Runs==1 && f.Runs[0].Length==6 && !memcmp(f.Text+f.Runs[0].Offset,"Attack",6) && f.Runs[0].Phase==PHASE_CONTENT,"one run, to the line's end");
    Check(Near(f.Runs[0].Rect[0],0.1205f) && Near(f.Runs[0].Rect[3],0.321f),"its place measured from its glyphs");
    Check(w.Quads==2 && f.Quads[0].Phase==PHASE_ELEMENT && Near(f.Quads[0].UV[0],0.3f) && f.Quads[1].Colour==0x80805020,"its elements, letters of the menu font, quads with their tint");
    Check(font.refs==2,"a texture held once however many of its quads there are");
    Check(!memcmp(f.Windows[1].Name,"menu    iteminfo",16) && f.Windows[1].Flags==MIRROR_KEPT_FLAG,"the window kept: not hidden");
    const MirrorWindow& m=f.Windows[2];
    Check(Near(m.Rect[0],0.1505f) && Near(m.Rect[1],0.161f) && Near(m.Rect[2],0.3505f) && Near(m.Rect[3],0.361f),"the one moved measured where it is drawn: grown about its corner, then moved");

    // the next frames: nothing drawn; what was held given back two frames on
    block.Frame=11; mirror.Publish(11);
    Check(f.WindowCount==0 && f.Frame==0 && block.Serial==2,"an empty frame published once");
    Check(font.refs==2,"the texture still held a frame on, for an addon drawing the last frame late");
    mirror.Publish(12);
    Check(block.Serial==2 && font.refs==1,"not published again while nothing is mirrored; the texture given back");

    // a stale request, or no viewport: the game's own
    block.Frame=15;
    mirror.Viewport(view);
    Check(!mirror.Wanted() && !(mirror.Hold(saved),mirror.Begin(command.window,"menu    menuwind",true,nullptr,nullptr)) && !mirror.Active(),"a request five frames old: the game draws the group");
    mirror.End(saved);
    block.RequestFrame=15; mirror.Publish(15);
    Check(!(mirror.Hold(saved),mirror.Begin(command.window,"menu    menuwind",true,nullptr,nullptr)) && !mirror.Active(),"no viewport known: the game draws it");
    mirror.End(saved);
    mirror.Publish(15);
    Check(block.Dropped==1,"and that counted as dropped");

    // a window drawn within one mirrored, never settled (it drew nothing): the outer mirrored again after it
    mirror.Viewport(view);
    mirror.Hold(saved); mirror.Begin(command.window,"menu    menuwind",true,nullptr,nullptr);
    {
        Mirror::Saved inner;
        mirror.Hold(inner);
        Check(!mirror.Active(),"held for a window inside it: nothing of it mirrored until it is taken");
        mirror.End(inner);
    }
    Check(mirror.Active() && mirror.Hiding(),"the outer window still mirrored after one that drew nothing");
    mirror.End(saved);
    mirror.Publish(16);

    // cleared (the hooks given back): nothing held, nothing published
    mirror.Viewport(view);
    (mirror.Hold(saved),mirror.Begin(command.window,"menu    menuwind",true,nullptr,nullptr));
    mirror.Phase(PHASE_CONTENT); font.AddRef(); Quad(v,0,0,8,8,0x80808080); mirror.Record(FVF,&font,v,sizeof(Vertex),6);
    mirror.End(saved);
    mirror.Clear();
    Check(font.refs==1 && f.WindowCount==0 && !mirror.Active(),"cleared: textures given back, nothing published");

    printf("%d failures\n",failures);
    return failures ? 1 : 0;
}
