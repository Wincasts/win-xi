#pragma once
// The plugins' writes to the client's code, in one place (namehook's first, now uihook's and lens's too): each site's bytes as they were found are kept,
// a site is written only over those and taken back only while it still holds what was written, every
// write gets the page protection it needs and flushes the instruction cache, and a set of sites goes in
// whole or not at all.
//
// Memory reads and writes code: Read(at, out, size) and Write(at, bytes, size), each false where it
// could not. WindowsCodeMemory is the real one; the tests have their own to make writes fail.
//
// Everything here runs on the thread that loads and unloads plugins and draws the frame (the game's own):
// a write of several bytes is not atomic, and nothing else may be running the code being written.
#include <windows.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define CODE_PATCH_BYTES_MAX 144 // the largest patch is DrawName3 V2's, 131 bytes
#define CODE_PATCH_SITES_MAX 24  // five patches, the two line calls, and up to fourteen other calls

struct WindowsCodeMemory {
	static bool Readable(DWORD protect) {
		if ((protect & (PAGE_GUARD | PAGE_NOACCESS)) != 0) {
			return false;
		}
		return (protect & (PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READ
			| PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) != 0;
	}

	static bool Writable(DWORD protect) {
		return (protect & (PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) != 0
			&& (protect & PAGE_GUARD) == 0;
	}

	static bool Executable(DWORD protect) {
		return (protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) != 0;
	}

	// Whether every byte from at for size is committed and readable
	static bool Committed(uintptr_t at, size_t size) {
		const uintptr_t end = at + size;
		if (size == 0 || end < at) {
			return false;
		}
		for (uintptr_t p = at; p < end;) {
			MEMORY_BASIC_INFORMATION info;
			if (VirtualQuery(reinterpret_cast<const void*> (p), &info, sizeof(info)) != sizeof(info)
					|| info.State != MEM_COMMIT || !Readable(info.Protect)) {
				return false;
			}
			const uintptr_t next = reinterpret_cast<uintptr_t> (info.BaseAddress) + info.RegionSize;
			if (next <= p) {
				return false;
			}
			p = next;
		}
		return true;
	}

	bool Read(uintptr_t at, uint8_t* out, size_t size) {
		if (!Committed(at, size)) {
			return false;
		}
		memcpy(out, reinterpret_cast<const void*> (at), size);
		return true;
	}

	// Each region the bytes fall in is made writable as needed, and given back its own protection after
	bool Write(uintptr_t at, const uint8_t* bytes, size_t size) {
		if (!Committed(at, size)) {
			return false;
		}

		struct Changed { uintptr_t at; size_t size; DWORD was; };
		Changed changed[4];
		size_t count = 0;
		bool ok = true;
		const uintptr_t end = at + size;
		for (uintptr_t p = at; p < end && ok;) {
			MEMORY_BASIC_INFORMATION info;
			if (VirtualQuery(reinterpret_cast<const void*> (p), &info, sizeof(info)) != sizeof(info)) {
				ok = false;
				break;
			}
			const uintptr_t regionEnd = reinterpret_cast<uintptr_t> (info.BaseAddress) + info.RegionSize;
			const uintptr_t partEnd = regionEnd < end ? regionEnd : end;
			if (!Writable(info.Protect)) {
				DWORD was = 0;
				const DWORD wanted = Executable(info.Protect) ? PAGE_EXECUTE_READWRITE : PAGE_READWRITE;
				if (count == sizeof(changed) / sizeof(changed[0])
						|| !VirtualProtect(reinterpret_cast<void*> (p), partEnd - p, wanted, &was)) {
					ok = false;
					break;
				}
				changed[count++] = { p, partEnd - p, was };
			}
			p = partEnd;
		}

		if (ok) {
			memcpy(reinterpret_cast<void*> (at), bytes, size);
			ok = memcmp(reinterpret_cast<const void*> (at), bytes, size) == 0;
		}

		for (size_t i = count; i-- > 0;) {
			DWORD ignored = 0;
			VirtualProtect(reinterpret_cast<void*> (changed[i].at), changed[i].size, changed[i].was, &ignored);
		}
		if (ok) {
			FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<const void*> (at), size);
		}
		return ok;
	}
};

struct CodePatchSite {
	uintptr_t At;
	uint32_t Size;
	bool Written;   // what this plugin wrote is there
	bool Abandoned; // changed by something else since it was written: left as it was found
	bool Deferred;  // not written by Commit, but on its own when wanted
	bool Harmless;  // holds nothing that leads into the plugin: abandoned, it strands nothing
	uint8_t Original[CODE_PATCH_BYTES_MAX];
	uint8_t Bytes[CODE_PATCH_BYTES_MAX]; // what is written, or to be
};

template <typename Memory>
struct CodePatches {
	Memory Code {};
	CodePatchSite Sites[CODE_PATCH_SITES_MAX] {};
	size_t Count = 0;

