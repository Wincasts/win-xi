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
#include <intrin.h>

#include "Nameplate.h"

#include "findsignature.h"
#include "CodePatch.h"

// No copyright is claimed on the following "fair use for interoperability" section.
/* Begin "fair use for interoperability" section */
#define GETFRAMEDELTA "8B0D????????D94128D81D????????DFE0F6C4057A07D905????????C3"
// The same accessor as TrueFPS leaves it: its first two bytes are a short jump to the padding after it,
// the operand that names gGame kept as it was
#define GETFRAMEDELTA_TRUEFPS "EB??????????D94128D81D????????DFE0F6C4057A07D905????????C3"
#define INITAPPLICATIONDEFAULTS "B90002000033C0890D????????890D????????B901000000A3????????C705????????80020000C705????????E0010000"
#define GETPLAYERENTITY "66A1????????6685C0740E0FBFC08B0485????????85C0750233C0C3"

#define DRAWNAME_PATCH0_LOCATION "E8????????25FFFF000089442410DB442410D80D????????D88C24E0060000D95C244CE8????????8BBC24DC06000025FFFF00008944241083C9FFDB44241033C0F2AED80D????????D88C24E0060000F7D14983F924894C2418D95C24507E09B924000000894C2418"
#define DRAWNAME_PATCH1_LOCATION "E8????????25FFFF000089442410DB442410D80D????????D88C24D4060000D95C2438E8????????25FFFF00008BAC24D0060000894424108BFDDB44241083C9FF33C0F2AED80D????????D88C24D4060000F7D14983F924"
#define DRAWNAME2_PATCH_LOCATION "6683B9B20000000075178B44240C8B4C2408"
#define DRAWNAME3_V2_PATCH_LOCATION "A0????????84C0747A8B7E7033C0A0????????83F804776BFF2485????????F74778000000FF755B8B168BCEFF92CC0000005F5E81C418010000C38B4F7881E1000000FF81F90000000175378B9720010000C1EA0DF6C201EBCC8B8720010000C1E80DA801EB1AF74778000000FF7513E8????????85C0740A8B48788B47783BC875A5"

#define DRAWDAMAGE_PATCH_LOCATION "A1????????8B88C80D0000E8????????8B5008A1????????8954240CDB44240CD84C2408D80D????????D95C24208B88C80D0000E8????????8B400C8B0D????????8944240C8BF1DB44240C8BD681E2FFFFFF00D84C240881FA80808000D80D????????D95C2424750E8B879401000081E6000000FF0BF0"
/* End "fair use for interoperability" section */


// The length of a signature's text at compile time, for the size of the patch it is
static constexpr size_t nameplate_strlen(const char* text) {
    size_t len = 0;
    while (text[len] != '\0') {
        ++len;
    }
    return len;
}

// A 32-bit operand of the client's code, as it lies: an address, little-endian
static uint32_t ReadOperand(uintptr_t at) {
    uint32_t value;
    memcpy(&value, reinterpret_cast<const void*> (at), sizeof(value));
    return value;
}

// A function's address written over the placeholder in a patch, byte by byte
static void WriteAddress(uint8_t* pLoc, const void* function) {
    const uint32_t address = static_cast<uint32_t>(reinterpret_cast<uintptr_t> (function));
    memcpy(pLoc, &address, sizeof(address));
}

// Every write to the client's code goes through here (CodePatch.h)
static CodePatches<WindowsCodeMemory> Patches;

// Set when an unload found a site something else had changed since, and so left it: this plugin's code
// may still be called from the client, so its module is pinned and it is never loaded again this run.
static bool Stranded = false;

static void Strand() {
	Stranded = true;
	HMODULE self = nullptr;
	GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
		reinterpret_cast<LPCWSTR> (&Stranded), &self);
}

static constexpr auto getFrameDeltaSig = MakeSig<GETFRAMEDELTA>();
static constexpr auto getFrameDeltaTrueFpsSig = MakeSig<GETFRAMEDELTA_TRUEFPS>();
static constexpr auto initApplicationDefaultsSig = MakeSig<INITAPPLICATIONDEFAULTS>();
static constexpr auto getPlayerEntitySig = MakeSig<GETPLAYERENTITY>();

static constexpr auto drawNamePatch0LocationSig = MakeSig<DRAWNAME_PATCH0_LOCATION>();
static constexpr auto drawNamePatch1LocationSig = MakeSig<DRAWNAME_PATCH1_LOCATION>();
static constexpr auto drawName2PatchLocationSig = MakeSig<DRAWNAME2_PATCH_LOCATION>();
static constexpr auto drawName3V2PatchLocationSig = MakeSig<DRAWNAME3_V2_PATCH_LOCATION>();
static constexpr auto drawDamagePatchLocationSig = MakeSig<DRAWDAMAGE_PATCH_LOCATION>();

static constexpr size_t DRAWNAME_PATCH0_SIZE = nameplate_strlen(DRAWNAME_PATCH0_LOCATION) / 2;
static constexpr size_t DRAWNAME_PATCH1_SIZE = nameplate_strlen(DRAWNAME_PATCH1_LOCATION) / 2;
static constexpr size_t DRAWNAME2_PATCH_SIZE = nameplate_strlen(DRAWNAME2_PATCH_LOCATION) / 2;
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
static_assert(DRAWNAME2_PATCH_ADDRESS_LOCATION < DRAWNAME2_PATCH_SIZE, "the jump is within what the signature matched");
static_assert(DRAWNAME_PATCH0_SIZE <= CODE_PATCH_BYTES_MAX && DRAWNAME_PATCH1_SIZE <= CODE_PATCH_BYTES_MAX
	&& DRAWNAME3_V2_PATCH_SIZE <= CODE_PATCH_BYTES_MAX && DRAWDAMAGE_PATCH_SIZE <= CODE_PATCH_BYTES_MAX, "each patch fits a site");

// Past the end of the DrawName3 V2 patch, in the same function, are the two calls that draw a name:
// its first line, the name itself, and its second, the Job Mastery stars. Each goes through a small
// function of the model that begins as DRAWNAME2_PATCH_LOCATION does and passes its arguments on.
// No custom assembly here either: the two calls are pointed at functions of this plugin.
#define DRAWNAME_LINE_CALL_OFFSET 0x104
#define DRAWNAME_LINE_RET_OFFSET 0x2B   // RET 0x14
#define DRAWNAME_LINE2_CALL_OFFSET 0x137
#define DRAWNAME_LINE2_RET_OFFSET 0x21  // RET 0x0C
#define DRAWNAME_STARS '\xD2'           // what the second line holds for a player with a job mastered

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
  0x00, 0x75, 0x0e, 0x8b, 0x87, 0x94, 0x01, 0x00, 0x00, 0x81, 0xe6, 0x00,
  0x00, 0x00, 0xff, 0x09, 0xc6, 0x51, 0x8d, 0x44, 0x24, 0x0c, 0x50, 0x8d,
  0x44, 0x24, 0x28, 0x50, 0x8d, 0x44, 0x24, 0x20, 0x50, 0x89, 0xf9, 0x89,
  0xf2, 0xb8, 0x78, 0x56, 0x34, 0x12, 0xff, 0xd0, 0x59, 0x84, 0xc0, 0x0f,
  0x84, 0x55, 0x00, 0x00, 0x00, 0xeb, 0x1d, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
  0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90
};

#define DRAWDAMAGE_PATCH_CALL_ADDRESS_LOCATION 0x09
#define DRAWDAMAGE_PATCH_COLOR_ADDRESS_LOCATION 0x11
#define DRAWDAMAGE_PATCH_OLD_COLOR_ADDRESS_LOCATION 0x3E
// Where the popup is handed to the plugin, and the address of the function it is handed to. Without the
// client's code around the patch as expected, a short jump past it is written there in its place.
#define DRAWDAMAGE_PATCH_POPUP_LOCATION 0x35
#define DRAWDAMAGE_PATCH_POPUP_ADDRESS_LOCATION 0x4A
static constexpr uint8_t DrawDamage_PopupSkip[2] = { 0xEB, DRAWDAMAGE_PATCH_SIZE - DRAWDAMAGE_PATCH_POPUP_LOCATION - 2 };
// What the patch counts on outside itself: the point the popup is drawn at put in [esp+0x14] before it
// (from 0x37 bytes before), and the function's end, which a claimed popup jumps to, 0xAE after its start
#define DRAWDAMAGE_POSITION_OFFSET 0x37
static constexpr uint8_t DrawDamage_Position[] = {
  0x8b, 0x08, 0x89, 0x4c, 0x24, 0x14, 0x8b, 0x50, 0x04, 0x89, 0x54, 0x24,
  0x18, 0x8b, 0x40, 0x08, 0x8d, 0x4c, 0x24, 0x10, 0x89, 0x44, 0x24, 0x1c
};
#define DRAWDAMAGE_END_OFFSET 0xAE
static constexpr uint8_t DrawDamage_End[] = { 0x5f, 0x5e, 0x83, 0xc4, 0x40, 0xc3 };

#define LINE_CALLS_MAX 8
static_assert(5 + 2 * LINE_CALLS_MAX <= CODE_PATCH_SITES_MAX, "the five patches and every call fit");

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

	// Whether the patches are in, and which of Patches' sites is the jump that hides the stars
	bool Patched;
	int StarsSite;

	// The calls that draw a name's lines, and the client's functions they called before. The first of
	// each is the one in the function that draws every name; the rest are whatever else in the client
	// calls the same functions, which draws a name by another way (the one under the cursor, for one).
	uintptr_t DrawNameLineCalls[LINE_CALLS_MAX];
	uintptr_t DrawNameLine2Calls[LINE_CALLS_MAX];
	int DrawNameLineSites[LINE_CALLS_MAX];   // each call's site in Patches
	int DrawNameLine2Sites[LINE_CALLS_MAX];
	size_t DrawNameLineCallCount;
	size_t DrawNameLine2CallCount;
	bool OtherCallsTaken;
	DrawNameLineFn DrawNameLineOrig;
	DrawNameLine2Fn DrawNameLine2Orig;

	// Lines drawn this frame that were nobody's, and so the client's to draw as it would: and last frame
	uint32_t Unowned;
	uint32_t UnownedLast;

	// First lines this frame of a name already drawn this frame, which are not listed again or drawn
	// for an addon again: all of them, and those of them from the call that draws all the names; and
	// the same of last frame
	uint32_t Repeats;
	uint32_t RepeatsMain;
	uint32_t RepeatsLast;
	uint32_t RepeatsMainLast;

	// Names taken from a lower line and drawn where the higher was: this frame, and last
	uint32_t Lifted;
	uint32_t LiftedLast;

	// Which way up is along the world's second axis, 1 or -1, as the view last had it: 0 until known
	float WorldUp;

	// The model whose first line was last seen, where in the list its name was put (if it was), and
	// whether the client drew it: its second line follows at once, and goes the same way
	const XiModel* pLineModel;
	HookName* pLineName;
	bool LineDrawn;
} Globals;

// The sizes and the stars, as the client's patched code reads them
static struct {
	int FontSize;
	int DamageFontSize;
	int HideStars;
} AsmSettings;

// The plugin that is asked about entities while names are drawn; set while the patches are in place.
static Nameplate* Instance = nullptr;

// What addons read and write. The names in it are those of the last frame, whole: the frame being
// drawn is gathered apart, in Filling, and copied here by Publish.
extern "C" {
__declspec(dllexport) HookCapabilities NamehookCapabilities = {
    "NAMEHOOKCAPS", sizeof(HookCapabilities), 1,
    FEATURE_EDGE_RADIUS | FEATURE_SOFT_RECT | FEATURE_TIGHT_EDGE | FEATURE_DOUBLED | FEATURE_SOFT_TEXTURE | FEATURE_TEXTURES_32,
    NAMEHOOK_VERSION_MAJOR * 100 + NAMEHOOK_VERSION_MINOR
};
}

static HookShared Shared = { "NAMEHOOK", HOOK_VERSION, sizeof(HookShared), sizeof(HookName), 0, 0, 0, 0, 0, 0, 0, 0.0f, 0.0f, 0, 0, 0.0f, 0.0f, 0, {}, {}, 0, 0, 0 };

static struct {
	uint32_t Count;
	HookName Names[HOOK_NAMES_MAX];
	uint32_t Dropped; // names this frame that Names had no room for

	bool Changed;    // a name has been added, or touched, since the names were last made ready
	bool Published;  // the names have been made ready this frame
} Filling;

