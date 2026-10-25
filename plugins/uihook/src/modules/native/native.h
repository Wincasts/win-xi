// The native look: the game's own windows drawn moved and scaled, the game's own menu kept whole (its controller
// input, cursor and text its own). nativeui gives it its settings.
//
//   /uihook native                         what is set, and how much of each was drawn so
//   /uihook native group <x> <y> | off     every window the game stacks above the chat log moved together
//   /uihook native size <factor>           every framed window drawn larger or smaller, from its quarter's corner of
//                                          the screen (the bar from its ends, the group from the chat log's top left)
//   /uihook native inset <pixels> | 0      the sides brought in: each window on the left half of the screen drawn
//                                          that far right, each on the right half that far left, the bar across
//                                          the top (one wider than half the screen, over its middle) that much
//                                          shorter at each end; one over the middle and narrower left as it is,
//                                          as are the chat log and the windows stacked on it (the group's)
//   /uihook native frames <fill> <border> <rounding> <thickness> | off
//                                          the group's frames (the game's corners, edges and striped background)
//                                          left undrawn, a panel drawn in their place: filled and bordered in the
//                                          colours given (AARRGGBB), its corners rounded so many pixels, its border
//                                          so thick. Its words, pictures, cursor and buttons are the game's own.
//
// The group: the windows the game places in the bottom left over its chat log (the command menu, a shop's buy and
// sell, a yes or no, an item's description...), told by where the game draws them (+3A, as left, top, width,
// height): its bottom on the chat log's top (within a few), its left no further right than the log's left and 150.
// Not by the layout target (+8C), which for some is over the log while they are drawn elsewhere (1.38 moved the
// Master and Automaton menu, beside the main menu, so). Told again each frame, as
// one window can be placed there or elsewhere (the main menu is on the right, the command menu of the same name
// over the log). Each gets an entry of its own while it is one.
//
// Only the drawing moves: every screen-space draw made while the window is drawn (its frame, elements, contents,
// text, cursor and scrollbar alike) is copied, moved and drawn in its place, so the window moves whole without
// knowing where any of its parts keep their places; a draw wholly outside the window's frame (the inventory's count,
// drawn up in the menu name's bar) is left where the game put it, and the frame is what it is grown from. The game's own places are left as they are, so its mouse
// hit-tests stay where the game put the menu; the controller works it as ever. A draw from a vertex buffer cannot
// be moved, and is counted.
//
#pragma once
#include <stdint.h>
#include <string.h>
#include <cmath>
#include <algorithm>
#include <vector>
#include "../window/window.h"

#define NATIVE_ENTRIES 128
#define NATIVE_GROUP_REACH 150   // how far right of the log's left a window of the group may start, in its units
#define NATIVE_GROUP_SLACK 8     // how far above the log's top its bottom may be
#define NATIVE_BAR_REACH 48       // how far in from an end of the bar, past the inset, what it shows goes with that end
#define NATIVE_BAR_HEIGHT 80      // the tallest frame the inset takes for the bar across the top, in pixels
#define NATIVE_GROUP_STALE 600   // frames an entry of the group goes undrawn before its place is given to another
#define NATIVE_SCALE_LOW 0.5f
#define NATIVE_SCALE_HIGH 3.0f
#define NATIVE_MOUSE_FRAMES 2    // a window drawn this many frames ago or since is under the mouse where it was drawn

// The frame's art, as the texture census names it: its corners, its top and bottom, its sides, its striped background
static const uint32_t NativeFrameHashes[4]={0x72D3D795u,0x3C8984C5u,0x1023C0C5u,0x92C145C5u};
static bool NativeFrameHash(uint32_t hash) { for (uint32_t h:NativeFrameHashes) if (h==hash) return true; return false; }

