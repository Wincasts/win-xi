// One Ashita lifecycle; independent native-UI modules and versioned shared blocks.
#include "Ashita.h"
#include <memory>

IPlugin* CreateBuffModule();
IPlugin* CreatePartyModule();

class UIHook : public IPlugin {
    std::unique_ptr<IPlugin> buffs, party;
public:
    const char* GetName() const override { return "uihook"; }
    const char* GetAuthor() const override { return "win"; }
    const char* GetDescription() const override { return "Modular native UI replacement: buffs, party/alliance, targets, clock and compass."; }
    const char* GetLink() const override { return "https://github.com/Wincasts/win-xi"; }
    double GetVersion() const override { return 0.2; }
    uint32_t GetFlags() const override { return static_cast<uint32_t>(Ashita::PluginFlags::UseDirect3D); }
    bool Initialize(IAshitaCore* core, ILogManager* log, uint32_t id) override {
        if (core->GetPluginManager()->IsLoaded("buffhook") || core->GetPluginManager()->IsLoaded("partyhook")
            || GetModuleHandleA("buffhook.dll") || GetModuleHandleA("partyhook.dll")) {
            core->GetChatManager()->Write(0, false, "[uihook] Unload buffhook and partyhook before loading uihook.");
            return false;
        }
        buffs.reset(CreateBuffModule());
        party.reset(CreatePartyModule());
        // Recognition failure is module-local: both modules initialize successfully even when
        // their signatures are missing, exposing Hooked=0 in that module's shared block.
        if (!buffs->Initialize(core, log, id) || !party->Initialize(core, log, id)) {
            Release();
            return false;
        }
        return true;
    }
    void Release() override {
        if (party) { party->Release(); party.reset(); }
        if (buffs) { buffs->Release(); buffs.reset(); }
    }
    bool Direct3DInitialize(IDirect3DDevice8* device) override {
        return buffs && party && buffs->Direct3DInitialize(device) && party->Direct3DInitialize(device);
    }
    void Direct3DPresent(const RECT* source, const RECT* dest, HWND window, const RGNDATA* dirty) override {
        if (buffs) buffs->Direct3DPresent(source, dest, window, dirty);
        if (party) party->Direct3DPresent(source, dest, window, dirty);
    }
    // The capture/replay dispatcher owns one scoped GPU filter for party/target and
    // clock/compass boundaries. Buffs uses separate icon/timer callbacks.
    bool Direct3DDrawPrimitive(D3DPRIMITIVETYPE t, UINT start, UINT count) override {
        return party && party->Direct3DDrawPrimitive(t, start, count);
    }
    bool Direct3DDrawIndexedPrimitive(D3DPRIMITIVETYPE t, UINT min, UINT vertices, UINT start, UINT count) override {
        return party && party->Direct3DDrawIndexedPrimitive(t, min, vertices, start, count);
    }
    bool Direct3DDrawPrimitiveUP(D3DPRIMITIVETYPE t, UINT count, const void* data, UINT stride) override {
        return party && party->Direct3DDrawPrimitiveUP(t, count, data, stride);
    }
    bool Direct3DDrawIndexedPrimitiveUP(D3DPRIMITIVETYPE t, UINT min, UINT vertices, UINT count,
        const void* indices, D3DFORMAT format, const void* data, UINT stride) override {
        return party && party->Direct3DDrawIndexedPrimitiveUP(t, min, vertices, count, indices, format, data, stride);
    }
};
extern "C" {
__declspec(dllexport) IPlugin* __stdcall expCreatePlugin(const char*) { return new UIHook(); }
__declspec(dllexport) void __stdcall expDestroyPlugin(void* instance) { delete static_cast<IPlugin*>(instance); }
__declspec(dllexport) double __stdcall expGetInterfaceVersion() { return ASHITA_INTERFACE_VERSION; }
}
