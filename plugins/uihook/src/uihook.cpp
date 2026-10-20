// One Ashita lifecycle; independent native-UI modules and versioned shared blocks.
#include "Ashita.h"
#include <memory>
#include <string>
#include "slots.h"

IPlugin* CreateBuffModule();
IPlugin* CreatePartyModule();

class UIHook : public IPlugin {
    std::unique_ptr<IPlugin> buffs, party;
    IAshitaCore* m_Core = nullptr;
public:
    const char* GetName() const override { return "uihook"; }
    const char* GetAuthor() const override { return "win"; }
    const char* GetDescription() const override { return "Modular native UI replacement: buffs, party/alliance, targets, clock, compass and chat."; }
    const char* GetLink() const override { return "https://github.com/Wincasts/win-xi"; }
    double GetVersion() const override { return 0.92; }
    // UseCommands: Ashita gives plugins commands only when they ask, and /uihook hud is one; UseText: each line given
    // to the game's chat log, recorded for addons as it stands at uihook's turn
    uint32_t GetFlags() const override { return static_cast<uint32_t>(Ashita::PluginFlags::UseCommands | Ashita::PluginFlags::UseText | Ashita::PluginFlags::UseDirect3D); }
    bool Initialize(IAshitaCore* core, ILogManager* log, uint32_t id) override {
        m_Core = core;
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
    bool HandleIncomingText(int32_t mode, bool indent, const char* message, int32_t* modifiedMode, bool* modifiedIndent, char* modifiedMessage, bool injected, bool blocked) override {
        return party && party->HandleIncomingText(mode, indent, message, modifiedMode, modifiedIndent, modifiedMessage, injected, blocked);
    }
    bool HandleCommand(int32_t mode, const char* command, bool injected) override {
        char words[3][16] = {};
        if (!command || sscanf_s(command, "%15s %15s %15s", words[0], 16u, words[1], 16u, words[2], 16u) < 1 || _stricmp(words[0], "/uihook") != 0) return false;
        if (_stricmp(words[1], "hud") == 0) return party && party->HandleCommand(mode, "/uihook hud", injected);
        if (_stricmp(words[1], "chat") == 0 && _stricmp(words[2], "history") == 0) return party && party->HandleCommand(mode, "/uihook chat history", injected);
        if (_stricmp(words[1], "chat") == 0) return party && party->HandleCommand(mode, "/uihook chat", injected);
        if (_stricmp(words[1], "menus") == 0) return party && party->HandleCommand(mode, "/uihook menus", injected);
        if (!words[1][0] || _stricmp(words[1], "addons") == 0) { Addons(); return true; }
        Say("0.8./uihook (or /uihook addons) lists addons handing it something now; /uihook hud reports clock hooks; /uihook chat reports chat replacement; /uihook chat history prints the game's newest chat lines as it keeps them; /uihook menus reports native action-menu and expanded-log placement.");
        return true;
    }
    void Say(const std::string& text) const { m_Core->GetChatManager()->Write(0, false, ("[uihook] " + text).c_str()); }
    // Which addons are handing uihook something now: told by their slots, each of which only one
    // addon fills (buff its bar, party the party, alliance and target windows, clock the clock and
    // compass). A plugin cannot see which Lua addon calls it, only what has been handed over.
    void Addons() const {
        BuffSlots buff; PartySlots slots;
        GetBuffSlots(buff); GetPartySlots(slots);
        std::string none;
        auto absent = [&](const char* name) { none += none.empty() ? name : std::string(", ") + name; };
        auto part = [](std::string& list, const char* name, bool empty) {
            if (!list.empty()) list += ", ";
            list += name;
            if (empty) list += " (hidden)";
        };
        Say("0.8.Addons handing it something now:");
        int shown = 0;
        if (buff.fresh) {
            Say("  buff: its bar, in place of the game's status icons (" + std::to_string(buff.quads) + " quads)");
            ++shown;
        } else absent("buff");
        std::string party;
        const char* lists[3] = { "party list", "alliance 1", "alliance 2" };
        for (unsigned i = 0; i < 3; ++i) if (slots.fresh & (1u << i)) part(party, lists[i], (slots.empty & (1u << i)) != 0);
        if (slots.fresh & 0x38) part(party, "target window", (slots.empty & 0x38) == (slots.fresh & 0x38));
        if (!party.empty()) { Say("  party: " + party); ++shown; } else absent("party");
        std::string hud;
        if (slots.hudFresh & 1) part(hud, (slots.hudEmpty & 1) ? "the game's clock text hidden" : "its line in place of the game's clock", false);
        if (slots.hudFresh & 2) part(hud, (slots.hudEmpty & 2) ? "the compass hidden" : "the compass replaced", false);
        if (!hud.empty()) { Say("  clock: " + hud); ++shown; } else absent("clock");
        std::string chat;
        if (slots.chatFresh & 1) part(chat, "primary log", (slots.chatEmpty & 1)!=0);
        if (slots.chatFresh & 2) part(chat, "split log", (slots.chatEmpty & 2)!=0);
        if (slots.chatFresh & 4) part(chat, "input bar", (slots.chatEmpty & 4)!=0);
        if (!chat.empty()) { Say("  chat replacement: " + chat); ++shown; }
        if (!shown) Say("  none");
        if (!none.empty()) Say("Not now: " + none + " (not loaded, switched off, or waiting for the game to draw that part).");
        // What was refused, and why: the game draws its own there, and the addon's window is drawn by imgui over it
        std::string refused;
        for (unsigned i = 0; i < 11; ++i) if (slots.refusal[i]) {
            if (!refused.empty()) refused += "; ";
            refused += std::string(PartySlotName(i)) + ": " + RefusalName(slots.refusal[i]) + ", " + std::to_string(slots.refusalRun[i])
                + " in a row, the last " + std::to_string(slots.refusalAge[i]) + " frames ago";
        }
        if (!refused.empty()) Say("Refused, so the game draws its own there and the addon's window is over it: " + refused + ".");
        if (slots.failures) Say(std::to_string(slots.failures) + " captures refused since uihook loaded (each is in Ashita's log the first time, with its reason).");
        std::string missing;
        auto lack = [&](bool there, const char* name) { if (!there) missing += missing.empty() ? name : std::string(", ") + name; };
        lack(buff.loaded && buff.hooked, "status icons");
        lack(slots.partyHooked, "party lists");
        lack(slots.targetHooked, "target window");
        lack(slots.clockHooked, "clock");
        lack(slots.compassHooked, "compass");
        lack(slots.chatHooked, "chat logs");
        if (!missing.empty()) Say("Not recognised in this client, left to the game: " + missing + ".");
    }
    void Direct3DBeginScene(bool recording) override { if (party) party->Direct3DBeginScene(recording); }
    void Direct3DEndScene(bool recording) override { if (party) party->Direct3DEndScene(recording); }
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
