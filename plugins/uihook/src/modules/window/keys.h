// The game's keyboard, as its chat editor has it. The handler the mouse is taken at (mouse.h) is given each key's
// WM_KEYDOWN and the WM_CHAR TranslateMessage makes of it, from the MSG: the editor takes every key down there but
// Enter, Escape and 6C (0x33729f0), and each character, Enter's sending the line (0x31c7860). Ashita's key event sees
// the key down first and can keep it from this handler, but never sees the character, which reaches it whatever Ashita
// blocked (uihook 1.61 kept nothing in game: it waited for key downs Ashita had already kept). An addon names the virtual keys to keep from the game in the independent keys ABI 1 (magic UIHOOK-KEYS),
// renewed each frame. While a key is named, its key down, its repeats, the characters it types
// and its release are kept from the game; a press begun while it is named is kept whole, its characters and release
// too, though it is named no longer. A key down Ashita blocks never reaches this handler, but the character
// TranslateMessage made of it still does (Enter's sent the line), so a character is kept by its key being named, not
// by its key down having been seen. A press begun with the key not named is the game's, so a release lost to the
// window losing focus keeps nothing past the key's next press. Without a key down seen, only a control character is
// kept by its key being named.
#pragma once
#include <windows.h>
#include <stdint.h>

#define KEYS_HOLD_FRAMES 3 // frames after the addon's last commit that its keys are still kept
#define KEYS_CHARS_MOST 16 // characters a press can have waiting to be kept (its repeats)

struct KeysShared {
    char Magic[16]; uint32_t Version, Size, Frame, Supported; // Supported: 1 where the game's handler was taken
    // Written by the addon: bit vk%32 of word vk/32, a virtual key to keep from the game; then HoldFrame (the block's
    // Frame) as the commit. KEYS_HOLD_FRAMES after the last, nothing is kept.
    uint32_t Hold[8];
    volatile uint32_t HoldFrame;
    uint32_t Kept; // messages kept from the game, counted
};
static_assert(sizeof(KeysShared)==72,"keys ABI 1");

struct GameKeys {
    KeysShared* shared=nullptr;
    bool taken[256]={};           // a press being kept, by virtual key, until its release
    uint8_t chars[512]={};        // characters still to keep, by scan code (bit 8 the extended key's)
    static uint32_t Code(LPARAM lParam) { return uint32_t(lParam>>16)&0x1ff; }
    bool Holding(uint32_t vk) const {
        if (!shared || !shared->Supported || vk>255) return false;
        const uint32_t at=shared->HoldFrame;
        return at!=0 && shared->Frame-at<=KEYS_HOLD_FRAMES && ((shared->Hold[vk>>5]>>(vk&31))&1)!=0;
    }
    void Keep() { if (shared) ++shared->Kept; }
    // The key a control character is typed by (Enter's, Tab's, Escape's, Backspace's), 0 for any other: a printable
    // character is kept only with a key down seen, as a scan code's key is ambiguous (numpad 8's is Up's)
    static uint32_t KeyOf(WPARAM character) {
        return character==VK_RETURN || character==VK_TAB || character==VK_ESCAPE || character==VK_BACK ? uint32_t(character) : 0;
    }
    // Whether the game is given the message
    bool Pass(const MSG& message) {
        const UINT kind=message.message;
        if (kind==WM_KEYDOWN || kind==WM_SYSKEYDOWN) {
            if (message.wParam>255) return true;
            const uint32_t vk=uint32_t(message.wParam), code=Code(message.lParam);
            // bit 30: the key was down already, a repeat; a fresh press is judged afresh
            if (!(message.lParam & 0x40000000)) { taken[vk]=Holding(vk); chars[code]=0; }
            if (!taken[vk] && !Holding(vk)) return true;
            if (chars[code]<KEYS_CHARS_MOST) ++chars[code];
            Keep(); return false;
        }
        if (kind==WM_KEYUP || kind==WM_SYSKEYUP) {
            if (message.wParam>255 || (!taken[message.wParam] && !Holding(uint32_t(message.wParam)))) return true;
            taken[message.wParam]=false;
            Keep(); return false;
        }
        if (kind==WM_CHAR || kind==WM_SYSCHAR || kind==WM_DEADCHAR || kind==WM_SYSDEADCHAR) {
            const uint32_t code=Code(message.lParam);
            if (chars[code]) { --chars[code]; Keep(); return false; }
            if (!Holding(KeyOf(message.wParam))) return true;
            Keep(); return false;
        }
        return true;
    }
    void Clear() { memset(taken,0,sizeof(taken)); memset(chars,0,sizeof(chars)); }
};
