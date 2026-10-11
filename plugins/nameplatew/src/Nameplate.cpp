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
#include <inttypes.h>

#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <ctype.h>

#include "Nameplate.h"

#include "bytes/bytes.h"

#include "findsignature.h"

// No copyright is claimed on the following "fair use for interoperability" section.
/* Begin "fair use for interoperability" section */
#define GETFRAMEDELTA "8B0D????????D94128D81D????????DFE0F6C4057A07D905????????C3"
#define INITAPPLICATIONDEFAULTS "B90002000033C0890D????????890D????????B901000000A3????????C705????????80020000C705????????E0010000"
#define GETPLAYERENTITY "66A1????????6685C0740E0FBFC08B0485????????85C0750233C0C3"

#define DRAWNAME_PATCH0_LOCATION "E8????????25FFFF000089442410DB442410D80D????????D88C24E0060000D95C244CE8????????8BBC24DC06000025FFFF00008944241083C9FFDB44241033C0F2AED80D????????D88C24E0060000F7D14983F924894C2418D95C24507E09B924000000894C2418"
#define DRAWNAME_PATCH1_LOCATION "E8????????25FFFF000089442410DB442410D80D????????D88C24D4060000D95C2438E8????????25FFFF00008BAC24D0060000894424108BFDDB44241083C9FF33C0F2AED80D????????D88C24D4060000F7D14983F924"
#define DRAWNAME2_PATCH_LOCATION "6683B9B20000000075178B44240C8B4C2408"
#define DRAWNAME3_PATCH_LOCATION "A0????????84C0745E8B4E7033C0A0????????83F803774FFF2485????????F74178000000FF753F8B168BCEFF92CC0000005F5E81C418010000C38B517881E2000000FF81FA00000001751B8B8120010000C1E80DA801EBCD8B8920010000C1E90DF6C10175C1"
#define DRAWNAME3_V2_PATCH_LOCATION "A0????????84C0747A8B7E7033C0A0????????83F804776BFF2485????????F74778000000FF755B8B168BCEFF92CC0000005F5E81C418010000C38B4F7881E1000000FF81F90000000175378B9720010000C1EA0DF6C201EBCC8B8720010000C1E80DA801EB1AF74778000000FF7513E8????????85C0740A8B48788B47783BC875A5"

#define DRAWDAMAGE_PATCH_LOCATION "A1????????8B88C80D0000E8????????8B5008A1????????8954240CDB44240CD84C2408D80D????????D95C24208B88C80D0000E8????????8B400C8B0D????????8944240C8BF1DB44240C8BD681E2FFFFFF00D84C240881FA80808000D80D????????D95C2424750E8B879401000081E6000000FF0BF0"
/* End "fair use for interoperability" section */


// MSVC does not provide GCC/Clang's nameplate_strlen.  Keep this tiny
// constexpr helper so the patch-size constants and command parser lengths
// work with Visual Studio/MSVC as well as Clang.
static constexpr size_t nameplate_strlen(const char* text) {
    size_t len = 0;
    while (text[len] != '\0') {
        ++len;
    }
    return len;
}

static constexpr auto getFrameDeltaSig = MakeSig<GETFRAMEDELTA>();
static constexpr auto initApplicationDefaultsSig = MakeSig<INITAPPLICATIONDEFAULTS>();
static constexpr auto getPlayerEntitySig = MakeSig<GETPLAYERENTITY>();

static constexpr auto drawNamePatch0LocationSig = MakeSig<DRAWNAME_PATCH0_LOCATION>();
static constexpr auto drawNamePatch1LocationSig = MakeSig<DRAWNAME_PATCH1_LOCATION>();
static constexpr auto drawName2PatchLocationSig = MakeSig<DRAWNAME2_PATCH_LOCATION>();
static constexpr auto drawName3PatchLocationSig = MakeSig<DRAWNAME3_PATCH_LOCATION>();
static constexpr auto drawName3V2PatchLocationSig = MakeSig<DRAWNAME3_V2_PATCH_LOCATION>();
static constexpr auto drawDamagePatchLocationSig = MakeSig<DRAWDAMAGE_PATCH_LOCATION>();

static constexpr size_t DRAWNAME_PATCH0_SIZE = nameplate_strlen(DRAWNAME_PATCH0_LOCATION) / 2;
static constexpr size_t DRAWNAME_PATCH1_SIZE = nameplate_strlen(DRAWNAME_PATCH1_LOCATION) / 2;
static constexpr size_t DRAWNAME2_PATCH_SIZE = nameplate_strlen(DRAWNAME2_PATCH_LOCATION) / 2;
static constexpr size_t DRAWNAME3_PATCH_SIZE = nameplate_strlen(DRAWNAME3_PATCH_LOCATION) / 2;
static constexpr size_t DRAWNAME3_V2_PATCH_SIZE = nameplate_strlen(DRAWNAME3_V2_PATCH_LOCATION) / 2;
static constexpr size_t DRAWDAMAGE_PATCH_SIZE = nameplate_strlen(DRAWDAMAGE_PATCH_LOCATION) / 2;

// Wish I could just #embed these...
// See src/assembly for source code.
static constexpr uint8_t DrawName_Patch0[DRAWNAME_PATCH0_SIZE] = {
  0x8d, 0x4c, 0x24, 0x4c, 0x8d, 0x94, 0x24, 0xe0, 0x06, 0x00, 0x00, 0xb8,
  0x78, 0x56, 0x34, 0x12, 0xff, 0xd0, 0x8b, 0xbc, 0x24, 0xdc, 0x06, 0x00,
  0x00, 0x83, 0xc9, 0xff, 0x31, 0xc0, 0xf2, 0xae, 0xf7, 0xd1, 0x49, 0x83,
  0xf9, 0x24, 0x7e, 0x05, 0xb9, 0x24, 0x00, 0x00, 0x00, 0x89, 0x4c, 0x24,
  0x18, 0xeb, 0x36, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90
};
#define DRAWNAME_PATCH0_ADDRESS_LOCATION 12

static constexpr uint8_t DrawName_Patch1[DRAWNAME_PATCH1_SIZE] = {
  0x8d, 0x4c, 0x24, 0x38, 0x8d, 0x94, 0x24, 0xd4, 0x06, 0x00, 0x00, 0xb8,
  0x78, 0x56, 0x34, 0x12, 0xff, 0xd0, 0xd9, 0x44, 0x24, 0x3c, 0x8b, 0xac,
  0x24, 0xd0, 0x06, 0x00, 0x00, 0x83, 0xc9, 0xff, 0x89, 0xef, 0x31, 0xc0,
  0xf2, 0xae, 0xf7, 0xd1, 0x49, 0x83, 0xf9, 0x24, 0xeb, 0x2a, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90
};
#define DRAWNAME_PATCH1_ADDRESS_LOCATION 12

// No custom assembly here-- just patching a jnz to a jmp
#define DRAWNAME2_PATCH_ADDRESS_LOCATION 8

// Past the end of the DrawName3 V2 patch, in the same function, are the two calls that draw a name:
// its first line, the name itself, and its second, the Job Mastery stars. Each goes through a small
// function of the model that begins as DRAWNAME2_PATCH_LOCATION does and passes its arguments on.
// No custom assembly here either: the two calls are pointed at functions of this plugin.
#define DRAWNAME_LINE_CALL_OFFSET 0x104
#define DRAWNAME_LINE_RET_OFFSET 0x2B   // RET 0x14
#define DRAWNAME_LINE2_CALL_OFFSET 0x137
#define DRAWNAME_LINE2_RET_OFFSET 0x21  // RET 0x0C
#define DRAWNAME_STARS '\xD2'           // what the second line holds for a player with a job mastered

