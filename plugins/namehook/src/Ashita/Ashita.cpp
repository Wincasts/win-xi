/*
This file is part of Nameplate.
Copyright (C) 2024 BunnyBox Productions

Nameplate is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

Nameplate is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with Nameplate.
If not, see <https://www.gnu.org/licenses/>.
*/

#include <windows.h>
#include <strsafe.h>
#include <math.h>

#include "Ashita.h"

#include "../Nameplate.h"
#include "../NameBounds.h"

#include "exports.h"


#define LogLevel_Info ((uint32_t) Ashita::LogLevel::Info)
#define LogLevel_Critcal ((uint32_t) Ashita::LogLevel::Critical)

#define CHAT_HEADER "\x1e\x51[\x1e\x06namehook\x1e\x51]\x1e\x01 "

// The client's entities by index: players are in the second of these ranges, and what comes and goes
// with them (pets, trusts, fellows) in the third
#define PLAYERS_BEGIN 0x400
#define DYNAMIC_BEGIN 0x700

// A corner of a quad of a name drawn for an addon: a place in the picture, not in the world
struct NameVertex {
    float x, y, z, rhw;
    DWORD color;
    float u, v;
};
#define NAME_FVF (D3DFVF_XYZRHW | D3DFVF_DIFFUSE | D3DFVF_TEX1)

// How solid a name has to be, of 255, to be written to the picture's depth
#define NAME_SOLID 0x80

// One name's quads, each with its four dark copies for the edge
#define NAME_VERTICES (HOOK_QUADS_PER_NAME * 5 * 6)
static NameVertex Vertices[NAME_VERTICES];

// Vertices that follow one another and are drawn from the same texture
struct NameRun {
    uint32_t texture;
    uint32_t first;
    uint32_t count;
};
// Every expanded quad can start another texture run, including four outline
// copies. Capacity must match the worst case, not just the foreground quads.
static NameRun Runs[NAME_VERTICES / 6];
static DWORD EdgeColors[HOOK_QUADS_PER_NAME];


class AshitaNameplate : public IPlugin, private Nameplate {
private:
    IAshitaCore* m_AshitaCore;
    ILogManager* m_LogManager;
    uint32_t m_PluginId;

    // For drawing names an addon has drawn. All of it is the frame's: made as the first name of a
    // frame is drawn, and the state blocks let go as the frame is presented.
    IDirect3DBaseTexture8* m_Textures[HOOK_TEXTURES]; // the addon's textures, held while they are drawn from
    IDirect3DDevice8* m_Device; // the device, for the frame's names
    DWORD m_NameStates;   // the device's state as names are drawn with it
    DWORD m_SavedStates;  // the same states as the client had them, to put back
    D3DVIEWPORT8 m_Viewport;
    float m_ViewProjection[16];
    bool m_CanDraw;
    float m_HorizontalFit = 1.0f;
    NameBoundsCache m_NameBounds[HOOK_ENTITIES]; // CPU-only; no device-reset resources
    IDirect3DBaseTexture8* m_BubbleTextures[HOOK_TEXTURES]{};
    NameBoundsCache m_BubbleBounds[HOOK_ENTITIES];
    float m_BubbleFit = 1.0f;
    bool m_BubblesFresh = false;

    void RenderCustom(uint32_t entityIndex, const HookDrawing& drawing, const HookQuad* quads, const float* position, bool bubble);

    bool MakeNameStates();
    void PublishNames(bool frameDone);
    void ReleaseNameStates();
    void ReleaseTextures();

public:
	AshitaNameplate();

    virtual const char* GetName(void) const override;
    virtual const char* GetAuthor(void) const override;
    virtual const char* GetDescription(void) const override;
    virtual const char* GetLink(void) const override;
    virtual double GetVersion(void) const override;
    virtual double GetInterfaceVersion(void) const override;
    virtual int32_t GetPriority(void) const override;
    virtual uint32_t GetFlags(void) const override;

    virtual bool Initialize(IAshitaCore* core, ILogManager* log, uint32_t id) override;
    virtual void Release(void) override;

    virtual void Debug(const char* text) override {
        m_AshitaCore->GetChatManager()->Writef(0, false, CHAT_HEADER "%s", text);
    }

