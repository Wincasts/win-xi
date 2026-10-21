// lens: for now a diagnostic. /lens capture [frames] records every draw the game makes over a few
// frames, with the state it is drawn in and the game's code that made it, to config\lens\, so the place
// where the 3D world ends and the UI begins can be found before the world is drawn anywhere else.
#include "Ashita.h"
#include <intrin.h>
#include <psapi.h>
#include <memory>
#include <string>
#include <time.h>
#include "capture.h"
#include "stack.h"

class Lens : public IPlugin {
    IAshitaCore* m_Core = nullptr;
    std::unique_ptr<lens::Capture> m_Capture;
    uint32_t m_Want = 0;        // frames to record; 0 when not recording
    bool m_Started = false;     // recording began at a Present
    uintptr_t m_Base = 0;       // FFXiMain.dll
    size_t m_Size = 0;

public:
    const char* GetName() const override { return "lens"; }
    const char* GetAuthor() const override { return "win"; }
    const char* GetDescription() const override { return "Records what the game draws over a few frames, for finding where its 3D world ends and its UI begins."; }
    const char* GetLink() const override { return "https://github.com/Wincasts/win-xi"; }
    double GetVersion() const override { return 0.1; }
    uint32_t GetFlags() const override { return static_cast<uint32_t>(Ashita::PluginFlags::UseCommands | Ashita::PluginFlags::UseDirect3D); }

    bool Initialize(IAshitaCore* core, ILogManager*, uint32_t) override {
        m_Core = core;
        HMODULE game = GetModuleHandleA("FFXiMain.dll");
        MODULEINFO info = {};
        if (game && GetModuleInformation(GetCurrentProcess(), game, &info, sizeof(info))) {
            m_Base = reinterpret_cast<uintptr_t>(info.lpBaseOfDll);
            m_Size = info.SizeOfImage;
        }
        return true;
    }
    void Release() override { m_Capture.reset(); }
    bool Direct3DInitialize(IDirect3DDevice8*) override { return true; }

    void Say(const std::string& text) const { m_Core->GetChatManager()->Write(0, false, ("[lens] " + text).c_str()); }

    bool HandleCommand(int32_t, const char* command, bool) override {
        char words[3][16] = {};
        if (!command || sscanf_s(command, "%15s %15s %15s", words[0], 16u, words[1], 16u, words[2], 16u) < 1 || _stricmp(words[0], "/lens") != 0) return false;
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
        Say("/lens capture [frames] - records every draw over the next frames (2 to start) to config/lens/.");
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
    bool Direct3DDrawPrimitiveUP(D3DPRIMITIVETYPE t, UINT count, const void*, UINT) override { Record(lens::DPUP, t, count); return false; }
    bool Direct3DDrawIndexedPrimitiveUP(D3DPRIMITIVETYPE t, UINT, UINT, UINT count, const void*, D3DFORMAT, const void*, UINT) override { Record(lens::DIPUP, t, count); return false; }

private:
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
