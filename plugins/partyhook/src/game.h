// Verified against the unpacked Phoenix client (2026-10-15 codedump). Never use fixed addresses.
#pragma once

// Window::Render(this), no stack arguments. Updates animation, then draws background/content/cursor.
// Its first six bytes are whole instructions, with no relative operand.
#define WINDOW_PATTERN "83 EC 24 53 55 56 57 8B E9 E8 ?? ?? ?? ?? 66 8B 45 56 33 FF 66 3B C7 7E 05 48 66 89 45 56"
#define WINDOW_STOLEN 6

// hideparty's main-party/target global-pointer discovery. Main party global is at +0x19.
#define PARTY_PATTERN "66 C7 81 82 00 00 00 ?? ?? C7 81 8C 00 00 00 ?? ?? ?? ?? C7 81 90 00 00 00"
#define PARTY_GLOBAL_AT 0x19

// The native menu registry: three adjacent 44-byte entries, name[16], padding[16],
// pointer-to-global at +32, then metadata. partywin / raid1 / raid2 are the actual HUD lists,
// NOT the similarly named party-order menu. Cross-check partywin against hideparty's code signature.
// Unlike hideparty's older alliance code pattern, these entries exist in the captured Phoenix client.
#define OBJECT_WINDOW 8
static bool PartyGlobals(uint8_t* begin, size_t size, uintptr_t main, void*** globals) {
    uint8_t* match = nullptr;
    for (size_t i=0; i+132<=size; i++) {
        uint8_t* at=begin+i;
        if (memcmp(at,"menu    partywin",16) || memcmp(at+44,"menu    raid1   ",16)
            || memcmp(at+88,"menu    raid2   ",16)) continue;
        uintptr_t addresses[3]={};
        bool valid=true;
        for (unsigned j=0;j<3;j++) {
            uint32_t address=0; memcpy(&address,at+j*44+32,4); addresses[j]=address;
            uintptr_t low=reinterpret_cast<uintptr_t>(begin);
            if (address<low || address>low+size-4 || address%4) valid=false;
        }
        if (!valid || addresses[0]!=main || addresses[0]==addresses[1]
            || addresses[0]==addresses[2] || addresses[1]==addresses[2]) continue;
        if (match) return false; // ambiguous registry: leave the game alone
        match=at;
        for (unsigned j=0;j<3;j++) globals[j]=reinterpret_cast<void**>(addresses[j]);
    }
    return match!=nullptr;
}