    virtual void GetFrameFacts(FrameFacts& facts, bool withPets) override;
    virtual void ProbeScene() override;
    virtual void BeginNames(const HookDraw& draw, bool fresh, float& targetWidth, float& targetHeight) override;
    virtual void DrawCustom(uint32_t entityIndex, const HookDrawing& drawing, const HookQuad* quads, const float* position) override;
    virtual void BeginBubbles(const HookDraw& draw, bool fresh) override;
    virtual void DrawBubble(uint32_t entityIndex, const HookDrawing& drawing, const HookQuad* quads, const float* position) override;

    virtual uint32_t GetSpawnFlags(uint32_t entityIndex) override {
        IEntity* entities = m_AshitaCore->GetMemoryManager()->GetEntity();
        if (entities == nullptr) {
            return 0;
        }

        const Ashita::FFXI::entity_t* entity = entities->GetRawEntity(entityIndex);
        return (entity != nullptr) ? entity->SpawnFlags : 0;
    }

    virtual bool GetConfigPath(wchar_t path[UNICODE_MAX_PATH]) override {
        const char* installPath = m_AshitaCore->GetInstallPath();

        StringCchPrintfW(path, UNICODE_MAX_PATH, L"%S\\config", installPath);
        return true;
    }

    bool HandleCommand(int32_t mode, const char* command, bool injected) override;

    // Ashita asks this of a plugin that uses Direct3D, and does not load one that says no
    bool Direct3DInitialize([[maybe_unused]] IDirect3DDevice8* device) override {
        return true;
    }

    void Direct3DEndScene(bool isRenderingBackBuffer) override;
    void Direct3DPresent(const RECT* pSourceRect, const RECT* pDestRect, HWND hDestWindowOverride, const RGNDATA* pDirtyRegion) override;

    virtual void ShowMessage(MESSAGE message, int param) override;
    virtual void CommandError(const char* command) override;
};

AshitaNameplate::AshitaNameplate() : m_AshitaCore(nullptr), m_LogManager(nullptr), m_PluginId(0),
        m_Textures{}, m_Device(nullptr), m_NameStates(0), m_SavedStates(0), m_Viewport{}, m_ViewProjection{}, m_CanDraw(false) {
}

const char* AshitaNameplate::GetName(void) const {
    return "namehook";
}

const char* AshitaNameplate::GetAuthor(void) const {
    return "BunnyBox Productions, win";
}

const char* AshitaNameplate::GetDescription(void) const {
    return "Corrects defects in nameplate rendering, shows and hides names by category, and lists the names drawn for addons.";
}

const char* AshitaNameplate::GetLink(void) const {
    return "https://www.github.com/Shirk/Nameplate";
}

double AshitaNameplate::GetVersion(void) const {
    return 1.24;
}

double AshitaNameplate::GetInterfaceVersion(void) const {
    return ASHITA_INTERFACE_VERSION;
}

int32_t AshitaNameplate::GetPriority(void) const {
    return 0;
}

uint32_t AshitaNameplate::GetFlags(void) const {
    return static_cast<uint32_t>(Ashita::PluginFlags::UseCommands) | static_cast<uint32_t>(Ashita::PluginFlags::UseDirect3D);
}

bool AshitaNameplate::Initialize(IAshitaCore* core, ILogManager* log, uint32_t id) {
    m_AshitaCore = core;
    m_LogManager = log;
    m_PluginId = id;

    // These plugins patch the same instructions. Check before Init writes anything.
    for (const char* conflict : { "nameplate", "nameplatew", "nameplatehook" }) {
        if (core->GetPluginManager()->IsLoaded(conflict)) {
            log->Logf(LogLevel_Critcal, "namehook", "Cannot load while %s is running. Unload it first with /unload %s, then /load namehook.", conflict, conflict);
            core->GetChatManager()->Writef(0, false, CHAT_HEADER "Cannot load while %s is running. Use /unload %s, then /load namehook. Only one nameplate plugin can run at a time.", conflict, conflict);
            return false;
        }
    }

    int ret = this->Init();
    if (ret < 0) {
        m_LogManager->Logf(LogLevel_Critcal, "namehook", "Plugin Load Error: \"%d\"", ret);
        ShowMessage(MESSAGE::PLUGIN_LOAD_ERROR, ret);
        return false;
    }

	return true;
}