static constexpr uint8_t DrawName3_Patch[DRAWNAME3_PATCH_SIZE] = {
  0x89, 0xf1, 0xb8, 0x78, 0x56, 0x34, 0x12, 0xff, 0xd0, 0x84, 0xc0, 0x75,
  0x5a, 0x74, 0x19, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x8b, 0x16, 0x89, 0xf1, 0xff, 0x92, 0xcc, 0x00,
  0x00, 0x00, 0x5f, 0x5e, 0x81, 0xc4, 0x18, 0x01, 0x00, 0x00, 0xc3, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90
};
#define DRAWNAME3_PATCH_ADDRESS_LOCATION 3

static constexpr uint8_t DrawName3_V2_Patch[DRAWNAME3_V2_PATCH_SIZE] = {
  0x89, 0xf1, 0xb8, 0x78, 0x56, 0x34, 0x12, 0xff, 0xd0, 0x84, 0xc0, 0x75,
  0x76, 0x74, 0x19, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x8b, 0x16, 0x89, 0xf1, 0xff, 0x92, 0xcc, 0x00,
  0x00, 0x00, 0x5f, 0x5e, 0x81, 0xc4, 0x18, 0x01, 0x00, 0x00, 0xc3, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90
};
#define DRAWNAME3_V2_PATCH_ADDRESS_LOCATION 3

static constexpr uint8_t DrawDamage_Patch[DRAWDAMAGE_PATCH_SIZE] = {
  0x8d, 0x4c, 0x24, 0x20, 0x8d, 0x54, 0x24, 0x08, 0xb8, 0x78, 0x56, 0x34,
  0x12, 0xff, 0xd0, 0x8b, 0x0d, 0x78, 0x56, 0x34, 0x12, 0x89, 0xca, 0x89,
  0xce, 0x81, 0xe2, 0xff, 0xff, 0xff, 0x00, 0x81, 0xfa, 0x80, 0x80, 0x80,
  0x00, 0x75, 0x51, 0x8b, 0x87, 0x94, 0x01, 0x00, 0x00, 0x81, 0xe6, 0x00,
  0x00, 0x00, 0xff, 0x09, 0xc6, 0xeb, 0x41, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90
};

#define DRAWDAMAGE_PATCH_CALL_ADDRESS_LOCATION 0x09
#define DRAWDAMAGE_PATCH_COLOR_ADDRESS_LOCATION 0x11
#define DRAWDAMAGE_PATCH_OLD_COLOR_ADDRESS_LOCATION 0x3E

// "CGame" - various application-level rendering-related things.
typedef struct CGame {
	uint8_t unknown0[0x18];
	uint16_t BackgroundWidth;
	uint16_t BackgroundHeight;
	uint8_t unknown1[0x33C - 0x1C];
} CGame;

typedef struct Entity {
	uint8_t unknown0[0x74];
	uint32_t EntityIndex;
	uint32_t EntityId;
	char Name[28]; // the last 4 bytes are a flag on some entities
	uint8_t unknown1[0x120 - 0x98];
	uint32_t Flags0;
	// etc.
} Entity;

typedef struct XiModel {
	uint8_t unknown0[0x70];
	Entity* pEntity;
	// etc.
} XiModel;

// The model's two functions for drawing a line of its name. They are __thiscall, written here as
// __fastcall with a second argument that goes unused: the same registers, the same stack.
typedef void (__fastcall *DrawNameLineFn)(const XiModel* pModel, void* unused, const float* pPosition, const char* text, uint32_t scale, uint32_t nameColor, uint32_t iconColor);
typedef void (__fastcall *DrawNameLine2Fn)(const XiModel* pModel, void* unused, const float* pPosition, const char* text, uint32_t scale);

static struct {
	CGame** pgGame;
	uint32_t* pWindowWidth;
	uint32_t* pWindowHeight;
	uint16_t* pPlayerEntityIndex;
	bool* pNamesOff;

	uintptr_t DrawNamePatch0Addr;
	uint8_t DrawNamePatch0Orig[DRAWNAME_PATCH0_SIZE];

	uintptr_t DrawNamePatch1Addr;
	uint8_t DrawNamePatch1Orig[DRAWNAME_PATCH1_SIZE];

	uintptr_t DrawName2PatchAddr;
	uint8_t DrawName2PatchOrig[DRAWNAME2_PATCH_SIZE];

	uintptr_t DrawName3PatchAddr;
	uint8_t DrawName3PatchOrig[DRAWNAME3_PATCH_SIZE];

	uintptr_t DrawName3V2PatchAddr;
	uint8_t DrawName3V2PatchOrig[DRAWNAME3_V2_PATCH_SIZE];

	uintptr_t DrawDamagePatchAddr;
	uint8_t DrawDamagePatchOrig[DRAWDAMAGE_PATCH_SIZE];

	// The two calls that draw a name's lines, and the client's functions they called before
	uintptr_t DrawNameLineCallAddr;
	uintptr_t DrawNameLine2CallAddr;
	DrawNameLineFn DrawNameLineOrig;
	DrawNameLine2Fn DrawNameLine2Orig;

	// The model whose first line was last handed to an addon, so that its second is not drawn either,
	// and where in the list that name was put
	const XiModel* pCustomModel;
	struct CustomName* pCustomName;
} Globals;

static struct {
	int FontSize;
	int DamageFontSize;
	int HideStars;
	int IncludeAlliance;
	int Custom;
	NAME_MODE NameMode;
} AsmSettings;

// [Experimental] Names handed to an addon to draw, in place of the client drawing them.
//
// With the Custom setting on and an addon asking, every name the client is about to draw (so one the
// mode has not hidden, and that the client itself finds near enough and on screen) is added to this
// list and not drawn. The addon finds the list in this DLL by its first 16 bytes, sets Consumer while
// it is drawing, and each frame reads the names and sets Count back to 0. Should the list fill, no
// addon is emptying it: names are drawn by the client again until one does.
#define CUSTOM_NAMES_MAX 256
#define CUSTOM_NAMES_VERSION 2
#define CUSTOM_NAME_TEXT_SIZE 48

struct CustomName {
	uint32_t EntityIndex;
	float X, Y, Z;      // where the client puts the name, in the world: the point above the head
	float Scale;        // the client's own size for the name, 1 unless it is drawn larger or smaller
	uint32_t NameColor; // the client's colour for the name, as 0xAARRGGBB with 0x80 for full
	uint32_t IconColor; // its colour for the linkshell pearl, as 0xAABBGGRR with 0x80 for full
	uint32_t Stars;     // 1 if the client was about to draw the Job Mastery stars over the name

	// The name as the client writes it: its icons first, each a single byte of 0x8E or more in the
	// client's font, then a space if there were any, then the name. Cut short if it does not fit.
	char Text[CUSTOM_NAME_TEXT_SIZE];
};

static struct CustomNames {
	char Magic[16];
	uint32_t Version;
	uint32_t Hooked;    // 1 while the client's two calls are in this plugin's hands
	uint32_t Enabled;   // the Custom setting
	uint32_t Consumer;  // set by the addon while it draws the names, and cleared when it stops
	uint32_t Count;     // names added since the addon last set this to 0
	uint32_t Reserved[3];
	CustomName Names[CUSTOM_NAMES_MAX];
} Custom = { "NAMEPLATEW-LIST", CUSTOM_NAMES_VERSION, 0, 0, 0, 0, {}, {} };

