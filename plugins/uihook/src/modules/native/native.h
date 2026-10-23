// The native look, an experiment: a window of the game's, named, moved where the game lays it out and its frame
// tinted as it is drawn, the game's own menu kept whole (its input, cursor, text and hit-tests its own). For trying
// a skin on the real menus rather than drawing them again (the mirror).
//
//   /uihook native                         what is set, and whether each was applied
//   /uihook native move <name> <x> <y>     the window moved by x, y display pixels
//   /uihook native tint <name> <AARRGGBB>  its frame's draws multiplied by this colour (0xFF808080 halves it)
//   /uihook native clear [name]            one, or all, as the game has them again
//
// The move is the action menus' (chat/menus.h): the layout target (+8C) written before Window::Render calls
// Window::Update and the window marked for it (+94), so its frame, rows, cursor and hit-tests are laid out there
// by the game itself. The tint is a second texture stage after the game's own, multiplying what it made by the
// colour (the texture factor), set for the frame's draws alone and put back after each: the game's frames do not
// take their vertices' colours, so changing those (1.25) showed nothing. The contents, the elements, the cursor,
// the scrollbar and any text are left as they are.
#pragma once
#include <stdint.h>
#include <string.h>
#include <cmath>
#include "../mirror/mirror.h"

#define NATIVE_ENTRIES 16

// The target moved by dx, dy display pixels, in the window's units: pixels, or the 640x480 units scaled to the
// menu manager's dimensions where the window is scaled (+99). Kept from going past the top or left edge; false
// where it would leave the units' range.
static bool NativeOffset(const int16_t* original,bool scaled,const int* dimensions,int dx,int dy,int16_t* out) {
    if (scaled && (dimensions[0]<=0 || dimensions[1]<=0 || dimensions[0]>16384 || dimensions[1]>16384)) return false;
    const float sx=scaled ? dimensions[0]/640.0f : 1.0f,sy=scaled ? dimensions[1]/480.0f : 1.0f;
    const float x=(std::max)(0.0f,std::floor(original[0]+dx/sx+0.5f)),y=(std::max)(0.0f,std::floor(original[1]+dy/sy+0.5f));
    if (x>32767 || y>32767) return false;
    out[0]=static_cast<int16_t>(x); out[1]=static_cast<int16_t>(y);
    return true;
}
// A window's name as the game keeps it: "menu    " and the name, spaces to sixteen
static bool NativeName(const char* name,char* out) {
    const size_t length=name ? strlen(name) : 0;
    if (!length || length>8) return false;
    memcpy(out,"menu            ",16); memcpy(out+8,name,length);
    return true;
}

struct NativeEntry {
    char name[16]={};
    bool move=false,tint=false;
    int dx=0,dy=0; uint32_t colour=0;
    // the window last moved, and what was written: given back the next time it is drawn, once no longer asked for
    void* window=nullptr; void* header=nullptr;
    int16_t original[2]={},applied[2]={};
    bool moved=false;
    uint32_t frame=0;    // the frame it was last drawn moved
    // for /uihook native: when a window of its name was last drawn, why it was last not moved, and its frame's draws
    uint32_t seen=0; const char* why="not drawn since asked";
    uint32_t tinted=0,refused=0,lastFormat=0;
    uint32_t stage[3]={};  // the game's first texture stage at its frame's last draw: colour op, its two arguments
};

class NativeLook {
public:
    NativeEntry entries[NATIVE_ENTRIES];
    uint32_t applied=0,restored=0;
    // the window being drawn, while its frame is: the entry tinting it, and whether a text routine is under way
    NativeEntry* current=nullptr;
    MirrorPhase phase=MIRROR_FRAME;
    unsigned text=0;

