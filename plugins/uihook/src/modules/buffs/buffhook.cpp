// buffhook: draws the buff addon's bar where, and when, the game draws its own row of status icons,
// in their place. See README.md.
//
// The game draws its status icons as one of its menus, each icon by a callback its list calls for
// every item it shows, and each icon's time (with the game's timers switched on) by a second. Both
// are taken: while the addon has written a bar lately, the first callback draws the whole bar for
// the first item and nothing for the others, and the second draws nothing. What the game draws after
// its status icons (its other menus) is drawn over the bar as it would be over them, and when the
// game does not draw them (no statuses, the interface hidden, a cutscene) the bar is not drawn either.
// When the addon has not written one, the callbacks are the game's own.

#include <windows.h>
#include <psapi.h>
#include <stdint.h>
#include <string.h>

#include "Ashita.h"
#include "buffhook.h"
#include "../../slots.h"
#include "detour.h"
#include "game.h"

#define CHAT_HEADER "\x1e\x51[\x1e\x06" "uihook:buffs\x1e\x51]\x1e\x01 "

static BuffShared Shared = { "BUFFHOOK-SHARED", BUFF_VERSION, sizeof(BuffShared), 0, 1, 0, 0.0f, 0.0f, 0.0f, 0.0f, -1, BUFF_NO_STATUS, 0, 0, 0, 0, {}, {} };

// ---------------------------------------------------------------------------------------------------
// Finding and taking the game's two callbacks

// The status icon list's window's setting for where its cursor goes: found, not taken
typedef void(__fastcall* CursorOffset)(void* window, void* unused, int32_t x, int32_t y);
static CursorOffset SetCursorOffset = nullptr;

// The status icon menu's item callback: list, the list's own value, the item's place, its number,
// and whether it is the chosen one
typedef void(__cdecl* ItemCallback)(void*, int32_t, int32_t, int32_t, int32_t, int32_t);

static void __cdecl DrawStatusIcon(void* list, int32_t extra, int32_t x, int32_t y, int32_t index, int32_t chosen);
static void __cdecl DrawStatusTime(void* list, int32_t extra, int32_t x, int32_t y, int32_t index, int32_t chosen);

static Detour IconDetour = {
    ICON_PATTERN, ICON_STOLEN, ICON_CALL_AT, reinterpret_cast<void*>(&DrawStatusIcon), nullptr, nullptr, {},
};
static Detour TimeDetour = {
    TIME_PATTERN, TIME_STOLEN, TIME_CALL_AT, reinterpret_cast<void*>(&DrawStatusTime), nullptr, nullptr, {},
};

// ---------------------------------------------------------------------------------------------------
// Drawing the bar

struct BarVertex {
    float x, y, z, rhw;
    DWORD color;
    float u, v;
};
#define BAR_FVF (D3DFVF_XYZRHW | D3DFVF_DIFFUSE | D3DFVF_TEX1)

static BarVertex Vertices[BUFF_QUADS * 6];

// Vertices that follow one another and are drawn from the same texture
struct BarRun {
    uint32_t texture;
    uint32_t first;
    uint32_t count;
};
static BarRun Runs[BUFF_QUADS];

