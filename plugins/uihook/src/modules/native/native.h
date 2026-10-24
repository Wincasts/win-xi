// The native look, an experiment: a window of the game's, named, drawn moved, scaled and with its frame tinted,
// the game's own menu kept whole (its controller input, cursor and text its own). For trying a skin on the real
// menus rather than drawing them again (the mirror).
//
//   /uihook native                         what is set, and how much of each was drawn so
//   /uihook native move <name> <x> <y>     the window drawn x, y display pixels from where the game puts it
//   /uihook native scale <name> <factor>   drawn larger or smaller, grown from the corner of the screen it is nearest
//   /uihook native tint <name> <AARRGGBB>  its frame's draws multiplied by this colour (0xFF808080 halves it)
//   /uihook native clear [name]            one, or all, as the game draws them
//   /uihook native group <x> <y> | off     every window the game stacks above the chat log moved together
//   /uihook native size <factor>           every framed window drawn larger or smaller, from its quarter's corner of
//                                          the screen (the bar from its ends, the group from the chat log's top left)
//   /uihook native inset <pixels> | 0      the sides brought in: each window on the left half of the screen drawn
//                                          that far right, each on the right half that far left, the bar across
//                                          the top (one wider than half the screen, over its middle) that much
//                                          shorter at each end; one over the middle and narrower left as it is,
//                                          as are the chat log and the windows stacked on it (the group's)
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
// The tint is a second texture stage after the game's own, multiplying what it made by the colour (the texture
// factor), for the frame's draws alone. The game's frames are the texture times twice the vertex colour (stage 5
// 2 1), so the vertices' colours would do as well; the stage leaves them as they are.
#pragma once
#include <stdint.h>
#include <string.h>
#include <cmath>
#include <algorithm>
#include "../mirror/mirror.h"

#define NATIVE_ENTRIES 128
#define NATIVE_GROUP_REACH 150   // how far right of the log's left a window of the group may start, in its units
#define NATIVE_GROUP_SLACK 8     // how far above the log's top its bottom may be
#define NATIVE_BAR_REACH 48       // how far in from an end of the bar, past the inset, what it shows goes with that end
#define NATIVE_BAR_HEIGHT 80      // the tallest frame the inset takes for the bar across the top, in pixels
#define NATIVE_GROUP_STALE 600   // frames an entry of the group goes undrawn before its place is given to another
#define NATIVE_SCALE_LOW 0.5f
#define NATIVE_SCALE_HIGH 3.0f

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
// A window's name as the game keeps it: "menu    " and the name, spaces to sixteen
static bool NativeName(const char* name,char* out) {
    const size_t length=name ? strlen(name) : 0;
    if (!length || length>8) return false;
    memcpy(out,"menu            ",16); memcpy(out+8,name,length);
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
};
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
    bool place=false,tint=false;
    bool group=false,member=false;   // made for the group; and, this frame, one of it
    bool automatic=false,noInset=false;
    // the bar across the top: whether it drew something over its middle (what the game centres while loading, its
    // progress line) this frame, and the frame before, which says how what it shows is moved
    bool barSpanning=false,barCentred=false;  // made as it was drawn (for the group or the inset), its place given up when long undrawn; never brought in
    float dx=0,dy=0,scale=1; uint32_t colour=0;
    // the window's draws' bounds as the game made them, in display pixels: those of the frame being drawn, and the
    // last whole frame's, which each frame's draws are placed by
    float gather[4]={}; uint32_t gatherFrame=0; bool gathered=false;
    float bounds[4]={}; bool known=false;
    // the same of its frame's draws alone: what it is placed by, and what a draw must touch to be moved
    float frameGather[4]={}; bool frameGathered=false;
    float frame[4]={}; bool frameKnown=false;
    // for /uihook native
    uint32_t seen=0,moved=0,unmoved=0,kept=0,tinted=0,refused=0,lastFormat=0;
    uint32_t stage[3]={};  // the game's first texture stage at its frame's last draw: colour op, its two arguments
};