// A panel drawn in place of a frame (/uihook native frames): a vertex as the game's interface's are (screen-space, a
// colour, a texture place, unused), and how it looks
struct NativePanelVertex { float x,y,z,rhw; uint32_t colour; float u,v; };
struct NativePanelStyle { uint32_t fill=0,border=0; float rounding=0,thickness=1; };
// A rectangle's outline (left, top, right, bottom) with its corners rounded radius, each corner segments+1 points,
// clockwise from the top left's
static void NativeOutline(float l,float t,float r,float b,float radius,unsigned segments,std::vector<float>& out) {
    out.clear();
    radius=(std::max)(0.0f,(std::min)(radius,(std::min)(r-l,b-t)/2));
    const float cx[4]={l+radius,r-radius,r-radius,l+radius},cy[4]={t+radius,t+radius,b-radius,b-radius};
    for (unsigned c=0;c<4;c++) for (unsigned i=0;i<=segments;i++) {
        const float a=3.14159265f*(1.0f+0.5f*float(c)+(segments ? 0.5f*float(i)/float(segments) : 0.0f));
        out.push_back(cx[c]+cosf(a)*radius); out.push_back(cy[c]+sinf(a)*radius);
    }
}
// The panel over rect (pixels: left, top, right, bottom) as triangles: its fill, then its border inside its edge
static void NativePanel(const float* rect,const NativePanelStyle& s,std::vector<NativePanelVertex>& out) {
    out.clear();
    const float l=rect[0],t=rect[1],r=rect[2],b=rect[3];
    if (!(r>l && b>t)) return;
    const unsigned segments=s.rounding>0 ? unsigned(s.rounding/2)+2 : 0;
    std::vector<float> outer,inner;
    NativeOutline(l,t,r,b,s.rounding,segments,outer);
    const size_t n=outer.size()/2;
    // a place given as the device has it: a pixel's middle at its .5
    auto vertex=[&](float x,float y,uint32_t colour) { out.push_back({x-0.5f,y-0.5f,0,1,colour,0,0}); };
    if (s.fill>>24) {
        const float mx=(l+r)/2,my=(t+b)/2;
        for (size_t i=0;i<n;i++) {
            const size_t j=(i+1)%n;
            vertex(mx,my,s.fill); vertex(outer[2*i],outer[2*i+1],s.fill); vertex(outer[2*j],outer[2*j+1],s.fill);
        }
    }
    const float k=(std::min)(s.thickness,(std::min)(r-l,b-t)/2);
    if ((s.border>>24) && k>0) {
        NativeOutline(l+k,t+k,r-k,b-k,(std::max)(0.0f,s.rounding-k),segments,inner);
        for (size_t i=0;i<n;i++) {
            const size_t j=(i+1)%n;
            vertex(outer[2*i],outer[2*i+1],s.border); vertex(outer[2*j],outer[2*j+1],s.border); vertex(inner[2*j],inner[2*j+1],s.border);
            vertex(outer[2*i],outer[2*i+1],s.border); vertex(inner[2*j],inner[2*j+1],s.border); vertex(inner[2*i],inner[2*i+1],s.border);
        }
    }
}

// Where a window's draws go: grown by scale about the corner of the display its bounds are nearest, then moved by
// dx, dy, kept on the display. out: the corner (ax, ay) and the move kept (dx, dy). False with no bounds.
static bool NativePlace(const float* bounds,float dx,float dy,float scale,float width,float height,float* out) {
    if (!(bounds[2]>bounds[0] && bounds[3]>bounds[1]) || width<=0 || height<=0) return false;
    const float ax=(bounds[0]+bounds[2])/2<width/2 ? bounds[0] : bounds[2];
    const float ay=(bounds[1]+bounds[3])/2<height/2 ? bounds[1] : bounds[3];
    const float left=ax+(bounds[0]-ax)*scale,top=ay+(bounds[1]-ay)*scale;
    const float right=ax+(bounds[2]-ax)*scale,bottom=ay+(bounds[3]-ay)*scale;
    // kept on the display where it fits; one larger than the display kept at its top left
    dx=(std::max)(-left,(std::min)(width-right,dx));
    dy=(std::max)(-top,(std::min)(height-bottom,dy));
    out[0]=ax; out[1]=ay; out[2]=dx; out[3]=dy;
    return true;
}

