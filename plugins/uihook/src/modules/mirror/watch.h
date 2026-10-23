// The mirror watched while played: every window Window::Render draws in a frame, whether an addon asked for it,
// whether it was mirrored or dropped (past MIRROR_WINDOWS a frame), and how its draws were made: only
// DrawPrimitiveUP in screen space (XYZRHW) can be measured, so a window drawn any other way is mirrored with no
// place. Written to a file as what is drawn changes, at most once a second, with what was published; off until
// /uihook mirror watch, for reading what a menu does while it is open from outside the game.
#pragma once
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <string>
#include <vector>

#define MIRROR_WATCH_WINDOWS 64
#define MIRROR_WATCH_EVERY 1000 // ms between writes, at most

struct MirrorWatchWindow {
    char name[17];
    uint32_t kind; uint8_t draws, depth;
    bool wanted, hidden, mirrored;
    uint32_t up, other, buffer; // its draws: measured (UP, screen space), UP not in screen space, from vertex buffers
};

class MirrorWatch {
    std::vector<MirrorWatchWindow> drawn;
    int current=-1;
    uint8_t depth=0;
    std::string last; // what was last written, but for the draws' counts
    uint32_t writtenAt=0;
public:
    bool on=false;
    void Start() { on=true; drawn.clear(); current=-1; depth=0; last.clear(); writtenAt=0; }
    void Stop() { on=false; drawn.clear(); current=-1; depth=0; }
    // The next frame is written whatever has changed (after a mark)
    void Renew() { last.clear(); writtenAt=0; }
    // A window about to be drawn, as the mirror took it; the one drawn before it, given back by Leave
    int Enter(void* window,bool wanted,bool hidden,bool mirrored) {
        const int was=current;
        depth++;
        if (!on || !window) { current=-1; return was; }
        auto* w=static_cast<uint8_t*>(window);
        char name[16]; uint8_t* header=nullptr;
        if (!ChatRead(w+CENSUS_HEADER,&header,4) || !header || !ChatRead(header+CENSUS_NAME,name,16)) { current=-1; return was; }
        for (char& c:name) if (c && (c<0x20 || c>0x7e)) c='?';
        int at=-1;
        for (size_t i=0;i<drawn.size();i++) if (!memcmp(drawn[i].name,name,16)) { at=int(i); break; }
        if (at<0) {
            if (drawn.size()>=MIRROR_WATCH_WINDOWS) { current=-1; return was; }
            MirrorWatchWindow entry{}; memcpy(entry.name,name,16);
            ChatRead(w+CENSUS_KIND,&entry.kind,4); ChatRead(w+CENSUS_DRAWS,&entry.draws,1);
            entry.depth=uint8_t(depth-1);
            drawn.push_back(entry); at=int(drawn.size()-1);
        }
        drawn[at].wanted|=wanted; drawn[at].hidden|=hidden; drawn[at].mirrored|=mirrored;
        current=at;
        return was;
    }
    void Leave(int was) { current=was; if (depth) depth--; }
    enum Kind { UP, OTHER, BUFFER };
    void Draw(Kind kind) {
        if (!on || current<0) return;
        MirrorWatchWindow& w=drawn[size_t(current)];
        (kind==UP ? w.up : kind==OTHER ? w.other : w.buffer)++;
    }
    // At Present, after the frame is published: what to add to the file, or nothing where nothing has changed or
    // the last was written less than a second ago (now, ms). The frame's windows forgotten either way.
    std::string Present(const MirrorFrameData& published,uint32_t dropped,uint32_t frame,uint32_t now,const char* clock) {
        if (!on) return std::string();
        std::string same,text; char line[256];
        for (auto& w:drawn) {
            snprintf(line,sizeof(line),"  %-16s kind %X draws %u depth %u: %s%s%s",w.name,w.kind,w.draws,w.depth,
                w.wanted ? "asked" : "-",w.hidden ? " hidden" : "",w.wanted ? (w.mirrored ? " mirrored" : " NOT MIRRORED") : "");
            same+=line; text+=line;
            snprintf(line,sizeof(line),"%s\n",w.up+w.other+w.buffer ? "" : " (no draws)"); same+=line;
            snprintf(line,sizeof(line),"; draws: %u measured, %u not screen space, %u from buffers\n",w.up,w.other,w.buffer); text+=line;
        }
        for (uint32_t i=0;i<published.WindowCount && i<MIRROR_WINDOWS;i++) {
            const MirrorWindow& w=published.Windows[i];
            const bool placed=w.Rect[2]>w.Rect[0] && w.Rect[3]>w.Rect[1];
            snprintf(line,sizeof(line),"  published %.16s: flags %X, %s%.3f,%.3f to %.3f,%.3f; %u runs, %u quads; cursor %s, scrollbar %u of %u\n",
                w.Name,w.Flags,placed ? "" : "NO PLACE ",w.Rect[0],w.Rect[1],w.Rect[2],w.Rect[3],w.Runs,w.Quads,
                w.CursorFrame ? "drawn" : "none",w.ScrollPage,w.ScrollCount);
            same+=line;
        }
        const unsigned count=unsigned(drawn.size());
        drawn.clear(); current=-1; depth=0;
        if (same==last || (writtenAt && now-writtenAt<MIRROR_WATCH_EVERY)) return std::string();
        last=same; writtenAt=now ? now : 1;
        // the published windows' lines, which have no counts, as they are in same
        const size_t published0=same.find("  published ");
        snprintf(line,sizeof(line),"== %s frame %u: %u drawn, %u published, %u dropped since loading\n",clock,frame,
            count,published.WindowCount,dropped);
        return line+text+(published0==std::string::npos ? std::string() : same.substr(published0));
    }
};