// What an addon has drawn of the names, for the plugin to put in the picture. Kept apart from Shared,
// which is in the DLL's file: this is large, and empty until an addon fills it.
static HookDraw Draw;
static HookBubbles Bubbles = { "NAMEBUBBLES", 2, sizeof(HookBubbles), sizeof(HookDraw), {}, {} };
static HookPopups Popups = { "NAMEHOOKPOPUPS", 1, sizeof(HookPopups), sizeof(HookPopup), 0, 0, 0, 0, 0, 0, 0, {} };
// The claim slots and their drawings, for addons drawing names besides HookShared's (HookClaims)
static HookDraw SlotDraws[HOOK_CLAIM_SLOTS];
static HookClaims Claims = { "NAMEHOOKCLAIMS", 1, sizeof(HookClaims), sizeof(HookClaimSlot), HOOK_CLAIM_SLOTS, HOOK_CLAIM_PRIORITY, {}, {} };
static HookCamera Camera = { "NAMEHOOKCAMERA", 1, sizeof(HookCamera), 0, 0, {}, {}, {}, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
static HookPopupDraw PopupDraw;

// The frame whose first name has been seen, so that what is done once a frame is done then
static uint32_t NamesFrame = 0xFFFFFFFF;

// The client can draw one entity's name more than once in a frame: from the call that draws all the
// names and from one of its others, or from the first twice over (a player fishing is one, over the
// head and lower down). The name is listed, and drawn for an addon, once: from the call that draws all
// the names where it draws it, and otherwise the first time at all. Where that call draws it more than
// once, it is the highest of them that is taken, and not the first: the client draws them in an order
// that changes as the camera moves. A name is drawn for an addon as the client draws it, before the
// rest are known, so the first of them is taken whatever its height, and one in the lower half of the
// last frame that had more than one, within LIFT_TIME, is drawn where the highest was: lifted by
// how far the highest was from the lowest, with the highest's size and colours. Waiting for the
// higher let the name vanish when it did not come, as the count changed from frame to frame; and
// taking a lower as it was had the name jump. Frames are kept as Shared.Frame + 1, so that 0 is never.
#define LIFT_TIME 500000 // microseconds: half a second
#define SEEN_NONE 0xFFFF
static struct {
	uint32_t Frame;     // the frame its name was first drawn in
	uint32_t MainFrame; // and drawn by the call that draws all the names in
	uint64_t MainTime;  // when MainFrame began
	uint16_t Slot;      // where it is in Filling, or SEEN_NONE
	bool Main;          // whether that was by the call that draws all the names
	uint16_t MainCount; // how many times that call drew it in MainFrame
	uint16_t MainCountLast; // and in the frame before, if it drew it then
	float Low, High;    // how high the lowest and the highest of those were in MainFrame
	float LowAt[3], HighAt[3]; // and where they were
	uint32_t HighScale, HighNameColor, HighIconColor; // the highest's size and colours
	uint32_t MultiFrame; // the last frame that call drew it more than once in, or 0
	uint64_t MultiTime;  // and when that frame began
	float Middle;       // halfway between the lowest and highest of MultiFrame
	float Lift[3];      // from its lowest to its highest
	uint32_t LiftScale, LiftNameColor, LiftIconColor; // its highest's size and colours
} Seen[HOOK_ENTITIES];

// The party, the target and the pets, as they were when the frame began
static FrameFacts Facts;

// Set by the probe command: the next name drawn has the plugin's host say what it is drawn on
static bool ProbeWanted = false;

// Whether every call of the client's to its name drawing is taken, or only the one that draws all the
// names: kept with the settings
static int OtherCalls = 1;

// Whether the device's state is captured once for a run of names an addon has drawn, and not before
// each: kept with the settings
static int KeepStates = 1;

bool Nameplate::KeepsStates() const {
	return KeepStates != 0;
}

// Players whose names are drawn in every mode that hides players.
#define WHITELIST_MAX 512
#define WHITELIST_NAME_SIZE 24
#define WHITELIST_SLOTS (WHITELIST_MAX * 2) // at most half full; power of two

static struct {
	size_t Count;
	char Names[WHITELIST_MAX][WHITELIST_NAME_SIZE];
	// a number made from each name, without regard to case: every player's name is looked for here
	// every frame, and a name is only compared with those whose number is its own
	uint32_t Hashes[WHITELIST_MAX];
	// Lookup slots hold the original list index + 1, preserving display/save order.
	uint32_t Slots[WHITELIST_SLOTS];
	size_t IndexedCount;
	bool IndexDirty;
} Whitelist;

static uint32_t HashName(const char* name) {
	uint32_t hash = 2166136261u;
	for (size_t i = 0; i < WHITELIST_NAME_SIZE && name[i] != '\0'; i++) {
		hash = (hash ^ static_cast<uint32_t>(tolower(static_cast<unsigned char>(name[i])))) * 16777619u;
	}
	return hash;
}

static void IndexWhitelistName(size_t index) {
	size_t slot = Whitelist.Hashes[index] & (WHITELIST_SLOTS - 1);
	while (Whitelist.Slots[slot] != 0) {
		slot = (slot + 1) & (WHITELIST_SLOTS - 1);
	}
	Whitelist.Slots[slot] = static_cast<uint32_t>(index + 1);
}

static void EnsureWhitelistIndex() {
	if (!Whitelist.IndexDirty && Whitelist.IndexedCount == Whitelist.Count) { return; }
	ZeroMemory(Whitelist.Slots, sizeof(Whitelist.Slots));
	for (size_t i = 0; i < Whitelist.Count; i++) { IndexWhitelistName(i); }
	Whitelist.IndexedCount = Whitelist.Count;
	Whitelist.IndexDirty = false;
}

static int FindWhitelisted(const char* name) {
	if (Whitelist.Count == 0) { return -1; }
	EnsureWhitelistIndex();
	const uint32_t hash = HashName(name);
	size_t slot = hash & (WHITELIST_SLOTS - 1);
	for (size_t probes = 0; probes < WHITELIST_SLOTS; probes++) {
		if (Whitelist.Slots[slot] == 0) { return -1; }
		const size_t index = Whitelist.Slots[slot] - 1;
		if (Whitelist.Hashes[index] == hash && _strnicmp(name, Whitelist.Names[index], WHITELIST_NAME_SIZE) == 0) {
			return static_cast<int>(index);
		}
		slot = (slot + 1) & (WHITELIST_SLOTS - 1);
	}
	return -1;
}

// The name is in place before the count says it is there to be read.
// Insertion updates the index directly; loading a list is not repeatedly rehashed.
static void AddWhitelisted(const char* name) {
	if (Whitelist.Count >= WHITELIST_MAX) { return; }
	EnsureWhitelistIndex();
	const size_t index = Whitelist.Count;
	StringCbCopyA(Whitelist.Names[index], WHITELIST_NAME_SIZE, name);
	Whitelist.Hashes[index] = HashName(Whitelist.Names[index]);
	Whitelist.Count++;
	IndexWhitelistName(index);
	Whitelist.IndexedCount = Whitelist.Count;
}

static bool IsAmong(uint32_t serverId, const uint32_t* ids, size_t count) {
	for (size_t i = 0; i < count; i++) {
		if (ids[i] == serverId) {
			return true;
		}
	}
	return false;
}

// The category of what a name is over. flags is given what is learnt of the name on the way.
static uint32_t Classify(const Entity* pEntity, uint32_t& flags) {
	const uint32_t index = pEntity->EntityIndex;
	const uint32_t id = pEntity->EntityId;

	if (Facts.TargetIndex != 0 && index == Facts.TargetIndex) {
		flags |= NAME_TARGET;
	}

	if (Globals.pPlayerEntityIndex != nullptr && index == *Globals.pPlayerEntityIndex) {
		return CATEGORY_SELF;
	}

	const bool isPlayer = (id & 0xFF000000) == 0;

	// attackable (charmed)
	if (isPlayer && ((pEntity->Flags0 >> 13) & 1) != 0) {
		flags |= NAME_CHARMED;
		return CATEGORY_MONSTER;
	}

	if (!isPlayer && Facts.PetIndex != 0 && index == Facts.PetIndex) {
		return CATEGORY_MY_PET;
	}

	// a trust is of the party it is in
	if (id != 0 && IsAmong(id, Facts.PartyIds, 6)) {
		return CATEGORY_PARTY;
	}
	if (id != 0 && IsAmong(id, Facts.AllianceIds, 12)) {
		return CATEGORY_ALLIANCE;
	}

	if (isPlayer) {
		return CATEGORY_PLAYER;
	}

	if (index < HOOK_ENTITIES && (Facts.Pets[index / 8] & (1 << (index % 8))) != 0) {
		return CATEGORY_PET;
	}

	if (Instance != nullptr && (Instance->GetSpawnFlags(index) & 0x10) != 0) {
		return CATEGORY_MONSTER;
	}

	return CATEGORY_NPC;
}

// Whether a name of this category is to be seen: by an addon's word on the entity, the whitelist and
// the target, and failing those by whether its category is hidden.
static bool IsWanted(const Entity* pEntity, uint32_t category, uint32_t& flags) {
	const uint32_t index = pEntity->EntityIndex;

	if (index < HOOK_ENTITIES && Shared.Override[index] != OVERRIDE_NONE) {
		flags |= NAME_OVERRIDDEN;
		return Shared.Override[index] == OVERRIDE_SHOW;
	}

	if ((category & (CATEGORY_PARTY | CATEGORY_ALLIANCE | CATEGORY_PLAYER)) != 0
			&& Whitelist.Count != 0 && FindWhitelisted(pEntity->Name) >= 0) {
		flags |= NAME_WHITELISTED;
		return true;
	}

	// the target is shown whatever it is, but for the local player: a name hidden as their own stays
	// hidden while they have themselves targeted
	if ((flags & NAME_TARGET) != 0 && (Shared.Options & OPTION_ALWAYS_TARGET) != 0 && category != CATEGORY_SELF) {
		return true;
	}

	return (Shared.Hidden & category) == 0;
}

// The time, in microseconds, by the system's steady clock. What lasts a while is timed by it and not
// by frames, which come two and a half times as often at 144 a second as at 60.
static uint64_t SteadyMicroseconds() {
	static LARGE_INTEGER frequency = {};
	if (frequency.QuadPart == 0) {
		QueryPerformanceFrequency(&frequency);
	}
	LARGE_INTEGER count;
	QueryPerformanceCounter(&count);
	const uint64_t ticks = static_cast<uint64_t>(count.QuadPart), rate = static_cast<uint64_t>(frequency.QuadPart);
	return ticks / rate * 1000000 + ticks % rate * 1000000 / rate;
}
static uint64_t (*Clock)() = SteadyMicroseconds;
static uint64_t FrameTime = 0; // when the frame being drawn began, by Clock

// The claim last seen made, and when
static uint32_t ClaimSeen = 0xFFFFFFFF;
static uint64_t ClaimTime = 0;

static void NoteClaim() {
	if (Shared.ClaimFrame != ClaimSeen) {
		ClaimSeen = Shared.ClaimFrame;
		ClaimTime = FrameTime;
	}
}

// Whether an addon is drawing this category's names itself. A claim has to be made again every frame
// or so: an addon that stops without a word costs half a second without names, and no more.
static bool IsClaimed(uint32_t category) {
	NoteClaim();
	return (Shared.Claimed & category) != 0 && FrameTime - ClaimTime <= HOOK_CLAIM_TIME;
}

// Each slot's claim last seen made, by whom, and when; as ClaimSeen and ClaimTime are HookShared's
static uint32_t SlotClaimSeen[HOOK_CLAIM_SLOTS] = { 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF };
static uint32_t SlotOwnerSeen[HOOK_CLAIM_SLOTS] = {};
static uint64_t SlotClaimTime[HOOK_CLAIM_SLOTS] = {};

static void NoteSlotClaims() {
	for (uint32_t i = 0; i < HOOK_CLAIM_SLOTS; i++) {
		const HookClaimSlot& slot = Claims.Slots[i];
		if (slot.ClaimFrame != SlotClaimSeen[i] || slot.Owner != SlotOwnerSeen[i]) {
			SlotClaimSeen[i] = slot.ClaimFrame;
			SlotOwnerSeen[i] = slot.Owner;
			SlotClaimTime[i] = FrameTime;
		}
	}
}

// Whether slot i's owner draws this category's names itself
static bool SlotClaims(uint32_t i, uint32_t category) {
	const HookClaimSlot& slot = Claims.Slots[i];
	return slot.Owner != 0 && (slot.Categories & category) != 0 && FrameTime - SlotClaimTime[i] <= HOOK_CLAIM_TIME;
}

// Whether anybody, HookShared's claim or a slot's, draws this category's names itself
static bool AnyClaims(uint32_t category) {
	if (IsClaimed(category)) {
		return true;
	}
	NoteSlotClaims();
	for (uint32_t i = 0; i < HOOK_CLAIM_SLOTS; i++) {
		if (SlotClaims(i, category)) {
			return true;
		}
	}
	return false;
}

// The claims in the order a name is offered to them this frame: by priority, highest first, HookShared's
// own (0) before a slot of the same; a slot is 1 + its index
static uint32_t ClaimOrder[1 + HOOK_CLAIM_SLOTS];

static void OrderClaims() {
	for (uint32_t i = 0; i <= HOOK_CLAIM_SLOTS; i++) {
		ClaimOrder[i] = i;
	}
	auto priority = [](uint32_t owner) { return owner == 0 ? static_cast<uint32_t>(HOOK_CLAIM_PRIORITY) : Claims.Slots[owner - 1].Priority; };
	for (uint32_t i = 1; i <= HOOK_CLAIM_SLOTS; i++) {
		for (uint32_t j = i; j > 0 && priority(ClaimOrder[j]) > priority(ClaimOrder[j - 1]); j--) {
			const uint32_t t = ClaimOrder[j]; ClaimOrder[j] = ClaimOrder[j - 1]; ClaimOrder[j - 1] = t;
		}
	}
}

// Slots whose claim has lapsed are freed for another addon to take
static void FreeLapsedSlots() {
	NoteSlotClaims();
	for (uint32_t i = 0; i < HOOK_CLAIM_SLOTS; i++) {
		HookClaimSlot& slot = Claims.Slots[i];
		if (slot.Owner != 0 && FrameTime - SlotClaimTime[i] > HOOK_CLAIM_TIME) {
			slot.Owner = 0;
			slot.Categories = 0;
			SlotDraws[i].QuadCount = 0;
		}
	}
}

// Whether an addon has drawn names lately enough for them to be the ones to draw
static bool IsDrawFresh() {
	return Shared.Frame - Draw.Frame <= HOOK_DRAW_FRAMES;
}

// What an addon has drawn for this entity's name this frame, or null
static const HookDrawing* FindDrawing(uint32_t entityIndex, const HookDraw& draw = Draw) {
	if (entityIndex >= HOOK_ENTITIES || Shared.Frame - draw.Frame > HOOK_DRAW_FRAMES || draw.QuadCount > HOOK_QUADS_MAX) {
		return nullptr;
	}

	const HookDrawing& drawing = draw.Entities[entityIndex];
	if (drawing.Frame != draw.Frame || drawing.Count == 0) {
		return nullptr;
	}
	if (drawing.Count > HOOK_QUADS_PER_NAME || drawing.First > draw.QuadCount || drawing.Count > draw.QuadCount - drawing.First) {
		Shared.DrawingsRefused++; // drawn this frame, but not as it can be drawn
		return nullptr;
	}

	return &drawing;
}

// A name's first line, from the call at site. The name is put on the list for addons, hidden or not,
// and drawn by the client if it is wanted and no addon has claimed it. A name drawn again in the same
// frame is drawn by the client as it would be, if it is the client's to draw, and is otherwise passed
// over: see Seen.
static void DrawNameLineFrom(uintptr_t site, const XiModel* pModel, const float* pPosition, const char* text, uint32_t scale, uint32_t nameColor, uint32_t iconColor) {
	Globals.pLineModel = nullptr;
	Globals.pLineName = nullptr;
	Globals.LineDrawn = true;

	if (NamesFrame != Shared.Frame && Instance != nullptr) {
		NamesFrame = Shared.Frame;
		Instance->BeginBubbles(Bubbles.Draw, Bubbles.Draw.QuadCount > 0 && Bubbles.Draw.QuadCount <= HOOK_QUADS_MAX
			&& Shared.Frame - Bubbles.Draw.Frame <= HOOK_DRAW_FRAMES);
		OrderClaims();
		NoteSlotClaims();
		for (uint32_t i = 0; i < HOOK_CLAIM_SLOTS; i++) {
			Instance->BeginSlot(i, SlotDraws[i], SlotClaims(i, CATEGORY_ALL) && Shared.Frame - SlotDraws[i].Frame <= HOOK_DRAW_FRAMES);
		}
		Instance->BeginNames(Draw, IsDrawFresh(), Shared.TargetWidth, Shared.TargetHeight, Shared.FontTexture);
	}

	if (ProbeWanted && Instance != nullptr) {
		ProbeWanted = false;
		Instance->ProbeScene();
	}

	if (pModel != nullptr && pModel->pEntity != nullptr) {
		const Entity* pEntity = pModel->pEntity;

		// whether this entity's name has been drawn already this frame, or is drawn by the call that
		// draws all the names and so is to be taken from there: that call drew it last frame
		const uint32_t index = pEntity->EntityIndex;
		const uint32_t now = Shared.Frame + 1;
		const bool main = site != 0 && site == Globals.DrawNameLineCalls[0];
		bool repeat = false;
		bool replace = false;
		// where the name is drawn and listed, and how: as the client has it, unless lifted
		const float* at = pPosition;
		float lifted[3];
		uint32_t atScale = scale, atNameColor = nameColor, atIconColor = iconColor;
		if (index < HOOK_ENTITIES) {
			auto& seen = Seen[index];
			if (main) {
				const float height = (pPosition != nullptr) ? pPosition[1] * Globals.WorldUp : 0.0f;
				if (seen.MainFrame != now) {
					const bool last = seen.MainFrame == now - 1;
					seen.MainCountLast = last ? seen.MainCount : 0;
					// the frame before had more than one: what is lifted by is taken from it
					if (last && seen.MainCount > 1) {
						seen.MultiFrame = seen.MainFrame;
						seen.MultiTime = seen.MainTime;
						seen.Middle = (seen.Low + seen.High) * 0.5f;
						for (int i = 0; i < 3; i++) {
							seen.Lift[i] = seen.HighAt[i] - seen.LowAt[i];
						}
						seen.LiftScale = seen.HighScale;
						seen.LiftNameColor = seen.HighNameColor;
						seen.LiftIconColor = seen.HighIconColor;
					}
					seen.MainCount = 0;
					seen.MainFrame = now;
					seen.MainTime = FrameTime;
				}
				seen.MainCount++;
				if (pPosition != nullptr && (seen.MainCount == 1 || height < seen.Low)) {
					seen.Low = height;
					memcpy(seen.LowAt, pPosition, sizeof(seen.LowAt));
				}
				if (pPosition != nullptr && (seen.MainCount == 1 || height > seen.High)) {
					seen.High = height;
					memcpy(seen.HighAt, pPosition, sizeof(seen.HighAt));
					seen.HighScale = scale;
					seen.HighNameColor = nameColor;
					seen.HighIconColor = iconColor;
				}

				if (seen.Frame == now && seen.Main) {
					repeat = true; // taken already
				} else {
					// it takes the place of another call's, if that came first
					replace = seen.Frame == now;
					// a lower one, while the name has lately been drawn higher too: drawn there
					if (pPosition != nullptr && seen.MultiFrame != 0 && FrameTime - seen.MultiTime <= LIFT_TIME && height < seen.Middle) {
						for (int i = 0; i < 3; i++) {
							lifted[i] = pPosition[i] + seen.Lift[i];
						}
						at = lifted;
						atScale = seen.LiftScale;
						atNameColor = seen.LiftNameColor;
						atIconColor = seen.LiftIconColor;
						Globals.Lifted++;
					}
				}
			} else if (seen.Frame == now || seen.MainFrame == now || seen.MainFrame == now - 1) {
				repeat = true;
			}
			if (repeat) {
				Globals.Repeats++;
				if (main) {
					Globals.RepeatsMain++;
				}
			} else {
				if (!replace) {
					seen.Slot = SEEN_NONE;
				}
				seen.Frame = now;
				seen.Main = main;
			}
		}

		uint32_t flags = 0;
		const uint32_t category = Classify(pEntity, flags);
		if (IsWanted(pEntity, category, flags)) {
			flags |= NAME_WANTED;
			if (!AnyClaims(category)) {
				flags |= NAME_DRAWN;
			} else if (!repeat && at != nullptr && Instance != nullptr) {
				// claimed by an addon: the first claiming it, by priority, that has drawn the name has it put
				// where the client's would be
				for (uint32_t k = 0; k <= HOOK_CLAIM_SLOTS; k++) {
					const uint32_t owner = ClaimOrder[k];
					if (owner == 0 ? !IsClaimed(category) : !SlotClaims(owner - 1, category)) {
						continue;
					}
					const HookDraw& draw = owner == 0 ? Draw : SlotDraws[owner - 1];
					const HookDrawing* pDrawing = FindDrawing(pEntity->EntityIndex, draw);
					if (pDrawing != nullptr) {
						Instance->DrawCustom(owner, pEntity->EntityIndex, *pDrawing, &draw.Quads[pDrawing->First], at);
						flags |= NAME_CUSTOM;
						break;
					}
				}
			}
		}

		// Additive layer, independent of visibility and claims of the underlying name.
		if (!repeat && at != nullptr && Instance != nullptr && index < HOOK_ENTITIES
				&& Bubbles.ServerIds[index] == pEntity->EntityId) {
			const HookDrawing* bubble = FindDrawing(index, Bubbles.Draw);
			if (bubble != nullptr) {
				Instance->DrawBubble(index, *bubble, &Bubbles.Draw.Quads[bubble->First], at);
			}
		}

		HookName* pName = nullptr;
		if (repeat) {
			// not listed again
		} else if (replace && Seen[index].Slot != SEEN_NONE && pPosition != nullptr) {
			pName = &Filling.Names[Seen[index].Slot];
			Filling.Changed = true;
		} else if (pPosition != nullptr && Filling.Count < HOOK_NAMES_MAX) {
			if (index < HOOK_ENTITIES) {
				Seen[index].Slot = static_cast<uint16_t>(Filling.Count);
			}
			pName = &Filling.Names[Filling.Count];
			Filling.Count++;
			Filling.Changed = true;
		} else if (pPosition != nullptr) {
			Filling.Dropped++;
		}

		if (pName != nullptr) {
			ZeroMemory(pName, sizeof(HookName));
			pName->EntityIndex = pEntity->EntityIndex;
			pName->ServerId = pEntity->EntityId;
			pName->Category = category;
			pName->Flags = flags;
			pName->X = at[0];
			pName->Y = at[1];
			pName->Z = at[2];
			memcpy(&pName->Scale, &atScale, sizeof(pName->Scale));
			pName->NameColor = atNameColor;
			pName->IconColor = atIconColor;

			for (size_t i = 0; i < HOOK_NAME_SIZE - 1 && pEntity->Name[i] != '\0'; i++) {
				pName->Name[i] = pEntity->Name[i];
			}
			if (text != nullptr) {
				for (size_t i = 0; i < HOOK_TEXT_SIZE - 1 && text[i] != '\0'; i++) {
					pName->Text[i] = text[i];
				}
			}
		}

		Globals.pLineModel = pModel;
		Globals.pLineName = pName;
		Globals.LineDrawn = (flags & NAME_DRAWN) != 0;
	} else {
		Globals.Unowned++;
	}

	if (Globals.LineDrawn && Globals.DrawNameLineOrig != nullptr) {
		Globals.DrawNameLineOrig(pModel, nullptr, pPosition, text, scale, nameColor, iconColor);
		if (Instance != nullptr) {
			Instance->ClientDrew();
		}
	}
}

// Called in place of the client's function for a name's first line, from any of the calls to it
static void __fastcall DrawNameLine(const XiModel* pModel, [[maybe_unused]] void* unused, const float* pPosition, const char* text, uint32_t scale, uint32_t nameColor, uint32_t iconColor) {
	// the call is the 5 bytes before where it comes back to
	const uintptr_t site = reinterpret_cast<uintptr_t> (_ReturnAddress()) - 5;
	DrawNameLineFrom(site, pModel, pPosition, text, scale, nameColor, iconColor);
}

// Called in place of the client's function for a name's second line, which follows the first at once.
static void __fastcall DrawNameLine2(const XiModel* pModel, [[maybe_unused]] void* unused, const float* pPosition, const char* text, uint32_t scale) {
	bool drawn = true;

	if (Globals.pLineModel != nullptr && Globals.pLineModel == pModel) {
		// The second line is the stars or nothing: the client writes them as this one character
		if (Globals.pLineName != nullptr && text != nullptr && strchr(text, DRAWNAME_STARS) != nullptr && AsmSettings.HideStars == 0) {
			Globals.pLineName->Flags |= NAME_STARS;
			Filling.Changed = true;
		}

		drawn = Globals.LineDrawn;
		Globals.pLineModel = nullptr;
		Globals.pLineName = nullptr;
	}

	if (drawn && Globals.DrawNameLine2Orig != nullptr) {
		Globals.DrawNameLine2Orig(pModel, nullptr, pPosition, text, scale);
		if (Instance != nullptr) {
			Instance->ClientDrew();
		}
	}
}

// Where a CALL rel32 at this address goes, or 0 if that is not what is there, or it goes far off.
static uintptr_t CallTarget(uintptr_t pCall) {
	uint8_t code[5];
	if (!Patches.Code.Read(pCall, code, sizeof(code)) || code[0] != 0xE8) {
		return 0;
	}

	int32_t rel;
	memcpy(&rel, code + 1, sizeof(rel));
	if (rel < -0x10000 || rel > 0x10000) {
		return 0;
	}

	return pCall + 5 + rel;
}

// A CALL rel32 at pCall to target, as the bytes to write there
static void CallBytes(uint8_t code[5], uintptr_t pCall, uintptr_t target) {
	const int32_t rel = static_cast<int32_t>(target - (pCall + 5));
	code[0] = 0xE8;
	memcpy(code + 1, &rel, sizeof(rel));
}

// Every CALL rel32 in a stretch of code that goes to this function: where each is, up to max of them.
// Returns how many there were.
static size_t FindCallsIn(const uint8_t* begin, size_t length, uintptr_t target, uintptr_t* sites, size_t max) {
	size_t found = 0;
	if (length < 5) {
		return 0;
	}

	for (size_t i = 0; i + 5 <= length; i++) {
		if (begin[i] == 0xE8) {
			int32_t rel;
			memcpy(&rel, begin + i + 1, sizeof(rel));
			const uintptr_t at = reinterpret_cast<uintptr_t> (begin + i);
			if (at + 5 + static_cast<uintptr_t>(rel) == target) {
				if (found < max) {
					sites[found] = at;
				}
				found++;
			}
		}
	}
	return found;
}

// The same through all of the client's own code. first, which is known to be one of them, is put
// first. Returns how many of sites are filled.
static size_t FindCalls(uintptr_t target, uintptr_t first, uintptr_t* sites, size_t max) {
	size_t count = 0;
	sites[count++] = first;

	HMODULE module = GetModuleHandleA("FFXiMain.dll");
	if (module == nullptr) {
		return count;
	}

	const uint8_t* base = reinterpret_cast<const uint8_t*> (module);
	const IMAGE_DOS_HEADER* dos = reinterpret_cast<const IMAGE_DOS_HEADER*> (base);
	if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
		return count;
	}
	const IMAGE_NT_HEADERS* nt = reinterpret_cast<const IMAGE_NT_HEADERS*> (base + dos->e_lfanew);
	if (nt->Signature != IMAGE_NT_SIGNATURE) {
		return count;
	}

	const IMAGE_SECTION_HEADER* section = IMAGE_FIRST_SECTION(nt);
	for (unsigned i = 0; i < nt->FileHeader.NumberOfSections; i++, section++) {
		if ((section->Characteristics & IMAGE_SCN_MEM_EXECUTE) == 0) {
			continue;
		}

		if (!WindowsCodeMemory::Committed(reinterpret_cast<uintptr_t> (base + section->VirtualAddress), section->Misc.VirtualSize)) {
			continue;
		}
		uintptr_t found[LINE_CALLS_MAX * 2];
		size_t n = FindCallsIn(base + section->VirtualAddress, section->Misc.VirtualSize, target, found, LINE_CALLS_MAX * 2);
		// more than there is room for is more than was looked for: something else is being found
		if (n > LINE_CALLS_MAX * 2) {
			return 1;
		}
		for (size_t j = 0; j < n && count < max; j++) {
			if (found[j] != first) {
				sites[count++] = found[j];
			}
		}
	}
	return count;
}

