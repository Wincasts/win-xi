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

#include <windows.h>
#include <psapi.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <tuple>

// should be moved elsewhere or removed
// module name should not be hardcoded
class Haystack {
    public:
        constexpr Haystack() : haystack(nullptr), haystacklen(0) {}

        void Refresh() {
            haystack = nullptr;
            haystacklen = 0;
            MODULEINFO ModuleInfo{};
            HMODULE module = GetModuleHandleA("FFXiMain.dll");
            if (module != nullptr && GetModuleInformation(GetCurrentProcess(), module, &ModuleInfo, sizeof(ModuleInfo))) {
                haystack = static_cast<const uint8_t*>(ModuleInfo.lpBaseOfDll);
                haystacklen = static_cast<size_t>(ModuleInfo.SizeOfImage);
            }
        }

        void Retrieve(const uint8_t** pHaystack, size_t* pHaystackLen) {
            if (haystack == nullptr) {
                Refresh();
            }

            if (pHaystack != nullptr) {
                *pHaystack = haystack;
            }

            if (pHaystackLen != nullptr) {
                *pHaystackLen = haystacklen;
            }
        }
    private:
        const uint8_t* haystack;
        size_t haystacklen;
};

// should be moved elsewhere or removed
static Haystack gHaystack;

template<size_t N>
struct SLit {
    constexpr SLit(const char (&str)[N]) {
        std::copy_n(str, N, value);
    }

    uint8_t value[N];
};

static constexpr uint8_t digit(uint8_t x) {
    if (x >= 'A' && x <= 'F') {
        return 10 + (x - 'A');
    } else {
        return x - '0';
    }
}

