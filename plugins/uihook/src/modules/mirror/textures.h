// The texture census: every texture the game's screen-space drawing uses, which windows use it and in which part
// (frame, element, cursor, scrollbar, contents, text, after), how much of it they take (the texture places used), and
// its pixels, written out once each by what they are. To tell whether the menus are made of a few pieces that could be
// reskinned once for them all, rather than each menu drawn again.
//
// Read only, and off until /uihook textures on. Each texture is read once as first seen (and again where its pointer
// has not been seen for a while, as the game may have made another there), kept as pixels until /uihook textures clear.
#pragma once
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <string>
#include <vector>
#include <algorithm>
#include <cmath>
#include "labels.h"

#define TEXTURE_PARTS 8
#define TEXTURE_WINDOWS 96
#define TEXTURE_COLOURS 8
#define TEXTURE_STALE 120               // frames a pointer goes unseen before it is read again
#define TEXTURE_MEMORY (128u<<20)       // pixels kept at most, in bytes; past it a texture is counted, not kept
enum TexturePart { TEXTURE_FRAME, TEXTURE_CONTENT, TEXTURE_CURSOR, TEXTURE_ELEMENT, TEXTURE_SCROLL, TEXTURE_AFTER, TEXTURE_TEXT, TEXTURE_OUTSIDE };
static const char* const TexturePartNames[TEXTURE_PARTS] = { "frame", "content", "cursor", "element", "scroll", "after", "text", "outside" };

// A texture's name by its pixels and size, as the census writes it (tex-<hash>.bmp) and a skin names its own
static uint32_t TextureHash(const LabelPixels& pixels,uint32_t width,uint32_t height) { return LabelHash(pixels)^(width*2654435761u)^height; }

struct TextureEntry {
    uint32_t hash=0, width=0, height=0, format=0, pool=0;   // hash 0: none read (why says why); width 0: no texture at all
    const char* why="";
    LabelPixels pixels;
    uint32_t draws[TEXTURE_PARTS]={}, buffered=0;           // screen-space draws by part; of them, from a vertex buffer
    std::vector<std::string> windows;                       // the windows drawing it, at most TEXTURE_WINDOWS
    float uv[4]={}; bool uvKnown=false;                     // the texture places drawn, all draws together
    uint32_t colours[TEXTURE_COLOURS]={}; unsigned colourCount=0;
    uint32_t Total() const { uint32_t n=0; for (auto d:draws) n+=d; return n; }
};

class TextureCensus {
public:
    bool on=false;
    std::vector<TextureEntry> entries;
    struct Pointer { uintptr_t texture; uint32_t seen; size_t entry; };
    std::vector<Pointer> pointers;
    size_t memory=0;
    char window[17]={};                                     // the window being drawn, "" outside any