// Points every call but the first of each kind at this plugin, or back at the client. A call that is
// no longer as this plugin left it is left alone. False where any could not be changed.
static bool TakeOtherCalls(bool take) {
	bool ok = true;
	for (size_t i = 1; i < Globals.DrawNameLineCallCount; i++) {
		ok = (take ? Patches.Write(Globals.DrawNameLineSites[i]) : Patches.Restore(Globals.DrawNameLineSites[i])) && ok;
	}
	for (size_t i = 1; i < Globals.DrawNameLine2CallCount; i++) {
		ok = (take ? Patches.Write(Globals.DrawNameLine2Sites[i]) : Patches.Restore(Globals.DrawNameLine2Sites[i])) && ok;
	}
	Globals.OtherCallsTaken = take;
	return ok;
}

// Whether the function here is one of the model's two for drawing a line of its name: it begins as
// both do, and gives back the stack that one of them does.
static bool IsDrawNameLine(uintptr_t pFunction, size_t retOffset, uint8_t retBytes) {
	static const uint8_t begins[] = { 0x66, 0x83, 0xB9, 0xB2, 0x00, 0x00, 0x00, 0x00 };
	uint8_t code[0x40];
	if (pFunction == 0 || retOffset + 3 > sizeof(code) || !Patches.Code.Read(pFunction, code, retOffset + 3)) {
		return false;
	}

	return memcmp(code, begins, sizeof(begins)) == 0
		&& code[retOffset] == 0xC2 && code[retOffset + 1] == retBytes && code[retOffset + 2] == 0x00;
}

