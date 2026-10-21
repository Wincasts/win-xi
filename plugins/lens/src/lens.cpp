// lens: the game's world laid onto the screen through a Panini or cylindrical projection. The game draws the world to
// a texture of its own and copies it onto the back buffer with one quad before the UI (lens 0.1's
// captures, 2026-10-21); lens draws a warped grid in that quad's place (warp.h) and blocks the quad, so
// the UI is drawn over it as ever. /lens capture [frames] still records every draw over a few frames.
#include "Ashita.h"
#include <intrin.h>
#include <psapi.h>
#include <memory>
#include <string>
#include <time.h>
#include "capture.h"
#include "stack.h"
#include "warp.h"

class Lens : public IPlugin {
    IAshitaCore* m_Core = nullptr;
    std::unique_ptr<lens::Capture> m_Capture;
    uint32_t m_Want = 0;        // frames to record; 0 when not recording
    bool m_Started = false;     // recording began at a Present
    uintptr_t m_Base = 0;       // FFXiMain.dll
    size_t m_Size = 0;

    bool m_On = true;           // the warp
    int m_Strength = 50;        // the Panini distance, or for cylindrical how far from flat, in hundredths
    lens::Mode m_Mode = lens::Panini;
    bool m_Drawing = false;     // our own grid is being drawn: not the game's
    std::vector<lens::Vertex> m_Vertices;
    std::vector<uint16_t> m_Indices;
    lens::Quad m_Quad = {};     // what the grid was built for
    double m_TanH = 0, m_TanV = 0;
    int m_Built = -1;           // the strength it was built for; -1 for none
    lens::Mode m_BuiltMode = lens::Panini;
    uint32_t m_Warped = 0;      // frames warped, for the status
    static const int Cols = 128, Rows = 64;

public:
    const char* GetName() const override { return "lens"; }
    const char* GetAuthor() const override { return "win"; }
    const char* GetDescription() const override { return "The world through a Panini or cylindrical projection, for wide screens without stretched edges."; }
    const char* GetLink() const override { return "https://github.com/Wincasts/win-xi"; }
    double GetVersion() const override { return 0.3; }
    uint32_t GetFlags() const override { return static_cast<uint32_t>(Ashita::PluginFlags::UseCommands | Ashita::PluginFlags::UseDirect3D); }

    bool Initialize(IAshitaCore* core, ILogManager*, uint32_t) override {
        m_Core = core;
        HMODULE game = GetModuleHandleA("FFXiMain.dll");
        MODULEINFO info = {};
        if (game && GetModuleInformation(GetCurrentProcess(), game, &info, sizeof(info))) {
            m_Base = reinterpret_cast<uintptr_t>(info.lpBaseOfDll);
            m_Size = info.SizeOfImage;
        }
        Load();
        return true;
    }
    void Release() override { m_Capture.reset(); }

    std::string SettingsPath() const { return std::string(m_Core->GetInstallPath()) + "\\config\\lens\\lens.ini"; }
    void Load() {
        FILE* f = nullptr;
        if (fopen_s(&f, SettingsPath().c_str(), "rb") != 0 || !f) return;
        char line[64];
        while (fgets(line, sizeof(line), f)) {
            int v = 0;
            if (sscanf_s(line, "on=%d", &v) == 1) m_On = v != 0;
            if (sscanf_s(line, "strength=%d", &v) == 1 && v >= 0 && v <= 100) m_Strength = v;
            if (sscanf_s(line, "mode=%d", &v) == 1 && (v == 0 || v == 1)) m_Mode = static_cast<lens::Mode>(v);
        }
        fclose(f);
    }
    void Save() const {
        CreateDirectoryA((std::string(m_Core->GetInstallPath()) + "\\config").c_str(), nullptr);
        CreateDirectoryA((std::string(m_Core->GetInstallPath()) + "\\config\\lens").c_str(), nullptr);
        FILE* f = nullptr;
        if (fopen_s(&f, SettingsPath().c_str(), "wb") != 0 || !f) return;
        fprintf(f, "on=%d\nstrength=%d\nmode=%d\n", m_On ? 1 : 0, m_Strength, static_cast<int>(m_Mode));
        fclose(f);
    }
    void Status() const {
        std::string text = m_On ? "on" : "off";
        text += std::string(", ") + (m_Mode == lens::Panini ? "panini" : "cylindrical") + ", strength " + std::to_string(m_Strength);
        if (m_TanH > 0) {
            char more[200];
            const double deg = 180.0 / 3.14159265358979323846;
            double k = m_Strength / 100.0;
            double middle = lens::MiddleHeight(m_TanH, m_TanV, m_Mode, k), across = lens::ShownAcross(m_TanH, m_TanV, m_Mode, k);
            snprintf(more, sizeof(more), "; the world is drawn %.0f across and %.0f up, and the screen shows %.0f across and %.0f up the middle (%.0f%% of the height)",
                2 * atan(m_TanH) * deg, 2 * atan(m_TanV) * deg, 2 * atan(across) * deg, 2 * atan(m_TanV * middle) * deg, middle * 100);
            text += more;
        }
        text += m_On && !m_Warped ? "; the game's copy of the world to the screen has not been seen yet." : ".";
        Say(text);
    }
    bool Direct3DInitialize(IDirect3DDevice8*) override { return true; }

