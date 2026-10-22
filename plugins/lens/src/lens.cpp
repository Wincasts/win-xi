// lens: the game's world laid onto the screen through a Panini or cylindrical projection. The game draws the world to
// a texture of its own and copies it onto the back buffer with one quad before the UI (lens 0.1's
// captures, 2026-10-21); lens draws a warped grid in that quad's place (warp.h) and blocks the quad, so
// the UI is drawn over it as ever. The grid averages four taps over each pixel's patch of the world
// (warp.h Taps, shaders.h), for edges smoother than the game's own copy gives, with or without the
// warp. /lens capture [frames] still records every draw over a few frames.
#include "Ashita.h"
#include <intrin.h>
#include <psapi.h>
#include <memory>
#include <string>
#include <time.h>
#include "capture.h"
#include "stack.h"
#include "warp.h"
#include "shared.h"
#include "mousescan.h"
#include "shaders.h"

// Exported, so that the compiler keeps it although nothing here reads it, and so that another plugin
// (namehook) can find it by name
extern "C" __declspec(dllexport) lens::Shared LensWarp = { "LENS-WARP", 1, sizeof(lens::Shared), 0, 0, 0, 0, 0, 0 };
static lens::Shared& Shared = LensWarp;

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
    bool m_Aa = true;           // four taps a pixel
    bool m_Drawing = false;     // our own grid is being drawn: not the game's
    std::vector<lens::Tapped> m_Vertices;
    std::vector<uint16_t> m_Indices;
    lens::Quad m_Quad = {};     // what the grid was built for
    double m_TanH = 0, m_TanV = 0;
    int m_Built = -1;           // the strength it was built for (0 with the warp off); -1 for none
    lens::Mode m_BuiltMode = lens::Panini;
    uint32_t m_Warped = 0;      // frames warped, for the status
    UINT m_BackW = 0, m_BackH = 0;  // the back buffer's size at the last warp
    UINT m_SourceW = 0, m_SourceH = 0;  // the world's texture's, for the status
    uint32_t m_CopyFrame = 0;   // the Frame the game's copy was last taken over in
    DWORD m_GameFilter = 0;     // the game's own minifying filter at the copy
    enum class Taps { Off, Averaged, NoShader, UnknownCopy } m_Taps = Taps::Off;   // how the last copy was read
    // the pixel shaders averaging the taps, made once for the device; 0 where it cannot have them
    IDirect3DDevice8* m_ShaderDevice = nullptr;
    DWORD m_Average = 0, m_AverageModulate = 0;
    bool m_ShadersTried = false;
    // the grid, kept on the card and written only when it is built, rather than sent with every frame
    IDirect3DDevice8* m_BufferDevice = nullptr;
    IDirect3DVertexBuffer8* m_VertexBuffer = nullptr;
    IDirect3DIndexBuffer8* m_IndexBuffer = nullptr;
    bool m_Written = false;     // the buffers hold the grid as built
    static const int Cols = 128, Rows = 64;

    std::vector<lens::Candidate> m_Mouse;   // where the cursor's place may be kept, from /lens mouse
    uint32_t m_MouseLooks = 0;

