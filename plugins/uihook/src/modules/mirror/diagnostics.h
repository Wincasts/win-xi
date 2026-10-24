// The tools used to find out how the game draws its menus, kept apart from what changes its drawing:
//   /uihook census on|off|dump|clear        every window drawn and the text it prints (census.h)
//   /uihook textures on|off|dump|clear      every texture the screen-space drawing uses, by window and part (textures.h)
//   /uihook mirror labels [seconds]         the art of the menus mirrored, cut from its textures (labels.h)
//   /uihook mirror watch | mark <words>     each window drawn and what was published, as it changes (watch.h)
// and the watch kept in memory for tools/uihook_live.py (UihookWatch). One of the party module's parts: it hears
// the text routes, the windows and the draws the mirror and the native look hear.
#pragma once
#include <windows.h>
#include <stdio.h>
#include <string>
#include <vector>
#include <algorithm>
#include "../../drawcontext.h"
#include "../chat/chat.h"
#include "../native/native.h"
#include "census.h"
#include "mirror.h"
#include "labels.h"
#include "textures.h"
#include "watch.h"

// exported, as nothing in the DLL reads it back: a block private to it would have every write to it optimized away
extern "C" __declspec(dllexport) MirrorWatchShared UihookWatch{};

class DiagnosticsModule {
public:
    Census census;           // /uihook census: the windows drawn and the text they print, heard while it is on
    TextureCensus textures;  // /uihook textures
    MirrorWatch watch;       // every window drawn, kept in UihookWatch; with /uihook mirror watch, to logs\uihook-mirror-watch.txt
    bool watchFile=false;
    DrawContext* ctx=nullptr;
    MirrorShared* block=nullptr;      // the mirror's block and the mirror: what was asked for, mirrored and published
    Mirror* mirror=nullptr;
    const NativeLook* native=nullptr; // the part of a window being drawn, and whether a text routine is under way
    void Init(DrawContext* context,MirrorShared* mirrorBlock,Mirror* menuMirror,const NativeLook* nativeLook) {
        ctx=context; block=mirrorBlock; mirror=menuMirror; native=nativeLook;
    }
    // The text routes and the contents' call taken (the mirror's): the census told where the game's code is, the watch begun
    void Start(uintptr_t base) {
        census.base=base;
        memcpy(UihookWatch.Magic,"UIHOOK-WATCH",13); UihookWatch.Version=1; UihookWatch.Size=sizeof(UihookWatch);
        watch.Start();
    }
    // and given back
    void Stop() { census.on=false; census.current=nullptr; watch.Stop(); watchFile=false; UihookWatch.Count=0; }
    // uihook unloaded: the census's file written a last time, the textures let go
    void Unload() { AutoCensus(true); textures.on=false; textures.Clear(); textures.window[0]=0; }
    // Each Present, before the frame is counted: the watch shared, the art written where it was asked for later, the
    // census's file written as it falls due
    void Present() {
        if (watch.on) {
            watch.Share(UihookWatch,ctx->Frame());
            if (watchFile) WatchPresent(); else watch.Next();
        }
        if (labelsAt && int32_t(GetTickCount()-labelsAt)>=0) { labelsAt=0; LabelsCommand(); }
        AutoCensus(false);
    }
    // and after
    void Counted() { census.frame=ctx->Frame(); }
    // A draw from a vertex buffer
    void BufferDraw() { TextureDraw(nullptr,0,0,true); census.Draw(); watch.Draw(MirrorWatch::BUFFER); }
    // A draw from memory: its vertices, and how many make a piece of its texture (6 a list's quad, 4 a strip's)
    void MemoryDraw(const void* data,unsigned vertices,unsigned stride,unsigned group) {
        TextureDraw(data,vertices,stride,false,group);
        census.Draw();
        if (watch.Inside()) WatchUp();
    }
    // Each print of the three text routes heard, and its text read for the texture census's glyphs; then ended
    void TextBegin(CensusRoute route,int32_t x,int32_t y,const char* text,uint32_t colour) {
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
    // A window Window::Render draws, for as long as it is drawn: the census and the watch told, the texture census its
    // name. hidden: the mirror leaves it undrawn.
    struct Window {
        DiagnosticsModule& d; CensusScope scope; char was[sizeof(TextureCensus::window)]; int watchWas;
        Window(DiagnosticsModule& m,void* window,bool hidden) : d(m), scope(m.census,window) {
            memcpy(was,m.textures.window,sizeof(was));
            if (m.textures.on) {
                void* header=nullptr; char name[16];
                const bool named=window && ChatRead(static_cast<uint8_t*>(window)+4,&header,4) && header && ChatRead(static_cast<uint8_t*>(header)+0x46,name,16);
                m.textures.Window(named ? name : "?");
            }
            watchWas=m.watch.on ? m.WatchEnter(window,hidden) : -1;
        }
        ~Window() { d.watch.Leave(watchWas); memcpy(d.textures.window,was,sizeof(was)); }
    };
    // /uihook mirror labels [seconds]: at once, or after the seconds given, so the chat line the command was typed in
    // has closed and the menus are drawn as they are while played
    void LabelsLater(int seconds) {
        if (seconds<=0) { LabelsCommand(); return; }
        labelsAt=GetTickCount()+DWORD((std::min)(seconds,60))*1000;
        char line[96]; snprintf(line,sizeof(line),"[uihook:mirror] writing the menus' art in %d seconds.",(std::min)(seconds,60));
        ctx->core->GetChatManager()->Write(0,false,line);
    }
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
    bool StartCensus() { if (!block->Supported) return false; census.on=true; return true; }
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
            const bool hooked=block->Supported!=0;
            if (census.Write(path.c_str(),hooked ? "heard" : "not found in this client"))
                snprintf(line,sizeof(line),"[uihook:census] %zu windows written to %s.",census.windows.size(),path.c_str());
            else snprintf(line,sizeof(line),"[uihook:census] could not write %s.",path.c_str());
        } else snprintf(line,sizeof(line),"[uihook:census] %s, %zu windows seen. /uihook census on|off|dump|clear.",census.on ? "on" : "off",census.windows.size());
        ctx->core->GetChatManager()->Write(0,false,line);
    }
    // Every element and content quad (an icon, a letter) of the last frame published, cut from its texture to logs\uihook-labels\N.bmp, with
    // labels.txt naming each one's window, texture, place in it and the hash of its pixels
    DWORD labelsAt=0; // when a /uihook mirror labels asked for later is to be written, or 0
    void LabelsCommand() {
        char line[512];
        const MirrorFrameData& last=block->Published;
        uint32_t elements=0;
        for (uint32_t i=0;i<last.QuadCount;i++) if (last.Quads[i].Phase==MIRROR_ELEMENT || last.Quads[i].Phase==MIRROR_CONTENT) elements++;
        if (!elements) {
            ctx->core->GetChatManager()->Write(0,false,"[uihook:mirror] no elements or art in the last frame mirrored: open a menu the menus addon mirrors first; nothing written.");
            return;
        }
        // each run in a folder of its own, 01, 02 and on, so none is written over
        const std::string base=std::string(ctx->core->GetInstallPath())+"\\logs\\uihook-labels";
        CreateDirectoryA(base.c_str(),nullptr);
        std::string folder;
        for (unsigned n=1;n<1000 && folder.empty();n++) {
            char sub[8]; snprintf(sub,sizeof(sub),"\\%02u",n);
            if (CreateDirectoryA((base+sub).c_str(),nullptr)) folder=base+sub;
        }
        if (folder.empty()) { snprintf(line,sizeof(line),"[uihook:mirror] could not make a folder in %s.",base.c_str()); ctx->core->GetChatManager()->Write(0,false,line); return; }
        std::vector<uint32_t> sheets; // each texture once whole, as sheet-XXXXXXXX.bmp
        FILE* list=fopen((folder+"\\labels.txt").c_str(),"w");
        if (!list) { snprintf(line,sizeof(line),"[uihook:mirror] could not write %s.",folder.c_str()); ctx->core->GetChatManager()->Write(0,false,line); return; }
        fprintf(list,"# n window texture WxH format uv(left top right bottom) texels(x0 y0 x1 y1) hash colour rect(normalized) phase(1 content, 3 element)\n");
        unsigned written=0,skipped=0;
        for (uint32_t i=0;i<last.QuadCount;i++) {
            const MirrorQuad& q=last.Quads[i];
            if ((q.Phase!=MIRROR_ELEMENT && q.Phase!=MIRROR_CONTENT) || q.Window>=last.WindowCount) continue;
            const char* name=last.Windows[q.Window].Name;
            LabelPixels pixels; D3DSURFACE_DESC desc{}; uint32_t texels[4]={}; const char* why="not held";
            const bool cut=q.Texture && mirror->Holds(q.Texture)
                && LabelCut(reinterpret_cast<IDirect3DBaseTexture8*>(uintptr_t(q.Texture)),q.UV,pixels,desc,texels,why);
            if (cut && std::find(sheets.begin(),sheets.end(),q.Texture)==sheets.end()) {
                sheets.push_back(q.Texture);
                const float whole[4]={0,0,1,1}; LabelPixels sheet; D3DSURFACE_DESC d{}; uint32_t t[4]; const char* w;
                char name[40]; snprintf(name,sizeof(name),"\\sheet-%08X.bmp",q.Texture);
                if (LabelCut(reinterpret_cast<IDirect3DBaseTexture8*>(uintptr_t(q.Texture)),whole,sheet,d,t,w)) LabelWrite((folder+name).c_str(),sheet);
            }
            char file[32]="-";
            if (cut) {
                snprintf(file,sizeof(file),"%03u.bmp",i);
                if (!LabelWrite((folder+"\\"+file).c_str(),pixels)) { snprintf(file,sizeof(file),"-"); why="not written"; }
            }
            fprintf(list,"%s %.16s %08X %ux%u %08X %.5f %.5f %.5f %.5f %u %u %u %u %08X %08X %.4f %.4f %.4f %.4f %u%s%s\n",
                file,name,q.Texture,desc.Width,desc.Height,uint32_t(desc.Format),q.UV[0],q.UV[1],q.UV[2],q.UV[3],
                texels[0],texels[1],texels[2],texels[3],file[0]!='-' ? LabelHash(pixels) : 0u,q.Colour,
                q.Rect[0],q.Rect[1],q.Rect[2],q.Rect[3],q.Phase,file[0]!='-' ? "" : " # ",file[0]!='-' ? "" : why);
            (file[0]!='-' ? written : skipped)++;
        }
        fclose(list);
        snprintf(line,sizeof(line),"[uihook:mirror] %u pieces and %zu textures written, %u not, to %s (from %u windows mirrored last frame).",
            written,sheets.size(),skipped,folder.c_str(),last.WindowCount);
        ctx->core->GetChatManager()->Write(0,false,line);
    }
    // /uihook mirror watch: each window drawn, whether asked for and mirrored, and how it drew, written as it changes
    std::string WatchPath() const { return std::string(ctx->core->GetInstallPath())+"\\logs\\uihook-mirror-watch.txt"; }
    int WatchEnter(void* window,bool hidden) {
        char name[16]; uint8_t* header=nullptr; bool hide=false;
        auto* w=static_cast<uint8_t*>(window);
        const bool wanted=w && ChatRead(w+CENSUS_HEADER,&header,4) && header && ChatRead(header+CENSUS_NAME,name,16) && mirror->Wanted(name,hide);
        return watch.Enter(window,wanted,hidden,mirror->Active());
    }
    void WatchUp() {
        DWORD fvf=0; auto* device=ctx->Device();
        const bool screen=device && ctx->DrawFvf(fvf) && (fvf & D3DFVF_POSITION_MASK)==D3DFVF_XYZRHW;
        watch.Draw(screen ? MirrorWatch::UP : MirrorWatch::OTHER);
    }
    void WatchWrite(const std::string& text) {
        if (text.empty()) return;
        if (FILE* file=fopen(WatchPath().c_str(),"a")) { fputs(text.c_str(),file); fclose(file); }
    }
    static std::string WatchClock() {
        SYSTEMTIME t; GetLocalTime(&t); char clock[16];
        snprintf(clock,sizeof(clock),"%02u:%02u:%02u.%03u",t.wHour,t.wMinute,t.wSecond,t.wMilliseconds);
        return clock;
    }
    void WatchPresent() {
        WatchWrite(watch.Present(block->Published,block->Dropped,ctx->Frame(),GetTickCount(),WatchClock().c_str()));
    }
    void WatchCommand(const char* word) {
        char line[320]; const std::string path=WatchPath();
        if (word[0]) {
            // a line of the player's own in the file, where they are and what they see, and the next frame written
            if (!watchFile) { ctx->core->GetChatManager()->Write(0,false,"[uihook:mirror] the watch is off: /uihook mirror watch first."); return; }
            WatchWrite("-- "+WatchClock()+" mark: "+word+"\n"); watch.Renew();
            snprintf(line,sizeof(line),"[uihook:mirror] marked: %s",word);
        } else if (watchFile) {
            watchFile=false; snprintf(line,sizeof(line),"[uihook:mirror] watch off; %s kept.",path.c_str());
        } else if (!block->Supported) {
            snprintf(line,sizeof(line),"[uihook:mirror] the menus' drawing was not found in this client; nothing to watch.");
        } else if (FILE* file=fopen(path.c_str(),"w")) {
            fprintf(file,"uihook mirror watch, started %s: each window drawn (asked for by an addon, hidden, mirrored), its draws, and what was published\n",WatchClock().c_str());
            fclose(file); watchFile=true; watch.Renew();
            snprintf(line,sizeof(line),"[uihook:mirror] watching to %s; /uihook mirror mark <words> to note a moment, /uihook mirror watch again to stop.",path.c_str());
        } else snprintf(line,sizeof(line),"[uihook:mirror] could not write %s.",path.c_str());
        ctx->core->GetChatManager()->Write(0,false,line);
    }
};
