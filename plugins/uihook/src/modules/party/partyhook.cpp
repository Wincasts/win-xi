// Experimental native Party replacement. Capture the addon's existing ImGui geometry in C++;
// replay it at Window::Render, executing native window logic with only its GPU submissions blocked.
#include <windows.h>
#include <psapi.h>
#include <stdint.h>
#include <vector>
#include <cmath>
#include <cstdio>
#include "Ashita.h"
#include "partyhook.h"
#include "detour.h"
#include "game.h"
#include "target.h"
#include "hud.h"
#include "../chat/chat.h"
#include "../chat/controls.h"
#include "../../slots.h"
#include "clip.h"
#include "runs.h"
#define PARTY_FVF (D3DFVF_XYZRHW | D3DFVF_DIFFUSE | D3DFVF_TEX1)
#include "states.h"

static int32_t __cdecl Submit(int32_t index, int32_t capture);
static void __fastcall RenderWindow(void* window, void*);
static int32_t __cdecl SubmitHud(int32_t index, int32_t capture);
static int32_t __cdecl SubmitChat(int32_t index, int32_t capture);
static ChatShared Chat = { "UIHOOK-CHAT", 9, sizeof(ChatShared), 0, 1, 0, {}, {}, {}, 0, {}, 0, {}, 0, {}, 0, 0, 0, 0, 0, 0, 0, 0, {}, 0, 0, 0, {}, 0, 0, 0, 0, {} };
static void __fastcall RenderCompass(void*,void*);
static void __fastcall RenderClock(void*,void*,int32_t,int32_t);
static void __cdecl DrawClockText(int32_t,int32_t,const char*,uint32_t);
// The one CALL in Clock::Draw that draws its text, aimed at DrawClockText while uihook is loaded.
static ClockTextCall TextCall;
// Clock::Draw's three icon calls, aimed at DrawClockIcon<0..2> while uihook is loaded.
template<int Icon> static void __fastcall DrawClockIcon(void*,void*,int32_t,int32_t,uint32_t,uint32_t,uint32_t);
static ClockIconCalls IconCalls;
static HudShared Hud = { "UIHOOK-HUD", HUD_VERSION, sizeof(HudShared), 0, 1, 0, {}, {}, 0xffff, {}, 0, {}, {}, {}, 0, 0, 0, 0 };
static Detour CompassDetour = { COMPASS_DRAW_PATTERN, 6, -1, reinterpret_cast<void*>(&RenderCompass), nullptr, nullptr, {} };
static Detour ClockDetour = { CLOCK_DRAW_PATTERN, 6, -1, reinterpret_cast<void*>(&RenderClock), nullptr, nullptr, {} };
// Sprite::Draw(this, x, y, sx, sy, color, flags1, flags2, flags3): preserve all eight stack
// words verbatim, including float bit patterns and signed shorts promoted by the native caller.
static void __fastcall DrawTargetArrow(void*,void*,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
static ArrowCalls Arrows;
static PartyShared Shared = { "PARTYHOOK", PARTY_VERSION, sizeof(PartyShared), 0, 0, 1, {}, 0, 0, 0, 0, 0, 0, 0, {} };
static Detour WindowDetour = { WINDOW_PATTERN, WINDOW_STOLEN, -1, reinterpret_cast<void*>(&RenderWindow), nullptr, nullptr, {} };
static void __fastcall DrawExpandedChat(void*,void*);
static Detour ExpandedChatDetour = { CHAT_FULL_DRAW_PATTERN, 5, -1, reinterpret_cast<void*>(&DrawExpandedChat), nullptr, nullptr, {} };
static void __fastcall DrawChatTab(void*,void*,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
static void __fastcall DrawChatSelection(void*,void*,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
static void __fastcall DrawChatCursor(void*,void*,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
static void __fastcall DrawChatScroll(void*,void*);
static void __fastcall DrawChatTabs(void*,void*,uint32_t);
static ChatControlCalls ChatControls;

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
    Drawing drawings[11]; // Party 0..5, HUD 6..7, chat logs/input 8..10; independent ABIs
    ChatModule chat;
    bool expandedCapture=false, expandedSkin=false, controlsValid=false;
    void* expandedOwner=nullptr;
    ChatControlStyle controlStyle;
    uint32_t replaceControls=0;       // CHAT_REPLACE_* bits, copied with a successful expanded capture
    // The game's tab strip and scrollbar, measured as they are drawn in a skinned full log (hidden or not)
    ChatBounds* chatMeasure=nullptr;  // the control being drawn, while it is
    bool measuringTabs=false;
    ChatBounds tabBounds[12], scrollBounds; uint32_t tabChannels[12]={}; bool tabSelected[12]={}; unsigned tabCount=0;
    D3DVIEWPORT8 chatViewport={}; bool chatViewportKnown=false;
    void** compassGlobal = nullptr;
    bool (__cdecl* radarVisible)() = nullptr;
    uint16_t* nativeWeather = nullptr;
    Drawing staging;
    std::vector<PartyVertex> transformed;
    std::vector<uint8_t> scaledVertices; // a weather icon's vertices, drawn larger or smaller
    DWORD states = 0, saved = 0;
    bool blocking = false;
    // What /uihook hud reports: the device as the clock replacement is drawn, and the game's own
    // clock draws. Read-only; it changes nothing that is drawn.
    struct HudProbe {
        uint32_t calls=0, callsFrame=0, callsLast=0, x=0, y=0;
        uint32_t replayFrame=0, vertices=0, runs=0;
        float width=0, height=0, minX=0, minY=0, maxX=0, maxY=0;
        D3DVIEWPORT8 viewport={};
        UINT targetWidth=0, targetHeight=0, backWidth=0, backHeight=0;
        bool targetIsBack=false, scene=false;
        DWORD blendOp=0, fillMode=0, clipping=0, shader=0;
        uint32_t nativeCalls=0, nativeUP=0; DWORD nativeShader=0;
        float nMinX=0, nMinY=0, nMaxX=0, nMaxY=0;
    } probe;
    bool inClock = false, inScene = false, inText = false, hideText = false;
    float clockShiftX=0, clockShiftY=0; // native screen pixels; replay itself is already positioned by its addon
    int inIcon = -1;          // which of the clock's icons is being drawn, or -1
    uint32_t hideIcons = 0;   // HUD_ICON_* to leave undrawn in this Clock::Draw call
    int32_t weatherShift = 0; // and the game's units to move its weather icons down by
    uint32_t preview = 0;     // and which of its weather icons to draw all of, beside each other
    float weatherScale = 1;   // and how large its weather icons are drawn
    bool previewing = false;  // while the preview's icons are drawn
    bool scaling = false;     // while a scaled copy is drawn: not measured, not scaled again
    float weatherMiddle[2][2] = {}; bool weatherMiddleKnown[2] = {}; // each weather icon's middle, as last drawn unscaled
    void* (__cdecl* bank)(int32_t) = nullptr;
    // The game's own clock draws in one Clock::Draw call: their screen bounds, and the viewport
    // they were drawn in, to say where the clock is; its text's (or, without the text call, all of
    // it), and each icon's.
    struct ClockBounds {
        uint32_t vertices=0; float left=0, top=0, right=0, bottom=0;
        void Add(float x,float y) {
            if (!vertices++) { left=right=x; top=bottom=y; }
            left=(std::min)(left,x); right=(std::max)(right,x);
            top=(std::min)(top,y); bottom=(std::max)(bottom,y);
        }
    } bounds, iconBounds[3];
    D3DVIEWPORT8 clockViewport={}; bool clockViewportKnown=false;
    void Native(bool up, const void* data, UINT stride, UINT count) {
        if (chatMeasure && !inClock) { MeasureChat(up,data,stride,count); return; }
        if (!inClock) return;
        auto* device=core->GetDirect3DDevice();
        DWORD shader=0;
        if (device) device->GetVertexShader(&shader);
        if (!probe.nativeCalls++) probe.nativeShader=shader;
        if (!up || !data || stride<8 || !(shader & D3DFVF_XYZRHW)) return;
        if (!clockViewportKnown && device) clockViewportKnown=SUCCEEDED(device->GetViewport(&clockViewport));
        auto* bytes=static_cast<const uint8_t*>(data);
        for (UINT i=0;i<count && i<4096;i++) {
            float v[2]; memcpy(v,bytes+size_t(i)*stride,sizeof(v));
            if (!std::isfinite(v[0]) || !std::isfinite(v[1])) continue;
            if (!probe.nativeUP++) { probe.nMinX=probe.nMaxX=v[0]; probe.nMinY=probe.nMaxY=v[1]; }
            probe.nMinX=(std::min)(probe.nMinX,v[0]); probe.nMaxX=(std::max)(probe.nMaxX,v[0]);
            probe.nMinY=(std::min)(probe.nMinY,v[1]); probe.nMaxY=(std::max)(probe.nMaxY,v[1]);
            if (inIcon>=0) { iconBounds[inIcon].Add(v[0],v[1]); continue; }
            // With the text call taken, the clock's place is its text's; the icons are the game's.
            if (TextCall.call && !inText) continue;
            bounds.Add(v[0],v[1]);
        }
    }
    // A native chat control's screen-space vertices, drawn from memory, give its bounds; anything else is not it
    void MeasureChat(bool up,const void* data,UINT stride,UINT count) {
        auto* device=core->GetDirect3DDevice();
        DWORD shader=0;
        if (!up || !data || stride<8 || !device || FAILED(device->GetVertexShader(&shader)) || !(shader & D3DFVF_XYZRHW)) return;
        if (!chatViewportKnown) chatViewportKnown=SUCCEEDED(device->GetViewport(&chatViewport));
        auto* bytes=static_cast<const uint8_t*>(data);
        for (UINT i=0;i<count && i<4096;i++) {
            float v[2]; memcpy(v,bytes+size_t(i)*stride,sizeof(v));
            if (std::isfinite(v[0]) && std::isfinite(v[1])) chatMeasure->Add(v[0],v[1]);
        }
    }
    bool NormalizeChat(const ChatBounds& from,float out[4]) const {
        return chatViewportKnown && ChatNormalize(from,float(chatViewport.X),float(chatViewport.Y),float(chatViewport.Width),float(chatViewport.Height),out);
    }
    // Replay maps ImGui display pixels onto the viewport; this is its inverse, for the clock's place.
    bool PublishRect(const ClockBounds& from,float out[4],uint32_t& frame) {
        auto* gui=core->GetGuiManager();
        if (!from.vertices || !clockViewportKnown || !gui) return false;
        const ImVec2 display=gui->GetIO().DisplaySize;
        const auto& v=clockViewport;
        if (!(display.x>0 && display.y>0) || !v.Width || !v.Height) return false;
        const float sx=display.x/float(v.Width), sy=display.y/float(v.Height);
        out[0]=(from.left+clockShiftX-float(v.X)+0.5f)*sx; out[1]=(from.top+clockShiftY-float(v.Y)+0.5f)*sy;
        out[2]=(from.right+clockShiftX-float(v.X)+0.5f)*sx; out[3]=(from.bottom+clockShiftY-float(v.Y)+0.5f)*sy;
        frame=Shared.Frame;
        return true;
    }
    void PublishClockRect() {
        PublishRect(bounds,Hud.ClockRect,Hud.ClockRectFrame);
        for (unsigned i=0;i<3;i++) PublishRect(iconBounds[i],Hud.IconRect[i],Hud.IconFrame[i]);
        // in the game's pixels, as its vertices are: what a scaled icon is grown about next frame
        for (unsigned i=1;i<3;i++) if (iconBounds[i].vertices) {
            weatherMiddle[i-1][0]=(iconBounds[i].left+iconBounds[i].right)/2;
            weatherMiddle[i-1][1]=(iconBounds[i].top+iconBounds[i].bottom)/2;
            weatherMiddleKnown[i-1]=true;
        }
    }
    // Weather resizing and whole-clock translation to the replacement log's top-left:
    // drawn from a copy in place of the game's, never modifying client vertex memory. Only screen-space vertices drawn from
    // memory, as the clock's are; anything else is left as the game draws it.
    bool ScaleIcon(D3DPRIMITIVETYPE t,UINT count,const void* data,UINT stride) {
        const bool resize=weatherScale!=1 && (inIcon==1 || inIcon==2 || previewing);
        const bool translate=inClock && (clockShiftX!=0 || clockShiftY!=0);
        if ((!resize && !translate) || !data || stride<8) return false;
        const UINT vertices=t==D3DPT_TRIANGLELIST ? count*3 : t==D3DPT_TRIANGLESTRIP || t==D3DPT_TRIANGLEFAN ? count+2 : 0;
        auto* device=core->GetDirect3DDevice();
        DWORD shader=0;
        if (!vertices || vertices>4096 || !device || FAILED(device->GetVertexShader(&shader)) || !(shader & D3DFVF_XYZRHW)) return false;
        scaledVertices.assign(static_cast<const uint8_t*>(data),static_cast<const uint8_t*>(data)+size_t(vertices)*stride);
        float cx=0,cy=0;
        // a double weather's two grow about the first's middle, so that the second moves out as they grow
        if (!previewing && weatherMiddleKnown[0]) { cx=weatherMiddle[0][0]; cy=weatherMiddle[0][1]; }
        else {
            ClockBounds own;
            for (UINT i=0;i<vertices;i++) { float v[2]; memcpy(v,&scaledVertices[size_t(i)*stride],sizeof(v)); own.Add(v[0],v[1]); }
            cx=(own.left+own.right)/2; cy=(own.top+own.bottom)/2;
        }
        if (resize) ScaleScreenVertices(scaledVertices.data(),vertices,stride,cx,cy,weatherScale);
        if (translate && !ChatTranslateVertices(scaledVertices.data(),vertices,stride,clockShiftX,clockShiftY)) return false;
        scaling=true;
        const bool ok=SUCCEEDED(device->DrawPrimitiveUP(t,count,scaledVertices.data(),stride));
        scaling=false;
        return ok;
    }
    void ProbeDevice(IDirect3DDevice8* device, const D3DVIEWPORT8& viewport, const Drawing& drawing) {
        probe.replayFrame=Shared.Frame; probe.viewport=viewport; probe.scene=inScene;
        probe.width=drawing.width; probe.height=drawing.height;
        probe.vertices=static_cast<uint32_t>(transformed.size()); probe.runs=static_cast<uint32_t>(drawing.runs.size());
        for (size_t i=0;i<transformed.size();i++) {
            const auto& v=transformed[i];
            if (!i) { probe.minX=probe.maxX=v.x; probe.minY=probe.maxY=v.y; }
            probe.minX=(std::min)(probe.minX,v.x); probe.maxX=(std::max)(probe.maxX,v.x);
            probe.minY=(std::min)(probe.minY,v.y); probe.maxY=(std::max)(probe.maxY,v.y);
        }
        IDirect3DSurface8 *target=nullptr, *back=nullptr; D3DSURFACE_DESC desc;
        probe.targetWidth=probe.targetHeight=probe.backWidth=probe.backHeight=0;
        if (SUCCEEDED(device->GetRenderTarget(&target)) && target) {
            if (SUCCEEDED(target->GetDesc(&desc))) { probe.targetWidth=desc.Width; probe.targetHeight=desc.Height; }
        }
        if (SUCCEEDED(device->GetBackBuffer(0,D3DBACKBUFFER_TYPE_MONO,&back)) && back) {
            if (SUCCEEDED(back->GetDesc(&desc))) { probe.backWidth=desc.Width; probe.backHeight=desc.Height; }
        }
        probe.targetIsBack=target && target==back;
        if (target) target->Release();
        if (back) back->Release();
        device->GetRenderState(D3DRS_BLENDOP,&probe.blendOp);
        device->GetRenderState(D3DRS_FILLMODE,&probe.fillMode);
        device->GetRenderState(D3DRS_CLIPPING,&probe.clipping);
        device->GetVertexShader(&probe.shader);
    }
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
        core=c; Instance=this;
        Shared.Submit = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(&Submit));
        Hud.Submit = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(&SubmitHud));
        Chat.Submit = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(&SubmitChat));
        MODULEINFO module={};
        if (GetModuleInformation(GetCurrentProcess(),GetModuleHandleA("FFXiMain.dll"),&module,sizeof(module))) {
            auto* begin=static_cast<uint8_t*>(module.lpBaseOfDll);
            // Window geometry is shared by party and input; discovery cannot depend on party globals.
            if (auto* rect=UniquePattern(begin,module.SizeOfImage,RECT_PATTERN)) {
                uintptr_t manager=0; memcpy(&manager,rect+RECT_MANAGER_AT,4);
                uintptr_t low=reinterpret_cast<uintptr_t>(begin);
                if (manager>=low && manager<=low+module.SizeOfImage-0x84) {
                    menuManager=reinterpret_cast<uint8_t*>(manager); Shared.GeometryReady=1;
                }
            }
            // HUD discovery is independent of party/window recognition. Compass replacement needs
            // the nested clock boundary too, so replacing radar can never swallow an ordinary clock.
            auto hud=FindHud(begin,module.SizeOfImage);
            if (hud.clock && Take(ClockDetour,begin,module.SizeOfImage)) {
                compassGlobal=hud.global; nativeWeather=hud.weather; Hud.SupportedMask=HUD_CLOCK;
                TakeClockText(TextCall,hud.text,hud.textTarget,reinterpret_cast<void*>(&DrawClockText));
                void* const iconReplacements[3]={reinterpret_cast<void*>(&DrawClockIcon<0>),
                    reinterpret_cast<void*>(&DrawClockIcon<1>),reinterpret_cast<void*>(&DrawClockIcon<2>)};
                TakeClockIcons(IconCalls,hud.icons,hud.iconTarget,iconReplacements);
                bank=reinterpret_cast<void*(__cdecl*)(int32_t)>(hud.bank);
                if (hud.radarVisible && Take(CompassDetour,begin,module.SizeOfImage)) {
                    radarVisible=reinterpret_cast<bool(__cdecl*)()>(hud.radarVisible);
                    Hud.SupportedMask|=HUD_COMPASS;
                }
            }
            // Chat recognition must not depend on party globals/signatures.
            if (chat.Discover(begin,module.SizeOfImage) && Take(WindowDetour,begin,module.SizeOfImage)) {
                Chat.SupportedMask=3 | (chat.InputSupported() ? 4 : 0) | (chat.ExpandedSupported() ? CHAT_FULL_SUPPORTED : 0);
                const auto controls=DiscoverChatControls(begin,module.SizeOfImage,WindowDetour.target,chat.ExpandedDraw());
                if (chat.ExpandedDraw() && Take(ExpandedChatDetour,begin,module.SizeOfImage)) {
                    Chat.SupportedMask |= CHAT_FULL_SKIN_SUPPORTED;
                    void* callbacks[]={reinterpret_cast<void*>(&DrawChatTab),reinterpret_cast<void*>(&DrawChatSelection),
                        reinterpret_cast<void*>(&DrawChatCursor),reinterpret_cast<void*>(&DrawChatScroll),reinterpret_cast<void*>(&DrawChatTabs)};
                    if (TakeChatControls(ChatControls,controls,callbacks)) Chat.SupportedMask |= CHAT_CONTROLS_SUPPORTED | CHAT_REPLACE_SUPPORTED;
                }
            }
            auto* party=FindPattern(begin,module.SizeOfImage,PARTY_PATTERN);
            uintptr_t main=0;
            if (party) memcpy(&main,party+PARTY_GLOBAL_AT,4);
            if (main && PartyGlobals(begin,module.SizeOfImage,main,globals)
                && (WindowDetour.trampoline || Take(WindowDetour,begin,module.SizeOfImage))) {
                Shared.SupportedMask=7; Shared.Hooked=1;
                uintptr_t target=0; memcpy(&target,party+TARGET_GLOBAL_AT,4);
                globals[3]=TargetGlobal(begin,module.SizeOfImage,target);
                if (globals[3] && TakeArrows(Arrows,begin,module.SizeOfImage,reinterpret_cast<void*>(&DrawTargetArrow))) {
                    Shared.SupportedMask|=8;
                } else globals[3]=nullptr; // party mode still works if target discovery fails
            }
        }
        core->GetChatManager()->Write(0,false, Shared.Hooked ?
            (Shared.SupportedMask & 8 ? "[uihook:party] Party/target hooks ready (native arrows preserved). /pt native [target] on; unload hideparty first." :
             "[uihook:party] Party hook ready; target/cursor signatures unavailable. /pt native on; unload hideparty first.") :
            "[uihook:party] Client not recognised; native lists unchanged.");
        core->GetChatManager()->Write(0,false,Hud.SupportedMask==3 ?
            "[uihook:hud] Clock/compass hooks ready. Unload hidecompass before clock replacement." :
            "[uihook:hud] Clock/compass replacement unavailable or partial; unsupported HUD unchanged.");
        return true;
    }
    void Stop() { for (unsigned i=0;i<6;i++) drawings[i].Clear(); staging.Clear(); }
    void StopHud() { drawings[6].Clear(); drawings[7].Clear(); staging.Clear(); }
    void Release() override {
        Shared.Hooked=0; Shared.Submit=0; Shared.GeometryReady=0;
        Hud.SupportedMask=0; Hud.Submit=0;
        Chat.SupportedMask=0; Chat.Submit=0; Chat.InputRectFrame=Chat.PrimaryRectFrame=Chat.ExpandedRectFrame=Chat.StateFrame=Chat.StateFlags=0; chat.Clear(); StopChat();
        GiveClockText(TextCall); GiveClockIcons(IconCalls); Hud.HideIcons=0; Hud.WeatherShift=0; Hud.PreviewWeather=0; Hud.WeatherScale=0; bank=nullptr; Give(CompassDetour); Give(ClockDetour); compassGlobal=nullptr;
        GiveArrows(Arrows); GiveChatControls(ChatControls); Give(ExpandedChatDetour); Give(WindowDetour); blocking=targetScope=expandedSkin=false; ReleaseStates(); Stop(); StopHud(); Instance=nullptr;
    }
    bool Direct3DInitialize(IDirect3DDevice8*) override { return true; }
    void Direct3DPresent(const RECT*,const RECT*,HWND,const RGNDATA*) override {
        ++Shared.Frame;
        Hud.Frame=Chat.Frame=Shared.Frame;
        chat.Sample(Chat,Shared.Frame);
        // As namehook: no cross-frame state blocks holding client resources across a reset.
        ReleaseStates();
        for (auto& d:drawings) if (!d.Fresh()) d.Clear();
    }
    void Direct3DBeginScene(bool) override { inScene=true; }
    void Direct3DEndScene(bool) override { inScene=false; }
    bool Direct3DDrawPrimitive(D3DPRIMITIVETYPE,UINT,UINT) override { Native(false,nullptr,0,0); return Block(); }
    bool Direct3DDrawIndexedPrimitive(D3DPRIMITIVETYPE,UINT,UINT,UINT,UINT) override { Native(false,nullptr,0,0); return Block(); }
    bool Direct3DDrawPrimitiveUP(D3DPRIMITIVETYPE t,UINT count,const void* data,UINT stride) override {
        if (scaling) return false; // our own scaled copy, on its way to the device
        Native(true,data,stride,t==D3DPT_TRIANGLELIST ? count*3 : t==D3DPT_TRIANGLESTRIP || t==D3DPT_TRIANGLEFAN ? count+2 : 0);
        if (Block()) return true;
        return ScaleIcon(t,count,data,stride);
    }
    bool Direct3DDrawIndexedPrimitiveUP(D3DPRIMITIVETYPE t,UINT min,UINT vertices,UINT count,const void* indices,D3DFORMAT format,const void* data,UINT stride) override {
        if (scaling) return false;
        Native(true,data,stride,vertices);
        if (Block()) return true;
        auto* device=core->GetDirect3DDevice(); DWORD shader=0;
        if (!inClock || min!=0 || (clockShiftX==0 && clockShiftY==0) || !data || stride<8 || !vertices || vertices>4096
            || !device || FAILED(device->GetVertexShader(&shader)) || !(shader & D3DFVF_XYZRHW)) return false;
        scaledVertices.assign(static_cast<const uint8_t*>(data),static_cast<const uint8_t*>(data)+size_t(vertices)*stride);
        if (!ChatTranslateVertices(scaledVertices.data(),vertices,stride,clockShiftX,clockShiftY)) return false;
        scaling=true;
        const bool ok=SUCCEEDED(device->DrawIndexedPrimitiveUP(t,min,vertices,count,indices,format,scaledVertices.data(),stride));
        scaling=false;
        return ok;
    }
    bool HandleCommand(int32_t,const char* command,bool) override {
        if (command && _stricmp(command,"/uihook chat")==0) {
            char line[256];
            snprintf(line,sizeof(line),"[uihook:chat] ABI 9, mask %u, frame %u; primary native/drawn %u/%u, split %u/%u, input %u/%u.",
                Chat.SupportedMask,Chat.Frame,Chat.NativeFrame[0],Chat.DrawnFrame[0],Chat.NativeFrame[1],Chat.DrawnFrame[1],Chat.NativeFrame[2],Chat.DrawnFrame[2]);
            core->GetChatManager()->Write(0,false,line);
            snprintf(line,sizeof(line),"[uihook:chat] state 0x%x at %u, full bounds at %u; history scroll %u, cursor %u/%u, filter %u (browsing/filter menus remain native).",
                Chat.StateFlags,Chat.StateFrame,Chat.ExpandedRectFrame,Chat.FullScroll,Chat.FullCursor,Chat.FullPageRows,Chat.FullFilter);
            core->GetChatManager()->Write(0,false,line);
            snprintf(line,sizeof(line),"[uihook:chat] replacing %u (1 tabs, 2 scrollbar); %u tabs measured at %u; scrollbar page %u of %u rows, %u above, at %u.",
                replaceControls,Chat.TabCount,Chat.TabFrame,Chat.ScrollPage,Chat.ScrollCount,Chat.ScrollTop,Chat.ScrollFrame);
            core->GetChatManager()->Write(0,false,line);
            return true;
        }
        if (!command || _stricmp(command,"/uihook hud")!=0) return false;
        auto* chat=core->GetChatManager();
        char line[256];
        const auto& p=probe;
        auto write=[&](const char* text) { chat->Write(0,false,text); };
        snprintf(line,sizeof(line),"[uihook:hud] frame %u, mask %u; Clock::Draw %u calls (%u last frame), at %d,%d; seen %u, drawn %u",
            Shared.Frame,Hud.SupportedMask,p.calls,p.callsLast,int32_t(p.x),int32_t(p.y),Hud.NativeFrame[0],Hud.DrawnFrame[0]); write(line);
        char grid[9]={}; memcpy(grid,Hud.Grid,8);
        for (char& c:grid) if (c && (c<32 || c>126)) c='?';
        snprintf(line,sizeof(line),"[uihook:hud] game's clock text in ImGui pixels %.0f,%.0f to %.0f,%.0f at frame %u; text call %s; grid \"%s\"",
            Hud.ClockRect[0],Hud.ClockRect[1],Hud.ClockRect[2],Hud.ClockRect[3],Hud.ClockRectFrame,
            TextCall.call ? "taken (icons left to the game)" : "not found (icons replaced too)",grid); write(line);
        snprintf(line,sizeof(line),"[uihook:hud] icon calls %s; addon draws its own: %s%s; day at %.0f,%.0f (frame %u), weather at %.0f,%.0f (frame %u)",
            IconCalls.original ? "taken" : "not found (the game's icons only)",
            Hud.HideIcons & HUD_ICON_DAY ? "day " : "", Hud.HideIcons & HUD_ICON_WEATHER ? "weather" : (Hud.HideIcons ? "" : "none"),
            Hud.IconRect[0][0],Hud.IconRect[0][1],Hud.IconFrame[0],Hud.IconRect[1][0],Hud.IconRect[1][1],Hud.IconFrame[1]); write(line);
        snprintf(line,sizeof(line),"[uihook:hud] weather icon moved %d of the game's units, scaled %.2f; all weather shown: 0x%02x (banks %s)",
            int(Hud.WeatherShift),double(Hud.WeatherScale),unsigned(Hud.PreviewWeather & 0xff),bank ? "found" : "not found");
        write(line);
        snprintf(line,sizeof(line),"[uihook:hud] replay at frame %u: %u vertices, %u runs, captured %.0fx%.0f, drawn %.0f,%.0f to %.0f,%.0f",
            p.replayFrame,p.vertices,p.runs,p.width,p.height,p.minX,p.minY,p.maxX,p.maxY); write(line);
        snprintf(line,sizeof(line),"[uihook:hud] viewport %lu,%lu %lux%lu z %.2f-%.2f; target %ux%u, back buffer %ux%u, target is back buffer %d, in scene %d",
            p.viewport.X,p.viewport.Y,p.viewport.Width,p.viewport.Height,p.viewport.MinZ,p.viewport.MaxZ,
            p.targetWidth,p.targetHeight,p.backWidth,p.backHeight,int(p.targetIsBack),int(p.scene)); write(line);
        snprintf(line,sizeof(line),"[uihook:hud] game's states: blend op %lu, fill %lu, clipping %lu, shader 0x%lx; game's clock: %u draws, shader 0x%lx, %u screen vertices %.0f,%.0f to %.0f,%.0f",
            p.blendOp,p.fillMode,p.clipping,p.shader,p.nativeCalls,p.nativeShader,p.nativeUP,p.nMinX,p.nMinY,p.nMaxX,p.nMaxY); write(line);
        return true;
    }

    int Capture(int index, int capture) {
        if (index<0) { Stop(); return 1; }
        if (index>10) return 0;
        Drawing& out=drawings[index];
        if (capture<0) { out.Clear(); return 1; }
        if (index<6 ? (!Shared.Hooked || !(Shared.SupportedMask & (index<3 ? (1u<<index) : 8u)))
                    : index<8 ? !(Hud.SupportedMask & (1u<<(index-6)))
                              : !(Chat.SupportedMask & (1u<<(index-8)))) return 0;
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
        if (index==8 && !out.vertices.empty()) {
            const ImVec2 pos=gui->GetWindowPos(), size=gui->GetWindowSize();
            if (std::isfinite(pos.x) && std::isfinite(pos.y) && std::isfinite(size.x) && std::isfinite(size.y) && size.x>0 && size.y>0) {
                Chat.ReplacementRect[0]=pos.x; Chat.ReplacementRect[1]=pos.y;
                Chat.ReplacementRect[2]=pos.x+size.x; Chat.ReplacementRect[3]=pos.y+size.y;
                Chat.ReplacementRectFrame=Shared.Frame;
            }
        }
        // Keep ImGui's layout and hit-testing; consume only its GPU commands, after making a complete copy.
        for (int c=0;c<list->CmdBuffer.Size;c++) list->CmdBuffer[c].ElemCount=0;
        return 1;
    }

    bool Replay(unsigned index) {
        Drawing& drawing=drawings[index];
        if (!drawing.Fresh()) return false;
        if (drawing.vertices.empty()) {
            if (index>=8) Chat.DrawnFrame[index-8]=Shared.Frame;
            return true; // explicit empty replacement (solo/faded/hidden list)
        }
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
        if (index==6) ProbeDevice(device,viewport,drawing);
        if (FAILED(device->CaptureStateBlock(saved))) return false;
        device->ApplyStateBlock(states);
        bool ok=true;
        for (const auto& r:drawing.runs) if (r.count) {
            device->SetTexture(0,r.texture);
            if (FAILED(device->DrawPrimitiveUP(D3DPT_TRIANGLELIST,r.count/3,&transformed[r.first],sizeof(PartyVertex)))) ok=false;
        }
        device->ApplyStateBlock(saved);
        if (ok) {
            drawing.drawn=Shared.Frame;
            if (index<6) Shared.DrawnFrame[index]=Shared.Frame;
            else if (index<8) Hud.DrawnFrame[index-6]=Shared.Frame;
            else Chat.DrawnFrame[index-8]=Shared.Frame;
            ++Shared.Replays;
        }
        return ok;
    }
    void Compass(void* object) {
        // Always run native update/navigation code. Only GPU submissions in a fresh replacement
        // scope are blocked; the nested clock callback temporarily escapes this filter.
        HudDrawScope scope(blocking,targetScope);
        const bool own=compassGlobal && *compassGlobal==object;
        if (own && static_cast<uint8_t*>(object)[0x0d] && radarVisible && radarVisible()) {
            Hud.NativeFrame[1]=Shared.Frame;
            blocking=Replay(7);
        }
        reinterpret_cast<void(__fastcall*)(void*,void*)>(CompassDetour.trampoline)(object,nullptr);
    }
    void Clock(void* object,int32_t x,int32_t y) {
        HudDrawScope scope(blocking,targetScope);
        clockShiftX=clockShiftY=0;
        auto* gui=core->GetGuiManager(); auto* device=core->GetDirect3DDevice(); D3DVIEWPORT8 viewport;
        float dx=0,dy=0;
        if (compassGlobal && *compassGlobal==object && gui && device && SUCCEEDED(device->GetViewport(&viewport))) {
            const ImVec2 display=gui->GetIO().DisplaySize;
            if (ChatClockOffset(Chat,display.x,display.y,dx,dy)) {
                clockShiftX=dx*viewport.Width/display.x; clockShiftY=dy*viewport.Height/display.y;
            }
        }
        if (probe.callsFrame!=Shared.Frame) { probe.callsLast=probe.calls; probe.calls=0; probe.callsFrame=Shared.Frame; probe.nativeCalls=probe.nativeUP=0; }
        ++probe.calls; probe.x=uint32_t(x); probe.y=uint32_t(y);
        // Clock::Draw takes this + two stack coordinates and returns with ret 8. Preserve all
        // arguments and let its original logic refresh the client's own time buffer even if hidden.
        if (compassGlobal && *compassGlobal==object && static_cast<uint8_t*>(object)[0x2e]) {
            Hud.NativeFrame[0]=Shared.Frame;
            Hud.Weather=nativeWeather ? *nativeWeather : 0xffff;
            const bool replaced=Replay(6);
            // With the text call taken only the game's text gives way; its icons are drawn as ever
            if (TextCall.call) hideText=replaced; else blocking=replaced;
            // the addon's own icons only while its line is drawn: otherwise the game's are back
            hideIcons=replaced && IconCalls.original ? Hud.HideIcons & (HUD_ICON_DAY|HUD_ICON_WEATHER) : 0;
            weatherShift=replaced && IconCalls.original ? (std::max)(-HUD_SHIFT_MOST,(std::min)(HUD_SHIFT_MOST,Hud.WeatherShift)) : 0;
            preview=replaced && IconCalls.original && bank ? Hud.PreviewWeather & 0xff : 0;
            const float scale=Hud.WeatherScale;
            weatherScale=replaced && IconCalls.original && scale>=HUD_SCALE_LEAST && scale<=HUD_SCALE_MOST ? scale : 1;
        }
        bounds=ClockBounds();
        for (auto& icon:iconBounds) icon=ClockBounds();
        clockViewportKnown=false;
        inClock=true;
        reinterpret_cast<void(__fastcall*)(void*,void*,int32_t,int32_t)>(ClockDetour.trampoline)(object,nullptr,x,y);
        inClock=inText=hideText=false; inIcon=-1; hideIcons=0; weatherShift=0; preview=0; weatherScale=1;
        if (compassGlobal && *compassGlobal==object) {
            PublishClockRect();
            const char* grid=static_cast<const char*>(object)+CLOCK_GRID_AT;
            memset(Hud.Grid,0,sizeof(Hud.Grid));
            memcpy(Hud.Grid,grid,8);
        }
    }
    // The game's text still runs, so it is measured where it would be; drawn only when not replaced.
    void Text(int32_t x,int32_t y,const char* text,uint32_t color) {
        const bool was=blocking;
        inText=true; blocking=hideText;
        TextCall.original(x,y,text,color);
        inText=false; blocking=was;
    }
    // An icon still runs, so it is measured where it would be; drawn unless the addon draws its own.
    void Icon(int icon,void* sprite,int32_t x,int32_t y,uint32_t color,uint32_t a,uint32_t b) {
        const bool was=blocking;
        const uint32_t mask=icon==0 ? HUD_ICON_DAY : HUD_ICON_WEATHER;
        if (icon>0) y+=weatherShift;
        inIcon=icon; if (hideIcons & mask) blocking=true;
        IconCalls.original(sprite,nullptr,x,y,color,a,b);
        inIcon=-1; blocking=was;
        // the day icon is drawn whatever the weather: the preview's row is drawn after it
        if (icon==0 && preview) Preview(x,y-CLOCK_WEATHER_ABOVE_DAY+weatherShift,color,a,b);
    }
    // The game's own weather icons, each in its place in a row from the weather icon's, a sprite's
    // width and two apart, drawn as the game draws its weather icon; not measured, never hidden.
    void Preview(int32_t x,int32_t y,uint32_t color,uint32_t a,uint32_t b) {
        auto* from=static_cast<uint8_t*>(bank(CLOCK_WEATHER_BANK));
        void** sprites=from ? *reinterpret_cast<void***>(from) : nullptr;
        if (!sprites) return;
        const bool was=blocking;
        blocking=false; previewing=true;
        for (int i=0;i<8;i++) {
            auto* sprite=static_cast<uint8_t*>(sprites[i]);
            if (!sprite) continue;
            int16_t left=0,right=0; memcpy(&left,sprite+0x20,2); memcpy(&right,sprite+0x22,2);
            const int32_t width=right>left && right-left<=64 ? right-left : 16;
            // each grown about its own middle: the places are as far apart as the grown icons and two
            const int32_t step=static_cast<int32_t>(width*weatherScale+0.5f)+2;
            if (preview & (1u<<i)) IconCalls.original(sprite,nullptr,x+i*step,y,color,a,b);
        }
        blocking=was; previewing=false;
    }
    void Slots(PartySlots& out) const {
        out.loaded=true;
        out.partyHooked=Shared.Hooked && (Shared.SupportedMask & 7);
        out.targetHooked=Shared.Hooked && (Shared.SupportedMask & 8);
        out.clockHooked=(Hud.SupportedMask & HUD_CLOCK)!=0;
        out.compassHooked=(Hud.SupportedMask & HUD_COMPASS)!=0;
        out.chatHooked=Chat.SupportedMask!=0;
        for (unsigned i=0;i<11;i++) {
            if (!drawings[i].Fresh()) continue;
            const uint8_t bit=static_cast<uint8_t>(1u<<(i<6 ? i : i<8 ? i-6 : i-8));
            const bool empty=drawings[i].vertices.empty();
            if (i<6) { out.fresh|=bit; if (empty) out.empty|=bit; }
            else if (i<8) { out.hudFresh|=bit; if (empty) out.hudEmpty|=bit; }
            else { out.chatFresh|=bit; if (empty) out.chatEmpty|=bit; }
        }
    }
    void StopChat() { drawings[8].Clear(); drawings[9].Clear(); drawings[10].Clear(); staging.Clear(); Chat.ReplacementRectFrame=0; expandedCapture=controlsValid=false; replaceControls=0; Chat.ControlStyleFrame=0; Chat.TabFrame=Chat.ScrollFrame=0; }
    int CaptureChat(int index,int capture) {
        if (index==-1) { StopChat(); return 1; }
        if (index<0 || index>2 || capture>2) return 0;
        if (capture==2 && (index!=0 || !(Chat.SupportedMask & CHAT_FULL_SKIN_SUPPORTED))) return 0;
        chat.Sample(Chat,Shared.Frame);
        if (index==0) { Chat.ReplacementRectFrame=0; expandedCapture=controlsValid=false; replaceControls=0; }
        const int result=Capture(index+8,capture==2 ? 1 : capture);
        if (index==0 && result && capture>0) {
            expandedCapture=capture==2;
            controlsValid=expandedCapture && (Chat.SupportedMask & CHAT_CONTROLS_SUPPORTED) && controlStyle.Read(Chat);
            // the addon's own tabs and scrollbar stand in only while its frame does, and only where the hooks are
            replaceControls=controlsValid && (Chat.SupportedMask & CHAT_REPLACE_SUPPORTED) ? Chat.ReplaceControls & (CHAT_REPLACE_TABS|CHAT_REPLACE_SCROLL) : 0;
        }
        if (!result) drawings[index+8].Clear(); // failed capture restores native even after an empty Begin
        return result;
    }
    int CaptureHud(int index,int capture) {
        if (index==-1) { StopHud(); return 1; }
        if (index<0 || index>1) return 0;
        return Capture(index+6,capture);
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
    bool WindowRect(void* window,NativeRect& result) {
        if (!menuManager) return false;
        auto* device=core->GetDirect3DDevice(); D3DVIEWPORT8 viewport;
        if (!device || FAILED(device->GetViewport(&viewport))) return false;
        int16_t rect[4], dimensions[2]; uint8_t scaled=0;
        auto* data=static_cast<const uint8_t*>(window);
        if (!ChatRead(data+0x3a,rect,sizeof(rect)) || !ChatRead(data+0x99,&scaled,1)
            || !ChatRead(menuManager+0x80,dimensions,sizeof(dimensions))) return false;
        return MakeNativeRect(rect,scaled!=0,dimensions[0],dimensions[1],viewport.Width,viewport.Height,Shared.Frame,result);
    }
    void RecordRect(unsigned index,void* window) {
        NativeRect result={};
        if (WindowRect(window,result)) Shared.Rects[index]=result;
        else Shared.Rects[index].Frame=0;
    }
    void RecordChatRect(int index,void* window) {
        NativeRect result={};
        float* rect=index==0 ? Chat.PrimaryRect : index==3 ? Chat.ExpandedRect : Chat.InputRect;
        uint32_t& frame=index==0 ? Chat.PrimaryRectFrame : index==3 ? Chat.ExpandedRectFrame : Chat.InputRectFrame;
        frame=0;
        if (!WindowRect(window,result)) return;
        rect[0]=result.Left; rect[1]=result.Top; rect[2]=result.Right; rect[3]=result.Bottom;
        frame=result.Frame;
    }
    bool ControlsActive() const { return expandedSkin && controlsValid; }
    // The whole tab strip: measured tab by tab in a skinned full log, and left undrawn (art and labels alike)
    // where the addon draws its own tabs; the game's hit-tests and Square selection are untouched either way.
    void ChatTabs(void* owner,uint32_t filter) {
        const bool measure=expandedSkin && owner && owner==expandedOwner;
        const bool was=blocking;
        if (ChatHidden(replaceControls,CHAT_REPLACE_TABS,measure && controlsValid)) blocking=true;
        tabCount=0; measuringTabs=measure;
        reinterpret_cast<ChatTabStrip>(ChatControls.targets[CHAT_ART_TABS])(owner,nullptr,filter);
        measuringTabs=false; chatMeasure=nullptr; blocking=was;
        if (!measure) return;
        unsigned published=0;
        for (unsigned i=0;i<tabCount && published<12;i++) {
            auto& tab=Chat.Tabs[published];
            if (!NormalizeChat(tabBounds[i],tab.Rect)) continue;
            tab.Channel=tabChannels[i]; tab.Selected=tabSelected[i] ? 1 : 0; published++;
        }
        Chat.TabCount=published; Chat.TabFrame=published ? Shared.Frame : 0;
    }
    void ChatTab(void* sprite,uint32_t x,uint32_t y,uint32_t color,uint32_t a,uint32_t b) {
        if (measuringTabs && tabCount<12) {
            uint32_t channel=0xffffffff; bool selected=false;
            ChatTabChannel(expandedOwner,sprite,channel,selected);
            tabBounds[tabCount]=ChatBounds(); tabChannels[tabCount]=channel; tabSelected[tabCount]=selected;
            chatMeasure=&tabBounds[tabCount];
        }
        ForwardChatTab(reinterpret_cast<ChatTabSprite>(ChatControls.targets[CHAT_ART_TAB]),ControlsActive(),controlStyle,expandedOwner,
            sprite,x,y,color,a,b);
        if (chatMeasure) { if (chatMeasure->vertices) tabCount++; chatMeasure=nullptr; }
    }
    void ChatWindowArt(bool cursor,void* sprite,uint32_t x,uint32_t y,uint32_t sx,uint32_t sy,uint32_t color,uint32_t a,uint32_t b,uint32_t c) {
        ForwardChatWindowArt(reinterpret_cast<ChatWindowSprite>(ChatControls.targets[cursor ? CHAT_ART_CURSOR : CHAT_ART_SELECTION]),
            expandedSkin,ControlsActive(),controlStyle,cursor,blocking,sprite,x,y,sx,sy,color,a,b,c);
    }
    // The scrollbar: its page, count and rows above the view read and its bounds measured in a skinned full
    // log, and left undrawn where the addon draws its own; the native object is never written.
    void ChatScroll(void* object) {
        const bool measure=expandedSkin;
        ChatScrollInfo info;
        const bool fields=measure && ChatScrollRead(object,info);
        const bool was=blocking;
        if (ChatHidden(replaceControls,CHAT_REPLACE_SCROLL,measure && controlsValid)) blocking=true;
        if (measure) { scrollBounds=ChatBounds(); chatMeasure=&scrollBounds; }
        ForwardChatScroll(reinterpret_cast<ChatScrollDraw>(ChatControls.targets[CHAT_ART_SCROLL]),ControlsActive(),controlStyle,object);
        chatMeasure=nullptr; blocking=was;
        if (!measure) return;
        Chat.ScrollFrame=0;
        if (fields && NormalizeChat(scrollBounds,Chat.ScrollRect)) {
            Chat.ScrollPage=info.page; Chat.ScrollCount=info.count; Chat.ScrollTop=info.top; Chat.ScrollFrame=Shared.Frame;
        }
    }
    void ExpandedContent(void* owner) {
        ChatNativeContent(expandedSkin,blocking);
        ChatOwnerScope ownerScope(expandedOwner,expandedSkin ? owner : nullptr);
        reinterpret_cast<void(__fastcall*)(void*,void*)>(ExpandedChatDetour.trampoline)(owner,nullptr);
    }
    void Render(void* window) {
        int index=-1;
        for (int i=0;i<4;i++) {
            void* object=globals[i] ? *globals[i] : nullptr;
            if (object && *reinterpret_cast<void**>(static_cast<uint8_t*>(object)+OBJECT_WINDOW)==window) { index=i; break; }
        }
        bool was=blocking, wasTarget=targetScope, wasExpanded=expandedSkin;
        expandedSkin=false;
        blocking=false; // replacement GPU calls must not be caught by our own callbacks
        const int chatIndex=chat.Identify(window);
        const int chatSlot=chatIndex==3 ? 0 : chatIndex;
        bool chatReady=true;
        if (chatIndex>=0) {
            chat.Sample(Chat,Shared.Frame);
            Chat.NativeFrame[chatSlot]=Shared.Frame;
            // Full-log captures replace only the frame, never the native rows/actions. A compact
            // capture must not cover a newly opened full log (or vice versa).
            if (chatSlot==0) chatReady=ChatReplayAllowed(Chat,expandedCapture)
                && (expandedCapture ? chatIndex==3 && !drawings[8].vertices.empty() : chatIndex==0);
            else chatReady=!(Chat.StateFlags & CHAT_EXPANDED); // no stale input/split captures over expanded native UI
        }
        bool replaced=chatIndex>=0 ? chatReady && Replay(static_cast<unsigned>(chatSlot+8))
            : index==3 ? ReplayTargets() : index>=0 && Replay(static_cast<unsigned>(index));
        blocking=replaced;
        expandedSkin=chatIndex==3 && replaced && expandedCapture;
        // a full log drawn afresh: its tabs and scrollbar measured again, or not at all if the game leaves them out
        if (chatIndex==3) { Chat.TabFrame=Chat.ScrollFrame=0; chatViewportKnown=false; chatMeasure=nullptr; measuringTabs=false; }
        targetScope=index==3 && replaced;
        reinterpret_cast<void(__fastcall*)(void*,void*)>(WindowDetour.trampoline)(window,nullptr);
        // Read after the client's animation/layout update, even when this window is not replaced.
        // No native positioning/state writes: Lua uses this geometry for its next submission.
        if (index>=0) RecordRect(static_cast<unsigned>(index),window);
        if (chatIndex==0 || chatIndex==2 || chatIndex==3) RecordChatRect(chatIndex,window);
        blocking=was; targetScope=wasTarget; expandedSkin=wasExpanded;
    }
};
PartyHook* PartyHook::Instance=nullptr;
static void __fastcall DrawChatTab(void* sprite,void*,uint32_t x,uint32_t y,uint32_t color,uint32_t a,uint32_t b) {
    if (PartyHook::Instance) PartyHook::Instance->ChatTab(sprite,x,y,color,a,b);
    else reinterpret_cast<ChatTabSprite>(ChatControls.targets[CHAT_ART_TAB])(sprite,nullptr,x,y,color,a,b);
}
static void __fastcall DrawChatSelection(void* sprite,void*,uint32_t x,uint32_t y,uint32_t sx,uint32_t sy,uint32_t color,uint32_t a,uint32_t b,uint32_t c) {
    if (PartyHook::Instance) PartyHook::Instance->ChatWindowArt(false,sprite,x,y,sx,sy,color,a,b,c);
    else reinterpret_cast<ChatWindowSprite>(ChatControls.targets[CHAT_ART_SELECTION])(sprite,nullptr,x,y,sx,sy,color,a,b,c);
}
static void __fastcall DrawChatCursor(void* sprite,void*,uint32_t x,uint32_t y,uint32_t sx,uint32_t sy,uint32_t color,uint32_t a,uint32_t b,uint32_t c) {
    if (PartyHook::Instance) PartyHook::Instance->ChatWindowArt(true,sprite,x,y,sx,sy,color,a,b,c);
    else reinterpret_cast<ChatWindowSprite>(ChatControls.targets[CHAT_ART_CURSOR])(sprite,nullptr,x,y,sx,sy,color,a,b,c);
}
static void __fastcall DrawChatTabs(void* owner,void*,uint32_t filter) {
    if (PartyHook::Instance) PartyHook::Instance->ChatTabs(owner,filter);
    else reinterpret_cast<ChatTabStrip>(ChatControls.targets[CHAT_ART_TABS])(owner,nullptr,filter);
}
static void __fastcall DrawChatScroll(void* object,void*) {
    if (PartyHook::Instance) PartyHook::Instance->ChatScroll(object);
    else reinterpret_cast<ChatScrollDraw>(ChatControls.targets[CHAT_ART_SCROLL])(object,nullptr);
}
static void __fastcall DrawExpandedChat(void* owner,void*) {
    if (PartyHook::Instance) PartyHook::Instance->ExpandedContent(owner);
    else reinterpret_cast<void(__fastcall*)(void*,void*)>(ExpandedChatDetour.trampoline)(owner,nullptr);
}
static void __fastcall RenderWindow(void* window,void*) {
    if (PartyHook::Instance) PartyHook::Instance->Render(window);
    else reinterpret_cast<void(__fastcall*)(void*,void*)>(WindowDetour.trampoline)(window,nullptr);
}
static void __fastcall DrawTargetArrow(void* sprite,void*,uint32_t x,uint32_t y,uint32_t sx,uint32_t sy,uint32_t color,uint32_t a,uint32_t b,uint32_t c) {
    if (PartyHook::Instance) PartyHook::Instance->Arrow(sprite,x,y,sx,sy,color,a,b,c);
    else reinterpret_cast<SpriteDraw>(Arrows.sprite)(sprite,nullptr,x,y,sx,sy,color,a,b,c);
}
static int32_t __cdecl Submit(int32_t index,int32_t capture) {
    if (!PartyHook::Instance || index < -1 || index > 5) return 0;
    try { return PartyHook::Instance->Capture(index,capture); }
    catch (...) { PartyHook::Instance->Stop(); ++Shared.Failures; return 0; }
}
static void __fastcall RenderCompass(void* object,void*) {
    if (PartyHook::Instance) PartyHook::Instance->Compass(object);
    else reinterpret_cast<void(__fastcall*)(void*,void*)>(CompassDetour.trampoline)(object,nullptr);
}
static void __fastcall RenderClock(void* object,void*,int32_t x,int32_t y) {
    if (PartyHook::Instance) PartyHook::Instance->Clock(object,x,y);
    else reinterpret_cast<void(__fastcall*)(void*,void*,int32_t,int32_t)>(ClockDetour.trampoline)(object,nullptr,x,y);
}
template<int Icon> static void __fastcall DrawClockIcon(void* sprite,void*,int32_t x,int32_t y,uint32_t color,uint32_t a,uint32_t b) {
    if (PartyHook::Instance && IconCalls.original) PartyHook::Instance->Icon(Icon,sprite,x,y,color,a,b);
    else if (IconCalls.original) IconCalls.original(sprite,nullptr,x,y,color,a,b);
}
static void __cdecl DrawClockText(int32_t x,int32_t y,const char* text,uint32_t color) {
    if (PartyHook::Instance && TextCall.original) PartyHook::Instance->Text(x,y,text,color);
    else if (TextCall.original) TextCall.original(x,y,text,color);
}
static int32_t __cdecl SubmitHud(int32_t index,int32_t capture) {
    if (!PartyHook::Instance) return 0;
    try { return PartyHook::Instance->CaptureHud(index,capture); }
    catch (...) { PartyHook::Instance->StopHud(); ++Shared.Failures; return 0; }
}
static int32_t __cdecl SubmitChat(int32_t index,int32_t capture) {
    if (!PartyHook::Instance) return 0;
    try { return PartyHook::Instance->CaptureChat(index,capture); }
    catch (...) { PartyHook::Instance->StopChat(); ++Shared.Failures; return 0; }
}
IPlugin* CreatePartyModule() { return new PartyHook(); }

void GetPartySlots(PartySlots& out) {
    out = PartySlots();
    if (PartyHook::Instance) PartyHook::Instance->Slots(out);
}

