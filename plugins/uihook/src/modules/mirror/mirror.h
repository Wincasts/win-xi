// The menu mirror: a window of the game's, named by an addon, keeps working as it is (its input, its
// cursor, its hit-tests the game's own), while what it draws is measured and, if the addon asks, left
// undrawn; the addon draws its own from what the game would have. Independent mirror ABI 4.
//
// Window::Render draws a window in three parts: its frame, then its contents through its owner's
// vtable +10, then the cursor, row highlight and scrollbar. The one call to the contents is taken
// (MIRROR_CONTENT_PATTERN, five bytes, mov edx,[ecx]; call [edx+10], made a call to ours), so every draw
// is known to be the frame's, the contents', or a control's. In the contents, the text routines say what
// is printed and where (census.h), and every other draw is a quad of the game's art (an item's icon),
// kept with its texture and its place in it. Each is measured from its screen-space vertices.
//
// Everything is published in pixels of the viewport, normalized to it, as the chat rectangles are: the
// window's own place among them, so that a mirror drawn over it stands where the game's hit-tests are.
#pragma once
#include <stdint.h>
#include <string.h>
#include <vector>
#include <algorithm>

// Window::Render's call to the contents, +20 into this pattern, checked to lie in Window::Render
#define MIRROR_CONTENT_PATTERN "8B 4D 0C 85 C9 74 ?? 8A 45 6A 84 C0 74 ?? 83 7D 10 0E 74 ?? 8B 11 FF 52 10"
#define MIRROR_CONTENT_AT 20
#define MIRROR_CONTENT_WITHIN 0x800
#define MIRROR_REQUESTS 128 // windows an addon may name
#define MIRROR_WINDOWS 16  // windows published a frame
#define MIRROR_RUNS 512
#define MIRROR_QUADS 512
#define MIRROR_TEXT 32768
#define MIRROR_RUN_BYTES 255
#define MIRROR_REQUEST_FRAMES 4 // a request holds this many frames after the addon last renewed it

// What a draw belonged to. An element is one of the window's own sprites, drawn by Window::Render before the
// contents from its list of elements: the labels of a menu whose words are pictures (the main menu, the command
// menu), its buttons and icons; the one the cursor is on drawn tinted, which makes the window's Selection.
enum MirrorPhase : uint32_t { MIRROR_FRAME, MIRROR_CONTENT, MIRROR_CURSOR, MIRROR_ELEMENT, MIRROR_SCROLL, MIRROR_AFTER };
// Window flags: its cursor shown (+62), it focused (+63), it left undrawn, its contents drawn this frame
enum : uint32_t { MIRROR_HAS_CURSOR=1, MIRROR_FOCUSED=2, MIRROR_HIDDEN=4, MIRROR_DREW_CONTENT=8 };

