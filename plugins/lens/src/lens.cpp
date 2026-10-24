// lens: the game's world laid onto the screen through a Panini or cylindrical projection. The game draws the world to
// a texture of its own and copies it onto the back buffer with one quad before the UI (lens 0.1's
// captures, 2026-10-21); lens draws a warped grid in that quad's place (warp.h) and blocks the quad, so
// the UI is drawn over it as ever. The grid averages four taps over each pixel's patch of the world
// (warp.h Taps, shaders.h), for edges smoother than the game's own copy gives, with or without the
// warp. lens also sets the field of view and the aspect constant the game builds its projection with
// (projection.h; /lens fov, middle and square, drawscale's until its 2.0), and the camera's distance in battle
// (camera.h; /lens battle). /lens capture [frames] still records
// every draw over a few frames.
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
#include "projection.h"
#include "camera.h"

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

    bool m_On = true;           // everything below; off is the game's own view, the settings kept for on
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

    // the projection: what is asked for, where it is built, and what is in play
    int m_Fov = 0;              // the vertical field of view in degrees; 0 for the game's own
    int m_Middle = 0;           // degrees to keep up the middle through the warp; 0 for none. One of the two at most
    bool m_Square = false;      // the world at the window's true proportions
    uint32_t m_CAddr = 0;       // the game's constant C (192), 0 when not found
    double m_C = 0;
    std::vector<uintptr_t> m_FovSites;  // its loads that a projection's field of view is made from
    uintptr_t m_GameGlobal = 0; // the global holding the game object, 0 when not found
    uint8_t* m_Page = nullptr;  // lens's own values the game's code reads: C at 0, the battle pair at 16 and 20;
                                // kept allocated at release, for a thread still reading them
    double* m_CMem = nullptr;   // lens's own C, in m_Page
    bool m_FovPatched = false;  // the loads point at m_CMem
    bool m_FovForeign = false;  // something else points them elsewhere (drawscale 1.9's fov)
    double m_FovInPlay = 0;     // the vertical field of view lens has set, 0 for the game's own
    bool m_Capped = false;      // the middle asked for is beyond the widest field of view
    bool m_Squared = false;     // k was last set by lens for square
    // the camera in battle: what is asked for, its two loads and the constants they read, and the usual pair's
    lens::Battle m_Battle = lens::Battle::Game;
    double m_BattleDistance = 0;    // for Battle::Distance
    uintptr_t m_BattleSite[2] = {}; // the fld and fadd of the battle min and max, 0 when not found
    uint32_t m_BattleConst[2] = {}, m_NormalConst[2] = {};
    bool m_BattlePatched = false, m_BattleForeign = false;
    double m_BattleInPlay[2] = {};  // the pair lens has set, for the status
    struct { int middle = -1, mode = -1; double strength = -1, aspect = -1, fov = 0; bool capped = false; } m_MiddleCache;

    std::vector<lens::Candidate> m_Mouse;   // where the cursor's place may be kept, from /lens mouse
    uint32_t m_MouseLooks = 0;

