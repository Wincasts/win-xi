// The skin: the game's own interface drawn with other pictures in place of its textures, every menu at once. A skin
// is a folder of pictures, each named for the game texture it stands for as the texture census names them
// (tex-<hash>.png or .bmp), any size: a draw's texture places are a share of the texture, so one twice the size is
// drawn twice as fine. The game's layout, input and every draw's place are its own; only stage 0's texture is
// changed for the draw, and put back after it.
//
//   /uihook skin <name>     config\uihook\skins\<name>\ loaded and drawn
//   /uihook skin reload     the same again, as its pictures are changed
//   /uihook skin off        the game's own textures
//   /uihook skin            what is loaded, and how much of it the game has drawn
//
// The game colours some of its art by the vertices (a button bar blue-grey or orange, each the same texture), so a
// skin may say what those colours are to be drawn as, in skin.txt beside its pictures, a line each:
//
//   <hash> <RRGGBB or *> <RRGGBB>     e.g. 9E2854A3 616180 363650: a draw with that texture, its vertices of the
//                                     game's colour (any, for *) drawn in the other; their alpha the game's
//   <hash> <RRGGBB or *> <AARRGGBB>   the same, their alpha this one: the game fades its frame by its vertices'
//                                     alpha (its sides near 0, its top and bottom 0x61), so a frame even all round
//                                     sets one
//
// The first line that fits a vertex is used. Only for a draw from memory (a vertex buffer's are drawn as they are).
//
// A game texture is known by its pixels, read the first time its pointer is seen in a screen-space draw (and again
// where it has not been seen for a while, as the game may have made another there).
#pragma once
#include <stdint.h>
#include <string.h>
#include <vector>
#include <cmath>
#include "../mirror/textures.h"

#define SKIN_POINTERS 4096
#define SKIN_ANY 0xffffffffu

struct SkinColour { uint32_t from=SKIN_ANY, to=0; bool alpha=false; };    // RGB, or SKIN_ANY for every colour; alpha: to's own, not the game's

// One size of a picture: tex-<hash>.png is the game's size, tex-<hash>@<factor>.png that many times it
// base: the file's pixels, kept for a font's picture, to draw its glyphs again on; stale: its glyphs to be drawn again
// (in the fonts chosen) before it is next drawn with
struct SkinSize { float factor=1; uint32_t width=0, height=0; void* texture=nullptr; std::vector<uint32_t> base; bool stale=false; };

struct SkinTexture {
    uint32_t hash=0, width=0, height=0;
    void* texture=nullptr;      // the picture as a texture, the device's to draw with (its first size)
    std::vector<SkinSize> sizes;   // every size of it, smallest first
    uint32_t drawn=0;           // draws made with it in the game's place
    unsigned matched=0;         // game textures found with its pixels
    std::vector<SkinColour> colours;
    uint32_t recoloured=0;      // draws whose vertices' colours were changed
};

// A draw's vertices with their colours as the skin's picture says, in out (the whole of data, count vertices of
// stride); false where none is changed or the vertices have no colour
static bool SkinRecolour(const SkinTexture& t,const void* data,unsigned count,unsigned stride,uint32_t fvf,std::vector<uint8_t>& out) {
    if (t.colours.empty() || !data || !count || !(fvf & D3DFVF_DIFFUSE) || (fvf & D3DFVF_POSITION_MASK)!=D3DFVF_XYZRHW || stride<20) return false;
    const auto* bytes=static_cast<const uint8_t*>(data);
    bool changed=false;
    for (unsigned i=0;i<count;i++) {
        uint32_t c; memcpy(&c,bytes+size_t(i)*stride+16,4);
        for (auto& m:t.colours) {
            if (m.from!=SKIN_ANY && m.from!=(c&0xffffff)) continue;
            const uint32_t to=m.alpha ? m.to : (c&0xff000000) | (m.to&0xffffff);
            if (to!=c) {
                if (!changed) { out.assign(bytes,bytes+size_t(count)*stride); changed=true; }
                memcpy(out.data()+size_t(i)*stride+16,&to,4);
            }
            break;
        }
    }
    return changed;
}
// skin.txt's lines given to the skin's pictures; returns the lines not understood or of no picture loaded
static unsigned SkinColours(std::vector<SkinTexture>& textures,const char* text) {
    unsigned bad=0;
    while (text && *text) {
        const char* end=strchr(text,'\n'); const size_t length=end ? size_t(end-text) : strlen(text);
        char line[128]={}; memcpy(line,text,length<sizeof(line)-1 ? length : sizeof(line)-1);
        text=end ? end+1 : nullptr;
        if (char* hash=strchr(line,'#')) *hash=0;
        char a[16]={},b[16]={},c[16]={};
        const int n=sscanf_s(line,"%15s %15s %15s",a,16u,b,16u,c,16u);
        if (n<=0) continue;
        char* stop=nullptr; uint32_t hash=0,from=SKIN_ANY,to=0; bool ok=n==3;
        if (ok) { hash=strtoul(a,&stop,16); ok=*stop==0 && strlen(a)==8; }
        if (ok && strcmp(b,"*")) { from=strtoul(b,&stop,16); ok=*stop==0 && strlen(b)==6; }
        if (ok) { to=strtoul(c,&stop,16); ok=*stop==0 && (strlen(c)==6 || strlen(c)==8); }
        SkinTexture* t=nullptr;
        if (ok) for (auto& x:textures) if (x.hash==hash) t=&x;
        if (!t) { bad++; continue; }
        SkinColour colour; colour.from=from; colour.to=to; colour.alpha=strlen(c)==8; t->colours.push_back(colour);
    }
    return bad;
}

