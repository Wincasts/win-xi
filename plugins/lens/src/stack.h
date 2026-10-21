// Who made a draw: the game's return addresses up the stack. The client's code does not keep frame
// pointers everywhere, so the stack is read as it lies, from the draw outward, and a dword is taken
// as a return address when it points into the client and the bytes before it are a call.
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace lens {

// Whether the bytes just before ra (code[at] being ra's byte, with at bytes before it to read) end
// in a call: call rel32, call reg, call [reg+d8], call [reg+d32], call [d32], and the SIB forms.
inline bool AfterCall(const uint8_t* code, size_t at) {
    auto is = [&](size_t back, uint8_t value) { return at >= back && code[at - back] == value; };
    auto modrm = [&](size_t back) { return at >= back ? code[at - back] : 0xFF; };
    if (is(5, 0xE8)) return true;
    if (is(2, 0xFF) && modrm(1) >= 0xD0 && modrm(1) <= 0xD7) return true;                           // call reg
    if (is(2, 0xFF) && modrm(1) <= 0x17 && modrm(1) >= 0x10 && modrm(1) != 0x14 && modrm(1) != 0x15) return true; // call [reg]
    if (is(3, 0xFF) && modrm(2) >= 0x50 && modrm(2) <= 0x57 && modrm(2) != 0x54) return true;      // call [reg+d8]
    if (is(4, 0xFF) && modrm(3) == 0x54) return true;                                               // call [sib+d8]
    if (is(6, 0xFF) && (modrm(5) == 0x15 || (modrm(5) >= 0x90 && modrm(5) <= 0x97 && modrm(5) != 0x94))) return true; // call [d32], [reg+d32]
    if (is(7, 0xFF) && modrm(6) == 0x94) return true;                                               // call [sib+d32]
    return false;
}

// The first count return addresses into the module (image, size bytes, loaded at base) among the
// stack's dwords, as offsets from base; the rest of out left 0. A return address is never in the first
// bytes of the module, so anything under 8 bytes in is not one.
inline void ReturnAddresses(const uint32_t* stack, size_t dwords, uintptr_t base, const uint8_t* image, size_t size, uint32_t* out, size_t count) {
    size_t found = 0;
    for (size_t i = 0; i < dwords && found < count; ++i) {
        uintptr_t v = stack[i];
        if (v < base + 8 || v >= base + size) continue;
        size_t at = v - base;
        if (AfterCall(image, at)) out[found++] = static_cast<uint32_t>(at);
    }
}

} // namespace lens