void AshitaNameplate::Release(void) {

    ReleaseNameStates();
    ReleaseTextures();

    int ret = this->Deinit();
    if (ret < 0) {
        m_LogManager->Logf(LogLevel_Critcal, "namehook", "Plugin Unload Error: \"%d\"", ret);
        ShowMessage(MESSAGE::PLUGIN_UNLOAD_ERROR, ret);
    }

    IPlugin::Release();
}

void AshitaNameplate::GetFrameFacts(FrameFacts& facts, bool withPets) {
    IMemoryManager* memory = m_AshitaCore->GetMemoryManager();
    IParty* party = memory->GetParty();
    IEntity* entities = memory->GetEntity();
    ITarget* target = memory->GetTarget();

    uint32_t selfIndex = 0;

    if (party != nullptr) {
        // slots 0-5 are the local player's party, 6-17 the other two parties of the alliance
        for (uint32_t i = 0; i < 18; i++) {
            if (party->GetMemberIsActive(i) != 0) {
                if (i < 6) {
                    facts.PartyIds[i] = party->GetMemberServerId(i);
                } else {
                    facts.AllianceIds[i - 6] = party->GetMemberServerId(i);
                }
            }
        }

        if (party->GetMemberIsActive(0) != 0) {
            selfIndex = party->GetMemberTargetIndex(0);
        }
    }

    if (target != nullptr) {
        // with a sub target up, the target proper is the second of the two
        facts.TargetIndex = target->GetTargetIndex(target->GetIsSubTargetActive());
    }

    if (entities == nullptr) {
        return;
    }

    if (selfIndex != 0) {
        const Ashita::FFXI::entity_t* self = entities->GetRawEntity(selfIndex);
        if (self != nullptr) {
            facts.PetIndex = self->PetTargetIndex;
        }
    }

    // the rest is a look at every player there is, and is not done every frame
    if (!withPets) {
        return;
    }

    auto mark = [&facts](uint32_t index) {
        if (index != 0 && index < HOOK_ENTITIES) {
            facts.Pets[index / 8] |= static_cast<uint8_t>(1 << (index % 8));
        }
    };

    // every player's pet and fellow
    for (uint32_t i = PLAYERS_BEGIN; i < DYNAMIC_BEGIN; i++) {
        const Ashita::FFXI::entity_t* entity = entities->GetRawEntity(i);
        if (entity != nullptr) {
            mark(entity->PetTargetIndex);
            mark(entity->FellowTargetIndex);
        }
    }

    // and what has an owner: the trusts
    for (uint32_t i = DYNAMIC_BEGIN; i < HOOK_ENTITIES; i++) {
        const Ashita::FFXI::entity_t* entity = entities->GetRawEntity(i);
        if (entity != nullptr && entity->TrustOwnerTargetIndex != 0) {
            mark(i);
        }
    }
}

static void DescribeSurface(IChatManager* chat, const char* what, IDirect3DSurface8* surface) {
    if (surface == nullptr) {
        chat->Writef(0, false, CHAT_HEADER "  %s: none", what);
        return;
    }

    D3DSURFACE_DESC desc;
    if (SUCCEEDED(surface->GetDesc(&desc))) {
        chat->Writef(0, false, CHAT_HEADER "  %s: %p %ux%u format %d multisample %d usage %lu", what, static_cast<void*>(surface),
            desc.Width, desc.Height, static_cast<int>(desc.Format), static_cast<int>(desc.MultiSampleType), desc.Usage);
    }
    surface->Release();
}

