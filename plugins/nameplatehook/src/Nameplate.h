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

#pragma once

#include <stdint.h>

#define UNICODE_MAX_PATH 32768

// What a name is over. Every name is in exactly one category, and a category's names are shown or
// hidden together.
enum : uint32_t {
    CATEGORY_SELF     = 1 << 0, // the local player
    CATEGORY_PARTY    = 1 << 1, // the others of the local player's party, trusts among them
    CATEGORY_ALLIANCE = 1 << 2, // the other parties of the alliance
    CATEGORY_PLAYER   = 1 << 3, // every other player
    CATEGORY_MY_PET   = 1 << 4, // the local player's pet
    CATEGORY_PET      = 1 << 5, // anyone else's pet, trust or fellow
    CATEGORY_NPC      = 1 << 6, // what cannot be fought
    CATEGORY_MONSTER  = 1 << 7, // what can, charmed players among them

    CATEGORY_COUNT    = 8,
    CATEGORY_ALL      = (1 << CATEGORY_COUNT) - 1,
};

enum : uint32_t {
    OPTION_ALWAYS_TARGET = 1 << 0, // the target's name is shown whatever its category

    OPTION_ALL           = OPTION_ALWAYS_TARGET,
};

// What is known of one name, in HookName::Flags
enum : uint32_t {
    NAME_WANTED      = 1 << 0, // not hidden by its category, or shown in spite of it
    NAME_DRAWN       = 1 << 1, // drawn by the client: wanted, and not claimed by an addon
    NAME_STARS       = 1 << 2, // the client was about to draw the Job Mastery stars over it
    NAME_TARGET      = 1 << 3, // it is the local player's target
    NAME_CHARMED     = 1 << 4, // a player who can be fought
    NAME_WHITELISTED = 1 << 5, // a player on the whitelist
    NAME_ON_SCREEN   = 1 << 6, // in front of the camera: ScreenX, ScreenY and Depth are filled in
    NAME_OVERRIDDEN  = 1 << 7, // shown or hidden by HookShared::Override, and not by its category
};

enum : uint8_t {
    OVERRIDE_NONE = 0, // by category
    OVERRIDE_SHOW = 1,
    OVERRIDE_HIDE = 2,
};

#define HOOK_VERSION 1
#define HOOK_NAMES_MAX 256
#define HOOK_ENTITIES 0x900     // the client's entities, by index
#define HOOK_CLAIM_FRAMES 30    // how long a claim lasts without being made again
#define HOOK_NAME_SIZE 28
#define HOOK_TEXT_SIZE 48

// One name the client was about to draw last frame.
struct HookName {
    uint32_t EntityIndex;
    uint32_t ServerId;
    uint32_t Category;  // one of CATEGORY_*
    uint32_t Flags;     // NAME_*
    float X, Y, Z;      // where the client puts the name, in the world: the point above the head
    float Scale;        // 1 near to, falling to 0 as the name nears the distance it is no longer drawn at
    float ScreenX;      // the same point on screen, in pixels from the top left
    float ScreenY;
    float Depth;        // how far in front of the camera it is
    uint32_t NameColor; // the client's colour for the name, as 0xAARRGGBB with 0x80 for full
    uint32_t IconColor; // its colour for the linkshell pearl, as 0xAABBGGRR with 0x80 for full
    char Name[HOOK_NAME_SIZE]; // the entity's name

    // The name as the client writes it: its icons first, each a single byte of 0x8E or more in the
    // client's font, then a space if there were any, then the name. Cut short if it does not fit.
    char Text[HOOK_TEXT_SIZE];
};

// What an addon reads and writes: found in this DLL by its first 16 bytes. See README.md.
struct HookShared {
    char Magic[16];
    uint32_t Version;    // HOOK_VERSION
    uint32_t Size;       // of this, and of one name: an addon that has them otherwise does not read on
    uint32_t NameSize;
    uint32_t Hooked;     // 1 while the client's two calls that draw a name are in this plugin's hands

