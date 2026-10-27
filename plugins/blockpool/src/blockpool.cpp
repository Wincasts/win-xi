// blockpool: reuses the d3d8 state blocks that are made and deleted every frame, around a leak in
// Proton's wined3d (seen with GE-Proton11-5 on 2026-10-26/27). Ashita's core creates a state block of
// type D3DSBT_ALL once a frame and once for every font or primitive object it draws, applies it after
// drawing and deletes it; each such create copies the game's lights into the new block, and one copy
// of light 2 is left behind by the delete, 272 bytes a time, until the 32-bit process runs out of
// address space (about 12 MB a minute with eight font objects on screen, about 2 h 45 min to the crash).
// A fresh D3DSBT_ALL block is a snapshot of the whole device state at the moment of the create; so is
// CaptureStateBlock on an existing D3DSBT_ALL block, which copies no lights. So CreateStateBlock(ALL) is
// answered with a block from a pool, captured just now, and DeleteStateBlock of a pooled block puts it
// back in the pool. The first use of each pool slot is a real create (one copy leaked); after that
// nothing is. Pixel-state blocks pass through untouched; vertex-state blocks are pooled the same way,
// since they copy lights too. Reset deletes the idle pool and forgets the rest.
// A pooled block holds only the lights that existed when its slot was first created; a light the game
// first touches later is not restored by an apply of it. The game sets every light it uses each frame
// (about two thousand SetLight calls a frame), so nothing is seen of that.
#include "Ashita.h"
#include <psapi.h>
#include <cstdio>
#include <string>
#include <vector>

namespace {

enum Fn { FnReset, FnDelete, FnCreate, FnCount };
const int Slot[FnCount] = { 14, 56, 57 };
const int SlotCapture = 55;

typedef HRESULT(__stdcall* ResetT)(void*, D3DPRESENT_PARAMETERS*);
typedef HRESULT(__stdcall* TokenT)(void*, DWORD);
typedef HRESULT(__stdcall* CreateT)(void*, D3DSTATEBLOCKTYPE, DWORD*);

struct Entry { DWORD token; D3DSTATEBLOCKTYPE type; bool busy; };

struct State {
    void* device = nullptr;
    void** vtable = nullptr;
    void* original[FnCount] = {};
    bool hooked[FnCount] = {};
    void* capture = nullptr;
    std::vector<Entry> pool;
    uint32_t created = 0;      // real creates of pooled types
    uint32_t reused = 0;       // creates answered from the pool
    uint32_t passed = 0;       // creates passed through (pixel state, or the pool full)
    uint32_t returned = 0;     // deletes that put a block back
    uint32_t resets = 0;
    uint32_t captureFailed = 0;
};
State g;
bool g_Stranded = false;
const size_t PoolLimit = 64;

HRESULT __stdcall HookCreate(void* self, D3DSTATEBLOCKTYPE type, DWORD* token) {
    CreateT create = reinterpret_cast<CreateT>(g.original[FnCreate]);
    if (self != g.device || !token || (type != D3DSBT_ALL && type != D3DSBT_VERTEXSTATE)) { g.passed++; return create(self, type, token); }
    for (Entry& e : g.pool) {
        if (e.busy || e.type != type) continue;
        HRESULT hr = reinterpret_cast<TokenT>(g.capture)(self, e.token);
        if (FAILED(hr)) { g.captureFailed++; break; }
        e.busy = true; *token = e.token; g.reused++;
        return D3D_OK;
    }
    HRESULT hr = create(self, type, token);
    if (SUCCEEDED(hr) && g.pool.size() < PoolLimit) { g.pool.push_back({ *token, type, true }); g.created++; }
    else g.passed++;
    return hr;
}
HRESULT __stdcall HookDelete(void* self, DWORD token) {
    if (self == g.device) {
        for (Entry& e : g.pool) {
            if (e.token != token) continue;
            e.busy = false; g.returned++;
            return D3D_OK;
        }
    }
    return reinterpret_cast<TokenT>(g.original[FnDelete])(self, token);
}
HRESULT __stdcall HookReset(void* self, D3DPRESENT_PARAMETERS* parameters) {
    if (self == g.device) {
        g.resets++;
        for (const Entry& e : g.pool) if (!e.busy) reinterpret_cast<TokenT>(g.original[FnDelete])(self, e.token);
        g.pool.clear();
    }
    return reinterpret_cast<ResetT>(g.original[FnReset])(self, parameters);
}
void* const Hooks[FnCount] = { reinterpret_cast<void*>(HookReset), reinterpret_cast<void*>(HookDelete), reinterpret_cast<void*>(HookCreate) };

bool Write(void** slot, void* value) {
    DWORD old = 0;
    if (!VirtualProtect(slot, sizeof(void*), PAGE_EXECUTE_READWRITE, &old)) return false;
    *slot = value;
    VirtualProtect(slot, sizeof(void*), old, &old);
    return true;
}

}  // namespace