// A window's draws as moved: x' = ax + (x - ax) * k + dx, and y likewise; for the bar across the top, ax and dx by
// each vertex's side of the middle (0 and +inset left of it, width and -inset right)
struct NativeTransform {
    float ax=0,ay=0,k=1,dx=0,dy=0;
    bool pinch=false; float middle=0,width=0,inset=0;
    void Apply(float& x,float& y) const {
        if (pinch) { const bool left=x<middle; const float a=left ? 0 : width; x=a+(x-a)*k+(left ? inset : -inset); }
        else x=ax+(x-ax)*k+dx;
        y=ay+(y-ay)*k+dy;
    }
    // A place as drawn given back as the game's own: Apply undone (for the bar, by the side of the middle it is drawn on)
    void Invert(float& x,float& y) const {
        if (k<=0) return;
        if (pinch) { const bool left=x<middle; const float a=left ? 0 : width; x=a+(x-(left ? inset : -inset)-a)/k; }
        else x=ax+(x-dx-ax)/k;
        y=ay+(y-dy-ay)/k;
    }
};
// Where a mouse message goes (NativeLook::MapPoint)
enum NativeMouse { NATIVE_MOUSE_AS_IS, NATIVE_MOUSE_MOVED, NATIVE_MOUSE_KEPT };
static void NativeTransformVertices(void* data,unsigned count,unsigned stride,const NativeTransform& t) {
    auto* bytes=static_cast<uint8_t*>(data);
    for (unsigned i=0;i<count;i++) {
        float v[2]; memcpy(v,bytes+size_t(i)*stride,sizeof(v));
        t.Apply(v[0],v[1]);
        memcpy(bytes+size_t(i)*stride,v,sizeof(v));
    }
}

struct NativeEntry {
    char name[16]={};
    bool group=false,member=false;   // made for the group; and, this frame, one of it
    bool noInset=false;              // the chat log's: never brought in
    // the bar across the top: whether it drew something over its middle (what the game centres while loading, its
    // progress line) this frame, and the frame before, which says how what it shows is moved
    bool barSpanning=false,barCentred=false;
    float dx=0,dy=0;
    // the window's draws' bounds as the game made them, in display pixels: those of the frame being drawn, and the
    // last whole frame's, which each frame's draws are placed by
    float gather[4]={}; uint32_t gatherFrame=0; bool gathered=false;
    float bounds[4]={}; bool known=false;
    // the same of its frame's draws alone: what it is placed by, and what a draw must touch to be moved
    float frameGather[4]={}; bool frameGathered=false;
    float frame[4]={}; bool frameKnown=false;
    uint32_t panelFrame=0;  // the frame its panel was last drawn in (/uihook native frames)
    uint32_t order=0;  // its place among the windows drawn in the frame it was last drawn, for the mouse: the last on top
    // for /uihook native
    uint32_t seen=0,moved=0,unmoved=0,kept=0;
};

class NativeLook {
public:
    NativeEntry entries[NATIVE_ENTRIES];
    // the window being drawn, where it is one named: its entry, its part (frame, contents...), whether a text
    // routine is under way
    NativeEntry* current=nullptr;
    WindowPhase phase=PHASE_FRAME;
    unsigned text=0;
    // the group above the chat log, and the log's layout target as last drawn (its left and top), 0 frame unknown
    bool groupOn=false; float groupX=0,groupY=0;
    // /uihook native frames: the group's frames drawn as panels of this look. The group is told while either is on.
    bool framesOn=false; NativePanelStyle panelStyle;
    bool mirrorOn=false;   // an addon draws the group itself (mirror.h), asked again each frame
    float inset=0;   // the sides brought in by this many pixels, 0 not
    float menuScale=1;   // every framed window drawn this much larger, from its quarter's corner of the screen
    int16_t logLeft=0,logTop=0; uint32_t logFrame=0;
    uint32_t orderFrame=0,orderNext=0;  // the windows drawn so far this frame, for each one's order

