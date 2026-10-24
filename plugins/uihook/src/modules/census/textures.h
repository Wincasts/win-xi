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
#define TEXTURE_SAMPLES 48              // pieces drawn of each texture, kept to show how it is cut
#define TEXTURE_STALE 120               // frames a pointer goes unseen before it is read again
#define TEXTURE_MEMORY (128u<<20)       // pixels kept at most, in bytes; past it a texture is counted, not kept
enum TexturePart { TEXTURE_FRAME, TEXTURE_CONTENT, TEXTURE_CURSOR, TEXTURE_ELEMENT, TEXTURE_SCROLL, TEXTURE_AFTER, TEXTURE_TEXT, TEXTURE_OUTSIDE };
static const char* const TexturePartNames[TEXTURE_PARTS] = { "frame", "content", "cursor", "element", "scroll", "after", "text", "outside" };

// A texture's name by its pixels and size, as the census writes it (tex-<hash>.bmp) and a skin names its own
static uint32_t TextureHash(const LabelPixels& pixels,uint32_t width,uint32_t height) { return LabelHash(pixels)^(width*2654435761u)^height; }

// One piece of a texture as drawn (a quad of a draw): where on the screen, the texture places at its top-left and
// bottom-right corners (either way round, so a piece drawn mirrored shows it), its first vertex's colour
struct TextureSample { char window[17]; uint8_t part; float rect[4], uv[4]; uint32_t colour; uint32_t count; };

// A glyph of a font texture: the character it is (a byte, or a Shift-JIS pair as lead<<8 | trail), its texels, its
// size on the screen, and how many prints drew it so
struct TextureGlyph { uint16_t token; uint16_t texels[4]; float size[2]; uint32_t count; };
#define TEXTURE_GLYPHS 4096

struct TextureEntry {
    uint32_t hash=0, width=0, height=0, format=0, pool=0;   // hash 0: none read (why says why); width 0: no texture at all
    const char* why="";
    LabelPixels pixels;
    uint32_t draws[TEXTURE_PARTS]={}, buffered=0;           // screen-space draws by part; of them, from a vertex buffer
    std::vector<std::string> windows;                       // the windows drawing it, at most TEXTURE_WINDOWS
    float uv[4]={}; bool uvKnown=false;                     // the texture places drawn, all draws together
    uint32_t colours[TEXTURE_COLOURS]={}; unsigned colourCount=0;
    std::vector<TextureSample> samples;
    std::vector<TextureGlyph> glyphs;
    uint32_t Total() const { uint32_t n=0; for (auto d:draws) n+=d; return n; }
};

