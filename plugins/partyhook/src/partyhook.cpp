// Experimental native Party replacement. Capture the addon's existing ImGui geometry in C++;
// replay it at Window::Render, executing native window logic with only its GPU submissions blocked.
#include <windows.h>
#include <psapi.h>
#include <stdint.h>
#include <vector>
#include <cmath>
#include "Ashita.h"
#include "partyhook.h"
#include "detour.h"
#include "game.h"
#include "target.h"
#include "clip.h"
#include "runs.h"
#define PARTY_FVF (D3DFVF_XYZRHW | D3DFVF_DIFFUSE | D3DFVF_TEX1)
#include "states.h"

static int32_t __cdecl Submit(int32_t index, int32_t capture);
static void __fastcall RenderWindow(void* window, void*);
// Sprite::Draw(this, x, y, sx, sy, color, flags1, flags2, flags3): preserve all eight stack
// words verbatim, including float bit patterns and signed shorts promoted by the native caller.
static void __fastcall DrawTargetArrow(void*,void*,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
static ArrowCalls Arrows;
static PartyShared Shared = { "PARTYHOOK", PARTY_VERSION, sizeof(PartyShared), 0, 0, 1, {}, 0, 0, 0, 0, 0, 0, 0, {} };
static Detour WindowDetour = { WINDOW_PATTERN, WINDOW_STOLEN, -1, reinterpret_cast<void*>(&RenderWindow), nullptr, nullptr, {} };

using Run = TextureRun<IDirect3DBaseTexture8>;
struct Drawing {
    std::vector<PartyVertex> vertices;
    std::vector<Run> runs;
    uint32_t submitted = 0, drawn = 0;
    float width = 0, height = 0;
    IDirect3DBaseTexture8* font = nullptr;
    void Clear() {
        for (auto& r : runs) if (r.texture) r.texture->Release();
        runs.clear(); vertices.clear(); submitted = drawn = 0; font = nullptr;
    }
    bool Fresh() const { return submitted != 0 && Shared.Frame-submitted <= PARTY_FRESH_FRAMES; }
};

class PartyHook : public IPlugin {
    IAshitaCore* core = nullptr;
    void** globals[4] = {};
    Drawing drawings[6];
    Drawing staging;
    std::vector<PartyVertex> transformed;
    DWORD states = 0, saved = 0;
    bool blocking = false;
    bool targetScope = false;
    uint8_t* menuManager = nullptr;

    IDirect3DBaseTexture8* Font() const {
        auto* gui = core->GetGuiManager();
        const ImFontAtlas* atlas = gui ? gui->GetIO().Fonts : nullptr;
        const ImTextureData* data = atlas ? atlas->TexData : nullptr;
        if (!data || (data->Status != ImTextureStatus_OK && data->Status != ImTextureStatus_WantUpdates)) return nullptr;
        // namehook 1.25 / buffhook 1.1: a 64-bit ImTextureID is read here, NEVER by Lua.
        return reinterpret_cast<IDirect3DBaseTexture8*>(static_cast<uintptr_t>(data->TexID));
    }
    void ReleaseStates() {
        auto* d = core ? core->GetDirect3DDevice() : nullptr;
        if (d) { if (states) d->DeleteStateBlock(states); if (saved) d->DeleteStateBlock(saved); }
        states = saved = 0;
    }
    bool MakeStates(IDirect3DDevice8* d) {
        if (!states) { d->BeginStateBlock(); SetPartyStates(d); if (FAILED(d->EndStateBlock(&states))) states=0; }
        if (!saved) { d->BeginStateBlock(); SetPartyStates(d); if (FAILED(d->EndStateBlock(&saved))) saved=0; }
        return states && saved;
    }
    bool Block() { if (blocking) Shared.BlockedCalls++; return blocking; }

public:
    static PartyHook* Instance;
    const char* GetName() const override { return "partyhook"; }
    const char* GetAuthor() const override { return "win"; }
    const char* GetDescription() const override { return "Experimental Party/target HUD replacement with native target arrows preserved."; }
    const char* GetLink() const override { return "https://github.com/Wincasts/win-xi"; }
    double GetVersion() const override { return 0.3; }
    uint32_t GetFlags() const override { return static_cast<uint32_t>(Ashita::PluginFlags::UseDirect3D); }
    bool Initialize(IAshitaCore* c, ILogManager*, uint32_t) override {
        if (GetModuleHandleA("uihook.dll")) {
            c->GetChatManager()->Write(0,false,"[partyhook] uihook already owns HUD hooks; unload it first.");
            return false;
        }
        core=c; Instance=this;
        Shared.Submit = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(&Submit));
        MODULEINFO module={};
        if (GetModuleInformation(GetCurrentProcess(),GetModuleHandleA("FFXiMain.dll"),&module,sizeof(module))) {
            auto* begin=static_cast<uint8_t*>(module.lpBaseOfDll);
            auto* party=FindPattern(begin,module.SizeOfImage,PARTY_PATTERN);
            uintptr_t main=0;
            if (party) memcpy(&main,party+PARTY_GLOBAL_AT,4);
            if (main && PartyGlobals(begin,module.SizeOfImage,main,globals)
                && Take(WindowDetour,begin,module.SizeOfImage)) {
                Shared.SupportedMask=7; Shared.Hooked=1;
                if (auto* rect=UniquePattern(begin,module.SizeOfImage,RECT_PATTERN)) {
                    uintptr_t manager=0; memcpy(&manager,rect+RECT_MANAGER_AT,4);
                    uintptr_t low=reinterpret_cast<uintptr_t>(begin);
                    if (manager>=low && manager<=low+module.SizeOfImage-0x84) {
                        menuManager=reinterpret_cast<uint8_t*>(manager); Shared.GeometryReady=1;
                    }
                }
                uintptr_t target=0; memcpy(&target,party+TARGET_GLOBAL_AT,4);
                globals[3]=TargetGlobal(begin,module.SizeOfImage,target);
                if (globals[3] && TakeArrows(Arrows,begin,module.SizeOfImage,reinterpret_cast<void*>(&DrawTargetArrow))) {
                    Shared.SupportedMask|=8;
                } else globals[3]=nullptr; // party mode still works if target discovery fails
            }
        }
        core->GetChatManager()->Write(0,false, Shared.Hooked ?
            (Shared.SupportedMask & 8 ? "[partyhook] Party/target hooks ready (native arrows preserved). /pt native [target] on; unload hideparty first." :
             "[partyhook] Party hook ready; target/cursor signatures unavailable. /pt native on; unload hideparty first.") :
            "[partyhook] Client not recognised; native lists unchanged.");
        return true;
    }
    void Stop() { for (auto& d:drawings) d.Clear(); staging.Clear(); }
    void Release() override {
        Shared.Hooked=0; Shared.Submit=0; Shared.GeometryReady=0;
        GiveArrows(Arrows); Give(WindowDetour); blocking=targetScope=false; ReleaseStates(); Stop(); Instance=nullptr;
    }
    bool Direct3DInitialize(IDirect3DDevice8*) override { return true; }
    void Direct3DPresent(const RECT*,const RECT*,HWND,const RGNDATA*) override {
        ++Shared.Frame;
        // As namehook: no cross-frame state blocks holding client resources across a reset.
        ReleaseStates();
        for (auto& d:drawings) if (!d.Fresh()) d.Clear();
    }
    bool Direct3DDrawPrimitive(D3DPRIMITIVETYPE,UINT,UINT) override { return Block(); }
    bool Direct3DDrawIndexedPrimitive(D3DPRIMITIVETYPE,UINT,UINT,UINT,UINT) override { return Block(); }
    bool Direct3DDrawPrimitiveUP(D3DPRIMITIVETYPE,UINT,const void*,UINT) override { return Block(); }
    bool Direct3DDrawIndexedPrimitiveUP(D3DPRIMITIVETYPE,UINT,UINT,UINT,const void*,D3DFORMAT,const void*,UINT) override { return Block(); }

    int Capture(int index, int capture) {
        if (index<0) { Stop(); return 1; }
        if (index>5 || !Shared.Hooked) return 0;
        Drawing& out=drawings[index];
        if (capture<0) { out.Clear(); return 1; }
        if (!(Shared.SupportedMask & (index<3 ? (1u<<index) : 8u))) return 0;
        if (!capture) { out.Clear(); out.submitted=Shared.Frame; return 1; }
        auto* gui=core->GetGuiManager();
        ImDrawList* list=gui ? gui->GetWindowDrawList() : nullptr;
        if (!list) return 0;
        staging.Clear();
        const ImVec2 display=gui->GetIO().DisplaySize;
        if (!(display.x>0 && display.y>0)) return 0;
        staging.width=display.x; staging.height=display.y; staging.font=Font();
        bool ok=true;
        unsigned commands=0;
        for (int c=0;c<list->CmdBuffer.Size && ok;c++) {
            const ImDrawCmd& cmd=list->CmdBuffer[c];
            if (!cmd.ElemCount) continue;
            if (cmd.UserCallback || cmd.ElemCount%3 || cmd.IdxOffset+uint64_t(cmd.ElemCount)>uint64_t(list->IdxBuffer.Size)
                || ++commands>PARTY_MAX_COMMANDS) { ok=false; break; }
            // Resolve all textures on the C++ side, including the font atlas; never interpret mark 1 as a pointer.
            const ImTextureData* data=cmd.TexRef._TexData;
            if (data && data->Status!=ImTextureStatus_OK && data->Status!=ImTextureStatus_WantUpdates) { ok=false; break; }
            // Read fields, not assertion-bearing GetTexID methods (the recent namehook failure).
            const ImTextureID id=data ? data->TexID : cmd.TexRef._TexID;
            const uintptr_t address=static_cast<uintptr_t>(id);
            if (address<0x10000 || uint64_t(id)>UINT32_MAX) { ok=false; break; }
            auto* texture=reinterpret_cast<IDirect3DBaseTexture8*>(address);
            uint32_t first=static_cast<uint32_t>(staging.vertices.size());
            PartyClip clip={cmd.ClipRect.x,cmd.ClipRect.y,cmd.ClipRect.z,cmd.ClipRect.w};
            if (!std::isfinite(clip.left)||!std::isfinite(clip.top)||!std::isfinite(clip.right)||!std::isfinite(clip.bottom)) { ok=false; break; }
            if (clip.right<=clip.left || clip.bottom<=clip.top) continue;
            for (unsigned i=0;i<cmd.ElemCount && ok;i+=3) {
                PartyVertex triangle[3], polygon[12];
                for (unsigned j=0;j<3;j++) {
                    uint64_t at=uint64_t(cmd.VtxOffset)+list->IdxBuffer[cmd.IdxOffset+i+j];
                    if (at>=uint64_t(list->VtxBuffer.Size)) { ok=false; break; }
                    const ImDrawVert& v=list->VtxBuffer[static_cast<int>(at)];
                    // ImGui ABGR -> Direct3D ARGB.
                    uint32_t color=(v.col&0xff00ff00)|((v.col&255)<<16)|((v.col>>16)&255);
                    triangle[j]={v.pos.x,v.pos.y,0,1,color,v.uv.x,v.uv.y};
                    if (!std::isfinite(v.pos.x)||!std::isfinite(v.pos.y)||!std::isfinite(v.uv.x)||!std::isfinite(v.uv.y)) ok=false;
                }
                if (!ok) break;
                unsigned n=ClipTriangle(triangle,clip,polygon);
                if (n<3) continue;
                if (staging.vertices.size()+(n-2)*3>PARTY_MAX_VERTICES) { ok=false; break; }
                for (unsigned j=1;j+1<n;j++) {
                    staging.vertices.push_back(polygon[0]); staging.vertices.push_back(polygon[j]); staging.vertices.push_back(polygon[j+1]);
                }
            }
            AppendRun(staging.runs,texture,first,static_cast<uint32_t>(staging.vertices.size())-first);
        }
        if (!ok) { staging.Clear(); out.Clear(); ++Shared.Failures; return 0; }
        out.Clear();
        out.vertices.swap(staging.vertices); out.runs.swap(staging.runs);
        out.width=staging.width; out.height=staging.height; out.font=staging.font; out.submitted=Shared.Frame;
        Shared.CapturedVertices=static_cast<uint32_t>(out.vertices.size());
        // Keep ImGui's layout and hit-testing; consume only its GPU commands, after making a complete copy.
        for (int c=0;c<list->CmdBuffer.Size;c++) list->CmdBuffer[c].ElemCount=0;
        return 1;
    }

    bool Replay(unsigned index) {
        Drawing& drawing=drawings[index];
        if (!drawing.Fresh()) return false;
        if (drawing.vertices.empty()) return true; // explicit empty replacement (solo/faded/hidden list)
        if (drawing.font!=Font()) return false; // atlas changed: old glyph UVs are not safe to replay
        // Keep the atlas check on repeated passes, but avoid redundant viewport queries/state work.
        if (drawing.drawn==Shared.Frame) return true;
        auto* device=core->GetDirect3DDevice(); D3DVIEWPORT8 viewport;
        if (!device || FAILED(device->GetViewport(&viewport))) return false;
        if (!MakeStates(device)) return false;
        transformed.resize(drawing.vertices.size());
        const float sx=float(viewport.Width)/drawing.width, sy=float(viewport.Height)/drawing.height;
        for (size_t i=0;i<transformed.size();i++) {
            transformed[i]=drawing.vertices[i];
            transformed[i].x=viewport.X+drawing.vertices[i].x*sx-0.5f;
            transformed[i].y=viewport.Y+drawing.vertices[i].y*sy-0.5f;
        }
        if (FAILED(device->CaptureStateBlock(saved))) return false;
        device->ApplyStateBlock(states);
        bool ok=true;
        for (const auto& r:drawing.runs) if (r.count) {
            device->SetTexture(0,r.texture);
            if (FAILED(device->DrawPrimitiveUP(D3DPT_TRIANGLELIST,r.count/3,&transformed[r.first],sizeof(PartyVertex)))) ok=false;
        }
        device->ApplyStateBlock(saved);
        if (ok) { drawing.drawn=Shared.Frame; Shared.DrawnFrame[index]=Shared.Frame; ++Shared.Replays; }
        return ok;
    }
    bool ReplayTargets() {
        // Validate the whole target group before drawing any of it; no fresh submission means
        // the stock target box/arrow run unchanged. Empty hidden frames still preserve the arrows.
        auto* font=Font();
        for (unsigned i=3;i<6;i++) if (!drawings[i].Fresh()
            || (!drawings[i].vertices.empty() && drawings[i].font!=font)) return false;
        return Replay(3) && Replay(4) && Replay(5);
    }
    void Arrow(void* sprite,uint32_t x,uint32_t y,uint32_t sx,uint32_t sy,uint32_t color,uint32_t a,uint32_t b,uint32_t c) {
        if (targetScope && blocking) ++Shared.TargetCursorCalls;
        ArrowScope allow(blocking,targetScope);
        reinterpret_cast<SpriteDraw>(Arrows.sprite)(sprite,nullptr,x,y,sx,sy,color,a,b,c);
    }
    void RecordRect(unsigned index,void* window) {
        if (!menuManager) return;
        auto* device=core->GetDirect3DDevice(); D3DVIEWPORT8 viewport;
        if (!device || FAILED(device->GetViewport(&viewport))) return;
        int16_t rect[4]; auto* data=static_cast<const uint8_t*>(window);
        memcpy(rect,data+0x3a,sizeof(rect));
        int16_t w=0,h=0; memcpy(&w,menuManager+0x80,2); memcpy(&h,menuManager+0x82,2);
        NativeRect result={};
        if (MakeNativeRect(rect,data[0x99]!=0,w,h,viewport.Width,viewport.Height,Shared.Frame,result))
            Shared.Rects[index]=result;
        else Shared.Rects[index].Frame=0;
    }
    void Render(void* window) {
        int index=-1;
        for (int i=0;i<4;i++) {
            void* object=globals[i] ? *globals[i] : nullptr;
            if (object && *reinterpret_cast<void**>(static_cast<uint8_t*>(object)+OBJECT_WINDOW)==window) { index=i; break; }
        }
        bool was=blocking, wasTarget=targetScope;
        blocking=false; // replacement GPU calls must not be caught by our own callbacks
        bool replaced=index==3 ? ReplayTargets() : index>=0 && Replay(static_cast<unsigned>(index));
        blocking=replaced;
        targetScope=index==3 && replaced;
        reinterpret_cast<void(__fastcall*)(void*,void*)>(WindowDetour.trampoline)(window,nullptr);
        // Read after the client's animation/layout update, even when this window is not replaced.
        // No native positioning/state writes: Lua uses this geometry for its next submission.
        if (index>=0) RecordRect(static_cast<unsigned>(index),window);
        blocking=was; targetScope=wasTarget;
    }
};
PartyHook* PartyHook::Instance=nullptr;
static void __fastcall RenderWindow(void* window,void*) {
    if (PartyHook::Instance) PartyHook::Instance->Render(window);
    else reinterpret_cast<void(__fastcall*)(void*,void*)>(WindowDetour.trampoline)(window,nullptr);
}
static void __fastcall DrawTargetArrow(void* sprite,void*,uint32_t x,uint32_t y,uint32_t sx,uint32_t sy,uint32_t color,uint32_t a,uint32_t b,uint32_t c) {
    if (PartyHook::Instance) PartyHook::Instance->Arrow(sprite,x,y,sx,sy,color,a,b,c);
    else reinterpret_cast<SpriteDraw>(Arrows.sprite)(sprite,nullptr,x,y,sx,sy,color,a,b,c);
}
static int32_t __cdecl Submit(int32_t index,int32_t capture) {
    if (!PartyHook::Instance) return 0;
    try { return PartyHook::Instance->Capture(index,capture); }
    catch (...) { PartyHook::Instance->Stop(); ++Shared.Failures; return 0; }
}
extern "C" {
__declspec(dllexport) IPlugin* __stdcall expCreatePlugin(const char*) { return new PartyHook(); }
__declspec(dllexport) void __stdcall expDestroyPlugin(void* instance) { delete static_cast<IPlugin*>(instance); }
__declspec(dllexport) double __stdcall expGetInterfaceVersion() { return ASHITA_INTERFACE_VERSION; }
}
