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
struct PartySlots {
    bool loaded = false;
    bool partyHooked = false, targetHooked = false, clockHooked = false, compassHooked = false;
    uint8_t fresh = 0, empty = 0;
    uint8_t hudFresh = 0, hudEmpty = 0;
};
void GetBuffSlots(BuffSlots& out);
void GetPartySlots(PartySlots& out);
