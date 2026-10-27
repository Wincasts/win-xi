// d3dcount: a diagnostic. Counts the d3d8 device's light and state block calls a frame, and who made
// them (the module and offset of each caller), for the wined3d light record leak of 2026-10-27.
// It patches the device's vtable slots for SetLight, LightEnable, Begin/End/Apply/Capture/Delete/
// CreateStateBlock and Reset: on the device Ashita hands plugins (the front), and on the device
// that one wraps when its vtable is d3d8.dll's (the real one). /d3dcount prints the last frame's
// counts and the totals since load; /d3dcount reset zeroes the totals.
#include "Ashita.h"
#include <intrin.h>
#include <psapi.h>
#include <cstdio>
#include <string>

namespace {

enum Fn { FnSetLight, FnLightEnable, FnBegin, FnEnd, FnApply, FnCapture, FnDelete, FnCreate, FnReset, FnCount };
const char* const Names[FnCount] = { "SetLight", "LightEnable", "BeginStateBlock", "EndStateBlock", "ApplyStateBlock",
                                     "CaptureStateBlock", "DeleteStateBlock", "CreateStateBlock", "Reset" };
const int Slot[FnCount] = { 44, 46, 52, 53, 54, 55, 56, 57, 14 };

struct Caller { uintptr_t addr; uint32_t frame, last, total; };
struct Counter {
    uint32_t frame = 0, last = 0, total = 0;
    Caller callers[12] = {};
    void Hit(uintptr_t ret) {
        frame++; total++;
        for (auto& c : callers) {
            if (c.addr == ret) { c.frame++; c.total++; return; }
            if (!c.addr) { c.addr = ret; c.frame = 1; c.total = 1; return; }
        }
    }
    void EndFrame() { last = frame; frame = 0; for (auto& c : callers) { c.last = c.frame; c.frame = 0; } }
    void Reset() { total = 0; for (auto& c : callers) c.total = 0; }
};
struct Detail { uint32_t frame = 0, last = 0, total = 0; void Hit() { frame++; total++; } void EndFrame() { last = frame; frame = 0; } };

struct Table {
    const char* label = "";
    void* device = nullptr;
    void** vtable = nullptr;
    void* original[FnCount] = {};
    bool hooked[FnCount] = {};
    Counter counters[FnCount];
    Detail lightSet[9];          // SetLight by index, 8 = any higher
    Detail lightOn[9], lightOff[9];
    Detail created[4];           // CreateStateBlock by type 1..3, 0 = other
    void EndFrame() {
        for (auto& c : counters) c.EndFrame();
        for (int i = 0; i < 9; i++) { lightSet[i].EndFrame(); lightOn[i].EndFrame(); lightOff[i].EndFrame(); }
        for (auto& d : created) d.EndFrame();
    }
};

Table g_Front, g_Real;
bool g_Stranded = false;

Table* Of(void* self) {
    if (self == g_Real.device) return &g_Real;
    if (self == g_Front.device) return &g_Front;
    return g_Real.device ? &g_Real : &g_Front;   // another object with the same vtable: counted with the one patched
}
int Clamp(DWORD index) { return index < 8 ? static_cast<int>(index) : 8; }

typedef HRESULT(__stdcall* SetLightT)(void*, DWORD, const D3DLIGHT8*);
typedef HRESULT(__stdcall* LightEnableT)(void*, DWORD, BOOL);
typedef HRESULT(__stdcall* NoArgT)(void*);
typedef HRESULT(__stdcall* TokenOutT)(void*, DWORD*);
typedef HRESULT(__stdcall* TokenT)(void*, DWORD);
typedef HRESULT(__stdcall* CreateT)(void*, D3DSTATEBLOCKTYPE, DWORD*);
typedef HRESULT(__stdcall* ResetT)(void*, D3DPRESENT_PARAMETERS*);

HRESULT __stdcall HookSetLight(void* self, DWORD index, const D3DLIGHT8* light) {
    Table* t = Of(self); t->counters[FnSetLight].Hit(reinterpret_cast<uintptr_t>(_ReturnAddress())); t->lightSet[Clamp(index)].Hit();
    return reinterpret_cast<SetLightT>(t->original[FnSetLight])(self, index, light);
}
HRESULT __stdcall HookLightEnable(void* self, DWORD index, BOOL enable) {
    Table* t = Of(self); t->counters[FnLightEnable].Hit(reinterpret_cast<uintptr_t>(_ReturnAddress()));
    (enable ? t->lightOn : t->lightOff)[Clamp(index)].Hit();
    return reinterpret_cast<LightEnableT>(t->original[FnLightEnable])(self, index, enable);
}
HRESULT __stdcall HookBegin(void* self) {
    Table* t = Of(self); t->counters[FnBegin].Hit(reinterpret_cast<uintptr_t>(_ReturnAddress()));
    return reinterpret_cast<NoArgT>(t->original[FnBegin])(self);
}
HRESULT __stdcall HookEnd(void* self, DWORD* token) {
    Table* t = Of(self); t->counters[FnEnd].Hit(reinterpret_cast<uintptr_t>(_ReturnAddress()));
    return reinterpret_cast<TokenOutT>(t->original[FnEnd])(self, token);
}
HRESULT __stdcall HookApply(void* self, DWORD token) {
    Table* t = Of(self); t->counters[FnApply].Hit(reinterpret_cast<uintptr_t>(_ReturnAddress()));
    return reinterpret_cast<TokenT>(t->original[FnApply])(self, token);
}
HRESULT __stdcall HookCapture(void* self, DWORD token) {
    Table* t = Of(self); t->counters[FnCapture].Hit(reinterpret_cast<uintptr_t>(_ReturnAddress()));
    return reinterpret_cast<TokenT>(t->original[FnCapture])(self, token);
}
HRESULT __stdcall HookDelete(void* self, DWORD token) {
    Table* t = Of(self); t->counters[FnDelete].Hit(reinterpret_cast<uintptr_t>(_ReturnAddress()));
    return reinterpret_cast<TokenT>(t->original[FnDelete])(self, token);
}
HRESULT __stdcall HookCreate(void* self, D3DSTATEBLOCKTYPE type, DWORD* token) {
    Table* t = Of(self); t->counters[FnCreate].Hit(reinterpret_cast<uintptr_t>(_ReturnAddress()));
    t->created[type >= 1 && type <= 3 ? static_cast<int>(type) : 0].Hit();
    return reinterpret_cast<CreateT>(t->original[FnCreate])(self, type, token);
}
HRESULT __stdcall HookReset(void* self, D3DPRESENT_PARAMETERS* parameters) {
    Table* t = Of(self); t->counters[FnReset].Hit(reinterpret_cast<uintptr_t>(_ReturnAddress()));
    return reinterpret_cast<ResetT>(t->original[FnReset])(self, parameters);
}
void* const Hooks[FnCount] = { reinterpret_cast<void*>(HookSetLight), reinterpret_cast<void*>(HookLightEnable), reinterpret_cast<void*>(HookBegin),
                               reinterpret_cast<void*>(HookEnd), reinterpret_cast<void*>(HookApply), reinterpret_cast<void*>(HookCapture),
                               reinterpret_cast<void*>(HookDelete), reinterpret_cast<void*>(HookCreate), reinterpret_cast<void*>(HookReset) };

bool Readable(const void* p, size_t n) {
    MEMORY_BASIC_INFORMATION info = {};
    if (!p || VirtualQuery(p, &info, sizeof(info)) != sizeof(info) || info.State != MEM_COMMIT) return false;
    if (info.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return false;
    return reinterpret_cast<const char*>(p) + n <= reinterpret_cast<const char*>(info.BaseAddress) + info.RegionSize;
}

bool Write(void** slot, void* value) {
    DWORD old = 0;
    if (!VirtualProtect(slot, sizeof(void*), PAGE_EXECUTE_READWRITE, &old)) return false;
    *slot = value;
    VirtualProtect(slot, sizeof(void*), old, &old);
    return true;
}

void Hook(Table& t) {
    for (int f = 0; f < FnCount; f++) {
        t.original[f] = t.vtable[Slot[f]];
        t.hooked[f] = Write(&t.vtable[Slot[f]], Hooks[f]);
        if (!t.hooked[f]) t.original[f] = nullptr;
    }
}
int Unhook(Table& t) {    // returns how many slots had to be left (someone else wrote over ours)
    int left = 0;
    for (int f = 0; f < FnCount; f++) {
        if (!t.hooked[f]) continue;
        if (t.vtable[Slot[f]] == Hooks[f]) { if (!Write(&t.vtable[Slot[f]], t.original[f])) left++; }
        else left++;
        t.hooked[f] = false;
    }
    return left;
}

std::string Where(uintptr_t addr) {
    HMODULE module = nullptr;
    char path[MAX_PATH] = {};
    if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, reinterpret_cast<LPCSTR>(addr), &module)
        || !GetModuleFileNameA(module, path, MAX_PATH)) {
        char text[32]; snprintf(text, sizeof(text), "%08X", static_cast<unsigned>(addr)); return text;
    }
    const char* base = strrchr(path, '\\'); base = base ? base + 1 : path;
    char text[MAX_PATH + 16]; snprintf(text, sizeof(text), "%s+%X", base, static_cast<unsigned>(addr - reinterpret_cast<uintptr_t>(module)));
    return text;
}

}  // namespace