// The plugin whose party is asked about while names are drawn; set while the patches are in place.
static Nameplate* Instance = nullptr;

// Players whose names are drawn in every mode that hides players.
#define WHITELIST_MAX 512
#define WHITELIST_NAME_SIZE 24

static struct {
	size_t Count;
	char Names[WHITELIST_MAX][WHITELIST_NAME_SIZE];
} Whitelist;

static int FindWhitelisted(const char* name) {
	for (size_t i = 0; i < Whitelist.Count; i++) {
		if (_strnicmp(name, Whitelist.Names[i], WHITELIST_NAME_SIZE) == 0) {
			return static_cast<int>(i);
		}
	}
	return -1;
}

// Whether a player's name is drawn in the modes that hide players. With party set, members of the
// local player's party (and alliance, by the IncludeAlliance setting) are drawn as well.
static bool ShouldDrawPlayer(const Entity* pEntity, bool party) {
	// attackable (charmed)
	if (((pEntity->Flags0 >> 13) & 1) != 0) {
		return true;
	}

	if (Whitelist.Count != 0 && FindWhitelisted(pEntity->Name) >= 0) {
		return true;
	}

	if (party && Instance != nullptr) {
		return Instance->IsPartyMember(pEntity->EntityId, AsmSettings.IncludeAlliance != 0);
	}

	return false;
}

// Called in place of the client's function for a name's first line: the name is handed to the addon,
// or drawn as it always was.
static void __fastcall DrawNameLine(const XiModel* pModel, [[maybe_unused]] void* unused, const float* pPosition, const char* text, uint32_t scale, uint32_t nameColor, uint32_t iconColor) {
	Globals.pCustomModel = nullptr;

	if (Custom.Enabled != 0 && Custom.Consumer != 0 && Custom.Count < CUSTOM_NAMES_MAX
			&& pModel != nullptr && pModel->pEntity != nullptr && pPosition != nullptr) {
		CustomName& name = Custom.Names[Custom.Count];
		name.EntityIndex = pModel->pEntity->EntityIndex;
		name.X = pPosition[0];
		name.Y = pPosition[1];
		name.Z = pPosition[2];
		memcpy(&name.Scale, &scale, sizeof(name.Scale));
		name.NameColor = nameColor;
		name.IconColor = iconColor;
		name.Stars = 0;

		size_t length = 0;
		if (text != nullptr) {
			while (length < CUSTOM_NAME_TEXT_SIZE - 1 && text[length] != '\0') {
				name.Text[length] = text[length];
				length++;
			}
		}
		name.Text[length] = '\0';

		Custom.Count++;

		Globals.pCustomModel = pModel;
		Globals.pCustomName = &name;
		return;
	}

	if (Globals.DrawNameLineOrig != nullptr) {
		Globals.DrawNameLineOrig(pModel, nullptr, pPosition, text, scale, nameColor, iconColor);
	}
}

// Called in place of the client's function for a name's second line, which follows the first at once.
static void __fastcall DrawNameLine2(const XiModel* pModel, [[maybe_unused]] void* unused, const float* pPosition, const char* text, uint32_t scale) {
	if (Globals.pCustomModel != nullptr && Globals.pCustomModel == pModel) {
		// The second line is the stars or nothing: the client writes them as this one character
		if (text != nullptr && strchr(text, DRAWNAME_STARS) != nullptr && AsmSettings.HideStars == 0 && Globals.pCustomName != nullptr) {
			Globals.pCustomName->Stars = 1;
		}

		Globals.pCustomModel = nullptr;
		Globals.pCustomName = nullptr;
		return;
	}

	if (Globals.DrawNameLine2Orig != nullptr) {
		Globals.DrawNameLine2Orig(pModel, nullptr, pPosition, text, scale);
	}
}

// Where a CALL rel32 at this address goes, or 0 if that is not what is there, or it goes far off.
static uintptr_t CallTarget(uintptr_t pCall) {
	const uint8_t* pLoc = reinterpret_cast<const uint8_t*> (pCall);
	if (pLoc[0] != 0xE8) {
		return 0;
	}

	int32_t rel;
	memcpy(&rel, pLoc + 1, sizeof(rel));
	if (rel < -0x10000 || rel > 0x10000) {
		return 0;
	}

	return pCall + 5 + rel;
}

static void SetCallTarget(uintptr_t pCall, uintptr_t target) {
	int32_t rel = static_cast<int32_t>(target - (pCall + 5));
	memcpy(reinterpret_cast<uint8_t*> (pCall) + 1, &rel, sizeof(rel));
}

// Whether the function here is one of the model's two for drawing a line of its name: it begins as
// both do, and gives back the stack that one of them does.
static bool IsDrawNameLine(uintptr_t pFunction, size_t retOffset, uint8_t retBytes) {
	static const uint8_t begins[] = { 0x66, 0x83, 0xB9, 0xB2, 0x00, 0x00, 0x00, 0x00 };
	const uint8_t* pLoc = reinterpret_cast<const uint8_t*> (pFunction);

	return pFunction != 0
		&& memcmp(pLoc, begins, sizeof(begins)) == 0
		&& pLoc[retOffset] == 0xC2 && pLoc[retOffset + 1] == retBytes && pLoc[retOffset + 2] == 0x00;
}

static void __fastcall GetNameplateScale(float* wh, const float* pS) {
	if (Globals.pgGame != nullptr) {
		auto gGame = *Globals.pgGame;

		double bkgW = gGame->BackgroundWidth;
		double bkgH = gGame->BackgroundHeight;
		double winW = *Globals.pWindowWidth;
		double winH = *Globals.pWindowHeight;

		double wRatio = bkgW / winW;
		double hRatio = bkgH / winH;

		double s = *pS;

		double FontScale = (double) AsmSettings.FontSize / 11.0;

		wh[0] = static_cast<float>(FontScale * wRatio * s);
		wh[1] = static_cast<float>(FontScale * hRatio * s);
	}
}

static void __fastcall GetDamageNumberScale(float* wh, const float* pS) {
	if (Globals.pgGame != nullptr) {
		auto gGame = *Globals.pgGame;

		double bkgW = gGame->BackgroundWidth;
		double bkgH = gGame->BackgroundHeight;
		double winW = *Globals.pWindowWidth;
		double winH = *Globals.pWindowHeight;

		double wRatio = bkgW / winW;
		double hRatio = bkgH / winH;

		double s = *pS;

		// Using the same scale factor seems to look correct.
		double FontScale = (double) AsmSettings.DamageFontSize / 11.0;

		wh[0] = static_cast<float>(FontScale * wRatio * s);
		wh[1] = static_cast<float>(FontScale * hRatio * s);
	}
}