void AshitaNameplate::ProbeScene() {
    IChatManager* chat = m_AshitaCore->GetChatManager();
    IDirect3DDevice8* device = m_AshitaCore->GetDirect3DDevice();
    if (device == nullptr) {
        return;
    }

    chat->Write(0, false, CHAT_HEADER "As the client draws a name:");

    IDirect3DSurface8* surface = nullptr;
    DescribeSurface(chat, "target", SUCCEEDED(device->GetRenderTarget(&surface)) ? surface : nullptr);
    surface = nullptr;
    DescribeSurface(chat, "depth", SUCCEEDED(device->GetDepthStencilSurface(&surface)) ? surface : nullptr);
    surface = nullptr;
    DescribeSurface(chat, "back buffer", SUCCEEDED(device->GetBackBuffer(0, D3DBACKBUFFER_TYPE_MONO, &surface)) ? surface : nullptr);

    D3DVIEWPORT8 viewport;
    if (SUCCEEDED(device->GetViewport(&viewport))) {
        chat->Writef(0, false, CHAT_HEADER "  viewport: %lu,%lu %lux%lu MinZ %.4f MaxZ %.4f", viewport.X, viewport.Y, viewport.Width, viewport.Height, viewport.MinZ, viewport.MaxZ);
    }

    DWORD zEnable = 0, zFunc = 0, zWrite = 0, alphaTest = 0, alphaRef = 0;
    device->GetRenderState(D3DRS_ZENABLE, &zEnable);
    device->GetRenderState(D3DRS_ZFUNC, &zFunc);
    device->GetRenderState(D3DRS_ZWRITEENABLE, &zWrite);
    device->GetRenderState(D3DRS_ALPHATESTENABLE, &alphaTest);
    device->GetRenderState(D3DRS_ALPHAREF, &alphaRef);
    chat->Writef(0, false, CHAT_HEADER "  ZENABLE %lu ZFUNC %lu ZWRITEENABLE %lu ALPHATESTENABLE %lu ALPHAREF %lu", zEnable, zFunc, zWrite, alphaTest, alphaRef);

    D3DMATRIX projection;
    if (SUCCEEDED(device->GetTransform(D3DTS_PROJECTION, &projection))) {
        chat->Writef(0, false, CHAT_HEADER "  projection: _11 %.4f _22 %.4f _33 %.6f _43 %.6f _34 %.2f", projection._11, projection._22, projection._33, projection._43, projection._34);
    }
}

bool AshitaNameplate::HandleCommand([[maybe_unused]] int32_t mode, const char* command, [[maybe_unused]] bool injected) {
    return ParseCommand(command, true);
}

// The client draws its names between the scene's beginning and its end, and addons draw theirs as the
// frame is presented: the names are made ready as the scene ends, and again, whichever of this
// plugin and the addons is asked first, as the frame is presented, when the next frame's begin.
void AshitaNameplate::Direct3DEndScene(bool isRenderingBackBuffer) {
    // the client ends a scene a dozen times a frame: only the one the names were drawn in has any to make ready
    if (isRenderingBackBuffer && WantsPublish(false)) {
        PublishNames(false);
    }
}

void AshitaNameplate::Direct3DPresent([[maybe_unused]] const RECT* pSourceRect, [[maybe_unused]] const RECT* pDestRect, [[maybe_unused]] HWND hDestWindowOverride, [[maybe_unused]] const RGNDATA* pDirtyRegion) {
    ReleaseNameStates();
    PublishNames(true);
}

void AshitaNameplate::ReleaseNameStates() {
    IDirect3DDevice8* device = (m_AshitaCore != nullptr) ? m_AshitaCore->GetDirect3DDevice() : nullptr;
    if (device != nullptr) {
        if (m_NameStates != 0) {
            device->DeleteStateBlock(m_NameStates);
        }
        if (m_SavedStates != 0) {
            device->DeleteStateBlock(m_SavedStates);
        }
    }
    m_NameStates = 0;
    m_SavedStates = 0;
    m_Device = nullptr;
    m_CanDraw = false;
}

static void RetainTextures(IDirect3DBaseTexture8** textures, const HookDraw* draw) {
    for (size_t i = 0; i < HOOK_TEXTURES; i++) {
        auto* texture = draw != nullptr ? reinterpret_cast<IDirect3DBaseTexture8*>(static_cast<uintptr_t>(draw->Textures[i])) : nullptr;
        if (texture != textures[i]) {
            if (texture != nullptr) texture->AddRef();
            if (textures[i] != nullptr) textures[i]->Release();
            textures[i] = texture;
        }
    }
}

void AshitaNameplate::ReleaseTextures() {
    RetainTextures(m_Textures, nullptr);
    RetainTextures(m_BubbleTextures, nullptr);
    m_BubblesFresh = false;
}

void AshitaNameplate::BeginBubbles(const HookDraw& draw, bool fresh) {
    m_BubblesFresh = fresh;
    m_BubbleFit = draw.HorizontalFit();
    RetainTextures(m_BubbleTextures, fresh ? &draw : nullptr);
}