public:
    const char* GetName() const override { return "lens"; }
    const char* GetAuthor() const override { return "win"; }
    const char* GetDescription() const override { return "The world through a Panini or cylindrical projection, for wide screens without stretched edges."; }
    const char* GetLink() const override { return "https://github.com/Wincasts/win-xi"; }
    double GetVersion() const override { return 0.91; }
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
        FindProjection();
        return true;
    }
    void Release() override {
        RestoreProjection();
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
            if (sscanf_s(line, "fov=%d", &v) == 1 && (v == 0 || (v >= lens::FovMin && v <= lens::FovMax))) m_Fov = v;
            if (sscanf_s(line, "middle=%d", &v) == 1 && (v == 0 || (v >= lens::FovMin && v <= lens::FovMax))) m_Middle = v;
            if (sscanf_s(line, "square=%d", &v) == 1) m_Square = v != 0;
            char word[16] = {};
            double d = 0;
            if (sscanf_s(line, "battle=%15s", word, 16u) == 1) {
                if (_stricmp(word, "same") == 0) m_Battle = lens::Battle::Same;
                else if (sscanf_s(word, "%lf", &d) == 1 && d >= lens::BattleLeast && d <= lens::BattleMost) { m_Battle = lens::Battle::Distance; m_BattleDistance = d; }
                else m_Battle = lens::Battle::Game;
            }
        }
        fclose(f);
        if (m_Fov) m_Middle = 0;
    }
    void Save() const {
        CreateDirectoryA((std::string(m_Core->GetInstallPath()) + "\\config").c_str(), nullptr);
        CreateDirectoryA((std::string(m_Core->GetInstallPath()) + "\\config\\lens").c_str(), nullptr);
        FILE* f = nullptr;
        if (fopen_s(&f, SettingsPath().c_str(), "wb") != 0 || !f) return;
        fprintf(f, "on=%d\nstrength=%d\nmode=%d\naa=%d\nfov=%d\nmiddle=%d\nsquare=%d\nbattle=%s\n", m_On ? 1 : 0, m_Strength, static_cast<int>(m_Mode), m_Aa ? 1 : 0,
            m_Fov, m_Middle, m_Square ? 1 : 0, BattleWord().c_str());
        fclose(f);
    }
    void Status() const {
        if (!m_On) {
            Say("off: the game's own view, flat, without aa, at its own field of view and proportions. /lens on puts back " + Settings() + ".");
            return;
        }
        std::string text = std::string("on, ") + (m_Mode == lens::Panini ? "panini" : "cylindrical") + ", strength " + std::to_string(m_Strength);
        if (m_TanH > 0) {
            char more[200];
            const double deg = 180.0 / 3.14159265358979323846;
            double k = m_Strength / 100.0;
            double middle = lens::MiddleHeight(m_TanH, m_TanV, m_Mode, k), across = lens::ShownAcross(m_TanH, m_TanV, m_Mode, k);
            snprintf(more, sizeof(more), "; the world is drawn %.0f across and %.0f up, and the screen shows %.0f across and %.0f up the middle (%.0f%% of the height)",
                2 * atan(m_TanH) * deg, 2 * atan(m_TanV) * deg, 2 * atan(across) * deg, 2 * atan(m_TanV * middle) * deg, middle * 100);
            text += more;
        }
        text += m_Warped ? "." : "; the game's copy of the world to the screen has not been seen yet.";
        Say(text);
        Say(ProjectionText());
        Say(CameraText());
        Say(Smoothing());
    }
    // battle as the ini and the status have it: game, same or the distance
    std::string BattleWord() const {
        if (m_Battle == lens::Battle::Same) return "same";
        if (m_Battle == lens::Battle::Game) return "game";
        char text[32];
        snprintf(text, sizeof(text), "%g", m_BattleDistance);
        return text;
    }
    // The camera's distance in battle as it is.
    std::string CameraText() const {
        char text[200];
        if (!m_BattleSite[0] || !m_BattleSite[1]) return "battle unavailable: the battle camera's distance was not found.";
        if (m_BattleForeign) return "battle left alone: something else has pointed the battle camera's distance elsewhere.";
        if (m_BattlePatched) {
            snprintf(text, sizeof(text), "battle %s: the camera %.1f to %.1f from you engaged%s.", m_Battle == lens::Battle::Same ? "same" : BattleWord().c_str(),
                m_BattleInPlay[0], m_BattleInPlay[1], m_Battle == lens::Battle::Same ? ", as when not" : "");
            return text;
        }
        float min = 0, max = 0;
        SafeRead(m_BattleConst[0], &min, 4);
        SafeRead(m_BattleConst[1], &max, 4);
        snprintf(text, sizeof(text), "battle %s: the game's own, the camera %.1f to %.1f from you engaged%s.", BattleWord().c_str(), min, max,
            m_On ? "" : " (lens is off)");
        return text;
    }
    // The settings /lens on puts in force, as words.
    std::string Settings() const {
        std::string text = std::string(m_Mode == lens::Panini ? "panini" : "cylindrical") + " at strength " + std::to_string(m_Strength) + ", aa " + (m_Aa ? "on" : "off");
        if (m_Fov) text += ", fov " + std::to_string(m_Fov);
        else if (m_Middle) text += ", middle " + std::to_string(m_Middle);
        text += std::string(", square ") + (m_Square ? "on" : "off");
        if (m_Battle != lens::Battle::Game) text += ", battle " + BattleWord();
        return text;
    }
    // The field of view and square as they are.
    std::string ProjectionText() const {
        char text[240];
        std::string fov;
        if (!m_CAddr || m_FovSites.empty()) fov = "fov unavailable: the projection's field of view was not found";
        else if (!m_On) fov = m_Fov ? "fov " + std::to_string(m_Fov) : m_Middle ? "middle " + std::to_string(m_Middle) : std::string("fov the game's own");
        else if (m_FovForeign) fov = "fov left alone: something else has set it (drawscale's fov before 2.0? /drawscale fov 0)";
        else if (m_FovInPlay > 0 && m_Fov) { snprintf(text, sizeof(text), "fov %d up", m_Fov); fov = text; }
        else if (m_FovInPlay > 0) {
            snprintf(text, sizeof(text), "fov %.1f up, for %d up the middle%s", m_FovInPlay, m_Middle, m_Capped ? " (as near as the widest, 140, gets)" : "");
            fov = text;
        }
        else if (m_Middle) { snprintf(text, sizeof(text), "middle %d: waiting for the game's copy of the world, to know its proportions", m_Middle); fov = text; }
        else { snprintf(text, sizeof(text), "fov the game's own, %.0f up", lens::FovOf(m_C)); fov = text; }
        if (m_On && m_CAddr && !m_FovForeign) { snprintf(text, sizeof(text), " (%u places)", static_cast<unsigned>(m_FovSites.size())); fov += text; }
        fov += std::string("; square ") + (m_Square ? "on" : "off") + (m_GameGlobal ? "" : " (the game object was not found)");
        return fov + (m_On ? "." : "; lens is off, so the game's own until /lens on.");
    }
    std::string Smoothing() const {
        std::string text = std::string("aa ") + (m_Aa ? "on" : "off");
        if (!m_On) return text + ", once /lens on.";
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
            ApplyProjection();
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
        if (_stricmp(words[1], "fov") == 0 || _stricmp(words[1], "middle") == 0) {
            bool middle = _stricmp(words[1], "middle") == 0;
            char* end = nullptr;
            long v = strtol(words[2], &end, 10);
            if (!words[2][0] || *end || (v != 0 && (v < lens::FovMin || v > lens::FovMax))) {
                Say(middle ? "Usage: /lens middle <n>, the degrees up the middle of the screen to keep whatever the warp, 20 to 140, or 0 for none."
                           : "Usage: /lens fov <n>, the vertical field of view the world is drawn with, 20 to 140 (the game's is about 77), or 0 for the game's own.");
                return true;
            }
            (middle ? m_Middle : m_Fov) = static_cast<int>(v);
            if (v) (middle ? m_Fov : m_Middle) = 0;
            Save();
            ApplyProjection();
            Status();
            return true;
        }
        if (_stricmp(words[1], "square") == 0) {
            if (_stricmp(words[2], "on") == 0) m_Square = true;
            else if (_stricmp(words[2], "off") == 0) m_Square = false;
            else { Say("Usage: /lens square on|off."); return true; }
            Save();
            ApplyProjection();
            Say(ProjectionText());
            return true;
        }
        if (_stricmp(words[1], "battle") == 0) {
            char* end = nullptr;
            double v = strtod(words[2], &end);
            if (_stricmp(words[2], "same") == 0) m_Battle = lens::Battle::Same;
            else if (words[2][0] && !*end && v == 0) m_Battle = lens::Battle::Game;
            else if (words[2][0] && !*end && v >= lens::BattleLeast && v <= lens::BattleMost) { m_Battle = lens::Battle::Distance; m_BattleDistance = v; }
            else { Say("Usage: /lens battle same|<n>|0: same keeps the camera where it is when you engage; n sets how far it moves out, 1 to 50 (the game's is 8.6); 0 is the game's own."); return true; }
            Save();
            ApplyProjection();
            Say(CameraText());
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
        Say("/lens - what the warp is doing. /lens on|off - everything lens does: off is the game's own view, and on puts your settings back. /lens mode panini|cylindrical.");
        Say("/lens strength <n> - 0 (flat, as the game) to 100 (the classic Panini, or fully cylindrical), 50 to start. /lens aa on|off - each pixel the average of four reads over the patch of the world it covers (on to start; at strength 0 for aa alone).");
        Say("/lens middle <n> - keep n degrees up the middle of the screen (77 is the game's): lens draws the world taller to give back what the warp takes. 0 for none.");
        Say("/lens fov <n> - draw the world n degrees up instead, 20 to 140; 0 is the game's own. /lens square on|off - the world at the window's true proportions (off to start).");
        Say("/lens battle same|<n>|0 - the camera's distance when you engage: same keeps it where it was, n how far out (the game's is 8.6), 0 the game's own.");
        Say("/lens capture [frames] - records every draw over the next frames to config/lens/.");
        return true;
    }

    void Direct3DBeginScene(bool back) override { if (m_Want && m_Started) m_Capture->Mark(lens::Capture::Event::BeginScene, back); }
    void Direct3DEndScene(bool back) override { if (m_Want && m_Started) m_Capture->Mark(lens::Capture::Event::EndScene, back); }
    void Direct3DPresent(const RECT*, const RECT*, HWND, const RGNDATA*) override {
        ++Shared.Frame;
        ApplyProjection();
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
        return m_On && Warp(t, count, data, stride);
    }
    bool Direct3DDrawIndexedPrimitiveUP(D3DPRIMITIVETYPE t, UINT, UINT, UINT count, const void*, D3DFORMAT, const void*, UINT) override {
        if (!m_Drawing) Record(lens::DIPUP, t, count);
        return false;
    }

private:
    // Where the projection is built: C from the build function, its loads, and the game object's global, all
    // in FFXiMain.dll. Under SEH, as the module is read whole.
    static bool SafeFind(const uint8_t* bytes, size_t size, const lens::Pattern& p, ptrdiff_t& at) {
        __try { at = lens::Find(bytes, size, p); return true; }
        __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    }
    static bool SafeSites(const uint8_t* bytes, size_t size, uintptr_t base, uint32_t c, std::vector<uintptr_t>& out) {
        __try { lens::FovSites(bytes, size, base, c, out); return true; }
        __except (EXCEPTION_EXECUTE_HANDLER) { out.clear(); return false; }
    }
    void FindProjection() {
        if (!m_Base) return;
        const auto* module = reinterpret_cast<const uint8_t*>(m_Base);
        ptrdiff_t build = -1, game = -1;
        const lens::Pattern buildPattern(lens::BuildPattern), gamePattern(lens::GamePattern);
        uint32_t cAddr = 0, global = 0;
        double c = 0;
        if (SafeFind(module, m_Size, buildPattern, build) && build >= 0 && SafeRead(m_Base + build + lens::CAt, &cAddr, 4)
            && SafeRead(cAddr, &c, 8) && c > 1 && c < 10000 && SafeSites(module, m_Size, m_Base, cAddr, m_FovSites) && !m_FovSites.empty()) {
            m_CAddr = cAddr;
            m_C = c;
        }
        if (SafeFind(module, m_Size, gamePattern, game) && game >= 0 && SafeRead(m_Base + game + 1, &global, 4)) m_GameGlobal = global;

        // the battle camera's two loads and the usual pair's constants, each found once
        const lens::Pattern battle[2] = { lens::Pattern(lens::BattleMinPattern), lens::Pattern(lens::BattleMaxPattern) };
        const size_t battleAt[2] = { lens::BattleMinAt, lens::BattleMaxAt };
        const lens::Pattern normal[2] = { lens::Pattern(lens::NormalMinPattern), lens::Pattern(lens::NormalMaxPattern) };
        const size_t normalAt[2] = { lens::NormalMinAt, lens::NormalMaxAt };
        uintptr_t sites[2] = {};
        uint32_t consts[2] = {}, normals[2] = {};
        bool found = true;
        for (int i = 0; i < 2 && found; ++i) {
            ptrdiff_t at = -1, n = -1;
            found = SafeFind(module, m_Size, battle[i], at) && at >= 0 && SafeRead(m_Base + at + battleAt[i] + 2, &consts[i], 4)
                && SafeFind(module, m_Size, normal[i], n) && n >= 0 && SafeRead(m_Base + n + normalAt[i], &normals[i], 4);
            sites[i] = found ? m_Base + at + battleAt[i] : 0;
        }
        if (found) {
            for (int i = 0; i < 2; ++i) { m_BattleSite[i] = sites[i]; m_BattleConst[i] = consts[i]; m_NormalConst[i] = normals[i]; }
        }
    }
    // lens's own page of values for the game's code to read, made once.
    uint8_t* Page() {
        if (!m_Page) {
            m_Page = static_cast<uint8_t*>(VirtualAlloc(nullptr, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
            m_CMem = m_Page ? reinterpret_cast<double*>(m_Page) : nullptr;
        }
        return m_Page;
    }
    // Four bytes of the game's code.
    static void WriteCode(uintptr_t at, uint32_t value) {
        DWORD old = 0;
        if (!VirtualProtect(reinterpret_cast<void*>(at), 4, PAGE_EXECUTE_READWRITE, &old)) return;
        memcpy(reinterpret_cast<void*>(at), &value, 4);
        VirtualProtect(reinterpret_cast<void*>(at), 4, old, &old);
        FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(at), 4);
    }
    // The field of view asked for, in degrees, 0 for the game's own: fov as set, or the one keeping middle up
    // the middle through the warp as it is (worked out again only when something it rests on changes).
    double WantedFov() {
        if (!m_On || !m_Middle) m_Capped = false;
        if (!m_On) return 0;
        if (m_Fov) { m_Capped = false; return m_Fov; }
        if (!m_Middle) return 0;
        const double strength = m_Strength / 100.0;
        if (strength == 0) { m_Capped = false; return m_Middle; }
        if (m_TanH <= 0 || m_TanV <= 0) return 0;
        const double aspect = m_TanH / m_TanV;
        auto& k = m_MiddleCache;
        if (k.middle != m_Middle || k.mode != m_Mode || k.strength != strength || fabs(k.aspect - aspect) > 1e-4) {
            k.middle = m_Middle; k.mode = m_Mode; k.strength = strength; k.aspect = aspect;
            k.fov = lens::MiddleFov(m_Middle, aspect, m_Mode, strength, k.capped);
        }
        m_Capped = k.capped;
        return k.fov;
    }
    // Into the game, each Present and after a command: the loads of C at lens's own C for a field of view, back
    // at the game's for its own, and k for square. Only what differs is written; loads something else has
    // pointed elsewhere are left to it.
    void ApplyProjection() {
        if (m_CAddr && !m_FovSites.empty()) {
            const double fov = WantedFov();
            if (fov > 0) {
                if (Page()) {
                    const double c = lens::CFor(fov);
                    if (*m_CMem != c) *m_CMem = c;
                    if (!m_FovPatched) {
                        const uint32_t ours = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(m_CMem));
                        m_FovForeign = false;
                        for (uintptr_t site : m_FovSites) {
                            uint32_t now = 0;
                            if (!SafeRead(site + 2, &now, 4) || (now != m_CAddr && now != ours)) m_FovForeign = true;
                        }
                        if (!m_FovForeign) {
                            for (uintptr_t site : m_FovSites) WriteCode(site + 2, ours);
                            m_FovPatched = true;
                        }
                    }
                }
            } else if (m_FovPatched) {
                for (uintptr_t site : m_FovSites) WriteCode(site + 2, m_CAddr);
                m_FovPatched = false;
            } else {
                m_FovForeign = false;
            }
            m_FovInPlay = m_FovPatched ? fov : 0;
        }
        ApplyCamera();
        const bool square = m_On && m_Square;
        if (m_GameGlobal && (square || m_Squared)) {
            uint32_t object = 0, k = 0;
            if (SafeRead(m_GameGlobal, &object, 4) && object && SafeRead(object + lens::KOffset, &k, 4)) {
                const uint32_t want = square ? lens::KSquare : lens::KStock;
                // a k that is neither constant was set by something else, and is left to it
                if (k != want && (k == lens::KStock || k == lens::KSquare)) SafeWrite(object + lens::KOffset, &want, 4);
            }
            m_Squared = square;
        }
    }
    // The battle camera's loads at lens's own pair for battle same or a distance, back at the game's constants
    // for its own or with lens off. The pair follows the game's constants (the usual pair for same), read each
    // time, so another addon's change to them is kept.
    void ApplyCamera() {
        if (!m_BattleSite[0] || !m_BattleSite[1]) return;
        if (m_On && m_Battle != lens::Battle::Game && Page()) {
            float normalMin = 0, normalMax = 0, battleMin = 0, battleMax = 0;
            if (!SafeRead(m_NormalConst[0], &normalMin, 4) || !SafeRead(m_NormalConst[1], &normalMax, 4)
                || !SafeRead(m_BattleConst[0], &battleMin, 4) || !SafeRead(m_BattleConst[1], &battleMax, 4)) return;
            double min = 0, max = 0;
            lens::BattleRange(m_Battle, m_BattleDistance, normalMin, normalMax, battleMin, battleMax, min, max);
            float* ours = reinterpret_cast<float*>(m_Page + 16);
            if (ours[0] != static_cast<float>(min)) ours[0] = static_cast<float>(min);
            if (ours[1] != static_cast<float>(max)) ours[1] = static_cast<float>(max);
            m_BattleInPlay[0] = min; m_BattleInPlay[1] = max;
            if (!m_BattlePatched) {
                m_BattleForeign = false;
                for (int i = 0; i < 2; ++i) {
                    uint32_t now = 0;
                    const uint32_t mine = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(ours + i));
                    if (!SafeRead(m_BattleSite[i] + 2, &now, 4) || (now != m_BattleConst[i] && now != mine)) m_BattleForeign = true;
                }
                if (!m_BattleForeign) {
                    for (int i = 0; i < 2; ++i) WriteCode(m_BattleSite[i] + 2, static_cast<uint32_t>(reinterpret_cast<uintptr_t>(ours + i)));
                    m_BattlePatched = true;
                }
            }
        } else if (m_BattlePatched) {
            for (int i = 0; i < 2; ++i) WriteCode(m_BattleSite[i] + 2, m_BattleConst[i]);
            m_BattlePatched = false;
        } else {
            m_BattleForeign = false;
        }
    }
    // The game's own projection and camera back, at release; lens's page stays allocated.
    void RestoreProjection() {
        if (m_BattlePatched) for (int i = 0; i < 2; ++i) WriteCode(m_BattleSite[i] + 2, m_BattleConst[i]);
        m_BattlePatched = false;
        if (m_FovPatched) for (uintptr_t site : m_FovSites) WriteCode(site + 2, m_CAddr);
        m_FovPatched = false;
        if (m_Squared && m_GameGlobal) {
            uint32_t object = 0, k = 0;
            if (SafeRead(m_GameGlobal, &object, 4) && object && SafeRead(object + lens::KOffset, &k, 4) && k == lens::KSquare)
                SafeWrite(object + lens::KOffset, &lens::KStock, 4);
        }
        m_Squared = false;
    }

    static bool SafeRead(uintptr_t address, void* buffer, size_t size) {
        __try { memcpy(buffer, reinterpret_cast<const void*>(address), size); return true; }
        __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    }
    static bool SafeWrite(uintptr_t address, const void* buffer, size_t size) {
        __try { memcpy(reinterpret_cast<void*>(address), buffer, size); return true; }
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
    // grid with the same state, warped by the strength (flat at 0, for aa alone), and the quad
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
        const int strength = m_Strength;
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