static bool __fastcall ShouldDrawNameplate(const XiModel* pModel) {
	if (*Globals.pNamesOff) {
		return false;
	}

	if (pModel == nullptr) {
		return false;
	}
	const Entity* pEntity = pModel->pEntity;
	if (pEntity == nullptr) {
		return false;
	}

	// client version (some options not accessable in retail client)
	// note - (Entity->Flags0 >> 13) & 1 is attackable entity
	// mode 0 - off
	// mode 1 - npc only
	// mode 2 - mob (incl. attackable pc) and npc
	// mode 3 - non-attackable entities only
	// mode 4 - player and npcs

	if (Globals.pPlayerEntityIndex != nullptr) {
		switch (AsmSettings.NameMode) {
			case NAME_MODE::ALL:
			default:
				return true;

			case NAME_MODE::NONE:
				return false;

			case NAME_MODE::HIDE_SELF:
				return (pEntity->EntityIndex != *Globals.pPlayerEntityIndex);

			case NAME_MODE::HIDE_PCSELF:
				if (pEntity->EntityIndex == *Globals.pPlayerEntityIndex) {
					return false;
				}
				[[fallthrough]];
			case NAME_MODE::HIDE_PC:
				if ((pEntity->EntityId & 0xFF000000) != 0) {
					return true;
				}
				return ShouldDrawPlayer(pEntity, false);

			case NAME_MODE::HIDE_PCPARTYSELF:
				if (pEntity->EntityIndex == *Globals.pPlayerEntityIndex) {
					return false;
				}
				[[fallthrough]];
			case NAME_MODE::HIDE_PCPARTY:
				if ((pEntity->EntityId & 0xFF000000) != 0) {
					return true;
				}
				if (pEntity->EntityIndex == *Globals.pPlayerEntityIndex) {
					return true;
				}
				return ShouldDrawPlayer(pEntity, true);

			case NAME_MODE::HIDE_NPCSELF:
				if (pEntity->EntityIndex == *Globals.pPlayerEntityIndex) {
					return false;
				}
				[[fallthrough]];
			case NAME_MODE::HIDE_NPC:
				return ((pEntity->EntityId & 0xFF000000) == 0);
		}
	}

	return true;
}

void NameplateSettings::Flush() {
	AsmSettings.FontSize = FontSize;
	AsmSettings.DamageFontSize = DamageFontSize;
	AsmSettings.HideStars = HideStars;
	AsmSettings.IncludeAlliance = IncludeAlliance;
	AsmSettings.Custom = Custom;
	AsmSettings.NameMode = NameMode;

	::Custom.Enabled = (Custom != 0) ? 1 : 0;
}

void NameplateSettings::Normalize() {
	if (FontSize < 1) {
		FontSize = 1;
	}
	if (FontSize > 256) {
		FontSize = 256;
	}

	if (DamageFontSize < 1) {
		DamageFontSize = 1;
	}
	if (DamageFontSize > 256) {
		DamageFontSize = 256;
	}

	HideStars = (HideStars != 0) ? 1 : 0;
	IncludeAlliance = (IncludeAlliance != 0) ? 1 : 0;
	Custom = (Custom != 0) ? 1 : 0;

	if (NameMode < NAME_MODE::MIN) {
		NameMode = NAME_MODE::ALL;
	}
	if (NameMode > NAME_MODE::MAX) {
		NameMode = NAME_MODE::ALL;
	}
}

int NameplateSettings::Init() {

	FontSize = 22;
	DamageFontSize = 22;
	HideStars = 0;
	IncludeAlliance = 0;
	Custom = 0;
	NameMode = NAME_MODE::ALL;

	return 0;
}

int NameplateSettings::Load(const wchar_t* basePath) {
	wchar_t path[UNICODE_MAX_PATH];
	StringCchPrintfW(path, UNICODE_MAX_PATH, L"%s\\nameplatew\\defaults.ini", basePath);

	// Before the first save, start from the settings of the plugin this one replaces
	if (GetFileAttributesW(path) == INVALID_FILE_ATTRIBUTES) {
		StringCchPrintfW(path, UNICODE_MAX_PATH, L"%s\\nameplate\\defaults.ini", basePath);
	}

	FontSize = GetPrivateProfileIntW(L"Settings", L"FontSizeInPx", 22, path);
	DamageFontSize = GetPrivateProfileIntW(L"Settings", L"DamageFontSizeInPx", 22, path);
	HideStars = GetPrivateProfileIntW(L"Settings", L"HideStars", 0, path);
	IncludeAlliance = GetPrivateProfileIntW(L"Settings", L"IncludeAlliance", 0, path);
	Custom = GetPrivateProfileIntW(L"Settings", L"Custom", 0, path);
	NameMode = static_cast<NAME_MODE>(GetPrivateProfileIntW(L"Settings", L"NameMode", static_cast<int>(NAME_MODE::ALL), path));

	Normalize();
	Flush();

	return 0;
}

int NameplateSettings::Save(const wchar_t* basePath) {
	wchar_t path[UNICODE_MAX_PATH];

	StringCchPrintfW(path, UNICODE_MAX_PATH, L"%s\\nameplatew", basePath);
	CreateDirectoryW(path, NULL);

	StringCchPrintfW(path, UNICODE_MAX_PATH, L"%s\\nameplatew\\defaults.ini", basePath);

	wchar_t buf[256];

	StringCbPrintfW(buf, sizeof(buf), L"%d", FontSize);
	WritePrivateProfileStringW(L"Settings", L"FontSizeInPx", buf, path);

	StringCbPrintfW(buf, sizeof(buf), L"%d", DamageFontSize);
	WritePrivateProfileStringW(L"Settings", L"DamageFontSizeInPx", buf, path);

	StringCbPrintfW(buf, sizeof(buf), L"%d", HideStars);
	WritePrivateProfileStringW(L"Settings", L"HideStars", buf, path);

	StringCbPrintfW(buf, sizeof(buf), L"%d", IncludeAlliance);
	WritePrivateProfileStringW(L"Settings", L"IncludeAlliance", buf, path);

	StringCbPrintfW(buf, sizeof(buf), L"%d", Custom);
	WritePrivateProfileStringW(L"Settings", L"Custom", buf, path);

	StringCbPrintfW(buf, sizeof(buf), L"%d", static_cast<int>(NameMode));
	WritePrivateProfileStringW(L"Settings", L"NameMode", buf, path);

	return 0;
}

static bool is_end(char c) {
	return (c == '\0');
}

static bool is_end(const char* cmd) {
	return is_end(*cmd);
}

static bool isspace_or_end(char c) {
	return isspace(c) || (c == '\0');
}

static void eat_space(const char*& cmd) {
	while (isspace(*cmd)) {
		cmd++;
	}
}

static bool eat_space_and_is_end(const char*& cmd) {
	eat_space(cmd);
	return is_end(cmd);
}

static bool token_match_and_advance(const char*& cmd, const char* token, size_t token_length) {
	if (_strnicmp(cmd, token, token_length) == 0) {
		if (isspace_or_end(cmd[token_length])) {
			cmd += token_length;
			return true;
		}
	}

	return false;
}

static bool eat_space_token_match_and_advance(const char*& cmd, const char* token, size_t token_length) {
	eat_space(cmd);

	if (_strnicmp(cmd, token, token_length) == 0) {
		if (isspace_or_end(cmd[token_length])) {
			cmd += token_length;
			return true;
		}
	}

	return false;
}