    // Where a pointer's entry is, if it was seen lately; else npos, and it is to be read
    size_t Known(uintptr_t texture,uint32_t frame) {
        for (auto& p:pointers) if (p.texture==texture) {
            if (frame-p.seen>TEXTURE_STALE) return SIZE_MAX;
            p.seen=frame; return p.entry;
        }
        return SIZE_MAX;
    }
    // A texture read: kept by its pixels, one entry for each that are alike wherever the game keeps them
    size_t Add(uintptr_t texture,uint32_t frame,uint32_t width,uint32_t height,uint32_t format,uint32_t pool,LabelPixels* pixels,const char* why) {
        const uint32_t hash=pixels ? TextureHash(*pixels,width,height) : 0;
        size_t at=SIZE_MAX;
        if (hash) for (size_t i=0;i<entries.size();i++)
            if (entries[i].hash==hash && entries[i].width==width && entries[i].height==height) { at=i; break; }
        if (!hash) for (size_t i=0;i<entries.size();i++)   // one not read: one entry for each of its kind
            if (!entries[i].hash && entries[i].width==width && entries[i].height==height && entries[i].format==format && !strcmp(entries[i].why,why)) { at=i; break; }
        if (at==SIZE_MAX) {
            entries.emplace_back(); TextureEntry& e=entries.back();
            e.hash=hash; e.width=width; e.height=height; e.format=format; e.pool=pool; e.why=why;
            const size_t bytes=pixels ? pixels->argb.size()*4 : 0;
            if (pixels && memory+bytes<=TEXTURE_MEMORY) { e.pixels=std::move(*pixels); memory+=bytes; }
            else if (pixels) e.why="past the memory kept";
            at=entries.size()-1;
        }
        for (auto& p:pointers) if (p.texture==texture) { p.seen=frame; p.entry=at; return at; }
        pointers.push_back({texture,frame,at});
        return at;
    }
    // One draw with it: its part, the window, the texture places and colour of its first vertex
    void Count(size_t at,TexturePart part,const float* uv,const uint32_t* colour,bool buffered) {
        if (at>=entries.size()) return;
        TextureEntry& e=entries[at];
        e.draws[part]++; if (buffered) e.buffered++;
        const char* name=window[0] ? window : "(no window)";
        if (e.windows.size()<TEXTURE_WINDOWS && std::find(e.windows.begin(),e.windows.end(),name)==e.windows.end()) e.windows.push_back(name);
        if (uv) {
            if (!e.uvKnown) { e.uv[0]=uv[0]; e.uv[1]=uv[1]; e.uv[2]=uv[2]; e.uv[3]=uv[3]; e.uvKnown=true; }
            else { e.uv[0]=(std::min)(e.uv[0],uv[0]); e.uv[1]=(std::min)(e.uv[1],uv[1]); e.uv[2]=(std::max)(e.uv[2],uv[2]); e.uv[3]=(std::max)(e.uv[3],uv[3]); }
        }
        if (colour && e.colourCount<TEXTURE_COLOURS && std::find(e.colours,e.colours+e.colourCount,*colour)==e.colours+e.colourCount) e.colours[e.colourCount++]=*colour;
    }
    void Clear() { entries.clear(); pointers.clear(); memory=0; }
    // A window's name as the game keeps it ("menu    " and its own), its own part kept
    void Window(const char* name) {
        if (!name) { window[0]=0; return; }
        const char* own=!memcmp(name,"menu    ",8) ? name+8 : name;
        const size_t most=16-size_t(own-name);
        size_t n=0; for (;n<most && own[n];n++) window[n]=(own[n]>=0x20 && own[n]<0x7f) ? own[n] : '?';
        while (n && window[n-1]==' ') n--;
        window[n]=0;
    }