	// A site to write, its present bytes kept as its original. -1 where there is no room, it is too
	// large, it overlaps a site already added or cannot be read. A deferred one is left for Write.
	int Add(uintptr_t at, const uint8_t* bytes, size_t size, bool deferred = false) {
		if (Count == CODE_PATCH_SITES_MAX || size == 0 || size > CODE_PATCH_BYTES_MAX || at + size < at) {
			return -1;
		}
		for (size_t i = 0; i < Count; i++) {
			if (at < Sites[i].At + Sites[i].Size && Sites[i].At < at + size) {
				return -1;
			}
		}
		CodePatchSite& site = Sites[Count];
		memset(&site, 0, sizeof(site));
		if (!Code.Read(at, site.Original, size)) {
			return -1;
		}
		site.At = at;
		site.Size = static_cast<uint32_t>(size);
		site.Deferred = deferred;
		memcpy(site.Bytes, bytes, size);
		return static_cast<int>(Count++);
	}

	bool Holds(const CodePatchSite& site, const uint8_t* bytes) {
		uint8_t now[CODE_PATCH_BYTES_MAX];
		return Code.Read(site.At, now, site.Size) && memcmp(now, bytes, site.Size) == 0;
	}

	// Writes a site that still holds its original
	bool Write(int index) {
		if (index < 0 || static_cast<size_t>(index) >= Count) {
			return false;
		}
		CodePatchSite& site = Sites[index];
		if (site.Written) {
			return true;
		}
		if (site.Abandoned || !Holds(site, site.Original)) {
			return false;
		}
		if (!Code.Write(site.At, site.Bytes, site.Size)) {
			// a write that went in only in part is not as found: nothing more is done there
			site.Abandoned = !Holds(site, site.Original);
			return false;
		}
		site.Written = true;
		return true;
	}

	// Gives a site back its original while it still holds what was written. A site something else has
	// changed since is abandoned: never written again, and left as it is.
	bool Restore(int index) {
		if (index < 0 || static_cast<size_t>(index) >= Count) {
			return false;
		}
		CodePatchSite& site = Sites[index];
		if (!site.Written) {
			return !site.Abandoned;
		}
		if (!Holds(site, site.Bytes)) {
			site.Abandoned = !Holds(site, site.Original);
			site.Written = false;
			return !site.Abandoned;
		}
		if (!Code.Write(site.At, site.Original, site.Size)) {
			site.Abandoned = true;
			site.Written = false;
			return false;
		}
		site.Written = false;
		return true;
	}

	// A written site changed in place, while it still holds what was last written
	bool Rewrite(int index, const uint8_t* bytes) {
		if (index < 0 || static_cast<size_t>(index) >= Count) {
			return false;
		}
		CodePatchSite& site = Sites[index];
		if (!site.Written) {
			// not written yet, or given back as found by something else: written afresh where wanted
			if (site.Abandoned) {
				return false;
			}
			memcpy(site.Bytes, bytes, site.Size);
			return site.Deferred || Write(index);
		}
		if (!Holds(site, site.Bytes)) {
			site.Abandoned = !Holds(site, site.Original);
			site.Written = false;
			return false;
		}
		if (!Code.Write(site.At, bytes, site.Size)) {
			return false;
		}
		memcpy(site.Bytes, bytes, site.Size);
		return true;
	}