    // Written by addons, and by the plugin's commands
    uint32_t Hidden;     // the categories whose names are hidden
    uint32_t Options;    // OPTION_*
    uint32_t Claimed;    // the categories an addon draws itself: wanted, listed, and not drawn by the client
    uint32_t ClaimFrame; // the Frame the claim was last made in; it lapses HOOK_CLAIM_FRAMES later

    // Written by the plugin
    uint32_t Frame;      // counts the frames drawn
    uint32_t Count;      // the names of the last frame
    float Width;         // the size of the picture ScreenX and ScreenY are places in: the client's window
    float Height;
    uint32_t Sequence;   // goes up each time the names are made ready, which is more than once a frame
    uint32_t Reserved[3];

    uint8_t Override[HOOK_ENTITIES]; // OVERRIDE_* for each entity, by index; written by addons
    HookName Names[HOOK_NAMES_MAX];
};

// What the plugin asks of its host once a frame, for sorting names into categories. An id or index of
// 0 is none.
struct FrameFacts {
    uint32_t PartyIds[6];      // server ids: the local player's party
    uint32_t AllianceIds[12];  // and the other two parties of the alliance
    uint32_t TargetIndex;      // the local player's target
    uint32_t PetIndex;         // and pet
    uint8_t Pets[HOOK_ENTITIES / 8]; // a bit for each entity that is somebody's pet, trust or fellow
};

enum class MESSAGE : uint32_t {
    PLUGIN_LOAD_ERROR,
    PLUGIN_UNLOAD_ERROR,

    SHORT_HELP,
    LONG_HELP,
    LOAD_ERROR,
    SAVE_ERROR,

    MESSAGE_MAX,
};

class NameplateSettings {
    friend class Nameplate;
    public:
        NameplateSettings() :
            FontSize(0),
            DamageFontSize(0),
            HideStars(0) {}

        int Init();
        int Load(const wchar_t* basePath);
        int Save(const wchar_t* basePath);

        void SetFontSize(int fontSize) {
            FontSize = fontSize;
        }
        void SetDamageFontSize(int fontSize) {
            DamageFontSize = fontSize;
        }
        void SetHideStars(int hideStars) {
            HideStars = hideStars;
        }

    private:
        void Flush();
        void Normalize();

        int FontSize;
        int DamageFontSize;
        int HideStars;
};

class Nameplate {
    public:
        virtual void Debug(const char* text) = 0;
        virtual void Debug(const wchar_t* text);

        virtual void ShowMessage(MESSAGE message, int param = 0) = 0;
        // A command that was not understood: command is its first word after the plugin's name
        virtual void CommandError(const char* command) = 0;
        virtual bool GetConfigPath(wchar_t path[UNICODE_MAX_PATH]) = 0;

        // The party, the target and the pets, asked for once a frame
        virtual void GetFrameFacts([[maybe_unused]] FrameFacts& facts) {}

        // An entity's spawn flags (0x10 for what can be fought). Called from the client's name drawing
        // code, once per name that is not a player's.
        virtual uint32_t GetSpawnFlags([[maybe_unused]] uint32_t entityIndex) {
            return 0;
        }

        // A look at what the client is drawing on at the moment it draws a name, said in the chat log.
        // Asked for by the probe command, and called from the client's name drawing code, once.
        virtual void ProbeScene() {}

        int Init();
        int Deinit();

        int LoadSettings();
        int SaveSettings();
        int Update();

        bool ParseCommand(const char* cmd, bool includesName);

        // Makes the names drawn so far this frame the ones addons read, each with its place on screen
        // worked out from the camera's view and projection (16 floats each, as Direct3D has them; null
        // for none). With frameDone the frame is over, and the next begins with no names.
        void Publish(const float* view, const float* projection, bool frameDone);

    private:
        int LoadWhitelist();
        int SaveWhitelist();
        void ParseWhitelistCommand(const char* cmd);
        void ParseCategoryCommand(const char* cmd, int show);
        void SayStatus();

        NameplateSettings Settings;
};