// Resolution ratios and font-size divisions need only change with the settings
// or dimensions, not on every name/star/damage call. Keep double precision to
// preserve the original arithmetic before the final float conversion.
static struct {
	uint32_t BackgroundWidth, BackgroundHeight, WindowWidth, WindowHeight;
	int FontSize, DamageFontSize;
	double NameWidth, NameHeight, DamageWidth, DamageHeight;
	bool Valid;
} ScaleFactors;

static bool UpdateScaleFactors() {
	if (Globals.pgGame == nullptr || *Globals.pgGame == nullptr
			|| Globals.pWindowWidth == nullptr || Globals.pWindowHeight == nullptr) {
		return false;
	}
	const CGame* game = *Globals.pgGame;
	const uint32_t winW = *Globals.pWindowWidth, winH = *Globals.pWindowHeight;
	if (winW == 0 || winH == 0) { return false; }
	if (!ScaleFactors.Valid || ScaleFactors.BackgroundWidth != game->BackgroundWidth
			|| ScaleFactors.BackgroundHeight != game->BackgroundHeight
			|| ScaleFactors.WindowWidth != winW || ScaleFactors.WindowHeight != winH
			|| ScaleFactors.FontSize != AsmSettings.FontSize
			|| ScaleFactors.DamageFontSize != AsmSettings.DamageFontSize) {
		ScaleFactors.BackgroundWidth = game->BackgroundWidth;
		ScaleFactors.BackgroundHeight = game->BackgroundHeight;
		ScaleFactors.WindowWidth = winW;
		ScaleFactors.WindowHeight = winH;
		ScaleFactors.FontSize = AsmSettings.FontSize;
		ScaleFactors.DamageFontSize = AsmSettings.DamageFontSize;
		const double wRatio = static_cast<double>(game->BackgroundWidth) / winW;
		const double hRatio = static_cast<double>(game->BackgroundHeight) / winH;
		const double name = static_cast<double>(AsmSettings.FontSize) / 11.0;
		const double damage = static_cast<double>(AsmSettings.DamageFontSize) / 11.0;
		ScaleFactors.NameWidth = name * wRatio;
		ScaleFactors.NameHeight = name * hRatio;
		ScaleFactors.DamageWidth = damage * wRatio;
		ScaleFactors.DamageHeight = damage * hRatio;
		ScaleFactors.Valid = true;
	}
	return true;
}

static void __fastcall GetNameplateScale(float* wh, const float* pS) {
	if (UpdateScaleFactors()) {
		wh[0] = static_cast<float>(ScaleFactors.NameWidth * *pS);
		wh[1] = static_cast<float>(ScaleFactors.NameHeight * *pS);
	}
}

static void __fastcall GetDamageNumberScale(float* wh, const float* pS) {
	if (UpdateScaleFactors()) {
		wh[0] = static_cast<float>(ScaleFactors.DamageWidth * *pS);
		wh[1] = static_cast<float>(ScaleFactors.DamageHeight * *pS);
	}
}

// What the client's object for a damage popup holds, where the drawing function reads it, and what
// the effect it belongs to holds (read from the running game: the actors of the one hit and the one
// who hit them, in the effect's generator, for every popup)
#define POPUP_OBJECT_EFFECT 0xFC     // a pointer to a pointer to the effect's generator
#define POPUP_OBJECT_TEXT 0x198      // the text, of which 16 characters are drawn
#define POPUP_GENERATOR_SOURCE 0x3C  // the actor of who hit
#define POPUP_GENERATOR_TARGET 0x40  // and of who was hit

// The popups gathered as the client draws them this frame, made ready by Publish
static struct {
	uint32_t Count;
	HookPopup Popups[HOOK_POPUPS_MAX];
	bool Changed;
	bool Published;
} PopupFilling;

// Each popup seen lately, so that one drawn frame after frame keeps its id: the same object with the
// same text within HOOK_DRAW_FRAMES of the last frame it was drawn in
static struct {
	uint32_t Object;
	uint32_t LastFrame;
	HookPopup Popup;     // as first seen: its id, who it is over and from, and first frame
} RecentPopups[HOOK_POPUPS_MAX];
static uint32_t NextPopupId = 1;

// The frame whose first claimed popup has been drawn, so that the host is readied once a frame
static uint32_t PopupsDrawFrame = 0xFFFFFFFF;

// Set by /namehook popups probe: the next claimed popup has the host say what it is drawn on
static bool PopupProbeWanted = false;

// Whether an addon has drawn popups lately enough for them to be the ones to draw
static bool IsPopupDrawFresh() {
	return PopupDraw.QuadCount <= HOOK_POPUP_QUADS_MAX && PopupDraw.Count <= HOOK_POPUPS_MAX
		&& Shared.Frame - PopupDraw.Frame <= HOOK_DRAW_FRAMES;
}

// Where an addon's drawing of this popup is in PopupDraw.Drawings, or HOOK_POPUPS_MAX for none
static uint32_t FindPopupDrawing(uint32_t id) {
	if (!IsPopupDrawFresh()) {
		return HOOK_POPUPS_MAX;
	}
	for (uint32_t i = 0; i < PopupDraw.Count; i++) {
		const HookPopupDrawing& one = PopupDraw.Drawings[i];
		const HookDrawing& drawing = one.Drawing;
		if (one.Id == id && drawing.Frame == PopupDraw.Frame && drawing.Count != 0 && drawing.Count <= HOOK_QUADS_PER_NAME
				&& drawing.First <= PopupDraw.QuadCount && drawing.Count <= PopupDraw.QuadCount - drawing.First) {
			return i;
		}
	}
	return HOOK_POPUPS_MAX;
}

// A claimed popup, drawn as an addon has drawn it, at the point the client was about to draw it at
static void DrawClaimedPopup(uint32_t id, const float* position) {
	if (Instance == nullptr) {
		return;
	}
	if (PopupsDrawFrame != Shared.Frame) {
		PopupsDrawFrame = Shared.Frame;
		Instance->BeginPopups(PopupDraw, IsPopupDrawFresh());
	}
	const uint32_t slot = FindPopupDrawing(id);
	if (PopupProbeWanted) {
		PopupProbeWanted = false;
		Instance->ProbePopup(position, slot < HOOK_POPUPS_MAX);
	}
	if (slot < HOOK_POPUPS_MAX) {
		const HookPopupDrawing& drawing = PopupDraw.Drawings[slot];
		Instance->DrawPopup(slot, drawing, &PopupDraw.Quads[drawing.Drawing.First], position);
	}
}

// /namehook popups watch: each new popup said in the chat log as the frame ends, until turned off
static bool PopupsWatched = false;
static uint32_t PopupsToSay = 0;
static HookPopup PopupSaying[HOOK_POPUPS_MAX];