	// Writes the sites from first to the last added but the deferred, in order, all or none: where one
	// cannot be written those this call wrote are taken back, last first, and it is false.
	bool Commit(size_t first = 0) {
		for (size_t i = first; i < Count; i++) {
			if (Sites[i].Deferred) {
				continue;
			}
			if (!Write(static_cast<int>(i))) {
				for (size_t j = i; j-- > first;) {
					Restore(static_cast<int>(j));
				}
				return false;
			}
		}
		return true;
	}

	// Every site taken back, last first. How many are left abandoned that are not harmless.
	size_t RestoreAll() {
		for (size_t i = Count; i-- > 0;) {
			Restore(static_cast<int>(i));
		}
		return Stranding();
	}

	// How many abandoned sites may still lead into the plugin
	size_t Stranding() const {
		size_t count = 0;
		for (size_t i = 0; i < Count; i++) {
			if (Sites[i].Abandoned && !Sites[i].Harmless) {
				count++;
			}
		}
		return count;
	}

	bool AnyWritten() const {
		for (size_t i = 0; i < Count; i++) {
			if (Sites[i].Written) {
				return true;
			}
		}
		return false;
	}

	// Forgets the sites from first on, none of them written
	void Drop(size_t first) {
		if (first < Count) {
			Count = first;
		}
	}
};

// One site on its own, as a hook takes a call or a function's first bytes: what CodePatches does for each of its
// sites, for one of up to 16 bytes, small enough to keep beside each hook. Write takes the bytes there now as the
// original and writes over them; Restore gives them back only while the site holds what was written, and leaves
// a site something else has changed since (Abandoned), as it found it.
template <typename Memory>
struct CodeSite {
    uintptr_t At = 0;
    uint32_t Size = 0;
    bool Written = false;
    bool Abandoned = false;
    uint8_t Original[16] = {};
    uint8_t Bytes[16] = {};
    Memory Code {};

    bool Holds(const uint8_t* bytes) {
        uint8_t now[16];
        return Code.Read(At, now, Size) && memcmp(now, bytes, Size) == 0;
    }

    // False where the site is written already, too large, cannot be read or cannot be written; a write that went
    // in only in part leaves the site abandoned
    bool Write(uintptr_t at, const uint8_t* bytes, size_t size) {
        if (Written || size == 0 || size > sizeof(Bytes)) {
            return false;
        }
        uint8_t was[16];
        if (!Code.Read(at, was, size)) {
            return false;
        }
        At = at;
        Size = static_cast<uint32_t>(size);
        Abandoned = false;
        memcpy(Original, was, size);
        memcpy(Bytes, bytes, size);
        if (!Code.Write(at, bytes, size)) {
            Abandoned = !Holds(Original);
            return false;
        }
        Written = true;
        return true;
    }

    // True where the original is back, or the site was never written; false where it is left abandoned
    bool Restore() {
        if (!Written) {
            return !Abandoned;
        }
        Written = false;
        if (!Holds(Bytes)) {
            Abandoned = !Holds(Original);
            return !Abandoned;
        }
        if (!Code.Write(At, Original, Size)) {
            Abandoned = true;
            return false;
        }
        return true;
    }
};

// Whether this DLL has left a site behind that the client may still go through into it: then it is pinned (kept
// loaded), and a later load refuses. One for each DLL that includes this header.
inline bool& CodeStranded() {
    static bool stranded = false;
    return stranded;
}

inline void StrandCode() {
    if (CodeStranded()) {
        return;
    }
    CodeStranded() = true;
    HMODULE self = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR> (&CodeStranded), &self);
}