    // The census as files in folder: index.txt, the textures by how many windows draw them, then the windows by the
    // textures they draw; each texture read as tex-<hash>.bmp
    bool Write(const std::string& folder,unsigned& images) const {
        FILE* f=fopen((folder+"\\index.txt").c_str(),"w");
        if (!f) return false;
        std::vector<size_t> order; for (size_t i=0;i<entries.size();i++) order.push_back(i);
        std::sort(order.begin(),order.end(),[&](size_t a,size_t b){
            if (entries[a].windows.size()!=entries[b].windows.size()) return entries[a].windows.size()>entries[b].windows.size();
            return entries[a].Total()>entries[b].Total();
        });
        std::vector<std::string> names;
        for (auto& e:entries) for (auto& w:e.windows) if (std::find(names.begin(),names.end(),w)==names.end()) names.push_back(w);
        std::sort(names.begin(),names.end());
        uint32_t total=0; for (auto& e:entries) total+=e.Total();
        fprintf(f,"uihook texture census: %zu textures, %zu windows, %u screen-space draws, %zu bytes of pixels kept\n",entries.size(),names.size(),total,memory);
        fprintf(f,"parts: frame (the window's own art), content, cursor, element, scroll, after (drawn after the contents), text (in a text routine), outside (drawn in no window)\n\n");
        fprintf(f,"%-14s %9s %8s %4s %5s %-46s %-27s %s\n","file","size","format","pool","wins","draws by part (f/c/cu/e/s/a/t/o) +buffered","uv used","colours");
        images=0;
        for (size_t i:order) {
            const TextureEntry& e=entries[i];
            char file[24]="-";
            if (e.hash && !e.pixels.argb.empty()) {
                snprintf(file,sizeof(file),"tex-%08X.bmp",e.hash);
                if (LabelWrite((folder+"\\"+file).c_str(),e.pixels)) images++; else snprintf(file,sizeof(file),"(not written)");
            } else if (!e.width) snprintf(file,sizeof(file),"(no texture)");
            char size[16]; snprintf(size,sizeof(size),"%ux%u",e.width,e.height);
            char parts[64]; snprintf(parts,sizeof(parts),"%u/%u/%u/%u/%u/%u/%u/%u +%u",e.draws[0],e.draws[1],e.draws[2],e.draws[3],e.draws[4],e.draws[5],e.draws[6],e.draws[7],e.buffered);
            char uv[40]="-"; if (e.uvKnown) snprintf(uv,sizeof(uv),"%.3f,%.3f-%.3f,%.3f",e.uv[0],e.uv[1],e.uv[2],e.uv[3]);
            std::string colours; for (unsigned c=0;c<e.colourCount;c++) { char s[12]; snprintf(s,sizeof(s),"%s%08X",c ? " " : "",e.colours[c]); colours+=s; }
            fprintf(f,"%-14s %9s %08X %4u %5zu %-46s %-27s %s%s%s\n",file,size,e.format,e.pool,e.windows.size(),parts,uv,colours.c_str(),
                e.why[0] ? "  # " : "",e.why);
            std::string list; for (auto& w:e.windows) { list+=list.empty() ? "" : " "; list+=w; }
            fprintf(f,"    %s\n",list.c_str());
        }
        fprintf(f,"\nwindows and the textures they draw (file, or size/format where none was read):\n");
        for (auto& name:names) {
            std::string list; unsigned n=0;
            for (size_t i:order) {
                const TextureEntry& e=entries[i];
                if (std::find(e.windows.begin(),e.windows.end(),name)==e.windows.end()) continue;
                char s[40];
                if (e.hash) snprintf(s,sizeof(s)," %08X",e.hash); else if (e.width) snprintf(s,sizeof(s)," %ux%u/%X",e.width,e.height,e.format); else snprintf(s,sizeof(s)," none");
                list+=s; n++;
            }
            fprintf(f,"%-16s %3u:%s\n",name.c_str(),n,list.c_str());
        }
        fclose(f);
        return true;
    }
};

// A screen-space draw's first vertex's colour and the texture places of all its vertices, by its FVF; false where it
// has no texture places
static bool TextureVertices(const void* data,unsigned count,unsigned stride,uint32_t fvf,float* uv,uint32_t* colour,bool& hasColour) {
    hasColour=false;
    if (!data || !count || (fvf & D3DFVF_POSITION_MASK)!=D3DFVF_XYZRHW) return false;
    unsigned at=16;
    const auto* bytes=static_cast<const uint8_t*>(data);
    if (fvf & D3DFVF_DIFFUSE) { if (stride>=at+4) { memcpy(colour,bytes+at,4); hasColour=true; } at+=4; }
    if (fvf & D3DFVF_SPECULAR) at+=4;
    if (((fvf & D3DFVF_TEXCOUNT_MASK)>>D3DFVF_TEXCOUNT_SHIFT)<1 || stride<at+8) return false;
    for (unsigned i=0;i<count;i++) {
        float t[2]; memcpy(t,bytes+size_t(i)*stride+at,sizeof(t));
        if (!std::isfinite(t[0]) || !std::isfinite(t[1])) return false;
        if (!i) { uv[0]=uv[2]=t[0]; uv[1]=uv[3]=t[1]; continue; }
        uv[0]=(std::min)(uv[0],t[0]); uv[1]=(std::min)(uv[1],t[1]);
        uv[2]=(std::max)(uv[2],t[0]); uv[3]=(std::max)(uv[3],t[1]);
    }
    return true;
}