class D3dCount : public IPlugin {
    IAshitaCore* m_Core = nullptr;
    ILogManager* m_Log = nullptr;
    uint32_t m_Frames = 0;

    void Say(const std::string& text) const {
        m_Core->GetChatManager()->Write(0, false, ("[d3dcount] " + text).c_str());
        if (m_Log) m_Log->Log(static_cast<uint32_t>(Ashita::LogLevel::Info), "d3dcount", text.c_str());
    }
    void Report(const Table& t) const {
        if (!t.device) return;
        Say(std::string(t.label) + " device: counts are last frame / since load; callers are module+offset last/total");
        for (int f = 0; f < FnCount; f++) {
            const Counter& c = t.counters[f];
            if (!c.total && !t.hooked[f]) { Say(std::string("  ") + Names[f] + ": not hooked"); continue; }
            if (!c.total) continue;
            std::string line = std::string("  ") + Names[f] + ": " + std::to_string(c.last) + " / " + std::to_string(c.total) + "; ";
            for (const auto& caller : c.callers) {
                if (!caller.addr) break;
                line += Where(caller.addr) + " " + std::to_string(caller.last) + "/" + std::to_string(caller.total) + ", ";
            }
            Say(line);
        }
        std::string lights = "  SetLight by index: ";
        for (int i = 0; i < 9; i++) if (t.lightSet[i].total) lights += (i < 8 ? std::to_string(i) : std::string("8+")) + ":" + std::to_string(t.lightSet[i].last) + "/" + std::to_string(t.lightSet[i].total) + " ";
        std::string enables = "  LightEnable on/off by index: ";
        for (int i = 0; i < 9; i++) if (t.lightOn[i].total || t.lightOff[i].total)
            enables += (i < 8 ? std::to_string(i) : std::string("8+")) + ":" + std::to_string(t.lightOn[i].last) + "/" + std::to_string(t.lightOn[i].total)
                       + " off " + std::to_string(t.lightOff[i].last) + "/" + std::to_string(t.lightOff[i].total) + " ";
        std::string creates = "  CreateStateBlock by type (1 all, 2 pixel, 3 vertex): ";
        for (int i = 0; i < 4; i++) if (t.created[i].total) creates += std::to_string(i) + ":" + std::to_string(t.created[i].last) + "/" + std::to_string(t.created[i].total) + " ";
        Say(lights); Say(enables); Say(creates);
    }

public:
    const char* GetName() const override { return "d3dcount"; }
    const char* GetAuthor() const override { return "win"; }
    const char* GetDescription() const override { return "Counts the d3d8 device's light and state block calls a frame, and who made them."; }
    const char* GetLink() const override { return ""; }
    double GetVersion() const override { return 0.1; }
    uint32_t GetFlags() const override { return static_cast<uint32_t>(Ashita::PluginFlags::UseCommands | Ashita::PluginFlags::UseDirect3D); }