// The popup claim last seen made, and when; it lapses as a name claim does
static uint32_t PopupClaimSeen = 0xFFFFFFFF;
static uint64_t PopupClaimTime = 0;

static void NotePopupClaim() {
	if (Popups.ClaimFrame != PopupClaimSeen) {
		PopupClaimSeen = Popups.ClaimFrame;
		PopupClaimTime = FrameTime;
	}
}

static bool IsPopupClaimed() {
	NotePopupClaim();
	return Popups.Claimed != 0 && FrameTime - PopupClaimTime <= HOOK_CLAIM_TIME;
}

static uint32_t ReadPointer(uintptr_t at) {
	return (at != 0) ? ReadOperand(at) : 0;
}

// The entity an actor is, by the host; HOOK_ENTITIES for none
static uint32_t ActorEntity(uint32_t actor) {
	return (actor != 0 && Instance != nullptr) ? Instance->GetActorEntity(actor) : HOOK_ENTITIES;
}

// A damage popup the client is about to draw: at position (three floats), its letters size (two) and
// its own size factor (one). Listed for addons, and drawn by the client (true) unless an addon has
// claimed the popups. Called from the client's drawing function for it, through DrawDamage_Patch.
static bool __fastcall OnDamagePopup(const uint8_t* object, uint32_t color, const float* position, const float* size, const float* scale) {
	if (object == nullptr) {
		return true;
	}

	const bool drawn = !IsPopupClaimed();
	const uint32_t address = static_cast<uint32_t>(reinterpret_cast<uintptr_t> (object));
	char text[HOOK_POPUP_TEXT_SIZE] = {};
	memcpy(text, object + POPUP_OBJECT_TEXT, strnlen(reinterpret_cast<const char*> (object + POPUP_OBJECT_TEXT), 16));

	// drawn twice in one frame, it is listed once, as last drawn
	uint32_t slot = 0;
	while (slot < PopupFilling.Count && PopupFilling.Popups[slot].Object != address) {
		slot++;
	}
	if (slot == PopupFilling.Count) {
		if (PopupFilling.Count == HOOK_POPUPS_MAX) {
			return drawn;
		}
		PopupFilling.Count++;
	}

	// one seen lately keeps what was found of it; a new one is given an id and its owner looked for
	size_t recent = HOOK_POPUPS_MAX, oldest = 0;
	for (size_t i = 0; i < HOOK_POPUPS_MAX; i++) {
		if (RecentPopups[i].Object == address && RecentPopups[i].Popup.Id != 0
				&& Shared.Frame - RecentPopups[i].LastFrame <= HOOK_DRAW_FRAMES
				&& strcmp(RecentPopups[i].Popup.Text, text) == 0) {
			recent = i;
			break;
		}
		if (Shared.Frame - RecentPopups[i].LastFrame > Shared.Frame - RecentPopups[oldest].LastFrame || RecentPopups[i].Popup.Id == 0) {
			oldest = i;
		}
	}
	if (recent == HOOK_POPUPS_MAX) {
		recent = oldest;
		auto& seen = RecentPopups[recent];
		seen.Object = address;
		seen.Popup = {};
		seen.Popup.Id = NextPopupId++;
		if (NextPopupId == 0) {
			NextPopupId = 1;
		}
		seen.Popup.Object = address;
		seen.Popup.FirstFrame = Shared.Frame;
		memcpy(seen.Popup.Text, text, sizeof(text));
		seen.Popup.EntityIndex = HOOK_ENTITIES;
		seen.Popup.SourceIndex = HOOK_ENTITIES;
		const uint32_t generator = ReadPointer(ReadPointer(address + POPUP_OBJECT_EFFECT));
		if (generator != 0) {
			seen.Popup.EntityIndex = ActorEntity(ReadPointer(generator + POPUP_GENERATOR_TARGET));
			seen.Popup.SourceIndex = ActorEntity(ReadPointer(generator + POPUP_GENERATOR_SOURCE));
		}
		seen.Popup.Flags = (seen.Popup.EntityIndex < HOOK_ENTITIES ? POPUP_TARGET : 0)
			| (seen.Popup.SourceIndex < HOOK_ENTITIES ? POPUP_SOURCE : 0);
		if (PopupsWatched && PopupsToSay < HOOK_POPUPS_MAX) {
			PopupSaying[PopupsToSay++] = seen.Popup;
		}
	}
	RecentPopups[recent].LastFrame = Shared.Frame;

	HookPopup& popup = PopupFilling.Popups[slot];
	popup = RecentPopups[recent].Popup;
	popup.Flags = (popup.Flags & (POPUP_TARGET | POPUP_SOURCE)) | (drawn ? POPUP_DRAWN : 0);
	popup.Color = color;
	popup.X = position[0];
	popup.Y = position[1];
	popup.Z = position[2];
	popup.Scale = *scale;
	popup.Width = size[0];
	popup.Height = size[1];
	PopupFilling.Changed = true;

	if (!drawn) {
		DrawClaimedPopup(popup.Id, position);
	}

	if (PopupsWatched && popup.FirstFrame == Shared.Frame) {
		// the watch says it with what it was drawn at the first time
		for (uint32_t i = PopupsToSay; i-- > 0;) {
			if (PopupSaying[i].Id == popup.Id) {
				PopupSaying[i] = popup;
				break;
			}
		}
	}

	return drawn;
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

	// With the calls that draw a name in this plugin's hands, the name is decided on there, where
	// there is its place and its colour to put on the list for addons. Without them it is decided
	// here, and there is no list.
	if (Shared.Hooked != 0) {
		return true;
	}

	uint32_t flags = 0;
	return IsWanted(pEntity, Classify(pEntity, flags), flags);
}

void NameplateSettings::Normalize() {
	if (AsmSettings.FontSize < 1) {
		AsmSettings.FontSize = 1;
	}
	if (AsmSettings.FontSize > 256) {
		AsmSettings.FontSize = 256;
	}

	if (AsmSettings.DamageFontSize < 1) {
		AsmSettings.DamageFontSize = 1;
	}
	if (AsmSettings.DamageFontSize > 256) {
		AsmSettings.DamageFontSize = 256;
	}

	AsmSettings.HideStars = (AsmSettings.HideStars != 0) ? 1 : 0;
}

int NameplateSettings::Init() {
	AsmSettings.FontSize = 22;
	AsmSettings.DamageFontSize = 22;
	AsmSettings.HideStars = 0;

	return 0;
}

int NameplateSettings::Load(const wchar_t* basePath) {
	wchar_t path[UNICODE_MAX_PATH];
	StringCchPrintfW(path, UNICODE_MAX_PATH, L"%s\\namehook\\defaults.ini", basePath);

	AsmSettings.FontSize = GetPrivateProfileIntW(L"Settings", L"FontSizeInPx", 22, path);
	AsmSettings.DamageFontSize = GetPrivateProfileIntW(L"Settings", L"DamageFontSizeInPx", 22, path);
	AsmSettings.HideStars = GetPrivateProfileIntW(L"Settings", L"HideStars", 0, path);

	// Which names are hidden is kept where addons can change it
	Shared.Hidden = GetPrivateProfileIntW(L"Settings", L"Hidden", 0, path) & CATEGORY_ALL;
	Shared.Options = (GetPrivateProfileIntW(L"Settings", L"AlwaysTarget", 0, path) != 0) ? OPTION_ALWAYS_TARGET : 0;
	OtherCalls = (GetPrivateProfileIntW(L"Settings", L"OtherCalls", 1, path) != 0) ? 1 : 0;
	KeepStates = (GetPrivateProfileIntW(L"Settings", L"KeepStates", 1, path) != 0) ? 1 : 0;

	Normalize();

	return 0;
}