class BlockPool : public IPlugin {
    IAshitaCore* m_Core = nullptr;
    ILogManager* m_Log = nullptr;

    void Say(const std::string& text) const {
        m_Core->GetChatManager()->Write(0, false, ("[blockpool] " + text).c_str());
        if (m_Log) m_Log->Log(static_cast<uint32_t>(Ashita::LogLevel::Info), "blockpool", text.c_str());
    }

public:
    const char* GetName() const override { return "blockpool"; }
    const char* GetAuthor() const override { return "win"; }
    const char* GetDescription() const override { return "Reuses the d3d8 state blocks made every frame, around a light record leak in Proton's wined3d."; }
    const char* GetLink() const override { return ""; }
    double GetVersion() const override { return 0.1; }
    uint32_t GetFlags() const override { return static_cast<uint32_t>(Ashita::PluginFlags::UseCommands | Ashita::PluginFlags::UseDirect3D); }

    bool Initialize(IAshitaCore* core, ILogManager* log, uint32_t) override {
        m_Core = core; m_Log = log;
        if (g_Stranded) { Say("left stranded by an earlier unload; restart the game before loading again"); return false; }
        return true;
    }
    bool Direct3DInitialize(IDirect3DDevice8* device) override {
        if (!device) { Say("no device; nothing done"); return true; }
        g.device = device;
        g.vtable = *reinterpret_cast<void***>(device);
        g.capture = g.vtable[SlotCapture];
        int hooked = 0;
        for (int f = 0; f < FnCount; f++) {
            g.original[f] = g.vtable[Slot[f]];
            g.hooked[f] = Write(&g.vtable[Slot[f]], Hooks[f]);
            if (g.hooked[f]) hooked++; else g.original[f] = nullptr;
        }
        if (hooked != FnCount) {
            Say("could not write the device's vtable; undone, nothing pooled");
            Release();
            return true;
        }
        Say("pooling the state blocks made each frame; /blockpool for the counts");
        return true;
    }
    void Release() override {
        if (!g.device) return;
        int left = 0;
        for (int f = 0; f < FnCount; f++) {
            if (!g.hooked[f]) continue;
            if (g.vtable[Slot[f]] == Hooks[f]) { if (!Write(&g.vtable[Slot[f]], g.original[f])) left++; }
            else left++;
            g.hooked[f] = false;
        }
        // Idle pooled blocks are ours to delete; busy ones belong to whoever holds them, and their
        // deletes reach the device directly from now on.
        if (g.original[FnDelete]) for (const Entry& e : g.pool) if (!e.busy) reinterpret_cast<TokenT>(g.original[FnDelete])(g.device, e.token);
        if (left) {
            HMODULE self = nullptr;
            GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN, reinterpret_cast<LPCSTR>(&Write), &self);
            g_Stranded = true;
            Say(std::to_string(left) + " vtable slots were written over by someone else and are left; this DLL stays loaded");
        }
        g = State();
    }
    bool HandleCommand(int32_t, const char* command, bool) override {
        char word[16] = {};
        if (!command || sscanf_s(command, "%15s", word, 16u) < 1 || _stricmp(word, "/blockpool") != 0) return false;
        size_t busy = 0;
        for (const Entry& e : g.pool) if (e.busy) busy++;
        Say("pool " + std::to_string(g.pool.size()) + " blocks, " + std::to_string(busy) + " in use; real creates " + std::to_string(g.created)
            + ", reused " + std::to_string(g.reused) + ", passed through " + std::to_string(g.passed) + ", put back " + std::to_string(g.returned)
            + ", capture failures " + std::to_string(g.captureFailed) + ", resets " + std::to_string(g.resets));
        return true;
    }
};

__declspec(dllexport) IPlugin* __stdcall expCreatePlugin(const char*) { return new BlockPool(); }
__declspec(dllexport) void __stdcall expDestroyPlugin(void* instance) { delete static_cast<IPlugin*>(instance); }
__declspec(dllexport) double __stdcall expGetInterfaceVersion() { return ASHITA_INTERFACE_VERSION; }
