#include <stdio.h>
#include <cmath>
#include <d3d8.h>
#include "../src/modules/party/detour.h"
#include "../src/modules/party/target.h"
#include "../src/modules/chat/controls.h"
#include "../src/modules/mirror/census.h"
#include "../src/modules/mirror/mirror.h"
#include "../src/modules/mirror/labels.h"
#include "../src/modules/mirror/mouse.h"
#include "../src/modules/mirror/watch.h"
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
    Check(sizeof(MirrorShared)==84632,"mirror ABI 5's size");
    static MirrorShared block; memcpy(block.Magic,"UIHOOK-MIRROR",14); block.Version=5; block.Size=sizeof(block);
    block.Supported=1; block.Frame=10; block.RequestFrame=10; block.Hide[0]=1;
    memcpy(block.Requests[0],"menu    inventor",16); memcpy(block.Requests[1],"menu    iteminfo",16);
    static Mirror mirror; mirror.shared=&block;
    {   // past the first 32 requests: the hidden bit in the second word
        bool hide=false;
        memcpy(block.Requests[40],"menu    menuwind",16);
        Check(mirror.Wanted("menu    menuwind",hide) && !hide,"the 41st asked, watched");
        block.Hide[1]=1u<<8;
        Check(mirror.Wanted("menu    menuwind",hide) && hide,"the 41st hidden by the second word");
        block.Hide[0]|=1u<<31; memcpy(block.Requests[31],"menu    bank    ",16);
        Check(mirror.Wanted("menu    bank    ",hide) && hide && mirror.Wanted("menu    inventor",hide) && hide,"the 32nd hidden, the first still");
        memcpy(block.Requests[100],"menu    auc1    ",16); block.Hide[3]=1u<<4;
        Check(mirror.Wanted("menu    auc1    ",hide) && hide,"the 101st hidden by the fourth word");
        memset(block.Requests[100],0,16); block.Hide[3]=0;
        memset(block.Requests[40],0,16); memset(block.Requests[31],0,16); block.Hide[0]=1; block.Hide[1]=0;
    }
    const D3DVIEWPORT8 view={0,0,1000,500,0,1};
    FakeWindow inventor("menu    inventor",true,true), info("menu    iteminfo",false,false), other("menu    playermo",true,true);

    // a hidden window: its frame, its text, its icons, its cursor
    mirror.Viewport(view);
    Mirror::Saved saved;
    Check(mirror.Begin(inventor.window,nullptr,saved) && mirror.Active(),"a window asked for and hidden: left undrawn, and mirrored");
    Vertex v[6];
    Quad(v,100,100,300,300,0x80808080); mirror.Record(FVF,nullptr,v,sizeof(Vertex),6);
    mirror.Phase(PHASE_CONTENT);
    mirror.TextBegin(TEXT_FONT,221,72,"Automat. Oil +1\nthe next line",0x80509050);
    mirror.TextBegin(TEXT_BITMAP,0,0,"nested",0x80808080); // a text call within one: part of it, no run of its own
    Quad(v,120,150,180,160,0x80808080); mirror.Record(FVF,nullptr,v,sizeof(Vertex),6);
    mirror.TextEnd();
    Quad(v,181,150,200,162,0x80808080); mirror.Record(FVF,nullptr,v,sizeof(Vertex),6);
    mirror.TextEnd();
    FakeTexture icons;
    icons.AddRef(); Quad(v,100,148,116,164,0x80404040,0.25f,0.5f,0.375f,0.625f); mirror.Record(FVF,&icons,v,sizeof(Vertex),6);
    icons.AddRef(); Quad(v,100,166,116,182,0x80808080); mirror.Record(FVF,&icons,v,sizeof(Vertex),6);
    Check(icons.refs==2,"a texture held once however many of its quads there are");
    mirror.Phase(PHASE_AFTER);
    mirror.Phase(PHASE_CURSOR); Quad(v,80,150,98,162,0x80808080); mirror.Record(FVF,nullptr,v,sizeof(Vertex),6); mirror.Phase(PHASE_AFTER);
    mirror.Scrollbar(ChatScrollInfo{10,30,5});
    Quad(v,0,0,999,499,0x80808080); mirror.Record(FVF,nullptr,v,sizeof(Vertex),6); // after the controls: neither the frame nor contents
    mirror.End(saved);
    Check(!mirror.Active(),"the window drawn: nothing mirrored");

    // a watched window: drawn by the game, still mirrored; and one not asked for
    Check(!mirror.Begin(info.window,nullptr,saved) && mirror.Active(),"a watched window: the game draws it, and it is mirrored");
    {
        Mirror::Saved inner;
        Check(!mirror.Begin(other.window,nullptr,inner) && !mirror.Active(),"a window not asked for, drawn within it: not mirrored");
        mirror.Record(FVF,nullptr,v,sizeof(Vertex),6);
        mirror.End(inner);
    }
    Check(mirror.Active(),"the outer window mirrored again after it");
    mirror.End(saved);

    mirror.Publish(10);
    const MirrorFrameData& f=block.Published;
    Check(f.Frame==10 && f.WindowCount==2 && block.Serial==1,"two windows published at frame 10");
    const MirrorWindow& w=f.Windows[0];
    Check(!memcmp(w.Name,"menu    inventor",16) && w.Flags==(MIRROR_HAS_CURSOR|MIRROR_FOCUSED|MIRROR_HIDDEN|MIRROR_DREW_CONTENT),"its name and flags");
    Check(Near(w.Rect[0],0.1005f) && Near(w.Rect[1],0.201f) && Near(w.Rect[2],0.3005f) && Near(w.Rect[3],0.601f),"its frame's place, normalized with the half pixel");
    Check(w.CursorFrame==10 && Near(w.Cursor[0],0.0805f),"its cursor's place");
    Check(w.ScrollPage==10 && w.ScrollCount==30 && w.ScrollTop==5 && !w.ScrollFrame,"the scrollbar's rows, though none of it was drawn");
    Check(w.Target[0]==200 && w.Target[3]==190,"the game's layout target");
    Check(w.Runs==1 && f.RunCount==1,"one run: the nested call is part of it");
    const MirrorRun& r=f.Runs[0];
    Check(r.Length==15 && !memcmp(f.Text+r.Offset,"Automat. Oil +1",15),"its text to the line's end");
    Check(r.Route==TEXT_FONT && r.Colour==0x80509050 && r.X==221 && r.Y==72 && r.Phase==PHASE_CONTENT,"its route, colour and place as asked");
    Check(Near(r.Rect[0],0.1205f) && Near(r.Rect[2],0.2005f) && Near(r.Rect[3],0.325f),"its place measured from both its glyph draws");
    Check(w.Quads==2 && f.Quads[0].Texture==static_cast<uint32_t>(reinterpret_cast<uintptr_t>(static_cast<IDirect3DBaseTexture8*>(&icons))),"two quads, the icons' texture");
    Check(Near(f.Quads[0].UV[0],0.25f) && Near(f.Quads[0].UV[3],0.625f) && f.Quads[0].Colour==0x80404040,"a quad's corners in its texture and its colour");
    Check(!memcmp(f.Windows[1].Name,"menu    iteminfo",16) && !(f.Windows[1].Flags & MIRROR_HIDDEN),"the watched window, not hidden");
    Check(icons.refs==2,"the published texture held");

    // the next frame: nothing asked, nothing drawn; what was held given back
    block.Frame=11;
    mirror.Publish(11);
    Check(f.WindowCount==0 && f.Frame==0 && block.Serial==2,"an empty frame published once");
    Check(icons.refs==2,"the texture still held a frame on, for an addon drawing the last frame late");
    mirror.Publish(12);
    Check(block.Serial==2,"and not again while nothing is mirrored");
    Check(icons.refs==1,"the texture given back two frames on");

    // a stale request, or no viewport: the game's own
    block.Frame=15;
    mirror.Viewport(view);
    Check(!mirror.Begin(inventor.window,nullptr,saved) && !mirror.Active(),"a request five frames old: the game draws its own");
    mirror.End(saved);
    block.Frame=12; mirror.Publish(12);
    Check(!mirror.Begin(inventor.window,nullptr,saved) && !mirror.Active() && block.Dropped==0,"no viewport known: the game draws its own");
    mirror.End(saved);
    mirror.Publish(12);
    Check(block.Dropped==1,"and that counted as dropped");

    // too much text: the runs past the room dropped, the window kept
    mirror.Viewport(view);
    mirror.Begin(inventor.window,nullptr,saved); mirror.Phase(PHASE_CONTENT);
    for (unsigned i=0;i<MIRROR_RUNS+3;i++) { mirror.TextBegin(TEXT_FONT,0,0,"x",0); mirror.TextEnd(); }
    mirror.End(saved); mirror.Publish(12);
    Check(f.RunCount==MIRROR_RUNS && block.Dropped==4,"runs past the room dropped and counted");

    // elements: each a quad of its art; the one tinted (the cursor's) the window's selection, the rest not
    mirror.Viewport(view);
    mirror.Begin(other.window,nullptr,saved);
    Check(!mirror.Active(),"a window not asked for: its elements nothing");
    mirror.End(saved);
    memcpy(block.Requests[2],"menu    menuwind",16);
    FakeWindow menu("menu    menuwind",true,true);
    mirror.Begin(menu.window,nullptr,saved);
    WindowPhase was=mirror.Element(0x80808080);
    icons.AddRef(); Quad(v,100,100,180,116,0x80808080,0,0,0.5f,0.0625f); mirror.Record(FVF,&icons,v,sizeof(Vertex),6);
    mirror.Phase(was);
    was=mirror.Element(0x80805020);
    icons.AddRef(); Quad(v,100,118,180,134,0x80805020,0,0.0625f,0.5f,0.125f); mirror.Record(FVF,&icons,v,sizeof(Vertex),6);
    mirror.Phase(was);
    was=mirror.Element(0x30808080); // greyed: not the cursor's
    icons.AddRef(); Quad(v,100,136,180,152,0x30808080); mirror.Record(FVF,&icons,v,sizeof(Vertex),6);
    mirror.Phase(was);
    Quad(v,90,90,200,170,0x80808080); mirror.Record(FVF,nullptr,v,sizeof(Vertex),6); // after: the frame
    mirror.End(saved); mirror.Publish(12);
    const MirrorWindow& m=f.Windows[0];
    Check(m.Quads==3 && f.Quads[0].Phase==PHASE_ELEMENT && f.Quads[1].Phase==PHASE_ELEMENT,"three elements, each a quad");
    Check(Near(f.Quads[1].UV[1],0.0625f) && f.Quads[1].Colour==0x80805020,"the cursor's element: its corners and tint");
    Check(m.SelectionFrame==block.Frame && Near(m.Selection[1],0.237f) && Near(m.Selection[3],0.269f),"the selection the tinted element's, not the window's");
    Check(Near(m.Rect[1],0.181f) && Near(m.Rect[3],0.341f),"the frame the frame's, the elements apart from it");
    mirror.Publish(12); mirror.Publish(12);
    Check(icons.refs==1,"the elements' texture given back");
    memset(block.Requests[2],0,16);

    // given back on release
    mirror.Viewport(view);
    mirror.Begin(inventor.window,nullptr,saved); mirror.Phase(PHASE_CONTENT);
    icons.AddRef(); mirror.Record(FVF,&icons,v,sizeof(Vertex),6);
    mirror.End(saved); mirror.Publish(12);
    Check(icons.refs==2,"held");
    mirror.Publish(12);
    Check(icons.refs==2,"held a frame on");
    mirror.Clear();
    Check(icons.refs==1 && f.WindowCount==0,"released and nothing published");
    // a draw that is not screen space is nothing of the window's
    mirror.Viewport(view); mirror.Begin(inventor.window,nullptr,saved); mirror.Phase(PHASE_CONTENT);
    icons.AddRef(); mirror.Record(D3DFVF_XYZ|D3DFVF_TEX1,&icons,v,sizeof(Vertex),6);
    mirror.End(saved); mirror.Publish(12); mirror.Publish(12);
    Check(f.QuadCount==0 && icons.refs==1,"a world-space draw: no quad, its texture given back");
    // labels: the texels of a texture decoded as ARGB
    {
        const uint16_t argb4[4]={0xF00F,0x8F00,0x00F0,0x1234}; // 2x2 A4R4G4B4
        LabelPixels p;
        Check(LabelDecode(reinterpret_cast<const uint8_t*>(argb4),4,D3DFMT_A4R4G4B4,1,0,2,2,p) && p.width==1 && p.height==2
            && p.argb[0]==0x88FF0000 && p.argb[1]==0x11223344,"A4R4G4B4 cut and widened");
        // DXT1, one block: colour 0 white, colour 1 black, opaque; row 0 all index 0, row 1 all index 1, row 2 index 2, row 3 index 3
        const uint8_t dxt1[8]={0xFF,0xFF,0x00,0x00,0x00,0x55,0xAA,0xFF};
        Check(LabelDecode(dxt1,8,MAKEFOURCC('D','X','T','1'),0,0,4,4,p) && p.argb[0]==0xFFFFFFFF && p.argb[4]==0xFF000000
            && p.argb[8]==0xFFAAAAAA && p.argb[12]==0xFF555555,"DXT1 block");
        // DXT3: explicit alpha, the first texel 0, the rest 15
        uint8_t dxt3[16]; memset(dxt3,0xFF,8); dxt3[0]=0xF0; memcpy(dxt3+8,dxt1,8);
        Check(LabelDecode(dxt3,16,MAKEFOURCC('D','X','T','3'),0,0,2,1,p) && p.argb[0]==0x00FFFFFF && p.argb[1]==0xFFFFFFFF,"DXT3 alpha");
        Check(!LabelDecode(dxt1,8,D3DFMT_P8,0,0,1,1,p),"a format not read refused");
    }
    // the mouse: a place on a menu drawn elsewhere and larger, given to the game at the same place on its own
    {
        static MirrorShared m; m.Frame=100;
        float x=0.3f,y=0.3f;
        Check(!MirrorMapPoint(m,x,y),"nothing said: no place moved");
        const float maps[2][8]={ { 0.5f,0.5f,0.9f,0.9f, 0.1f,0.1f,0.3f,0.3f }, { 0.0f,0.0f,0.2f,0.2f, 0.0f,0.0f,0.2f,0.2f } };
        memcpy(m.Mouse,maps,sizeof(maps)); m.MouseCount=2; m.MouseFrame=99;
        x=0.7f; y=0.6f;
        Check(MirrorMapPoint(m,x,y) && Near(x,0.2f) && Near(y,0.15f),"on a menu drawn twice as large, elsewhere: the same place on the game's own");
        x=0.4f; y=0.4f;
        Check(!MirrorMapPoint(m,x,y) && Near(x,0.4f),"off every menu: the place as it was");
        x=0.9f; y=0.7f;
        Check(!MirrorMapPoint(m,x,y),"the right edge is not on it");
        m.Frame=104; x=0.7f; y=0.6f;
        Check(!MirrorMapPoint(m,x,y),"said five frames ago: no place moved");
        m.Frame=100; m.MouseCount=1000; x=0.7f; y=0.6f;
        Check(MirrorMapPoint(m,x,y),"a count past the room read as the room");
        m.MouseCount=2;
        // a message in a client area of 1000 by 500: lParam and the screen's pt moved as far
        MSG message={}; message.message=WM_LBUTTONDOWN; message.lParam=MAKELPARAM(700,300); message.pt={ 1700,1300 };
        Check(MirrorMapMessage(m,message,1000,500) && LOWORD(message.lParam)==200 && HIWORD(message.lParam)==75
            && message.pt.x==1200 && message.pt.y==1075,"a press on the drawn menu: given at the game's own place");
        message.message=WM_MOUSEWHEEL; message.lParam=MAKELPARAM(700,300);
        Check(!MirrorMapMessage(m,message,1000,500) && LOWORD(message.lParam)==700,"the wheel's place (the screen's) left alone");
        message.message=WM_KEYDOWN;
        Check(!MirrorMouseMessage(WM_KEYDOWN) && MirrorMouseMessage(WM_MOUSEMOVE) && MirrorMouseMessage(WM_XBUTTONUP),"which messages carry a place");
        message.message=WM_MOUSEMOVE; message.lParam=MAKELPARAM(static_cast<WORD>(-5),10);
        Check(!MirrorMapMessage(m,message,1000,500),"a place left of the client area: on no menu");
        // the game's handler, its first bytes as the client has them: the pattern fits, and only what is stolen is whole instructions
        uint8_t handler[40]={0x83,0xEC,0x2C,0x53,0x8B,0x5C,0x24,0x38,0x55,0x56,0x8B,0x74,0x24,0x44,0x57,0x8B,0x7C,0x24,0x4C,0x81,0xFB,0x0F,0x01,0x00,0x00};
        Check(FindPattern(handler,sizeof(handler),MIRROR_INPUT_PATTERN)==handler && MIRROR_INPUT_STOLEN==8,"the mouse handler's pattern");
    }
    {
        // the watch: each window drawn, asked for or not, mirrored or not, and how it drew; written as it changes
        MirrorWatch watch; static MirrorFrameData none{};
        FakeWindow asked("menu    auc1    ",true,true), seen("menu    partywin",false,false);
        watch.Start();
        int was=watch.Enter(asked.window,true,false,false);
        watch.Draw(MirrorWatch::BUFFER); watch.Draw(MirrorWatch::BUFFER);
        const int outer=watch.Enter(seen.window,false,false,false); watch.Draw(MirrorWatch::UP); watch.Leave(outer);
        watch.Draw(MirrorWatch::OTHER);
        watch.Leave(was);
        static MirrorWatchShared block{};
        watch.Share(block,10);
        Check(block.Count==2 && block.Frame==10 && !memcmp(block.Windows[0].Name,"menu    auc1    ",16) && block.Windows[0].Flags==MIRROR_WATCH_WANTED
            && block.Windows[0].Buffer==2 && block.Windows[0].Other==1 && block.Windows[1].Depth==1 && block.Windows[1].Up==1,"the watch's block: each window drawn, its flags and draws");
        std::string text=watch.Present(none,3,10,5000,"12:00:00.000");
        Check(text.find("== 12:00:00.000 frame 10: 2 drawn, 0 published, 3 dropped")==0,"the watch: a frame's heading");
        Check(text.find("menu    auc1     kind 0 draws 0 depth 0: asked NOT MIRRORED; draws: 0 measured, 1 not screen space, 2 from buffers")!=std::string::npos,
            "an asked window not mirrored, its draws counted by kind, a nested window's not among them");
        Check(text.find("menu    partywin kind 0 draws 0 depth 1: -; draws: 1 measured")!=std::string::npos,"a window drawn within it, not asked for");
        was=watch.Enter(asked.window,true,false,false); watch.Draw(MirrorWatch::BUFFER);
        { const int inner=watch.Enter(seen.window,false,false,false); watch.Draw(MirrorWatch::UP); watch.Draw(MirrorWatch::UP); watch.Leave(inner); }
        watch.Leave(was);
        Check(watch.Present(none,3,11,5300,"").empty(),"the same windows: nothing written, whatever their draws");
        was=watch.Enter(asked.window,true,true,true); watch.Leave(was);
        Check(watch.Present(none,3,12,5600,"").empty(),"a change within the second: not yet");
        was=watch.Enter(asked.window,true,true,true); watch.Leave(was);
        text=watch.Present(none,3,13,6100,"t");
        Check(text.find("asked hidden mirrored (no draws)")==std::string::npos && text.find("asked hidden mirrored; draws: 0 measured")!=std::string::npos,"and after it, written");
        watch.Renew();
        was=watch.Enter(asked.window,true,true,true); watch.Leave(was);
        Check(!watch.Present(none,3,14,6200,"t").empty(),"after a mark: the next frame written");
        watch.Stop();
        Check(watch.Enter(asked.window,true,true,true)==-1 && watch.Present(none,0,15,20000,"").empty(),"stopped: nothing kept or written");
    }
    printf("%d failures\n",failures);
    return failures ? 1 : 0;
}