    bool Initialize(IAshitaCore* core, ILogManager* log, uint32_t) override {
        m_Core = core; m_Log = log;
        if (g_Stranded) { Say("left stranded by an earlier unload; restart the game before loading again"); return false; }
        return true;
    }
    bool Direct3DInitialize(IDirect3DDevice8* device) override {
        if (!device) return true;
        HMODULE d3d8 = GetModuleHandleA("d3d8.dll");
        MODULEINFO info = {};
        uintptr_t base = 0, size = 0;
        if (d3d8 && GetModuleInformation(GetCurrentProcess(), d3d8, &info, sizeof(info))) { base = reinterpret_cast<uintptr_t>(info.lpBaseOfDll); size = info.SizeOfImage; }
        auto inD3d8 = [&](const void* p) { uintptr_t a = reinterpret_cast<uintptr_t>(p); return base && a >= base && a < base + size; };

        void** frontVt = *reinterpret_cast<void***>(device);
        if (inD3d8(frontVt)) {
            g_Real.label = "real"; g_Real.device = device; g_Real.vtable = frontVt;
        } else {
            g_Front.label = "front"; g_Front.device = device; g_Front.vtable = frontVt;
            void* candidate = *reinterpret_cast<void**>(reinterpret_cast<char*>(device) + sizeof(void*));
            if (Readable(candidate, sizeof(void*))) {
                void** candidateVt = *reinterpret_cast<void***>(candidate);
                if (inD3d8(candidateVt) && Readable(candidateVt, 100 * sizeof(void*))) { g_Real.label = "real"; g_Real.device = candidate; g_Real.vtable = candidateVt; }
            }
        }
        if (g_Front.device) Hook(g_Front);
        if (g_Real.device) Hook(g_Real);
        char text[160];
        snprintf(text, sizeof(text), "hooked: front %s (vtable %s), real %s (vtable %s); /d3dcount for the counts",
                 g_Front.device ? "yes" : "no", g_Front.vtable ? Where(reinterpret_cast<uintptr_t>(g_Front.vtable)).c_str() : "-",
                 g_Real.device ? "yes" : "no", g_Real.vtable ? Where(reinterpret_cast<uintptr_t>(g_Real.vtable)).c_str() : "-");
        Say(text);
        return true;
    }
    void Release() override {
        int left = Unhook(g_Front) + Unhook(g_Real);
        if (left) {
            HMODULE self = nullptr;
            GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN, reinterpret_cast<LPCSTR>(&Where), &self);
            g_Stranded = true;
            Say(std::to_string(left) + " vtable slots were written over by someone else and are left; this DLL stays loaded");
        }
        g_Front = Table(); g_Real = Table();
    }
    void Direct3DPresent(const RECT*, const RECT*, HWND, const RGNDATA*) override {
        g_Front.EndFrame(); g_Real.EndFrame(); m_Frames++;
    }
    bool HandleCommand(int32_t, const char* command, bool) override {
        char words[2][16] = {};
        if (!command || sscanf_s(command, "%15s %15s", words[0], 16u, words[1], 16u) < 1 || _stricmp(words[0], "/d3dcount") != 0) return false;
        if (_stricmp(words[1], "reset") == 0) {
            for (Table* t : { &g_Front, &g_Real }) { for (auto& c : t->counters) c.Reset(); for (int i = 0; i < 9; i++) { t->lightSet[i].total = 0; t->lightOn[i].total = 0; t->lightOff[i].total = 0; } for (auto& d : t->created) d.total = 0; }
            m_Frames = 0; Say("totals zeroed"); return true;
        }
        Say("frames counted since load or reset: " + std::to_string(m_Frames));
        Report(g_Front); Report(g_Real);
        return true;
    }
};

__declspec(dllexport) IPlugin* __stdcall expCreatePlugin(const char*) { return new D3dCount(); }
__declspec(dllexport) void __stdcall expDestroyPlugin(void* instance) { delete static_cast<IPlugin*>(instance); }
__declspec(dllexport) double __stdcall expGetInterfaceVersion() { return ASHITA_INTERFACE_VERSION; }