bool Nameplate::ParseCommand(const char* cmd, bool includesName) {
	if (includesName) {
		if (token_match_and_advance(cmd, "/nameplatew", nameplate_strlen("/nameplatew"))) {
			// skip
		} else if (token_match_and_advance(cmd, "//nameplatew", nameplate_strlen("//nameplatew"))) {
			// skip
		} else {
			return false;
		}
	}

	// help
	// load
	// save
	// fontsizeinpx <num>
	// damagefontsizeinpx <num>
	// hidestars
	// showstars
	// mode all
	// mode none
	// mode hideself
	// mode hidepc
	// mode hidepcparty
	// alliance on|off
	// custom on|off
	// whitelist add|remove <name>...
	// whitelist list|clear

	int ret = 0;

	if (eat_space_token_match_and_advance(cmd, "help", nameplate_strlen("help"))) {
		ShowMessage(MESSAGE::LONG_HELP);
	} else if (eat_space_token_match_and_advance(cmd, "load", nameplate_strlen("load"))) {
		if (eat_space_and_is_end(cmd)) {
			ret = LoadSettings();
			if (ret < 0) {
				ShowMessage(MESSAGE::LOAD_ERROR, ret);
			} else {
				Update();
			}
		} else {
			ShowMessage(MESSAGE::LOAD_COMMAND_ERROR);
		}
	} else if (eat_space_token_match_and_advance(cmd, "save", nameplate_strlen("save"))) {
		if (eat_space_and_is_end(cmd)) {
			ret = SaveSettings();
			if (ret < 0) {
				ShowMessage(MESSAGE::SAVE_ERROR, ret);
			}
		} else {
			ShowMessage(MESSAGE::SAVE_COMMAND_ERROR);
		}
	} else if (eat_space_token_match_and_advance(cmd, "fontsizeinpx", nameplate_strlen("fontsizeinpx"))
			|| eat_space_token_match_and_advance(cmd, "fontsize", nameplate_strlen("fontsize"))) {
		errno = 0;

		char* cmd_end = const_cast<char*>(cmd);

		unsigned long val = strtoul(cmd, &cmd_end, 10);

		cmd = cmd_end;

		if (val == 0 || val > 256 || errno != 0 || !eat_space_and_is_end(cmd)) {
			ShowMessage(MESSAGE::FONT_SIZE_COMMAND_ERROR);
		} else {
			Settings.SetFontSize(static_cast<int>(val));
			Settings.Flush();
			// update not necessary in this path
		}
	} else if (eat_space_token_match_and_advance(cmd, "damagefontsizeinpx", nameplate_strlen("damagefontsizeinpx"))
			|| eat_space_token_match_and_advance(cmd, "damagefontsize", nameplate_strlen("damagefontsize"))
			|| eat_space_token_match_and_advance(cmd, "dmgfontsize", nameplate_strlen("dmgfontsize"))) {
		errno = 0;

		char* cmd_end = const_cast<char*>(cmd);

		unsigned long val = strtoul(cmd, &cmd_end, 10);

		cmd = cmd_end;

		if (val == 0 || val > 256 || errno != 0 || !eat_space_and_is_end(cmd)) {
			ShowMessage(MESSAGE::DAMAGE_FONT_SIZE_COMMAND_ERROR);
		} else {
			Settings.SetDamageFontSize(static_cast<int>(val));
			Settings.Flush();
			// update not necessary in this path
		}
	} else if (eat_space_token_match_and_advance(cmd, "showstars", nameplate_strlen("showstars"))) {
		if (eat_space_and_is_end(cmd)) {
			Settings.SetHideStars(0);
			Settings.Flush();
			Update();
		} else {
			ShowMessage(MESSAGE::SHOW_STARS_COMMAND_ERROR);
		}
	} else if (eat_space_token_match_and_advance(cmd, "hidestars", nameplate_strlen("hidestars"))) {
		if (eat_space_and_is_end(cmd)) {
			Settings.SetHideStars(1);
			Settings.Flush();
			Update();
		} else {
			ShowMessage(MESSAGE::HIDE_STARS_COMMAND_ERROR);
		}
	} else if (eat_space_token_match_and_advance(cmd, "mode", nameplate_strlen("mode"))) {
		NAME_MODE NameMode = NAME_MODE::ALL;
		bool cmdError = false;

		if (eat_space_token_match_and_advance(cmd, "all", nameplate_strlen("all"))) {
			NameMode = NAME_MODE::ALL;
		} else if (eat_space_token_match_and_advance(cmd, "none", nameplate_strlen("none"))) {
			NameMode = NAME_MODE::NONE;
		} else if (eat_space_token_match_and_advance(cmd, "hideself", nameplate_strlen("hideself"))) {
			NameMode = NAME_MODE::HIDE_SELF;
		} else if (eat_space_token_match_and_advance(cmd, "hidepc", nameplate_strlen("hidepc"))) {
			NameMode = NAME_MODE::HIDE_PC;
		} else if (eat_space_token_match_and_advance(cmd, "hidepcself", nameplate_strlen("hidepcself"))) {
			NameMode = NAME_MODE::HIDE_PCSELF;
		} else if (eat_space_token_match_and_advance(cmd, "hidenpc", nameplate_strlen("hidenpc"))) {
			NameMode = NAME_MODE::HIDE_NPC;
		} else if (eat_space_token_match_and_advance(cmd, "hidenpcself", nameplate_strlen("hidenpcself"))) {
			NameMode = NAME_MODE::HIDE_NPCSELF;
		} else if (eat_space_token_match_and_advance(cmd, "hidepcparty", nameplate_strlen("hidepcparty"))) {
			NameMode = NAME_MODE::HIDE_PCPARTY;
		} else if (eat_space_token_match_and_advance(cmd, "hidepcpartyself", nameplate_strlen("hidepcpartyself"))) {
			NameMode = NAME_MODE::HIDE_PCPARTYSELF;
		} else {
			cmdError = true;
		}

		if (!cmdError && eat_space_and_is_end(cmd)) {
			Settings.SetNameMode(NameMode);
			Settings.Flush();
			// update not necessary in this path
		} else {
			ShowMessage(MESSAGE::MODE_COMMAND_ERROR);
		}
	} else if (eat_space_token_match_and_advance(cmd, "alliance", nameplate_strlen("alliance"))) {
		int includeAlliance = -1;

		if (eat_space_token_match_and_advance(cmd, "on", nameplate_strlen("on"))) {
			includeAlliance = 1;
		} else if (eat_space_token_match_and_advance(cmd, "off", nameplate_strlen("off"))) {
			includeAlliance = 0;
		}

		if (includeAlliance >= 0 && eat_space_and_is_end(cmd)) {
			Settings.SetIncludeAlliance(includeAlliance);
			Settings.Flush();
			// update not necessary in this path
		} else {
			ShowMessage(MESSAGE::ALLIANCE_COMMAND_ERROR);
		}
	} else if (eat_space_token_match_and_advance(cmd, "custom", nameplate_strlen("custom"))) {
		int custom = -1;

		if (eat_space_token_match_and_advance(cmd, "on", nameplate_strlen("on"))) {
			custom = 1;
		} else if (eat_space_token_match_and_advance(cmd, "off", nameplate_strlen("off"))) {
			custom = 0;
		}

		if (custom >= 0 && eat_space_and_is_end(cmd)) {
			Settings.SetCustom(custom);
			Settings.Flush();
			// update not necessary in this path

			if (custom != 0 && Custom.Hooked == 0) {
				Debug("Custom names are on, but this client's name drawing was not recognised: names are drawn as before.");
			}
		} else {
			ShowMessage(MESSAGE::CUSTOM_COMMAND_ERROR);
		}
	} else if (eat_space_token_match_and_advance(cmd, "whitelist", nameplate_strlen("whitelist"))
			|| eat_space_token_match_and_advance(cmd, "wl", nameplate_strlen("wl"))) {
		ParseWhitelistCommand(cmd);
	} else {
		ShowMessage(MESSAGE::SHORT_HELP);
	}

	return true;
}