// Everything of the device's state that drawing the bar changes. Recorded twice over: once to be put
// on the device, and once to be filled with what the game had, and put back.
static void SetBarStates(IDirect3DDevice8* device) {
    device->SetRenderState(D3DRS_ZENABLE, D3DZB_FALSE);
    device->SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
    device->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
    device->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
    device->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
    device->SetRenderState(D3DRS_ALPHATESTENABLE, FALSE);
    device->SetRenderState(D3DRS_COLORWRITEENABLE, 0x0F);
    device->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
    device->SetRenderState(D3DRS_LIGHTING, FALSE);
    device->SetRenderState(D3DRS_FOGENABLE, FALSE);
    device->SetRenderState(D3DRS_STENCILENABLE, FALSE);
    device->SetRenderState(D3DRS_SHADEMODE, D3DSHADE_GOURAUD);

    // the texture's colour and how solid it is, each scaled by the vertex's
    device->SetTextureStageState(0, D3DTSS_COLOROP, D3DTOP_MODULATE);
    device->SetTextureStageState(0, D3DTSS_COLORARG1, D3DTA_TEXTURE);
    device->SetTextureStageState(0, D3DTSS_COLORARG2, D3DTA_DIFFUSE);
    device->SetTextureStageState(0, D3DTSS_ALPHAOP, D3DTOP_MODULATE);
    device->SetTextureStageState(0, D3DTSS_ALPHAARG1, D3DTA_TEXTURE);
    device->SetTextureStageState(0, D3DTSS_ALPHAARG2, D3DTA_DIFFUSE);
    device->SetTextureStageState(0, D3DTSS_MINFILTER, D3DTEXF_LINEAR);
    device->SetTextureStageState(0, D3DTSS_MAGFILTER, D3DTEXF_LINEAR);
    device->SetTextureStageState(0, D3DTSS_MIPFILTER, D3DTEXF_NONE);
    device->SetTextureStageState(0, D3DTSS_ADDRESSU, D3DTADDRESS_CLAMP);
    device->SetTextureStageState(0, D3DTSS_ADDRESSV, D3DTADDRESS_CLAMP);
    device->SetTextureStageState(0, D3DTSS_TEXCOORDINDEX, 0);
    device->SetTextureStageState(0, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_DISABLE);
    device->SetTextureStageState(1, D3DTSS_COLOROP, D3DTOP_DISABLE);
    device->SetTextureStageState(1, D3DTSS_ALPHAOP, D3DTOP_DISABLE);

    device->SetTexture(0, nullptr);
    device->SetVertexShader(BAR_FVF);
    device->SetPixelShader(0);
    // drawing from vertices in memory leaves the device with no vertex buffer: the game's is put back
    device->SetStreamSource(0, nullptr, 0);
}

class BuffHook : public IPlugin {
private:
    IAshitaCore* m_AshitaCore = nullptr;
    IDirect3DBaseTexture8* m_Textures[BUFF_TEXTURES] = {}; // the addon's, held while they are drawn from
    DWORD m_BarStates = 0;   // the device's state as the bar is drawn with it
    DWORD m_SavedStates = 0; // the same states as the game had them, to put back
    void* m_CursorWindow = nullptr; // the window whose cursor is put out of sight, while it is

    // The vertices made from the addon's quads, and its textures held, kept while the addon hands
    // over the same bar (its Sequence) to be drawn in the same place
    bool m_Built = false;
    uint32_t m_BuiltSequence = 0;
    float m_BuiltLeft = 0.0f;
    float m_BuiltTop = 0.0f;
    uint32_t m_RunCount = 0;
    IDirect3DBaseTexture8* m_BuiltFont = nullptr; // imgui's font texture as it was then

    // imgui's font texture as its renderer made it, for a texture the addon gave as BUFF_TEXTURE_FONT:
    // read here, where it is a pointer, and not by the addon, which Ashita cannot hand it to once it
    // is above 2 GB. Asked each time the bar is drawn, as imgui makes the texture again when the font
    // atlas grows. Null while it has none ready.
    IDirect3DBaseTexture8* FontTexture() const {
        IGuiManager* gui = m_AshitaCore != nullptr ? m_AshitaCore->GetGuiManager() : nullptr;
        if (gui == nullptr) {
            return nullptr;
        }
        const ImFontAtlas* atlas = gui->GetIO().Fonts;
        const ImTextureData* data = atlas != nullptr ? atlas->TexData : nullptr;
        if (data == nullptr || (data->Status != ImTextureStatus_OK && data->Status != ImTextureStatus_WantUpdates)) {
            return nullptr;
        }
        return reinterpret_cast<IDirect3DBaseTexture8*>(static_cast<uintptr_t>(data->TexID));
    }