// What a print (a text routine) drew, matched to what it was asked to print: its characters, as tokens (a byte, a
// Shift-JIS pair, the game's two-byte codes skipped), and the pieces drawn while it ran. Where the pieces are as
// many as the characters (spaces drawn or not), or a whole number of times as many (a shadow or an edge drawn
// with each, or each pass whole), each piece is that character's glyph.
struct GlyphPiece { size_t entry; float rect[4], uv[4]; };
static void GlyphTokens(const uint8_t* text,size_t length,bool spaces,std::vector<uint16_t>& out) {
    out.clear();
    for (size_t i=0;i<length;i++) {
        const uint8_t b=text[i];
        if (b==0x1e || b==0x1f || b==0x7f) { i++; continue; }      // colour and other codes, with their byte
        if (b<0x20) continue;
        if (b==0x20 && !spaces) continue;
        if (((b>=0x81 && b<=0x9f) || (b>=0xe0 && b<=0xfc)) && i+1<length) { out.push_back(uint16_t(b<<8 | text[i+1])); i++; continue; }
        out.push_back(b);
    }
}

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
    // A piece drawn, kept where it is unlike those kept: by window, part, size and texture places, wherever it is
    void Sample(size_t at,TexturePart part,const float* rect,const float* uv,uint32_t colour) {
        if (at>=entries.size()) return;
        TextureEntry& e=entries[at];
        const char* name=window[0] ? window : "(no window)";
        auto same=[&](const TextureSample& s) {
            if (s.part!=part || strcmp(s.window,name)) return false;
            if (fabsf((s.rect[2]-s.rect[0])-(rect[2]-rect[0]))>0.5f || fabsf((s.rect[3]-s.rect[1])-(rect[3]-rect[1]))>0.5f) return false;
            for (int i=0;i<4;i++) if (fabsf(s.uv[i]-uv[i])>0.002f) return false;
            return true;
        };
        for (auto& s:e.samples) if (same(s)) { s.count++; return; }
        if (e.samples.size()>=TEXTURE_SAMPLES) return;
        TextureSample s={}; snprintf(s.window,sizeof(s.window),"%s",name); s.part=uint8_t(part);
        memcpy(s.rect,rect,sizeof(s.rect)); memcpy(s.uv,uv,sizeof(s.uv)); s.colour=colour; s.count=1;
        e.samples.push_back(s);
    }
    void Clear() { entries.clear(); pointers.clear(); memory=0; runs=matched=0; }

    // Prints: the one under way (the outermost, a print within it counted as its own), and how many matched
    uint8_t runText[256]={}; size_t runLength=0; unsigned runDepth=0; bool runOn=false;
    std::vector<GlyphPiece> runPieces;
    uint32_t runs=0, matched=0;
    void PrintBegin(const uint8_t* text,size_t length) {
        if (runDepth++ || !on) return;
        runLength=length<sizeof(runText) ? length : sizeof(runText); memcpy(runText,text,runLength);
        runPieces.clear(); runOn=true;
    }
    void PrintPiece(size_t at,const float* rect,const float* uv) {
        if (runOn && runPieces.size()<1024) { GlyphPiece p; p.entry=at; memcpy(p.rect,rect,sizeof(p.rect)); memcpy(p.uv,uv,sizeof(p.uv)); runPieces.push_back(p); }
    }
    void PrintEnd() {
        if (!runDepth || --runDepth || !runOn) return;
        runOn=false; runs++;
        std::vector<uint16_t> tokens;
        for (int spaces=0;spaces<2;spaces++) {
            GlyphTokens(runText,runLength,spaces!=0,tokens);
            const size_t n=tokens.size(),q=runPieces.size();
            if (!n || !q || q%n || q/n>4) continue;
            const size_t k=q/n;
            auto same=[&](const GlyphPiece& a,const GlyphPiece& b) {
                if (a.entry!=b.entry) return false;
                for (int i=0;i<4;i++) if (fabsf(a.uv[i]-b.uv[i])>0.0005f) return false;
                return true;
            };
            bool interleaved=true,blocked=true;
            for (size_t i=0;i<n && (interleaved || blocked);i++) for (size_t j=1;j<k;j++) {
                if (!same(runPieces[i*k],runPieces[i*k+j])) interleaved=false;
                if (!same(runPieces[i],runPieces[j*n+i])) blocked=false;
            }
            if (!interleaved && !blocked) continue;
            for (size_t i=0;i<n;i++) Glyph(interleaved ? runPieces[i*k] : runPieces[i],tokens[i]);
            matched++;
            return;
        }
    }
    void Glyph(const GlyphPiece& p,uint16_t token) {
        if (p.entry>=entries.size()) return;
        TextureEntry& e=entries[p.entry];
        if (!e.width || !e.height) return;
        uint16_t texels[4];
        for (int i=0;i<4;i++) {
            const float t=p.uv[i]*float(i%2 ? e.height : e.width)+0.5f;
            texels[i]=uint16_t(t<0 ? 0 : t>65535 ? 65535 : t);
        }
        for (auto& g:e.glyphs) if (g.token==token && !memcmp(g.texels,texels,sizeof(texels))) { g.count++; return; }
        if (e.glyphs.size()>=TEXTURE_GLYPHS) return;
        TextureGlyph g={}; g.token=token; memcpy(g.texels,texels,sizeof(texels));
        g.size[0]=p.rect[2]-p.rect[0]; g.size[1]=p.rect[3]-p.rect[1]; g.count=1;
        e.glyphs.push_back(g);
    }
    // glyphs.txt: each font texture's glyphs, by character
    bool WriteGlyphs(const std::string& path) const {
        FILE* f=fopen(path.c_str(),"w");
        if (!f) return false;
        fprintf(f,"uihook glyph census: %u prints heard, %u matched to what they drew\n",runs,matched);
        fprintf(f,"# texture: token (hex; the character where it is one), texels x0 y0 x1 y1 (either way round), size on the screen, prints\n");
        for (auto& e:entries) {
            if (e.glyphs.empty()) continue;
            std::vector<TextureGlyph> sorted=e.glyphs;
            std::sort(sorted.begin(),sorted.end(),[](const TextureGlyph& a,const TextureGlyph& b) { return a.token!=b.token ? a.token<b.token : a.count>b.count; });
            fprintf(f,"\ntex-%08X %ux%u format %08X: %zu glyphs\n",e.hash,e.width,e.height,e.format,sorted.size());
            for (auto& g:sorted) {
                char shown[4]="  "; if (g.token>=0x21 && g.token<0x7f) { shown[0]=char(g.token); shown[1]=0; }
                fprintf(f,"  %04X %-2s %4u %4u %4u %4u  %5.1fx%-5.1f x%u\n",g.token,shown,g.texels[0],g.texels[1],g.texels[2],g.texels[3],g.size[0],g.size[1],g.count);
            }
        }
        fclose(f);
        return true;
    }
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
            for (auto& p:e.samples)
                fprintf(f,"      %-12s %-7s at %7.1f,%7.1f size %6.1fx%-6.1f uv %7.3f,%7.3f to %7.3f,%7.3f colour %08X x%u\n",p.window,TexturePartNames[p.part],
                    p.rect[0],p.rect[1],p.rect[2]-p.rect[0],p.rect[3]-p.rect[1],p.uv[0],p.uv[1],p.uv[2],p.uv[3],p.colour,p.count);
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
static inline bool TextureVertices(const void* data,unsigned count,unsigned stride,uint32_t fvf,float* uv,uint32_t* colour,bool& hasColour) {
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

// A draw's pieces (every group vertices of it: 6 for a list of triangles, 4 for indexed quads or a strip), each with
// its place on the screen and the texture places at its top-left and bottom-right vertices, given to piece()
template<class Piece> static void TexturePieces(const void* data,unsigned count,unsigned stride,uint32_t fvf,unsigned group,Piece piece) {
    if (!data || !group || (fvf & D3DFVF_POSITION_MASK)!=D3DFVF_XYZRHW) return;
    unsigned at=16; const bool diffuse=(fvf & D3DFVF_DIFFUSE)!=0;
    if (diffuse) at+=4;
    if (fvf & D3DFVF_SPECULAR) at+=4;
    if (((fvf & D3DFVF_TEXCOUNT_MASK)>>D3DFVF_TEXCOUNT_SHIFT)<1 || stride<at+8) return;
    const auto* bytes=static_cast<const uint8_t*>(data);
    for (unsigned first=0;first+group<=count && first<group*1024;first+=group) {
        float rect[4]={},uv[4]={}; float low=0,high=0; uint32_t colour=0;
        for (unsigned i=first;i<first+group;i++) {
            float v[2],t[2]; memcpy(v,bytes+size_t(i)*stride,sizeof(v)); memcpy(t,bytes+size_t(i)*stride+at,sizeof(t));
            if (!std::isfinite(v[0]) || !std::isfinite(v[1]) || !std::isfinite(t[0]) || !std::isfinite(t[1])) return;
            if (i==first) { rect[0]=rect[2]=v[0]; rect[1]=rect[3]=v[1]; low=high=v[0]+v[1]; uv[0]=uv[2]=t[0]; uv[1]=uv[3]=t[1]; if (diffuse) memcpy(&colour,bytes+size_t(i)*stride+16,4); continue; }
            rect[0]=(std::min)(rect[0],v[0]); rect[1]=(std::min)(rect[1],v[1]); rect[2]=(std::max)(rect[2],v[0]); rect[3]=(std::max)(rect[3],v[1]);
            if (v[0]+v[1]<low) { low=v[0]+v[1]; uv[0]=t[0]; uv[1]=t[1]; }
            if (v[0]+v[1]>high) { high=v[0]+v[1]; uv[2]=t[0]; uv[3]=t[1]; }
        }
        piece(rect,uv,colour);
    }
}