struct MirrorRun {      // a piece of text as the game printed it
    float Rect[4];      // measured from its glyphs, normalized; all zero where nothing was measured
    uint32_t Window;    // index in Windows
    uint32_t Route;     // CensusRoute: 0 bitmap font, 1 scaled bitmap, 2 rendered font
    uint32_t Colour;    // the game's: components of 0x80 as one
    uint32_t Offset, Length; // its bytes in Text, as the game was given them
    uint32_t Phase;
    int16_t X, Y;       // where the game was told to print it, in its own units
};
struct MirrorQuad {     // a draw of the game's art: its texture, where it went and what part of it
    float Rect[4];      // normalized
    float UV[4];        // its texture's corners: left, top, right, bottom
    uint32_t Window, Texture, Colour, Phase; // Texture an IDirect3DBaseTexture8*, held until the next frame is published
};
struct MirrorWindow {
    char Name[16];
    uint32_t Flags;
    float Rect[4];      // the frame's bounds (else everything drawn), normalized
    float Cursor[4];    // the cursor's, where it drew one this frame (CursorFrame), normalized
    float Selection[4]; // the element the cursor is on: those drawn tinted
    float Scroll[4];    // the scrollbar's
    uint32_t CursorFrame, SelectionFrame, ScrollFrame;
    uint32_t ScrollPage, ScrollCount, ScrollTop; // the scrollbar's rows shown, rows, rows above, where read
    int16_t Target[4];  // the game's layout target (+8C): origin and size, its units
    uint32_t FirstRun, Runs, FirstQuad, Quads;
};
struct MirrorFrameData {
    uint32_t Frame, WindowCount, RunCount, QuadCount, TextUsed;
    MirrorWindow Windows[MIRROR_WINDOWS];
    MirrorRun Runs[MIRROR_RUNS];
    MirrorQuad Quads[MIRROR_QUADS];
    char Text[MIRROR_TEXT];
};
struct MirrorShared {
    char Magic[16]; uint32_t Version, Size, Frame, Supported;
    // Written by the addon: the windows to mirror (their 16-byte names, "menu    inventor"), each with
    // its bit in Hide set where the game's drawing of it is left undrawn, then RequestFrame (the
    // block's Frame) as the commit. Renewed every frame; MIRROR_REQUEST_FRAMES after the last, the
    // game draws them all again.
    volatile uint32_t RequestFrame, Hide[MIRROR_REQUESTS/32];
    char Requests[MIRROR_REQUESTS][16];
    // Written by uihook as each frame is presented: what the requested windows drew in it
    uint32_t Serial, Dropped; // Serial moves with each frame published; Dropped counts runs, quads or text that did not fit
    MirrorFrameData Published;
};

static_assert(sizeof(MirrorRun)==44 && sizeof(MirrorQuad)==48 && sizeof(MirrorWindow)==132,"mirror ABI");
static_assert(sizeof(MirrorFrameData)==82004 && sizeof(MirrorShared)==84112,"mirror ABI");

class Mirror {
    MirrorFrameData building{};
    // A reference to each texture of the last two frames published, and to each being gathered: an addon may
    // draw the last frame's quads after the next is published (Ashita gives Present to plugins in their order)
    std::vector<IDirect3DBaseTexture8*> held, heldBefore, heldBuilding;
    ChatBounds frameBounds, allBounds, cursorBounds, selectionBounds, scrollBounds, runBounds;
    D3DVIEWPORT8 viewport{}; bool viewportKnown=false;
    int window=-1;            // the slot of the window being drawn, or -1
    MirrorPhase phase=MIRROR_FRAME;
    unsigned depth=0;         // text calls under way
    bool elementLit=false;    // the element being drawn is tinted: the cursor is on it
    int run=-1;               // the run being measured
    uint32_t dropped=0;
public:
    MirrorShared* shared=nullptr;