template<SLit slit>
static consteval auto innerrle() {
    static_assert(sizeof(slit.value) > 1 && sizeof(slit.value) % 2 == 1,
        "a signature must contain complete hex byte pairs");

    // slit - string literal in a wrapper
    // soff - offset into the string literal; the recursion variable
    // aoff - position into the output buffer
    // hedr - position of the current rle header byte
    // phase - keeps track of wildcard vs. literal state
    // hrun - the current literal run length
    // hbgn - position of the current best literal run
    // hbst - length of the best literal run

    // first output byte:
    // - position of largest exact match

    // header bytes:
    // - <0x80: n+1 wildcard bytes
    // - >0x7F: (n-0x7F) exact match bytes

    // could be cleaned up quite a bit now that it is a consteval
    // function and not a recursive template

    enum PHASE {
        INITIAL,
        WILDCARD,
        LITERAL,
    };

    constexpr size_t slen = sizeof(slit.value);
    size_t soff = 0;
    size_t aoff = 1;
    size_t hedr = 0;
    PHASE phase = PHASE::INITIAL;
    size_t hrun = 0;
    size_t hbgn = 0;
    size_t hbst = 0;

    // Preallocate worst case.
    std::array<uint8_t, slen+1> a;
    a.fill(0);

    for (soff = 0; soff < (slen&(~1)); soff += 2) {
        uint8_t s0 = slit.value[soff+0];
        uint8_t s1 = slit.value[soff+1];
        const auto hex = [](uint8_t c) { return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'); };
        if (!((s0 == '?' && s1 == '?') || (hex(s0) && hex(s1)))) {
            throw "invalid signature byte";
        }

        if (s0 == '?' && s1 == '?') {
            // Wildcard phase
            if (phase != PHASE::WILDCARD || a[hedr] == 0x7F) {
                a[aoff] = 0;
                hedr = aoff;
                aoff = aoff + 1;
                phase = PHASE::WILDCARD;
                hrun = 0;
            } else {
                a[hedr] = a[hedr] + 1;
                phase = PHASE::WILDCARD;
                hrun = 0;
            }
        } else {
            // Literal phase
            uint8_t t = digit(s0);
            uint8_t o = digit(s1);
            uint8_t v = (t * 16) + o;

            if (phase != PHASE::LITERAL || hrun == 128) {
                a[aoff+0] = 0x80;
                a[aoff+1] = v;
                hedr = aoff;
                phase = PHASE::LITERAL;
                hrun = 1;
                if (hbst == 0) { hbgn = hedr; hbst = 1; }
                aoff = aoff + 2;
            } else {
                a[hedr] = 0x80 | ((a[hedr] & 0x7F) + 1);
                a[aoff] = v;

                if (hrun + 1 > hbst) {
                    phase = PHASE::LITERAL;
                    hrun = hrun + 1;
                    hbgn = hedr;
                    hbst = hrun;
                    aoff = aoff + 1;
                } else {
                    phase = PHASE::LITERAL;
                    hrun = hrun + 1;
                    aoff = aoff + 1;
                }
            }
        }
    }

    // store the starting position in the start.
    // resulting scan algo:
    // jump to hbgn
    // scan right to end
    // jump to start
    // scan right to hbgn
    if (hbgn == 0 || hbgn > 255) { throw "signature needs a literal needle with an encodable offset"; }
    a[0] = static_cast<uint8_t>(hbgn);
    return std::tuple<std::array<uint8_t, slen+1>, size_t>(a, aoff);
}

template<SLit slit>
static consteval auto rleize() {
    constexpr auto t = innerrle<slit>();

    constexpr auto r = std::get<0>(t);
    constexpr auto l = std::get<1>(t);

    // Truncate result.
    std::array<uint8_t, l> tmp;
    std::copy_n(r.begin(), l, tmp.begin());

    return tmp;
}

// Validate the encoded runs before any candidate pointer is formed. The complete
// decoded span (not just the needle) must fit in the supplied readable region.
static bool SignatureSpan(const uint8_t* sig, size_t length, size_t& span, size_t& rewind) {
    if (sig == nullptr || length < 3 || sig[0] < 1 || sig[0] >= length) { return false; }
    span = rewind = 0;
    bool needle = false;
    for (size_t at = 1; at < length;) {
        const size_t headerAt = at;
        const uint8_t header = sig[at++];
        const size_t run = (header & 0x7F) + 1;
        if (headerAt == sig[0]) {
            if (header < 0x80) { return false; }
            needle = true;
            rewind = span;
        }
        if (run > SIZE_MAX - span) { return false; }
        span += run;
        if (header >= 0x80) {
            if (run > length - at) { return false; }
            at += run;
        }
    }
    return needle;
}

static bool IsSigMatch(const uint8_t* haystack, const uint8_t* start, const uint8_t* end, const uint8_t* entry, size_t rewind) {
    const uint8_t* p = entry;
    const uint8_t* q = haystack;

    while (p < end) {
        uint8_t header = p[0];
        uint8_t runlen = (header & 0x7F) + 1;

        p += 1;

        if (header >= 0x80) {
            if (memcmp(p, q, runlen) != 0) {
                return false;
            }
            p += runlen;
        }

        q += runlen;
    }

    p = start;
    q = haystack - rewind;

    while (p < entry) {
        uint8_t header = p[0];
        uint8_t runlen = (header & 0x7F) + 1;

        p += 1;

        if (header >= 0x80) {
            if (memcmp(p, q, runlen) != 0) {
                return false;
            }
            p += runlen;
        }

        q += runlen;
    }

    return true;
}

inline uint8_t* FindSigIn(const uint8_t* sig, size_t length, const uint8_t* haystack, size_t haystacklen) {
    size_t span = 0, rewind = 0;
    if (haystack == nullptr || !SignatureSpan(sig, length, span, rewind) || span > haystacklen) {
        return nullptr;
    }
    const uint8_t* needle = sig + sig[0];
    const size_t needlelen = (needle[0] & 0x7F) + 1;

    const uint8_t* start = sig + 1;
    const uint8_t* end = sig + length;
    const uint8_t* entry = needle;
    needle++;

    const size_t last = haystacklen - span + rewind;
    if (needlelen > 1) {
        const uint8_t* x = needle;
        const uint8_t* y = haystack;

        size_t j, k, ell;

        if (x[0] == x[1]) {
            k = 2;
            ell = 1;
        } else {
            k = 1;
            ell = 2;
        }

        j = rewind;
        while (j <= last) {
            if (x[1] != y[j + 1]) {
                 j += k;
            } else {
                if (IsSigMatch(&y[j], start, end, entry, rewind)) {
                    return (uint8_t*) &y[j - rewind];
                }

                j += ell;
            }
        }
    } else {
        for (size_t j = rewind; j <= last; j++) {
            if (haystack[j] == needle[0] && IsSigMatch(haystack + j, start, end, entry, rewind)) {
                return const_cast<uint8_t*>(haystack + j - rewind);
            }
        }
    }

    return nullptr;
}

// Never compare across an inaccessible image page. Adjacent readable regions
// are combined so a legitimate signature may still straddle protection boundaries.
inline uint8_t* FindReadableSig(const uint8_t* sig, size_t length, const uint8_t* image, size_t size) {
    if (image == nullptr || size == 0) { return nullptr; }
    size_t offset = 0, begin = 0;
    while (offset < size) {
        MEMORY_BASIC_INFORMATION region{};
        if (VirtualQuery(image + offset, &region, sizeof(region)) == 0) { return nullptr; }
        const uintptr_t at = reinterpret_cast<uintptr_t>(image + offset);
        const uintptr_t base = reinterpret_cast<uintptr_t>(region.BaseAddress);
        if (base > at || at - base >= region.RegionSize) { return nullptr; }
        const size_t bytes = (std::min)(size - offset, static_cast<size_t>(region.RegionSize) - static_cast<size_t>(at - base));
        const DWORD readable = PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY
            | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
        const bool canRead = region.State == MEM_COMMIT && (region.Protect & (PAGE_GUARD | PAGE_NOACCESS)) == 0
            && (region.Protect & readable) != 0;
        if (!canRead) {
            if (auto* found = FindSigIn(sig, length, image + begin, offset - begin)) { return found; }
            begin = offset + bytes;
        }
        offset += bytes;
    }
    return FindSigIn(sig, length, image + begin, size - begin);
}

inline uint8_t* FindSig(const uint8_t* sig, size_t length) {
    const uint8_t* image = nullptr;
    size_t size = 0;
    gHaystack.Retrieve(&image, &size);
    return FindReadableSig(sig, length, image, size);
}

template <size_t N>
class Signature {
    public:
        constexpr Signature(std::array<uint8_t, N> sig) : signature(sig) {}

        uint8_t* Find() const {
            return FindSig(signature.data(), signature.size());
        }

        uint8_t* FindIn(const uint8_t* bytes, size_t length) const {
            return FindSigIn(signature.data(), signature.size(), bytes, length);
        }

    private:
        std::array<uint8_t, N> signature;
};

template<SLit slit>
consteval auto MakeSig() {
    constexpr auto n = rleize<slit>();
    return Signature<n.size()>(n);
}