    void RetainTextures(bool keep, IDirect3DBaseTexture8* font = nullptr) {
        if (!keep) {
            m_Built = false;
        }
        m_BuiltFont = font;
        Shared.FontTexture = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(font));
        for (uint32_t i = 0; i < BUFF_TEXTURES; i++) {
            const uint32_t given = keep ? Shared.Textures[i] : 0;
            auto* texture = given == BUFF_TEXTURE_FONT ? font : reinterpret_cast<IDirect3DBaseTexture8*>(static_cast<uintptr_t>(given));
            if (texture != m_Textures[i]) {
                if (texture != nullptr) texture->AddRef();
                if (m_Textures[i] != nullptr) m_Textures[i]->Release();
                m_Textures[i] = texture;
            }
        }
    }

    void ReleaseStates() {
        IDirect3DDevice8* device = (m_AshitaCore != nullptr) ? m_AshitaCore->GetDirect3DDevice() : nullptr;
        if (device != nullptr) {
            if (m_BarStates != 0) device->DeleteStateBlock(m_BarStates);
            if (m_SavedStates != 0) device->DeleteStateBlock(m_SavedStates);
        }
        m_BarStates = 0;
        m_SavedStates = 0;
    }

    // The two records of the device's state the bar is drawn between, made the first time in a frame
    // it is drawn and let go as the frame is presented
    bool MakeStates(IDirect3DDevice8* device) {
        if (m_BarStates == 0) {
            device->BeginStateBlock();
            SetBarStates(device);
            if (FAILED(device->EndStateBlock(&m_BarStates))) m_BarStates = 0;
        }
        if (m_SavedStates == 0) {
            device->BeginStateBlock();
            SetBarStates(device);
            if (FAILED(device->EndStateBlock(&m_SavedStates))) m_SavedStates = 0;
        }
        return m_BarStates != 0 && m_SavedStates != 0;
    }

