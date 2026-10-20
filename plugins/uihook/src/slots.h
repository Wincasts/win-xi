// What each module says of its slots, for /uihook: read on the game's thread, as commands are.
// A slot is in use while its addon's last submission is fresh (two frames), empty or not.
#pragma once
#include <stdint.h>

struct BuffSlots {
    bool loaded = false;   // the module is there
    bool hooked = false;   // it recognised the game's status icons
    bool fresh = false;    // the buff addon is handing a bar over
    uint32_t quads = 0;    // what that bar is drawn with: icons, letters and their edges
};
// Party slots 0-2 the party list and the two alliance lists, 3-5 the target window's three parts;
// HUD 0 the clock, 1 the compass. Bits set for the slots in use, and for those handed over empty.
// Why a capture was refused: the last reason is kept for each of the party module's eleven slots (party,
// alliance and target 0-5, clock and compass 6-7, the two logs and the input bar 8-10) until one is taken.
enum PartyRefusal : uint8_t {
    REFUSED_NONE = 0,
    REFUSED_NO_LIST,            // no window being drawn, or no display
    REFUSED_COMMAND,            // a draw command of a kind that cannot be replayed (a callback, a broken index range)
    REFUSED_TOO_MANY_COMMANDS,  // more than PARTY_MAX_COMMANDS
    REFUSED_TEXTURE_NOT_READY,  // imgui's texture is being made or destroyed
    REFUSED_TEXTURE_ID,         // a texture id that is no 32-bit pointer
    REFUSED_CLIP,               // a clip rectangle that is not a number
    REFUSED_INDEX,              // a vertex index past the buffer
    REFUSED_VERTEX,             // a vertex that is not a number
    REFUSED_TOO_MANY_VERTICES,  // more than PARTY_MAX_VERTICES once clipped
    REFUSED_EXCEPTION,          // the capture threw
};
static inline const char* RefusalName(uint8_t why) {
    static const char* const names[] = { "none", "no window or display", "a draw command that cannot be replayed",
        "too many draw commands", "imgui's texture not ready", "a texture id that is no 32-bit pointer",
        "a clip rectangle that is not a number", "a vertex index past the buffer", "a vertex that is not a number",
        "too many vertices", "the capture threw" };
    return why < sizeof(names) / sizeof(names[0]) ? names[why] : "unknown";
}
static inline const char* PartySlotName(unsigned slot) {
    static const char* const names[11] = { "party list", "alliance 1", "alliance 2", "target window", "sub-target",
        "target of target", "clock", "compass", "primary log", "split log", "input bar" };
    return slot < 11 ? names[slot] : "unknown";
}
struct PartySlots {
    bool loaded = false;
    bool partyHooked = false, targetHooked = false, clockHooked = false, compassHooked = false;
    uint8_t fresh = 0, empty = 0;
    uint8_t hudFresh = 0, hudEmpty = 0;
    bool chatHooked = false;
    uint8_t chatFresh = 0, chatEmpty = 0;
    uint32_t failures = 0;          // captures refused since loading, every slot
    uint8_t refusal[11] = {};       // each slot's last refusal (PartyRefusal), none where its last capture was taken
    uint32_t refusalAge[11] = {};   // frames since that refusal
    uint32_t refusalRun[11] = {};   // and how many refusals in a row it made
};
void GetBuffSlots(BuffSlots& out);
void GetPartySlots(PartySlots& out);