int NameplateSettings::Save(const wchar_t* basePath) {
	wchar_t path[UNICODE_MAX_PATH];

	StringCchPrintfW(path, UNICODE_MAX_PATH, L"%s\\namehook", basePath);
	CreateDirectoryW(path, NULL);

	StringCchPrintfW(path, UNICODE_MAX_PATH, L"%s\\namehook\\defaults.ini", basePath);

	wchar_t buf[256];

	StringCbPrintfW(buf, sizeof(buf), L"%d", AsmSettings.FontSize);
	WritePrivateProfileStringW(L"Settings", L"FontSizeInPx", buf, path);

	StringCbPrintfW(buf, sizeof(buf), L"%d", AsmSettings.DamageFontSize);
	WritePrivateProfileStringW(L"Settings", L"DamageFontSizeInPx", buf, path);

	StringCbPrintfW(buf, sizeof(buf), L"%d", AsmSettings.HideStars);
	WritePrivateProfileStringW(L"Settings", L"HideStars", buf, path);

	StringCbPrintfW(buf, sizeof(buf), L"%u", Shared.Hidden & CATEGORY_ALL);
	WritePrivateProfileStringW(L"Settings", L"Hidden", buf, path);

	StringCbPrintfW(buf, sizeof(buf), L"%d", (Shared.Options & OPTION_ALWAYS_TARGET) != 0 ? 1 : 0);
	WritePrivateProfileStringW(L"Settings", L"AlwaysTarget", buf, path);

	StringCbPrintfW(buf, sizeof(buf), L"%d", OtherCalls);
	WritePrivateProfileStringW(L"Settings", L"OtherCalls", buf, path);

	StringCbPrintfW(buf, sizeof(buf), L"%d", KeepStates);
	WritePrivateProfileStringW(L"Settings", L"KeepStates", buf, path);

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

// Whether the command goes on with this word, whole: if so it is passed over
static bool token_match_and_advance(const char*& cmd, const char* token, size_t token_length) {
	if (_strnicmp(cmd, token, token_length) == 0 && isspace_or_end(cmd[token_length])) {
		cmd += token_length;
		return true;
	}

	return false;
}

template <size_t N>
static bool token_match_and_advance(const char*& cmd, const char (&token)[N]) {
	return token_match_and_advance(cmd, token, N - 1);
}

template <size_t N>
static bool eat_space_token_match_and_advance(const char*& cmd, const char (&token)[N]) {
	eat_space(cmd);
	return token_match_and_advance(cmd, token, N - 1);
}

static void Sayf(Nameplate* plugin, const char* format, ...);

// The categories, by the words a command names them with
static const struct {
	const char* Word;
	uint32_t Category;
} CategoryWords[] = {
	{ "self", CATEGORY_SELF },
	{ "party", CATEGORY_PARTY },
	{ "alliance", CATEGORY_ALLIANCE },
	{ "players", CATEGORY_PLAYER },
	{ "mypet", CATEGORY_MY_PET },
	{ "pets", CATEGORY_PET },
	{ "npcs", CATEGORY_NPC },
	{ "monsters", CATEGORY_MONSTER },
	// the first eight are the categories in their order, by the names they are said back with
	{ "player", CATEGORY_PLAYER },
	{ "pet", CATEGORY_PET },
	{ "npc", CATEGORY_NPC },
	{ "monster", CATEGORY_MONSTER },
	{ "mobs", CATEGORY_MONSTER },
	{ "mob", CATEGORY_MONSTER },
	{ "all", CATEGORY_ALL },
};

bool Nameplate::ParseCommand(const char* cmd, bool includesName) {
	if (includesName) {
		if (token_match_and_advance(cmd, "/namehook")) {
			// skip
		} else if (token_match_and_advance(cmd, "/nh")) {
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
	// show|hide|toggle <category>...
	// target on|off
	// status
	// othercalls on|off
	// keepstates on|off
	// whitelist add|remove <name>...
	// whitelist list|clear
	// popups [watch on|off]

	int ret = 0;

	if (eat_space_token_match_and_advance(cmd, "help")) {
		ShowMessage(MESSAGE::LONG_HELP);
	} else if (eat_space_token_match_and_advance(cmd, "load")) {
		if (eat_space_and_is_end(cmd)) {
			ret = LoadSettings();
			if (ret < 0) {
				ShowMessage(MESSAGE::LOAD_ERROR, ret);
			} else {
				Update();
			}
		} else {
			CommandError("load");
		}
	} else if (eat_space_token_match_and_advance(cmd, "save")) {
		if (eat_space_and_is_end(cmd)) {
			ret = SaveSettings();
			if (ret < 0) {
				ShowMessage(MESSAGE::SAVE_ERROR, ret);
			}
		} else {
			CommandError("save");
		}
	} else if (eat_space_token_match_and_advance(cmd, "fontsizeinpx")
			|| eat_space_token_match_and_advance(cmd, "fontsize")) {
		errno = 0;

		char* cmd_end = const_cast<char*>(cmd);

		unsigned long val = strtoul(cmd, &cmd_end, 10);

		cmd = cmd_end;

		if (val == 0 || val > 256 || errno != 0 || !eat_space_and_is_end(cmd)) {
			CommandError("fontsize");
		} else {
			AsmSettings.FontSize = static_cast<int>(val);
			// update not necessary in this path
		}
	} else if (eat_space_token_match_and_advance(cmd, "damagefontsizeinpx")
			|| eat_space_token_match_and_advance(cmd, "damagefontsize")
			|| eat_space_token_match_and_advance(cmd, "dmgfontsize")) {
		errno = 0;

		char* cmd_end = const_cast<char*>(cmd);

		unsigned long val = strtoul(cmd, &cmd_end, 10);

		cmd = cmd_end;

		if (val == 0 || val > 256 || errno != 0 || !eat_space_and_is_end(cmd)) {
			CommandError("damagefontsize");
		} else {
			AsmSettings.DamageFontSize = static_cast<int>(val);
			// update not necessary in this path
		}
	} else if (eat_space_token_match_and_advance(cmd, "showstars")) {
		if (eat_space_and_is_end(cmd)) {
			AsmSettings.HideStars = 0;
			Update();
		} else {
			CommandError("showstars");
		}
	} else if (eat_space_token_match_and_advance(cmd, "hidestars")) {
		if (eat_space_and_is_end(cmd)) {
			AsmSettings.HideStars = 1;
			Update();
		} else {
			CommandError("hidestars");
		}
	} else if (eat_space_token_match_and_advance(cmd, "show")) {
		ParseCategoryCommand(cmd, 1);
	} else if (eat_space_token_match_and_advance(cmd, "hide")) {
		ParseCategoryCommand(cmd, 0);
	} else if (eat_space_token_match_and_advance(cmd, "toggle")) {
		ParseCategoryCommand(cmd, -1);
	} else if (eat_space_token_match_and_advance(cmd, "target")) {
		int alwaysTarget = -1;

		if (eat_space_token_match_and_advance(cmd, "on")) {
			alwaysTarget = 1;
		} else if (eat_space_token_match_and_advance(cmd, "off")) {
			alwaysTarget = 0;
		}

		if (alwaysTarget >= 0 && eat_space_and_is_end(cmd)) {
			if (alwaysTarget != 0) {
				Shared.Options |= OPTION_ALWAYS_TARGET;
			} else {
				Shared.Options &= ~static_cast<uint32_t>(OPTION_ALWAYS_TARGET);
			}
		} else {
			CommandError("target");
		}
	} else if (eat_space_token_match_and_advance(cmd, "probe")) {
		// not in the help: for finding out how the client draws
		if (Shared.Hooked != 0) {
			ProbeWanted = true;
		} else {
			Debug("This client's name drawing was not recognised: there is nothing to look at.");
		}
	} else if (eat_space_token_match_and_advance(cmd, "othercalls")) {
		int otherCalls = -1;

		if (eat_space_token_match_and_advance(cmd, "on")) {
			otherCalls = 1;
		} else if (eat_space_token_match_and_advance(cmd, "off")) {
			otherCalls = 0;
		}

		if (otherCalls >= 0 && eat_space_and_is_end(cmd)) {
			OtherCalls = otherCalls;
			if (Shared.Hooked != 0 && !TakeOtherCalls(otherCalls != 0)) {
				ShowMessage(MESSAGE::PATCH_ERROR);
			}
		} else {
			CommandError("othercalls");
		}
	} else if (eat_space_token_match_and_advance(cmd, "keepstates")) {
		int keepStates = -1;

		if (eat_space_token_match_and_advance(cmd, "on")) {
			keepStates = 1;
		} else if (eat_space_token_match_and_advance(cmd, "off")) {
			keepStates = 0;
		}

		if (keepStates >= 0 && eat_space_and_is_end(cmd)) {
			KeepStates = keepStates;
		} else {
			CommandError("keepstates");
		}
	} else if (eat_space_token_match_and_advance(cmd, "status")) {
		if (eat_space_and_is_end(cmd)) {
			SayStatus();
		} else {
			CommandError("status");
		}
	} else if (eat_space_token_match_and_advance(cmd, "whitelist")
			|| eat_space_token_match_and_advance(cmd, "wl")) {
		ParseWhitelistCommand(cmd);
	} else if (eat_space_token_match_and_advance(cmd, "popups")) {
		ParsePopupsCommand(cmd);
	} else {
		ShowMessage(MESSAGE::SHORT_HELP);
	}

	return true;
}

// show, hide or toggle (show 1, 0 or -1), then one category or more. Nothing is changed unless every
// word is a category.
void Nameplate::ParseCategoryCommand(const char* cmd, int show) {
	uint32_t categories = 0;

	while (!eat_space_and_is_end(cmd)) {
		uint32_t category = 0;
		for (const auto& word : CategoryWords) {
			if (token_match_and_advance(cmd, word.Word, strlen(word.Word))) {
				category = word.Category;
				break;
			}
		}

		if (category == 0) {
			categories = 0;
			break;
		}
		categories |= category;
	}

	if (categories == 0) {
		CommandError(show > 0 ? "show" : (show == 0 ? "hide" : "toggle"));
	} else if (show > 0) {
		Shared.Hidden &= ~categories;
	} else if (show == 0) {
		Shared.Hidden |= categories;
	} else {
		Shared.Hidden ^= categories;
	}
}

// An entity's name, if its name was drawn last frame, and its index, for the chat log
static void DescribeEntity(char* out, size_t size, uint32_t index) {
	const char* name = "";
	for (uint32_t i = 0; i < Shared.Count && i < HOOK_NAMES_MAX; i++) {
		if (Shared.Names[i].EntityIndex == index) {
			name = Shared.Names[i].Name;
			break;
		}
	}
	StringCbPrintfA(out, size, "%s%s0x%03X", name, name[0] != '\0' ? " " : "", static_cast<unsigned>(index));
}

// One popup in the chat log
static void SayPopup(Nameplate* plugin, const HookPopup& popup) {
	char target[48] = "nobody known", source[48] = "nobody known";
	if ((popup.Flags & POPUP_TARGET) != 0) {
		DescribeEntity(target, sizeof(target), popup.EntityIndex);
	}
	if ((popup.Flags & POPUP_SOURCE) != 0) {
		DescribeEntity(source, sizeof(source), popup.SourceIndex);
	}

	char screen[48];
	if ((popup.Flags & POPUP_ON_SCREEN) != 0) {
		StringCbPrintfA(screen, sizeof(screen), "screen %.0f,%.0f", popup.ScreenX, popup.ScreenY);
	} else {
		StringCbCopyA(screen, sizeof(screen), "not placed on screen");
	}

	char text[HOOK_POPUP_TEXT_SIZE + 1] = {};
	memcpy(text, popup.Text, HOOK_POPUP_TEXT_SIZE);
	Sayf(plugin, "#%u \"%s\" on %s from %s, colour %08X, size %.2f, at %.1f %.1f %.1f, %s, %s",
		static_cast<unsigned>(popup.Id), text, target, source, static_cast<unsigned>(popup.Color), popup.Scale,
		popup.X, popup.Y, popup.Z, screen, (popup.Flags & POPUP_DRAWN) != 0 ? "drawn by the client" : "claimed");
}

// What /namehook popups watch has seen this frame, said as the frame ends
static void SayNewPopups(Nameplate* plugin) {
	for (uint32_t i = 0; i < PopupsToSay; i++) {
		SayPopup(plugin, PopupSaying[i]);
	}
	PopupsToSay = 0;
}

// How many popups there were last frame, and who draws them: false if the client's are not hooked
static bool SayPopupSummary(Nameplate* plugin) {
	if (Popups.Hooked == 0) {
		Sayf(plugin, "This client's damage popups were not recognised: the client draws them, and none are listed.");
		return false;
	}
	Sayf(plugin, "%u damage popups last frame; %s.", static_cast<unsigned>(Popups.Count),
		IsPopupClaimed() ? "an addon draws them in place of the client" : "the client draws them");
	return true;
}

// popups, or popups watch on|off
void Nameplate::ParsePopupsCommand(const char* cmd) {
	if (eat_space_and_is_end(cmd)) {
		SayPopups();
		return;
	}

	if (eat_space_token_match_and_advance(cmd, "probe")) {
		// not in the help: for finding out how the client draws its popups
		if (eat_space_and_is_end(cmd)) {
			PopupProbeWanted = true;
			Sayf(this, "The next damage popup an addon draws will be looked at.");
		} else {
			CommandError("popups");
		}
		return;
	}

	int watch = -1;
	if (eat_space_token_match_and_advance(cmd, "watch")) {
		if (eat_space_token_match_and_advance(cmd, "on")) {
			watch = 1;
		} else if (eat_space_token_match_and_advance(cmd, "off")) {
			watch = 0;
		}
	}

	if (watch < 0 || !eat_space_and_is_end(cmd)) {
		CommandError("popups");
	} else {
		PopupsWatched = watch != 0;
		PopupsToSay = 0;
		Sayf(this, PopupsWatched ? "Each new damage popup will be said here, until /namehook popups watch off." : "New damage popups are no longer said.");
	}
}

void Nameplate::SayPopups() {
	if (!SayPopupSummary(this)) {
		return;
	}
	for (uint32_t i = 0; i < Popups.Count && i < HOOK_POPUPS_MAX; i++) {
		SayPopup(this, Popups.Popups[i]);
	}
}

void Nameplate::SayStatus() {
	char shown[256];
	char hidden[256];
	shown[0] = '\0';
	hidden[0] = '\0';

	for (size_t i = 0; i < CATEGORY_COUNT; i++) {
		char* list = ((Shared.Hidden & CategoryWords[i].Category) != 0) ? hidden : shown;
		if (list[0] != '\0') {
			StringCbCatA(list, sizeof(shown), ", ");
		}
		StringCbCatA(list, sizeof(shown), CategoryWords[i].Word);
	}

	Sayf(this, "Shown: %s", (shown[0] != '\0') ? shown : "none");
	Sayf(this, "Hidden: %s", (hidden[0] != '\0') ? hidden : "none");
	Sayf(this, "The target's name is %s.", ((Shared.Options & OPTION_ALWAYS_TARGET) != 0) ? "always shown" : "shown or hidden with its category");

	if (Shared.Hooked == 0) {
		Sayf(this, "This client's name drawing was not recognised: names are shown and hidden, but none are listed for addons.");
	} else if (AnyClaims(CATEGORY_ALL)) {
		Sayf(this, "%u names last frame. An addon is drawing some in place of the client.", static_cast<unsigned>(Shared.Count));
	} else {
		Sayf(this, "%u names last frame.", static_cast<unsigned>(Shared.Count));
	}

	if (Shared.Hooked != 0) {
		Sayf(this, "The client draws names from %u places (%u for the second line); %s. %u lines last frame were nobody's.",
			static_cast<unsigned>(Globals.DrawNameLineCallCount), static_cast<unsigned>(Globals.DrawNameLine2CallCount),
			(Globals.DrawNameLineCallCount <= 1 && Globals.DrawNameLine2CallCount <= 1) ? "there are no others to take"
				: (Globals.OtherCallsTaken ? "all are taken" : "only the first is taken (othercalls off)"),
			static_cast<unsigned>(Globals.UnownedLast));
		Sayf(this, "%u names last frame were drawn again after their first time (%u of those by the call that draws all the names), and were listed and drawn for an addon once; %u were taken from a lower line and drawn where the higher had been.",
			static_cast<unsigned>(Globals.RepeatsLast), static_cast<unsigned>(Globals.RepeatsMainLast), static_cast<unsigned>(Globals.LiftedLast));
		Sayf(this, "The device's state is %s (keepstates %s).", KeepStates != 0 ? "captured once for a run of names an addon has drawn" : "captured before each name an addon has drawn", KeepStates != 0 ? "on" : "off");
	}

	SayPopupSummary(this);
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

	if (eat_space_token_match_and_advance(cmd, "add")) {
		int named = 0;
		bool changed = false;

		while (next_name(cmd, name, tooLong)) {
			named++;
			if (FindWhitelisted(name) >= 0) {
				Sayf(this, "%s is already on the whitelist.", name);
			} else if (Whitelist.Count >= WHITELIST_MAX) {
				Sayf(this, "The whitelist is full (%d names); %s was not added.", WHITELIST_MAX, name);
			} else {
				AddWhitelisted(name);
				changed = true;
				Sayf(this, "Added %s to the whitelist.", name);
			}
		}

		if (tooLong || named == 0) {
			CommandError("whitelist");
		}
		if (changed && SaveWhitelist() < 0) {
			Sayf(this, "The whitelist could not be saved.");
		}
	} else if (eat_space_token_match_and_advance(cmd, "remove")
			|| eat_space_token_match_and_advance(cmd, "del")) {
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
					Whitelist.Hashes[i] = Whitelist.Hashes[i + 1];
				}
				Whitelist.Count--;
				Whitelist.IndexDirty = true; // compaction changes every later list index
				changed = true;
				Sayf(this, "Removed %s from the whitelist.", name);
			}
		}

		if (tooLong || named == 0) {
			CommandError("whitelist");
		}
		if (changed && SaveWhitelist() < 0) {
			Sayf(this, "The whitelist could not be saved.");
		}
	} else if (eat_space_token_match_and_advance(cmd, "clear")) {
		if (eat_space_and_is_end(cmd)) {
			size_t count = Whitelist.Count;
			Whitelist.Count = 0;
			Whitelist.IndexDirty = true;
			if (SaveWhitelist() < 0) {
				Sayf(this, "The whitelist could not be saved.");
			} else {
				Sayf(this, "Removed all %u names from the whitelist.", static_cast<unsigned>(count));
			}
		} else {
			CommandError("whitelist");
		}
	} else if (eat_space_and_is_end(cmd) || eat_space_token_match_and_advance(cmd, "list")) {
		if (!eat_space_and_is_end(cmd)) {
			CommandError("whitelist");
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
		CommandError("whitelist");
	}
}

// One name to a line in config/namehook/whitelist.txt; without the file, the whitelist is empty.
int Nameplate::LoadWhitelist() {
	wchar_t basePath[UNICODE_MAX_PATH];
	if (!this->GetConfigPath(basePath)) {
		return -19;
	}

	wchar_t path[UNICODE_MAX_PATH];
	StringCchPrintfW(path, UNICODE_MAX_PATH, L"%s\\namehook\\whitelist.txt", basePath);

	Whitelist.Count = 0;
	Whitelist.IndexDirty = true;

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
			AddWhitelisted(name);
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
	StringCchPrintfW(path, UNICODE_MAX_PATH, L"%s\\namehook", basePath);
	CreateDirectoryW(path, NULL);

	StringCchPrintfW(path, UNICODE_MAX_PATH, L"%s\\namehook\\whitelist.txt", basePath);

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

int Nameplate::Init() {
	// An earlier load left code of the client's calling into this module: Globals is still what it reads
	if (Stranded) {
		return -24;
	}

	ZeroMemory(&Globals, sizeof(Globals));
	ZeroMemory(&Seen, sizeof(Seen));

	// A number of this load's own, never 0 and never the last one's, so that an addon tells this plugin
	// from one loaded before it, even at the same address
	{
		LARGE_INTEGER count;
		QueryPerformanceCounter(&count);
		uint32_t id = (static_cast<uint32_t>(count.QuadPart) ^ static_cast<uint32_t>(count.QuadPart >> 32) ^ GetTickCount()) * 2654435761u;
		if (id == 0 || id == Shared.LoadId) {
			id = Shared.LoadId + 1 != 0 ? Shared.LoadId + 1 : 1;
		}
		Shared.LoadId = id;
	}
	Shared.NamesDropped = 0;
	Shared.DrawingsRefused = 0;

	// Configuration setup
	Settings.Init();
	LoadSettings();

	// GetFrameDelta
	uintptr_t pGetFrameDelta = (uintptr_t) getFrameDeltaSig.Find();
	if (pGetFrameDelta == 0) {
		pGetFrameDelta = (uintptr_t) getFrameDeltaTrueFpsSig.Find();
	}
	if (pGetFrameDelta == 0) {
		return -4;
	}

	// offset into instruction accessing gGame
	uintptr_t pppObj = pGetFrameDelta + 2;

	// pointer to gGame
	uintptr_t ppObj = ReadOperand(pppObj);
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
	uintptr_t pWindowWidth = ReadOperand(ppWindowWidth);
	if (pWindowWidth == 0) {
		return -7;
	}

	// pWindowHeight
	uintptr_t pWindowHeight = ReadOperand(ppWindowHeight);
	if (pWindowHeight == 0) {
		return -8;
	}

	// GetPlayerEntity
	uintptr_t pGetPlayerEntity = (uintptr_t) getPlayerEntitySig.Find();
	if (pGetPlayerEntity == 0) {
		return -15;
	}

	uintptr_t ppPlayerEntityIndex = pGetPlayerEntity + 2;
	uintptr_t pPlayerEntityIndex = ReadOperand(ppPlayerEntityIndex);
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

	// DrawName3 (display mode): the function that decides whether a name is drawn, and draws it
	uintptr_t pDrawName3V2Patch = (uintptr_t) drawName3V2PatchLocationSig.Find();
	if (pDrawName3V2Patch == 0) {
		return -14;
	}

	uintptr_t pNamesOff = ReadOperand(pDrawName3V2Patch + 1);
	if (pNamesOff == 0) {
		return -17;
	}

	// DrawDamage
	uintptr_t pDrawDamagePatch = (uintptr_t) drawDamagePatchLocationSig.Find();
	if (pDrawDamagePatch == 0) {
		return -18;
	}

	// Every write is made ready first, each at a site of its own whose bytes as found are kept, and
	// they go in together or not at all (CodePatch.h)
	Patches.Drop(0);
	uint8_t bytes[CODE_PATCH_BYTES_MAX];

	CopyMemory(bytes, &DrawName_Patch0[0], DRAWNAME_PATCH0_SIZE);
	WriteAddress(bytes + DRAWNAME_PATCH0_ADDRESS_LOCATION, reinterpret_cast<const void*> (&GetNameplateScale));
	if (Patches.Add(pDrawNamePatch0, bytes, DRAWNAME_PATCH0_SIZE) < 0) {
		return -22;
	}

	CopyMemory(bytes, &DrawName_Patch1[0], DRAWNAME_PATCH1_SIZE);
	WriteAddress(bytes + DRAWNAME_PATCH1_ADDRESS_LOCATION, reinterpret_cast<const void*> (&GetNameplateScale));
	if (Patches.Add(pDrawNamePatch1, bytes, DRAWNAME_PATCH1_SIZE) < 0) {
		return -22;
	}

	// DrawName2: its jnz made a jmp while the stars are hidden, and put back as it was when they are not
	uint8_t stars[1];
	if (!Patches.Code.Read(pDrawName2Patch + DRAWNAME2_PATCH_ADDRESS_LOCATION, stars, sizeof(stars))) {
		return -22;
	}
	if (AsmSettings.HideStars != 0) {
		stars[0] = 0xEB;
	}
	Globals.StarsSite = Patches.Add(pDrawName2Patch + DRAWNAME2_PATCH_ADDRESS_LOCATION, stars, sizeof(stars));
	if (Globals.StarsSite < 0) {
		return -22;
	}
	Patches.Sites[Globals.StarsSite].Harmless = true; // a jump within the client's own code

	CopyMemory(bytes, &DrawName3_V2_Patch[0], DRAWNAME3_V2_PATCH_SIZE);
	WriteAddress(bytes + DRAWNAME3_V2_PATCH_ADDRESS_LOCATION, reinterpret_cast<const void*> (&ShouldDrawNameplate));
	if (Patches.Add(pDrawName3V2Patch, bytes, DRAWNAME3_V2_PATCH_SIZE) < 0) {
		return -22;
	}

	// DrawDamage: the colour's address is the client's own, read from what the patch goes over
	uint8_t damageWas[DRAWDAMAGE_PATCH_SIZE];
	if (!Patches.Code.Read(pDrawDamagePatch, damageWas, DRAWDAMAGE_PATCH_SIZE)) {
		return -22;
	}
	CopyMemory(bytes, &DrawDamage_Patch[0], DRAWDAMAGE_PATCH_SIZE);
	WriteAddress(bytes + DRAWDAMAGE_PATCH_CALL_ADDRESS_LOCATION, reinterpret_cast<const void*> (&GetDamageNumberScale));
	CopyMemory(bytes + DRAWDAMAGE_PATCH_COLOR_ADDRESS_LOCATION, &damageWas[DRAWDAMAGE_PATCH_OLD_COLOR_ADDRESS_LOCATION], 4);

	// The popups are handed to the plugin only where the client's code around the patch is as expected
	uint8_t position[sizeof(DrawDamage_Position)];
	uint8_t end[sizeof(DrawDamage_End)];
	const bool popups = Patches.Code.Read(pDrawDamagePatch - DRAWDAMAGE_POSITION_OFFSET, position, sizeof(position))
		&& Patches.Code.Read(pDrawDamagePatch + DRAWDAMAGE_END_OFFSET, end, sizeof(end))
		&& memcmp(position, DrawDamage_Position, sizeof(position)) == 0
		&& memcmp(end, DrawDamage_End, sizeof(end)) == 0;
	if (popups) {
		WriteAddress(bytes + DRAWDAMAGE_PATCH_POPUP_ADDRESS_LOCATION, reinterpret_cast<const void*> (&OnDamagePopup));
	} else {
		CopyMemory(bytes + DRAWDAMAGE_PATCH_POPUP_LOCATION, DrawDamage_PopupSkip, sizeof(DrawDamage_PopupSkip));
	}
	if (Patches.Add(pDrawDamagePatch, bytes, DRAWDAMAGE_PATCH_SIZE) < 0) {
		return -22;
	}

	// The calls that draw a name's two lines, where names are listed for addons: taken only if both go
	// where they are expected to; without them names are shown and hidden all the same, and there is
	// no list. The client draws a name by these two functions from other places too: every call to
	// either is found while they still go to the client, and is taken only with othercalls on.
	bool lines = false;
	{
		uintptr_t pLineCall = pDrawName3V2Patch + DRAWNAME_LINE_CALL_OFFSET;
		uintptr_t pLine2Call = pDrawName3V2Patch + DRAWNAME_LINE2_CALL_OFFSET;
		uintptr_t pLine = CallTarget(pLineCall);
		uintptr_t pLine2 = CallTarget(pLine2Call);

		if (IsDrawNameLine(pLine, DRAWNAME_LINE_RET_OFFSET, 0x14) && IsDrawNameLine(pLine2, DRAWNAME_LINE2_RET_OFFSET, 0x0C)) {
			const size_t before = Patches.Count;
			uintptr_t lineCalls[LINE_CALLS_MAX], line2Calls[LINE_CALLS_MAX];
			const size_t lineCount = FindCalls(pLine, pLineCall, lineCalls, LINE_CALLS_MAX);
			const size_t line2Count = FindCalls(pLine2, pLine2Call, line2Calls, LINE_CALLS_MAX);

			// the first of each is the one in the function that draws every name: without it, none
			uint8_t call[5];
			CallBytes(call, pLineCall, reinterpret_cast<uintptr_t> (&DrawNameLine));
			const int lineSite = Patches.Add(pLineCall, call, sizeof(call));
			CallBytes(call, pLine2Call, reinterpret_cast<uintptr_t> (&DrawNameLine2));
			const int line2Site = Patches.Add(pLine2Call, call, sizeof(call));

			if (lineSite >= 0 && line2Site >= 0) {
				Globals.DrawNameLineOrig = reinterpret_cast<DrawNameLineFn> (pLine);
				Globals.DrawNameLine2Orig = reinterpret_cast<DrawNameLine2Fn> (pLine2);
				Globals.DrawNameLineCalls[0] = pLineCall;
				Globals.DrawNameLineSites[0] = lineSite;
				Globals.DrawNameLine2Calls[0] = pLine2Call;
				Globals.DrawNameLine2Sites[0] = line2Site;
				Globals.DrawNameLineCallCount = 1;
				Globals.DrawNameLine2CallCount = 1;

				// the rest, each where it does not meet another site: deferred, for TakeOtherCalls
				for (size_t i = 1; i < lineCount; i++) {
					CallBytes(call, lineCalls[i], reinterpret_cast<uintptr_t> (&DrawNameLine));
					const int site = Patches.Add(lineCalls[i], call, sizeof(call), true);
					if (site >= 0) {
						Globals.DrawNameLineCalls[Globals.DrawNameLineCallCount] = lineCalls[i];
						Globals.DrawNameLineSites[Globals.DrawNameLineCallCount++] = site;
					}
				}
				for (size_t i = 1; i < line2Count; i++) {
					CallBytes(call, line2Calls[i], reinterpret_cast<uintptr_t> (&DrawNameLine2));
					const int site = Patches.Add(line2Calls[i], call, sizeof(call), true);
					if (site >= 0) {
						Globals.DrawNameLine2Calls[Globals.DrawNameLine2CallCount] = line2Calls[i];
						Globals.DrawNameLine2Sites[Globals.DrawNameLine2CallCount++] = site;
					}
				}
				lines = true;
			} else {
				Patches.Drop(before);
			}
		}
	}

	// What the patched code reads is ready before any of it can run
	Globals.pgGame = reinterpret_cast<CGame**> (ppObj);
	Globals.pWindowWidth = reinterpret_cast<uint32_t*> (pWindowWidth);
	Globals.pWindowHeight = reinterpret_cast<uint32_t*> (pWindowHeight);
	Globals.pPlayerEntityIndex = reinterpret_cast<uint16_t*> (pPlayerEntityIndex);
	Globals.pNamesOff = reinterpret_cast<bool*> (pNamesOff);

	if (!Patches.Commit()) {
		// Commit has taken back what it wrote; a site it could not take back strands the plugin
		if (Patches.Stranding() != 0) {
			Strand();
			return -23;
		}
		Patches.Drop(0);
		ZeroMemory(&Globals, sizeof(Globals));
		return -23;
	}
	Globals.Patched = true;
	Popups.Hooked = popups ? 1 : 0;

	if (lines) {
		TakeOtherCalls(OtherCalls != 0);
		Shared.Hooked = 1;
	}

	ZeroMemory(&Bubbles.Draw, sizeof(Bubbles.Draw));
	ZeroMemory(Bubbles.ServerIds, sizeof(Bubbles.ServerIds));
	Bubbles.Draw.QuadsMax = HOOK_QUADS_MAX;
	Bubbles.Draw.Frame = 0 - (HOOK_DRAW_FRAMES + 1);
	Draw.QuadsMax = HOOK_QUADS_MAX;
	Draw.Frame = 0 - (HOOK_DRAW_FRAMES + 1); // nothing drawn yet
	for (uint32_t i = 0; i < HOOK_CLAIM_SLOTS; i++) {
		ZeroMemory(&SlotDraws[i], sizeof(SlotDraws[i]));
		SlotDraws[i].QuadsMax = HOOK_QUADS_MAX;
		SlotDraws[i].Frame = 0 - (HOOK_DRAW_FRAMES + 1);
		ZeroMemory(&Claims.Slots[i], sizeof(Claims.Slots[i]));
		Claims.Slots[i].Draw = static_cast<uint32_t>(reinterpret_cast<uintptr_t> (&SlotDraws[i]));
		SlotClaimSeen[i] = 0xFFFFFFFF;
	}
	ZeroMemory(&PopupDraw, sizeof(PopupDraw));
	PopupDraw.QuadsMax = HOOK_POPUP_QUADS_MAX;
	PopupDraw.DrawingsMax = HOOK_POPUPS_MAX;
	PopupDraw.Frame = 0 - (HOOK_DRAW_FRAMES + 1);
	Popups.Draw = static_cast<uint32_t>(reinterpret_cast<uintptr_t> (&PopupDraw));
	FrameTime = Clock();
	Shared.Draw = static_cast<uint32_t>(reinterpret_cast<uintptr_t> (&Draw));

	Instance = this;

	return 0;
}

int Nameplate::Update() {
	if (Globals.Patched) {
		// a JMP there while the stars are hidden, the client's own jnz while they are not
		const uint8_t jump[1] = { (AsmSettings.HideStars != 0) ? static_cast<uint8_t>(0xEB) : Patches.Sites[Globals.StarsSite].Original[0] };
		if (!Patches.Rewrite(Globals.StarsSite, jump)) {
			ShowMessage(MESSAGE::PATCH_ERROR);
			return -25;
		}
	}

	return 0;
}

// As a frame ends with nothing made ready, there are last frame's names, or popups, to take away
static bool NamesWanted(bool frameDone) {
	return Filling.Changed || (frameDone && !Filling.Published);
}

static bool PopupsWanted(bool frameDone) {
	return PopupFilling.Changed || (frameDone && !PopupFilling.Published && Popups.Count != 0);
}

void Nameplate::PublishCamera(const float* view, const float* projection, const float* viewProjection, const float* viewport,
		const float* lens, uint32_t lensMode) {
	// not valid while it is being written, so an addon reading between never takes half of it
	Camera.Valid = 0;
	if (view == nullptr || projection == nullptr || viewProjection == nullptr || viewport == nullptr) {
		Camera.Frame = Shared.Frame;
		return;
	}
	CopyMemory(Camera.View, view, sizeof(Camera.View));
	CopyMemory(Camera.Projection, projection, sizeof(Camera.Projection));
	CopyMemory(Camera.ViewProjection, viewProjection, sizeof(Camera.ViewProjection));
	Camera.ViewportX = viewport[0];
	Camera.ViewportY = viewport[1];
	Camera.ViewportWidth = viewport[2];
	Camera.ViewportHeight = viewport[3];
	Camera.ViewportMinZ = viewport[4];
	Camera.ViewportMaxZ = viewport[5];
	Camera.Lens = lens != nullptr ? 1 : 0;
	Camera.LensMode = lens != nullptr ? lensMode : 0;
	Camera.LensStrength = lens != nullptr ? lens[0] : 0.0f;
	Camera.LensTanH = lens != nullptr ? lens[1] : 0.0f;
	Camera.LensTanV = lens != nullptr ? lens[2] : 0.0f;
	Camera.Frame = Shared.Frame;
	Camera.Valid = 1;
}

bool Nameplate::WantsPublish(bool frameDone) const {
	return NamesWanted(frameDone) || PopupsWanted(frameDone);
}

// Where a point in the world comes on screen, in pixels from the top left, and how far in front of
// the camera it is: false behind it. m is the view and projection together.
static bool PlaceOnScreen(const float* m, float halfWidth, float halfHeight, float x, float y, float z, float& screenX, float& screenY, float& depth) {
	const float w = x * m[3] + y * m[7] + z * m[11] + m[15];
	if (!(w > 0.01f)) {
		return false;
	}
	const float inverse = 1.0f / w;
	screenX = (1.0f + (x * m[0] + y * m[4] + z * m[8] + m[12]) * inverse) * halfWidth;
	screenY = (1.0f - (x * m[1] + y * m[5] + z * m[9] + m[13]) * inverse) * halfHeight;
	depth = w;
	return true;
}

void Nameplate::Publish(const float* view, const float* projection, bool frameDone) {
	const bool names = NamesWanted(frameDone);
	const bool popups = PopupsWanted(frameDone);

	// the picture is the size of the client's window
	const float width = (Globals.pWindowWidth != nullptr) ? static_cast<float>(*Globals.pWindowWidth) : 0.0f;
	const float height = (Globals.pWindowHeight != nullptr) ? static_cast<float>(*Globals.pWindowHeight) : 0.0f;
	const float halfWidth = width * 0.5f;
	const float halfHeight = height * 0.5f;

	// A point in the world goes through the view and then the projection to where it is on screen
	float m[16];
	const bool placed = (names || popups) && view != nullptr && projection != nullptr && width > 0.0f && height > 0.0f;
	if ((names || popups) && view != nullptr) {
		// the camera never turns past straight up or down, so the world's second axis is up on
		// screen when the view raises it
		Globals.WorldUp = (view[5] < 0.0f) ? -1.0f : 1.0f;
	}
	if (placed) {
		for (int row = 0; row < 4; row++) {
			for (int column = 0; column < 4; column++) {
				m[row * 4 + column] = view[row * 4 + 0] * projection[0 * 4 + column]
					+ view[row * 4 + 1] * projection[1 * 4 + column]
					+ view[row * 4 + 2] * projection[2 * 4 + column]
					+ view[row * 4 + 3] * projection[3 * 4 + column];
			}
		}
	}

	if (popups) {
		const uint32_t count = PopupFilling.Count;
		for (uint32_t i = 0; i < count; i++) {
			HookPopup& popup = PopupFilling.Popups[i];
			popup.Flags &= ~static_cast<uint32_t>(POPUP_ON_SCREEN);
			if (placed && PlaceOnScreen(m, halfWidth, halfHeight, popup.X, popup.Y, popup.Z, popup.ScreenX, popup.ScreenY, popup.Depth)) {
				popup.Flags |= POPUP_ON_SCREEN;
			}
		}

		// the popups are in place before the count says they are there to be read
		Popups.Count = 0;
		CopyMemory(&Popups.Popups[0], &PopupFilling.Popups[0], count * sizeof(HookPopup));
		Popups.Frame = Shared.Frame;
		Popups.Count = count;
		Popups.Sequence++;

		PopupFilling.Changed = false;
		PopupFilling.Published = true;
	}

	if (names) {
		const uint32_t count = Filling.Count;

		for (uint32_t i = 0; i < count; i++) {
			HookName& name = Filling.Names[i];
			name.Flags &= ~static_cast<uint32_t>(NAME_ON_SCREEN);
			if (placed && PlaceOnScreen(m, halfWidth, halfHeight, name.X, name.Y, name.Z, name.ScreenX, name.ScreenY, name.Depth)) {
				name.Flags |= NAME_ON_SCREEN;
			}
		}

		// the names are in place before the count says they are there to be read
		Shared.Count = 0;
		CopyMemory(&Shared.Names[0], &Filling.Names[0], count * sizeof(HookName));
		Shared.Width = width;
		Shared.Height = height;
		Shared.Count = count;
		Shared.NamesDropped = Filling.Dropped;
		Shared.Sequence++;

		Filling.Changed = false;
		Filling.Published = true;
	}

	if (frameDone) {
		Globals.UnownedLast = Globals.Unowned;
		Globals.Unowned = 0;
		Globals.RepeatsLast = Globals.Repeats;
		Globals.RepeatsMainLast = Globals.RepeatsMain;
		Globals.Repeats = 0;
		Globals.RepeatsMain = 0;
		Globals.LiftedLast = Globals.Lifted;
		Globals.Lifted = 0;
		Filling.Count = 0;
		Filling.Dropped = 0;
		Filling.Changed = false;
		Filling.Published = false;
		PopupFilling.Count = 0;
		PopupFilling.Changed = false;
		PopupFilling.Published = false;
		NoteClaim(); // a claim made last frame is timed from then
		NotePopupClaim();
		FreeLapsedSlots();
		SayNewPopups(this);
		Shared.Frame++;
		FrameTime = Clock();

		// Everybody's pets are looked for now and then, and what was found kept in between
		const bool withPets = (Shared.Frame % FACTS_PETS_EVERY) == 1;
		ZeroMemory(&Facts.PartyIds, sizeof(Facts.PartyIds));
		ZeroMemory(&Facts.AllianceIds, sizeof(Facts.AllianceIds));
		Facts.TargetIndex = 0;
		Facts.PetIndex = 0;
		if (withPets) {
			ZeroMemory(&Facts.Pets, sizeof(Facts.Pets));
		}
		GetFrameFacts(Facts, withPets);
	}
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
	Shared.LoadId = 0;

	Shared.Hooked = 0;
	Shared.Count = 0;
	Shared.Draw = 0;
	Filling.Count = 0;

	Popups.Hooked = 0;
	Popups.Count = 0;
	Popups.Draw = 0;
	for (uint32_t i = 0; i < HOOK_CLAIM_SLOTS; i++) {
		Claims.Slots[i].Owner = 0;
		Claims.Slots[i].Categories = 0;
		Claims.Slots[i].Draw = 0;
	}

	// Already stranded (a load refused, or one whose commit could not be taken back): nothing more to do
	if (Stranded) {
		return 0;
	}

	// Every site given back, last first. One something else has changed since is left as it is: the
	// client may still call into this plugin from there, so its module is kept loaded, and what that
	// code reads (Globals) is kept as it is.
	const size_t abandoned = Patches.RestoreAll();
	Globals.OtherCallsTaken = false;
	if (abandoned != 0) {
		Strand();
		return -26;
	}

	Patches.Drop(0);
	ZeroMemory(&Globals, sizeof(Globals));

    return 0;
}
