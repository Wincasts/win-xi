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

#include "Ashita.h"

#include "../Nameplate.h"

#include "exports.h"


#define LogLevel_Info ((uint32_t) Ashita::LogLevel::Info)
#define LogLevel_Critcal ((uint32_t) Ashita::LogLevel::Critical)

#define CHAT_HEADER "\x1e\x51[\x1e\x06nameplatehook\x1e\x51]\x1e\x01 "

// The client's entities by index: players are in the second of these ranges, and what comes and goes
// with them (pets, trusts, fellows) in the third
#define PLAYERS_BEGIN 0x400
#define DYNAMIC_BEGIN 0x700


class AshitaNameplate : public IPlugin, private Nameplate {
private:
    IAshitaCore* m_AshitaCore;
    ILogManager* m_LogManager;
    uint32_t m_PluginId;

    void PublishNames(bool frameDone);

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

    virtual void GetFrameFacts(FrameFacts& facts) override;

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

AshitaNameplate::AshitaNameplate() : m_AshitaCore(nullptr), m_LogManager(nullptr), m_PluginId(0) {
}

const char* AshitaNameplate::GetName(void) const {
    return "nameplatehook";
}

const char* AshitaNameplate::GetAuthor(void) const {
    return "BunnyBox Productions, win (and claude)";
}

const char* AshitaNameplate::GetDescription(void) const {
    return "Corrects defects in nameplate rendering, shows and hides names by category, and lists the names drawn for addons.";
}

const char* AshitaNameplate::GetLink(void) const {
    return "https://www.github.com/Shirk/Nameplate";
}

double AshitaNameplate::GetVersion(void) const {
    return 1.00;
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

    int ret = this->Init();
    if (ret < 0) {
        m_LogManager->Logf(LogLevel_Critcal, "nameplatehook", "Plugin Load Error: \"%d\"", ret);
        ShowMessage(MESSAGE::PLUGIN_LOAD_ERROR, ret);
        return false;
    }

	return true;
}

void AshitaNameplate::Release(void) {

    int ret = this->Deinit();
    if (ret < 0) {
        m_LogManager->Logf(LogLevel_Critcal, "nameplatehook", "Plugin Unload Error: \"%d\"", ret);
        ShowMessage(MESSAGE::PLUGIN_UNLOAD_ERROR, ret);
    }

    IPlugin::Release();
}

void AshitaNameplate::GetFrameFacts(FrameFacts& facts) {
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

            if (i == selfIndex) {
                facts.PetIndex = entity->PetTargetIndex;
            }
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

bool AshitaNameplate::HandleCommand([[maybe_unused]] int32_t mode, const char* command, [[maybe_unused]] bool injected) {
    return ParseCommand(command, true);
}

// The client draws its names between the scene's beginning and its end, and addons draw theirs as the
// frame is presented: the names are made ready as the scene ends, and again, whichever of this
// plugin and the addons is asked first, as the frame is presented, when the next frame's begin.
void AshitaNameplate::Direct3DEndScene(bool isRenderingBackBuffer) {
    if (isRenderingBackBuffer) {
        PublishNames(false);
    }
}

void AshitaNameplate::Direct3DPresent([[maybe_unused]] const RECT* pSourceRect, [[maybe_unused]] const RECT* pDestRect, [[maybe_unused]] HWND hDestWindowOverride, [[maybe_unused]] const RGNDATA* pDirtyRegion) {
    PublishNames(true);
}

void AshitaNameplate::PublishNames(bool frameDone) {
    IDirect3DDevice8* device = m_AshitaCore->GetDirect3DDevice();

    D3DMATRIX view;
    D3DMATRIX projection;
    if (device != nullptr && SUCCEEDED(device->GetTransform(D3DTS_VIEW, &view)) && SUCCEEDED(device->GetTransform(D3DTS_PROJECTION, &projection))) {
        Publish(&view.m[0][0], &projection.m[0][0], frameDone);
    } else {
        Publish(nullptr, nullptr, frameDone);
    }
}

static void AshitaLongHelp(IChatManager* chat) {
    chat->Write(0, false, "\x1e\x05nameplatehook v1.00, from Nameplate v0.51 by way of nameplatew v0.60");
    chat->Write(0, false, "\x1e\x05https://www.github.com/Shirk/Nameplate");
    chat->Write(0, false, "\x1e\x6aUsage (\x1e\x6a/nph\x1e\x6a is short for\x1e\x6a /nameplatehook\x1e\x6a):");
    chat->Write(0, false, "\x1e\x6a/nameplatehook help");
    chat->Write(0, true , "You're reading it!");
    chat->Write(0, false, "\x1e\x6a/nameplatehook show\x1e\x01 |\x1e\x6a hide\x1e\x01 |\x1e\x6a toggle <category>...");
    chat->Write(0, true , "Show or hide the names of a category, or of several:\x1e\x6a self party alliance players mypet pets npcs monsters\x1e\x01, or\x1e\x6a all");
    chat->Write(0, false, "\x1e\x6a/nameplatehook target on\x1e\x01 |\x1e\x6a off");
    chat->Write(0, true , "Always show your target's name, whatever its category");
    chat->Write(0, false, "\x1e\x6a/nameplatehook status");
    chat->Write(0, true , "Say which categories are shown and hidden, and how many names were listed for addons last frame");
    chat->Write(0, false, "\x1e\x6a/nameplatehook whitelist add\x1e\x6a <name>...");
    chat->Write(0, true , "Always show these players' nameplates, though players are hidden; saved at once to\x1e\x6a config\\nameplatehook\\whitelist.txt");
    chat->Write(0, false, "\x1e\x6a/nameplatehook whitelist remove\x1e\x6a <name>...");
    chat->Write(0, true , "Take these players off the whitelist");
    chat->Write(0, false, "\x1e\x6a/nameplatehook whitelist list");
    chat->Write(0, true , "Show the names on the whitelist");
    chat->Write(0, false, "\x1e\x6a/nameplatehook whitelist clear");
    chat->Write(0, true , "Take every name off the whitelist");
    chat->Write(0, false, "\x1e\x6a/nameplatehook fontsize\x1e\x6a <number>");
    chat->Write(0, true , "Set the nameplate font size to <number> pixels");
    chat->Write(0, false, "\x1e\x6a/nameplatehook damagefontsize\x1e\x6a <number>");
    chat->Write(0, true , "Set the damage font size to <number> pixels");
    chat->Write(0, false, "\x1e\x6a/nameplatehook hidestars");
    chat->Write(0, true , "Hide all Job Mastery stars");
    chat->Write(0, false, "\x1e\x6a/nameplatehook showstars");
    chat->Write(0, true , "Re-enable displaying Job Mastery stars");
    chat->Write(0, false, "\x1e\x6a/nameplatehook load");
    chat->Write(0, true , "Load configuration from\x1e\x6a config\\nameplatehook\\defaults.ini");
    chat->Write(0, false, "\x1e\x6a/nameplatehook save");
    chat->Write(0, true , "Save current configuration to\x1e\x6a config\\nameplatehook\\defaults.ini");
}

void AshitaNameplate::ShowMessage(MESSAGE message, int param) {
    IChatManager* chat = m_AshitaCore->GetChatManager();

    switch (message) {
        case MESSAGE::PLUGIN_LOAD_ERROR:
            chat->Writef(0, false, CHAT_HEADER "\x1e\x44Plugin load failed with error code \x1e\x05%d\x1e\x44!", param);
            break;
        case MESSAGE::PLUGIN_UNLOAD_ERROR:
            chat->Writef(0, false, CHAT_HEADER "\x1e\x44Plugin unload failed with error code \x1e\x05%d\x1e\x44!", param);
            break;
        case MESSAGE::SHORT_HELP:
            chat->Write(0, false, CHAT_HEADER "\x1e\x44Unknown command, please consult \x1e\x6a/nameplatehook help\x1e\x44 for more information.");
            break;
        case MESSAGE::LONG_HELP:
            AshitaLongHelp(chat);
            break;
        case MESSAGE::LOAD_ERROR:
            chat->Writef(0, false, CHAT_HEADER "\x1e\x44Loading\x1e\x6a config\\nameplatehook\\defaults.ini\x1e\x44 failed with error code \x1e\x05%d\x1e\x44!", param);
            break;
        case MESSAGE::SAVE_ERROR:
            chat->Writef(0, false, CHAT_HEADER "\x1e\x44Saving\x1e\x6a config\\nameplatehook\\defaults.ini\x1e\x44 failed with error code \x1e\x05%d\x1e\x44!", param);
            break;
        default:
            chat->Writef(0, false, "\x1e\x44Unknown message %u (%d)", (uint32_t) message, param);
            break;
    }
}

void AshitaNameplate::CommandError(const char* command) {
    m_AshitaCore->GetChatManager()->Writef(0, false, CHAT_HEADER "\x1e\x6a/nameplatehook %s\x1e\x44 command error, please consult \x1e\x6a/nameplatehook help\x1e\x44 for correct usage.", command);
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
