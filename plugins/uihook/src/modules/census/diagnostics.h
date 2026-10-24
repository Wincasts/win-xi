// The tools used to find out how the game draws its menus, kept apart from what changes its drawing:
//   /uihook census on|off|dump|clear        every window drawn and the text it prints (census.h)
//   /uihook textures on|off|dump|clear      every texture the screen-space drawing uses, by window and part (textures.h)
// One of the party module's parts: it hears the window hooks (window.h) and the draws the native look hears.
//
// Built only with ./build.sh --diagnostics (UIHOOK_DIAGNOSTICS=1). Without, DiagnosticsModule is the stand-in at the
// end of this file: every call made of it does nothing, and its commands say how to build them.
#pragma once
#ifndef UIHOOK_DIAGNOSTICS
#define UIHOOK_DIAGNOSTICS 0
#endif
#include <windows.h>
#include <stdio.h>
#include <string>
#include <vector>
#include <algorithm>
#include "../../drawcontext.h"
#include "../chat/chat.h"
#include "../window/window.h"
#include "../native/native.h"
#include "census.h"
#include "labels.h"
#include "textures.h"

#if UIHOOK_DIAGNOSTICS
class DiagnosticsModule {
public:
    Census census;           // /uihook census: the windows drawn and the text they print, heard while it is on
    TextureCensus textures;  // /uihook textures
    bool hooked=false;       // the window hooks taken: the text routes heard
    DrawContext* ctx=nullptr;
    const NativeLook* native=nullptr; // the part of a window being drawn, and whether a text routine is under way
    void Init(DrawContext* context,const NativeLook* nativeLook) { ctx=context; native=nativeLook; }
    // The window hooks taken: the census told where the game's code is
    void Start(uintptr_t base) { census.base=base; hooked=true; }
    // and given back
    void Stop() { hooked=false; census.on=false; census.current=nullptr; }
    // uihook unloaded: the census's file written a last time, the textures let go
    void Unload() { AutoCensus(true); textures.on=false; textures.Clear(); textures.window[0]=0; }
    // Each Present, before the frame is counted: the census's file written as it falls due
    void Present() { AutoCensus(false); }
    // and after
    void Counted() { census.frame=ctx->Frame(); }
    // A draw from a vertex buffer
    void BufferDraw() { TextureDraw(nullptr,0,0,true); census.Draw(); }
    // A draw from memory: its vertices, and how many make a piece of its texture (6 a list's quad, 4 a strip's)
    void MemoryDraw(const void* data,unsigned vertices,unsigned stride,unsigned group) {
        TextureDraw(data,vertices,stride,false,group);
        census.Draw();
    }
    // Each print of the three text routes heard, and its text read for the texture census's glyphs; then ended
    void TextBegin(TextRoute route,int32_t x,int32_t y,const char* text,uint32_t colour) {
        census.Text(route,x,y,text,colour); census.depth++; PrintBegin(text);
    }
    void TextEnd() { census.depth--; textures.PrintEnd(); }
    // A print's text read for the texture census's glyphs, as far as its end or 255 bytes
    void PrintBegin(const char* text) {
        if (!textures.on || !text) { textures.PrintBegin(nullptr,0); return; }
        uint8_t bytes[256]; size_t n=0;
        while (n<sizeof(bytes)-1 && ChatRead(text+n,bytes+n,1) && bytes[n]) n++;
        textures.PrintBegin(bytes,n);
    }
    // A window Window::Render draws, for as long as it is drawn: the census told, the texture census its name
    struct Window {
        DiagnosticsModule& d; CensusScope scope; char was[sizeof(TextureCensus::window)];
        Window(DiagnosticsModule& m,void* window) : d(m), scope(m.census,window) {
            memcpy(was,m.textures.window,sizeof(was));
            if (m.textures.on) {
                void* header=nullptr; char name[16];
                const bool named=window && ChatRead(static_cast<uint8_t*>(window)+WINDOW_HEADER,&header,4) && header && ChatRead(static_cast<uint8_t*>(header)+WINDOW_NAME,name,16);
                m.textures.Window(named ? name : "?");
            }
        }
        ~Window() { memcpy(d.textures.window,was,sizeof(was)); }
    };
    // /uihook textures: a screen-space draw's texture (stage 0), read the first time it is seen, counted with the
    // window and part drawing it. data: its vertices, from min; none from a vertex buffer.
    void TextureDraw(const void* data,unsigned vertices,unsigned stride,bool buffered,unsigned group=0) {
        if (!textures.on) return;
        auto* device=ctx->Device(); DWORD fvf=0;
        if (!device || !ctx->DrawFvf(fvf) || (fvf & D3DFVF_POSITION_MASK)!=D3DFVF_XYZRHW) return;
        IDirect3DBaseTexture8* base=nullptr;
        if (FAILED(device->GetTexture(0,&base))) base=nullptr;
        const uintptr_t key=reinterpret_cast<uintptr_t>(base);
        size_t at=textures.Known(key,ctx->Frame());
        if (at==SIZE_MAX) {
            LabelPixels pixels; D3DSURFACE_DESC desc{}; uint32_t texels[4]={}; const char* why="";
            static const float whole[4]={0,0,1,1};
            const bool read=base && LabelCut(base,whole,pixels,desc,texels,why);
            at=textures.Add(key,ctx->Frame(),desc.Width,desc.Height,uint32_t(desc.Format),uint32_t(desc.Pool),read ? &pixels : nullptr,read || !base ? "" : why);
        }
        if (base) base->Release();
        float uv[4]; uint32_t colour=0; bool hasColour=false;
        const bool hasUV=!buffered && TextureVertices(data,vertices,stride,fvf,uv,&colour,hasColour);
        const TexturePart part=!textures.window[0] ? TEXTURE_OUTSIDE : native->text ? TEXTURE_TEXT : TexturePart(native->phase);
        textures.Count(at,part,hasUV ? uv : nullptr,hasColour ? &colour : nullptr,buffered);
        if (hasUV) TexturePieces(data,vertices,stride,fvf,group,[&](const float* rect,const float* piece,uint32_t c) {
            textures.Sample(at,part,rect,piece,c);
            if (part==TEXTURE_TEXT || native->text) textures.PrintPiece(at,rect,piece);
        });
    }
    void TexturesWrite(char* line,size_t size) {
        const std::string base=std::string(ctx->core->GetInstallPath())+"\\logs\\uihook-textures";
        CreateDirectoryA(base.c_str(),nullptr);
        std::string folder;
        for (unsigned n=1;n<1000 && folder.empty();n++) {
            char sub[8]; snprintf(sub,sizeof(sub),"\\%02u",n);
            if (CreateDirectoryA((base+sub).c_str(),nullptr)) folder=base+sub;
        }
        unsigned images=0;
        if (folder.empty() || !textures.Write(folder,images)) snprintf(line,size,"[uihook:textures] could not write to %s.",base.c_str());
        else {
            textures.WriteGlyphs(folder+"\\glyphs.txt");
            snprintf(line,size,"[uihook:textures] %zu textures (%u as pictures) written to %s\\index.txt, glyphs of %u prints to glyphs.txt.",
                textures.entries.size(),images,folder.c_str(),textures.matched);
        }
    }
    void TexturesCommand(const char* word) {
        char line[512];
        if (!_stricmp(word,"on")) {
            snprintf(line,sizeof(line),textures.on ? "[uihook:textures] already on."
                : "[uihook:textures] on: open the menus you want counted, then /uihook textures off to write them to logs\\uihook-textures.");
            textures.on=true;
        } else if (!_stricmp(word,"off")) {
            textures.on=false;
            if (textures.entries.empty()) snprintf(line,sizeof(line),"[uihook:textures] off; nothing seen.");
            else TexturesWrite(line,sizeof(line));
        } else if (!_stricmp(word,"dump")) {
            if (textures.entries.empty()) snprintf(line,sizeof(line),"[uihook:textures] nothing seen yet: /uihook textures on, then open some menus.");
            else TexturesWrite(line,sizeof(line));
        } else if (!_stricmp(word,"clear")) {
            textures.Clear(); snprintf(line,sizeof(line),"[uihook:textures] cleared.");
        } else snprintf(line,sizeof(line),"[uihook:textures] %s, %zu textures seen (%zu bytes of pixels kept). /uihook textures on|off|dump|clear.",
            textures.on ? "on" : "off",textures.entries.size(),textures.memory);
        ctx->core->GetChatManager()->Write(0,false,line);
    }
    // The census, from /uihook census on: each time it is switched on a file of its own in logs\uihook-census (named
    // for when it began), written a few seconds after a window is first seen, each minute while windows are drawn,
    // and as it is switched off or uihook is unloaded. Off from load.
    std::string censusAuto; DWORD censusWrittenAt=0, censusNewAt=0; size_t censusWritten=0; uint32_t censusFrame=0;
    void StartAutoCensus() {
        if (!StartCensus()) return;
        const std::string folder=std::string(ctx->core->GetInstallPath())+"\\logs\\uihook-census";
        CreateDirectoryA(folder.c_str(),nullptr);
        SYSTEMTIME t; GetLocalTime(&t); char name[48];
        snprintf(name,sizeof(name),"\\%04u-%02u-%02u_%02u%02u%02u.txt",t.wYear,t.wMonth,t.wDay,t.wHour,t.wMinute,t.wSecond);
        censusAuto=folder+name; censusWrittenAt=GetTickCount(); censusNewAt=0; censusWritten=0; censusFrame=0;
    }
    void AutoCensus(bool now) {
        if (censusAuto.empty() || !census.on || census.windows.empty()) return;
        const DWORD tick=GetTickCount();
        if (census.windows.size()!=censusWritten && !censusNewAt) censusNewAt=tick ? tick : 1;
        uint32_t last=0; for (auto& w:census.windows) last=(std::max)(last,w.last);
        const bool fresh=censusNewAt && tick-censusNewAt>=5000;
        const bool minute=tick-censusWrittenAt>=60000 && last!=censusFrame;
        if (!now && !fresh && !minute) return;
        if (census.Write(censusAuto.c_str(),"heard")) { censusWritten=census.windows.size(); censusFrame=last; }
        censusWrittenAt=tick; censusNewAt=0;
    }
    bool StartCensus() { if (!hooked) return false; census.on=true; return true; }
    void StopCensus() { census.on=false; census.current=nullptr; }
    void CensusCommand(const char* word) {
        char line[256];
        const std::string path=std::string(ctx->core->GetInstallPath())+"\\logs\\uihook-census.txt";
        if (!_stricmp(word,"on")) {
            const bool was=census.on;
            if (!was) StartAutoCensus();
            snprintf(line,sizeof(line),was ? "[uihook:census] already on." : census.on
                ? "[uihook:census] on, written to logs\\uihook-census as you open menus; /uihook census off to stop." : "[uihook:census] the text routines were not found in this client.");
        } else if (!_stricmp(word,"off")) {
            AutoCensus(true); censusAuto.clear();
            StopCensus(); snprintf(line,sizeof(line),"[uihook:census] off; %zu windows kept until /uihook census clear.",census.windows.size());
        } else if (!_stricmp(word,"clear")) {
            census.Clear(); snprintf(line,sizeof(line),"[uihook:census] cleared.");
        } else if (!_stricmp(word,"dump")) {
            if (census.Write(path.c_str(),hooked ? "heard" : "not found in this client"))
                snprintf(line,sizeof(line),"[uihook:census] %zu windows written to %s.",census.windows.size(),path.c_str());
            else snprintf(line,sizeof(line),"[uihook:census] could not write %s.",path.c_str());
        } else snprintf(line,sizeof(line),"[uihook:census] %s, %zu windows seen. /uihook census on|off|dump|clear.",census.on ? "on" : "off",census.windows.size());
        ctx->core->GetChatManager()->Write(0,false,line);
    }
};
#else
// The stand-in: the calls the party module makes, each nothing
class DiagnosticsModule {
public:
    DrawContext* ctx=nullptr;
    void Init(DrawContext* context,const NativeLook*) { ctx=context; }
    void Start(uintptr_t) {}
    void Stop() {}
    void Unload() {}
    void Present() {}
    void Counted() {}
    void BufferDraw() {}
    void MemoryDraw(const void*,unsigned,unsigned,unsigned) {}
    void TextBegin(TextRoute,int32_t,int32_t,const char*,uint32_t) {}
    void TextEnd() {}
    struct Window { Window(DiagnosticsModule&,void*) {} };
    void Absent(const char* tool) const {
        char line[160];
        snprintf(line,sizeof(line),"[uihook] %s is one of the diagnostics, left out of this build: plugins/uihook/build.sh --diagnostics builds them in.",tool);
        ctx->core->GetChatManager()->Write(0,false,line);
    }
    void CensusCommand(const char*) { Absent("/uihook census"); }
    void TexturesCommand(const char*) { Absent("/uihook textures"); }
};
#endif
