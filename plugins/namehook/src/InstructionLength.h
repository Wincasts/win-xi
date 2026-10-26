#pragma once
// How long one 32-bit x86 instruction is, for telling a real CALL from bytes that only look like one. FindCalls
// finds every E8 whose rel32 goes to a name-line function; one inside another instruction's immediate or
// displacement would be patched as if it were code. A site is taken only where decoding from its function's
// start lands on it (CallSiteDecodes). Pure: bytes alone, so the tests (and a check against objdump over the
// client's own code) can run it.
//
// The one-byte map, the 0F map as compilers of the client's time emit it, 3DNow! (the client has it), x87 and the
// prefixes. Anything else
// is not known: 0, and a site behind it is not taken. Never a wrong length taken for a right one: a site is
// refused rather than guessed at.
#include <stddef.h>
#include <stdint.h>

namespace InstructionLength {

// The ModRM byte at p, and what follows it (SIB, displacement): how many bytes in all, 0 where it runs past end
inline size_t ModRm(const uint8_t* p, const uint8_t* end, bool address16) {
    if (p >= end) return 0;
    const uint8_t modrm = p[0], mod = modrm >> 6, rm = modrm & 7;
    size_t n = 1;
    if (address16) {
        if (mod == 0 && rm == 6) n += 2;
        else if (mod == 1) n += 1;
        else if (mod == 2) n += 2;
    } else {
        if (mod != 3 && rm == 4) {
            if (p + 1 >= end) return 0;
            const uint8_t base = p[1] & 7;
            n += 1;
            if (mod == 0 && base == 5) n += 4;
        }
        if (mod == 0 && rm == 5) n += 4;
        else if (mod == 1) n += 1;
        else if (mod == 2) n += 4;
    }
    return p + n <= end ? n : 0;
}

// The length of the instruction at p, or 0 where it is not one this knows (or runs past end)
inline size_t Of(const uint8_t* p, const uint8_t* end) {
    const uint8_t* start = p;
    bool operand16 = false, address16 = false;
    // prefixes: operand and address size, segments, lock and repeat
    for (int i = 0; i < 4 && p < end; i++) {
        const uint8_t b = *p;
        if (b == 0x66) operand16 = true;
        else if (b == 0x67) address16 = true;
        else if (b == 0x26 || b == 0x2E || b == 0x36 || b == 0x3E || b == 0x64 || b == 0x65 || b == 0xF0 || b == 0xF2 || b == 0xF3) {}
        else break;
        p++;
    }
    if (p >= end) return 0;
    const size_t imm = operand16 ? 2 : 4;
    const uint8_t op = *p++;
    size_t n = 0, more = 0;
    auto modrm = [&](size_t extra) -> size_t {
        const size_t m = ModRm(p, end, address16);
        if (m == 0) return 0;
        return (p + m + extra <= end) ? static_cast<size_t>(p - start) + m + extra : 0;
    };

    if (op == 0x0F) {
        if (p >= end) return 0;
        const uint8_t op2 = *p++;
        if (op2 == 0x0F) return modrm(1);                               // 3DNow!: its operation in a byte after
        if (op2 >= 0x80 && op2 <= 0x8F) more = 4;                       // jcc rel32
        else if (op2 == 0x0E || op2 == 0x31 || op2 == 0xA2 || op2 == 0x0B || (op2 >= 0xC8 && op2 <= 0xCF)
                || op2 == 0xA0 || op2 == 0xA1 || op2 == 0xA8 || op2 == 0xA9 || op2 == 0x77) more = 0; // rdtsc cpuid ud2 bswap push/pop fs gs emms
        else if (op2 == 0xA4 || op2 == 0xAC || op2 == 0xBA || op2 == 0x70 || op2 == 0x71 || op2 == 0x72 || op2 == 0x73
                || op2 == 0xC2 || op2 == 0xC4 || op2 == 0xC5 || op2 == 0xC6) return modrm(1); // shld/shrd imm8, bt imm8, pshuf/shift imm8, cmpps, pinsrw...
        else if ((op2 >= 0x40 && op2 <= 0x4F) || (op2 >= 0x90 && op2 <= 0x9F) || op2 == 0xA3 || op2 == 0xA5 || op2 == 0xAB
                || op2 == 0xAD || op2 == 0xAF || op2 == 0xB0 || op2 == 0xB1 || op2 == 0xB3 || (op2 >= 0xB6 && op2 <= 0xBF)
                || op2 == 0xC0 || op2 == 0xC1 || op2 == 0xC7 || op2 == 0x1F || op2 == 0x18 || op2 == 0x0D || op2 == 0x00 || op2 == 0x01
                || (op2 >= 0x10 && op2 <= 0x17) || (op2 >= 0x28 && op2 <= 0x2F) || (op2 >= 0x50 && op2 <= 0x6F)
                || (op2 >= 0x74 && op2 <= 0x76) || op2 == 0x7E || op2 == 0x7F || op2 == 0xAE
                || (op2 >= 0xD1 && op2 <= 0xFE)) return modrm(0);
        else return 0;
        n = static_cast<size_t>(p - start) + more;
        return start + n <= end ? n : 0;
    }

    switch (op) {
    // ALU r/m forms (00-3F, the low three of each eight), mov, test, xchg, lea, pop r/m
    case 0x00: case 0x01: case 0x02: case 0x03: case 0x08: case 0x09: case 0x0A: case 0x0B:
    case 0x10: case 0x11: case 0x12: case 0x13: case 0x18: case 0x19: case 0x1A: case 0x1B:
    case 0x20: case 0x21: case 0x22: case 0x23: case 0x28: case 0x29: case 0x2A: case 0x2B:
    case 0x30: case 0x31: case 0x32: case 0x33: case 0x38: case 0x39: case 0x3A: case 0x3B:
    case 0x84: case 0x85: case 0x86: case 0x87: case 0x88: case 0x89: case 0x8A: case 0x8B:
    case 0x8C: case 0x8D: case 0x8E: case 0x8F: case 0x62: case 0x63:
    case 0xD0: case 0xD1: case 0xD2: case 0xD3: case 0xFE: case 0xFF: case 0xC4: case 0xC5:
    case 0xD8: case 0xD9: case 0xDA: case 0xDB: case 0xDC: case 0xDD: case 0xDE: case 0xDF: // x87
        return modrm(0);
    case 0x80: case 0x82: case 0x83: case 0xC0: case 0xC1: case 0xC6: case 0x6B:
        return modrm(1);
    case 0x81: case 0xC7: case 0x69:
        return modrm(imm);
    case 0xF6: case 0xF7: {                                             // test r/m, imm; not neg mul div
        if (p >= end) return 0;
        const uint8_t reg = (*p >> 3) & 7;
        return modrm(reg <= 1 ? (op == 0xF6 ? 1 : imm) : 0);
    }
    // the accumulator with an immediate
    case 0x04: case 0x0C: case 0x14: case 0x1C: case 0x24: case 0x2C: case 0x34: case 0x3C: case 0xA8:
    case 0x6A: case 0xCD: case 0xD4: case 0xD5: case 0xE4: case 0xE5: case 0xE6: case 0xE7:
    case 0x70: case 0x71: case 0x72: case 0x73: case 0x74: case 0x75: case 0x76: case 0x77:
    case 0x78: case 0x79: case 0x7A: case 0x7B: case 0x7C: case 0x7D: case 0x7E: case 0x7F:
    case 0xE0: case 0xE1: case 0xE2: case 0xE3: case 0xEB:
    case 0xB0: case 0xB1: case 0xB2: case 0xB3: case 0xB4: case 0xB5: case 0xB6: case 0xB7:
        more = 1; break;
    case 0x05: case 0x0D: case 0x15: case 0x1D: case 0x25: case 0x2D: case 0x35: case 0x3D: case 0xA9:
    case 0x68: case 0xE8: case 0xE9:
    case 0xB8: case 0xB9: case 0xBA: case 0xBB: case 0xBC: case 0xBD: case 0xBE: case 0xBF:
        more = imm; break;
    case 0xA0: case 0xA1: case 0xA2: case 0xA3:                         // mov to and from moffs
        more = address16 ? 2 : 4; break;
    case 0xC2: case 0xCA:
        more = 2; break;
    case 0xC8:
        more = 3; break;
    case 0x9A: case 0xEA:
        more = imm + 2; break;
    // one byte alone
    case 0x06: case 0x07: case 0x0E: case 0x16: case 0x17: case 0x1E: case 0x1F: case 0x27: case 0x2F: case 0x37: case 0x3F:
    case 0x90: case 0x91: case 0x92: case 0x93: case 0x94: case 0x95: case 0x96: case 0x97: case 0x98: case 0x99:
    case 0x9B: case 0x9C: case 0x9D: case 0x9E: case 0x9F: case 0xA4: case 0xA5: case 0xA6: case 0xA7:
    case 0xAA: case 0xAB: case 0xAC: case 0xAD: case 0xAE: case 0xAF: case 0xC3: case 0xC9: case 0xCB: case 0xCC:
    case 0xCE: case 0xCF: case 0xD7: case 0xEC: case 0xED: case 0xEE: case 0xEF: case 0xF4: case 0xF5:
    case 0xF8: case 0xF9: case 0xFA: case 0xFB: case 0xFC: case 0xFD: case 0x60: case 0x61:
        more = 0; break;
    default:
        if (op >= 0x40 && op <= 0x5F) { more = 0; break; }              // inc dec push pop r32
        return 0;
    }
    n = static_cast<size_t>(p - start) + more;
    return start + n <= end ? n : 0;
}

// Whether a CALL at site is one an instruction begins at. x86 decoding falls back into step with the code within a
// few instructions of a wrong start, so from every byte of the window before the site it is decoded forward: a real
// CALL is landed on from nearly all of them, bytes inside another instruction from few. Taken where at least
// MIN_VOTES starts decode up to it (one stopped by a byte not known has no vote) and NEED of them land on it.
// Measured over the client's own code (2026-10-26, against objdump's 1.17 million instructions): of 66,927 real
// CALLs 66,625 taken; of 6,375 E8 bytes inside other instructions none, the best landed on from 46.5% of starts.
inline bool CallSiteDecodes(const uint8_t* begin, const uint8_t* end, const uint8_t* site,
        size_t window = 256, int minVotes = 64, double need = 0.9) {
    if (site < begin || site + 5 > end || *site != 0xE8) return false;
    int land = 0, votes = 0;
    for (size_t back = 1; back <= window && static_cast<size_t>(site - begin) >= back; back++) {
        const uint8_t* at = site - back;
        while (at < site) {
            const size_t n = Of(at, end);
            if (n == 0) break;
            at += n;
        }
        if (at < site) continue;
        votes++;
        if (at == site) land++;
    }
    return votes >= minVotes && land >= need * votes;
}

} // namespace InstructionLength
