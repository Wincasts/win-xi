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
#include "../mirror/textures.h"

#define SKIN_POINTERS 4096
#define SKIN_ANY 0xffffffffu

struct SkinColour { uint32_t from=SKIN_ANY, to=0; bool alpha=false; };    // RGB, or SKIN_ANY for every colour; alpha: to's own, not the game's

struct SkinTexture {
    uint32_t hash=0, width=0, height=0;
    void* texture=nullptr;      // the picture as a texture, the device's to draw with
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
        for (auto& t:textures) if (reinterpret_cast<uintptr_t>(t.texture)==texture) return true;
        return false;
    }
    // The skin's picture for a game texture, or -1. read(hash&) gives its pixels' hash, false where it cannot be read;
    // called only for a pointer not seen lately.
    template<class Read> int32_t Lookup(uintptr_t texture,uint32_t frame,Read readHash) {
        if (!texture || textures.empty() || Ours(texture)) return -1;
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
        for (auto& t:textures) if (t.texture) held.push_back(t.texture);
        textures.clear(); pointers.clear(); read=0;
        return held;
    }
    // A picture's name, tex-<eight hex digits>.png or .bmp, as its hash; false for any other
    static bool FileHash(const char* file,uint32_t& hash) {
        if (_strnicmp(file,"tex-",4)) return false;
        hash=0;
        for (int i=0;i<8;i++) {
            const char c=file[4+i]; uint32_t v;
            if (c>='0' && c<='9') v=uint32_t(c-'0'); else if (c>='a' && c<='f') v=uint32_t(c-'a'+10); else if (c>='A' && c<='F') v=uint32_t(c-'A'+10); else return false;
            hash=hash<<4 | v;
        }
        return !_stricmp(file+12,".png") || !_stricmp(file+12,".bmp");
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