// The next word of a command as a player name: first letter upper case, the rest lower.
// False at the end of the command, or for a word too long to be a name.
static bool next_name(const char*& cmd, char name[WHITELIST_NAME_SIZE], bool& tooLong) {
	tooLong = false;

	eat_space(cmd);
	if (is_end(cmd)) {
		return false;
	}

	size_t len = 0;
	while (!isspace_or_end(*cmd)) {
		if (len < WHITELIST_NAME_SIZE - 1) {
			unsigned char c = static_cast<unsigned char>(*cmd);
			name[len] = static_cast<char>((len == 0) ? toupper(c) : tolower(c));
		}
		len++;
		cmd++;
	}

	if (len > WHITELIST_NAME_SIZE - 1) {
		tooLong = true;
		return false;
	}

	name[len] = '\0';
	return true;
}

static void Sayf(Nameplate* plugin, const char* format, ...) {
	char buf[512];

	va_list args;
	va_start(args, format);
	StringCbVPrintfA(buf, sizeof(buf), format, args);
	va_end(args);

	plugin->Debug(buf);
}

void Nameplate::ParseWhitelistCommand(const char* cmd) {
	char name[WHITELIST_NAME_SIZE];
	bool tooLong = false;

	if (eat_space_token_match_and_advance(cmd, "add", nameplate_strlen("add"))) {
		int named = 0;
		bool changed = false;

		while (next_name(cmd, name, tooLong)) {
			named++;
			if (FindWhitelisted(name) >= 0) {
				Sayf(this, "%s is already on the whitelist.", name);
			} else if (Whitelist.Count >= WHITELIST_MAX) {
				Sayf(this, "The whitelist is full (%d names); %s was not added.", WHITELIST_MAX, name);
			} else {
				// the name is in place before the count says it is there to be read
				StringCbCopyA(Whitelist.Names[Whitelist.Count], WHITELIST_NAME_SIZE, name);
				Whitelist.Count++;
				changed = true;
				Sayf(this, "Added %s to the whitelist.", name);
			}
		}

		if (tooLong || named == 0) {
			ShowMessage(MESSAGE::WHITELIST_COMMAND_ERROR);
		}
		if (changed && SaveWhitelist() < 0) {
			Sayf(this, "The whitelist could not be saved.");
		}
	} else if (eat_space_token_match_and_advance(cmd, "remove", nameplate_strlen("remove"))
			|| eat_space_token_match_and_advance(cmd, "del", nameplate_strlen("del"))) {
		int named = 0;
		bool changed = false;

		while (next_name(cmd, name, tooLong)) {
			named++;
			int at = FindWhitelisted(name);
			if (at < 0) {
				Sayf(this, "%s is not on the whitelist.", name);
			} else {
				// close the gap, keeping the order the names were added in
				for (size_t i = static_cast<size_t>(at); i + 1 < Whitelist.Count; i++) {
					CopyMemory(Whitelist.Names[i], Whitelist.Names[i + 1], WHITELIST_NAME_SIZE);
				}
				Whitelist.Count--;
				changed = true;
				Sayf(this, "Removed %s from the whitelist.", name);
			}
		}

		if (tooLong || named == 0) {
			ShowMessage(MESSAGE::WHITELIST_COMMAND_ERROR);
		}
		if (changed && SaveWhitelist() < 0) {
			Sayf(this, "The whitelist could not be saved.");
		}
	} else if (eat_space_token_match_and_advance(cmd, "clear", nameplate_strlen("clear"))) {
		if (eat_space_and_is_end(cmd)) {
			size_t count = Whitelist.Count;
			Whitelist.Count = 0;
			if (SaveWhitelist() < 0) {
				Sayf(this, "The whitelist could not be saved.");
			} else {
				Sayf(this, "Removed all %u names from the whitelist.", static_cast<unsigned>(count));
			}
		} else {
			ShowMessage(MESSAGE::WHITELIST_COMMAND_ERROR);
		}
	} else if (eat_space_and_is_end(cmd) || eat_space_token_match_and_advance(cmd, "list", nameplate_strlen("list"))) {
		if (!eat_space_and_is_end(cmd)) {
			ShowMessage(MESSAGE::WHITELIST_COMMAND_ERROR);
		} else if (Whitelist.Count == 0) {
			Sayf(this, "The whitelist is empty.");
		} else {
			Sayf(this, "Whitelist (%u):", static_cast<unsigned>(Whitelist.Count));

			// a few names to a line
			char line[256];
			line[0] = '\0';
			for (size_t i = 0; i < Whitelist.Count; i++) {
				if (line[0] != '\0') {
					StringCbCatA(line, sizeof(line), ", ");
				}
				StringCbCatA(line, sizeof(line), Whitelist.Names[i]);
				if ((i + 1) % 8 == 0 || i + 1 == Whitelist.Count) {
					Sayf(this, "%s", line);
					line[0] = '\0';
				}
			}
		}
	} else {
		ShowMessage(MESSAGE::WHITELIST_COMMAND_ERROR);
	}
}

// One name to a line in config/nameplatew/whitelist.txt. A missing file is an empty whitelist.
int Nameplate::LoadWhitelist() {
	wchar_t basePath[UNICODE_MAX_PATH];
	if (!this->GetConfigPath(basePath)) {
		return -19;
	}

	wchar_t path[UNICODE_MAX_PATH];
	StringCchPrintfW(path, UNICODE_MAX_PATH, L"%s\\nameplatew\\whitelist.txt", basePath);

	Whitelist.Count = 0;

	FILE* file = _wfopen(path, L"r");
	if (file == nullptr) {
		return 0;
	}

	char line[256];
	while (fgets(line, sizeof(line), file) != nullptr) {
		const char* cmd = line;
		char name[WHITELIST_NAME_SIZE];
		bool tooLong = false;

		if (next_name(cmd, name, tooLong) && FindWhitelisted(name) < 0 && Whitelist.Count < WHITELIST_MAX) {
			StringCbCopyA(Whitelist.Names[Whitelist.Count], WHITELIST_NAME_SIZE, name);
			Whitelist.Count++;
		}
	}

	fclose(file);
	return 0;
}

int Nameplate::SaveWhitelist() {
	wchar_t basePath[UNICODE_MAX_PATH];
	if (!this->GetConfigPath(basePath)) {
		return -20;
	}

	wchar_t path[UNICODE_MAX_PATH];
	StringCchPrintfW(path, UNICODE_MAX_PATH, L"%s\\nameplatew", basePath);
	CreateDirectoryW(path, NULL);

	StringCchPrintfW(path, UNICODE_MAX_PATH, L"%s\\nameplatew\\whitelist.txt", basePath);

	FILE* file = _wfopen(path, L"w");
	if (file == nullptr) {
		return -21;
	}

	for (size_t i = 0; i < Whitelist.Count; i++) {
		fprintf(file, "%s\n", Whitelist.Names[i]);
	}

	fclose(file);
	return 0;
}

void Nameplate::Debug(const wchar_t* text) {
	char buf[1024];
	StringCbPrintfA(buf, sizeof(buf), "%ls", text);
	Debug(buf);
}