    void Say(const std::string& text) const { m_Core->GetChatManager()->Write(0, false, ("[lens] " + text).c_str()); }

    bool HandleCommand(int32_t, const char* command, bool) override {
        char words[3][16] = {};
        if (!command || sscanf_s(command, "%15s %15s %15s", words[0], 16u, words[1], 16u, words[2], 16u) < 1 || _stricmp(words[0], "/lens") != 0) return false;
        if (!words[1][0]) { Status(); return true; }
        if (_stricmp(words[1], "on") == 0 || _stricmp(words[1], "off") == 0) {
            m_On = _stricmp(words[1], "on") == 0;
            Save();
            Status();
            return true;
        }
        if (_stricmp(words[1], "mode") == 0) {
            if (_stricmp(words[2], "panini") == 0) m_Mode = lens::Panini;
            else if (_stricmp(words[2], "cylindrical") == 0) m_Mode = lens::Cylindrical;
            else { Say("Usage: /lens mode panini|cylindrical."); return true; }
            Save();
            Status();
            return true;
        }
        if (_stricmp(words[1], "strength") == 0) {
            char* end = nullptr;
            long v = strtol(words[2], &end, 10);
            if (!words[2][0] || *end || v < 0 || v > 100) { Say("Usage: /lens strength <n>, 0 (flat, as the game) to 100 (the classic Panini, or fully cylindrical)."); return true; }
            m_Strength = static_cast<int>(v);
            Save();
            Status();
            return true;
        }
        if (_stricmp(words[1], "capture") == 0) {
            int frames = words[2][0] ? atoi(words[2]) : 2;
            if (frames < 1 || frames > 10) { Say("Usage: /lens capture [frames], 1 to 10 (2 to start)."); return true; }
            if (m_Want) { Say("Already recording."); return true; }
            m_Capture = std::make_unique<lens::Capture>();
            m_Want = static_cast<uint32_t>(frames);
            m_Started = false;
            Say("Recording the next " + std::to_string(frames) + " frame(s)" + (m_Base ? "." : "; FFXiMain.dll was not found, so the game's callers will be missing."));
            return true;
        }
        Say("/lens - what the warp is doing. /lens on|off - the warp. /lens mode panini|cylindrical. /lens strength <n> - 0 (flat, as the game) to 100 (the classic Panini, or fully cylindrical), 50 to start.");
        Say("A stronger warp shows less up and down in the middle; drawscale's fov above the game's 77 puts it back. /lens capture [frames] - records every draw over the next frames to config/lens/.");
        return true;
    }

    void Direct3DBeginScene(bool back) override { if (m_Want && m_Started) m_Capture->Mark(lens::Capture::Event::BeginScene, back); }
    void Direct3DEndScene(bool back) override { if (m_Want && m_Started) m_Capture->Mark(lens::Capture::Event::EndScene, back); }
    void Direct3DPresent(const RECT*, const RECT*, HWND, const RGNDATA*) override {
        if (!m_Want) return;
        if (!m_Started) { m_Started = true; return; }
        m_Capture->Mark(lens::Capture::Event::Present, true);
        if (m_Capture->frames >= m_Want) Finish();
    }