// Everything of the device's state that drawing a name changes. Recorded twice over: once to be
// put on the device, and once to be filled with what the client had, and put back.
static void SetNameStates(IDirect3DDevice8* device) {
    // tested against the picture's depth, and not written to it: that is a second pass
    device->SetRenderState(D3DRS_ZENABLE, D3DZB_TRUE);
    device->SetRenderState(D3DRS_ZFUNC, D3DCMP_LESSEQUAL);
    device->SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
    device->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
    device->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
    device->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
    device->SetRenderState(D3DRS_ALPHATESTENABLE, FALSE);
    device->SetRenderState(D3DRS_ALPHAREF, NAME_SOLID);
    device->SetRenderState(D3DRS_ALPHAFUNC, D3DCMP_GREATEREQUAL);
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
    device->SetVertexShader(NAME_FVF);
    device->SetPixelShader(0);
    // drawing from vertices in memory leaves the device with no vertex buffer: the client's is put back
    device->SetStreamSource(0, nullptr, 0);
}

void AshitaNameplate::BeginNames(const HookDraw& draw, bool fresh, float& targetWidth, float& targetHeight) {
    m_CanDraw = false;
    m_HorizontalFit = draw.HorizontalFit();

    IDirect3DDevice8* device = m_AshitaCore->GetDirect3DDevice();
    if (device == nullptr) {
        return;
    }

    // the picture the client draws the world on, which an addon sizes its letters for
    if (FAILED(device->GetViewport(&m_Viewport))) {
        return;
    }
    targetWidth = static_cast<float>(m_Viewport.Width);
    targetHeight = static_cast<float>(m_Viewport.Height);

    // Each layer owns its textures; bubbles work even without an addon drawing names.
    RetainTextures(m_Textures, fresh ? &draw : nullptr);
    if (!fresh && !m_BubblesFresh) return;

    // A point in the world goes through the view and then the projection to where it is in the picture
    D3DMATRIX view;
    D3DMATRIX projection;
    if (FAILED(device->GetTransform(D3DTS_VIEW, &view)) || FAILED(device->GetTransform(D3DTS_PROJECTION, &projection))) {
        return;
    }
    for (int row = 0; row < 4; row++) {
        for (int column = 0; column < 4; column++) {
            m_ViewProjection[row * 4 + column] = view.m[row][0] * projection.m[0][column]
                + view.m[row][1] * projection.m[1][column]
                + view.m[row][2] * projection.m[2][column]
                + view.m[row][3] * projection.m[3][column];
        }
    }

    // the device's states for drawing are not made until there is a name to draw with them
    m_Device = device;
    m_CanDraw = true;
}

// The two records of the device's state that a name is drawn between, made for the frame's first
// name and let go as the frame is presented
bool AshitaNameplate::MakeNameStates() {
    if (m_NameStates != 0 && m_SavedStates != 0) {
        return true;
    }

    if (m_NameStates == 0) {
        m_Device->BeginStateBlock();
        SetNameStates(m_Device);
        if (FAILED(m_Device->EndStateBlock(&m_NameStates))) {
            m_NameStates = 0;
        }
    }
    if (m_SavedStates == 0) {
        m_Device->BeginStateBlock();
        SetNameStates(m_Device);
        if (FAILED(m_Device->EndStateBlock(&m_SavedStates))) {
            m_SavedStates = 0;
        }
    }

    // without both, no name is drawn this frame, and they are not tried for again until the next
    m_CanDraw = m_NameStates != 0 && m_SavedStates != 0;
    return m_CanDraw;
}

static DWORD FadeColor(uint32_t color, float alpha) {
    const float solid = static_cast<float>(color >> 24) * alpha;
    const DWORD faded = (solid <= 0.0f) ? 0 : ((solid >= 255.0f) ? 255 : static_cast<DWORD>(solid + 0.5f));
    return (faded << 24) | (color & 0x00FFFFFF);
}

void AshitaNameplate::DrawCustom(uint32_t entityIndex, const HookDrawing& drawing, const HookQuad* quads, const float* position) {
    RenderCustom(entityIndex, drawing, quads, position, false);
}

void AshitaNameplate::DrawBubble(uint32_t entityIndex, const HookDrawing& drawing, const HookQuad* quads, const float* position) {
    RenderCustom(entityIndex, drawing, quads, position, true);
}