class NativeLook {
public:
    NativeEntry entries[NATIVE_ENTRIES];
    // the window being drawn, where it is one named: its entry, its part (frame, contents...), whether a text
    // routine is under way
    NativeEntry* current=nullptr;
    MirrorPhase phase=MIRROR_FRAME;
    unsigned text=0;
    // the group above the chat log, and the log's layout target as last drawn (its left and top), 0 frame unknown
    bool groupOn=false; float groupX=0,groupY=0;
    float inset=0;   // the sides brought in by this many pixels, 0 not
    float menuScale=1;   // every framed window drawn this much larger, from its quarter's corner of the screen
    int16_t logLeft=0,logTop=0; uint32_t logFrame=0;

    // The chat log's windows: never of the group, never brought in (chatbox places the log)
    static bool LogWindow(const char* name) {
        return !memcmp(name+8,"logwindo",8) || !memcmp(name+8,"logwin2 ",8) || !memcmp(name+8,"fulllog ",8) || !memcmp(name+8,"inline  ",8);
    }
    // An entry for a window as it is drawn: a new one, or the place of one made so and long undrawn
    NativeEntry* Make(const char* name,uint32_t frame) {
        NativeEntry* e=Find(name,true);
        if (!e) for (auto& x:entries) if (x.automatic && frame-x.seen>NATIVE_GROUP_STALE && &x!=current) { x=NativeEntry(); memcpy(x.name,name,16); e=&x; break; }
        if (e) { e->automatic=true; e->place=true; e->noInset=LogWindow(name); }
        return e;
    }
    bool Inset(float pixels) { inset=pixels>0 ? pixels : 0; return true; }
    bool MenuScale(float k) { if (!(k>=NATIVE_SCALE_LOW && k<=NATIVE_SCALE_HIGH)) return false; menuScale=k; return true; }
    // Whether a window of this name and place is one of the group
    bool GroupMember(const char* name,const int16_t* target) const {
        if (!groupOn || !logFrame || !target || target[2]<=0 || target[3]<=0) return false;
        if (LogWindow(name)) return false;
        const int bottom=target[1]+target[3];
        return bottom<=logTop && bottom>=logTop-NATIVE_GROUP_SLACK && target[0]>=0 && target[0]<=logLeft+NATIVE_GROUP_REACH;
    }
    bool Group(float x,float y) {
        groupOn=true; groupX=x; groupY=y;
        for (auto& e:entries) if (e.group) { e.dx=x; e.dy=y; }
        return true;
    }
    unsigned GroupOff() {
        unsigned n=0; groupOn=false;
        for (auto& e:entries) if (e.name[0] && e.group) {
            n++;
            // one asked for by name keeps its scale and tint, as the game places it
            if (!e.automatic) { e.group=e.member=false; e.dx=e.dy=0; continue; }
            if (&e==current) current=nullptr;
            e=NativeEntry();
        }
        return n;
    }
    // The window about to be drawn, by its name as the game keeps it and where it is drawn: the log's noted, and
    // one of the group given its entry (made, or one long undrawn taken for it)
    void Note(const char* name,const int16_t* target,uint32_t frame) {
        if (!name || !target) return;
        if (!memcmp(name,"menu    logwindo",16)) { logLeft=target[0]; logTop=target[1]; logFrame=frame; return; }
        NativeEntry* e=Find(name,false);
        const bool member=GroupMember(name,target);
        // one that was not of the group (made for the inset before the log was seen, or asked for by name to be scaled)
        // and is one now: the group's offset, its scale its own
        if (e && member && !e->group) { e->group=true; e->place=true; e->dx=groupX; e->dy=groupY; }
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
    // One asked for by name (move, scale, tint): kept, not given up when long undrawn as one made as it was drawn is
    NativeEntry* Named(const char* name) {
        char full[16]; NativeEntry* e=NativeName(name,full) ? Find(full,true) : nullptr;
        if (e) e->automatic=false;
        return e;
    }
    bool Move(const char* name,float dx,float dy) {
        NativeEntry* e=Named(name);
        if (!e) return false;
        e->place=true; e->dx=dx; e->dy=dy;
        return true;
    }
    bool Scale(const char* name,float scale) {
        if (!(scale>=NATIVE_SCALE_LOW && scale<=NATIVE_SCALE_HIGH)) return false;
        NativeEntry* e=Named(name);
        if (!e) return false;
        e->place=true; e->scale=scale;
        return true;
    }
    bool Tint(const char* name,uint32_t colour) {
        NativeEntry* e=Named(name);
        if (!e) return false;
        e->tint=true; e->colour=colour;
        return true;
    }
    // One, or every one, as the game draws it again
    unsigned Clear(const char* name) {
        char full[16]; unsigned n=0;
        if (name && !NativeName(name,full)) return 0;
        for (auto& e:entries) {
            if (!e.name[0] || (name && memcmp(e.name,full,16))) continue;
            if (&e==current) current=nullptr;
            e=NativeEntry(); n++;
        }
        return n;
    }
    bool Any() const { if (groupOn || inset>0 || menuScale!=1) return true; for (auto& e:entries) if (e.name[0]) return true; return false; }

    // The window being drawn: its entry, if it is one named. Its draws' bounds from the frame before become the ones
    // it is placed by. Returns what to give back after it.
    struct Saved { NativeEntry* current; MirrorPhase phase; unsigned text; };
    // drawn: where the game draws the window this frame (+3A, in pixels: left, top, right, bottom), or null. A window
    // drawn for the first time (or the first since its entry was given to another) is placed by it at once: placed
    // by its draws of the frame before alone, it showed for a frame where the game put it, then moved.
    Saved Enter(const char* name,uint32_t frame,const float* drawn=nullptr) {
        Saved saved={current,phase,text};
        current=nullptr; phase=MIRROR_FRAME; text=0;
        NativeEntry* e=name ? Find(name,false) : nullptr;
        if (!e && name && (inset>0 || menuScale!=1)) e=Make(name,frame);
        if (e) {
            e->seen=frame;
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
    MirrorPhase Phase(MirrorPhase now) { const MirrorPhase was=phase; phase=now; return was; }
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
        if (phase==MIRROR_FRAME && !text) Grow(current->frameGather,current->frameGathered,b);
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
    //  - one asked for by name and scaled: grown from the corner of the screen it is nearest, kept on it
    //  - one of the group over the chat log: the group's offset, scaled by the menu scale from the log's top left
    //  - one with a frame of its own (not the chat log): scaled by the menu scale from its quarter's corner of the
    //    screen (one over the middle from the middle), brought in by the inset; the bar across the top (short, over
    //    the middle, wider than half the screen) each vertex by its side, so its ends stay with their neighbours
    //  - any other (one without a frame, the target's arrow over the world): only as asked by name
    // whole: moved with the screen, not alone, so its draws all go with it (none kept back for lying outside its
    // frame: the main menu's arrows beside it)
    bool Transform(float width,float height,NativeTransform& t,bool* whole=nullptr) const {
        t=NativeTransform();
        if (whole) *whole=false;
        if (!current || !current->place || !current->known) return false;
        const NativeEntry& e=*current;
        const float* bounds=e.frameKnown ? e.frame : e.bounds;
        // one made for the group, placed elsewhere this frame: as any other
        const bool grouped=e.group && e.member,away=e.group && !e.member;
        const float dx=away ? 0 : e.dx,dy=away ? 0 : e.dy;
        const bool framed=e.frameKnown && e.frame[2]>e.frame[0] && e.frame[3]>e.frame[1];
        const bool screen=!grouped && !e.noInset && framed;
        if (e.scale!=1) {
            float extra=0;
            if (screen && inset>0) extra=e.frame[2]<=width/2 ? inset : e.frame[0]>=width/2 ? -inset : 0;
            float p[4];
            if (!NativePlace(bounds,dx+extra,dy,e.scale,width,height,p)) return false;
            t.ax=p[0]; t.ay=p[1]; t.k=e.scale; t.dx=p[2]; t.dy=p[3];
            return true;
        }
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
        if (!t.pinch || !current || (phase==MIRROR_FRAME && !text) || !current->frameKnown) return false;
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
        if (!current || !current->place || !current->known) return 1;
        const NativeEntry& e=*current;
        if (e.scale!=1) return e.scale;
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
    // Whether a draw now is the frame of a window tinted, and the colour
    bool Tinting(uint32_t& colour) const {
        if (!current || !current->tint || phase!=MIRROR_FRAME || text) return false;
        colour=current->colour; return true;
    }
    // A draw of a window moved that could not be (from a vertex buffer)
    void Unmoved() { if (current && current->place) current->unmoved++; }
};