    bool Direct3DDrawPrimitive(D3DPRIMITIVETYPE t, UINT, UINT count) override { Record(lens::DP, t, count); return false; }
    bool Direct3DDrawIndexedPrimitive(D3DPRIMITIVETYPE t, UINT, UINT, UINT, UINT count) override { Record(lens::DIP, t, count); return false; }
    bool Direct3DDrawPrimitiveUP(D3DPRIMITIVETYPE t, UINT count, const void* data, UINT stride) override {
        if (m_Drawing) return false;
        Record(lens::DPUP, t, count);
        return m_On && Warp(t, count, data, stride);
    }
    bool Direct3DDrawIndexedPrimitiveUP(D3DPRIMITIVETYPE t, UINT, UINT, UINT count, const void*, D3DFORMAT, const void*, UINT) override {
        if (!m_Drawing) Record(lens::DIPUP, t, count);
        return false;
    }

private:
    // The game's copy of its world to the screen: a strip of two triangles of screen-space vertices
    // (FVF 0x144) onto the back buffer, nearly all of it, from a render-target texture. Drawn as a
    // warped grid with the same state, and the quad blocked; true when so.
    bool Warp(D3DPRIMITIVETYPE type, UINT count, const void* data, UINT stride) {
        if (type != D3DPT_TRIANGLESTRIP || count != 2 || stride != sizeof(lens::Vertex) || !data) return false;
        auto* device = m_Core->GetDirect3DDevice();
        if (!device) return false;
        DWORD shader = 0;
        if (FAILED(device->GetVertexShader(&shader)) || shader != 0x144) return false;
        IDirect3DBaseTexture8* base = nullptr;
        bool renderTarget = false;
        if (SUCCEEDED(device->GetTexture(0, &base)) && base) {
            D3DSURFACE_DESC desc;
            if (base->GetType() == D3DRTYPE_TEXTURE && SUCCEEDED(static_cast<IDirect3DTexture8*>(base)->GetLevelDesc(0, &desc)))
                renderTarget = (desc.Usage & D3DUSAGE_RENDERTARGET) != 0;
            base->Release();
        }
        if (!renderTarget) return false;
        IDirect3DSurface8 *target = nullptr, *back = nullptr;
        D3DSURFACE_DESC backDesc = {};
        bool onBack = SUCCEEDED(device->GetRenderTarget(&target)) && SUCCEEDED(device->GetBackBuffer(0, D3DBACKBUFFER_TYPE_MONO, &back))
            && target == back && SUCCEEDED(back->GetDesc(&backDesc));
        if (target) target->Release();
        if (back) back->Release();
        if (!onBack) return false;
        lens::Quad q = lens::QuadOf(static_cast<const lens::Vertex*>(data));
        if (q.right - q.left < backDesc.Width * 0.9f || q.bottom - q.top < backDesc.Height * 0.9f) return false;
        D3DMATRIX p;
        if (FAILED(device->GetTransform(D3DTS_PROJECTION, &p)) || p._11 <= 0 || p._22 <= 0) return false;
        double tanH = 1.0 / p._11, tanV = 1.0 / p._22;
        if (m_Built != m_Strength || m_BuiltMode != m_Mode || memcmp(&q, &m_Quad, sizeof(q)) != 0 || tanH != m_TanH || tanV != m_TanV) {
            lens::Build(q, tanH, tanV, m_Mode, m_Strength / 100.0, Cols, Rows, m_Vertices, m_Indices);
            m_Quad = q; m_TanH = tanH; m_TanV = tanV; m_Built = m_Strength; m_BuiltMode = m_Mode;
        }
        // sampled smoothly, as the warp reads between the picture's pixels; the game's filters put back
        DWORD mag = 0, min = 0;
        device->GetTextureStageState(0, D3DTSS_MAGFILTER, &mag);
        device->GetTextureStageState(0, D3DTSS_MINFILTER, &min);
        device->SetTextureStageState(0, D3DTSS_MAGFILTER, D3DTEXF_LINEAR);
        device->SetTextureStageState(0, D3DTSS_MINFILTER, D3DTEXF_LINEAR);
        m_Drawing = true;
        HRESULT hr = device->DrawIndexedPrimitiveUP(D3DPT_TRIANGLELIST, 0, static_cast<UINT>(m_Vertices.size()), static_cast<UINT>(m_Indices.size() / 3),
            m_Indices.data(), D3DFMT_INDEX16, m_Vertices.data(), sizeof(lens::Vertex));
        m_Drawing = false;
        device->SetTextureStageState(0, D3DTSS_MAGFILTER, mag);
        device->SetTextureStageState(0, D3DTSS_MINFILTER, min);
        if (FAILED(hr)) return false;
        ++m_Warped;
        return true;
    }

    void Callers(uint32_t* out) const {
        if (!m_Base) return;
        uint32_t here = 0;
        auto* stack = &here;
        auto top = static_cast<uintptr_t>(__readfsdword(4)); // the thread's stack base, from its TIB
        size_t dwords = top > reinterpret_cast<uintptr_t>(stack) ? (top - reinterpret_cast<uintptr_t>(stack)) / 4 : 0;
        if (dwords > 8192) dwords = 8192;
        __try {
            lens::ReturnAddresses(stack, dwords, m_Base, reinterpret_cast<const uint8_t*>(m_Base), m_Size, out, 2);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            out[0] = out[1] = 0;
        }
    }