public:
    static BuffHook* Instance;

    const char* GetName(void) const override { return "buffhook"; }
    const char* GetAuthor(void) const override { return "win"; }
    const char* GetDescription(void) const override { return "Draws the buff addon's bar in place of the game's status icons, under the menus that open over them."; }
    const char* GetLink(void) const override { return "https://github.com/Wincasts/win-xi"; }
    double GetVersion(void) const override { return 1.1; }
    uint32_t GetFlags(void) const override { return static_cast<uint32_t>(Ashita::PluginFlags::UseDirect3D); }

    bool Initialize(IAshitaCore* core, [[maybe_unused]] ILogManager* log, [[maybe_unused]] uint32_t id) override {
        m_AshitaCore = core;
        Instance = this;
        MODULEINFO module = {};
        uint8_t* begin = nullptr;
        if (GetModuleInformation(GetCurrentProcess(), GetModuleHandleA("FFXiMain.dll"), &module, sizeof(module))) {
            begin = static_cast<uint8_t*>(module.lpBaseOfDll);
        }
        if (begin != nullptr) {
            SetCursorOffset = reinterpret_cast<CursorOffset>(FindPattern(begin, module.SizeOfImage, CURSOR_OFFSET_PATTERN));
        }
        if (begin != nullptr && Take(IconDetour, begin, module.SizeOfImage) && Take(TimeDetour, begin, module.SizeOfImage)) {
            Shared.Hooked = 1;
        } else {
            Give(IconDetour);
            Give(TimeDetour);
            core->GetChatManager()->Write(0, false, CHAT_HEADER "This client's status icons were not recognised: the buff addon's bar is drawn over the game instead.");
        }
        return true;
    }

    void Release(void) override {
        Give(IconDetour);
        Give(TimeDetour);
        // the window's cursor back, if the game has drawn the list lately, and so still has it
        if (Shared.Frame - Shared.DrawnFrame <= BUFF_DRAW_FRAMES) {
            PutCursorBack(m_CursorWindow);
        }
        Shared.Hooked = 0;
        ReleaseStates();
        RetainTextures(false);
        Instance = nullptr;
    }

    // Ashita asks this of a plugin that uses Direct3D, and does not load one that says no
    bool Direct3DInitialize([[maybe_unused]] IDirect3DDevice8* device) override { return true; }

    void Direct3DPresent([[maybe_unused]] const RECT* source, [[maybe_unused]] const RECT* destination, [[maybe_unused]] HWND window, [[maybe_unused]] const RGNDATA* dirty) override {
        Shared.Frame++;
        ReleaseStates();
        // what the addon wrote and stopped writing is let go of: it may let go of its textures next
        if (!Fresh()) {
            RetainTextures(false);
        }
    }

    static bool Fresh() {
        return Shared.SubmitFrame != 0 && Shared.Frame - Shared.SubmitFrame <= BUFF_DRAW_FRAMES;
    }

    // The buff selector's cursor, the game's hand, is put out of sight while the bar is drawn in the
    // icons' place, as it points at where the game's icons would be; the addon draws its own. Put
    // back when the game draws its own icons again, or the plugin unloads.
    // Only the window being drawn, or the last one hidden while the game still draws it, is changed:
    // one the game has made again in its place is gone, and is forgotten.
    // Put away each frame it is drawn, not once a window: the game makes the list again (the cursor
    // at -5, -5 once more), often at the address the last one had, and the hand came back.
    void PutCursorAway(void* window) {
        if (SetCursorOffset == nullptr || window == nullptr) {
            return;
        }
        SetCursorOffset(window, nullptr, CURSOR_AWAY, CURSOR_AWAY);
        m_CursorWindow = window;
    }

    void PutCursorBack(void* window) {
        if (m_CursorWindow != nullptr && window == m_CursorWindow) {
            SetCursorOffset(m_CursorWindow, nullptr, CURSOR_OFFSET_X, CURSOR_OFFSET_Y);
        }
        m_CursorWindow = nullptr;
    }

    // Where the game would put its first icon, and which of them its cursor is on
    void Place(const uint8_t* list, float x, float y) {
        Shared.OriginX = x;
        Shared.OriginY = y;
        Shared.DrawnFrame = Shared.Frame;
        const int32_t cursor = *reinterpret_cast<const int32_t*>(list + LIST_CURSOR);
        const uint32_t count = *reinterpret_cast<const uint16_t*>(list + LIST_COUNT);
        Shared.Cursor = cursor;
        Shared.CursorStatus = (cursor >= 0 && static_cast<uint32_t>(cursor) < count && cursor < LIST_ITEMS_MOST)
            ? *reinterpret_cast<const uint16_t*>(list + LIST_STATUSES + cursor * 2) : BUFF_NO_STATUS;
        void* window = *reinterpret_cast<void* const*>(list + LIST_WINDOW);
        if (Fresh()) {
            PutCursorAway(window);
        } else {
            PutCursorBack(window);
        }
        IDirect3DDevice8* device = m_AshitaCore->GetDirect3DDevice();
        D3DVIEWPORT8 viewport;
        if (device != nullptr && SUCCEEDED(device->GetViewport(&viewport))) {
            Shared.Width = static_cast<float>(viewport.Width);
            Shared.Height = static_cast<float>(viewport.Height);
        }
    }

    // The vertices, in runs of quads from one texture in the order the addon wrote them: made again
    // only when the addon has written the bar afresh, or the game has moved where it goes
    void Build(float left, float top, IDirect3DBaseTexture8* font) {
        RetainTextures(true, font);
        m_Built = true;
        m_BuiltSequence = Shared.Sequence;
        m_BuiltLeft = left;
        m_BuiltTop = top;

        // on the pixel's middle, as the game draws its own
        left -= 0.5f;
        top -= 0.5f;
        const uint32_t count = Shared.Count <= BUFF_QUADS ? Shared.Count : BUFF_QUADS;
        uint32_t made = 0;
        m_RunCount = 0;
        for (uint32_t i = 0; i < count; i++) {
            const BuffQuad& quad = Shared.Quads[i];
            if (quad.Texture != BUFF_SOLID && (quad.Texture >= BUFF_TEXTURES || m_Textures[quad.Texture] == nullptr)) {
                continue;
            }
            if (m_RunCount == 0 || Runs[m_RunCount - 1].texture != quad.Texture) {
                Runs[m_RunCount++] = { quad.Texture, made, 0 };
            }
            Runs[m_RunCount - 1].count += 6;

            const float x0 = left + quad.X0, y0 = top + quad.Y0, x1 = left + quad.X1, y1 = top + quad.Y1;
            BarVertex* v = &Vertices[made];
            v[0] = { x0, y0, 0.0f, 1.0f, quad.Color, quad.U0, quad.V0 };
            v[1] = { x1, y0, 0.0f, 1.0f, quad.Color, quad.U1, quad.V0 };
            v[2] = { x0, y1, 0.0f, 1.0f, quad.Color, quad.U0, quad.V1 };
            v[3] = { x1, y0, 0.0f, 1.0f, quad.Color, quad.U1, quad.V0 };
            v[4] = { x1, y1, 0.0f, 1.0f, quad.Color, quad.U1, quad.V1 };
            v[5] = { x0, y1, 0.0f, 1.0f, quad.Color, quad.U0, quad.V1 };
            made += 6;
        }
    }

    void DrawBar(float left, float top) {
        IDirect3DDevice8* device = m_AshitaCore->GetDirect3DDevice();
        if (device == nullptr) {
            return;
        }
        IDirect3DBaseTexture8* font = FontTexture();
        if (!m_Built || m_BuiltSequence != Shared.Sequence || m_BuiltLeft != left || m_BuiltTop != top || m_BuiltFont != font) {
            Build(left, top, font);
        }
        const uint32_t runCount = m_RunCount;
        if (runCount == 0 || !MakeStates(device)) {
            return;
        }

        device->CaptureStateBlock(m_SavedStates);
        device->ApplyStateBlock(m_BarStates);
        for (uint32_t i = 0; i < runCount; i++) {
            // a run of colour alone is drawn with the vertices' colour, from no texture
            const bool solid = Runs[i].texture == BUFF_SOLID;
            if (i == 0 || solid != (Runs[i - 1].texture == BUFF_SOLID)) {
                const DWORD operation = solid ? D3DTOP_SELECTARG2 : D3DTOP_MODULATE;
                device->SetTextureStageState(0, D3DTSS_COLOROP, operation);
                device->SetTextureStageState(0, D3DTSS_ALPHAOP, operation);
            }
            device->SetTexture(0, solid ? nullptr : m_Textures[Runs[i].texture]);
            device->DrawPrimitiveUP(D3DPT_TRIANGLELIST, Runs[i].count / 3, &Vertices[Runs[i].first], sizeof(BarVertex));
        }
        device->ApplyStateBlock(m_SavedStates);
    }
};