class SkinLook {
public:
    std::vector<SkinTexture> textures;
    struct Pointer { uintptr_t texture; uint32_t seen; int32_t index; };
    std::vector<Pointer> pointers;
    char name[64]={};
    uint32_t read=0;            // game textures read to be known

    bool On() const { return !textures.empty(); }
    int32_t Find(uint32_t hash) const {
        for (size_t i=0;i<textures.size();i++) if (textures[i].hash==hash) return int32_t(i);
        return -1;
    }
    bool Ours(uintptr_t texture) const {
        for (auto& t:textures) {
            if (reinterpret_cast<uintptr_t>(t.texture)==texture) return true;
            for (auto& z:t.sizes) if (reinterpret_cast<uintptr_t>(z.texture)==texture) return true;
        }
        return false;
    }
    // A size of a picture: kept smallest first, the first its texture
    static void AddSize(SkinTexture& t,const SkinSize& size) {
        auto at=t.sizes.begin();
        while (at!=t.sizes.end() && at->factor<size.factor) ++at;
        t.sizes.insert(at,size);
        t.texture=t.sizes.front().texture; t.width=t.sizes.front().width; t.height=t.sizes.front().height;
    }
    // The size to draw with where a texel of its first size covers pixels pixels on the screen, and how: a size whose
    // texels are the pixels (density, texels a pixel, within 3% of 1) unfiltered (exact), crisp, nothing of a
    // neighbour's in the texture blurred into a piece's edge (the frame, the buttons); else the smallest at least
    // about twice as fine (1.9), filtered without its levels (levels: false), which is how the menu font, drawn at
    // half its texture, is sharpest (a size a texel to 1.05 pixels came out unevenly spaced, and the levels
    // between, at twice as fine, blurred); the levels only for one shrunk further than 2.6 times, or the largest
    static const SkinSize* Choose(const SkinTexture& t,float pixels,bool& exact,bool* levels=nullptr) {
        exact=false;
        if (levels) *levels=false;
        if (t.sizes.empty()) return nullptr;
        auto density=[&](const SkinSize& z) { return pixels>0 ? z.factor/t.sizes.front().factor/pixels : 1.0f; };
        for (auto& z:t.sizes) if (fabsf(density(z)-1)<0.03f) { exact=true; return &z; }
        const SkinSize* best=&t.sizes.back();
        for (auto& z:t.sizes) if (density(z)>=1.9f) { best=&z; break; }
        if (levels) *levels=density(*best)>2.6f;
        return best;
    }
    // The skin's picture for a game texture, or -1. read(hash&) gives its pixels' hash, false where it cannot be read;
    // called only for a pointer not seen lately.
    // the last pointer looked up, and what it was, this frame: draws one after another are mostly of one texture
    uintptr_t lastTexture=0; uint32_t lastFrame=0; int32_t lastIndex=-1;
    template<class Read> int32_t Lookup(uintptr_t texture,uint32_t frame,Read readHash) {
        if (!texture || textures.empty()) return -1;
        if (texture==lastTexture && frame==lastFrame) return lastIndex;
        lastTexture=texture; lastFrame=frame; lastIndex=Find(texture,frame,readHash);
        return lastIndex;
    }
    template<class Read> int32_t Find(uintptr_t texture,uint32_t frame,Read readHash) {
        if (Ours(texture)) return -1;
        for (auto& p:pointers) if (p.texture==texture) {
            if (frame-p.seen<=TEXTURE_STALE) { p.seen=frame; return p.index; }
            p.seen=frame; p.index=Known(readHash); return p.index;
        }
        if (pointers.size()>=SKIN_POINTERS) {   // the one longest unseen made room for it
            size_t oldest=0;
            for (size_t i=1;i<pointers.size();i++) if (frame-pointers[i].seen>frame-pointers[oldest].seen) oldest=i;
            pointers.erase(pointers.begin()+ptrdiff_t(oldest));
        }
        const int32_t index=Known(readHash);
        pointers.push_back({texture,frame,index});
        return index;
    }
    // Every texture forgotten; textures come back for the caller to release
    std::vector<void*> Clear() {
        std::vector<void*> held;
        for (auto& t:textures) {
            for (auto& z:t.sizes) if (z.texture) held.push_back(z.texture);
            if (t.sizes.empty() && t.texture) held.push_back(t.texture);
        }
        textures.clear(); pointers.clear(); read=0; lastTexture=0; lastIndex=-1;
        return held;
    }
    // A picture's name, tex-<eight hex digits>[@<factor>].png or .bmp, as its hash and size (1 without); false for any other
    static bool FileHash(const char* file,uint32_t& hash,float* factor=nullptr) {
        if (_strnicmp(file,"tex-",4)) return false;
        hash=0;
        for (int i=0;i<8;i++) {
            const char c=file[4+i]; uint32_t v;
            if (c>='0' && c<='9') v=uint32_t(c-'0'); else if (c>='a' && c<='f') v=uint32_t(c-'a'+10); else if (c>='A' && c<='F') v=uint32_t(c-'A'+10); else return false;
            hash=hash<<4 | v;
        }
        const char* rest=file+12; float f=1;
        if (*rest=='@') {
            char* end=nullptr; f=strtof(rest+1,&end);
            if (!end || end==rest+1 || !(f>=0.25f && f<=8)) return false;
            rest=end;
        }
        if (factor) *factor=f;
        return !_stricmp(rest,".png") || !_stricmp(rest,".bmp");
    }
private:
    template<class Read> int32_t Known(Read readHash) {
        uint32_t hash=0; read++;
        if (!readHash(hash)) return -1;
        const int32_t index=Find(hash);
        if (index>=0) textures[size_t(index)].matched++;
        return index;
    }
};