    void Record(uint8_t kind, D3DPRIMITIVETYPE type, UINT count) {
        if (!m_Want || !m_Started) return;
        auto* device = m_Core->GetDirect3DDevice();
        if (!device) return;
        lens::Draw d;
        d.kind = kind;
        d.prim = static_cast<uint32_t>(type);
        d.count = count;
        DWORD shader = 0;
        device->GetVertexShader(&shader);
        d.shader = shader;
        IDirect3DSurface8 *target = nullptr, *back = nullptr;
        if (SUCCEEDED(device->GetRenderTarget(&target)) && target) {
            D3DSURFACE_DESC desc;
            if (SUCCEEDED(target->GetDesc(&desc))) { d.targetW = desc.Width; d.targetH = desc.Height; }
            d.target = reinterpret_cast<uintptr_t>(target);
        }
        if (SUCCEEDED(device->GetBackBuffer(0, D3DBACKBUFFER_TYPE_MONO, &back)) && back) d.targetBack = back == target;
        if (target) target->Release();
        if (back) back->Release();
        D3DVIEWPORT8 vp = {};
        if (SUCCEEDED(device->GetViewport(&vp))) { d.vpX = vp.X; d.vpY = vp.Y; d.vpW = vp.Width; d.vpH = vp.Height; d.vpMinZ = vp.MinZ; d.vpMaxZ = vp.MaxZ; }
        DWORD v = 0;
        device->GetRenderState(D3DRS_ZENABLE, &v); d.zEnable = v;
        device->GetRenderState(D3DRS_ZWRITEENABLE, &v); d.zWrite = v;
        device->GetRenderState(D3DRS_ALPHABLENDENABLE, &v); d.blend = v;
        device->GetRenderState(D3DRS_FOGENABLE, &v); d.fog = v;
        device->GetRenderState(D3DRS_LIGHTING, &v); d.lighting = v;
        D3DMATRIX m;
        if (SUCCEEDED(device->GetTransform(D3DTS_PROJECTION, &m))) memcpy(d.proj.m, &m, sizeof(d.proj.m));
        if (SUCCEEDED(device->GetTransform(D3DTS_VIEW, &m))) memcpy(d.view.m, &m, sizeof(d.view.m));
        IDirect3DBaseTexture8* base = nullptr;
        if (SUCCEEDED(device->GetTexture(0, &base)) && base) {
            d.texture = reinterpret_cast<uintptr_t>(base);
            if (base->GetType() == D3DRTYPE_TEXTURE) {
                D3DSURFACE_DESC desc;
                if (SUCCEEDED(static_cast<IDirect3DTexture8*>(base)->GetLevelDesc(0, &desc))) { d.texW = desc.Width; d.texH = desc.Height; }
            }
            base->Release();
        }
        Callers(d.caller);
        m_Capture->Add(d);
    }

    void Finish() {
        m_Want = 0;
        std::string dir = std::string(m_Core->GetInstallPath()) + "\\config\\lens\\";
        CreateDirectoryA((std::string(m_Core->GetInstallPath()) + "\\config").c_str(), nullptr);
        CreateDirectoryA(dir.c_str(), nullptr);
        char name[64];
        time_t now = time(nullptr);
        tm local;
        localtime_s(&local, &now);
        strftime(name, sizeof(name), "capture-%Y%m%d-%H%M%S.txt", &local);
        char header[160];
        snprintf(header, sizeof(header), "lens %.2f, %s, FFXiMain.dll at %08X (%u bytes)\n", GetVersion(), name, static_cast<unsigned>(m_Base), static_cast<unsigned>(m_Size));
        std::string report = m_Capture->Report(header);
        FILE* f = nullptr;
        if (fopen_s(&f, (dir + name).c_str(), "wb") == 0 && f) {
            fwrite(report.data(), 1, report.size(), f);
            fclose(f);
            Say(std::to_string(m_Capture->draws.size()) + " draws over " + std::to_string(m_Capture->frames) + " frames, written to config/lens/" + name + ".");
        } else {
            Say("Could not write config/lens/" + std::string(name) + ".");
        }
        m_Capture.reset();
    }
};

extern "C" {
__declspec(dllexport) IPlugin* __stdcall expCreatePlugin(const char*) { return new Lens(); }
__declspec(dllexport) void __stdcall expDestroyPlugin(void* instance) { delete static_cast<IPlugin*>(instance); }
__declspec(dllexport) double __stdcall expGetInterfaceVersion() { return ASHITA_INTERFACE_VERSION; }
}