    // The chat log's windows: never of the group, never brought in (chatbox places the log)
    static bool LogWindow(const char* name) {
        return !memcmp(name+8,"logwindo",8) || !memcmp(name+8,"logwin2 ",8) || !memcmp(name+8,"fulllog ",8) || !memcmp(name+8,"inline  ",8);
    }
    // An entry for a window as it is drawn: a new one, or the place of one long undrawn
    NativeEntry* Make(const char* name,uint32_t frame) {
        NativeEntry* e=Find(name,true);
        if (!e) for (auto& x:entries) if (frame-x.seen>NATIVE_GROUP_STALE && &x!=current) { x=NativeEntry(); memcpy(x.name,name,16); e=&x; break; }
        if (e) e->noInset=LogWindow(name);
        return e;
    }
    bool Inset(float pixels) { inset=pixels>0 ? pixels : 0; return true; }
    bool MenuScale(float k) { if (!(k>=NATIVE_SCALE_LOW && k<=NATIVE_SCALE_HIGH)) return false; menuScale=k; return true; }
    // Whether a window of this name and place (left, top, width, height) is one of the group: its bottom on the log's
    // top, its left near the log's. Or, given its layout target (the same), one drawn within a target that is so: a
    // window opening, grown or slid into its place over some frames.
    bool GroupMember(const char* name,const int16_t* place,const int16_t* target=nullptr) const {
        if (!Grouping() || !logFrame || !place || place[2]<=0 || place[3]<=0) return false;
        if (LogWindow(name)) return false;
        auto over=[&](const int16_t* r) {
            const int bottom=r[1]+r[3];
            return r[2]>0 && r[3]>0 && bottom<=logTop && bottom>=logTop-NATIVE_GROUP_SLACK && r[0]>=0 && r[0]<=logLeft+NATIVE_GROUP_REACH;
        };
        if (over(place)) return true;
        const int slack=NATIVE_GROUP_SLACK;
        return target && over(target) && place[0]>=target[0]-slack && place[1]>=target[1]-slack
            && place[0]+place[2]<=target[0]+target[2]+slack && place[1]+place[3]<=target[1]+target[3]+slack;
    }
    bool Group(float x,float y) {
        groupOn=true; groupX=x; groupY=y;
        for (auto& e:entries) if (e.group) { e.dx=x; e.dy=y; }
        return true;
    }
    bool Grouping() const { return groupOn || framesOn || mirrorOn; }
    // The window being drawn one of the group this frame
    bool Member() const { return current && current->group && current->member; }
    // The group's move undone; its entries let go unless its frames are still drawn as panels
    unsigned GroupOff() {
        groupOn=false; groupX=groupY=0;
        if (framesOn) { unsigned n=0; for (auto& e:entries) if (e.name[0] && e.group) { e.dx=e.dy=0; n++; } return n; }
        return ForgetGroup();
    }
    void Frames(const NativePanelStyle& style) { framesOn=true; panelStyle=style; }
    unsigned FramesOff() { framesOn=false; return groupOn ? 0 : ForgetGroup(); }
    unsigned ForgetGroup() {
        unsigned n=0;
        for (auto& e:entries) if (e.name[0] && e.group) {
            n++;
            if (&e==current) current=nullptr;
            e=NativeEntry();
        }
        return n;
    }
    // The window about to be drawn, by its name as the game keeps it and where it is drawn: the log's noted, and
    // one of the group given its entry (made, or one long undrawn taken for it)
    void Note(const char* name,const int16_t* place,uint32_t frame,const int16_t* target=nullptr) {
        if (!name || !place) return;
        if (!memcmp(name,"menu    logwindo",16)) { logLeft=place[0]; logTop=place[1]; logFrame=frame; return; }
        NativeEntry* e=Find(name,false);
        const bool member=GroupMember(name,place,target);
        // one that was not of the group (made for the inset before the log was seen) and is one now: the group's offset
        if (e && member && !e->group) { e->group=true; e->dx=groupX; e->dy=groupY; }
        if (e) { e->member=member; return; }
        if (!member) return;
        e=Make(name,frame);
        if (!e) return;
        e->group=true; e->member=true; e->dx=groupX; e->dy=groupY;
    }

    NativeEntry* Find(const char* name,bool add) {
        for (auto& e:entries) if (e.name[0] && !memcmp(e.name,name,16)) return &e;
        if (!add) return nullptr;
        for (auto& e:entries) if (!e.name[0]) { e=NativeEntry(); memcpy(e.name,name,16); return &e; }
        return nullptr;
    }
    bool Any() const { if (Grouping() || inset>0 || menuScale!=1) return true; for (auto& e:entries) if (e.name[0]) return true; return false; }