public:
    const char* GetName() const override { return "lens"; }
    const char* GetAuthor() const override { return "win"; }
    const char* GetDescription() const override { return "The world through a Panini or cylindrical projection, for wide screens without stretched edges."; }
    const char* GetLink() const override { return "https://github.com/Wincasts/win-xi"; }
    double GetVersion() const override { return 0.7; }
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
    void Release() override {
        m_Capture.reset();
        ReleaseBuffers();
        ReleaseShaders();
        Shared.WarpedFrame = 0;
    }

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
            if (sscanf_s(line, "aa=%d", &v) == 1) m_Aa = v != 0;
        }
        fclose(f);
    }
    void Save() const {
        CreateDirectoryA((std::string(m_Core->GetInstallPath()) + "\\config").c_str(), nullptr);
        CreateDirectoryA((std::string(m_Core->GetInstallPath()) + "\\config\\lens").c_str(), nullptr);
        FILE* f = nullptr;
        if (fopen_s(&f, SettingsPath().c_str(), "wb") != 0 || !f) return;
        fprintf(f, "on=%d\nstrength=%d\nmode=%d\naa=%d\n", m_On ? 1 : 0, m_Strength, static_cast<int>(m_Mode), m_Aa ? 1 : 0);
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
        text += m_On || m_Aa ? (m_Warped ? "." : "; the game's copy of the world to the screen has not been seen yet.") : ".";
        Say(text);
        Say(Smoothing());
    }
    std::string Smoothing() const {
        std::string text = std::string("aa ") + (m_Aa ? "on" : "off");
        if (m_Aa && m_Warped) {
            if (m_Taps == Taps::Averaged) text += ": each pixel is the average of four reads over the patch of the world it covers";
            else if (m_Taps == Taps::NoShader) text += ", but this device has no pixel shader 1.1 and four textures: one smooth read a pixel";
            else if (m_Taps == Taps::UnknownCopy) text += ", but the game's copy is drawn in a way lens does not know: one smooth read a pixel";
        }
        if (m_SourceW && m_BackW) {
            char more[200];
            snprintf(more, sizeof(more), "; the world is drawn at %ux%u, %.2f by %.2f the screen", m_SourceW, m_SourceH, double(m_SourceW) / m_BackW, double(m_SourceH) / m_BackH);
            text += more;
            text += std::string("; the game's own copy reads ") + (m_GameFilter == D3DTEXF_POINT ? "the nearest texel" : m_GameFilter == D3DTEXF_LINEAR ? "smoothly" : "with another filter");
        }
        return text + ".";
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
        if (_stricmp(words[1], "aa") == 0) {
            if (_stricmp(words[2], "on") == 0) m_Aa = true;
            else if (_stricmp(words[2], "off") == 0) m_Aa = false;
            else { Say("Usage: /lens aa on|off."); return true; }
            Save();
            Say(Smoothing());
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
        if (_stricmp(words[1], "mouse") == 0) {
            if (_stricmp(words[2], "reset") == 0) { m_Mouse.clear(); m_MouseLooks = 0; Say("Forgot the mouse's places; /lens mouse looks afresh."); return true; }
            MouseScan();
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
        Say("/lens aa on|off - each pixel the average of four reads over the patch of the world it covers, with the warp or without (on to start).");
        Say("A stronger warp shows less up and down in the middle; drawscale's fov above the game's 77 puts it back. /lens capture [frames] - records every draw over the next frames to config/lens/.");
        return true;
    }

    void Direct3DBeginScene(bool back) override { if (m_Want && m_Started) m_Capture->Mark(lens::Capture::Event::BeginScene, back); }
    void Direct3DEndScene(bool back) override { if (m_Want && m_Started) m_Capture->Mark(lens::Capture::Event::EndScene, back); }
    void Direct3DPresent(const RECT*, const RECT*, HWND, const RGNDATA*) override {
        ++Shared.Frame;
        if (!m_Want) return;
        if (!m_Started) { m_Started = true; return; }
        m_Capture->Mark(lens::Capture::Event::Present, true);
        if (m_Capture->frames >= m_Want) Finish();
    }

    bool Direct3DDrawPrimitive(D3DPRIMITIVETYPE t, UINT, UINT count) override { if (!m_Drawing) Record(lens::DP, t, count); return false; }
    bool Direct3DDrawIndexedPrimitive(D3DPRIMITIVETYPE t, UINT, UINT, UINT, UINT count) override { if (!m_Drawing) Record(lens::DIP, t, count); return false; }
    bool Direct3DDrawPrimitiveUP(D3DPRIMITIVETYPE t, UINT count, const void* data, UINT stride) override {
        if (m_Drawing) return false;
        Record(lens::DPUP, t, count);
        return (m_On || m_Aa) && Warp(t, count, data, stride);
    }
    bool Direct3DDrawIndexedPrimitiveUP(D3DPRIMITIVETYPE t, UINT, UINT, UINT count, const void*, D3DFORMAT, const void*, UINT) override {
        if (!m_Drawing) Record(lens::DIPUP, t, count);
        return false;
    }

private:
    static bool SafeRead(uintptr_t address, void* buffer, size_t size) {
        __try { memcpy(buffer, reinterpret_cast<const void*>(address), size); return true; }
        __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    }
    static bool SafeScan(const MEMORY_BASIC_INFORMATION& m, int x, int y, int w, int h, std::vector<lens::Candidate>& out, size_t cap) {
        __try {
            lens::FindPairs(static_cast<const uint8_t*>(m.BaseAddress), m.RegionSize, m.RegionSize, reinterpret_cast<uintptr_t>(m.BaseAddress), x, y, w, h, out, cap);
            return true;
        } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    }
    static bool SafeDwords(uintptr_t base, size_t size, uint32_t low, uint32_t high, std::vector<uintptr_t>& out, size_t cap) {
        __try { lens::FindDwords(reinterpret_cast<const uint8_t*>(base), size, base, low, high, out, cap); return true; }
        __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    }
    std::string Bytes(uintptr_t at, size_t n) const {
        std::vector<uint8_t> b(n);
        if (!SafeRead(at, b.data(), n)) return "(unreadable)";
        std::string out;
        char hex[4];
        for (uint8_t v : b) { snprintf(hex, sizeof(hex), "%02X ", v); out += hex; }
        return out;
    }
    std::string Where(uintptr_t address) const {
        char text[96];
        if (m_Base && address >= m_Base && address < m_Base + m_Size) { snprintf(text, sizeof(text), "FFXiMain+%06X", static_cast<unsigned>(address - m_Base)); return text; }
        HMODULE module = nullptr;
        if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, reinterpret_cast<LPCSTR>(address), &module) && module) {
            char name[MAX_PATH] = {};
            GetModuleFileNameA(module, name, MAX_PATH);
            const char* base = strrchr(name, '\\');
            snprintf(text, sizeof(text), "%s+%X", base ? base + 1 : name, static_cast<unsigned>(address - reinterpret_cast<uintptr_t>(module)));
            return text;
        }
        return "heap";
    }

    // /lens mouse: where the cursor's place in the game's window is kept. The first look finds every
    // place in writable memory holding it; each later one, with the cursor elsewhere, keeps those that
    // moved with it. Once few are left, the client's code reading them (or the globals pointing at the
    // objects they are in) is listed with the bytes around it, all in config/lens/mouse-<time>.txt.
    void MouseScan() {
        HWND window = m_Core->GetProperties()->GetFinalFantasyHwnd();
        POINT p = {};
        RECT client = {};
        if (!window || !GetCursorPos(&p) || !ScreenToClient(window, &p) || !GetClientRect(window, &client)) { Say("The game's window or the cursor was not found."); return; }
        const int w = client.right - client.left, h = client.bottom - client.top;
        if (p.x < 8 || p.y < 8 || p.x >= w - 8 || p.y >= h - 8) { Say("Put the cursor over the game, away from its edges, and use /lens mouse again."); return; }
        if (p.x == p.y) { Say("The cursor is as far across as down; move it a little and try again."); return; }
        const int x = p.x, y = p.y;
        if (m_Mouse.empty()) {
            // this thread's own stack holds the point just read: not the game's
            NT_TIB* tib = reinterpret_cast<NT_TIB*>(NtCurrentTeb());
            uintptr_t stackLow = reinterpret_cast<uintptr_t>(tib->StackLimit), stackHigh = reinterpret_cast<uintptr_t>(tib->StackBase);
            MEMORY_BASIC_INFORMATION m;
            for (uintptr_t at = 0x10000; at < 0x7FFF0000 && VirtualQuery(reinterpret_cast<LPCVOID>(at), &m, sizeof(m)) == sizeof(m); at = reinterpret_cast<uintptr_t>(m.BaseAddress) + m.RegionSize) {
                const DWORD writable = PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
                uintptr_t region = reinterpret_cast<uintptr_t>(m.BaseAddress);
                if (m.State != MEM_COMMIT || !(m.Protect & writable) || (m.Protect & (PAGE_GUARD | PAGE_NOACCESS))) continue;
                if (region + m.RegionSize > stackLow && region < stackHigh) continue;
                SafeScan(m, x, y, w, h, m_Mouse, 500000);
                if (m_Mouse.size() >= 500000) break;
            }
        } else {
            lens::KeepPairs(m_Mouse, [](uintptr_t a, void* b, size_t n) { return SafeRead(a, b, n); }, x, y, w, h);
        }
        ++m_MouseLooks;

        std::string report;
        char line[256];
        snprintf(line, sizeof(line), "lens %.2f, look %u, cursor %d,%d in a %dx%d window, FFXiMain.dll at %08X: %u places\n",
            GetVersion(), m_MouseLooks, x, y, w, h, static_cast<unsigned>(m_Base), static_cast<unsigned>(m_Mouse.size()));
        report += line;
        if (m_Mouse.size() <= 200) {
            for (const lens::Candidate& c : m_Mouse) {
                snprintf(line, sizeof(line), "  %08X %s %s\n", static_cast<unsigned>(c.address), lens::PairKindNames[c.kind], Where(c.address).c_str());
                report += line;
            }
        }
        if (m_Mouse.size() <= 32 && m_Base) {
            report += "\nthe client's references:\n";
            for (const lens::Candidate& c : m_Mouse) {
                const bool global = c.address >= m_Base && c.address < m_Base + m_Size;
                std::vector<uintptr_t> refs;
                // a global is read by its address, or a field's, up to 0x40 in; an object's field through
                // a global pointing at the object, up to 0x1000 before the field
                SafeDwords(m_Base, m_Size, static_cast<uint32_t>(c.address - (global ? 0x40 : 0x1000)), static_cast<uint32_t>(c.address), refs, 64);
                snprintf(line, sizeof(line), "%08X (%s, %s): %u dwords in the client point at or before it\n", static_cast<unsigned>(c.address),
                    lens::PairKindNames[c.kind], global ? "a global" : "not in the client", static_cast<unsigned>(refs.size()));
                report += line;
                for (uintptr_t r : refs) {
                    uint32_t v = 0;
                    SafeRead(r, &v, 4);
                    snprintf(line, sizeof(line), "  at %s holds %08X (%+d from it)\n    -48: %s\n    +4:  %s\n", Where(r).c_str(), v,
                        static_cast<int>(static_cast<int64_t>(v) - static_cast<int64_t>(c.address)), Bytes(r - 48, 48).c_str(), Bytes(r + 4, 48).c_str());
                    report += line;
                    if (!global) {
                        // the code reading that pointer: its address as an operand
                        std::vector<uintptr_t> code;
                        SafeDwords(m_Base, m_Size, static_cast<uint32_t>(r), static_cast<uint32_t>(r), code, 16);
                        for (uintptr_t k : code) {
                            snprintf(line, sizeof(line), "    read at %s\n      -48: %s\n      +4:  %s\n", Where(k).c_str(), Bytes(k - 48, 48).c_str(), Bytes(k + 4, 48).c_str());
                            report += line;
                        }
                    }
                }
            }
        }
        std::string dir = std::string(m_Core->GetInstallPath()) + "\\config\\lens\\";
        CreateDirectoryA((std::string(m_Core->GetInstallPath()) + "\\config").c_str(), nullptr);
        CreateDirectoryA(dir.c_str(), nullptr);
        char name[64];
        time_t now = time(nullptr);
        tm local;
        localtime_s(&local, &now);
        strftime(name, sizeof(name), "mouse-%Y%m%d-%H%M%S.txt", &local);
        FILE* f = nullptr;
        if (fopen_s(&f, (dir + name).c_str(), "wb") == 0 && f) { fwrite(report.data(), 1, report.size(), f); fclose(f); }
        if (m_Mouse.empty()) Say("No place holds the cursor's place now; /lens mouse reset and look again.");
        else if (m_Mouse.size() > 32) Say(std::to_string(m_Mouse.size()) + " places hold the cursor's place. Move the cursor somewhere else over the game and /lens mouse again.");
        else Say(std::to_string(m_Mouse.size()) + " places left; their code is in config/lens/" + name + ". Once more elsewhere to be sure, or send that.");
    }

    // The game's copy of its world to the screen: a strip of two triangles of screen-space vertices
    // (FVF 0x144) onto the back buffer, nearly all of it, from a render-target texture. Drawn as a
    // grid with the same state, warped while the warp is on (flat while only aa is), and the quad
    // blocked; true when so.
    bool Warp(D3DPRIMITIVETYPE type, UINT count, const void* data, UINT stride) {
        if (type != D3DPT_TRIANGLESTRIP || count != 2 || stride != sizeof(lens::Vertex) || !data) return false;
        // the game's UI draws some 700 such quads a frame: while the copy is being taken over, the back
        // buffer's size from its last frame tells them apart without asking the device anything
        lens::Quad q = lens::QuadOf(static_cast<const lens::Vertex*>(data));
        if (m_BackW && Shared.Frame - m_CopyFrame <= 2 && (q.right - q.left < m_BackW * 0.9f || q.bottom - q.top < m_BackH * 0.9f)) return false;
        auto* device = m_Core->GetDirect3DDevice();
        if (!device) return false;
        DWORD shader = 0;
        if (FAILED(device->GetVertexShader(&shader)) || shader != 0x144) return false;
        IDirect3DBaseTexture8* base = nullptr;
        D3DSURFACE_DESC source = {};
        bool renderTarget = false;
        if (SUCCEEDED(device->GetTexture(0, &base)) && base) {
            if (base->GetType() == D3DRTYPE_TEXTURE && SUCCEEDED(static_cast<IDirect3DTexture8*>(base)->GetLevelDesc(0, &source)))
                renderTarget = (source.Usage & D3DUSAGE_RENDERTARGET) != 0;
            base->Release();   // the device keeps it bound through the draw
        }
        if (!renderTarget) return false;
        IDirect3DSurface8 *target = nullptr, *back = nullptr;
        D3DSURFACE_DESC backDesc = {};
        bool onBack = SUCCEEDED(device->GetRenderTarget(&target)) && SUCCEEDED(device->GetBackBuffer(0, D3DBACKBUFFER_TYPE_MONO, &back))
            && target == back && SUCCEEDED(back->GetDesc(&backDesc));
        if (target) target->Release();
        if (back) back->Release();
        if (!onBack) return false;
        if (q.right - q.left < backDesc.Width * 0.9f || q.bottom - q.top < backDesc.Height * 0.9f) return false;
        D3DMATRIX p;
        if (FAILED(device->GetTransform(D3DTS_PROJECTION, &p)) || p._11 <= 0 || p._22 <= 0) return false;
        double tanH = 1.0 / p._11, tanV = 1.0 / p._22;
        const int strength = m_On ? m_Strength : 0;
        if (m_Built != strength || m_BuiltMode != m_Mode || memcmp(&q, &m_Quad, sizeof(q)) != 0 || tanH != m_TanH || tanV != m_TanV) {
            lens::Taps(q, tanH, tanV, m_Mode, strength / 100.0, Cols, Rows, 0.25, m_Vertices);
            lens::Indices(Cols, Rows, m_Indices);
            m_Quad = q; m_TanH = tanH; m_TanV = tanV; m_Built = strength; m_BuiltMode = m_Mode;
            m_Written = false;
        }

        // four taps when there is a shader for the way the game colours its copy: the texture alone,
        // or the texture times the vertices' colour (the plain shader when that colour is white)
        DWORD ps = 0;
        m_Taps = Taps::Off;
        if (m_Aa) {
            DWORD op = 0, arg1 = 0, arg2 = 0;
            device->GetTextureStageState(0, D3DTSS_COLOROP, &op);
            device->GetTextureStageState(0, D3DTSS_COLORARG1, &arg1);
            device->GetTextureStageState(0, D3DTSS_COLORARG2, &arg2);
            // stage 0's current colour is the diffuse
            auto is = [](DWORD arg, DWORD what) { return arg == what || (what == D3DTA_DIFFUSE && arg == D3DTA_CURRENT); };
            bool alone = (op == D3DTOP_SELECTARG1 && is(arg1, D3DTA_TEXTURE)) || (op == D3DTOP_SELECTARG2 && is(arg2, D3DTA_TEXTURE));
            bool modulated = op == D3DTOP_MODULATE && ((is(arg1, D3DTA_TEXTURE) && is(arg2, D3DTA_DIFFUSE)) || (is(arg1, D3DTA_DIFFUSE) && is(arg2, D3DTA_TEXTURE)));
            if (!Shaders(device)) m_Taps = Taps::NoShader;
            else if (alone || (modulated && q.color == 0xFFFFFFFF)) ps = m_Average;
            else if (modulated && m_AverageModulate) ps = m_AverageModulate;
            else m_Taps = Taps::UnknownCopy;
            if (ps) m_Taps = Taps::Averaged;
        }

        // sampled smoothly, as the grid reads between the picture's pixels; the game's state put back
        DWORD mag = 0, min = 0, index = 0, oldPs = 0;
        device->GetTextureStageState(0, D3DTSS_MAGFILTER, &mag);
        device->GetTextureStageState(0, D3DTSS_MINFILTER, &min);
        device->GetTextureStageState(0, D3DTSS_TEXCOORDINDEX, &index);
        device->SetTextureStageState(0, D3DTSS_MAGFILTER, D3DTEXF_LINEAR);
        device->SetTextureStageState(0, D3DTSS_MINFILTER, D3DTEXF_LINEAR);
        // the taps are sets 0 to 3, a read by itself set 4
        device->SetTextureStageState(0, D3DTSS_TEXCOORDINDEX, ps ? 0 : 4);
        static const D3DTEXTURESTAGESTATETYPE kept[] = { D3DTSS_MAGFILTER, D3DTSS_MINFILTER, D3DTSS_MIPFILTER, D3DTSS_ADDRESSU,
            D3DTSS_ADDRESSV, D3DTSS_TEXCOORDINDEX, D3DTSS_TEXTURETRANSFORMFLAGS };
        static const DWORD wanted[] = { D3DTEXF_LINEAR, D3DTEXF_LINEAR, D3DTEXF_NONE, D3DTADDRESS_CLAMP, D3DTADDRESS_CLAMP, 0, D3DTTFF_DISABLE };
        IDirect3DBaseTexture8* stageTexture[4] = {};
        DWORD stageState[4][7] = {};
        if (ps) {
            // the same texture in stages 1 to 3, each with its own coordinate set
            for (DWORD stage = 1; stage < 4; ++stage) {
                device->GetTexture(stage, &stageTexture[stage]);
                for (int i = 0; i < 7; ++i) {
                    device->GetTextureStageState(stage, kept[i], &stageState[stage][i]);
                    device->SetTextureStageState(stage, kept[i], kept[i] == D3DTSS_TEXCOORDINDEX ? stage : wanted[i]);
                }
                device->SetTexture(stage, base);
            }
            device->GetPixelShader(&oldPs);
            device->SetPixelShader(ps);
        }
        device->SetVertexShader(0x544);
        m_Drawing = true;
        const UINT vertices = static_cast<UINT>(m_Vertices.size()), triangles = static_cast<UINT>(m_Indices.size() / 3);
        HRESULT hr;
        if (Buffers(device)) {
            // the game's indices put back after; stream 0 left empty, as the game's own DrawPrimitiveUP leaves it
            IDirect3DIndexBuffer8* indices = nullptr;
            UINT baseVertex = 0;
            device->GetIndices(&indices, &baseVertex);
            device->SetStreamSource(0, m_VertexBuffer, sizeof(lens::Tapped));
            device->SetIndices(m_IndexBuffer, 0);
            hr = device->DrawIndexedPrimitive(D3DPT_TRIANGLELIST, 0, vertices, 0, triangles);
            device->SetStreamSource(0, nullptr, 0);
            device->SetIndices(indices, baseVertex);
            if (indices) indices->Release();
        } else {
            hr = device->DrawIndexedPrimitiveUP(D3DPT_TRIANGLELIST, 0, vertices, triangles,
                m_Indices.data(), D3DFMT_INDEX16, m_Vertices.data(), sizeof(lens::Tapped));
        }
        m_Drawing = false;
        device->SetVertexShader(0x144);
        if (ps) {
            device->SetPixelShader(oldPs);
            for (DWORD stage = 1; stage < 4; ++stage) {
                device->SetTexture(stage, stageTexture[stage]);
                if (stageTexture[stage]) stageTexture[stage]->Release();
                for (int i = 0; i < 7; ++i) device->SetTextureStageState(stage, kept[i], stageState[stage][i]);
            }
        }
        device->SetTextureStageState(0, D3DTSS_MAGFILTER, mag);
        device->SetTextureStageState(0, D3DTSS_MINFILTER, min);
        device->SetTextureStageState(0, D3DTSS_TEXCOORDINDEX, index);
        if (FAILED(hr)) return false;
        m_BackW = backDesc.Width; m_BackH = backDesc.Height;
        m_SourceW = source.Width; m_SourceH = source.Height;
        m_GameFilter = min;
        m_CopyFrame = Shared.Frame;
        ++m_Warped;
        if (!m_On) return true;   // the flat picture: nothing for overlays to move
        Shared.Mode = static_cast<uint32_t>(m_Mode);
        Shared.Strength = m_Strength / 100.0f;
        Shared.TanH = static_cast<float>(tanH);
        Shared.TanV = static_cast<float>(tanV);
        Shared.WarpedFrame = Shared.Frame ? Shared.Frame : 1;
        return true;
    }

    // The pixel shaders averaging four taps (shaders.h), made once for the device when it has pixel
    // shader 1.1 and four textures at once; false without the plain one.
    bool Shaders(IDirect3DDevice8* device) {
        if (device != m_ShaderDevice) { m_Average = m_AverageModulate = 0; m_ShaderDevice = device; m_ShadersTried = false; }
        if (m_ShadersTried) return m_Average != 0;
        m_ShadersTried = true;
        D3DCAPS8 caps = {};
        if (FAILED(device->GetDeviceCaps(&caps)) || caps.PixelShaderVersion < D3DPS_VERSION(1, 1) || caps.MaxSimultaneousTextures < 4) return false;
        if (FAILED(device->CreatePixelShader(reinterpret_cast<const DWORD*>(lens::AverageShader), &m_Average))) m_Average = 0;
        if (FAILED(device->CreatePixelShader(reinterpret_cast<const DWORD*>(lens::AverageModulateShader), &m_AverageModulate))) m_AverageModulate = 0;
        return m_Average != 0;
    }
    void ReleaseShaders() {
        if (m_ShaderDevice) {
            if (m_Average) m_ShaderDevice->DeletePixelShader(m_Average);
            if (m_AverageModulate) m_ShaderDevice->DeletePixelShader(m_AverageModulate);
        }
        m_Average = m_AverageModulate = 0; m_ShaderDevice = nullptr; m_ShadersTried = false;
    }

    // The grid in buffers of the card's own (managed, so they outlive a reset), made for this device and
    // written once each time the grid is built; false when they cannot be had, and the grid is sent with
    // the draw instead.
    bool Buffers(IDirect3DDevice8* device) {
        if (device != m_BufferDevice) { ReleaseBuffers(); m_BufferDevice = device; }
        const UINT vertexBytes = static_cast<UINT>(m_Vertices.size() * sizeof(lens::Tapped)), indexBytes = static_cast<UINT>(m_Indices.size() * sizeof(uint16_t));
        if (!m_VertexBuffer && FAILED(device->CreateVertexBuffer(vertexBytes, D3DUSAGE_WRITEONLY, 0x544, D3DPOOL_MANAGED, &m_VertexBuffer))) { m_VertexBuffer = nullptr; return false; }
        if (!m_IndexBuffer && FAILED(device->CreateIndexBuffer(indexBytes, D3DUSAGE_WRITEONLY, D3DFMT_INDEX16, D3DPOOL_MANAGED, &m_IndexBuffer))) { m_IndexBuffer = nullptr; return false; }
        if (m_Written) return true;
        BYTE* to = nullptr;
        if (FAILED(m_VertexBuffer->Lock(0, vertexBytes, &to, 0)) || !to) return false;
        memcpy(to, m_Vertices.data(), vertexBytes);
        m_VertexBuffer->Unlock();
        to = nullptr;
        if (FAILED(m_IndexBuffer->Lock(0, indexBytes, &to, 0)) || !to) return false;
        memcpy(to, m_Indices.data(), indexBytes);
        m_IndexBuffer->Unlock();
        m_Written = true;
        return true;
    }
    void ReleaseBuffers() {
        if (m_VertexBuffer) m_VertexBuffer->Release();
        if (m_IndexBuffer) m_IndexBuffer->Release();
        m_VertexBuffer = nullptr; m_IndexBuffer = nullptr; m_BufferDevice = nullptr; m_Written = false;
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