void AshitaNameplate::RenderCustom(uint32_t entityIndex, const HookDrawing& drawing, const HookQuad* quads, const float* position, bool bubble) {
    auto** textures = bubble ? m_BubbleTextures : m_Textures;
    auto* boundsCache = bubble ? m_BubbleBounds : m_NameBounds;
    const float horizontalFit = bubble ? m_BubbleFit : m_HorizontalFit;
    if (!m_CanDraw || entityIndex >= HOOK_ENTITIES || drawing.Count == 0 || drawing.Count > HOOK_QUADS_PER_NAME) {
        return;
    }

    // where the point is in the picture, and how deep
    const float* m = m_ViewProjection;
    const float x = position[0];
    const float y = position[1];
    const float z = position[2];
    const float w = x * m[3] + y * m[7] + z * m[11] + m[15];
    if (w <= 0.01f) {
        return;
    }

    const float depth = (x * m[2] + y * m[6] + z * m[10] + m[14]) / w;
    if (depth < 0.0f || depth > 1.0f) {
        return;
    }

    const float rhw = 1.0f / w;
    // on a whole pixel, so that letters drawn at their own size stay sharp
    const float left = floorf(static_cast<float>(m_Viewport.X) + (1.0f + (x * m[0] + y * m[4] + z * m[8] + m[12]) / w) * 0.5f * static_cast<float>(m_Viewport.Width)) - 0.5f;
    const float top = floorf(static_cast<float>(m_Viewport.Y) + (1.0f - (x * m[1] + y * m[5] + z * m[9] + m[13]) / w) * 0.5f * static_cast<float>(m_Viewport.Height)) - 0.5f;
    const float deep = m_Viewport.MinZ + depth * (m_Viewport.MaxZ - m_Viewport.MinZ);

    const float alpha = (drawing.Alpha <= 0.0f) ? 0.0f : ((drawing.Alpha >= 1.0f) ? 1.0f : drawing.Alpha);
    if (alpha <= 0.0f) {
        return;
    }

    const NameBounds& bounds = boundsCache[entityIndex].Get(drawing, quads, horizontalFit);
    if (!bounds.Intersects(left, top, static_cast<float>(m_Viewport.X), static_cast<float>(m_Viewport.Y),
            static_cast<float>(m_Viewport.Width), static_cast<float>(m_Viewport.Height))) {
        return; // no vertex expansion, state capture or draw submission for invisible names
    }

    uint32_t vertexCount = 0;
    uint32_t runCount = 0;
    DWORD mostSolid = 0; // of the colours of what is drawn

    auto add = [&](const HookQuad& quad, float dx, float dy, DWORD color) {
        if (quad.Texture >= HOOK_TEXTURES || textures[quad.Texture] == nullptr || vertexCount + 6 > NAME_VERTICES) {
            return;
        }

        if (runCount == 0 || Runs[runCount - 1].texture != quad.Texture) {
            Runs[runCount].texture = quad.Texture;
            Runs[runCount].first = vertexCount;
            Runs[runCount].count = 0;
            runCount++;
        }
        Runs[runCount - 1].count += 6;
        if ((color >> 24) > mostSolid) {
            mostSolid = color >> 24;
        }

        const float x0 = left + quad.X0 + dx;
        const float y0 = top + quad.Y0 + dy;
        const float x1 = left + quad.X1 + dx;
        const float y1 = top + quad.Y1 + dy;

        NameVertex* v = &Vertices[vertexCount];
        v[0] = { x0, y0, deep, rhw, color, quad.U0, quad.V0 };
        v[1] = { x1, y0, deep, rhw, color, quad.U1, quad.V0 };
        v[2] = { x0, y1, deep, rhw, color, quad.U0, quad.V1 };
        v[3] = { x1, y0, deep, rhw, color, quad.U1, quad.V0 };
        v[4] = { x1, y1, deep, rhw, color, quad.U1, quad.V1 };
        v[5] = { x0, y1, deep, rhw, color, quad.U0, quad.V1 };
        vertexCount += 6;
    };

    // the edge is the quads again in the dark, behind themselves, towards each corner
    if (drawing.Edge > 0.0f) {
        const float edge = (drawing.Edge > 8.0f) ? 8.0f : drawing.Edge;
        for (int corner = 0; corner < 4; corner++) {
            const float dx = ((corner & 1) ? edge : -edge) * horizontalFit;
            const float dy = (corner & 2) ? edge : -edge;
            for (uint32_t i = 0; i < drawing.Count; i++) {
                if ((quads[i].Flags & QUAD_EDGED) != 0) {
                    // Fade with the fill, then apply an optional weaker edge (e.g. small icons).
                    if (corner == 0) {
                        EdgeColors[i] = FadeColor(drawing.EdgeColor, alpha * (static_cast<float>(quads[i].Color >> 24) / 255.0f) * quads[i].EdgeOpacity());
                    }
                    add(quads[i], dx, dy, EdgeColors[i]);
                }
            }
        }
    }
    for (uint32_t i = 0; i < drawing.Count; i++) {
        add(quads[i], 0.0f, 0.0f, FadeColor(quads[i].Color, alpha));
    }

    if (vertexCount == 0 || !MakeNameStates()) {
        return;
    }

    IDirect3DDevice8* device = m_Device;

    device->CaptureStateBlock(m_SavedStates);
    device->ApplyStateBlock(m_NameStates);

    // most names are letters alone, from the one texture, which is then set once for both passes
    for (uint32_t i = 0; i < runCount; i++) {
        if (i == 0 || runCount > 1) {
            device->SetTexture(0, textures[Runs[i].texture]);
        }
        device->DrawPrimitiveUP(D3DPT_TRIANGLELIST, Runs[i].count / 3, &Vertices[Runs[i].first], sizeof(NameVertex));
    }

    // Again for the picture's depth alone, where the name is solid: what the client draws after it,
    // and behind it, is then not drawn over it. A name faded past half is solid nowhere, the texture
    // making it no more so, and has nothing to draw here.
    if (mostSolid >= NAME_SOLID) {
        device->SetRenderState(D3DRS_COLORWRITEENABLE, 0);
        device->SetRenderState(D3DRS_ALPHATESTENABLE, TRUE);
        device->SetRenderState(D3DRS_ZWRITEENABLE, TRUE);
        for (uint32_t i = 0; i < runCount; i++) {
            if (runCount > 1) {
                device->SetTexture(0, textures[Runs[i].texture]);
            }
            device->DrawPrimitiveUP(D3DPT_TRIANGLELIST, Runs[i].count / 3, &Vertices[Runs[i].first], sizeof(NameVertex));
        }
    }

    device->ApplyStateBlock(m_SavedStates);
}