int Nameplate::Init() {
	ZeroMemory(&Globals, sizeof(Globals));

	// Configuration setup
	Settings.Init();
	LoadSettings();

	// GetFrameDelta
	uintptr_t pGetFrameDelta = (uintptr_t) getFrameDeltaSig.Find();
	if (pGetFrameDelta == 0) {
		return -4;
	}

	// offset into instruction accessing gGame
	uintptr_t pppObj = pGetFrameDelta + 2;

	// pointer to gGame
	uintptr_t ppObj = lsb32_i((uint8_t*) pppObj, 0);
	if (ppObj == 0) {
		return -5;
	}

	// note - some of these tests no longer make any sense, as the safe reads were removed

	// InitApplicationDefaults (for lack of a better name)
	uintptr_t pInitApplicationDefaults = (uintptr_t) initApplicationDefaultsSig.Find();
	if (pInitApplicationDefaults == 0) {
		return -6;
	}

	uintptr_t ppWindowWidth = pInitApplicationDefaults + 31;
	uintptr_t ppWindowHeight = pInitApplicationDefaults + 41;

	// pWindowWidth
	uintptr_t pWindowWidth = lsb32_i((uint8_t*) ppWindowWidth, 0);
	if (pWindowWidth == 0) {
		return -7;
	}

	// pWindowHeight
	uintptr_t pWindowHeight = lsb32_i((uint8_t*) ppWindowHeight, 0);
	if (pWindowHeight == 0) {
		return -8;
	}

	// GetPlayerEntity
	uintptr_t pGetPlayerEntity = (uintptr_t) getPlayerEntitySig.Find();
	if (pGetPlayerEntity == 0) {
		return -15;
	}

	uintptr_t ppPlayerEntityIndex = pGetPlayerEntity + 2;
	uintptr_t pPlayerEntityIndex = lsb32_i((uint8_t*) ppPlayerEntityIndex, 0);
	if (pPlayerEntityIndex == 0) {
		return -16;
	}

	// DrawName, patch location 0
	uintptr_t pDrawNamePatch0 = (uintptr_t) drawNamePatch0LocationSig.Find();
	if (pDrawNamePatch0 == 0) {
		return -9;
	}

	// DrawName, patch location 1 (useless mastery stars)
	uintptr_t pDrawNamePatch1 = (uintptr_t) drawNamePatch1LocationSig.Find();
	if (pDrawNamePatch1 == 0) {
		return -10;
	}

	// DrawName2 (mastery stars)
	uintptr_t pDrawName2Patch = (uintptr_t) drawName2PatchLocationSig.Find();
	if (pDrawName2Patch == 0) {
		return -11;
	}

	// DrawName3 (display mode)
	// either use the original or the new version, depending on what's found
	uintptr_t pDrawName3Patch = (uintptr_t) drawName3PatchLocationSig.Find();
	uintptr_t pDrawName3V2Patch = (uintptr_t) drawName3V2PatchLocationSig.Find();
	if (pDrawName3Patch == 0 && pDrawName3V2Patch == 0) {
		return -14;
	}

	uintptr_t ppNamesOff = (pDrawName3Patch != 0)
		? pDrawName3Patch + 1
		: pDrawName3V2Patch + 1;
	uintptr_t pNamesOff = lsb32_i((uint8_t*) ppNamesOff, 0);
	if (pNamesOff == 0) {
		return -17;
	}

	// DrawDamage
	uintptr_t pDrawDamagePatch = (uintptr_t) drawDamagePatchLocationSig.Find();
	if (pDrawDamagePatch == 0) {
		return -18;
	}

	uint8_t* pLoc;

	CopyMemory(&Globals.DrawNamePatch0Orig[0], reinterpret_cast<const void*> (pDrawNamePatch0), DRAWNAME_PATCH0_SIZE);
	CopyMemory(reinterpret_cast<void*> (pDrawNamePatch0), &DrawName_Patch0[0], DRAWNAME_PATCH0_SIZE);

	pLoc = reinterpret_cast<uint8_t*> (pDrawNamePatch0 + DRAWNAME_PATCH0_ADDRESS_LOCATION);
	pLoc[0] = (((uintptr_t) GetNameplateScale) >> 0) & 0xFF;
	pLoc[1] = (((uintptr_t) GetNameplateScale) >> 8) & 0xFF;
	pLoc[2] = (((uintptr_t) GetNameplateScale) >> 16) & 0xFF;
	pLoc[3] = (((uintptr_t) GetNameplateScale) >> 24) & 0xFF;

	CopyMemory(&Globals.DrawNamePatch1Orig[0], reinterpret_cast<const void*> (pDrawNamePatch1), DRAWNAME_PATCH1_SIZE);
	CopyMemory(reinterpret_cast<void*> (pDrawNamePatch1), &DrawName_Patch1[0], DRAWNAME_PATCH1_SIZE);

	pLoc = reinterpret_cast<uint8_t*> (pDrawNamePatch1 + DRAWNAME_PATCH1_ADDRESS_LOCATION);
	pLoc[0] = (((uintptr_t) GetNameplateScale) >> 0) & 0xFF;
	pLoc[1] = (((uintptr_t) GetNameplateScale) >> 8) & 0xFF;
	pLoc[2] = (((uintptr_t) GetNameplateScale) >> 16) & 0xFF;
	pLoc[3] = (((uintptr_t) GetNameplateScale) >> 24) & 0xFF;

	CopyMemory(&Globals.DrawName2PatchOrig[0], reinterpret_cast<const void*> (pDrawName2Patch), DRAWNAME2_PATCH_SIZE);

	pLoc = reinterpret_cast<uint8_t*> (pDrawName2Patch + DRAWNAME2_PATCH_ADDRESS_LOCATION);

	// Stick a JMP there.
	pLoc[0] = (AsmSettings.HideStars != 0) ? 0xEB : 0x75;

	if (pDrawName3Patch != 0) {
		CopyMemory(&Globals.DrawName3PatchOrig[0], reinterpret_cast<const void*> (pDrawName3Patch), DRAWNAME3_PATCH_SIZE);
		CopyMemory(reinterpret_cast<void*> (pDrawName3Patch), &DrawName3_Patch, DRAWNAME3_PATCH_SIZE);

		pLoc = reinterpret_cast<uint8_t*> (pDrawName3Patch + DRAWNAME3_PATCH_ADDRESS_LOCATION);
		pLoc[0] = (((uintptr_t) ShouldDrawNameplate) >> 0) & 0xFF;
		pLoc[1] = (((uintptr_t) ShouldDrawNameplate) >> 8) & 0xFF;
		pLoc[2] = (((uintptr_t) ShouldDrawNameplate) >> 16) & 0xFF;
		pLoc[3] = (((uintptr_t) ShouldDrawNameplate) >> 24) & 0xFF;
	}

	if (pDrawName3V2Patch != 0) {
		CopyMemory(&Globals.DrawName3V2PatchOrig[0], reinterpret_cast<const void*> (pDrawName3V2Patch), DRAWNAME3_V2_PATCH_SIZE);
		CopyMemory(reinterpret_cast<void*> (pDrawName3V2Patch), &DrawName3_V2_Patch, DRAWNAME3_V2_PATCH_SIZE);

		pLoc = reinterpret_cast<uint8_t*> (pDrawName3V2Patch + DRAWNAME3_V2_PATCH_ADDRESS_LOCATION);
		pLoc[0] = (((uintptr_t) ShouldDrawNameplate) >> 0) & 0xFF;
		pLoc[1] = (((uintptr_t) ShouldDrawNameplate) >> 8) & 0xFF;
		pLoc[2] = (((uintptr_t) ShouldDrawNameplate) >> 16) & 0xFF;
		pLoc[3] = (((uintptr_t) ShouldDrawNameplate) >> 24) & 0xFF;
	}

	CopyMemory(&Globals.DrawDamagePatchOrig[0], reinterpret_cast<const void*> (pDrawDamagePatch), DRAWDAMAGE_PATCH_SIZE);
	CopyMemory(reinterpret_cast<void*> (pDrawDamagePatch), &DrawDamage_Patch, DRAWDAMAGE_PATCH_SIZE);

	pLoc = reinterpret_cast<uint8_t*> (pDrawDamagePatch + DRAWDAMAGE_PATCH_CALL_ADDRESS_LOCATION);
	pLoc[0] = (((uintptr_t) GetDamageNumberScale) >> 0) & 0xFF;
	pLoc[1] = (((uintptr_t) GetDamageNumberScale) >> 8) & 0xFF;
	pLoc[2] = (((uintptr_t) GetDamageNumberScale) >> 16) & 0xFF;
	pLoc[3] = (((uintptr_t) GetDamageNumberScale) >> 24) & 0xFF;

	pLoc = reinterpret_cast<uint8_t*> (pDrawDamagePatch + DRAWDAMAGE_PATCH_COLOR_ADDRESS_LOCATION);
	const uint8_t* pOldLoc = &Globals.DrawDamagePatchOrig[DRAWDAMAGE_PATCH_OLD_COLOR_ADDRESS_LOCATION];
	pLoc[0] = pOldLoc[0];
	pLoc[1] = pOldLoc[1];
	pLoc[2] = pOldLoc[2];
	pLoc[3] = pOldLoc[3];

	Globals.pgGame = reinterpret_cast<CGame**> (ppObj);
	Globals.pWindowWidth = reinterpret_cast<uint32_t*> (pWindowWidth);
	Globals.pWindowHeight = reinterpret_cast<uint32_t*> (pWindowHeight);
	Globals.pPlayerEntityIndex = reinterpret_cast<uint16_t*> (pPlayerEntityIndex);
	Globals.pNamesOff = reinterpret_cast<bool*> (pNamesOff);

	Globals.DrawNamePatch0Addr = pDrawNamePatch0;
	Globals.DrawNamePatch1Addr = pDrawNamePatch1;
	Globals.DrawName2PatchAddr = pDrawName2Patch;
	Globals.DrawName3PatchAddr = pDrawName3Patch;
	Globals.DrawName3V2PatchAddr = pDrawName3V2Patch;
	Globals.DrawDamagePatchAddr = pDrawDamagePatch;

	// The calls that draw a name's two lines, for handing names to an addon. They are only known in
	// the V2 function, and only taken if both go where they are expected to; without them everything
	// else works as it did, and names are always drawn by the client.
	if (pDrawName3V2Patch != 0) {
		uintptr_t pLineCall = pDrawName3V2Patch + DRAWNAME_LINE_CALL_OFFSET;
		uintptr_t pLine2Call = pDrawName3V2Patch + DRAWNAME_LINE2_CALL_OFFSET;
		uintptr_t pLine = CallTarget(pLineCall);
		uintptr_t pLine2 = CallTarget(pLine2Call);

		if (IsDrawNameLine(pLine, DRAWNAME_LINE_RET_OFFSET, 0x14) && IsDrawNameLine(pLine2, DRAWNAME_LINE2_RET_OFFSET, 0x0C)) {
			Globals.DrawNameLineOrig = reinterpret_cast<DrawNameLineFn> (pLine);
			Globals.DrawNameLine2Orig = reinterpret_cast<DrawNameLine2Fn> (pLine2);
			Globals.DrawNameLineCallAddr = pLineCall;
			Globals.DrawNameLine2CallAddr = pLine2Call;

			SetCallTarget(pLineCall, reinterpret_cast<uintptr_t> (&DrawNameLine));
			SetCallTarget(pLine2Call, reinterpret_cast<uintptr_t> (&DrawNameLine2));

			Custom.Count = 0;
			Custom.Hooked = 1;
		}
	}

	Instance = this;

	return 0;
}