    // The window being drawn: its entry, if it is one named. Its draws' bounds from the frame before become the ones
    // it is placed by. Returns what to give back after it.
    struct Saved { NativeEntry* current; WindowPhase phase; unsigned text; };
    // drawn: where the game draws the window this frame (+3A, in pixels: left, top, right, bottom), or null. A window
    // drawn for the first time (or the first since its entry was given to another) is placed by it at once: placed
    // by its draws of the frame before alone, it showed for a frame where the game put it, then moved.
    Saved Enter(const char* name,uint32_t frame,const float* drawn=nullptr) {
        Saved saved={current,phase,text};
        current=nullptr; phase=PHASE_FRAME; text=0;
        NativeEntry* e=name ? Find(name,false) : nullptr;
        if (!e && name && (inset>0 || menuScale!=1)) e=Make(name,frame);
        if (e) {
            e->seen=frame;
            if (orderFrame!=frame) { orderFrame=frame; orderNext=0; }
            e->order=++orderNext;
            if (e->gatherFrame!=frame) {
                // drawn the frame before: its frame is what it drew as one, none where it drew none (a guess from
                // the game's place, below, is not kept for a window with no frame of its own)
                if (e->gathered) { memcpy(e->bounds,e->gather,sizeof(e->bounds)); e->known=true; e->frameKnown=false; }
                if (e->frameGathered) { memcpy(e->frame,e->frameGather,sizeof(e->frame)); e->frameKnown=true; }
                if (!e->known && drawn && drawn[2]>drawn[0] && drawn[3]>drawn[1]) {
                    memcpy(e->bounds,drawn,sizeof(e->bounds)); memcpy(e->frame,drawn,sizeof(e->frame));
                    e->known=e->frameKnown=true;
                }
                e->gathered=e->frameGathered=false; e->gatherFrame=frame;
                e->barCentred=e->barSpanning; e->barSpanning=false;
            }
            current=e;
        }
        return saved;
    }
    void Leave(const Saved& saved) { current=saved.current; phase=saved.phase; text=saved.text; }
    WindowPhase Phase(WindowPhase now) { const WindowPhase was=phase; phase=now; return was; }
    // A draw's vertices' places as bounds; false where none is finite
    static bool Bounds(const void* data,unsigned count,unsigned stride,float* out) {
        if (!data || stride<8) return false;
        const auto* bytes=static_cast<const uint8_t*>(data);
        bool any=false;
        for (unsigned i=0;i<count;i++) {
            float v[2]; memcpy(v,bytes+size_t(i)*stride,sizeof(v));
            if (!std::isfinite(v[0]) || !std::isfinite(v[1])) continue;
            if (!any) { out[0]=out[2]=v[0]; out[1]=out[3]=v[1]; any=true; continue; }
            out[0]=(std::min)(out[0],v[0]); out[1]=(std::min)(out[1],v[1]);
            out[2]=(std::max)(out[2],v[0]); out[3]=(std::max)(out[3],v[1]);
        }
        return any;
    }
    static void Grow(float* into,bool& any,const float* by) {
        if (!any) { memcpy(into,by,4*sizeof(float)); any=true; return; }
        into[0]=(std::min)(into[0],by[0]); into[1]=(std::min)(into[1],by[1]);
        into[2]=(std::max)(into[2],by[2]); into[3]=(std::max)(into[3],by[3]);
    }
    // A screen-space draw of the window: its vertices' places counted into its bounds, and its frame's if it is the frame
    void Gather(const void* data,unsigned count,unsigned stride) {
        float b[4];
        if (!current || !Bounds(data,count,stride,b)) return;
        Grow(current->gather,current->gathered,b);
        if (phase==PHASE_FRAME && !text) Grow(current->frameGather,current->frameGathered,b);
    }
    // Whether a draw touches the window's frame (as last drawn), so moves with it; every draw does until it is known
    bool Within(const void* data,unsigned count,unsigned stride) const {
        if (!current || !current->frameKnown) return true;
        float b[4];
        if (!Bounds(data,count,stride,b)) return true;
        const float* f=current->frame;
        return b[2]>=f[0] && b[0]<=f[2] && b[3]>=f[1] && b[1]<=f[3];
    }
    // How the window's draws are moved: false while they are not (or its bounds are not known yet).
    //  - one of the group over the chat log: the group's offset, scaled by the menu scale from the log's top left
    //  - one with a frame of its own (not the chat log): scaled by the menu scale from its quarter's corner of the
    //    screen (one over the middle from the middle), brought in by the inset; the bar across the top (short, over
    //    the middle, wider than half the screen) each vertex by its side, so its ends stay with their neighbours
    //  - any other (one without a frame, the target's arrow over the world): as the game draws it
    // whole: moved with the screen, not alone, so its draws all go with it (none kept back for lying outside its
    // frame: the main menu's arrows beside it)
    bool Transform(float width,float height,NativeTransform& t,bool* whole=nullptr) const {
        t=NativeTransform();
        if (whole) *whole=false;
        return current && TransformOf(*current,width,height,t,whole);
    }
    // The same for any window's entry
    bool TransformOf(const NativeEntry& e,float width,float height,NativeTransform& t,bool* whole=nullptr) const {
        t=NativeTransform();
        if (whole) *whole=false;
        if (!e.known) return false;
        const float* bounds=e.frameKnown ? e.frame : e.bounds;
        // one made for the group, placed elsewhere this frame: as any other
        const bool grouped=e.group && e.member,away=e.group && !e.member;
        const float dx=away ? 0 : e.dx,dy=away ? 0 : e.dy;
        const bool framed=e.frameKnown && e.frame[2]>e.frame[0] && e.frame[3]>e.frame[1];
        const bool screen=!grouped && !e.noInset && framed;
        if (grouped) {
            t.k=menuScale; t.ax=float(logLeft); t.ay=float(logTop); t.dx=dx; t.dy=dy;
        } else if (screen && (inset>0 || menuScale!=1)) {
            const float* f=e.frame; const float middle=width/2;
            t.k=menuScale; t.dx=dx; t.dy=dy;
            t.ay=(f[1]+f[3])/2<height/2 ? 0 : height;
            if (f[2]<=middle) { t.ax=0; t.dx+=inset; }
            else if (f[0]>=middle) { t.ax=width; t.dx-=inset; }
            else if (f[2]-f[0]>width/2 && f[3]-f[1]<=NATIVE_BAR_HEIGHT) { t.pinch=true; t.middle=middle; t.width=width; t.inset=inset; }
            else t.ax=middle;
            if (whole) *whole=dx==0 && dy==0;
        } else { t.dx=dx; t.dy=dy; }
        if (t.k==1 && !t.pinch) {
            if (t.dx==0 && t.dy==0) return false;
            // a move alone kept on the screen, as ever
            float p[4];
            if (!NativePlace(bounds,t.dx,t.dy,1,width,height,p)) return false;
            t.ax=p[0]; t.ay=p[1]; t.dx=p[2]; t.dy=p[3];
        }
        return true;
    }
    // A draw on the bar across the top that is not its frame (what the bar shows), moved for the whole bar alike: its
    // help text is drawn a letter or a few at a time, and each moved by where it lay (1.50) slid the sentence's start
    // over its end. What is at its right end (its title) goes with that end; the rest with its left end, but while
    // the bar shows something over its middle (the frame before: the loading screen's progress line, with
    // "Downloading data..." centred by it) it stays in the middle with the bar, but what is near the left end.
    bool OnBar(const void* data,unsigned count,unsigned stride,NativeTransform& t) {
        if (!t.pinch || !current || (phase==PHASE_FRAME && !text) || !current->frameKnown) return false;
        float b[4];
        if (!Bounds(data,count,stride,b)) return false;
        const float* f=current->frame;
        const float reach=t.inset+NATIVE_BAR_REACH;
        if (b[0]<t.middle && b[2]>t.middle) current->barSpanning=true;
        t.pinch=false;
        if (b[0]>=t.middle && b[2]>f[2]-reach) { t.ax=t.width; t.dx=-t.inset; }
        else if (!current->barCentred || b[0]<f[0]+reach) { t.ax=0; t.dx=t.inset; }
        else { t.ax=t.middle; t.dx=0; }
        return true;
    }
    // The scale the window being drawn is drawn at (as Transform gives it), for a skin's picture of the size to suit
    float ScaleNow() const {
        if (!current || !current->known) return 1;
        const NativeEntry& e=*current;
        if (e.group && e.member) return menuScale;
        const bool framed=e.frameKnown && e.frame[2]>e.frame[0] && e.frame[3]>e.frame[1];
        return !e.noInset && framed ? menuScale : 1;
    }
    // As Transform, in the terms the checks were written in: place as NativePlace gives it (corner, move), pinch the
    // bar's middle or -1
    bool Placing(float width,float height,float* place,float* pinch=nullptr,bool* whole=nullptr) const {
        NativeTransform t;
        if (pinch) *pinch=-1;
        if (!Transform(width,height,t,whole)) return false;
        place[0]=t.ax; place[1]=t.ay; place[2]=t.dx; place[3]=t.dy;
        if (pinch && t.pinch) *pinch=t.middle;
        return true;
    }
    // A place on the screen (in pixels, as the draws are) for the game's mouse. On a window drawn in the last few
    // frames (the last drawn on top) that is drawn moved: moved to the same place on the game's own (MOVED). On none
    // drawn there but where the game puts one drawn moved: kept from the game, which would work that window where it
    // is not seen (KEPT). Otherwise left as it is (AS_IS).
    NativeMouse MapPoint(float width,float height,uint32_t frame,float& x,float& y) const {
        const NativeEntry* top=nullptr; NativeTransform topMove; bool topMoved=false;
        bool under=false;
        for (auto& e:entries) {
            if (!e.name[0] || !e.known || frame-e.seen>NATIVE_MOUSE_FRAMES) continue;
            const float* f=e.frameKnown ? e.frame : e.bounds;
            NativeTransform t;
            const bool moved=TransformOf(e,width,height,t);
            float drawn[4]={f[0],f[1],f[2],f[3]};
            if (moved) { t.Apply(drawn[0],drawn[1]); t.Apply(drawn[2],drawn[3]); }
            if (moved && x>=f[0] && x<f[2] && y>=f[1] && y<f[3]) under=true;
            if (x<drawn[0] || x>=drawn[2] || y<drawn[1] || y>=drawn[3]) continue;
            if (top && (e.seen<top->seen || (e.seen==top->seen && e.order<top->order))) continue;
            top=&e; topMove=t; topMoved=moved;
        }
        if (top) {
            if (!topMoved) return NATIVE_MOUSE_AS_IS;
            topMove.Invert(x,y);
            return NATIVE_MOUSE_MOVED;
        }
        return under ? NATIVE_MOUSE_KEPT : NATIVE_MOUSE_AS_IS;
    }
    // Whether a draw of the window being drawn may be its frame's art, to be left undrawn for its panel: frames on, the
    // window of the group now, the draw its frame's and not text (its elements, the command menu's pictured words
    // among them, are drawn in the frame too: the draw's texture says which)
    bool FrameDraw() const { return framesOn && current && current->group && current->member && phase==PHASE_FRAME && !text; }
    // The window being drawn's panel, once a frame: where (its frame as last drawn, moved as its draws are), in pixels;
    // false where it is drawn already this frame or its frame is not known
    bool PanelDue(float width,float height,uint32_t frame,float* rect) {
        if (!current || current->panelFrame==frame || !current->frameKnown) return false;
        current->panelFrame=frame;
        memcpy(rect,current->frame,4*sizeof(float));
        NativeTransform t;
        if (TransformOf(*current,width,height,t)) { t.Apply(rect[0],rect[1]); t.Apply(rect[2],rect[3]); }
        return rect[2]>rect[0] && rect[3]>rect[1];
    }
    // A draw of a window moved that could not be (from a vertex buffer)
    void Unmoved() { if (current) current->unmoved++; }
};