void AshitaNameplate::PublishNames(bool frameDone) {
    // the camera is only asked after when there are names to place with it
    if (WantsPublish(frameDone)) {
        IDirect3DDevice8* device = m_AshitaCore->GetDirect3DDevice();

        D3DMATRIX view;
        D3DMATRIX projection;
        if (device != nullptr && SUCCEEDED(device->GetTransform(D3DTS_VIEW, &view)) && SUCCEEDED(device->GetTransform(D3DTS_PROJECTION, &projection))) {
            Publish(&view.m[0][0], &projection.m[0][0], frameDone);
            return;
        }
    }

    Publish(nullptr, nullptr, frameDone);
}

static void AshitaLongHelp(IChatManager* chat) {
    chat->Write(0, false, "\x1e\x05namehook v1.24, from Nameplate v0.51 by way of nameplatew v0.60");
    chat->Write(0, false, "\x1e\x05https://www.github.com/Shirk/Nameplate");
    chat->Write(0, false, "\x1e\x6aUsage (\x1e\x6a/nh\x1e\x6a is short for\x1e\x6a /namehook\x1e\x6a):");
    chat->Write(0, false, "\x1e\x6a/namehook help");
    chat->Write(0, true , "You're reading it!");
    chat->Write(0, false, "\x1e\x6a/namehook show\x1e\x01 |\x1e\x6a hide\x1e\x01 |\x1e\x6a toggle <category>...");
    chat->Write(0, true , "Show or hide the names of a category, or of several:\x1e\x6a self party alliance players mypet pets npcs monsters\x1e\x01, or\x1e\x6a all");
    chat->Write(0, false, "\x1e\x6a/namehook target on\x1e\x01 |\x1e\x6a off");
    chat->Write(0, true , "Always show your target's name, whatever its category; your own stays hidden if own names are");
    chat->Write(0, false, "\x1e\x6a/namehook status");
    chat->Write(0, true , "Say which categories are shown and hidden, and how many names were listed for addons last frame");
    chat->Write(0, false, "\x1e\x6a/namehook whitelist add\x1e\x6a <name>...");
    chat->Write(0, true , "Always show these players' nameplates, though players are hidden; saved at once to\x1e\x6a config\\namehook\\whitelist.txt");
    chat->Write(0, false, "\x1e\x6a/namehook whitelist remove\x1e\x6a <name>...");
    chat->Write(0, true , "Take these players off the whitelist");
    chat->Write(0, false, "\x1e\x6a/namehook whitelist list");
    chat->Write(0, true , "Show the names on the whitelist");
    chat->Write(0, false, "\x1e\x6a/namehook whitelist clear");
    chat->Write(0, true , "Take every name off the whitelist");
    chat->Write(0, false, "\x1e\x6a/namehook fontsize\x1e\x6a <number>");
    chat->Write(0, true , "Set the nameplate font size to <number> pixels");
    chat->Write(0, false, "\x1e\x6a/namehook damagefontsize\x1e\x6a <number>");
    chat->Write(0, true , "Set the damage font size to <number> pixels");
    chat->Write(0, false, "\x1e\x6a/namehook hidestars");
    chat->Write(0, true , "Hide all Job Mastery stars");
    chat->Write(0, false, "\x1e\x6a/namehook showstars");
    chat->Write(0, true , "Re-enable displaying Job Mastery stars");
    chat->Write(0, false, "\x1e\x6a/namehook load");
    chat->Write(0, true , "Load configuration from\x1e\x6a config\\namehook\\defaults.ini");
    chat->Write(0, false, "\x1e\x6a/namehook save");
    chat->Write(0, true , "Save current configuration to\x1e\x6a config\\namehook\\defaults.ini");
}

