// /uihook skin as it draws: the game's textures drawn with a skin's pictures in their place (skin.h), the skin's fonts
// drawn again in the fonts chosen (skinfont.h), its pictures read from config\uihook\skins\<name> (skinfile.h).
// One of the party module's parts: it calls Begin and End about each of the game's draws.
#pragma once
#include <string>
#include <vector>
#include <algorithm>
#include <cmath>
#include "../../drawcontext.h"
#include "../census/labels.h"
#include "native.h"
#include "skin.h"
#include "skinfile.h"
#include "skinfont.h"

class SkinModule {
public:
    SkinLook look;
    DrawContext* ctx=nullptr;
    const NativeLook* native=nullptr;  // the scale the window being drawn is drawn at, for a picture of the size to suit
    void Init(DrawContext* context,const NativeLook* nativeLook) { ctx=context; native=nativeLook; }
    // uihook unloaded: every picture and font let go
    void Unload() { Release(); look.name[0]=0; skinFace[0].Close(); skinFace[1].Close(); }
    // A moved draw's vertices (the native look's copy) given the colours the skin gives the picture in stage 0 for the
    // draw under way, as End would have given them had it drawn it; false where it has none
    bool RecolourActive(std::vector<uint8_t>& vertices,unsigned count,unsigned stride,DWORD fvf) {
        if (skinActive<0 || !SkinRecolour(look.textures[size_t(skinActive)],vertices.data(),count,stride,fvf,skinVertices)) return false;
        vertices.swap(skinVertices); look.textures[size_t(skinActive)].recoloured++;
        return true;
    }
    // /uihook skin: a screen-space draw whose texture (stage 0) the skin has a picture for is given it; what was there
    // comes back to be put back by End. Nothing where no skin is loaded.
    struct SkinSwap { int32_t index=-1; IDirect3DBaseTexture8* was=nullptr; DWORD filters[3]={}; bool clamped=false; DWORD address[2]={}; };
    // stage 0's filters while a skin's picture is in it: linear, with its levels, so one made larger than it is
    // drawn shrinks smoothly and one drawn larger is not blocky
    static constexpr D3DTEXTURESTAGESTATETYPE SkinFilters[3]={D3DTSS_MAGFILTER,D3DTSS_MINFILTER,D3DTSS_MIPFILTER};
    int32_t skinActive=-1;   // the skin's picture in stage 0 for the draw under way, for RecolourActive, or -1
    // The game's windows as the party module hears them (Window::Render): windowsHeard while its detour is in, and
    // windowDepth the windows being drawn now; a font's texture drawn in none left as the game's (SkinLeftOutside)
    bool windowsHeard=false;
    unsigned windowDepth=0;
    uint32_t fontsLeft=0;    // font draws left as the game's, outside any window, for the status
    // data, count, stride: the draw's vertices (from memory), to tell how large its texels are drawn; none from a
    // vertex buffer, drawn with the size suiting the window's scale
    SkinSwap Begin(const void* data=nullptr,unsigned count=0,unsigned stride=0) {
        SkinSwap swap;
        if (!look.On()) return swap;
        auto* device=ctx->Device(); DWORD fvf=0;
        if (!device || !ctx->DrawFvf(fvf) || (fvf & D3DFVF_POSITION_MASK)!=D3DFVF_XYZRHW) return swap;
        if (FAILED(device->GetTexture(0,&swap.was)) || !swap.was) { swap.was=nullptr; return swap; }
        IDirect3DBaseTexture8* game=swap.was;
        swap.index=look.Lookup(reinterpret_cast<uintptr_t>(game),ctx->Frame(),[&](uint32_t& hash) {
            LabelPixels pixels; D3DSURFACE_DESC desc{}; uint32_t texels[4]; const char* why="";
            static const float whole[4]={0,0,1,1};
            if (!LabelCut(game,whole,pixels,desc,texels,why)) return false;
            hash=TextureHash(pixels,desc.Width,desc.Height); return true;
        });
        if (swap.index>=0 && SkinLeftOutside(windowsHeard,windowDepth,skinFonts.Has(look.textures[size_t(swap.index)].hash))) { fontsLeft++; swap.index=-1; }
        if (swap.index<0) { swap.was->Release(); swap.was=nullptr; return swap; }
        const SkinTexture& t=look.textures[size_t(swap.index)];
        bool exact=false,levels=false;
        const SkinSize* size=SkinLook::Choose(t,Pixels(t,data,count,stride,fvf),exact,&levels);
        if (size && size->stale) DrawSize(t.hash,const_cast<SkinSize&>(*size));
        device->SetTexture(0,static_cast<IDirect3DBaseTexture8*>(size ? size->texture : t.texture));
        // a texel to a pixel: unfiltered, crisp; any other: filtered, with the levels between only where much smaller
        const DWORD filter=exact ? DWORD(D3DTEXF_POINT) : DWORD(D3DTEXF_LINEAR);
        const DWORD filters[3]={filter,filter,levels ? DWORD(D3DTEXF_LINEAR) : DWORD(D3DTEXF_NONE)};
        for (int i=0;i<3;i++) { device->GetTextureStageState(0,SkinFilters[i],&swap.filters[i]); device->SetTextureStageState(0,SkinFilters[i],filters[i]); }
        // a draw within its texture (not tiled across it, as the frame's edges are) clamped at the texture's edges:
        // filtered, a piece at its edge took in the far side wrapped round (a clear column where two button bars meet)
        if (Within(data,count,stride,fvf)) {
            swap.clamped=true;
            device->GetTextureStageState(0,D3DTSS_ADDRESSU,&swap.address[0]); device->GetTextureStageState(0,D3DTSS_ADDRESSV,&swap.address[1]);
            device->SetTextureStageState(0,D3DTSS_ADDRESSU,D3DTADDRESS_CLAMP); device->SetTextureStageState(0,D3DTSS_ADDRESSV,D3DTADDRESS_CLAMP);
        }
        skinActive=swap.index;
        return swap;
    }
    // Whether every texture place of a draw lies within its texture (0 to 1 each way); false where they are not to hand
    static bool Within(const void* data,unsigned count,unsigned stride,DWORD fvf) {
        if (!data || !count || (fvf & D3DFVF_POSITION_MASK)!=D3DFVF_XYZRHW) return false;
        unsigned at=16; if (fvf & D3DFVF_DIFFUSE) at+=4; if (fvf & D3DFVF_SPECULAR) at+=4;
        if (((fvf & D3DFVF_TEXCOUNT_MASK)>>D3DFVF_TEXCOUNT_SHIFT)<1 || stride<at+8) return false;
        const auto* bytes=static_cast<const uint8_t*>(data);
        for (unsigned i=0;i<count;i++) {
            float t[2]; memcpy(t,bytes+size_t(i)*stride+at,8);
            if (!(t[0]>=-0.001f && t[0]<=1.001f && t[1]>=-0.001f && t[1]<=1.001f)) return false;
        }
        return true;
    }
    // How many pixels a texel of a picture's first size covers in this draw: along its first triangle's longer side
    // on the screen, as the window is drawn (its scale); the window's scale alone where the vertices are not to hand
    float Pixels(const SkinTexture& t,const void* data,unsigned count,unsigned stride,DWORD fvf) const {
        const float k=(native ? native->ScaleNow() : 1.0f);
        if (!data || count<3 || t.sizes.empty() || (fvf & D3DFVF_POSITION_MASK)!=D3DFVF_XYZRHW) return k;
        unsigned at=16; if (fvf & D3DFVF_DIFFUSE) at+=4; if (fvf & D3DFVF_SPECULAR) at+=4;
        if (((fvf & D3DFVF_TEXCOUNT_MASK)>>D3DFVF_TEXCOUNT_SHIFT)<1 || stride<at+8) return k;
        const auto* bytes=static_cast<const uint8_t*>(data);
        float lo[4]={1e9f,1e9f,1e9f,1e9f},hi[4]={-1e9f,-1e9f,-1e9f,-1e9f};
        for (unsigned i=0;i<3;i++) {
            float v[4]; memcpy(v,bytes+size_t(i)*stride,8); memcpy(v+2,bytes+size_t(i)*stride+at,8);
            for (int j=0;j<4;j++) { lo[j]=(std::min)(lo[j],v[j]); hi[j]=(std::max)(hi[j],v[j]); }
        }
        const SkinSize& first=t.sizes.front();
        const float dx=hi[0]-lo[0],dy=hi[1]-lo[1],du=(hi[2]-lo[2])*float(first.width),dv=(hi[3]-lo[3])*float(first.height);
        if (dx>=dy && du>0.5f) return dx*k/du;
        if (dv>0.5f) return dy*k/dv;
        return k;
    }
    // A draw's vertices from memory with the colours the skin's skin.txt gives its picture, or as they were
    std::vector<uint8_t> skinVertices;
    const void* Vertices(const SkinSwap& swap,const void* data,unsigned count,unsigned stride) {
        SkinTexture& t=look.textures[size_t(swap.index)];
        auto* device=ctx->Device(); DWORD fvf=0;
        if (t.colours.empty() || count>65536 || !device || !ctx->DrawFvf(fvf) || !SkinRecolour(t,data,count,stride,fvf,skinVertices)) return data;
        t.recoloured++;
        return skinVertices.data();
    }
    // The draw made with the skin's picture, unless done already (blocked, or drawn moved), and the game's texture
    // put back. True where it was drawn here; false (the game's own then drawn by Ashita) where the draw failed.
    template<class Draw> bool End(const SkinSwap& swap,bool done,Draw draw) {
        skinActive=-1;
        if (swap.index<0) return done;
        auto* device=ctx->Device();
        bool ok=done;
        if (!done) {
            ctx->scaling=true; ok=SUCCEEDED(draw(device)); ctx->scaling=false;
            if (ok) look.textures[size_t(swap.index)].drawn++;
        }
        for (int i=0;i<3;i++) device->SetTextureStageState(0,SkinFilters[i],swap.filters[i]);
        if (swap.clamped) { device->SetTextureStageState(0,D3DTSS_ADDRESSU,swap.address[0]); device->SetTextureStageState(0,D3DTSS_ADDRESSV,swap.address[1]); }
        device->SetTexture(0,swap.was); swap.was->Release();
        return ok;
    }
    // config\uihook\skins\<name>\tex-<hash>.png or .bmp, each made a texture of its own
    void Release() { for (void* t:look.Clear()) static_cast<IDirect3DTexture8*>(t)->Release(); skinFonts.Clear(); }
    // A picture written to its texture, every level down to a texel, each the one above halved (SkinHalve): a picture
    // larger than it is drawn shrinks smoothly, drawn with the levels between
    static bool Upload(IDirect3DTexture8* texture,std::vector<uint32_t> argb,uint32_t width,uint32_t height) {
        uint32_t w=width,h=height;
        for (DWORD level=0;level<texture->GetLevelCount();level++) {
            D3DLOCKED_RECT locked;
            if (FAILED(texture->LockRect(level,&locked,nullptr,0))) return false;
            for (uint32_t y=0;y<h;y++) memcpy(static_cast<uint8_t*>(locked.pBits)+size_t(y)*locked.Pitch,argb.data()+size_t(y)*w,size_t(w)*4);
            texture->UnlockRect(level);
            if (w>1 || h>1) SkinHalve(argb,w,h);
        }
        return true;
    }
    // The skin's fonts (fonts.txt), and the font file chosen for each kind (menu, title), "" for the skin's own
    SkinFonts skinFonts;
    std::string skinFontFile[2];
    SkinFontFace skinFace[2];
    int skinFontWeight[2]={0,0};                       // FW_* or 0 for the file's own
    int skinOutline[2]={1,1};                          // pixels of winxi's outline about a chosen font's letters
    uint32_t skinOutlineColour[2]={0xE6000000,0xE6000000};
    // A font file's path: as given where it is one, else in Windows' Fonts folder
    static std::string FontPath(const std::string& file) {
        if (file.find('\\')!=std::string::npos || file.find(':')!=std::string::npos) return file;
        char windows[MAX_PATH]={}; GetWindowsDirectoryA(windows,MAX_PATH);
        return std::string(windows)+"\\Fonts\\"+file;
    }
    // Each font texture of the skin to be drawn again: its glyphs in the font chosen for its kind, or the skin's own
    // picture where none is chosen or it cannot be drawn. Each size is drawn the first time a draw is made with it
    // (DrawSize, from Begin), not here: both fonts at every size took 340 ms or more, and most sizes are not
    // drawn with at all at one Menu Scale. Returns the sizes to draw. kinds: which kinds' textures (1 menu, 2 title).
    unsigned ApplyFonts(std::string* why=nullptr,unsigned kinds=3) {
        unsigned drawn=0;
        for (int k=0;k<2;k++) {
            if (skinFontFile[k].empty()) { skinFace[k].Close(); continue; }
            const std::string path=FontPath(skinFontFile[k]);
            if (skinFace[k].path!=SkinWide(path.c_str()) || !skinFace[k].added)
                if (!skinFace[k].Open(path.c_str()) && why) *why+=(why->empty() ? "" : "; ")+path+" could not be opened";
            skinFace[k].Weight(skinFontWeight[k]);
        }
        // each texture holding fonts once (one may hold several: the menus' small font and a large one)
        std::vector<uint32_t> done;
        for (auto& style:skinFonts.styles) {
            const int kind=SkinFontKind(style.kind);
            if (kind<0 || !(kinds & (1u<<kind)) || std::find(done.begin(),done.end(),style.hash)!=done.end()) continue;
            done.push_back(style.hash);
            const int32_t at=look.Find(style.hash);
            if (at<0) continue;
            for (auto& z:look.textures[size_t(at)].sizes)
                if (!z.base.empty() && z.texture) { z.stale=true; drawn++; }
        }
        return drawn;
    }
    // A font texture's size drawn again, as ApplyFonts asked: its own pixels, the glyphs of each font in it with a
    // face chosen drawn on them, its levels made
    void DrawSize(uint32_t hash,SkinSize& z) {
        z.stale=false;
        if (z.base.empty() || !z.texture) return;
        std::vector<uint32_t> argb=z.base;
        SkinFontDrawer drawer;
        for (int k=0;k<2;k++) {
            drawer.faces[k]=!skinFontFile[k].empty() && skinFace[k].added ? &skinFace[k] : nullptr;
            drawer.outline[k]=skinOutline[k]; drawer.outlineColour[k]=skinOutlineColour[k];
        }
        drawer.Draw(skinFonts,hash,z.factor,argb,int(z.width),int(z.height));
        Upload(static_cast<IDirect3DTexture8*>(z.texture),argb,z.width,z.height);
    }
    void Load(const char* name,char* line,size_t size) {
        for (const char* c=name;*c;c++) if (!isalnum(static_cast<unsigned char>(*c)) && *c!='_' && *c!='-') {
            snprintf(line,size,"[uihook:skin] a skin's name is letters, digits, - and _."); return;
        }
        auto* device=ctx->Device();
        if (!device) { snprintf(line,size,"[uihook:skin] no device yet."); return; }
        const std::string folder=std::string(ctx->core->GetInstallPath())+"\\config\\uihook\\skins\\"+name;
        Release();
        // the glyph map first, so the font pictures' own pixels are kept to draw the glyphs on again
        bool hasFonts=false;
        if (FILE* f=fopen((folder+"\\fonts.txt").c_str(),"rb")) {
            std::string text; char chunk[4096]; size_t n;
            while ((n=fread(chunk,1,sizeof(chunk),f))>0 && text.size()<(1u<<20)) text.append(chunk,n);
            fclose(f);
            skinFonts.Parse(text.c_str()); hasFonts=!skinFonts.styles.empty();
        }
        WIN32_FIND_DATAA found; unsigned failed=0;
        HANDLE find=FindFirstFileA((folder+"\\tex-*").c_str(),&found);
        if (find!=INVALID_HANDLE_VALUE) {
            do {
                uint32_t hash=0; float factor=1;
                if ((found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) || !SkinLook::FileHash(found.cFileName,hash,&factor)) continue;
                const int32_t had=look.Find(hash);
                bool same=false;
                if (had>=0) for (auto& z:look.textures[size_t(had)].sizes) same|=fabsf(z.factor-factor)<0.001f;
                if (same) continue;
                uint32_t width=0,height=0; std::vector<uint32_t> argb;
                IDirect3DTexture8* texture=nullptr;
                if (!SkinReadPicture((folder+"\\"+found.cFileName).c_str(),width,height,argb)
                    || FAILED(device->CreateTexture(width,height,0,0,D3DFMT_A8R8G8B8,D3DPOOL_MANAGED,&texture))) { failed++; continue; }
                if (!Upload(texture,argb,width,height)) { texture->Release(); failed++; continue; }
                SkinSize size; size.factor=factor; size.width=width; size.height=height; size.texture=texture;
                if (hasFonts && skinFonts.Has(hash)) size.base=std::move(argb);
                if (had>=0) SkinLook::AddSize(look.textures[size_t(had)],size);
                else { SkinTexture t; t.hash=hash; SkinLook::AddSize(t,size); look.textures.push_back(t); }
            } while (FindNextFileA(find,&found));
            FindClose(find);
        }
        snprintf(look.name,sizeof(look.name),"%s",name);
        unsigned unread=0; bool colours=false;
        if (FILE* f=fopen((folder+"\\skin.txt").c_str(),"rb")) {
            std::string text; char chunk[4096]; size_t n;
            while ((n=fread(chunk,1,sizeof(chunk),f))>0 && text.size()<65536) text.append(chunk,n);
            fclose(f); colours=true;
            unread=SkinColours(look.textures,text.c_str());
        }
        // a font chosen before (by nativeui, or by hand) drawn into the skin's font pictures
        std::string why;
        const unsigned glyphs=hasFonts ? ApplyFonts(&why) : 0;
        if (look.textures.empty()) snprintf(line,size,"[uihook:skin] no pictures read in %s (tex-<hash>.png or .bmp)%s.",folder.c_str(),failed ? ", some could not be read" : "");
        else snprintf(line,size,"[uihook:skin] %s: %zu pictures loaded%s%s%s%s%s; the game's textures are known as they are drawn.",name,look.textures.size(),
            failed ? ", some could not be read" : "",colours ? ", skin.txt read" : "",unread ? " (some of its lines not understood, or of no picture)" : "",
            hasFonts ? (glyphs ? ", its fonts to be drawn in the fonts chosen as they are used" : ", fonts.txt read") : "",why.empty() ? "" : (" ("+why+")").c_str());
    }
    void Command(const char* word) {
        char line[512];
        // font <menu|title> <file|off> [regular|bold] [outline=<pixels>] [outlinecolour=<AARRGGBB>] [quiet]: the font a
        // kind of the skin's fonts is drawn in (in winxi's look, its weight and outline as given), off its own
        if (!_strnicmp(word,"font ",5) || !_stricmp(word,"font")) {
            char kind[16]={},file[MAX_PATH]={},more[4][32]={};
            const int n=sscanf_s(word+4," %15s %259s %31s %31s %31s %31s",kind,16u,file,unsigned(MAX_PATH),more[0],32u,more[1],32u,more[2],32u,more[3],32u);
            const int k=n>=1 ? SkinFontKind(kind) : -1;
            bool quietly=false;
            int weightWas=0,outlineWas=0; uint32_t colourWas=0;
            if (k>=0) {
                weightWas=skinFontWeight[k]; outlineWas=skinOutline[k]; colourWas=skinOutlineColour[k];
                skinFontWeight[k]=0;
                for (int i=0;i<4 && i+2<n;i++) {
                    if (!_stricmp(more[i],"quiet")) quietly=true;
                    else if (!_stricmp(more[i],"bold")) skinFontWeight[k]=FW_BOLD;
                    else if (!_stricmp(more[i],"regular")) skinFontWeight[k]=FW_NORMAL;
                    else if (!_strnicmp(more[i],"outline=",8)) skinOutline[k]=(std::max)(0,(std::min)(4,atoi(more[i]+8)));
                    else if (!_strnicmp(more[i],"outlinecolour=",14)) skinOutlineColour[k]=static_cast<uint32_t>(strtoul(more[i]+14,nullptr,16));
                }
            }
            if (k<0 || n<2) {
                snprintf(line,sizeof(line),"[uihook:skin] fonts: menu %s, title %s. /uihook skin font <menu|title> <file in C:\\Windows\\Fonts, or off>.",
                    skinFontFile[0].empty() ? "the skin's own" : skinFontFile[0].c_str(),skinFontFile[1].empty() ? "the skin's own" : skinFontFile[1].c_str());
                ctx->core->GetChatManager()->Write(0,false,line);
                return;
            }
            const std::string chosen=_stricmp(file,"off") ? file : "";
            // as it was (nativeui gives it again as the theme is looked at): nothing drawn again
            const bool same=chosen==skinFontFile[k] && skinFontWeight[k]==weightWas && skinOutline[k]==outlineWas && skinOutlineColour[k]==colourWas;
            skinFontFile[k]=chosen;
            std::string why;
            const unsigned glyphs=same ? 0 : ApplyFonts(&why,1u<<k);
            if (same && quietly) return;
            if (quietly && why.empty()) return;
            if (skinFontFile[k].empty()) snprintf(line,sizeof(line),"[uihook:skin] the %s font: the skin's own.",kind);
            else if (!skinFonts.styles.size()) snprintf(line,sizeof(line),"[uihook:skin] the %s font is %s, drawn once a skin with a fonts.txt is loaded.",kind,file);
            else snprintf(line,sizeof(line),"[uihook:skin] the %s font: %s, drawn as each of %u sizes is used%s%s.",kind,file,glyphs,why.empty() ? "" : "; ",why.c_str());
            ctx->core->GetChatManager()->Write(0,false,line);
            return;
        }
        if (!_stricmp(word,"off")) {
            const size_t n=look.textures.size(); Release(); look.name[0]=0;
            snprintf(line,sizeof(line),n ? "[uihook:skin] off; the game's own textures." : "[uihook:skin] no skin loaded.");
        } else if (!_stricmp(word,"reload")) {
            if (!look.name[0]) snprintf(line,sizeof(line),"[uihook:skin] no skin to reload: /uihook skin <name>.");
            else { char name[64]; snprintf(name,sizeof(name),"%s",look.name); Load(name,line,sizeof(line)); }
        } else if (word[0]) Load(word,line,sizeof(line));
        else if (!look.On()) snprintf(line,sizeof(line),"[uihook:skin] none loaded. /uihook skin <name> loads config\\uihook\\skins\\<name>\\; reload, off.");
        else {
            unsigned matched=0; uint32_t drawn=0,recoloured=0;
            for (auto& t:look.textures) { if (t.matched) matched++; drawn+=t.drawn; recoloured+=t.recoloured; }
            snprintf(line,sizeof(line),"[uihook:skin] %s: %zu pictures, %u found in the game's textures (%u read), %u draws made with them, %u of them recoloured; %u font draws in no window (the names) left as the game's%s.",
                look.name,look.textures.size(),matched,look.read,drawn,recoloured,fontsLeft,windowsHeard ? "" : " (the windows are not heard: every font draw skinned)");
            ctx->core->GetChatManager()->Write(0,false,line);
            std::string unseen;
            for (auto& t:look.textures) if (!t.matched) { char h[12]; snprintf(h,sizeof(h)," %08X",t.hash); unseen+=h; }
            if (unseen.empty()) return;
            snprintf(line,sizeof(line),"[uihook:skin] not drawn by the game yet:%s",unseen.substr(0,400).c_str());
        }
        ctx->core->GetChatManager()->Write(0,false,line);
    }
};
