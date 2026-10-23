// Experimental native Party replacement. Capture the addon's existing ImGui geometry in C++;
// replay it at Window::Render, executing native window logic with only its GPU submissions blocked.
#include <windows.h>
#include <psapi.h>
#include <stdint.h>
#include <vector>
#include <string>
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
#include "../chat/windows.h"
#include "../chat/colors.h"
#include "../chat/menus.h"
#include "../chat/history.h"
#include "../chat/texttap.h"
#include "../mirror/census.h"
#include "../mirror/mirror.h"
#include "../native/native.h"
#include "../mirror/labels.h"
#include "../mirror/textures.h"
#include "../native/skin.h"
#include "../native/skinfile.h"
#include "../mirror/mouse.h"
#include "../mirror/watch.h"
#include "../../slots.h"
#include "clip.h"
#include "runs.h"
#define PARTY_FVF (D3DFVF_XYZRHW | D3DFVF_DIFFUSE | D3DFVF_TEX1)
#include "states.h"

static int32_t __cdecl Submit(int32_t index, int32_t capture);
static void __fastcall RenderWindow(void* window, void*);
static int32_t __cdecl SubmitHud(int32_t index, int32_t capture);
static int32_t __cdecl SubmitChat(int32_t index, int32_t capture);
static ChatShared Chat = { "UIHOOK-CHAT", 13, sizeof(ChatShared), 0, 1, 0, {}, {}, {}, 0, {}, 0, {}, 0, {}, 0, 0, 0, 0, 0, 0, 0, 0, {}, 0, 0, 0, {}, 0, 0, 0, 0, {}, 0, 0, 0, {}, {}, {}, 0, 0, 0, {}, 0, {}, 0, 0, {}, {}, {} };
static MenuShared Menus = { "UIHOOK-MENUS", 1, sizeof(MenuShared), 1, 0, 0, 0, {}, 0, 0, 0, {}, 0, {}, 0, 0, 0 };
// The first log window's history, read when an addon asks (independent history ABI 1)
static ChatHistoryShared History = { "UIHOOK-HISTORY", 1, sizeof(ChatHistoryShared), 0, 0, 0, 0, 0, 0, 0, {}, {} };
static uint32_t historyServed = 0; // the request last served
// Every line given to the game's chat log, as it stands after every plugin and addon before uihook (independent text
// ABI 1): Ashita's own text event, nothing read from the game
// Zero to begin with, its magic written as the module initializes: half a megabyte of ring that is not in the DLL's file
static TextTapShared TextTap;
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
// The one call in the log drawer that draws a row of text, aimed at DrawChatRow while uihook is loaded
static void __cdecl DrawChatRow(const uint16_t*,ChatRowHeader,int32_t,int32_t,uint32_t,uint32_t,void*,uint32_t);
static ChatTextSite ChatText;
// The menu census (/uihook census): the windows drawn and the text they print, heard while it is on
static Census MenuCensus;
static int32_t __cdecl CensusBitmap(int32_t,int32_t,const char*,uint32_t,uint32_t,uint32_t,uint32_t);
static int32_t __cdecl CensusScaled(int32_t,int32_t,const char*,uint32_t,uint32_t,uint32_t,uint32_t);
static uint32_t __fastcall CensusFont(void*,void*,int32_t,int32_t,const char*,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
static Detour CensusBitmapDetour = { CENSUS_TEXT_PATTERN, CENSUS_TEXT_STOLEN, -1, reinterpret_cast<void*>(&CensusBitmap), nullptr, nullptr, {} };
static Detour CensusScaledDetour = { CENSUS_SCALED_PATTERN, CENSUS_SCALED_STOLEN, -1, reinterpret_cast<void*>(&CensusScaled), nullptr, nullptr, {} };
static Detour CensusFontDetour = { CENSUS_FONT_PATTERN, CENSUS_FONT_STOLEN, -1, reinterpret_cast<void*>(&CensusFont), nullptr, nullptr, {} };
// The menu mirror (mirror ABI 5): zero in the DLL's file, its magic written as the module initializes. Its
// text is heard through the census's three routes, taken with Window::Render; the contents' call in
// Window::Render aimed at MirrorContent.
static MirrorShared MirrorBlock;
static Mirror MenuMirror;
static NativeLook NativeMenus; // /uihook native: windows' draws moved and scaled, their frames tinted (native.h)
static TextureCensus Textures; // /uihook textures: every texture the screen-space drawing uses, by window and part (textures.h)
static SkinLook Skin; // /uihook skin: the game's textures drawn with pictures of a skin's in their place (skin.h)
static MirrorWatch MenuWatch; // every window drawn, kept in WatchBlock; with /uihook mirror watch, to logs\uihook-mirror-watch.txt
// exported, as nothing in the DLL reads it back: a block private to it would have every write to it optimized away
extern "C" __declspec(dllexport) MirrorWatchShared UihookWatch{};
static MirrorWatchShared& WatchBlock=UihookWatch;
static bool WatchFile=false;
static void __fastcall MirrorContent(void*,void*);
struct MirrorContentCall { uint8_t* call=nullptr; uint8_t saved[5]={}; };
static MirrorContentCall ContentCall;
// The game's mouse handler in its message loop, taken so a message on a menu drawn elsewhere is given to it at the
// same place on the game's own (mouse.h)
static void __cdecl MirrorInput(MSG);
static uint32_t MirrorMapped=0; // mouse messages given to the game at the place on its own menu, since loading
static Detour InputDetour = { MIRROR_INPUT_PATTERN, MIRROR_INPUT_STOLEN, -1, reinterpret_cast<void*>(&MirrorInput), nullptr, nullptr, {} };
// The five bytes mov edx,[ecx]; call [edx+10] made a call to ours, which makes the same call: the
// return address the game's own, the owner still in ecx
static bool TakeMirrorContent(uint8_t* begin,size_t size,uint8_t* render) {
    auto* site=UniquePattern(begin,size,MIRROR_CONTENT_PATTERN);
    if (!site || !render || site<render || size_t(site-render)>MIRROR_CONTENT_WITHIN) return false;
    uint8_t* call=site+MIRROR_CONTENT_AT;
    static const uint8_t expected[5]={0x8b,0x11,0xff,0x52,0x10};
    if (memcmp(call,expected,5)) return false;
    ContentCall.call=call; memcpy(ContentCall.saved,call,5);
    uint8_t jump[5]={0xe8,0,0,0,0};
    const int32_t distance=Distance(call+5,reinterpret_cast<void*>(&MirrorContent)); memcpy(jump+1,&distance,4);
    WriteCode(call,jump,5);
    return true;
}
static void GiveMirrorContent() {
    if (ContentCall.call) WriteCode(ContentCall.call,ContentCall.saved,5);
    ContentCall=MirrorContentCall();
}

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
    ILogManager* log = nullptr;
    void** globals[4] = {};
    Drawing drawings[11]; // Party 0..5, HUD 6..7, chat logs/input 8..10; independent ABIs
    // Each slot's last refusal (PartyRefusal), the frame of it and how many in a row: for /uihook, and
    // Ashita's log the first time and when the reason changes, so that a refusal leaves a trace
    uint8_t refusal[11] = {}; uint32_t refusedFrame[11] = {}, refusedRun[11] = {};
    ChatModule chat;
    MenuModule menus;
    ChatWindowRoutes windowRoutes; // the two log windows' routing, read from the game's config each frame
    ChatColorTables colorTables;   // the game's chat colours, read each frame
    bool expandedCapture=false, expandedSkin=false, controlsValid=false;
    void* expandedOwner=nullptr;
    ChatControlStyle controlStyle;
    uint32_t replaceControls=0;       // CHAT_REPLACE_* bits, copied with a successful expanded capture
    // The game's tab strip and scrollbar, measured as they are drawn in a skinned full log (hidden or not)
    ChatBounds* chatMeasure=nullptr;  // the control being drawn, while it is
    bool measuringTabs=false;
    ChatBounds tabBounds[12], scrollBounds; uint32_t tabChannels[12]={}; bool tabSelected[12]={}; unsigned tabCount=0;
    D3DVIEWPORT8 chatViewport={}; bool chatViewportKnown=false;
    // The full log's rows of text, measured and decoded as the game draws them in a skinned full log; the
    // last published kept apart, so that the serial moves only when the rows do
    ChatBounds rowBounds; unsigned rowCount=0; uint32_t textUsed=0;
    ChatBounds selectionBounds[8]; unsigned selectionCount=0; // the game's row-selection art, each call, as drawn in this full log before its rows
    ChatTextRow lastRows[CHAT_TEXT_ROWS]={}; char lastText[CHAT_TEXT_BYTES]={}; unsigned lastRowCount=0; uint32_t lastTextUsed=0;
    uint16_t rowWords[CHAT_ROW_WORDS]={};
    void** compassGlobal = nullptr;
    bool (__cdecl* radarVisible)() = nullptr;
    uint16_t* nativeWeather = nullptr;
    Drawing staging;
    std::vector<PartyVertex> transformed;
    std::vector<uint8_t> scaledVertices; // a weather icon's vertices, drawn larger or smaller
    DWORD states = 0, saved = 0;
    bool blocking = false;
    uint32_t primaryDeferred = 0; // the frame the first log's replay was held back for a second log stacked over it
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
    // /uihook native: the window being drawn taken, where it is one named, for its draws to be moved and tinted
    NativeLook::Saved NativeEnter(void* window) {
        if (!NativeMenus.Any()) return NativeMenus.Enter(nullptr,Shared.Frame);
        void* header=nullptr; char name[16];
        if (!window || !ChatRead(static_cast<uint8_t*>(window)+4,&header,4) || !header
            || !ChatRead(static_cast<uint8_t*>(header)+0x46,name,16)) return NativeMenus.Enter(nullptr,Shared.Frame);
        // where the game draws it (+3A: left, top, right, bottom), not its layout target (+8C), which for some is over the
        // chat log while they are drawn elsewhere (the Master and Automaton menu, beside the main menu)
        int16_t drawn[4];
        if (NativeMenus.groupOn && ChatRead(static_cast<uint8_t*>(window)+0x3a,drawn,sizeof(drawn)) && drawn[2]>drawn[0] && drawn[3]>drawn[1]) {
            const int16_t place[4]={drawn[0],drawn[1],int16_t(drawn[2]-drawn[0]),int16_t(drawn[3]-drawn[1])};
            NativeMenus.Note(name,place,Shared.Frame);
        }
        return NativeMenus.Enter(name,Shared.Frame);
    }
    // A screen-space draw of a window named: counted into its bounds; then, where it is moved or its frame tinted,
    // drawn so in its place (its vertices copied and moved; a second texture stage multiplying the game's own result by
    // the tint, put back after). vertices: from min, as an indexed draw's are.
    // The screen's size: the render target's the draw is made to (read each draw: the scene may be drawn to a larger
    // one first), the viewport's where it cannot be read
    bool ScreenSize(IDirect3DDevice8* device,const D3DVIEWPORT8& viewport,float* out) {
        out[0]=out[1]=0;
        IDirect3DSurface8* target=nullptr; D3DSURFACE_DESC desc{};
        if (SUCCEEDED(device->GetRenderTarget(&target)) && target) {
            if (SUCCEEDED(target->GetDesc(&desc))) { out[0]=float(desc.Width); out[1]=float(desc.Height); }
            target->Release();
        }
        if (!out[0] || !out[1]) { out[0]=float(viewport.X+viewport.Width); out[1]=float(viewport.Y+viewport.Height); }
        return out[0]>0 && out[1]>0;
    }
    bool NativeDraw(D3DPRIMITIVETYPE t,UINT min,UINT vertices,UINT count,const void* indices,D3DFORMAT format,const void* data,UINT stride) {
        NativeEntry* e=NativeMenus.current;
        if (!e || !data || !vertices || stride<8) return false;
        const UINT used=min+vertices;
        auto* device=core->GetDirect3DDevice(); DWORD shader=0,pixel=0;
        if (!device || FAILED(device->GetVertexShader(&shader)) || (shader & D3DFVF_POSITION_MASK)!=D3DFVF_XYZRHW) { NativeMenus.Unmoved(); return false; }
        NativeMenus.Gather(static_cast<const uint8_t*>(data)+size_t(min)*stride,vertices,stride);
        // the screen's size, not the viewport's: the game clips some text to its window with a viewport (the title
        // box's), which taken for the screen made its middle the box's and its words pinched there
        D3DVIEWPORT8 viewport={};
        float screen[2]={};
        NativeTransform move; bool whole=false;
        bool placing=used<=8192 && SUCCEEDED(device->GetViewport(&viewport)) && ScreenSize(device,viewport,screen)
            && NativeMenus.Transform(screen[0],screen[1],move,&whole);
        // wholly outside its frame (the inventory's count, up in the menu name's bar): left where the game put it, but
        // where the whole side is moved
        if (placing && !move.pinch && !whole && !NativeMenus.Within(static_cast<const uint8_t*>(data)+size_t(min)*stride,vertices,stride)) { e->kept++; placing=false; }
        uint32_t colour=0;
        bool tinting=NativeMenus.Tinting(colour);
        DWORD saved[6]={},factor=0,third=D3DTOP_DISABLE;
        static const D3DTEXTURESTAGESTATETYPE kinds[6]={D3DTSS_COLOROP,D3DTSS_COLORARG1,D3DTSS_COLORARG2,D3DTSS_ALPHAOP,D3DTSS_ALPHAARG1,D3DTSS_ALPHAARG2};
        if (tinting) {
            DWORD first[3]={};
            device->GetTextureStageState(0,D3DTSS_COLOROP,&first[0]);
            device->GetTextureStageState(0,D3DTSS_COLORARG1,&first[1]);
            device->GetTextureStageState(0,D3DTSS_COLORARG2,&first[2]);
            for (unsigned i=0;i<3;i++) e->stage[i]=first[i];
            e->lastFormat=shader;
            for (unsigned i=0;i<6;i++) device->GetTextureStageState(1,kinds[i],&saved[i]);
            if (FAILED(device->GetPixelShader(&pixel)) || pixel || saved[0]!=D3DTOP_DISABLE
                || FAILED(device->GetRenderState(D3DRS_TEXTUREFACTOR,&factor))) { e->refused++; tinting=false; }
        }
        if (!placing && !tinting) return false;
        const void* drawn=data;
        if (placing) {
            scaledVertices.assign(static_cast<const uint8_t*>(data),static_cast<const uint8_t*>(data)+size_t(used)*stride);
            NativeTransformVertices(scaledVertices.data()+size_t(min)*stride,vertices,stride,move);
            // the skin's colours for its picture, as SkinEnd would have given them had it drawn it: the moved windows
            // had the game's (the bottom-left buttons blue-grey and orange, the frame faded at the sides)
            if (skinActive>=0 && SkinRecolour(Skin.textures[size_t(skinActive)],scaledVertices.data(),used,stride,shader,skinVertices)) {
                scaledVertices.swap(skinVertices); Skin.textures[size_t(skinActive)].recoloured++;
            }
            drawn=scaledVertices.data();
        }
        IDirect3DBaseTexture8* texture=nullptr;
        if (tinting) {
            device->GetTexture(1,&texture);
            device->SetTexture(1,nullptr);
            device->SetRenderState(D3DRS_TEXTUREFACTOR,colour);
            static const DWORD tint[6]={D3DTOP_MODULATE,D3DTA_CURRENT,D3DTA_TFACTOR,D3DTOP_MODULATE,D3DTA_CURRENT,D3DTA_TFACTOR};
            for (unsigned i=0;i<6;i++) device->SetTextureStageState(1,kinds[i],tint[i]);
            device->GetTextureStageState(2,D3DTSS_COLOROP,&third);
            device->SetTextureStageState(2,D3DTSS_COLOROP,D3DTOP_DISABLE);
        }
        // a viewport clipping the draw to its window moved with it, so what is moved is not clipped away
        const bool clipped=placing && (viewport.X>0 || viewport.Y>0 || float(viewport.Width)<screen[0] || float(viewport.Height)<screen[1]);
        D3DVIEWPORT8 moved=viewport;
        if (clipped) {
            float corners[4]={float(viewport.X),float(viewport.Y),float(viewport.X+viewport.Width),float(viewport.Y+viewport.Height)};
            move.Apply(corners[0],corners[1]); move.Apply(corners[2],corners[3]);
            const float x0=(std::max)(0.0f,corners[0]),y0=(std::max)(0.0f,corners[1]);
            const float x1=(std::min)(screen[0],corners[2]),y1=(std::min)(screen[1],corners[3]);
            if (x1>x0 && y1>y0) {
                moved.X=DWORD(x0+0.5f); moved.Y=DWORD(y0+0.5f); moved.Width=DWORD(x1-x0+0.5f); moved.Height=DWORD(y1-y0+0.5f);
                device->SetViewport(&moved);
            }
        }
        scaling=true;
        const bool ok=indices ? SUCCEEDED(device->DrawIndexedPrimitiveUP(t,min,vertices,count,indices,format,drawn,stride))
            : SUCCEEDED(device->DrawPrimitiveUP(t,count,drawn,stride));
        scaling=false;
        if (clipped) device->SetViewport(&viewport);
        if (tinting) {
            device->SetTextureStageState(2,D3DTSS_COLOROP,third);
            for (unsigned i=0;i<6;i++) device->SetTextureStageState(1,kinds[i],saved[i]);
            device->SetRenderState(D3DRS_TEXTUREFACTOR,factor);
            device->SetTexture(1,texture); if (texture) texture->Release();
            if (ok) e->tinted++; else e->refused++;
        }
        if (placing && ok) e->moved++;
        return ok;
    }
    // /uihook skin: a screen-space draw whose texture (stage 0) the skin has a picture for is given it; what was there
    // comes back to be put back by SkinEnd. Nothing where no skin is loaded.
    struct SkinSwap { int32_t index=-1; IDirect3DBaseTexture8* was=nullptr; DWORD filters[3]={}; };
    // stage 0's filters while a skin's picture is in it: linear, with its levels, so one made larger than it is
    // drawn shrinks smoothly and one drawn larger is not blocky
    static constexpr D3DTEXTURESTAGESTATETYPE SkinFilters[3]={D3DTSS_MAGFILTER,D3DTSS_MINFILTER,D3DTSS_MIPFILTER};
    int32_t skinActive=-1;   // the skin's picture in stage 0 for the draw under way, for NativeDraw's colours, or -1
    SkinSwap SkinBegin() {
        SkinSwap swap;
        if (!Skin.On()) return swap;
        auto* device=core->GetDirect3DDevice(); DWORD fvf=0;
        if (!device || FAILED(device->GetVertexShader(&fvf)) || (fvf & D3DFVF_POSITION_MASK)!=D3DFVF_XYZRHW) return swap;
        if (FAILED(device->GetTexture(0,&swap.was)) || !swap.was) { swap.was=nullptr; return swap; }
        IDirect3DBaseTexture8* game=swap.was;
        swap.index=Skin.Lookup(reinterpret_cast<uintptr_t>(game),Shared.Frame,[&](uint32_t& hash) {
            LabelPixels pixels; D3DSURFACE_DESC desc{}; uint32_t texels[4]; const char* why="";
            static const float whole[4]={0,0,1,1};
            if (!LabelCut(game,whole,pixels,desc,texels,why)) return false;
            hash=TextureHash(pixels,desc.Width,desc.Height); return true;
        });
        if (swap.index<0) { swap.was->Release(); swap.was=nullptr; return swap; }
        device->SetTexture(0,static_cast<IDirect3DBaseTexture8*>(Skin.textures[size_t(swap.index)].texture));
        for (int i=0;i<3;i++) { device->GetTextureStageState(0,SkinFilters[i],&swap.filters[i]); device->SetTextureStageState(0,SkinFilters[i],D3DTEXF_LINEAR); }
        skinActive=swap.index;
        return swap;
    }
    // A draw's vertices from memory with the colours the skin's skin.txt gives its picture, or as they were
    std::vector<uint8_t> skinVertices;
    const void* SkinVertices(const SkinSwap& swap,const void* data,unsigned count,unsigned stride) {
        SkinTexture& t=Skin.textures[size_t(swap.index)];
        auto* device=core->GetDirect3DDevice(); DWORD fvf=0;
        if (t.colours.empty() || count>65536 || !device || FAILED(device->GetVertexShader(&fvf)) || !SkinRecolour(t,data,count,stride,fvf,skinVertices)) return data;
        t.recoloured++;
        return skinVertices.data();
    }
    // The draw made with the skin's picture, unless done already (blocked, or drawn moved), and the game's texture
    // put back. True where it was drawn here; false (the game's own then drawn by Ashita) where the draw failed.
    template<class Draw> bool SkinEnd(const SkinSwap& swap,bool done,Draw draw) {
        skinActive=-1;
        if (swap.index<0) return done;
        auto* device=core->GetDirect3DDevice();
        bool ok=done;
        if (!done) {
            scaling=true; ok=SUCCEEDED(draw(device)); scaling=false;
            if (ok) Skin.textures[size_t(swap.index)].drawn++;
        }
        for (int i=0;i<3;i++) device->SetTextureStageState(0,SkinFilters[i],swap.filters[i]);
        device->SetTexture(0,swap.was); swap.was->Release();
        return ok;
    }
    // config\uihook\skins\<name>\tex-<hash>.png or .bmp, each made a texture of its own
    void SkinRelease() { for (void* t:Skin.Clear()) static_cast<IDirect3DTexture8*>(t)->Release(); }
    void SkinLoad(const char* name,char* line,size_t size) {
        for (const char* c=name;*c;c++) if (!isalnum(static_cast<unsigned char>(*c)) && *c!='_' && *c!='-') {
            snprintf(line,size,"[uihook:skin] a skin's name is letters, digits, - and _."); return;
        }
        auto* device=core->GetDirect3DDevice();
        if (!device) { snprintf(line,size,"[uihook:skin] no device yet."); return; }
        const std::string folder=std::string(core->GetInstallPath())+"\\config\\uihook\\skins\\"+name;
        SkinRelease();
        WIN32_FIND_DATAA found; unsigned failed=0;
        HANDLE find=FindFirstFileA((folder+"\\tex-*").c_str(),&found);
        if (find!=INVALID_HANDLE_VALUE) {
            do {
                uint32_t hash=0;
                if ((found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) || !SkinLook::FileHash(found.cFileName,hash) || Skin.Find(hash)>=0) continue;
                uint32_t width=0,height=0; std::vector<uint32_t> argb;
                // every level down to a texel, each the one above halved (SkinHalve): a picture larger than it is drawn
                // (made for a larger Menu Scale) shrinks smoothly, drawn with the levels between
                IDirect3DTexture8* texture=nullptr;
                if (!SkinReadPicture((folder+"\\"+found.cFileName).c_str(),width,height,argb)
                    || FAILED(device->CreateTexture(width,height,0,0,D3DFMT_A8R8G8B8,D3DPOOL_MANAGED,&texture))) { failed++; continue; }
                bool filled=true; uint32_t w=width,h=height;
                for (DWORD level=0;level<texture->GetLevelCount() && filled;level++) {
                    D3DLOCKED_RECT locked;
                    if (FAILED(texture->LockRect(level,&locked,nullptr,0))) { filled=false; break; }
                    for (uint32_t y=0;y<h;y++) memcpy(static_cast<uint8_t*>(locked.pBits)+size_t(y)*locked.Pitch,argb.data()+size_t(y)*w,size_t(w)*4);
                    texture->UnlockRect(level);
                    if (w>1 || h>1) SkinHalve(argb,w,h);
                }
                if (!filled) { texture->Release(); failed++; continue; }
                SkinTexture t; t.hash=hash; t.width=width; t.height=height; t.texture=texture;
                Skin.textures.push_back(t);
            } while (FindNextFileA(find,&found));
            FindClose(find);
        }
        snprintf(Skin.name,sizeof(Skin.name),"%s",name);
        unsigned unread=0; bool colours=false;
        if (FILE* f=fopen((folder+"\\skin.txt").c_str(),"rb")) {
            std::string text; char chunk[4096]; size_t n;
            while ((n=fread(chunk,1,sizeof(chunk),f))>0 && text.size()<65536) text.append(chunk,n);
            fclose(f); colours=true;
            unread=SkinColours(Skin.textures,text.c_str());
        }
        if (Skin.textures.empty()) snprintf(line,size,"[uihook:skin] no pictures read in %s (tex-<hash>.png or .bmp)%s.",folder.c_str(),failed ? ", some could not be read" : "");
        else snprintf(line,size,"[uihook:skin] %s: %zu pictures loaded%s%s%s; the game's textures are known as they are drawn.",name,Skin.textures.size(),
            failed ? ", some could not be read" : "",colours ? ", skin.txt read" : "",unread ? " (some of its lines not understood, or of no picture)" : "");
    }
    void SkinCommand(const char* word) {
        char line[512];
        if (!_stricmp(word,"off")) {
            const size_t n=Skin.textures.size(); SkinRelease(); Skin.name[0]=0;
            snprintf(line,sizeof(line),n ? "[uihook:skin] off; the game's own textures." : "[uihook:skin] no skin loaded.");
        } else if (!_stricmp(word,"reload")) {
            if (!Skin.name[0]) snprintf(line,sizeof(line),"[uihook:skin] no skin to reload: /uihook skin <name>.");
            else { char name[64]; snprintf(name,sizeof(name),"%s",Skin.name); SkinLoad(name,line,sizeof(line)); }
        } else if (word[0]) SkinLoad(word,line,sizeof(line));
        else if (!Skin.On()) snprintf(line,sizeof(line),"[uihook:skin] none loaded. /uihook skin <name> loads config\\uihook\\skins\\<name>\\; reload, off.");
        else {
            unsigned matched=0; uint32_t drawn=0,recoloured=0;
            for (auto& t:Skin.textures) { if (t.matched) matched++; drawn+=t.drawn; recoloured+=t.recoloured; }
            snprintf(line,sizeof(line),"[uihook:skin] %s: %zu pictures, %u found in the game's textures (%u read), %u draws made with them, %u of them recoloured.",
                Skin.name,Skin.textures.size(),matched,Skin.read,drawn,recoloured);
            core->GetChatManager()->Write(0,false,line);
            std::string unseen;
            for (auto& t:Skin.textures) if (!t.matched) { char h[12]; snprintf(h,sizeof(h)," %08X",t.hash); unseen+=h; }
            if (unseen.empty()) return;
            snprintf(line,sizeof(line),"[uihook:skin] not drawn by the game yet:%s",unseen.substr(0,400).c_str());
        }
        core->GetChatManager()->Write(0,false,line);
    }
    // /uihook textures: a screen-space draw's texture (stage 0), read the first time it is seen, counted with the
    // window and part drawing it. data: its vertices, from min; none from a vertex buffer.
    void TextureDraw(const void* data,unsigned vertices,unsigned stride,bool buffered,unsigned group=0) {
        if (!Textures.on) return;
        auto* device=core->GetDirect3DDevice(); DWORD fvf=0;
        if (!device || FAILED(device->GetVertexShader(&fvf)) || (fvf & D3DFVF_POSITION_MASK)!=D3DFVF_XYZRHW) return;
        IDirect3DBaseTexture8* base=nullptr;
        if (FAILED(device->GetTexture(0,&base))) base=nullptr;
        const uintptr_t key=reinterpret_cast<uintptr_t>(base);
        size_t at=Textures.Known(key,Shared.Frame);
        if (at==SIZE_MAX) {
            LabelPixels pixels; D3DSURFACE_DESC desc{}; uint32_t texels[4]={}; const char* why="";
            static const float whole[4]={0,0,1,1};
            const bool read=base && LabelCut(base,whole,pixels,desc,texels,why);
            at=Textures.Add(key,Shared.Frame,desc.Width,desc.Height,uint32_t(desc.Format),uint32_t(desc.Pool),read ? &pixels : nullptr,read || !base ? "" : why);
        }
        if (base) base->Release();
        float uv[4]; uint32_t colour=0; bool hasColour=false;
        const bool hasUV=!buffered && TextureVertices(data,vertices,stride,fvf,uv,&colour,hasColour);
        const TexturePart part=!Textures.window[0] ? TEXTURE_OUTSIDE : NativeMenus.text ? TEXTURE_TEXT : TexturePart(NativeMenus.phase);
        Textures.Count(at,part,hasUV ? uv : nullptr,hasColour ? &colour : nullptr,buffered);
        if (hasUV) TexturePieces(data,vertices,stride,fvf,group,[&](const float* rect,const float* piece,uint32_t c) {
            Textures.Sample(at,part,rect,piece,c);
            if (part==TEXTURE_TEXT || NativeMenus.text) Textures.PrintPiece(at,rect,piece);
        });
    }
    void TexturesWrite(char* line,size_t size) {
        const std::string base=std::string(core->GetInstallPath())+"\\logs\\uihook-textures";
        CreateDirectoryA(base.c_str(),nullptr);
        std::string folder;
        for (unsigned n=1;n<1000 && folder.empty();n++) {
            char sub[8]; snprintf(sub,sizeof(sub),"\\%02u",n);
            if (CreateDirectoryA((base+sub).c_str(),nullptr)) folder=base+sub;
        }
        unsigned images=0;
        if (folder.empty() || !Textures.Write(folder,images)) snprintf(line,size,"[uihook:textures] could not write to %s.",base.c_str());
        else {
            Textures.WriteGlyphs(folder+"\\glyphs.txt");
            snprintf(line,size,"[uihook:textures] %zu textures (%u as pictures) written to %s\\index.txt, glyphs of %u prints to glyphs.txt.",
                Textures.entries.size(),images,folder.c_str(),Textures.matched);
        }
    }
    void TexturesCommand(const char* word) {
        char line[512];
        if (!_stricmp(word,"on")) {
            snprintf(line,sizeof(line),Textures.on ? "[uihook:textures] already on."
                : "[uihook:textures] on: open the menus you want counted, then /uihook textures off to write them to logs\\uihook-textures.");
            Textures.on=true;
        } else if (!_stricmp(word,"off")) {
            Textures.on=false;
            if (Textures.entries.empty()) snprintf(line,sizeof(line),"[uihook:textures] off; nothing seen.");
            else TexturesWrite(line,sizeof(line));
        } else if (!_stricmp(word,"dump")) {
            if (Textures.entries.empty()) snprintf(line,sizeof(line),"[uihook:textures] nothing seen yet: /uihook textures on, then open some menus.");
            else TexturesWrite(line,sizeof(line));
        } else if (!_stricmp(word,"clear")) {
            Textures.Clear(); snprintf(line,sizeof(line),"[uihook:textures] cleared.");
        } else snprintf(line,sizeof(line),"[uihook:textures] %s, %zu textures seen (%zu bytes of pixels kept). /uihook textures on|off|dump|clear.",
            Textures.on ? "on" : "off",Textures.entries.size(),Textures.memory);
        core->GetChatManager()->Write(0,false,line);
    }
    void NativeCommand(const char* command) {
        char verb[16]={},name[16]={},a[16]={},b[16]={}; char line[256];
        const int words=sscanf_s(command,"/uihook native %15s %15s %15s %15s",verb,16u,name,16u,a,16u,b,16u);
        auto* chat=core->GetChatManager();
        if (words>=4 && !_stricmp(verb,"move")) {
            snprintf(line,sizeof(line),NativeMenus.Move(name,float(atof(a)),float(atof(b))) ? "[uihook:native] %s drawn %s, %s from where the game puts it."
                : "[uihook:native] could not move %s: a name of at most 8 letters, and at most 16 windows.",name,a,b);
        } else if (words>=3 && !_stricmp(verb,"scale")) {
            snprintf(line,sizeof(line),NativeMenus.Scale(name,float(atof(a))) ? "[uihook:native] %s drawn at %s times its size."
                : "[uihook:native] could not scale %s: a factor from 0.5 to 3.",name,a);
        } else if (words>=3 && !_stricmp(verb,"tint")) {
            const uint32_t colour=static_cast<uint32_t>(strtoul(a,nullptr,16)) | (strlen(a)<=6 ? 0xff000000u : 0);
            snprintf(line,sizeof(line),NativeMenus.Tint(name,colour) ? "[uihook:native] %s's frame tinted %08X."
                : "[uihook:native] could not tint %s.",name,colour);
        } else if (words>=2 && !_stricmp(verb,"group") && !_stricmp(name,"off")) {
            // quiet: as an addon sends it, said nowhere
            snprintf(line,sizeof(line),"[uihook:native] the windows over the chat log as the game draws them again (%u).",NativeMenus.GroupOff());
            if (words>=3 && !_stricmp(a,"quiet")) return;
        } else if (words>=3 && !_stricmp(verb,"group")) {
            NativeMenus.Group(float(atof(name)),float(atof(a)));
            snprintf(line,sizeof(line),"[uihook:native] the windows the game stacks over the chat log drawn %s, %s from where it puts them.",name,a);
            if (words>=4 && !_stricmp(b,"quiet")) return;
        } else if (words>=2 && !_stricmp(verb,"size")) {
            const bool ok=NativeMenus.MenuScale(float(atof(name)));
            snprintf(line,sizeof(line),ok ? "[uihook:native] every framed window drawn %.2f times its size, from its corner of the screen."
                : "[uihook:native] a size from 0.5 to 3.",NativeMenus.menuScale);
            if (words>=3 && !_stricmp(a,"quiet")) return;
        } else if (words>=2 && !_stricmp(verb,"inset")) {
            NativeMenus.Inset(float(atof(name)));
            snprintf(line,sizeof(line),NativeMenus.inset>0 ? "[uihook:native] the sides brought in %.0f pixels: the bar across the top that much shorter at each end, the windows each side with it."
                : "[uihook:native] the sides where the game puts them.",NativeMenus.inset);
            if (words>=3 && !_stricmp(a,"quiet")) return;
        } else if (words>=1 && !_stricmp(verb,"clear")) {
            snprintf(line,sizeof(line),"[uihook:native] %u drawn as the game draws them again.",NativeMenus.Clear(words>=2 ? name : nullptr));
        } else if (words<1) {
            unsigned n=0; for (auto& e:NativeMenus.entries) if (e.name[0]) n++;
            snprintf(line,sizeof(line),"[uihook:native] %u menus set; the game's mouse hit-tests stay where it puts them.",n);
            chat->Write(0,false,line);
            if (NativeMenus.menuScale!=1) {
                snprintf(line,sizeof(line),"  every framed window drawn %.2f times its size",NativeMenus.menuScale);
                chat->Write(0,false,line);
            }
            if (NativeMenus.inset>0) {
                snprintf(line,sizeof(line),"  the sides brought in %.0f pixels",NativeMenus.inset);
                chat->Write(0,false,line);
            }
            if (NativeMenus.groupOn) {
                snprintf(line,sizeof(line),"  group over the chat log: %.0f, %.0f; the log's top %d at its left %d (%s)",NativeMenus.groupX,NativeMenus.groupY,
                    NativeMenus.logTop,NativeMenus.logLeft,NativeMenus.logFrame ? "seen" : "not drawn yet");
                chat->Write(0,false,line);
            }
            for (auto& e:NativeMenus.entries) {
                if (!e.name[0]) continue;
                char seen[48];
                if (!e.seen) snprintf(seen,sizeof(seen),"not drawn since asked");
                else snprintf(seen,sizeof(seen),"drawn %u frames ago",Shared.Frame-e.seen);
                snprintf(line,sizeof(line),"  %.8s%s: %s; move %.0f,%.0f scale %.2f (%u draws moved, %u outside its frame kept, %u could not be), tint %s %08X (%u tinted, %u refused, format %X, stage %u %X %X)",
                    e.name+8,e.group ? (e.member ? " (group)" : " (group, not now)") : "",seen,e.dx,e.dy,e.scale,e.moved,e.kept,e.unmoved,e.tint ? "on" : "off",e.colour,e.tinted,e.refused,
                    static_cast<unsigned>(e.lastFormat),static_cast<unsigned>(e.stage[0]),static_cast<unsigned>(e.stage[1]),static_cast<unsigned>(e.stage[2]));
                chat->Write(0,false,line);
            }
            return;
        } else {
            snprintf(line,sizeof(line),"[uihook:native] /uihook native [move <name> <x> <y> | scale <name> <factor> | tint <name> <AARRGGBB> | group <x> <y> | group off | inset <pixels> | size <factor> | clear [name]]");
        }
        chat->Write(0,false,line);
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
    bool Initialize(IAshitaCore* c, ILogManager* l, uint32_t) override {
        core=c; log=l; Instance=this;
        memcpy(TextTap.Magic,"UIHOOK-TEXT",12); TextTap.Version=1; TextTap.Size=sizeof(TextTapShared);
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
                History.Supported=1; // the first window's ring, followed from its owner when read
                if (menuManager && menus.Discover(begin,module.SizeOfImage,static_cast<uint8_t*>(WindowDetour.target))) {
                    Menus.Supported=1;
                    menus.Log(chat.ExpandedSupported() ? chat.FullOwner() : nullptr); // the expanded log, placed as the menus are
                }
                // which messages each of the two log windows shows, as the client decides it: read, never written
                if (DiscoverChatWindows(begin,module.SizeOfImage,chat.SplitOwner(),windowRoutes)) Chat.SupportedMask|=CHAT_WINDOWS_SUPPORTED;
                if (chat.LinesSupported()) Chat.SupportedMask|=CHAT_LINES_SUPPORTED; // each window's lines now, as the game grows and shrinks it
                if (DiscoverChatColors(begin,module.SizeOfImage,colorTables)) Chat.SupportedMask|=CHAT_COLORS_SUPPORTED; // the game's chat colours, as configured
                const auto controls=DiscoverChatControls(begin,module.SizeOfImage,WindowDetour.target,chat.ExpandedDraw());
                if (chat.ExpandedDraw() && Take(ExpandedChatDetour,begin,module.SizeOfImage)) {
                    Chat.SupportedMask |= CHAT_FULL_SKIN_SUPPORTED;
                    void* callbacks[]={reinterpret_cast<void*>(&DrawChatTab),reinterpret_cast<void*>(&DrawChatSelection),
                        reinterpret_cast<void*>(&DrawChatCursor),reinterpret_cast<void*>(&DrawChatScroll),reinterpret_cast<void*>(&DrawChatTabs)};
                    if (TakeChatControls(ChatControls,controls,callbacks)) {
                        Chat.SupportedMask |= CHAT_CONTROLS_SUPPORTED | CHAT_REPLACE_SUPPORTED;
                        // the rows of text as well, where the drawer's one row-drawing call is verified: on its own, the controls stand without it
                        if (TakeChatText(ChatText,DiscoverChatText(begin,module.SizeOfImage,chat.ExpandedDraw()),reinterpret_cast<void*>(&DrawChatRow)))
                            Chat.SupportedMask |= CHAT_TEXT_SUPPORTED | CHAT_MIRROR_SUPPORTED;
                    }
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
        // The menu mirror: zero in the file, its magic written now; supported where its four sites are found
        memcpy(MirrorBlock.Magic,"UIHOOK-MIRROR",14); MirrorBlock.Version=5; MirrorBlock.Size=sizeof(MirrorShared);
        MenuMirror.shared=&MirrorBlock;
        if (module.lpBaseOfDll && TakeMirror(static_cast<uint8_t*>(module.lpBaseOfDll),module.SizeOfImage)) {
            MirrorBlock.Supported=MIRROR_SUPPORTED;
            if (Take(InputDetour,static_cast<uint8_t*>(module.lpBaseOfDll),module.SizeOfImage)) MirrorBlock.Supported|=MIRROR_SUPPORTED_MOUSE;
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
    void Stop() { for (unsigned i=0;i<6;i++) { drawings[i].Clear(); Forgive(i); } staging.Clear(); }
    void StopHud() { drawings[6].Clear(); drawings[7].Clear(); Forgive(6); Forgive(7); staging.Clear(); }
    // A capture refused: counted, its reason kept for the slot, and written to Ashita's log the first time
    // in a row and when the reason changes. Until a capture is taken the game draws its own there, and the
    // addon's window is drawn by imgui over it.
    int Refuse(unsigned index,uint8_t why) {
        ++Shared.Failures;
        const bool changed=refusal[index]!=why;
        refusal[index]=why; refusedFrame[index]=Shared.Frame;
        refusedRun[index]=changed ? 1 : refusedRun[index]+1;
        if (changed && log) log->Logf(static_cast<uint32_t>(Ashita::LogLevel::Warn),"uihook",
            "%s: capture refused at frame %u, %s; the game's own is drawn there until a capture is taken",
            PartySlotName(index),Shared.Frame,RefusalName(why));
        return 0;
    }
    // A capture taken: the slot's refusals are over, said in the log where there were any
    void Accept(unsigned index) {
        if (refusal[index] && log) log->Logf(static_cast<uint32_t>(Ashita::LogLevel::Info),"uihook",
            "%s: capture taken again at frame %u, after %u refused (%s)",PartySlotName(index),Shared.Frame,refusedRun[index],RefusalName(refusal[index]));
        refusal[index]=REFUSED_NONE; refusedRun[index]=0;
    }
    // A slot released on purpose has nothing to report
    void Forgive(unsigned index) { refusal[index]=REFUSED_NONE; refusedRun[index]=0; }
    void RefusedByException(unsigned index) { if (index<11) Refuse(index,REFUSED_EXCEPTION); }
    void Release() override {
        Menus.RequestFrame=0; Menus.LogRequestFrame=0; menus.Stop(Menus); menus.StopLog(Menus); Menus.Supported=0;
        History.Supported=0; History.RequestFrame=0; History.Count=0; historyServed=0;
        Shared.Hooked=0; Shared.Submit=0; Shared.GeometryReady=0;
        Hud.SupportedMask=0; Hud.Submit=0;
        Chat.SupportedMask=0; Chat.Submit=0; Chat.InputRectFrame=Chat.PrimaryRectFrame=Chat.ExpandedRectFrame=Chat.SplitRectFrame=Chat.WindowFrame=Chat.LinesFrame=Chat.ColorFrame=Chat.StateFrame=Chat.StateFlags=0; chat.Clear(); windowRoutes.Clear(); colorTables.Clear(); StopChat(); ChatReadReset();
        GiveClockText(TextCall); GiveClockIcons(IconCalls); Hud.HideIcons=0; Hud.WeatherShift=0; Hud.PreviewWeather=0; Hud.WeatherScale=0; bank=nullptr; Give(CompassDetour); Give(ClockDetour); compassGlobal=nullptr;
        AutoCensus(true);
        Textures.on=false; Textures.Clear(); Textures.window[0]=0;
        SkinRelease(); Skin.name[0]=0;
        GiveMirror();
        GiveArrows(Arrows); GiveChatText(ChatText); GiveChatControls(ChatControls); Give(ExpandedChatDetour); Give(WindowDetour); blocking=targetScope=expandedSkin=false; ReleaseStates(); Stop(); StopHud(); Instance=nullptr;
    }
    bool Direct3DInitialize(IDirect3DDevice8*) override { return true; }
    void Direct3DPresent(const RECT*,const RECT*,HWND,const RGNDATA*) override {
        MenuMirror.Publish(Shared.Frame);
        if (MenuWatch.on) {
            MenuWatch.Share(WatchBlock,Shared.Frame);
            if (WatchFile) WatchPresent(); else MenuWatch.Next();
        }
        if (labelsAt && int32_t(GetTickCount()-labelsAt)>=0) { labelsAt=0; LabelsCommand(); }
        AutoCensus(false);
        ++Shared.Frame;
        MenuCensus.frame=Shared.Frame; MirrorBlock.Frame=Shared.Frame;
        Hud.Frame=Chat.Frame=Menus.Frame=Shared.Frame;
        ChatReadReset(); // the regions found readable last frame are asked about again
        chat.Sample(Chat,Shared.Frame);
        SampleChatWindows(windowRoutes,Chat,Shared.Frame);
        chat.SampleLines(Chat,Shared.Frame);
        History.Frame=Shared.Frame;
        TextTap.Frame=Shared.Frame;
        // a read of the first window's history, once for each request
        if (History.Supported && History.RequestFrame && History.RequestFrame!=historyServed) {
            historyServed=History.RequestFrame;
            if (!ChatReadHistory(chat.FirstRing(),History)) History.Count=History.Used=0;
            History.ReadFrame=Shared.Frame; History.Serial++;
        }
        // the colours change seldom, and are a few thousand bytes to read and compare: read every fourth
        // frame once they have been read, and vouched for as current between
        if (!colorTables.cached || (Shared.Frame & 3)==0) SampleChatColors(colorTables,Chat,Shared.Frame);
        else if (Chat.ColorFrame) Chat.ColorFrame=Shared.Frame;
        if (!MenuFresh(Menus,Chat,Shared.Frame)) menus.Stop(Menus);
        if (!LogFresh(Menus,Shared.Frame)) menus.StopLog(Menus);
        // As namehook: no cross-frame state blocks holding client resources across a reset.
        ReleaseStates();
        for (auto& d:drawings) if (!d.Fresh()) d.Clear();
    }
    void Direct3DBeginScene(bool) override { inScene=true; }
    void Direct3DEndScene(bool) override { inScene=false; }
    // Each draw: counted and heard as it is (the skin's picture not yet in place, so what is counted and mirrored
    // is the game's own); then, where the skin has a picture for its texture, drawn with it here, the game's put back
    bool BufferDraw() { TextureDraw(nullptr,0,0,true); MenuCensus.Draw(); MenuWatch.Draw(MirrorWatch::BUFFER); Native(false,nullptr,0,0); NativeMenus.Unmoved(); return false; }
    bool Direct3DDrawPrimitive(D3DPRIMITIVETYPE t,UINT start,UINT count) override {
        if (scaling) return false;
        BufferDraw();
        const SkinSwap skin=SkinBegin();
        return SkinEnd(skin,Block(),[&](IDirect3DDevice8* d) { return d->DrawPrimitive(t,start,count); });
    }
    bool Direct3DDrawIndexedPrimitive(D3DPRIMITIVETYPE t,UINT min,UINT vertices,UINT start,UINT count) override {
        if (scaling) return false;
        BufferDraw();
        const SkinSwap skin=SkinBegin();
        return SkinEnd(skin,Block(),[&](IDirect3DDevice8* d) { return d->DrawIndexedPrimitive(t,min,vertices,start,count); });
    }
    bool Direct3DDrawPrimitiveUP(D3DPRIMITIVETYPE t,UINT count,const void* data,UINT stride) override {
        if (scaling) return false;
        TextureDraw(data,t==D3DPT_TRIANGLELIST ? count*3 : t==D3DPT_TRIANGLESTRIP || t==D3DPT_TRIANGLEFAN ? count+2 : 0,stride,false,
            t==D3DPT_TRIANGLELIST ? 6 : t==D3DPT_TRIANGLESTRIP && count==2 ? 4 : 0);
        MenuCensus.Draw();
        if (MenuWatch.Inside()) WatchUp();
        if (MenuMirror.Active()) MenuMirror.Draw(core->GetDirect3DDevice(),true,data,stride,t==D3DPT_TRIANGLELIST ? count*3 : t==D3DPT_TRIANGLESTRIP || t==D3DPT_TRIANGLEFAN ? count+2 : 0); // our own scaled copy, on its way to the device
        Native(true,data,stride,t==D3DPT_TRIANGLELIST ? count*3 : t==D3DPT_TRIANGLESTRIP || t==D3DPT_TRIANGLEFAN ? count+2 : 0);
        const SkinSwap skin=SkinBegin();
        const bool done=Block() || NativeDraw(t,0,t==D3DPT_TRIANGLELIST ? count*3 : t==D3DPT_TRIANGLESTRIP || t==D3DPT_TRIANGLEFAN ? count+2 : 0,count,nullptr,D3DFMT_UNKNOWN,data,stride)
            || ScaleIcon(t,count,data,stride);
        return SkinEnd(skin,done,[&](IDirect3DDevice8* d) {
            return d->DrawPrimitiveUP(t,count,SkinVertices(skin,data,t==D3DPT_TRIANGLELIST ? count*3 : t==D3DPT_TRIANGLESTRIP || t==D3DPT_TRIANGLEFAN ? count+2 : 0,stride),stride);
        });
    }
    bool Direct3DDrawIndexedPrimitiveUP(D3DPRIMITIVETYPE t,UINT min,UINT vertices,UINT count,const void* indices,D3DFORMAT format,const void* data,UINT stride) override {
        if (scaling) return false;
        TextureDraw(data ? static_cast<const uint8_t*>(data)+size_t(min)*stride : nullptr,vertices,stride,false,4);
        MenuCensus.Draw();
        if (MenuWatch.Inside()) WatchUp();
        if (MenuMirror.Active()) MenuMirror.Draw(core->GetDirect3DDevice(),true,data,stride,vertices);
        Native(true,data,stride,vertices);
        const SkinSwap skin=SkinBegin();
        const bool done=Block() || NativeDraw(t,min,vertices,count,indices,format,data,stride) || ClockDraw(t,min,vertices,count,indices,format,data,stride);
        return SkinEnd(skin,done,[&](IDirect3DDevice8* d) {
            return d->DrawIndexedPrimitiveUP(t,min,vertices,count,indices,format,SkinVertices(skin,data,min+vertices,stride),stride);
        });
    }
    // The clock's draws moved by its shift
    bool ClockDraw(D3DPRIMITIVETYPE t,UINT min,UINT vertices,UINT count,const void* indices,D3DFORMAT format,const void* data,UINT stride) {
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
    // Each line given to the game's chat log, recorded as it stands at uihook's turn; never changed or blocked
    bool HandleIncomingText(int32_t mode,bool indent,const char* message,int32_t* modifiedMode,bool* modifiedIndent,char* modifiedMessage,bool injected,bool blocked) override {
        ChatTapRecord(TextTap,mode,indent,message,modifiedMode,modifiedIndent,modifiedMessage,injected,blocked);
        return false;
    }
    // The three text routes and the contents' call, all or none, with Window::Render if nothing else has
    // taken it: the mirror's, and the census's. Each passes straight on to the game's own while no window
    // is mirrored and the census is off.
    bool TakeMirror(uint8_t* begin,size_t size) {
        if (!WindowDetour.trampoline && !Take(WindowDetour,begin,size)) return false;
        if (!Take(CensusBitmapDetour,begin,size) || !Take(CensusScaledDetour,begin,size) || !Take(CensusFontDetour,begin,size)
            || !TakeMirrorContent(begin,size,static_cast<uint8_t*>(WindowDetour.target))) { GiveMirror(); return false; }
        MenuCensus.base=reinterpret_cast<uintptr_t>(begin);
        memcpy(WatchBlock.Magic,"UIHOOK-WATCH",13); WatchBlock.Version=1; WatchBlock.Size=sizeof(WatchBlock);
        MenuWatch.Start();
        return true;
    }
    void GiveMirror() {
        MirrorBlock.Supported=0; MirrorBlock.RequestFrame=0; MirrorBlock.MouseFrame=0; MenuMirror.Clear();
        Give(InputDetour);
        MenuCensus.on=false; MenuCensus.current=nullptr; MenuWatch.Stop(); WatchFile=false; WatchBlock.Count=0;
        GiveMirrorContent(); Give(CensusBitmapDetour); Give(CensusScaledDetour); Give(CensusFontDetour);
    }
    // The census, from /uihook census on: each time it is switched on a file of its own in logs\uihook-census (named
    // for when it began), written a few seconds after a window is first seen, each minute while windows are drawn,
    // and as it is switched off or uihook is unloaded. Off from load.
    std::string censusAuto; DWORD censusWrittenAt=0, censusNewAt=0; size_t censusWritten=0; uint32_t censusFrame=0;
    void StartAutoCensus() {
        if (!StartCensus()) return;
        const std::string folder=std::string(core->GetInstallPath())+"\\logs\\uihook-census";
        CreateDirectoryA(folder.c_str(),nullptr);
        SYSTEMTIME t; GetLocalTime(&t); char name[48];
        snprintf(name,sizeof(name),"\\%04u-%02u-%02u_%02u%02u%02u.txt",t.wYear,t.wMonth,t.wDay,t.wHour,t.wMinute,t.wSecond);
        censusAuto=folder+name; censusWrittenAt=GetTickCount(); censusNewAt=0; censusWritten=0; censusFrame=0;
    }
    void AutoCensus(bool now) {
        if (censusAuto.empty() || !MenuCensus.on || MenuCensus.windows.empty()) return;
        const DWORD tick=GetTickCount();
        if (MenuCensus.windows.size()!=censusWritten && !censusNewAt) censusNewAt=tick ? tick : 1;
        uint32_t last=0; for (auto& w:MenuCensus.windows) last=(std::max)(last,w.last);
        const bool fresh=censusNewAt && tick-censusNewAt>=5000;
        const bool minute=tick-censusWrittenAt>=60000 && last!=censusFrame;
        if (!now && !fresh && !minute) return;
        if (MenuCensus.Write(censusAuto.c_str(),"heard")) { censusWritten=MenuCensus.windows.size(); censusFrame=last; }
        censusWrittenAt=tick; censusNewAt=0;
    }
    bool StartCensus() { if (!MirrorBlock.Supported) return false; MenuCensus.on=true; return true; }
    void StopCensus() { MenuCensus.on=false; MenuCensus.current=nullptr; }
    void CensusCommand(const char* word) {
        char line[256];
        const std::string path=std::string(core->GetInstallPath())+"\\logs\\uihook-census.txt";
        if (!_stricmp(word,"on")) {
            const bool was=MenuCensus.on;
            if (!was) StartAutoCensus();
            snprintf(line,sizeof(line),was ? "[uihook:census] already on." : MenuCensus.on
                ? "[uihook:census] on, written to logs\\uihook-census as you open menus; /uihook census off to stop." : "[uihook:census] the text routines were not found in this client.");
        } else if (!_stricmp(word,"off")) {
            AutoCensus(true); censusAuto.clear();
            StopCensus(); snprintf(line,sizeof(line),"[uihook:census] off; %zu windows kept until /uihook census clear.",MenuCensus.windows.size());
        } else if (!_stricmp(word,"clear")) {
            MenuCensus.Clear(); snprintf(line,sizeof(line),"[uihook:census] cleared.");
        } else if (!_stricmp(word,"dump")) {
            const bool hooked=MirrorBlock.Supported!=0;
            if (MenuCensus.Write(path.c_str(),hooked ? "heard" : "not found in this client"))
                snprintf(line,sizeof(line),"[uihook:census] %zu windows written to %s.",MenuCensus.windows.size(),path.c_str());
            else snprintf(line,sizeof(line),"[uihook:census] could not write %s.",path.c_str());
        } else snprintf(line,sizeof(line),"[uihook:census] %s, %zu windows seen. /uihook census on|off|dump|clear.",MenuCensus.on ? "on" : "off",MenuCensus.windows.size());
        core->GetChatManager()->Write(0,false,line);
    }
    // Every element and content quad (an icon, a letter) of the last frame published, cut from its texture to logs\uihook-labels\N.bmp, with
    // labels.txt naming each one's window, texture, place in it and the hash of its pixels
    DWORD labelsAt=0; // when a /uihook mirror labels asked for later is to be written, or 0
    void LabelsCommand() {
        char line[512];
        const MirrorFrameData& last=MirrorBlock.Published;
        uint32_t elements=0;
        for (uint32_t i=0;i<last.QuadCount;i++) if (last.Quads[i].Phase==MIRROR_ELEMENT || last.Quads[i].Phase==MIRROR_CONTENT) elements++;
        if (!elements) {
            core->GetChatManager()->Write(0,false,"[uihook:mirror] no elements or art in the last frame mirrored: open a menu the menus addon mirrors first; nothing written.");
            return;
        }
        // each run in a folder of its own, 01, 02 and on, so none is written over
        const std::string base=std::string(core->GetInstallPath())+"\\logs\\uihook-labels";
        CreateDirectoryA(base.c_str(),nullptr);
        std::string folder;
        for (unsigned n=1;n<1000 && folder.empty();n++) {
            char sub[8]; snprintf(sub,sizeof(sub),"\\%02u",n);
            if (CreateDirectoryA((base+sub).c_str(),nullptr)) folder=base+sub;
        }
        if (folder.empty()) { snprintf(line,sizeof(line),"[uihook:mirror] could not make a folder in %s.",base.c_str()); core->GetChatManager()->Write(0,false,line); return; }
        std::vector<uint32_t> sheets; // each texture once whole, as sheet-XXXXXXXX.bmp
        FILE* list=fopen((folder+"\\labels.txt").c_str(),"w");
        if (!list) { snprintf(line,sizeof(line),"[uihook:mirror] could not write %s.",folder.c_str()); core->GetChatManager()->Write(0,false,line); return; }
        fprintf(list,"# n window texture WxH format uv(left top right bottom) texels(x0 y0 x1 y1) hash colour rect(normalized) phase(1 content, 3 element)\n");
        unsigned written=0,skipped=0;
        for (uint32_t i=0;i<last.QuadCount;i++) {
            const MirrorQuad& q=last.Quads[i];
            if ((q.Phase!=MIRROR_ELEMENT && q.Phase!=MIRROR_CONTENT) || q.Window>=last.WindowCount) continue;
            const char* name=last.Windows[q.Window].Name;
            LabelPixels pixels; D3DSURFACE_DESC desc{}; uint32_t texels[4]={}; const char* why="not held";
            const bool cut=q.Texture && MenuMirror.Holds(q.Texture)
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
        core->GetChatManager()->Write(0,false,line);
    }
    // /uihook mirror watch: each window drawn, whether asked for and mirrored, and how it drew, written as it changes
    std::string WatchPath() const { return std::string(core->GetInstallPath())+"\\logs\\uihook-mirror-watch.txt"; }
    int WatchEnter(void* window,bool hidden) {
        char name[16]; uint8_t* header=nullptr; bool hide=false;
        auto* w=static_cast<uint8_t*>(window);
        const bool wanted=w && ChatRead(w+CENSUS_HEADER,&header,4) && header && ChatRead(header+CENSUS_NAME,name,16) && MenuMirror.Wanted(name,hide);
        return MenuWatch.Enter(window,wanted,hidden,MenuMirror.Active());
    }
    void WatchUp() {
        DWORD fvf=0; auto* device=core->GetDirect3DDevice();
        const bool screen=device && SUCCEEDED(device->GetVertexShader(&fvf)) && (fvf & D3DFVF_POSITION_MASK)==D3DFVF_XYZRHW;
        MenuWatch.Draw(screen ? MirrorWatch::UP : MirrorWatch::OTHER);
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
        WatchWrite(MenuWatch.Present(MirrorBlock.Published,MirrorBlock.Dropped,Shared.Frame,GetTickCount(),WatchClock().c_str()));
    }
    void WatchCommand(const char* word) {
        char line[320]; const std::string path=WatchPath();
        if (word[0]) {
            // a line of the player's own in the file, where they are and what they see, and the next frame written
            if (!WatchFile) { core->GetChatManager()->Write(0,false,"[uihook:mirror] the watch is off: /uihook mirror watch first."); return; }
            WatchWrite("-- "+WatchClock()+" mark: "+word+"\n"); MenuWatch.Renew();
            snprintf(line,sizeof(line),"[uihook:mirror] marked: %s",word);
        } else if (WatchFile) {
            WatchFile=false; snprintf(line,sizeof(line),"[uihook:mirror] watch off; %s kept.",path.c_str());
        } else if (!MirrorBlock.Supported) {
            snprintf(line,sizeof(line),"[uihook:mirror] the menus' drawing was not found in this client; nothing to watch.");
        } else if (FILE* file=fopen(path.c_str(),"w")) {
            fprintf(file,"uihook mirror watch, started %s: each window drawn (asked for by an addon, hidden, mirrored), its draws, and what was published\n",WatchClock().c_str());
            fclose(file); WatchFile=true; MenuWatch.Renew();
            snprintf(line,sizeof(line),"[uihook:mirror] watching to %s; /uihook mirror mark <words> to note a moment, /uihook mirror watch again to stop.",path.c_str());
        } else snprintf(line,sizeof(line),"[uihook:mirror] could not write %s.",path.c_str());
        core->GetChatManager()->Write(0,false,line);
    }
    bool HandleCommand(int32_t,const char* command,bool) override {
        if (command && (!_stricmp(command,"/uihook native") || !_strnicmp(command,"/uihook native ",15))) { NativeCommand(command); return true; }
        if (command && (!_stricmp(command,"/uihook mirror watch") || !_strnicmp(command,"/uihook mirror mark ",20))) {
            const bool mark=command[15]=='m' || command[15]=='M';
            if (mark && !command[20]) return true;
            WatchCommand(mark ? command+20 : ""); return true;
        }
        if (command && !_strnicmp(command,"/uihook mirror labels",21)) {
            // at once, or after the seconds given, so the chat line the command was typed in has closed and the
            // menus are drawn as they are while played
            const int seconds=command[21]==' ' ? atoi(command+22) : 0;
            if (seconds<=0) { LabelsCommand(); return true; }
            labelsAt=GetTickCount()+DWORD((std::min)(seconds,60))*1000;
            char line[96]; snprintf(line,sizeof(line),"[uihook:mirror] writing the menus' art in %d seconds.",(std::min)(seconds,60));
            core->GetChatManager()->Write(0,false,line);
            return true;
        }
        if (command && _stricmp(command,"/uihook mirror")==0) {
            // what the mirror was asked for, and what it published from the last frame
            char line[256]; const MirrorFrameData& last=MirrorBlock.Published;
            std::string asked;
            for (unsigned i=0;i<MIRROR_REQUESTS;i++) if (MirrorBlock.Requests[i][0]) {
                if (!asked.empty()) asked+=", ";
                asked+=std::string(MirrorBlock.Requests[i]+8,8)+((MirrorBlock.Hide[i/32]>>(i%32))&1 ? " (hidden)" : " (watched)");
            }
            const bool fresh=MirrorBlock.RequestFrame && MirrorBlock.Frame-MirrorBlock.RequestFrame<=MIRROR_REQUEST_FRAMES;
            snprintf(line,sizeof(line),"[uihook:mirror] %s; asked %s: %s.",MirrorBlock.Supported ? "supported" : "not found in this client",
                fresh ? "now" : "nothing now",asked.empty() ? "none" : asked.c_str());
            core->GetChatManager()->Write(0,false,line);
            snprintf(line,sizeof(line),"[uihook:mirror] the last frame published (%u): %u windows, %u runs of text, %u quads, %u bytes; %u dropped since loading.",
                last.Frame,last.WindowCount,last.RunCount,last.QuadCount,last.TextUsed,MirrorBlock.Dropped);
            core->GetChatManager()->Write(0,false,line);
            const bool mouseFresh=MirrorBlock.MouseFrame && MirrorBlock.Frame-MirrorBlock.MouseFrame<=MIRROR_REQUEST_FRAMES;
            snprintf(line,sizeof(line),"[uihook:mirror] the mouse: %s; %u menus drawn elsewhere now; %u messages moved to the game's own since loading.",
                MirrorBlock.Supported & MIRROR_SUPPORTED_MOUSE ? "the game's handler taken" : "the game's handler not found",
                mouseFresh ? (std::min)(uint32_t(MirrorBlock.MouseCount),uint32_t(MIRROR_MOUSE)) : 0u,MirrorMapped);
            core->GetChatManager()->Write(0,false,line);
            for (uint32_t i=0;i<last.WindowCount;i++) {
                const MirrorWindow& w=last.Windows[i];
                snprintf(line,sizeof(line),"[uihook:mirror]   %.16s: flags %X, %.3f,%.3f to %.3f,%.3f; %u runs, %u quads; cursor %s, scrollbar %u of %u.",
                    w.Name,w.Flags,w.Rect[0],w.Rect[1],w.Rect[2],w.Rect[3],w.Runs,w.Quads,w.CursorFrame ? "drawn" : "none",w.ScrollPage,w.ScrollCount);
                core->GetChatManager()->Write(0,false,line);
            }
            return true;
        }
        if (command && !_strnicmp(command,"/uihook census",14)) { CensusCommand(command[14]==' ' ? command+15 : ""); return true; }
        if (command && (!_stricmp(command,"/uihook skin") || !_strnicmp(command,"/uihook skin ",13))) { SkinCommand(command[12]==' ' ? command+13 : ""); return true; }
        if (command && !_strnicmp(command,"/uihook textures",16)) { TexturesCommand(command[16]==' ' ? command+17 : ""); return true; }
        if (command && _stricmp(command,"/uihook menus")==0) {
            char line[256];
            snprintf(line,sizeof(line),"[uihook:menus] supported %u; frame/request %u/%u, host %u; applied/restored %u/%u; last %.16s at %u.",
                Menus.Supported,Menus.Frame,Menus.RequestFrame,Menus.HostSlot,Menus.Applied,Menus.Restored,Menus.LastName,Menus.MenuFrame);
            core->GetChatManager()->Write(0,false,line);
            snprintf(line,sizeof(line),"[uihook:menus] expanded log: request %u at %.0f,%.0f; applied/restored %u/%u, last at %u.",
                Menus.LogRequestFrame,Menus.LogPlace[0],Menus.LogPlace[1],Menus.LogApplied,Menus.LogRestored,Menus.LogFrame);
            core->GetChatManager()->Write(0,false,line); return true;
        }
        if (command && _stricmp(command,"/uihook chat history")==0) {
            // the newest lines of the first window's history, as read now: each line's header fields and its start
            char line[256];
            static ChatHistoryShared dump;
            if (!History.Supported || !ChatReadHistory(chat.FirstRing(),dump)) {
                core->GetChatManager()->Write(0,false,"[uihook:history] the first log window's history could not be read.");
                return true;
            }
            snprintf(line,sizeof(line),"[uihook:history] %u lines, %u bytes; the newest 12 (mode, serial, flags, +38, text):",dump.Count,dump.Used);
            core->GetChatManager()->Write(0,false,line);
            for (uint32_t i=dump.Count>12 ? dump.Count-12 : 0;i<dump.Count;i++) {
                const ChatHistoryLine& l=dump.Lines[i];
                char text[64]={}; uint32_t n=0;
                for (uint32_t j=0;j<l.Length && n<48;j++) { const char c=dump.Text[l.Offset+j]; text[n++]=(c==0x1e || c==0x1f) ? '^' : c; }
                snprintf(line,sizeof(line),"[uihook:history] %04X %u %02X %08X %s",l.Mode,l.Serial,l.Flags,l.Extra,text);
                core->GetChatManager()->Write(0,false,line);
            }
            return true;
        }
        if (command && _stricmp(command,"/uihook chat")==0) {
            char line[256];
            snprintf(line,sizeof(line),"[uihook:chat] ABI 13, mask %u, frame %u; primary native/drawn %u/%u, split %u/%u, input %u/%u.",
                Chat.SupportedMask,Chat.Frame,Chat.NativeFrame[0],Chat.DrawnFrame[0],Chat.NativeFrame[1],Chat.DrawnFrame[1],Chat.NativeFrame[2],Chat.DrawnFrame[2]);
            core->GetChatManager()->Write(0,false,line);
            snprintf(line,sizeof(line),"[uihook:chat] state 0x%x at %u, full bounds at %u; history scroll %u, cursor %u/%u, filter %u (browsing/filter menus remain native).",
                Chat.StateFlags,Chat.StateFrame,Chat.ExpandedRectFrame,Chat.FullScroll,Chat.FullCursor,Chat.FullPageRows,Chat.FullFilter);
            core->GetChatManager()->Write(0,false,line);
            snprintf(line,sizeof(line),"[uihook:chat] replacing %u (1 tabs, 2 scrollbar, 4 text, 8 all); %u tabs measured at %u; scrollbar page %u of %u rows, %u above, at %u.",
                replaceControls,Chat.TabCount,Chat.TabFrame,Chat.ScrollPage,Chat.ScrollCount,Chat.ScrollTop,Chat.ScrollFrame);
            core->GetChatManager()->Write(0,false,line);
            snprintf(line,sizeof(line),"[uihook:chat] text: row site %s; %u rows at %u, serial %u, %u bytes.",
                ChatText.call ? "taken" : "not found", Chat.TextCount,Chat.TextFrame,Chat.TextSerial,lastTextUsed);
            core->GetChatManager()->Write(0,false,line);
            unsigned firstModes=0,secondModes=0;
            for (unsigned i=0;i<8;i++) for (unsigned b=0;b<32;b++) { firstModes+=(Chat.WindowModes[0][i]>>b)&1; secondModes+=(Chat.WindowModes[1][i]>>b)&1; }
            snprintf(line,sizeof(line),"[uihook:chat] windows: routing %s at %u; the second window %s; the first keeps %u modes, the second %u; split bounds at %u.",
                windowRoutes.Ready() ? "read" : "not found", Chat.WindowFrame, Chat.WindowFlags & CHAT_SECOND_WINDOW ? "shown" : "hidden", firstModes, secondModes, Chat.SplitRectFrame);
            core->GetChatManager()->Write(0,false,line);
            snprintf(line,sizeof(line),"[uihook:chat] lines at %u: the first %u of %u (fewest %u), the second %u of %u (fewest %u).",
                Chat.LinesFrame,Chat.Lines[0][0],Chat.Lines[0][1],Chat.Lines[0][2],Chat.Lines[1][0],Chat.Lines[1][1],Chat.Lines[1][2]);
            core->GetChatManager()->Write(0,false,line);
            unsigned categories=0,modes=0;
            for (unsigned i=0;i<256;i++) { if (Chat.CategoryColors[i]) categories++; if (Chat.ModeCategory[i]) modes++; }
            snprintf(line,sizeof(line),"[uihook:chat] colours %s at %u, serial %u: %u categories, %u modes; say (mode 1) %08X, 1E 51 %08X.",
                colorTables.Ready() ? "read" : "not found", Chat.ColorFrame, Chat.ColorSerial, categories, modes,
                Chat.CategoryColors[Chat.ModeCategory[1]], Chat.CategoryColors[0x51]);
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
        if (capture<0) { out.Clear(); Forgive(static_cast<unsigned>(index)); return 1; }
        if (index<6 ? (!Shared.Hooked || !(Shared.SupportedMask & (index<3 ? (1u<<index) : 8u)))
                    : index<8 ? !(Hud.SupportedMask & (1u<<(index-6)))
                              : !(Chat.SupportedMask & (1u<<(index-8)))) return 0;
        if (!capture) { out.Clear(); out.submitted=Shared.Frame; return 1; }
        const unsigned slot=static_cast<unsigned>(index);
        auto* gui=core->GetGuiManager();
        ImDrawList* list=gui ? gui->GetWindowDrawList() : nullptr;
        if (!list) return Refuse(slot,REFUSED_NO_LIST);
        staging.Clear();
        const ImVec2 display=gui->GetIO().DisplaySize;
        if (!(display.x>0 && display.y>0)) return Refuse(slot,REFUSED_NO_LIST);
        staging.width=display.x; staging.height=display.y; staging.font=Font();
        uint8_t why=REFUSED_NONE;
        unsigned commands=0;
        for (int c=0;c<list->CmdBuffer.Size && !why;c++) {
            const ImDrawCmd& cmd=list->CmdBuffer[c];
            if (!cmd.ElemCount) continue;
            if (cmd.UserCallback || cmd.ElemCount%3 || cmd.IdxOffset+uint64_t(cmd.ElemCount)>uint64_t(list->IdxBuffer.Size)) { why=REFUSED_COMMAND; break; }
            if (++commands>PARTY_MAX_COMMANDS) { why=REFUSED_TOO_MANY_COMMANDS; break; }
            // Resolve all textures on the C++ side, including the font atlas; never interpret mark 1 as a pointer.
            const ImTextureData* data=cmd.TexRef._TexData;
            if (data && data->Status!=ImTextureStatus_OK && data->Status!=ImTextureStatus_WantUpdates) { why=REFUSED_TEXTURE_NOT_READY; break; }
            // Read fields, not assertion-bearing GetTexID methods (the recent namehook failure).
            const ImTextureID id=data ? data->TexID : cmd.TexRef._TexID;
            // The id's low 32 bits, sign-extended or not: a texture above 2 GB is drawn with as any other
            const uint32_t address=TextureAddress(static_cast<uint64_t>(id));
            if (!address) { why=REFUSED_TEXTURE_ID; break; }
            auto* texture=reinterpret_cast<IDirect3DBaseTexture8*>(static_cast<uintptr_t>(address));
            uint32_t first=static_cast<uint32_t>(staging.vertices.size());
            PartyClip clip={cmd.ClipRect.x,cmd.ClipRect.y,cmd.ClipRect.z,cmd.ClipRect.w};
            if (!std::isfinite(clip.left)||!std::isfinite(clip.top)||!std::isfinite(clip.right)||!std::isfinite(clip.bottom)) { why=REFUSED_CLIP; break; }
            if (clip.right<=clip.left || clip.bottom<=clip.top) continue;
            for (unsigned i=0;i<cmd.ElemCount && !why;i+=3) {
                PartyVertex triangle[3], polygon[12];
                for (unsigned j=0;j<3;j++) {
                    uint64_t at=uint64_t(cmd.VtxOffset)+list->IdxBuffer[cmd.IdxOffset+i+j];
                    if (at>=uint64_t(list->VtxBuffer.Size)) { why=REFUSED_INDEX; break; }
                    const ImDrawVert& v=list->VtxBuffer[static_cast<int>(at)];
                    // ImGui ABGR -> Direct3D ARGB.
                    uint32_t color=(v.col&0xff00ff00)|((v.col&255)<<16)|((v.col>>16)&255);
                    triangle[j]={v.pos.x,v.pos.y,0,1,color,v.uv.x,v.uv.y};
                    if (!std::isfinite(v.pos.x)||!std::isfinite(v.pos.y)||!std::isfinite(v.uv.x)||!std::isfinite(v.uv.y)) why=REFUSED_VERTEX;
                }
                if (why) break;
                unsigned n=ClipTriangle(triangle,clip,polygon);
                if (n<3) continue;
                if (staging.vertices.size()+(n-2)*3>PARTY_MAX_VERTICES) { why=REFUSED_TOO_MANY_VERTICES; break; }
                for (unsigned j=1;j+1<n;j++) {
                    staging.vertices.push_back(polygon[0]); staging.vertices.push_back(polygon[j]); staging.vertices.push_back(polygon[j+1]);
                }
            }
            AppendRun(staging.runs,texture,first,static_cast<uint32_t>(staging.vertices.size())-first);
        }
        if (why) { staging.Clear(); out.Clear(); return Refuse(slot,why); }
        Accept(slot);
        out.Clear();
        out.vertices.swap(staging.vertices); out.runs.swap(staging.runs);
        out.width=staging.width; out.height=staging.height; out.font=staging.font; out.submitted=Shared.Frame;
        Shared.CapturedVertices=static_cast<uint32_t>(out.vertices.size());
        if ((index==8 || index==9) && !out.vertices.empty()) {
            const ImVec2 pos=gui->GetWindowPos(), size=gui->GetWindowSize();
            const float rect[]={pos.x,pos.y,pos.x+size.x,pos.y+size.y};
            ChatClockAnchor(Chat,index-8,rect);
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
        out.failures=Shared.Failures;
        for (unsigned i=0;i<11;i++) {
            out.refusal[i]=refusal[i];
            out.refusalAge[i]=refusal[i] ? Shared.Frame-refusedFrame[i] : 0;
            out.refusalRun[i]=refusedRun[i];
        }
    }
    void StopChat() { drawings[8].Clear(); drawings[9].Clear(); drawings[10].Clear(); Forgive(8); Forgive(9); Forgive(10); staging.Clear(); Chat.ReplacementRectFrame=0; expandedCapture=controlsValid=false; replaceControls=0; Chat.ControlStyleFrame=0; Chat.TabFrame=Chat.ScrollFrame=Chat.TextFrame=0; }
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
            // the addon's own tabs, scrollbar and text stand in only while its frame does, and only where the hooks are
            replaceControls=controlsValid ? ChatReplaceGranted(Chat.ReplaceControls,(Chat.SupportedMask & CHAT_REPLACE_SUPPORTED)!=0,
                (Chat.SupportedMask & CHAT_TEXT_SUPPORTED)!=0) : 0;
        }
        if (!result) drawings[index+8].Clear(); // failed capture restores native even after an empty Begin
        return result;
    }
    int CaptureHud(int index,int capture) {
        if (index==-1) { StopHud(); return 1; }
        if (index<0 || index>1) return 0;
        return Capture(index+6,capture);
    }
    // Whether Replay would draw a drawing (or its empty replacement) now
    bool Replayable(unsigned index) {
        const Drawing& drawing=drawings[index];
        return drawing.Fresh() && (drawing.vertices.empty() || drawing.font==Font());
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
        // under lens's warp, the tip is put where the warp shows the target (x and y are menu-layer pixels)
        int16_t menu[2]={};
        if (menuManager && ChatRead(menuManager+0x80,menu,sizeof(menu))) {
            int32_t ax=static_cast<int32_t>(x), ay=static_cast<int32_t>(y);
            if (WarpArrow(ax,ay,menu[0],menu[1],LensBlock())) { x=static_cast<uint32_t>(ax); y=static_cast<uint32_t>(ay); }
        }
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
        float* rect=index==0 ? Chat.PrimaryRect : index==1 ? Chat.SplitRect : index==3 ? Chat.ExpandedRect : Chat.InputRect;
        uint32_t& frame=index==0 ? Chat.PrimaryRectFrame : index==1 ? Chat.SplitRectFrame : index==3 ? Chat.ExpandedRectFrame : Chat.InputRectFrame;
        frame=0;
        if (!WindowRect(window,result)) return;
        rect[0]=result.Left; rect[1]=result.Top; rect[2]=result.Right; rect[3]=result.Bottom;
        frame=result.Frame;
    }
    bool ControlsActive() const { return expandedSkin && controlsValid; }
    // The whole full log left undrawn, the addon drawing all of it: asked and granted with this frame's capture
    bool Mirrored() const { return expandedSkin && controlsValid && (replaceControls & CHAT_REPLACE_ALL); }
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
        // the selection art in a skinned full log measured (drawn or not), so its rows are published lit
        const bool measure=expandedSkin && !cursor && ChatSelectionColor(color) && !chatMeasure && selectionCount<8;
        if (measure) { selectionBounds[selectionCount]=ChatBounds(); chatMeasure=&selectionBounds[selectionCount]; }
        const MirrorPhase mirrorWas=cursor ? MenuMirror.Phase(MIRROR_CURSOR) : MenuMirror.Element(color);
        const MirrorPhase nativeWas=NativeMenus.Phase(cursor ? MIRROR_CURSOR : MIRROR_ELEMENT);
        ForwardChatWindowArt(reinterpret_cast<ChatWindowSprite>(ChatControls.targets[cursor ? CHAT_ART_CURSOR : CHAT_ART_SELECTION]),
            expandedSkin && !Mirrored(),ControlsActive(),controlStyle,cursor,blocking,sprite,x,y,sx,sy,color,a,b,c);
        MenuMirror.Phase(mirrorWas); NativeMenus.Phase(nativeWas);
        if (measure) { if (chatMeasure->vertices) selectionCount++; chatMeasure=nullptr; }
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
        ChatScrollInfo mirrorInfo;
        if (MenuMirror.Active() && ChatScrollRead(object,mirrorInfo)) MenuMirror.Scrollbar(mirrorInfo);
        const MirrorPhase mirrorWas=MenuMirror.Phase(MIRROR_SCROLL),nativeWas=NativeMenus.Phase(MIRROR_SCROLL);
        ForwardChatScroll(reinterpret_cast<ChatScrollDraw>(ChatControls.targets[CHAT_ART_SCROLL]),ControlsActive(),controlStyle,object);
        MenuMirror.Phase(mirrorWas); NativeMenus.Phase(nativeWas);
        chatMeasure=nullptr; blocking=was;
        if (!measure) return;
        Chat.ScrollFrame=0;
        if (fields && NormalizeChat(scrollBounds,Chat.ScrollRect)) {
            Chat.ScrollPage=info.page; Chat.ScrollCount=info.count; Chat.ScrollTop=info.top; Chat.ScrollFrame=Shared.Frame;
        }
    }
    // A row of the full log's text as the game draws it in a skinned full log: measured from its glyphs'
    // screen-space vertices, decoded from its glyph words to the bytes the game was given, and, where the addon
    // draws its own text, left undrawn (glyphs and the cursor's mark alike: this call's GPU submissions blocked);
    // the game's rows, cursor and hit-tests untouched. Anywhere else, a compact log's row, it is the game's call.
    void ChatRow(const uint16_t* text,const ChatRowHeader& header,int32_t x,int32_t y,uint32_t alpha,uint32_t flag,void* out,uint32_t zero) {
        const bool skinned=expandedSkin && expandedOwner;
        const bool measure=skinned && rowCount<CHAT_TEXT_ROWS;
        const bool was=blocking;
        if (ChatHidden(replaceControls,CHAT_REPLACE_TEXT,skinned && controlsValid)) blocking=true;
        if (measure) { rowBounds=ChatBounds(); chatMeasure=&rowBounds; }
        reinterpret_cast<ChatRowDraw>(ChatText.target)(text,header,x,y,alpha,flag,out,zero);
        chatMeasure=nullptr; blocking=was;
        if (!measure) return;
        ChatTextRow& row=Chat.Rows[rowCount];
        row=ChatTextRow();
        ChatRowInfo info;
        const bool fields=ChatRowFields(header,info);
        row.Mode=info.mode;
        if (info.state==1) row.Flags|=CHAT_ROW_CURSOR; else if (info.state==2) row.Flags|=CHAT_ROW_PRESSED;
        if (info.marks & 0x40) row.Flags|=CHAT_ROW_MARKED;
        row.Offset=textUsed;
        if (fields && info.words && text && ChatRead(text,rowWords,info.words*2)) {
            bool cut=false;
            row.Length=ChatDecodeRow(rowWords,info.words,Chat.Text+textUsed,CHAT_TEXT_BYTES-textUsed,cut);
            textUsed+=row.Length;
            if (cut) row.Flags|=CHAT_ROW_CUT;
        } else if (info.words) row.Flags|=CHAT_ROW_CUT; // words that could not be read, or more than a row holds: none published
        // its place: its glyphs', or, for a row that drew none, where the game would have drawn them (a 16-pixel cell from x, y)
        ChatBounds empty; empty.Add(float(x)-0.5f,float(y)-0.5f); empty.Add(float(x)+15.5f,float(y)+15.5f);
        if (NormalizeChat(rowBounds.vertices ? rowBounds : empty,row.Rect)) {
            row.Flags|=CHAT_ROW_PLACED;
            float lit[4];
            for (unsigned i=0;i<selectionCount;i++)
                if (NormalizeChat(selectionBounds[i],lit) && ChatRowLit(row.Rect,lit)) { row.Flags|=CHAT_ROW_LIT; break; }
        }
        rowCount++;
    }
    // The rows drawn in this content Draw published together, the serial moved only where they differ from the last
    void PublishChatText() {
        const bool same=rowCount==lastRowCount && textUsed==lastTextUsed
            && !memcmp(Chat.Rows,lastRows,sizeof(ChatTextRow)*rowCount) && !memcmp(Chat.Text,lastText,textUsed);
        if (!same) {
            memcpy(lastRows,Chat.Rows,sizeof(ChatTextRow)*rowCount); memcpy(lastText,Chat.Text,textUsed);
            lastRowCount=rowCount; lastTextUsed=textUsed; Chat.TextSerial++;
        }
        Chat.TextCount=rowCount; Chat.TextFrame=rowCount ? Shared.Frame : 0;
    }
    void ExpandedContent(void* owner) {
        ChatNativeContent(expandedSkin,Mirrored(),blocking);
        ChatOwnerScope ownerScope(expandedOwner,expandedSkin ? owner : nullptr);
        rowCount=0; textUsed=0;
        reinterpret_cast<void(__fastcall*)(void*,void*)>(ExpandedChatDetour.trampoline)(owner,nullptr);
        if (expandedSkin) PublishChatText();
    }
    void Render(void* window) {
        CensusScope censusScope(MenuCensus,window);
        Mirror::Saved mirrorSaved;
        const bool mirrorHidden=MenuMirror.Begin(window,core->GetDirect3DDevice(),mirrorSaved);
        struct NativeScope { NativeLook::Saved was; ~NativeScope() { NativeMenus.Leave(was); } } nativeScope{NativeEnter(window)};
        struct TextureScope { char was[17]; ~TextureScope() { memcpy(Textures.window,was,sizeof(was)); } } textureScope;
        memcpy(textureScope.was,Textures.window,sizeof(textureScope.was));
        if (Textures.on) {
            void* header=nullptr; char name[16];
            const bool named=window && ChatRead(static_cast<uint8_t*>(window)+4,&header,4) && header && ChatRead(static_cast<uint8_t*>(header)+0x46,name,16);
            Textures.Window(named ? name : "?");
        }
        struct WatchScope { int was; ~WatchScope() { MenuWatch.Leave(was); } } watchScope{MenuWatch.on ? WatchEnter(window,mirrorHidden) : -1};
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
        if (Menus.Supported) {
            int dimensions[2]={}; D3DVIEWPORT8 viewport={};
            auto* device=core->GetDirect3DDevice();
            const uint32_t host=Menus.HostSlot;
            const bool wantMenus=host<2 && MenuFresh(Menus,Chat,Shared.Frame);
            const bool wantLog=chatIndex==3 && LogFresh(Menus,Shared.Frame); // the full log placed where the addon asks
            const bool screen=(wantMenus || wantLog) && device && SUCCEEDED(device->GetViewport(&viewport)) && menuManager
                && ChatRead(menuManager+0x80,dimensions,sizeof(dimensions));
            const bool active=wantMenus && screen && drawings[host+8].Fresh() && !drawings[host+8].vertices.empty();
            menus.Before(window,Menus,active,dimensions,viewport.Width,viewport.Height);
            if (chatIndex==3) menus.BeforeLog(window,Menus,wantLog && screen,dimensions,viewport.Width,viewport.Height);
        }
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
        // The first log held back for a second log stacked over it, drawn once the second is
        const bool defer=chatIndex==0 && chatReady && Replayable(8)
            && ChatDeferPrimary(Chat,drawings[9].Fresh() && !drawings[9].vertices.empty());
        bool replaced=defer ? true : chatIndex>=0 ? chatReady && Replay(static_cast<unsigned>(chatSlot+8))
            : index==3 ? ReplayTargets() : index>=0 && Replay(static_cast<unsigned>(index));
        if (defer) primaryDeferred=Shared.Frame;
        else if (chatIndex==1 && primaryDeferred==Shared.Frame) { Replay(8); primaryDeferred=0; }
        blocking=replaced || mirrorHidden;
        expandedSkin=chatIndex==3 && replaced && expandedCapture;
        // a full log drawn afresh: its tabs, scrollbar and rows measured again, or not at all if the game leaves them out
        if (chatIndex==3) { Chat.TabFrame=Chat.ScrollFrame=Chat.TextFrame=0; chatViewportKnown=false; chatMeasure=nullptr; measuringTabs=false; rowCount=0; textUsed=0; selectionCount=0; }
        targetScope=index==3 && replaced;
        reinterpret_cast<void(__fastcall*)(void*,void*)>(WindowDetour.trampoline)(window,nullptr);
        // Read after the client's animation/layout update, even when this window is not replaced.
        // Read-only capture geometry for Lua's next submission. Registered action menus alone
        // may have been retargeted above, before the native layout update.
        if (index>=0) RecordRect(static_cast<unsigned>(index),window);
        if (chatIndex>=0) RecordChatRect(chatIndex,window);
        MenuMirror.End(mirrorSaved);
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
static void __cdecl DrawChatRow(const uint16_t* text,ChatRowHeader header,int32_t x,int32_t y,uint32_t alpha,uint32_t flag,void* out,uint32_t zero) {
    if (PartyHook::Instance) PartyHook::Instance->ChatRow(text,header,x,y,alpha,flag,out,zero);
    else reinterpret_cast<ChatRowDraw>(ChatText.target)(text,header,x,y,alpha,flag,out,zero);
}
static void __fastcall DrawExpandedChat(void* owner,void*) {
    if (PartyHook::Instance) PartyHook::Instance->ExpandedContent(owner);
    else reinterpret_cast<void(__fastcall*)(void*,void*)>(ExpandedChatDetour.trampoline)(owner,nullptr);
}
// A print's text read for the texture census's glyphs, as far as its end or 255 bytes
static void PrintBegin(const char* text) {
    if (!Textures.on || !text) { Textures.PrintBegin(nullptr,0); return; }
    uint8_t bytes[256]; size_t n=0;
    while (n<sizeof(bytes)-1 && ChatRead(text+n,bytes+n,1) && bytes[n]) n++;
    Textures.PrintBegin(bytes,n);
}
// Each text route heard, then the game's own, unchanged; a text call within one counted as nested
static int32_t __cdecl CensusBitmap(int32_t x,int32_t y,const char* text,uint32_t colour,uint32_t sx,uint32_t sy,uint32_t centred) {
    MenuCensus.Text(CENSUS_BITMAP,static_cast<int16_t>(x),static_cast<int16_t>(y),text,colour); MenuCensus.depth++; PrintBegin(text);
    MenuMirror.TextBegin(CENSUS_BITMAP,static_cast<int16_t>(x),static_cast<int16_t>(y),text,colour);
    NativeMenus.text++;
    const int32_t end=reinterpret_cast<int32_t(__cdecl*)(int32_t,int32_t,const char*,uint32_t,uint32_t,uint32_t,uint32_t)>(CensusBitmapDetour.trampoline)(x,y,text,colour,sx,sy,centred);
    NativeMenus.text--;
    MenuCensus.depth--; MenuMirror.TextEnd(); Textures.PrintEnd(); return end;
}
static int32_t __cdecl CensusScaled(int32_t x,int32_t y,const char* text,uint32_t colour,uint32_t flag,uint32_t sx,uint32_t sy) {
    MenuCensus.Text(CENSUS_SCALED,static_cast<int16_t>(x),static_cast<int16_t>(y),text,colour); MenuCensus.depth++; PrintBegin(text);
    MenuMirror.TextBegin(CENSUS_SCALED,static_cast<int16_t>(x),static_cast<int16_t>(y),text,colour);
    NativeMenus.text++;
    const int32_t end=reinterpret_cast<int32_t(__cdecl*)(int32_t,int32_t,const char*,uint32_t,uint32_t,uint32_t,uint32_t)>(CensusScaledDetour.trampoline)(x,y,text,colour,flag,sx,sy);
    NativeMenus.text--;
    MenuCensus.depth--; MenuMirror.TextEnd(); Textures.PrintEnd(); return end;
}
static uint32_t __fastcall CensusFont(void* font,void*,int32_t x,int32_t y,const char* text,uint32_t a,uint32_t colour,uint32_t flags,uint32_t sx,uint32_t sy) {
    MenuCensus.Text(CENSUS_FONT,x,y,text,colour); MenuCensus.depth++; PrintBegin(text);
    MenuMirror.TextBegin(CENSUS_FONT,x,y,text,colour);
    NativeMenus.text++;
    const uint32_t result=reinterpret_cast<uint32_t(__fastcall*)(void*,void*,int32_t,int32_t,const char*,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t)>(CensusFontDetour.trampoline)(font,nullptr,x,y,text,a,colour,flags,sx,sy);
    NativeMenus.text--;
    MenuCensus.depth--; MenuMirror.TextEnd(); Textures.PrintEnd(); return result;
}
// A window's contents drawn, as Window::Render would, with the mirror told they are being drawn
static void __cdecl MirrorInput(MSG message) {
    if (MirrorBlock.Supported & MIRROR_SUPPORTED_MOUSE) {
        RECT client;
        if (MirrorMouseMessage(message.message) && GetClientRect(message.hwnd,&client))
            if (MirrorMapMessage(MirrorBlock,message,client.right-client.left,client.bottom-client.top)) MirrorMapped++;
    }
    reinterpret_cast<void(__cdecl*)(MSG)>(InputDetour.trampoline)(message);
}
static void __fastcall MirrorContent(void* owner,void*) {
    void* draw=(*static_cast<void***>(owner))[4];
    MenuMirror.Phase(MIRROR_CONTENT); NativeMenus.Phase(MIRROR_CONTENT);
    reinterpret_cast<void(__fastcall*)(void*,void*)>(draw)(owner,nullptr);
    MenuMirror.Phase(MIRROR_AFTER); NativeMenus.Phase(MIRROR_AFTER);
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
    catch (...) { PartyHook::Instance->Stop(); if (index>=0) PartyHook::Instance->RefusedByException(static_cast<unsigned>(index)); else ++Shared.Failures; return 0; }
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
    catch (...) { PartyHook::Instance->StopHud(); if (index>=0 && index<2) PartyHook::Instance->RefusedByException(static_cast<unsigned>(index)+6); else ++Shared.Failures; return 0; }
}
static int32_t __cdecl SubmitChat(int32_t index,int32_t capture) {
    if (!PartyHook::Instance) return 0;
    try { return PartyHook::Instance->CaptureChat(index,capture); }
    catch (...) { PartyHook::Instance->StopChat(); if (index>=0 && index<3) PartyHook::Instance->RefusedByException(static_cast<unsigned>(index)+8); else ++Shared.Failures; return 0; }
}
IPlugin* CreatePartyModule() { return new PartyHook(); }

void GetPartySlots(PartySlots& out) {
    out = PartySlots();
    if (PartyHook::Instance) PartyHook::Instance->Slots(out);
}