void AshitaNameplate::ShowMessage(MESSAGE message, int param) {
    IChatManager* chat = m_AshitaCore->GetChatManager();

    switch (message) {
        case MESSAGE::PLUGIN_LOAD_ERROR:
            chat->Writef(0, false, CHAT_HEADER "\x1e\x44Plugin load failed with error code \x1e\x05%d\x1e\x44!", param);
            if (param == -9 || param == -10 || param == -11 || param == -14 || param == -18) {
                chat->Write(0, false, CHAT_HEADER "Required client rendering code was not found. Another nameplate plugin or patch may already own it; unload nameplate/nameplatew/nameplatehook before loading namehook. An unsupported client version can also cause this error.");
            }
            break;
        case MESSAGE::PLUGIN_UNLOAD_ERROR:
            chat->Writef(0, false, CHAT_HEADER "\x1e\x44Plugin unload failed with error code \x1e\x05%d\x1e\x44!", param);
            break;
        case MESSAGE::SHORT_HELP:
            chat->Write(0, false, CHAT_HEADER "\x1e\x44Unknown command, please consult \x1e\x6a/namehook help\x1e\x44 for more information.");
            break;
        case MESSAGE::LONG_HELP:
            AshitaLongHelp(chat);
            break;
        case MESSAGE::LOAD_ERROR:
            chat->Writef(0, false, CHAT_HEADER "\x1e\x44Loading\x1e\x6a config\\namehook\\defaults.ini\x1e\x44 failed with error code \x1e\x05%d\x1e\x44!", param);
            break;
        case MESSAGE::SAVE_ERROR:
            chat->Writef(0, false, CHAT_HEADER "\x1e\x44Saving\x1e\x6a config\\namehook\\defaults.ini\x1e\x44 failed with error code \x1e\x05%d\x1e\x44!", param);
            break;
        default:
            chat->Writef(0, false, "\x1e\x44Unknown message %u (%d)", (uint32_t) message, param);
            break;
    }
}

void AshitaNameplate::CommandError(const char* command) {
    m_AshitaCore->GetChatManager()->Writef(0, false, CHAT_HEADER "\x1e\x6a/namehook %s\x1e\x44 command error, please consult \x1e\x6a/namehook help\x1e\x44 for correct usage.", command);
}

DllExport IPlugin* __stdcall expCreatePlugin([[maybe_unused]] const char* args) {
    return new AshitaNameplate();
}

DllExport void __stdcall expDestroyPlugin(void* instance) {
    delete static_cast<IPlugin*>(instance);
}

DllExport double __stdcall expGetInterfaceVersion(void) {
    return ASHITA_INTERFACE_VERSION;
}
