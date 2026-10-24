// The menu census: every window Window::Render draws, by name, with what it prints and how it draws,
// written to a file for reading. Built to find how many ways the menus draw their contents (window.h).
//
// Read only, and off until /uihook census on. It hears the text routines the window hooks take.
#pragma once
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <string>
#include <vector>
#include <algorithm>
#include "../window/window.h"

#define CENSUS_WINDOWS 512
#define CENSUS_SAMPLES 24


struct CensusSample { uint8_t route; int32_t x, y; uint32_t colour; char text[48]; };
struct CensusWindow {
    char name[17] = {};
    uint32_t frames = 0, first = 0, last = 0, lastSeen = 0;    // frames drawn; the first and last frame; the frame counted
    uint32_t owners = 0;                                        // the content draw (vtable +10), as an offset into the client
    uint32_t vtable = 0, kind = 0;
    bool content = false, cursor = false, focus = false;
    int16_t target[4] = {};
    uint32_t texts[TEXT_ROUTES] = {};                         // text calls on each route
    uint32_t draws = 0, textDraws = 0;                          // draw calls in the window, and of those made in text calls
    uint32_t nested = 0;                                        // text calls made from text calls (one route over another)
    std::vector<CensusSample> samples;                          // distinct texts, at most CENSUS_SAMPLES
};

class Census {
public:
    std::vector<CensusWindow> windows;
    CensusWindow* current = nullptr;
    unsigned depth = 0;                                         // text calls under way
    uint32_t frame = 0, outside[TEXT_ROUTES] = {};            // text calls made outside any window
    uintptr_t base = 0;
    bool on = false;

    CensusWindow* Find(const char* name) {
        for (auto& w:windows) if (!memcmp(w.name,name,16)) return &w;
        if (windows.size()>=CENSUS_WINDOWS) return nullptr;
        windows.emplace_back(); memcpy(windows.back().name,name,16);
        windows.back().first=frame;
        return &windows.back();
    }
    // A window about to be drawn: counted once a frame, its owner and fields as they are now
    CensusWindow* Enter(void* window) {
        if (!on || !window) return nullptr;
        auto* w=static_cast<uint8_t*>(window);
        char name[16]; uint8_t* header=nullptr;
        if (!ChatRead(w+WINDOW_HEADER,&header,4) || !header || !ChatRead(header+WINDOW_NAME,name,16)) return nullptr;
        for (char& c:name) if (c && (c<0x20 || c>0x7e)) c='?';
        CensusWindow* entry=Find(name);
        if (!entry) return nullptr;
        if (entry->lastSeen!=frame) { entry->frames++; entry->lastSeen=frame; }
        entry->last=frame;
        void* owner=nullptr; uint32_t vtable=0,draw=0,kind=0; uint8_t flags[2]={},draws=0;
        if (ChatRead(w+WINDOW_OWNER,&owner,4) && owner && ChatRead(owner,&vtable,4) && vtable)
            ChatRead(reinterpret_cast<void*>(static_cast<uintptr_t>(vtable)+0x10),&draw,4);
        ChatRead(w+WINDOW_KIND,&kind,4); ChatRead(w+WINDOW_DRAWS,&draws,1); ChatRead(w+WINDOW_CURSOR,flags,2);
        ChatRead(w+WINDOW_TARGET,entry->target,8);
        entry->vtable=vtable ? vtable-static_cast<uint32_t>(base) : 0;
        entry->owners=draw ? draw-static_cast<uint32_t>(base) : 0;
        entry->kind=kind; entry->content=owner && draws && kind!=0xe;
        entry->cursor|=flags[0]!=0; entry->focus|=flags[1]!=0;
        return entry;
    }
    void Text(TextRoute route,int32_t x,int32_t y,const char* text,uint32_t colour) {
        if (!on) return;
        if (!current) { outside[route]++; return; }
        current->texts[route]++;
        if (depth) current->nested++;
        if (current->samples.size()>=CENSUS_SAMPLES || !text) return;
        CensusSample sample={}; sample.route=static_cast<uint8_t>(route); sample.x=x; sample.y=y; sample.colour=colour;
        for (unsigned i=0;i<sizeof(sample.text)-1;i++) {
            char c=0;
            if (!ChatRead(text+i,&c,1) || !c) break;
            sample.text[i]=(c>=0x20 && c<0x7f) ? c : '.';
        }
        for (auto& s:current->samples) if (s.route==route && !strcmp(s.text,sample.text)) return;
        current->samples.push_back(sample);
    }
    void Draw() { if (on && current) { current->draws++; if (depth) current->textDraws++; } }
    void Clear() { windows.clear(); current=nullptr; depth=0; memset(outside,0,sizeof(outside)); }

    // The census as a file: the windows by name, then each one's text
    bool Write(const char* path,const char* hooks) const {
        FILE* file=fopen(path,"w");
        if (!file) return false;
        std::vector<const CensusWindow*> sorted;
        for (auto& w:windows) sorted.push_back(&w);
        std::sort(sorted.begin(),sorted.end(),[](auto* a,auto* b){ return strcmp(a->name,b->name)<0; });
        fprintf(file,"uihook menu census, frame %u; %zu windows; text routes %s\n",frame,windows.size(),hooks);
        fprintf(file,"text outside any window: bitmap %u, scaled %u, font %u\n\n",outside[0],outside[1],outside[2]);
        fprintf(file,"%-16s %7s %8s %8s %4s %3s %-19s %6s %6s %6s %6s %6s %6s\n","name","frames","draw","vtable","kind","c/f",
            "target x,y,w,h","bitmap","scaled","font","nested","draws","intext");
        for (auto* w:sorted)
            fprintf(file,"%-16s %7u %08X %08X %4X %c%c  %4d,%4d,%4d,%4d %6u %6u %6u %6u %6u %6u\n",w->name,w->frames,w->owners,w->vtable,
                w->kind,w->cursor ? 'c' : '-',w->focus ? 'f' : '-',w->target[0],w->target[1],w->target[2],w->target[3],
                w->texts[0],w->texts[1],w->texts[2],w->nested,w->draws,w->textDraws);
        // the windows sharing a content draw: one drawer, many menus
        fprintf(file,"\ncontent draws shared by windows:\n");
        std::vector<uint32_t> draws;
        for (auto* w:sorted) if (w->owners && std::find(draws.begin(),draws.end(),w->owners)==draws.end()) draws.push_back(w->owners);
        for (uint32_t d:draws) {
            std::string names; unsigned n=0;
            for (auto* w:sorted) if (w->owners==d) { names+=' '; names+=w->name+8; n++; }
            fprintf(file,"  %08X %2u:%s\n",d,n,names.c_str());
        }
        fprintf(file,"\ntext seen in each window (route, x, y, colour, text):\n");
        for (auto* w:sorted) {
            if (w->samples.empty()) continue;
            fprintf(file,"%s\n",w->name);
            for (auto& s:w->samples) fprintf(file,"  %-6s %5d %5d %08X %s\n",TextRouteNames[s.route],s.x,s.y,s.colour,s.text);
        }
        fclose(file);
        return true;
    }
};
// The window being drawn, kept while it is, and the one before it given back after
struct CensusScope {
    Census& census; CensusWindow* was;
    CensusScope(Census& c,void* window) : census(c), was(c.current) { c.current=c.Enter(window); }
    ~CensusScope() { census.current=was; }
};