BuffHook* BuffHook::Instance = nullptr;

static void __cdecl DrawStatusIcon(void* list, int32_t extra, int32_t x, int32_t y, int32_t index, int32_t chosen) {
    BuffHook* plugin = BuffHook::Instance;
    // the game draws its icon a pixel in from the item's corner; the bar where the first is with the cursor on it
    int32_t barX = x, barY = y;
    if (plugin != nullptr && index == 0) {
        const int32_t cursor = *reinterpret_cast<const int32_t*>(static_cast<const uint8_t*>(list) + LIST_CURSOR);
        barX = SteadyFirst(x, cursor);
        barY = SteadyFirst(y, cursor);
        plugin->Place(static_cast<const uint8_t*>(list), static_cast<float>(barX + 1), static_cast<float>(barY + 1));
    }
    if (plugin == nullptr || !BuffHook::Fresh()) {
        reinterpret_cast<ItemCallback>(IconDetour.trampoline)(list, extra, x, y, index, chosen);
        return;
    }
    if (index == 0) {
        plugin->DrawBar(static_cast<float>(barX + 1), static_cast<float>(barY + 1));
    }
}

static void __cdecl DrawStatusTime(void* list, int32_t extra, int32_t x, int32_t y, int32_t index, int32_t chosen) {
    if (BuffHook::Instance == nullptr || !BuffHook::Fresh()) {
        reinterpret_cast<ItemCallback>(TimeDetour.trampoline)(list, extra, x, y, index, chosen);
    }
}

IPlugin* CreateBuffModule() { return new BuffHook(); }

void GetBuffSlots(BuffSlots& out) {
    out = BuffSlots();
    if (BuffHook::Instance == nullptr) return;
    out.loaded = true;
    out.hooked = Shared.Hooked != 0;
    out.fresh = BuffHook::Fresh();
    out.quads = out.fresh ? Shared.Count : 0;
}