int Nameplate::Update() {
	if (Globals.DrawName2PatchAddr != 0) {
		uint8_t* pLoc;

		uintptr_t pDrawName2Patch = Globals.DrawName2PatchAddr;
		pLoc = reinterpret_cast<uint8_t*> (pDrawName2Patch + DRAWNAME2_PATCH_ADDRESS_LOCATION);

		// Stick a JMP there.
		pLoc[0] = (AsmSettings.HideStars != 0) ? 0xEB : 0x75;
	}

	return 0;
}

int Nameplate::LoadSettings() {

	wchar_t basePath[UNICODE_MAX_PATH];
	bool pathOk = this->GetConfigPath(basePath);

	int ret;

	if (pathOk) {
		ret = Settings.Load(basePath);
		if (ret < 0) {
			return ret;
		}
		ret = Settings.Save(basePath);
		if (ret < 0) {
			return ret;
		}
		ret = LoadWhitelist();
		if (ret < 0) {
			return ret;
		}
	} else {
		return -12;
	}

	return 0;
}

int Nameplate::SaveSettings() {
	wchar_t basePath[UNICODE_MAX_PATH];
	bool pathOk = this->GetConfigPath(basePath);

	int ret;

	if (pathOk) {
		ret = Settings.Save(basePath);
		if (ret < 0) {
			return ret;
		}
	} else {
		return -13;
	}

	return 0;
}

int Nameplate::Deinit() {

	Instance = nullptr;

	Custom.Hooked = 0;
	Custom.Consumer = 0;
	Custom.Count = 0;

	if (Globals.DrawNameLine2CallAddr != 0) {
		SetCallTarget(Globals.DrawNameLine2CallAddr, reinterpret_cast<uintptr_t> (Globals.DrawNameLine2Orig));
	}

	if (Globals.DrawNameLineCallAddr != 0) {
		SetCallTarget(Globals.DrawNameLineCallAddr, reinterpret_cast<uintptr_t> (Globals.DrawNameLineOrig));
	}

	if (Globals.DrawDamagePatchAddr != 0) {
		CopyMemory(reinterpret_cast<void*> (Globals.DrawDamagePatchAddr), &Globals.DrawDamagePatchOrig[0], DRAWDAMAGE_PATCH_SIZE);
	}

	if (Globals.DrawName3V2PatchAddr != 0) {
		CopyMemory(reinterpret_cast<void*> (Globals.DrawName3V2PatchAddr), &Globals.DrawName3V2PatchOrig[0], DRAWNAME3_V2_PATCH_SIZE);
	}

	if (Globals.DrawName3PatchAddr != 0) {
		CopyMemory(reinterpret_cast<void*> (Globals.DrawName3PatchAddr), &Globals.DrawName3PatchOrig[0], DRAWNAME3_PATCH_SIZE);
	}

	if (Globals.DrawName2PatchAddr != 0) {
		CopyMemory(reinterpret_cast<void*> (Globals.DrawName2PatchAddr), &Globals.DrawName2PatchOrig[0], DRAWNAME2_PATCH_SIZE);
	}

	if (Globals.DrawNamePatch1Addr != 0) {
		CopyMemory(reinterpret_cast<void*> (Globals.DrawNamePatch1Addr), &Globals.DrawNamePatch1Orig[0], DRAWNAME_PATCH1_SIZE);
	}

	if (Globals.DrawNamePatch0Addr != 0) {
		CopyMemory(reinterpret_cast<void*> (Globals.DrawNamePatch0Addr), &Globals.DrawNamePatch0Orig[0], DRAWNAME_PATCH0_SIZE);
	}

	ZeroMemory(&Globals, sizeof(Globals));

    return 0;
}