    // A window of an entry's name drawn, and why it could not be moved, if it could not
    void Seen(const char* name,uint32_t frame,const char* why) {
        NativeEntry* e=Find(name,false);
        if (!e) return;
        e->seen=frame; if (why) e->why=why;
    }
    NativeEntry* Find(const char* name,bool add) {
        for (auto& e:entries) if (e.name[0] && !memcmp(e.name,name,16)) return &e;
        if (!add) return nullptr;
        for (auto& e:entries) if (!e.name[0] && !e.moved) { e=NativeEntry(); memcpy(e.name,name,16); return &e; }
        return nullptr;
    }
    bool Move(const char* name,int dx,int dy) {
        char full[16]; NativeEntry* e=NativeName(name,full) ? Find(full,true) : nullptr;
        if (!e) return false;
        e->move=true; e->dx=dx; e->dy=dy;
        return true;
    }
    bool Tint(const char* name,uint32_t colour) {
        char full[16]; NativeEntry* e=NativeName(name,full) ? Find(full,true) : nullptr;
        if (!e) return false;
        e->tint=true; e->colour=colour;
        return true;
    }
    // One, or every one, no longer asked for; one moved is put back the next time it is drawn
    unsigned Clear(const char* name) {
        char full[16]; unsigned n=0;
        if (name && !NativeName(name,full)) return 0;
        for (auto& e:entries) {
            if (!e.name[0] || (name && memcmp(e.name,full,16))) continue;
            e.move=e.tint=false; n++;
        }
        return n;
    }
    bool Any() const { for (auto& e:entries) if (e.name[0]) return true; return false; }

    // Before Window::Render lays the window out: moved where asked, or put back where it was. data is its first
    // 0x9a bytes as read, target writable at window+0x8c.
    void Before(void* window,void* header,const uint8_t* data,const int* dimensions,uint32_t frame) {
        char name[16]; if (!header || !ChatRead(static_cast<uint8_t*>(header)+0x46,name,16)) return;
        NativeEntry* e=Find(name,false);
        if (!e) return;
        e->why=nullptr;
        if (e->moved && (window!=e->window || header!=e->header)) e->moved=false; // another window of that name: its own place
        int16_t target[2]; memcpy(target,data+0x8c,4);
        auto* at=static_cast<uint8_t*>(window);
        int16_t desired[2];
        if (e->move) {
            if (!e->moved) memcpy(e->original,target,4);
            else for (unsigned i=0;i<2;i++) if (target[i]!=e->applied[i]) e->original[i]=target[i]; // the game laid it out afresh
            if (!NativeOffset(e->original,data[0x99]!=0,dimensions,e->dx,e->dy,desired)) { e->why="off the screen's range"; Restore(*e,window,target); return; }
            if (target[0]!=desired[0] || target[1]!=desired[1]) {
                memcpy(at+0x8c,desired,4); const int32_t dirty=-1; memcpy(at+0x94,&dirty,4);
                applied++;
            }
            memcpy(e->applied,desired,4); e->window=window; e->header=header; e->moved=true; e->frame=frame;
        } else Restore(*e,window,target);
        if (!e->move && !e->tint && !e->moved) *e=NativeEntry(); // done with
    }
    // Put back where the game had it, where it is still where it was put
    void Restore(NativeEntry& e,void* window,const int16_t* target) {
        if (!e.moved || window!=e.window) return;
        int16_t back[2]={target[0],target[1]}; bool changed=false;
        for (unsigned i=0;i<2;i++) if (target[i]==e.applied[i]) { back[i]=e.original[i]; changed=true; }
        if (changed) {
            auto* at=static_cast<uint8_t*>(window);
            memcpy(at+0x8c,back,4); const int32_t dirty=-1; memcpy(at+0x94,&dirty,4);
            restored++;
        }
        e.moved=false;
    }

    // The window being drawn: its entry, if its frame is tinted. Returns what to give back after it.
    struct Saved { NativeEntry* current; MirrorPhase phase; unsigned text; };
    Saved Enter(const char* name) {
        Saved saved={current,phase,text};
        current=nullptr; phase=MIRROR_FRAME; text=0;
        if (name) { NativeEntry* e=Find(name,false); if (e && e->tint) current=e; }
        return saved;
    }
    void Leave(const Saved& saved) { current=saved.current; phase=saved.phase; text=saved.text; }
    MirrorPhase Phase(MirrorPhase now) { const MirrorPhase was=phase; phase=now; return was; }
    // Whether a draw now is the frame of a window tinted, and the colour
    bool Tinting(uint32_t& colour) const {
        if (!current || !current->tint || phase!=MIRROR_FRAME || text) return false;
        colour=current->colour; return true;
    }
};