    bool Wanted(const char* name,bool& hide) const {
        if (!shared || !shared->Supported) return false;
        const uint32_t request=shared->RequestFrame;
        if (!request || shared->Frame-request>MIRROR_REQUEST_FRAMES) return false;
        for (unsigned i=0;i<MIRROR_REQUESTS;i++)
            if (shared->Requests[i][0] && !memcmp(shared->Requests[i],name,16)) { hide=(shared->Hide[i/32]>>(i%32))&1; return true; }
        return false;
    }
    bool Active() const { return window>=0; }
    // Whether a texture named in the last frame published is still held, so may be read
    bool Holds(uint32_t texture) const {
        for (auto* t:held) if (static_cast<uint32_t>(reinterpret_cast<uintptr_t>(t))==texture) return true;
        return false;
    }
    // A window about to be drawn: mirrored if the addon asks for it. Returns whether the game's drawing
    // of it is to be left undrawn. The slot it had is given back by End.
    struct Saved { int window; MirrorPhase phase; unsigned depth; int run; ChatBounds frame, all, cursor, selection, scroll; };
    bool Begin(void* object,IDirect3DDevice8* device,Saved& saved) {
        saved={window,phase,depth,run,frameBounds,allBounds,cursorBounds,selectionBounds,scrollBounds};
        window=-1; phase=MIRROR_FRAME; depth=0; run=-1;
        auto* w=static_cast<uint8_t*>(object);
        char name[16]; uint8_t* header=nullptr; bool hide=false;
        if (!w || !ChatRead(w+CENSUS_HEADER,&header,4) || !header || !ChatRead(header+CENSUS_NAME,name,16) || !Wanted(name,hide)) return false;
        if (building.WindowCount>=MIRROR_WINDOWS) { dropped++; return false; }
        if (!viewportKnown && device) viewportKnown=SUCCEEDED(device->GetViewport(&viewport));
        if (!viewportKnown) { dropped++; return false; } // nothing could be placed: the game draws it
        window=int(building.WindowCount++);
        MirrorWindow& out=building.Windows[window];
        memset(&out,0,sizeof(out)); memcpy(out.Name,name,16);
        uint8_t flags[2]={};
        if (ChatRead(w+CENSUS_CURSOR,flags,2)) out.Flags|=(flags[0] ? MIRROR_HAS_CURSOR : 0) | (flags[1] ? MIRROR_FOCUSED : 0);
        if (hide) out.Flags|=MIRROR_HIDDEN;
        ChatRead(w+CENSUS_TARGET,out.Target,8);
        out.FirstRun=building.RunCount; out.FirstQuad=building.QuadCount;
        frameBounds=allBounds=cursorBounds=selectionBounds=scrollBounds=ChatBounds();
        return hide;
    }
    void End(const Saved& saved) {
        if (window>=0) {
            MirrorWindow& out=building.Windows[window];
            if (!Normalize(frameBounds.vertices ? frameBounds : allBounds,out.Rect)) memset(out.Rect,0,sizeof(out.Rect));
            // stamped with the frame being drawn, which the block's Frame is until it is presented
            const uint32_t frame=shared ? shared->Frame : 0;
            if (Normalize(cursorBounds,out.Cursor)) out.CursorFrame=frame;
            if (Normalize(selectionBounds,out.Selection)) out.SelectionFrame=frame;
            if (Normalize(scrollBounds,out.Scroll)) out.ScrollFrame=frame;
            out.Runs=building.RunCount-out.FirstRun; out.Quads=building.QuadCount-out.FirstQuad;
        }
        window=saved.window; phase=saved.phase; depth=saved.depth; run=saved.run;
        frameBounds=saved.frame; allBounds=saved.all; cursorBounds=saved.cursor; selectionBounds=saved.selection; scrollBounds=saved.scroll;
    }
    // The part of the window being drawn: the contents (from the stub), a control (from its call site)
    MirrorPhase Phase(MirrorPhase now) {
        const MirrorPhase was=phase;
        elementLit=false;
        if (window>=0) { phase=now; if (now==MIRROR_CONTENT) building.Windows[window].Flags|=MIRROR_DREW_CONTENT; }
        return was;
    }
    // One of the window's elements about to be drawn in the colour Window::Render gives it: 0x80808080 as it
    // is, 0x30808080 greyed, any other tint (0x80805020, 0x40402810) the one the cursor is on
    MirrorPhase Element(uint32_t colour) {
        const MirrorPhase was=Phase(MIRROR_ELEMENT);
        elementLit=window>=0 && (colour & 0xffffff)!=0x808080;
        return was;
    }
    void Scrollbar(const ChatScrollInfo& info) {
        if (window<0) return;
        MirrorWindow& out=building.Windows[window];
        out.ScrollPage=info.page; out.ScrollCount=info.count; out.ScrollTop=info.top;
    }
    // A text routine called: the outermost call in a mirrored window a run, its bytes up to the line's end
    void TextBegin(uint32_t route,int32_t x,int32_t y,const char* text,uint32_t colour) {
        if (window<0) return;
        if (depth++) return;
        if (building.RunCount>=MIRROR_RUNS || !text) { dropped++; return; }
        char bytes[MIRROR_RUN_BYTES]; uint32_t length=0;
        while (length<sizeof(bytes)) {
            char c=0;
            if (!ChatRead(text+length,&c,1) || !c || c=='\n' || c=='\r') break;
            bytes[length++]=c;
        }
        if (building.TextUsed+length>MIRROR_TEXT) { dropped++; return; }
        run=int(building.RunCount++);
        MirrorRun& out=building.Runs[run];
        memset(&out,0,sizeof(out));
        out.Window=uint32_t(window); out.Route=route; out.Colour=colour; out.Phase=phase;
        out.X=int16_t(x); out.Y=int16_t(y);
        out.Offset=building.TextUsed; out.Length=length;
        memcpy(building.Text+building.TextUsed,bytes,length); building.TextUsed+=length;
        runBounds=ChatBounds();
    }
    void TextEnd() {
        if (window<0 || !depth) return;
        if (--depth) return;
        if (run>=0 && !Normalize(runBounds,building.Runs[run].Rect)) memset(building.Runs[run].Rect,0,sizeof(building.Runs[run].Rect));
        run=-1;
    }
    // The viewport the window is drawn in, where no device says (the fixtures)
    void Viewport(const D3DVIEWPORT8& given) { viewport=given; viewportKnown=given.Width && given.Height; }
    // A draw in a mirrored window, measured whether or not it is then left undrawn
    void Draw(IDirect3DDevice8* device,bool up,const void* data,UINT stride,UINT count) {
        if (window<0 || !up || !data || !device || stride<8 || !count) return;
        DWORD fvf=0;
        if (FAILED(device->GetVertexShader(&fvf)) || (fvf & D3DFVF_POSITION_MASK)!=D3DFVF_XYZRHW) return;
        IDirect3DBaseTexture8* bound=nullptr;
        if ((phase==MIRROR_CONTENT || phase==MIRROR_ELEMENT) && !depth && FAILED(device->GetTexture(0,&bound))) bound=nullptr;
        Record(fvf,bound,data,stride,count);
    }
    // The draw's vertices, as the device has them: screen-space positions first, then the diffuse colour and
    // the first texture's corners where the vertex format has them. bound is a reference to the texture
    // given over (held, or given back here), or null.
    void Record(DWORD fvf,IDirect3DBaseTexture8* bound,const void* data,UINT stride,UINT count) {
        struct Hold { IDirect3DBaseTexture8*& texture; ~Hold() { if (texture) texture->Release(); } } hold{bound};
        if (window<0 || !data || stride<8 || !count || (fvf & D3DFVF_POSITION_MASK)!=D3DFVF_XYZRHW) return;
        ChatBounds bounds,uv;
        const UINT diffuse=(fvf & D3DFVF_DIFFUSE) ? 16 : 0;
        UINT texture=16+((fvf & D3DFVF_DIFFUSE) ? 4 : 0)+((fvf & D3DFVF_SPECULAR) ? 4 : 0);
        const bool textured=((fvf & D3DFVF_TEXCOUNT_MASK)>>D3DFVF_TEXCOUNT_SHIFT)>=1 && texture+8<=stride;
        auto* bytes=static_cast<const uint8_t*>(data);
        for (UINT i=0;i<count && i<4096;i++) {
            float v[2]; memcpy(v,bytes+size_t(i)*stride,sizeof(v));
            if (!std::isfinite(v[0]) || !std::isfinite(v[1])) continue;
            bounds.Add(v[0],v[1]);
            if (textured) { float t[2]; memcpy(t,bytes+size_t(i)*stride+texture,sizeof(t)); if (std::isfinite(t[0]) && std::isfinite(t[1])) uv.Add(t[0],t[1]); }
        }
        if (!bounds.vertices) return;
        Merge(allBounds,bounds);
        if (depth) { Merge(runBounds,bounds); return; }
        switch (phase) {
        case MIRROR_FRAME: Merge(frameBounds,bounds); return;
        case MIRROR_CURSOR: Merge(cursorBounds,bounds); return;
        case MIRROR_ELEMENT: if (elementLit) Merge(selectionBounds,bounds); break;
        case MIRROR_SCROLL: Merge(scrollBounds,bounds); return;
        case MIRROR_AFTER: return;
        case MIRROR_CONTENT: break;
        }
        // the contents' own art, or an element: a quad of a texture
        if (building.QuadCount>=MIRROR_QUADS) { dropped++; return; }
        MirrorQuad& out=building.Quads[building.QuadCount];
        memset(&out,0,sizeof(out));
        if (!Normalize(bounds,out.Rect)) return;
        out.Window=uint32_t(window); out.Phase=phase;
        if (uv.vertices) { out.UV[0]=uv.left; out.UV[1]=uv.top; out.UV[2]=uv.right; out.UV[3]=uv.bottom; }
        if (diffuse && stride>=diffuse+4) memcpy(&out.Colour,bytes+diffuse,4);
        if (bound) {
            // one reference kept for each texture, given back once a later frame is published
            out.Texture=static_cast<uint32_t>(reinterpret_cast<uintptr_t>(bound));
            if (std::find(heldBuilding.begin(),heldBuilding.end(),bound)==heldBuilding.end()) { heldBuilding.push_back(bound); bound=nullptr; }
        }
        building.QuadCount++;
    }
    // At Present: what was gathered this frame published whole, the textures it names held in place of
    // the last frame's, and a new frame begun
    void Publish(uint32_t frame) {
        if (shared) {
            const bool any=building.WindowCount || shared->Published.WindowCount;
            if (any) {
                MirrorFrameData& out=shared->Published;
                out.Frame=building.WindowCount ? frame : 0;
                out.WindowCount=building.WindowCount; out.RunCount=building.RunCount; out.QuadCount=building.QuadCount; out.TextUsed=building.TextUsed;
                memcpy(out.Windows,building.Windows,sizeof(MirrorWindow)*building.WindowCount);
                memcpy(out.Runs,building.Runs,sizeof(MirrorRun)*building.RunCount);
                memcpy(out.Quads,building.Quads,sizeof(MirrorQuad)*building.QuadCount);
                memcpy(out.Text,building.Text,building.TextUsed);
                shared->Serial++;
            }
            shared->Dropped+=dropped;
        }
        for (auto* texture:heldBefore) texture->Release();
        heldBefore.swap(held); held.swap(heldBuilding); heldBuilding.clear();
        building.WindowCount=building.RunCount=building.QuadCount=building.TextUsed=0;
        dropped=0; viewportKnown=false; window=-1; depth=0; run=-1; phase=MIRROR_FRAME;
    }
    // Every texture given back and nothing published: on release, or a device going away
    void Clear() {
        for (auto* list:{&held,&heldBefore,&heldBuilding}) { for (auto* texture:*list) texture->Release(); list->clear(); }
        building.WindowCount=building.RunCount=building.QuadCount=building.TextUsed=0;
        if (shared) { shared->Published.WindowCount=shared->Published.RunCount=shared->Published.QuadCount=shared->Published.TextUsed=0; shared->Published.Frame=0; shared->Serial++; }
        window=-1; depth=0; run=-1;
    }
private:
    static void Merge(ChatBounds& into,const ChatBounds& from) {
        if (!from.vertices) return;
        into.Add(from.left,from.top); into.Add(from.right,from.bottom); into.vertices+=from.vertices-2;
    }
    bool Normalize(const ChatBounds& from,float out[4]) const {
        return viewportKnown && ChatNormalize(from,float(viewport.X),float(viewport.Y),float(viewport.Width),float(viewport.Height),out);
    }
};
