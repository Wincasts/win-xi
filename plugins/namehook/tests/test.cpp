// Checks which names are shown in each category, what is listed for addons, and the commands and
// files, without the game: the plugin's own source is compiled into this program, the client's patches
// are never applied, and the party is a made-up one. Built and run under wine by tests/run.sh.

// the whitelist's load and save are private; the header is read first, with them opened up
#define private public
#include "../src/Nameplate.h"
#undef private

#include "../src/Nameplate.cpp"
#include "../src/NameBounds.h"
#include "../src/NameSubmission.h"
#include "../src/NameStateBlocks.h"
#include "../../lens/src/warp.h"

#include <string>
#include <vector>

static int failures = 0;

// The plugin's clock, a frame further on each time it is read (once a frame): 1/60 s a frame to begin
// with, a little under, so that half a second is 30 frames as it always was
static uint64_t fakeTime = 0, fakeStep = 16666;
static uint64_t FakeClock() { return fakeTime += fakeStep; }
#define FRAMES_IN(time) static_cast<int>((time) / fakeStep)

#define CHECK(what) do { if (!(what)) { failures++; printf("FAILED line %d: %s\n", __LINE__, #what); } } while (0)

// The rel32 of a call or jump written straight into a test's own stretch of code, its opcode left
static void SetCallTarget(uintptr_t pCall, uintptr_t target) {
	uint8_t call[5];
	CallBytes(call, pCall, target);
	memcpy(reinterpret_cast<uint8_t*> (pCall) + 1, call + 1, 4);
}

// Code memory whose reads and writes can be made to fail, over a buffer of its own
struct FakeCode {
	uint8_t Bytes[256] = {};
	int WritesLeft = -1; // writes before every one fails; -1 for never
	int FailOnce = -1;   // the one write, counted from 0, that fails
	bool Partial = false; // that write gets its first byte in before failing
	int Writes = 0, Tried = 0;
	bool Read(uintptr_t at, uint8_t* out, size_t size) {
		if (at + size > sizeof(Bytes)) { return false; }
		memcpy(out, Bytes + at, size);
		return true;
	}
	bool Write(uintptr_t at, const uint8_t* bytes, size_t size) {
		if (Tried++ == FailOnce || at + size > sizeof(Bytes) || WritesLeft == 0) {
			if (Partial && at < sizeof(Bytes)) { Bytes[at] = bytes[0]; }
			return false;
		}
		if (WritesLeft > 0) { WritesLeft--; }
		Writes++;
		memcpy(Bytes + at, bytes, size);
		return true;
	}
};

static DWORD ProtectionAt(const void* at) {
	MEMORY_BASIC_INFORMATION info;
	return VirtualQuery(at, &info, sizeof(info)) == sizeof(info) ? info.Protect : 0;
}

static void TestCodePatches() {
	static const uint8_t a[] = { 0xA1, 0xA2, 0xA3, 0xA4 }, b[] = { 0xB1, 0xB2 }, c[] = { 0xC1 };
	{
		// a site is kept with its bytes as found; one that overlaps another, is empty, too large or
		// unreadable is refused
		CodePatches<FakeCode> patches;
		for (int i = 0; i < 256; i++) { patches.Code.Bytes[i] = static_cast<uint8_t>(i); }
		CHECK(patches.Add(10, a, sizeof(a)) == 0 && patches.Sites[0].Original[0] == 10 && patches.Sites[0].Original[3] == 13);
		CHECK(patches.Add(13, b, sizeof(b)) == -1 && patches.Add(7, a, sizeof(a)) == -1 && patches.Add(9, b, sizeof(b)) == -1);
		CHECK(patches.Add(14, b, sizeof(b)) == 1 && patches.Add(30, c, 0) == -1 && patches.Add(254, a, sizeof(a)) == -1);
		CHECK(patches.Add(0, a, CODE_PATCH_BYTES_MAX + 1) == -1 && patches.Count == 2);
		CHECK(patches.Add(40, c, sizeof(c), true) == 2);
		CHECK(patches.Code.Writes == 0);

		// committed in order, the deferred left for Write; taken back last first
		CHECK(patches.Commit() && patches.Code.Bytes[10] == 0xA1 && patches.Code.Bytes[15] == 0xB2 && patches.Code.Bytes[40] == 40);
		CHECK(patches.Sites[0].Written && patches.Sites[1].Written && !patches.Sites[2].Written);
		CHECK(patches.Write(2) && patches.Code.Bytes[40] == 0xC1 && patches.Write(2) && patches.Code.Writes == 3);
		CHECK(patches.RestoreAll() == 0 && patches.Code.Bytes[10] == 10 && patches.Code.Bytes[15] == 15 && patches.Code.Bytes[40] == 40);
		CHECK(!patches.AnyWritten());

		// a write that fails partway: what this commit wrote is taken back, and it is false
		patches.Code.FailOnce = patches.Code.Tried + 1;
		CHECK(!patches.Commit() && patches.Code.Bytes[10] == 10 && patches.Code.Bytes[14] == 14 && !patches.AnyWritten());
		CHECK(!patches.Sites[0].Abandoned && !patches.Sites[1].Abandoned);

		// something else writes over a site: left as it is on unload, and never written again; the rest
		// are given back all the same
		CHECK(patches.Commit());
		patches.Code.Bytes[11] = 0xE9;
		CHECK(patches.RestoreAll() == 1 && patches.Sites[0].Abandoned && patches.Code.Bytes[11] == 0xE9 && patches.Code.Bytes[15] == 15);
		CHECK(!patches.Write(0) && patches.Code.Bytes[10] == 0xA1 && patches.RestoreAll() == 1);

		// put back by something else as it was found: nothing is lost, nothing left
		CodePatches<FakeCode> back;
		CHECK(back.Add(20, b, sizeof(b)) == 0 && back.Commit());
		back.Code.Bytes[20] = back.Code.Bytes[21] = 0;
		CHECK(back.Restore(0) && !back.Sites[0].Abandoned && !back.Sites[0].Written);

		// a written site changed in place only while it is as last written
		CodePatches<FakeCode> live;
		CHECK(live.Add(5, c, sizeof(c)) == 0 && live.Commit());
		static const uint8_t jump[] = { 0xEB }, jnz[] = { 0x75 };
		CHECK(live.Rewrite(0, jump) && live.Code.Bytes[5] == 0xEB && live.Rewrite(0, jnz) && live.Code.Bytes[5] == 0x75);
		live.Code.Bytes[5] = 0x90;
		CHECK(!live.Rewrite(0, jump) && live.Code.Bytes[5] == 0x90 && live.Sites[0].Abandoned);
		CHECK(!live.Rewrite(0, jnz) && live.Code.Bytes[5] == 0x90);

		// given back as found by something else, a later change writes it afresh
		CodePatches<FakeCode> again;
		CHECK(again.Add(5, jump, sizeof(jump)) == 0 && again.Commit() && again.Code.Bytes[5] == 0xEB);
		again.Code.Bytes[5] = 0;
		CHECK(!again.Rewrite(0, jnz) && !again.Sites[0].Abandoned && !again.Sites[0].Written);
		CHECK(again.Rewrite(0, jump) && again.Code.Bytes[5] == 0xEB && again.Sites[0].Written);

		// a write that went in only in part leaves the site abandoned, not thought as found
		CodePatches<FakeCode> torn;
		CHECK(torn.Add(0, a, sizeof(a)) == 0);
		torn.Code.FailOnce = 0;
		torn.Code.Partial = true;
		CHECK(!torn.Commit() && torn.Sites[0].Abandoned && torn.Code.Bytes[0] == 0xA1 && torn.Stranding() == 1);

		// a harmless site abandoned strands nothing
		CodePatches<FakeCode> harmless;
		CHECK(harmless.Add(0, c, sizeof(c)) == 0 && harmless.Commit());
		harmless.Sites[0].Harmless = true;
		harmless.Code.Bytes[0] = 0x90;
		CHECK(harmless.RestoreAll() == 0 && harmless.Sites[0].Abandoned);

		// a site that cannot be given back after a failed commit is left abandoned, not forgotten
		CodePatches<FakeCode> stuck;
		CHECK(stuck.Add(0, a, sizeof(a)) == 0 && stuck.Add(8, b, sizeof(b)) == 1);
		stuck.Code.WritesLeft = 1;
		CHECK(!stuck.Commit() && stuck.Sites[0].Abandoned && stuck.Code.Bytes[0] == 0xA1);

		// a write over a site no longer as found is refused before anything is written
		CodePatches<FakeCode> raced;
		CHECK(raced.Add(0, a, sizeof(a)) == 0);
		raced.Code.Bytes[2] = 0x77;
		CHECK(!raced.Commit() && raced.Code.Writes == 0 && raced.Code.Bytes[0] == 0);
	}
	{
		// the real code memory: a write across an executable read-only page and a read-only one is made,
		// each page given back its own protection; nothing is written where nothing can be read
		SYSTEM_INFO info;
		GetSystemInfo(&info);
		const size_t page = info.dwPageSize;
		auto* pages = static_cast<uint8_t*>(VirtualAlloc(nullptr, page * 3, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
		CHECK(pages != nullptr);
		if (pages != nullptr) {
			memset(pages, 0xCC, page * 3);
			DWORD was = 0;
			CHECK(VirtualProtect(pages, page, PAGE_EXECUTE_READ, &was) && VirtualProtect(pages + page, page, PAGE_READONLY, &was)
				&& VirtualProtect(pages + page * 2, page, PAGE_NOACCESS, &was));
			WindowsCodeMemory memory;
			static const uint8_t bytes[] = { 1, 2, 3, 4, 5, 6, 7, 8 };
			const uintptr_t across = reinterpret_cast<uintptr_t> (pages + page - 4);
			CHECK(memory.Write(across, bytes, sizeof(bytes)) && memcmp(pages + page - 4, bytes, sizeof(bytes)) == 0);
			CHECK(ProtectionAt(pages) == PAGE_EXECUTE_READ && ProtectionAt(pages + page) == PAGE_READONLY);
			uint8_t out[8] = {};
			CHECK(memory.Read(across, out, sizeof(out)) && memcmp(out, bytes, sizeof(out)) == 0);
			const uintptr_t into = reinterpret_cast<uintptr_t> (pages + page * 2 - 4);
			CHECK(!memory.Read(into, out, sizeof(out)) && !memory.Write(into, bytes, sizeof(bytes)));
			CHECK(pages[page * 2 - 4] == 0xCC && ProtectionAt(pages + page) == PAGE_READONLY);
			CHECK(!memory.Read(0, out, 1) && !memory.Write(reinterpret_cast<uintptr_t> (pages), bytes, 0));

			// a patch over real code, ownership and all
			CodePatches<WindowsCodeMemory> patches;
			const uintptr_t at = reinterpret_cast<uintptr_t> (pages + 16);
			CHECK(patches.Add(at, a, sizeof(a)) == 0 && patches.Commit() && pages[16] == 0xA1 && ProtectionAt(pages) == PAGE_EXECUTE_READ);
			CHECK(patches.RestoreAll() == 0 && pages[16] == 0xCC && ProtectionAt(pages) == PAGE_EXECUTE_READ);
			VirtualFree(pages, 0, MEM_RELEASE);
		}
	}
}

struct TestPlugin : public Nameplate {
	std::vector<std::string> said;
	std::vector<std::string> errors;
	std::vector<MESSAGE> messages;
	wchar_t configPath[MAX_PATH];
	uint32_t target = 0;
	int begun = 0;
	int custom = 0;
	const HookQuad* lastQuads = nullptr;
	uint32_t lastCount = 0;
	float lastX = 0.0f;
	int bubbles = 0;

	void BeginNames(const HookDraw&, bool, float& targetWidth, float& targetHeight, uint32_t&) override {
		begun++;
		targetWidth = 1200.0f;
		targetHeight = 900.0f;
	}
	void DrawCustom(uint32_t, const HookDrawing& drawing, const HookQuad* quads, const float* position) override {
		custom++;
		lastX = position[0];
		lastQuads = quads;
		lastCount = drawing.Count;
	}

	int clientDrew = 0;
	void ClientDrew() override {
		clientDrew++;
	}
	void DrawBubble(uint32_t, const HookDrawing& drawing, const HookQuad* quads, const float*) override {
		bubbles++;
		CHECK(drawing.Count == 1 && quads == &Bubbles.Draw.Quads[0]);
	}

	void Debug(const char* text) override {
		said.push_back(text);
	}
	void ShowMessage(MESSAGE message, int) override {
		messages.push_back(message);
	}
	void CommandError(const char* command) override {
		errors.push_back(command);
	}
	bool GetConfigPath(wchar_t path[UNICODE_MAX_PATH]) override {
		StringCchCopyW(path, UNICODE_MAX_PATH, configPath);
		return true;
	}
	int petLooks = 0;
	void GetFrameFacts(FrameFacts& facts, bool withPets) override {
		if (withPets) {
			petLooks++;
		}
		facts.PartyIds[0] = 0x1000;
		facts.PartyIds[1] = 0x2000;
		facts.PartyIds[2] = 0x01009999; // a trust
		facts.AllianceIds[4] = 0x3000;
		facts.TargetIndex = target;
		facts.PetIndex = 0x701;
		facts.Pets[0x701 / 8] |= 1 << (0x701 % 8);
		facts.Pets[0x702 / 8] |= 1 << (0x702 % 8);
	}
	uint32_t GetSpawnFlags(uint32_t entityIndex) override {
		return (entityIndex == 300) ? 0x10 : 0x02;
	}
	int popupsBegun = 0;
	bool popupsFresh = false;
	int popupsDrawn = 0;
	uint32_t popupSlot = 0;
	float popupX = 0.0f;
	const HookQuad* popupQuads = nullptr;
	void BeginPopups(const HookPopupDraw&, bool fresh) override {
		popupsBegun++;
		popupsFresh = fresh;
	}
	void DrawPopup(uint32_t slot, const HookPopupDrawing&, const HookQuad* quads, const float* position) override {
		popupsDrawn++;
		popupSlot = slot;
		popupX = position[0];
		popupQuads = quads;
	}

	// the actors the host knows: entity 0x123's and 0x456's
	uintptr_t actors[2] = {};
	int actorLooks = 0;
	uint32_t GetActorEntity(uintptr_t pointer) override {
		actorLooks++;
		return (pointer == actors[0]) ? 0x123 : (pointer == actors[1]) ? 0x456 : HOOK_ENTITIES;
	}
};

static XiModel models[16];
static Entity entities[16];

static const XiModel* Make(int slot, uint32_t index, uint32_t id, const char* name, bool attackable = false) {
	ZeroMemory(&entities[slot], sizeof(Entity));
	entities[slot].EntityIndex = index;
	entities[slot].EntityId = id;
	StringCbCopyA(entities[slot].Name, sizeof(entities[slot].Name), name);
	entities[slot].Flags0 = attackable ? (1u << 13) : 0;
	models[slot].pEntity = &entities[slot];
	return &models[slot];
}

// Stand-ins for the client's two functions that draw a line of a name
static int lines = 0;
static int lines2 = 0;

static void __fastcall FakeLine(const XiModel*, void*, const float*, const char*, uint32_t, uint32_t, uint32_t) {
	lines++;
}

static void __fastcall FakeLine2(const XiModel*, void*, const float*, const char*, uint32_t) {
	lines2++;
}

static const float where[3] = { 1.5f, -2.5f, 3.5f };
static const uint32_t one = 0x3F800000;

// Whether the client is left to draw this name, by the way taken when its calls are in the plugin's hands
static bool Drawn(const XiModel* model, const char* text = "", const char* second = "") {
	int before = lines;
	int before2 = lines2;
	DrawNameLine(model, nullptr, where, text, one, 0x80406080, 0x80102030);
	DrawNameLine2(model, nullptr, where, second, one);
	CHECK((lines - before) == (lines2 - before2));
	return lines != before;
}

// Forgets which names have been drawn this frame, so that one drawn again is taken as if in a frame of
// its own: a name drawn twice in a frame is otherwise listed, and drawn for an addon, once
static void Fresh() {
	ZeroMemory(&Seen, sizeof(Seen));
}

static uint32_t CategoryOf(const XiModel* model) {
	uint32_t flags = 0;
	return Classify(model->pEntity, flags);
}

struct FakeStateDevice {
    HRESULT begin = S_OK, end = S_OK, capture = S_OK, applyNames = S_OK, restore = S_OK;
    int begun = 0, ended = 0, configured = 0, captures = 0, applications = 0, restores = 0;
    HRESULT BeginStateBlock() { begun++; return begin; }
    HRESULT EndStateBlock(DWORD* token) { ended++; *token = SUCCEEDED(end) ? 1 : 0; return end; }
    HRESULT CaptureStateBlock(DWORD) { captures++; return capture; }
    HRESULT ApplyStateBlock(DWORD token) {
        if (token == 1) { applications++; return applyNames; }
        restores++; return restore;
    }
};

int main() {
	TestCodePatches();
	{
		// a drawing drawn this frame but not as it can be drawn is refused and counted; none at all is not counted
		static HookDraw draw;
		ZeroMemory(&draw, sizeof(draw));
		draw.Frame = Shared.Frame;
		draw.QuadCount = 10;
		const uint32_t before = Shared.DrawingsRefused;
		CHECK(FindDrawing(5, draw) == nullptr && Shared.DrawingsRefused == before);
		draw.Entities[5] = { draw.Frame, 0, 4, 1.0f, 0.0f, 0 };
		CHECK(FindDrawing(5, draw) != nullptr && Shared.DrawingsRefused == before);
		draw.Entities[5].Count = HOOK_QUADS_PER_NAME + 1;
		CHECK(FindDrawing(5, draw) == nullptr && Shared.DrawingsRefused == before + 1);
		draw.Entities[5] = { draw.Frame, 8, 4, 1.0f, 0.0f, 0 };
		CHECK(FindDrawing(5, draw) == nullptr && Shared.DrawingsRefused == before + 2);
		CHECK(offsetof(HookShared, LoadId) == offsetof(HookShared, Names) + sizeof(Shared.Names));
	}
	{
		// the camera addons place things with: what the host readied, this frame's, lens's warp with it or not
		TestPlugin cameraHost;
		float view[16] = {}, projection[16] = {}, both[16] = {};
		for (int i = 0; i < 16; i++) { view[i] = static_cast<float>(i); projection[i] = static_cast<float>(i + 16); both[i] = static_cast<float>(i + 32); }
		const float viewport[6] = { 0, 0, 6880, 2880, 0, 1 };
		const float warp[3] = { 0.25f, 2.0f, 0.9f };
		CHECK(memcmp(Camera.Magic, "NAMEHOOKCAMERA", 14) == 0 && Camera.Version == 1 && Camera.Size == sizeof(HookCamera));
		cameraHost.PublishCamera(view, projection, both, viewport, warp, 1);
		CHECK(Camera.Valid == 1 && Camera.Frame == Shared.Frame && Camera.View[5] == 5 && Camera.Projection[0] == 16 && Camera.ViewProjection[15] == 47);
		CHECK(Camera.ViewportWidth == 6880 && Camera.ViewportHeight == 2880 && Camera.ViewportMaxZ == 1);
		CHECK(Camera.Lens == 1 && Camera.LensMode == 1 && Camera.LensStrength == 0.25f && Camera.LensTanH == 2.0f && Camera.LensTanV == 0.9f);
		cameraHost.PublishCamera(view, projection, both, viewport, nullptr, 1);
		CHECK(Camera.Valid == 1 && Camera.Lens == 0 && Camera.LensMode == 0 && Camera.LensStrength == 0);
		cameraHost.PublishCamera(nullptr, nullptr, nullptr, nullptr, nullptr, 0);
		CHECK(Camera.Valid == 0 && Camera.Frame == Shared.Frame);
	}
    {
        FakeStateDevice device;
        DWORD token = 0;
        auto configure = [](FakeStateDevice* d) { d->configured++; };
        device.begin = E_FAIL;
        CHECK(!NameStateBlocks::Record(&device, token, configure));
        CHECK(token == 0 && device.configured == 0 && device.ended == 0);
        device.begin = S_OK; device.end = E_FAIL;
        CHECK(!NameStateBlocks::Record(&device, token, configure) && token == 0);
        device.end = S_OK;
        CHECK(NameStateBlocks::Record(&device, token, configure) && token == 1);
        const int begun = device.begun;
        CHECK(NameStateBlocks::Record(&device, token, configure) && device.begun == begun);
        bool captured = false;
        device.capture = E_FAIL;
        CHECK(!NameStateBlocks::Activate(&device, 2, 1, captured, true));
        CHECK(!captured && device.applications == 0);
        device.capture = S_OK;
        CHECK(NameStateBlocks::Activate(&device, 2, 1, captured, true) && captured);
        const int captures = device.captures;
        CHECK(NameStateBlocks::Activate(&device, 2, 1, captured, true) && device.captures == captures);
        CHECK(NameStateBlocks::Activate(&device, 2, 1, captured, false) && device.captures == captures + 1);
        CHECK(NameStateBlocks::Restore(&device, 2, captured) && captured);
        device.applyNames = E_FAIL;
        const int restores = device.restores;
        CHECK(!NameStateBlocks::Activate(&device, 2, 1, captured, true));
        CHECK(!captured && device.restores == restores + 1);
        device.applyNames = S_OK;
        CHECK(NameStateBlocks::Activate(&device, 2, 1, captured, true) && captured);
        device.restore = E_FAIL;
        CHECK(!NameStateBlocks::Restore(&device, 2, captured) && !captured);
    }
    // Scanning must bound the complete signature, including wildcard prefixes/suffixes.
    {
        constexpr auto prefixed = MakeSig<"??ABCD">();
        constexpr auto suffixed = MakeSig<"ABCD??EF">();
        constexpr auto single = MakeSig<"AA??">();
        const uint8_t bytes[] = { 0xAB, 0xCD, 0, 0xEF };
        CHECK(prefixed.Find() == nullptr); // FFXiMain.dll is absent in this test process
        CHECK(prefixed.FindIn(nullptr, 0) == nullptr);
        CHECK(prefixed.FindIn(bytes, 0) == nullptr);
        CHECK(prefixed.FindIn(bytes, 1) == nullptr);
        CHECK(prefixed.FindIn(bytes, sizeof(bytes)) == nullptr); // no byte before the literal
        CHECK(suffixed.FindIn(bytes, 3) == nullptr); // literal fits but suffix does not
        CHECK(suffixed.FindIn(bytes, sizeof(bytes)) == bytes);
        const uint8_t valid[] = { 0, 0xAB, 0xCD };
        CHECK(prefixed.FindIn(valid, sizeof(valid)) == valid); // match at the final legal start
        const uint8_t oneByte[] = { 0, 0xAA, 0 };
        CHECK(single.FindIn(oneByte, sizeof(oneByte)) == oneByte + 1);
        const uint8_t malformed[] = { 1, 0x83, 0xAB }; // truncated encoded literal
        CHECK(FindSigIn(malformed, sizeof(malformed), bytes, sizeof(bytes)) == nullptr);
        const uint8_t insideLiteral[] = { 2, 0x81, 0xAB, 0xCD };
        CHECK(FindSigIn(insideLiteral, sizeof(insideLiteral), bytes, sizeof(bytes)) == nullptr);
        // Guard pages turn prefix/suffix overreads into deterministic test failures.
        SYSTEM_INFO info{};
        GetSystemInfo(&info);
        auto* pages = static_cast<uint8_t*>(VirtualAlloc(nullptr, info.dwPageSize * 4, MEM_RESERVE, PAGE_NOACCESS));
        CHECK(pages != nullptr);
        if (pages != nullptr) {
            auto* page = static_cast<uint8_t*>(VirtualAlloc(pages + info.dwPageSize, info.dwPageSize * 2, MEM_COMMIT, PAGE_READWRITE));
            CHECK(page != nullptr);
            if (page != nullptr) {
                page[0] = 0xAB; page[1] = 0xCD;
                CHECK(prefixed.FindIn(page, 3) == nullptr);
                uint8_t* tail = page + info.dwPageSize * 2 - 3;
                tail[0] = 0xAB; tail[1] = 0xCD; tail[2] = 0;
                CHECK(suffixed.FindIn(tail, 3) == nullptr);
                // A full image scan skips the first/last reserved pages, but may
                // match across two adjacent readable pages of different protection.
                const auto encoded = rleize<"12345678">();
                uint8_t* cross = page + info.dwPageSize - 2;
                cross[0] = 0x12; cross[1] = 0x34; cross[2] = 0x56; cross[3] = 0x78;
                DWORD oldProtect = 0;
                CHECK(VirtualProtect(page + info.dwPageSize, info.dwPageSize, PAGE_READONLY, &oldProtect));
                CHECK(FindReadableSig(encoded.data(), encoded.size(), pages, info.dwPageSize * 4) == cross);
                const auto absent = rleize<"12345679">();
                CHECK(FindReadableSig(absent.data(), absent.size(), pages, info.dwPageSize * 4) == nullptr);
            }
            VirtualFree(pages, 0, MEM_RELEASE);
        }
        CHECK(drawName3V2PatchLocationSig.FindIn(bytes, sizeof(bytes)) == nullptr);
    }
    CHECK(sizeof(HookCapabilities) == 32);
    CHECK(NamehookCapabilities.Size == sizeof(HookCapabilities) && NamehookCapabilities.Version == 1);
    CHECK((NamehookCapabilities.Features & FEATURE_EDGE_RADIUS) != 0 && (NamehookCapabilities.Features & FEATURE_DOUBLED) != 0 && (NamehookCapabilities.Features & FEATURE_SOFT_TEXTURE) != 0 && NamehookCapabilities.Build == NAMEHOOK_VERSION_MAJOR * 100 + NAMEHOOK_VERSION_MINOR);
    {
        const NameBounds bounds{ -50, -10, 50, 10 };
        CHECK(!bounds.Intersects(-60, 540, 0, 0, 1920, 1080));
        for (auto mode : { lens::Panini, lens::Cylindrical }) {
            double counter[4];
            lens::Counter(-60.0 / 1920, .5, 1920, 1080, 1.8, 1.0125, mode, 1, counter);
            const auto warped = bounds.Transformed(counter[0], counter[1], counter[2], counter[3]);
            CHECK(warped.Intersects(-60, 540, 0, 0, 1920, 1080));
            CHECK(!warped.Intersects(-1000, 540, 0, 0, 1920, 1080));
        }
        const auto shear = bounds.Transformed(.5f, .3f, -.2f, 2);
        CHECK(shear.Left < -29 && shear.Right > 29 && shear.Top < -31 && shear.Bottom > 31);
        const auto contracted = bounds.Transformed(.01f, 0, 0, .01f);
        CHECK(contracted.Left < -1 && contracted.Top < -1); // retain the screen-space AA fringe
        const auto extreme = bounds.Transformed(.1f, 100, 0, .001f);
        NameGeometry::SoftRectangle rectangle;
        CHECK(rectangle.Make({ -1005, -.01f }, { -995, -.01f }, { 995, .01f }));
        for (const auto& point : rectangle.Outer) {
            CHECK(point.x >= extreme.Left && point.x <= extreme.Right);
            CHECK(point.y >= extreme.Top && point.y <= extreme.Bottom);
        }
    }
    {
        int first = 1, second = 2;
        int* textures[8] = { &first, &second, nullptr, nullptr, &first };
        NameRun runs[16]{};
        uint32_t count = 0;
        CHECK(!NameSubmission::Visible(0x00FFFFFF) && NameSubmission::Visible(0x01000000));
        NameSubmission::Append(runs, count, 0, 0, 6, 0x40000000, textures);
        CHECK(count == 1 && !runs[0].WritesDepth(128));
        NameSubmission::Append(runs, count, 4, 6, 6, 0xFFFFFFFF, textures);
        CHECK(count == 1 && runs[0].first == 0 && runs[0].count == 12 && runs[0].WritesDepth(128));
        NameSubmission::Append(runs, count, 1, 12, 6, 0x7FFFFFFF, textures);
        CHECK(count == 2 && !runs[1].WritesDepth(128));
        NameSubmission::Append(runs, count, 1, 18, 6, 0x80FFFFFF, textures);
        CHECK(count == 2 && runs[1].count == 12 && runs[1].WritesDepth(128));
        NameSubmission::Append(runs, count, 0, 24, 6, 0xFFFFFFFF, textures);
        CHECK(count == 3 && runs[2].first == 24); // no reordering across a different texture
        // a doubled quad is a run of its own, though of the same texture, and not doubled the next
        NameSubmission::Append(runs, count, 0, 30, 6, 0xFF8F1F8F, textures, true);
        CHECK(count == 4 && runs[3].doubled && !runs[2].doubled && runs[3].first == 30);
        NameSubmission::Append(runs, count, 0, 36, 6, 0xFF8F1F8F, textures, true);
        CHECK(count == 4 && runs[3].count == 12);
        NameSubmission::Append(runs, count, 0, 42, 6, 0xFF000000, textures);
        CHECK(count == 5 && !runs[4].doubled);
    }
	Clock = FakeClock;
	static_assert(offsetof(Entity, Name) == 0x7C);
	static_assert(offsetof(Entity, Flags0) == 0x120);

	// what an addon reads is laid out as it expects, and found by its first bytes
	static_assert(sizeof(HookName) == 128 && offsetof(HookName, Name) == 52 && offsetof(HookName, Text) == 80);
	static_assert(offsetof(HookShared, Version) == 16 && offsetof(HookShared, Hidden) == 32 && offsetof(HookShared, Frame) == 48 && offsetof(HookShared, Sequence) == 64);
	static_assert(offsetof(HookShared, Draw) == 68 && offsetof(HookShared, TargetWidth) == 72);
	static_assert(sizeof(HookQuad) == 48 && sizeof(HookDrawing) == 24 && offsetof(HookDraw, Textures) == 16);
	static_assert(offsetof(HookDraw, Entities) == 48 && offsetof(HookDraw, Quads) == 48 + 24 * HOOK_ENTITIES);
	static_assert(offsetof(HookShared, FontTexture) == 80);
	static_assert(offsetof(HookShared, Override) == 84 && offsetof(HookShared, Names) == 84 + HOOK_ENTITIES);
	CHECK(memcmp(Shared.Magic, "NAMEHOOK\0\0\0\0\0\0\0", 16) == 0 && Shared.Version == 3);
	CHECK(Shared.Size == sizeof(HookShared) && Shared.NameSize == sizeof(HookName));

	// Native scale factors are reused, but dimensions/settings invalidate them.
	{
		CGame game{};
		game.BackgroundWidth = 1440;
		game.BackgroundHeight = 1080;
		CGame* currentGame = &game;
		uint32_t width = 960, height = 540;
		Globals.pgGame = &currentGame;
		Globals.pWindowWidth = &width;
		Globals.pWindowHeight = &height;
		AsmSettings.FontSize = 22;
		AsmSettings.DamageFontSize = 11;
		const float half = 0.5f;
		float result[2] = {};
		GetNameplateScale(result, &half);
		CHECK(result[0] == 1.5f && result[1] == 2.0f && ScaleFactors.Valid);
		GetDamageNumberScale(result, &half);
		CHECK(result[0] == 0.75f && result[1] == 1.0f);
		game.BackgroundWidth = 720;
		GetNameplateScale(result, &half);
		CHECK(result[0] == 0.75f && result[1] == 2.0f);
		AsmSettings.FontSize = 44;
		GetNameplateScale(result, &half);
		CHECK(result[0] == 1.5f && result[1] == 4.0f);
		width = 480;
		GetNameplateScale(result, &half);
		CHECK(result[0] == 3.0f && result[1] == 4.0f);
		width = 0;
		CHECK(!UpdateScaleFactors());
		currentGame = nullptr;
		CHECK(!UpdateScaleFactors());
		Globals.pgGame = nullptr;
		Globals.pWindowWidth = Globals.pWindowHeight = nullptr;
	}

	// Soft rectangle ramps stay one render-target pixel wide AFTER a Lens-style
	// affine transform, including rotated, sheared and nonuniformly scaled bars.
	{
		static_assert(NameGeometry::CopiesPerQuad >= 10);
		for (const auto& offset : NameGeometry::Halo) {
			CHECK(std::fabs(offset.x * offset.x + offset.y * offset.y - 1) < 0.00001f);
		}
		const NameGeometry::Point transforms[][3] = {
			{ { 10, 20 }, { 110, 20 }, { 10, 28 } },
			{ { 10, 20 }, { 110, 22 }, { 12, 28 } },
			{ { 10, 20 }, { 110, 70 }, { 6, 28 } },
			{ { 10, 20 }, { 210, 20 }, { 10, 24 } },
		};
		for (const auto& points : transforms) {
			NameGeometry::SoftRectangle rect;
			CHECK(rect.Make(points[0], points[1], points[2]));
			CHECK(rect.Coverage == 1);
			const float ax = points[1].x - points[0].x, ay = points[1].y - points[0].y;
			const float length = std::sqrt(ax * ax + ay * ay);
			auto distance = [&](NameGeometry::Point p) {
				return (ax * (p.y - points[0].y) - ay * (p.x - points[0].x)) / length;
			};
			CHECK(std::fabs(distance(rect.Inner[0]) - 0.5f) < 0.00001f);
			CHECK(std::fabs(distance(rect.Outer[0]) + 0.5f) < 0.00001f);
		}
		// a textured rectangle's points carry where they are in it; the fringe stops at its edge
		{
			NameGeometry::SoftRectangle rect;
			CHECK(rect.Make({ 0, 0 }, { 100, 0 }, { 0, 8 }));
			CHECK(std::fabs(rect.InnerAt[0].x - 0.005f) < 0.00001f && std::fabs(rect.InnerAt[0].y - 0.0625f) < 0.00001f);
			CHECK(std::fabs(rect.InnerAt[2].x - 0.995f) < 0.00001f && std::fabs(rect.InnerAt[2].y - 0.9375f) < 0.00001f);
			CHECK(rect.OuterAt[0].x == 0 && rect.OuterAt[0].y == 0 && rect.OuterAt[2].x == 1 && rect.OuterAt[2].y == 1);
			CHECK(rect.OuterAt[1].x == 1 && rect.OuterAt[1].y == 0 && rect.OuterAt[3].x == 0 && rect.OuterAt[3].y == 1);
		}
		NameGeometry::SoftRectangle tiny;
		CHECK(tiny.Make({ 0, 0 }, { 0.25f, 0 }, { 0, 4 }));
		CHECK(tiny.Coverage == 0.25f && tiny.Inner[0].x == tiny.Inner[1].x);
		CHECK(!tiny.Make({ 0, 0 }, { 0, 0 }, { 0, 4 }));
		CHECK(!tiny.Make({ 0, 0 }, { 4, 0 }, { 8, 0 }));
	}

	// Whole-drawing culling is conservative: visible text with an off-screen
	// anchor, outlines, stars and checked detail lines must all survive.
	{
		HookQuad quad{};
		quad.Flags = QUAD_EDGED;
		quad.Reserved = 191; // legacy/ordinary quads ignore this byte
		CHECK(quad.EdgeOpacity() == 1.0f);
		quad.Flags |= QUAD_EDGE_OPACITY;
		CHECK(quad.EdgeOpacity() == 191.0f / 255.0f);
		quad.Reserved = 0;
		CHECK(quad.EdgeOpacity() == 0.0f);
		quad.Reserved = 255;
		CHECK(quad.EdgeOpacity() == 1.0f);
		CHECK(quad.EdgeRadius(3) == 3 && quad.EdgeRadius(20) == 8 && quad.EdgeShadow());
		quad.Flags |= QUAD_TIGHT_EDGE;
		CHECK(quad.EdgeRadius(3) == 1 && quad.EdgeRadius(20) == 1 && !quad.EdgeShadow());
		CHECK(quad.EdgeRadius(0) == 0 && quad.EdgeRadius(0.5f) == 0.5f);
		quad.Flags = QUAD_EDGED | QUAD_EDGE_OPACITY | QUAD_TIGHT_EDGE | QUAD_EDGE_RADIUS;
		quad.Reserved = (640 << 8) | 128;
		CHECK(quad.EdgeRadius(0) == 2.5f && quad.EdgeRadius(8) == 2.5f && !quad.EdgeShadow());
		CHECK(quad.EdgeOpacity() == 128.0f / 255.0f);
		quad.Reserved = (0xFFFF << 8) | 255;
		CHECK(quad.EdgeRadius(0) == 8);
		quad.Reserved = 640 << 8;
		CHECK(quad.EdgeRadius(3) == 0); // zero opacity skips invisible halo passes
		quad.Flags = QUAD_TIGHT_EDGE;
		CHECK(quad.EdgeRadius(3) == 0 && !quad.EdgeShadow());
	}
	{
		HookDrawing drawing{};
		drawing.Frame = 1;
		drawing.Count = 3;
		drawing.Edge = 2.0f;
		HookQuad quads[3]{};
		quads[0].X0 = -30; quads[0].X1 = 30;
		quads[0].Y0 = 0; quads[0].Y1 = 12; quads[0].Flags = 1;
		quads[1].X0 = -5; quads[1].X1 = 5;
		quads[1].Y0 = -20; quads[1].Y1 = -10; // stars, without an outline
		quads[2].X0 = -50; quads[2].X1 = 50;
		quads[2].Y0 = 16; quads[2].Y1 = 28; quads[2].Flags = 1; // detail line
		NameBoundsCache cache;
		const NameBounds first = cache.Get(drawing, quads);
		CHECK(first.Left == -52 && first.Right == 52 && first.Top == -20 && first.Bottom == 30 + NameGeometry::ShadowDrop);
		CHECK(first.Intersects(-10, 10, 0, 0, 100, 100)); // anchor off screen, letters visible
		CHECK(first.Intersects(-40, 10, 0, 0, 100, 100)); // only the detail line reaches in
		CHECK(first.Intersects(50, 115, 0, 0, 100, 100)); // only the stars reach in
		CHECK(first.Intersects(-51, 10, 0, 0, 100, 100)); // outline reaches in
		CHECK(!first.Intersects(-53, 10, 0, 0, 100, 100));
		CHECK(!first.Intersects(153, 10, 0, 0, 100, 100));
		CHECK(!first.Intersects(50, -31, 0, 0, 100, 100));
		CHECK(!first.Intersects(50, 121, 0, 0, 100, 100));
		CHECK(first.Intersects(-52, 10, 0, 0, 100, 100)); // touching boundary is retained
		CHECK(first.Intersects(200, 200, 200, 200, 100, 100)); // viewport has an offset
		quads[2].X1 = 80;
		CHECK(cache.Get(drawing, quads).Right == 52); // geometry is cached for this batch
		drawing.Frame++;
		CHECK(cache.Get(drawing, quads).Right == 82);
		drawing.Edge = 20; // expansion is capped at eight, as in the renderer
		CHECK(cache.Get(drawing, quads).Right == 88);
		drawing.Count = 1;
		CHECK(cache.Get(drawing, quads).Right == 38);
		quads[0].X1 = 40;
		drawing.First++;
		CHECK(cache.Get(drawing, quads).Right == 48);
		CHECK(cache.Get(drawing, quads, 2.0f).Right == 56);
		CHECK(cache.Get(drawing, quads, 0.5f).Right == 44);
		CHECK(cache.Get(drawing, quads, 0.5f).Top == -8);
		CHECK(cache.Get(drawing, quads, 1.0f).Right == 48);
		quads[0].Flags = QUAD_SOFT_RECT;
		drawing.Frame++;
		const auto soft = cache.Get(drawing, quads);
		CHECK(soft.Left == -31 && soft.Right == 41 && soft.Top == -1 && soft.Bottom == 13);
		quads[0].Flags = QUAD_EDGED | QUAD_TIGHT_EDGE;
		drawing.Frame++;
		const auto tight = cache.Get(drawing, quads);
		CHECK(tight.Left == -31 && tight.Right == 41 && tight.Top == -1 && tight.Bottom == 13);
		quads[0].Flags |= QUAD_EDGE_RADIUS | QUAD_EDGE_OPACITY;
		quads[0].Reserved = (768 << 8) | 255;
		drawing.Edge = 0;
		drawing.Frame++;
		const auto independent = cache.Get(drawing, quads);
		CHECK(independent.Left == -33 && independent.Right == 43 && independent.Top == -3 && independent.Bottom == 15);
		quads[0].Flags &= ~QUAD_TIGHT_EDGE;
		drawing.Frame++;
		CHECK(cache.Get(drawing, quads).Bottom == 15 + NameGeometry::ShadowDrop);
		quads[0].Reserved &= ~255;
		drawing.Frame++;
		CHECK(cache.Get(drawing, quads).Bottom == 12);
		static HookDraw aspectDraw{};
		CHECK(aspectDraw.HorizontalFit() == 1.0f);
		aspectDraw.Reserved = 2 * 65536;
		CHECK(aspectDraw.HorizontalFit() == 2.0f);
		aspectDraw.Reserved = 65536 / 2;
		CHECK(aspectDraw.HorizontalFit() == 0.5f);
	}

	TestPlugin plugin;
	wchar_t temp[MAX_PATH];
	GetTempPathW(MAX_PATH, temp);
	StringCchPrintfW(plugin.configPath, MAX_PATH, L"%snamehook-test-%lu", temp, GetCurrentProcessId());
	CreateDirectoryW(plugin.configPath, NULL);

	// wine gives one run the process number of another: what an earlier run left in the folder is taken away
	for (const wchar_t* file : { L"defaults.ini", L"whitelist.txt" }) {
		wchar_t left[MAX_PATH];
		StringCchPrintfW(left, MAX_PATH, L"%s\\namehook\\%s", plugin.configPath, file);
		DeleteFileW(left);
	}

	static bool namesOff = false;
	static uint16_t selfIndex = 0x400;
	static uint32_t windowWidth = 800;
	static uint32_t windowHeight = 600;
	Globals.pNamesOff = &namesOff;
	Globals.pPlayerEntityIndex = &selfIndex;
	Globals.pWindowWidth = &windowWidth;
	Globals.pWindowHeight = &windowHeight;
	Globals.DrawNameLineOrig = &FakeLine;
	Globals.DrawNameLine2Orig = &FakeLine2;
	Instance = &plugin;

	const XiModel* self = Make(0, 0x400, 0x1000, "Me");
	const XiModel* buddy = Make(1, 0x401, 0x2000, "Buddy");
	const XiModel* ally = Make(2, 0x402, 0x3000, "Ally");
	const XiModel* stranger = Make(3, 0x403, 0x4000, "Stranger");
	const XiModel* friendly = Make(4, 0x404, 0x5000, "Friend");
	const XiModel* mob = Make(5, 300, 0x01001234, "Goblin");
	const XiModel* charmed = Make(6, 0x405, 0x6000, "Charmed", true);
	const XiModel* npc = Make(7, 50, 0x01000050, "Moogle");
	const XiModel* myPet = Make(8, 0x701, 0x01000701, "Carbuncle");
	const XiModel* pet = Make(9, 0x702, 0x01000702, "Ifrit");
	const XiModel* trust = Make(10, 0x703, 0x01009999, "Kupipi");

	plugin.Settings.Init();

	// the party, the target and the pets are asked for as a frame ends
	plugin.Publish(nullptr, nullptr, true);
	CHECK(Shared.Frame == 1 && Shared.Count == 0);

	// every name has its one category
	CHECK(CategoryOf(self) == CATEGORY_SELF && CategoryOf(buddy) == CATEGORY_PARTY && CategoryOf(ally) == CATEGORY_ALLIANCE);
	CHECK(CategoryOf(stranger) == CATEGORY_PLAYER && CategoryOf(mob) == CATEGORY_MONSTER && CategoryOf(npc) == CATEGORY_NPC);
	CHECK(CategoryOf(myPet) == CATEGORY_MY_PET && CategoryOf(pet) == CATEGORY_PET && CategoryOf(trust) == CATEGORY_PARTY);
	CHECK(CategoryOf(charmed) == CATEGORY_MONSTER);

	const XiModel* everyone[] = { self, buddy, ally, stranger, mob, npc, myPet, pet };

	// with nothing hidden, every name is drawn; each category is hidden by its own word, and no other is
	CHECK(Shared.Hidden == 0);
	for (const XiModel* model : everyone) {
		CHECK(Drawn(model) && ShouldDrawNameplate(model));
	}
	for (size_t i = 0; i < CATEGORY_COUNT; i++) {
		char command[64];
		StringCbPrintfA(command, sizeof(command), "/namehook hide %s", CategoryWords[i].Word);
		CHECK(plugin.ParseCommand(command, true));
		CHECK(Shared.Hidden == CategoryWords[i].Category);
		for (const XiModel* model : everyone) {
			CHECK(Drawn(model) == (CategoryOf(model) != CategoryWords[i].Category));
		}
		StringCbPrintfA(command, sizeof(command), "/nh show %s", CategoryWords[i].Word);
		plugin.ParseCommand(command, true);
		CHECK(Shared.Hidden == 0);
	}

	// several at once, toggled, and all
	plugin.ParseCommand("/namehook hide players alliance  mobs", true);
	CHECK(Shared.Hidden == (CATEGORY_PLAYER | CATEGORY_ALLIANCE | CATEGORY_MONSTER));
	CHECK(!Drawn(stranger) && !Drawn(ally) && !Drawn(mob) && !Drawn(charmed) && Drawn(buddy) && Drawn(trust) && Drawn(self));
	plugin.ParseCommand("/namehook toggle players party", true);
	CHECK(Shared.Hidden == (CATEGORY_PARTY | CATEGORY_ALLIANCE | CATEGORY_MONSTER));
	plugin.ParseCommand("/namehook hide all", true);
	CHECK(Shared.Hidden == CATEGORY_ALL && !Drawn(self) && !Drawn(npc));
	plugin.ParseCommand("/namehook show all", true);
	CHECK(Shared.Hidden == 0);

	// a command that is wrong says so and changes nothing
	plugin.ParseCommand("/namehook hide", true);
	plugin.ParseCommand("/namehook hide party goblins", true);
	plugin.ParseCommand("/namehook target maybe", true);
	CHECK(Shared.Hidden == 0 && Shared.Options == 0 && plugin.errors.size() == 3);
	CHECK(plugin.errors[0] == "hide" && plugin.errors[2] == "target");
	plugin.errors.clear();

	// where the client's calls were not taken, the name is decided on before it is drawn; where they
	// were, it is let through to be listed
	plugin.ParseCommand("/namehook hide players", true);
	CHECK(!ShouldDrawNameplate(stranger) && ShouldDrawNameplate(buddy));
	Shared.Hooked = 1;
	CHECK(ShouldDrawNameplate(stranger) && !Drawn(stranger));
	Shared.Hooked = 0;

	// the whitelist, typed in any case, shows a player whose category is hidden
	plugin.ParseCommand("/namehook whitelist add fRIEND someoneelse", true);
	CHECK(Whitelist.Count == 2 && strcmp(Whitelist.Names[0], "Friend") == 0 && strcmp(Whitelist.Names[1], "Someoneelse") == 0);
	CHECK(Drawn(friendly) && !Drawn(stranger));

	// a name that only begins like a listed one is not that name
	const XiModel* friendlier = Make(11, 0x406, 0x7000, "Friendlier");
	CHECK(!Drawn(friendlier));
	Make(11, 0x406, 0x7000, "Frien");
	CHECK(!Drawn(friendlier));

	// the whitelist is of players: it does not show the player's own name, or a monster of that name
	plugin.ParseCommand("/namehook wl add me goblin", true);
	plugin.ParseCommand("/namehook hide self monsters", true);
	CHECK(!Drawn(self) && !Drawn(mob));
	plugin.ParseCommand("/namehook wl remove me goblin", true);
	plugin.ParseCommand("/namehook show self monsters", true);

	// a second add changes nothing; the list is said back
	plugin.said.clear();
	plugin.ParseCommand("/namehook whitelist add Friend", true);
	CHECK(Whitelist.Count == 2 && plugin.said.size() == 1 && plugin.said[0] == "Friend is already on the whitelist.");
	plugin.said.clear();
	plugin.ParseCommand("/namehook whitelist list", true);
	CHECK(plugin.said.size() == 2 && plugin.said[0] == "Whitelist (2):" && plugin.said[1] == "Friend, Someoneelse");

	// a name is found among many, and one that is not there is not
	for (int i = 0; i < 300; i++) {
		char command[64];
		StringCbPrintfA(command, sizeof(command), "/nh wl add Filler%c%c%c", 'a' + i % 26, 'a' + (i / 26) % 26, 'a' + i % 7);
		plugin.ParseCommand(command, true);
	}
	plugin.ParseCommand("/nh wl add lastone", true);
	CHECK(Whitelist.Count > 200 && FindWhitelisted("LASTONE") == static_cast<int>(Whitelist.Count) - 1 && FindWhitelisted("Lastonee") < 0 && FindWhitelisted("Friend") == 0);
	plugin.ParseCommand("/nh wl remove Fillerbab", true);
	CHECK(FindWhitelisted("lastone") == static_cast<int>(Whitelist.Count) - 1 && FindWhitelisted("Someoneelse") == 1 && FindWhitelisted("Fillerbab") < 0 && FindWhitelisted("Fillercac") > 1);
	plugin.ParseCommand("/nh wl clear", true);
	plugin.ParseCommand("/namehook whitelist add fRIEND someoneelse", true);
	plugin.said.clear();

	// it is saved as it changes, and read back by a load
	Whitelist.Count = 0;
	CHECK(plugin.LoadWhitelist() == 0);
	CHECK(Whitelist.Count == 2 && strcmp(Whitelist.Names[1], "Someoneelse") == 0);
	plugin.ParseCommand("/namehook whitelist remove friend nobody", true);
	CHECK(Whitelist.Count == 1 && !Drawn(friendly));
	plugin.ParseCommand("/namehook whitelist frobnicate", true);
	plugin.ParseCommand("/namehook whitelist add Anamethatisfartoolongtobeaname", true);
	CHECK(plugin.errors.size() == 2 && plugin.errors[0] == "whitelist" && Whitelist.Count == 1);
	plugin.errors.clear();
	plugin.ParseCommand("/namehook whitelist clear", true);
	CHECK(Whitelist.Count == 0);

	// Indexed lookup preserves original ordering at maximum capacity, including
	// colliding buckets, case-insensitive matches and removal compaction.
	{
		const auto saved = Whitelist;
		Whitelist.Count = 0;
		Whitelist.IndexDirty = true;
		AddWhitelisted("Bucketfirst");
		const uint32_t bucket = HashName("Bucketfirst") & (WHITELIST_SLOTS - 1);
		char collision[WHITELIST_NAME_SIZE] = {};
		for (int i = 0; i < 100000; i++) {
			StringCbPrintfA(collision, sizeof(collision), "Collision%d", i);
			if ((HashName(collision) & (WHITELIST_SLOTS - 1)) == bucket) { break; }
		}
		CHECK((HashName(collision) & (WHITELIST_SLOTS - 1)) == bucket);
		AddWhitelisted(collision);
		CHECK(FindWhitelisted("BUCKETFIRST") == 0 && FindWhitelisted(collision) == 1);
		for (int i = 0; Whitelist.Count < WHITELIST_MAX; i++) {
			char name[WHITELIST_NAME_SIZE];
			StringCbPrintfA(name, sizeof(name), "Probe%d", i);
			AddWhitelisted(name);
		}
		CHECK(Whitelist.Count == WHITELIST_MAX && Whitelist.IndexedCount == WHITELIST_MAX);
		AddWhitelisted("Overflow");
		CHECK(Whitelist.Count == WHITELIST_MAX && FindWhitelisted("Overflow") < 0);
		for (size_t i = 0; i < Whitelist.Count; i++) {
			CHECK(FindWhitelisted(Whitelist.Names[i]) == static_cast<int>(i));
		}
		CHECK(FindWhitelisted("Absent") < 0);
		plugin.ParseCommand("/nh wl remove Probe100", true);
		CHECK(FindWhitelisted("Probe100") < 0);
		for (size_t i = 0; i < Whitelist.Count; i++) {
			CHECK(FindWhitelisted(Whitelist.Names[i]) == static_cast<int>(i));
		}
		Whitelist = saved;
		CHECK(plugin.SaveWhitelist() == 0);
	}

	// the target's name is shown whatever its category, when that is asked for
	plugin.target = 0x403;
	plugin.Publish(nullptr, nullptr, true);
	CHECK(!Drawn(stranger));
	plugin.ParseCommand("/namehook target on", true);
	CHECK(Shared.Options == OPTION_ALWAYS_TARGET && Drawn(stranger) && !Drawn(friendly));
	// but not the player's own name, hidden: with themselves targeted it stays hidden
	plugin.target = 0x400;
	plugin.Publish(nullptr, nullptr, true);
	CHECK(Drawn(self));
	plugin.ParseCommand("/namehook hide self", true);
	CHECK(!Drawn(self));
	plugin.ParseCommand("/namehook show self", true);
	plugin.target = 0x403;
	plugin.Publish(nullptr, nullptr, true);
	plugin.Publish(nullptr, nullptr, true);
	plugin.ParseCommand("/namehook target off", true);
	CHECK(Shared.Options == 0 && !Drawn(stranger));

	// an addon's word on one entity comes before its category, the whitelist and the target
	Shared.Override[0x403] = OVERRIDE_SHOW;
	Shared.Override[0x401] = OVERRIDE_HIDE;
	CHECK(Drawn(stranger) && !Drawn(buddy) && ShouldDrawNameplate(stranger) && !ShouldDrawNameplate(buddy));
	Shared.Override[0x403] = OVERRIDE_NONE;
	Shared.Override[0x401] = OVERRIDE_NONE;
	CHECK(!Drawn(stranger) && Drawn(buddy));

	// what was drawn so far is not listed until it is published; then it is, hidden names with the rest
	plugin.Publish(nullptr, nullptr, true);
	plugin.Publish(nullptr, nullptr, true);
	CHECK(Shared.Count == 0);
	plugin.ParseCommand("/namehook whitelist add friend", true);
	Drawn(buddy, "\x92\xAB Buddy", "\xD2");
	Drawn(stranger, "Stranger");
	Drawn(friendly, "Friend");
	Drawn(mob, "Goblin");
	CHECK(Shared.Count == 0);

	// a camera at the middle of the world looking along z, and a projection that leaves x and y as they are
	const float view[16] = { 1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1 };
	const float projection[16] = { 1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 1,  0, 0, 0, 0 };
	plugin.Publish(view, projection, false);
	CHECK(Shared.Count == 4 && Shared.Width == 800.0f && Shared.Height == 600.0f);

	const HookName& first = Shared.Names[0];
	CHECK(first.EntityIndex == 0x401 && first.ServerId == 0x2000 && first.Category == CATEGORY_PARTY);
	CHECK(first.Flags == (NAME_WANTED | NAME_DRAWN | NAME_STARS | NAME_ON_SCREEN));
	CHECK(first.X == 1.5f && first.Y == -2.5f && first.Z == 3.5f && first.Scale == 1.0f);
	CHECK(first.NameColor == 0x80406080 && first.IconColor == 0x80102030);
	CHECK(strcmp(first.Name, "Buddy") == 0 && strcmp(first.Text, "\x92\xAB Buddy") == 0);
	// x 1.5 and y -2.5 at depth 3.5: three sevenths right of the middle, five sevenths below it
	CHECK(first.Depth == 3.5f && fabsf(first.ScreenX - 400.0f * (1.0f + 1.5f / 3.5f)) < 0.01f && fabsf(first.ScreenY - 300.0f * (1.0f + 2.5f / 3.5f)) < 0.01f);

	CHECK(Shared.Names[1].Category == CATEGORY_PLAYER && Shared.Names[1].Flags == (NAME_TARGET | NAME_ON_SCREEN));
	CHECK(Shared.Names[2].Flags == (NAME_WANTED | NAME_DRAWN | NAME_WHITELISTED | NAME_ON_SCREEN));
	CHECK(Shared.Names[3].Category == CATEGORY_MONSTER && Shared.Names[3].ServerId == 0x01001234);

	// The client ends a scene many times a frame: the names are made ready once, in the one they were
	// drawn in, and again only if more are drawn. They stay as the frame ends, and go with the next.
	const uint32_t frame = Shared.Frame;
	const uint32_t sequence = Shared.Sequence;
	CHECK(!plugin.WantsPublish(false) && !plugin.WantsPublish(true));
	plugin.Publish(view, projection, false);
	plugin.Publish(nullptr, nullptr, false);
	CHECK(Shared.Count == 4 && Shared.Frame == frame && Shared.Sequence == sequence && (Shared.Names[0].Flags & NAME_ON_SCREEN) != 0);
	Fresh();
	Drawn(mob, "Goblin");
	CHECK(plugin.WantsPublish(false));
	plugin.Publish(view, projection, false);
	CHECK(Shared.Count == 5 && Shared.Sequence == sequence + 1);
	plugin.Publish(view, projection, true);
	CHECK(Shared.Count == 5 && Shared.Frame == frame + 1 && Shared.Sequence == sequence + 1);
	CHECK(!plugin.WantsPublish(false) && plugin.WantsPublish(true));
	plugin.Publish(view, projection, true);
	CHECK(Shared.Count == 0 && Shared.Frame == frame + 2 && Shared.Sequence == sequence + 2);

	// everybody's pets are looked for once in so many frames, and what was found is kept in between
	const int petLooks = plugin.petLooks;
	for (int i = 0; i < FACTS_PETS_EVERY * 3; i++) {
		plugin.Publish(nullptr, nullptr, true);
		CHECK(CategoryOf(pet) == CATEGORY_PET && CategoryOf(myPet) == CATEGORY_MY_PET && CategoryOf(buddy) == CATEGORY_PARTY);
	}
	CHECK(plugin.petLooks == petLooks + 3);
	plugin.ParseCommand("/namehook whitelist clear", true);

	// what is behind the camera has no place on screen
	const float behind[3] = { 0.0f, 0.0f, -4.0f };
	DrawNameLine(mob, nullptr, behind, "Goblin", one, 0, 0);
	plugin.Publish(view, projection, true);
	CHECK(Shared.Count == 1 && (Shared.Names[0].Flags & NAME_ON_SCREEN) == 0);

	// with the stars hidden, none are noted
	plugin.ParseCommand("/namehook hidestars", true);
	Drawn(buddy, "Buddy", "\xD2");
	plugin.ParseCommand("/namehook showstars", true);
	plugin.Publish(nullptr, nullptr, true);
	CHECK(Shared.Count == 1 && Shared.Names[0].Flags == (NAME_WANTED | NAME_DRAWN));

	// an addon that claims a category draws its names itself: they are wanted, listed, and not drawn.
	// A hidden name stays hidden, and a claim not made again lapses.
	Shared.Claimed = CATEGORY_PARTY | CATEGORY_PLAYER;
	Shared.ClaimFrame = Shared.Frame;
	CHECK(!Drawn(buddy) && !Drawn(stranger) && Drawn(mob));
	plugin.Publish(nullptr, nullptr, true);
	CHECK(Shared.Count == 3 && Shared.Names[0].Flags == NAME_WANTED && Shared.Names[1].Flags == NAME_TARGET && Shared.Names[2].Flags == (NAME_WANTED | NAME_DRAWN));
	for (int i = 0; i < FRAMES_IN(HOOK_CLAIM_TIME) - 1; i++) {
		plugin.Publish(nullptr, nullptr, true);
	}
	CHECK(!Drawn(buddy));
	plugin.Publish(nullptr, nullptr, true);
	CHECK(Drawn(buddy));
	// at 144 frames a second the claim still lasts half a second: 72 frames, not 30
	fakeStep = 6944;
	Shared.ClaimFrame = Shared.Frame;
	CHECK(!Drawn(buddy));
	for (int i = 0; i < FRAMES_IN(HOOK_CLAIM_TIME); i++) {
		plugin.Publish(nullptr, nullptr, true);
	}
	CHECK(FRAMES_IN(HOOK_CLAIM_TIME) == 72 && !Drawn(buddy));
	plugin.Publish(nullptr, nullptr, true);
	CHECK(Drawn(buddy));
	fakeStep = 16666;
	Shared.Claimed = 0;
	plugin.Publish(nullptr, nullptr, true);

	// an addon that has drawn a claimed name has the plugin put it in the picture, in place of the
	// client's: only a name that is wanted, only while what was drawn is of this frame or the last two
	Draw.Frame = 0 - 10;
	Shared.Claimed = CATEGORY_PARTY | CATEGORY_PLAYER;
	Shared.ClaimFrame = Shared.Frame;
	CHECK(!Drawn(buddy) && plugin.custom == 0 && plugin.begun > 0 && Shared.TargetWidth == 1200.0f && Shared.TargetHeight == 900.0f);
	Draw.Frame = Shared.Frame;
	Draw.QuadCount = 12;
	Draw.Entities[0x401] = { Draw.Frame, 3, 5, 1.0f, 1.0f, 0xE6000000 };
	Draw.Entities[0x403] = { Draw.Frame, 8, 4, 1.0f, 1.0f, 0xE6000000 }; // the stranger, who is hidden
	Draw.Entities[300] = { Draw.Frame, 0, 3, 1.0f, 0.0f, 0 };           // the monster, which is not claimed
	Fresh();
	CHECK(!Drawn(buddy) && plugin.custom == 1 && plugin.lastQuads == &Draw.Quads[3] && plugin.lastCount == 5);
	CHECK(!Drawn(stranger) && Drawn(mob) && plugin.custom == 1);
	plugin.Publish(nullptr, nullptr, true);
	// the first of these was the name before anything had been drawn for it
	CHECK(Shared.Count == 4 && Shared.Names[0].Flags == NAME_WANTED && Shared.Names[1].Flags == (NAME_WANTED | NAME_CUSTOM) && Shared.Names[2].Flags == NAME_TARGET && Shared.Names[3].Flags == (NAME_WANTED | NAME_DRAWN));
	// what does not hold together is not drawn
	Draw.Entities[0x401].First = 10;
	Fresh();
	CHECK(!Drawn(buddy) && plugin.custom == 1);
	Draw.Entities[0x401] = { Draw.Frame, 0, HOOK_QUADS_PER_NAME + 1, 1.0f, 0.0f, 0 };
	Draw.QuadCount = HOOK_QUADS_MAX;
	Fresh();
	CHECK(!Drawn(buddy) && plugin.custom == 1);
	Draw.Entities[0x401] = { Draw.Frame - 1, 0, 4, 1.0f, 0.0f, 0 };
	Fresh();
	CHECK(!Drawn(buddy) && plugin.custom == 1);
	Draw.Entities[0x401] = { Draw.Frame, 0, 4, 1.0f, 0.0f, 0 };
	Fresh();
	CHECK(!Drawn(buddy) && plugin.custom == 2);
	// what was drawn is drawn again while the addon misses a few frames, as under TrueFPS
	for (int frame = 1; frame < HOOK_DRAW_FRAMES; frame++) {
		plugin.Publish(nullptr, nullptr, true);
		Shared.ClaimFrame = Shared.Frame;
		CHECK(!Drawn(buddy) && plugin.custom == 2 + frame);
	}
	// nor what was drawn too long ago: the addon has stopped
	plugin.Publish(nullptr, nullptr, true);
	Shared.ClaimFrame = Shared.Frame;
	CHECK(!Drawn(buddy) && plugin.custom == 1 + HOOK_DRAW_FRAMES);
	// the first name of each frame, and no other, begins the frame's names
	int begun = plugin.begun;
	Drawn(buddy);
	Drawn(mob);
	CHECK(plugin.begun == begun);
	plugin.Publish(nullptr, nullptr, true);
	Drawn(mob);
	CHECK(plugin.begun == begun + 1);
	Shared.Claimed = 0;
	plugin.Publish(nullptr, nullptr, true);
	plugin.Publish(nullptr, nullptr, true);

	// World-space speech bubbles: their own block and their own drawing, beside the names and
	// independent of whether a name is shown or claimed
	{
		CHECK(strcmp(Bubbles.Magic, "NAMEBUBBLES") == 0 && Bubbles.Version == 2);
		CHECK(Bubbles.Size == sizeof(HookBubbles) && Bubbles.DrawSize == sizeof(HookDraw));
		const uint32_t hidden = Shared.Hidden;
		const uint32_t index = buddy->pEntity->EntityIndex;
		Bubbles.Draw.Frame = Shared.Frame;
		Bubbles.Draw.QuadCount = 1;
		Bubbles.Draw.Entities[index] = { Shared.Frame, 0, 1, 1.0f, 0, 0 };
		Bubbles.ServerIds[index] = buddy->pEntity->EntityId;
		Shared.Hidden |= CATEGORY_PARTY;
		Fresh();
		CHECK(!Drawn(buddy) && plugin.bubbles == 1); // hidden name, visible speech
		Drawn(buddy);
		CHECK(plugin.bubbles == 1); // no repeat
		Shared.Hidden = hidden;
		Fresh();
		CHECK(Drawn(buddy) && plugin.bubbles == 2); // stock name and speech coexist
		Bubbles.ServerIds[index]++;
		Fresh(); Drawn(buddy);
		CHECK(plugin.bubbles == 2); // index reused by another server ID
		Bubbles.ServerIds[index] = buddy->pEntity->EntityId;
		Bubbles.Draw.Entities[index].First = 1;
		Fresh(); Drawn(buddy);
		CHECK(plugin.bubbles == 2); // out of bounds
		Bubbles.Draw.Entities[index].First = 0;
		Bubbles.Draw.Frame = Shared.Frame - HOOK_DRAW_FRAMES - 1;
		Bubbles.Draw.Entities[index].Frame = Bubbles.Draw.Frame;
		Fresh(); Drawn(buddy);
		CHECK(plugin.bubbles == 2); // expired drawing
		Bubbles.Draw.Frame = Shared.Frame;
		Bubbles.Draw.Entities[index].Frame = Shared.Frame;
		Shared.Claimed = CATEGORY_PARTY;
		Shared.ClaimFrame = Shared.Frame;
		Draw.Frame = Shared.Frame;
		Draw.QuadCount = 1;
		Draw.Entities[index] = { Shared.Frame, 0, 1, 1.0f, 0, 0 };
		const int custom = plugin.custom;
		Fresh();
		CHECK(!Drawn(buddy) && plugin.custom == custom + 1 && plugin.bubbles == 3);
		Bubbles.Draw.QuadCount = 0;
		Shared.Claimed = 0;
		plugin.Publish(nullptr, nullptr, true);
	}

	// A name the client draws more than once in a frame, as it does a player's who is fishing, is
	// listed and drawn for an addon once: the first time the call that draws all the names draws it,
	// and otherwise the first time at all
	{
		const uintptr_t mainSite = 0x1000, otherSite = 0x2000;
		const float there[3] = { 9.5f, 0.0f, 4.0f };
		const uintptr_t mainWas = Globals.DrawNameLineCalls[0];
		Globals.DrawNameLineCalls[0] = mainSite;
		Fresh();
		Shared.Claimed = CATEGORY_PARTY;
		auto setOut = [&]() {
			Shared.ClaimFrame = Shared.Frame;
			Draw.Frame = Shared.Frame;
			Draw.QuadCount = 12;
			Draw.Entities[0x401] = { Draw.Frame, 0, 4, 1.0f, 0.0f, 0 };
		};
		plugin.Publish(nullptr, nullptr, true);
		setOut();

		// twice by the call that draws all the names: the first stands
		int custom = plugin.custom;
		lines = 0;
		DrawNameLineFrom(mainSite, buddy, where, "Buddy", one, 0, 0);
		DrawNameLineFrom(mainSite, buddy, there, "Buddy", one, 0, 0);
		CHECK(plugin.custom == custom + 1 && plugin.lastX == where[0] && lines == 0);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Shared.Count == 1 && Shared.Names[0].X == where[0] && Shared.Names[0].Flags == (NAME_WANTED | NAME_CUSTOM));
		CHECK(Globals.RepeatsLast == 1 && Globals.RepeatsMainLast == 1);

		// twice by that call in the frames after, in either order: the higher stands, there being
		// above where with the view that has the world's second axis up
		Globals.WorldUp = 1.0f;
		for (int order = 0; order < 4; order++) {
			const float* firstAt = (order & 1) ? there : where;
			const float* secondAt = (order & 1) ? where : there;
			setOut();
			custom = plugin.custom;
			DrawNameLineFrom(mainSite, buddy, firstAt, "Buddy", one, 0, 0);
			DrawNameLineFrom(mainSite, buddy, secondAt, "Buddy", one, 0, 0);
			CHECK(plugin.custom == custom + 1 && plugin.lastX == there[0]);
			plugin.Publish(nullptr, nullptr, true);
			CHECK(Shared.Count == 1 && Shared.Names[0].X == there[0] && Globals.RepeatsMainLast == 1);
		}
		// with only the lower one in a frame, it is drawn at once, where the higher was: the name
		// neither vanishes waiting for the higher nor drops to the lower; and listed there, with the
		// higher's size and colours
		const uint32_t half = 0x3F000000;
		setOut();
		custom = plugin.custom;
		DrawNameLineFrom(mainSite, buddy, where, "Buddy", one, 0x80FFFFFF, 0x80000000);
		DrawNameLineFrom(mainSite, buddy, there, "Buddy", one, 0x80FFFFFF, 0x80000000);
		CHECK(plugin.custom == custom + 1 && plugin.lastX == there[0]);
		plugin.Publish(nullptr, nullptr, true);
		for (int frame = 0; frame < 3; frame++) {
			setOut();
			custom = plugin.custom;
			DrawNameLineFrom(mainSite, buddy, where, "Buddy", half, 0x40FFFFFF, 0x40000000);
			CHECK(plugin.custom == custom + 1 && plugin.lastX == there[0]);
			plugin.Publish(nullptr, nullptr, true);
			CHECK(Shared.Count == 1 && Shared.Names[0].X == there[0] && Shared.Names[0].Y == there[1] && Shared.Names[0].Z == there[2]);
			CHECK(Shared.Names[0].NameColor == 0x80FFFFFF && Shared.Names[0].IconColor == 0x80000000 && Shared.Names[0].Scale == 1.0f);
			CHECK(Globals.LiftedLast == 1);
		}

		// and in a frame with both again, the lower first, the same
		setOut();
		custom = plugin.custom;
		DrawNameLineFrom(mainSite, buddy, where, "Buddy", one, 0, 0);
		DrawNameLineFrom(mainSite, buddy, there, "Buddy", one, 0, 0);
		CHECK(plugin.custom == custom + 1 && plugin.lastX == there[0]);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Shared.Count == 1 && Shared.Names[0].X == there[0] && Globals.RepeatsMainLast == 1);

		// the lower alone for longer than LIFT_TIME is the name's own place: drawn where it is
		for (int frame = 0; frame <= FRAMES_IN(LIFT_TIME); frame++) {
			setOut();
			DrawNameLineFrom(mainSite, buddy, where, "Buddy", one, 0, 0);
			plugin.Publish(nullptr, nullptr, true);
		}
		setOut();
		custom = plugin.custom;
		DrawNameLineFrom(mainSite, buddy, where, "Buddy", one, 0, 0);
		CHECK(plugin.custom == custom + 1 && plugin.lastX == where[0]);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Shared.Count == 1 && Shared.Names[0].X == where[0] && Globals.LiftedLast == 0);

		// a single name the client draws once a frame is never lifted
		Fresh();
		for (int frame = 0; frame < 3; frame++) {
			setOut();
			DrawNameLineFrom(mainSite, buddy, frame == 1 ? where : there, "Buddy", one, 0, 0);
			plugin.Publish(nullptr, nullptr, true);
			CHECK(Shared.Names[0].X == (frame == 1 ? where[0] : there[0]) && Globals.LiftedLast == 0);
		}

		// by another call and then by that one: that one's takes the other's place on the list
		Fresh();
		setOut();
		custom = plugin.custom;
		DrawNameLineFrom(otherSite, buddy, there, "Buddy", one, 0, 0);
		DrawNameLineFrom(mainSite, buddy, where, "Buddy", one, 0, 0);
		CHECK(plugin.custom == custom + 2 && plugin.lastX == where[0]);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Shared.Count == 1 && Shared.Names[0].X == where[0] && Globals.RepeatsLast == 0);

		// and from the next frame on, the other is passed over whichever comes first
		setOut();
		custom = plugin.custom;
		DrawNameLineFrom(otherSite, buddy, there, "Buddy", one, 0, 0);
		DrawNameLineFrom(mainSite, buddy, where, "Buddy", one, 0, 0);
		CHECK(plugin.custom == custom + 1 && plugin.lastX == where[0]);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Shared.Count == 1 && Shared.Names[0].X == where[0] && Globals.RepeatsLast == 1 && Globals.RepeatsMainLast == 0);

		// a name by another call alone, that call's own, is listed and drawn as ever
		Fresh();
		setOut();
		custom = plugin.custom;
		DrawNameLineFrom(otherSite, buddy, there, "Buddy", one, 0, 0);
		CHECK(plugin.custom == custom + 1 && plugin.lastX == there[0]);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Shared.Count == 1 && Shared.Names[0].X == there[0]);

		// unclaimed, the client draws the name each time, as it would, and it is listed once
		Shared.Claimed = 0;
		Fresh();
		lines = 0;
		DrawNameLineFrom(mainSite, buddy, where, "Buddy", one, 0, 0);
		DrawNameLineFrom(mainSite, buddy, there, "Buddy", one, 0, 0);
		CHECK(lines == 2);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Shared.Count == 1 && Shared.Names[0].Flags == (NAME_WANTED | NAME_DRAWN));

		Globals.DrawNameLineCalls[0] = mainWas;
		Fresh();
		plugin.Publish(nullptr, nullptr, true);
	}

	// a second line that does not follow its first is the client's to draw
	lines2 = 0;
	DrawNameLine(stranger, nullptr, where, "Stranger", one, 0, 0);
	DrawNameLine2(buddy, nullptr, where, "", one);
	DrawNameLine2(stranger, nullptr, where, "", one);
	DrawNameLine2(stranger, nullptr, where, "", one);
	CHECK(lines2 == 2);

	// a name too long for its place is cut short, one that is missing is empty, and a list that is
	// full takes no more, though names are shown and hidden as before
	plugin.Publish(nullptr, nullptr, true);
	DrawNameLine(mob, nullptr, where, "0123456789012345678901234567890123456789012345678901234567890123456789", one, 0, 0);
	Fresh();
	DrawNameLine(mob, nullptr, where, nullptr, one, 0, 0);
	lines = 0;
	for (int i = 0; i < HOOK_NAMES_MAX + 5; i++) {
		Fresh();
		DrawNameLine(mob, nullptr, where, "Goblin", one, 0, 0);
		DrawNameLine(stranger, nullptr, where, "Stranger", one, 0, 0);
	}
	plugin.Publish(nullptr, nullptr, true);
	CHECK(Shared.Count == HOOK_NAMES_MAX && lines == HOOK_NAMES_MAX + 5);
	CHECK(strlen(Shared.Names[0].Text) == HOOK_TEXT_SIZE - 1 && Shared.Names[1].Text[0] == '\0');
	plugin.Publish(nullptr, nullptr, true);

	// what is hidden goes to the ini with the rest and comes back
	plugin.ParseCommand("/namehook hide players npcs", true);
	plugin.ParseCommand("/namehook target on", true);
	plugin.ParseCommand("/namehook fontsize 30", true);
	plugin.ParseCommand("/namehook save", true);
	plugin.ParseCommand("/namehook show all", true);
	plugin.ParseCommand("/namehook target off", true);
	plugin.ParseCommand("/namehook fontsize 12", true);
	plugin.ParseCommand("/namehook load", true);
	CHECK(Shared.Hidden == (CATEGORY_PLAYER | CATEGORY_NPC) && Shared.Options == OPTION_ALWAYS_TARGET && AsmSettings.FontSize == 30);

	// what is shown and hidden is said back
	plugin.said.clear();
	plugin.ParseCommand("/namehook status", true);
	CHECK(plugin.said.size() == 5 && plugin.said[0] == "Shown: self, party, alliance, mypet, pets, monsters" && plugin.said[1] == "Hidden: players, npcs");
	CHECK(plugin.said.size() == 5 && plugin.said[4].find("damage popups were not recognised") != std::string::npos);

	// before its own settings are first saved there is nothing to read: the defaults, and no whitelist
	wchar_t path[MAX_PATH];
	StringCchPrintfW(path, MAX_PATH, L"%s\\namehook\\defaults.ini", plugin.configPath);
	DeleteFileW(path);
	StringCchPrintfW(path, MAX_PATH, L"%s\\namehook\\whitelist.txt", plugin.configPath);
	DeleteFileW(path);
	plugin.ParseCommand("/namehook load", true);
	CHECK(Shared.Hidden == 0 && Shared.Options == 0 && AsmSettings.FontSize == 22 && AsmSettings.HideStars == 0 && OtherCalls == 1);
	CHECK(Whitelist.Count == 0);

	// that load saved them as its own, which are read from then on
	plugin.ParseCommand("/namehook hide self alliance players", true);
	plugin.ParseCommand("/namehook target on", true);
	plugin.ParseCommand("/namehook fontsize 19", true);
	plugin.ParseCommand("/namehook save", true);
	plugin.ParseCommand("/namehook show all", true);
	plugin.ParseCommand("/namehook load", true);
	CHECK(Shared.Hidden == (CATEGORY_SELF | CATEGORY_ALLIANCE | CATEGORY_PLAYER) && Shared.Options == OPTION_ALWAYS_TARGET && AsmSettings.FontSize == 19);
	plugin.ParseCommand("/namehook target off", true);
	plugin.ParseCommand("/namehook show all", true);

	// other plugins' commands are not this one's
	CHECK(plugin.messages.empty() && plugin.errors.empty());
	CHECK(!plugin.ParseCommand("/nameplatew hide all", true) && !plugin.ParseCommand("/nhx hide all", true) && !plugin.ParseCommand("/nameplatehook hide all", true) && Shared.Hidden == 0);
	plugin.ParseCommand("/namehook mode all", true);
	CHECK(plugin.messages.size() == 1 && plugin.messages[0] == MESSAGE::SHORT_HELP);

	// a call is read and pointed elsewhere; only a function shaped like the model's two is taken
	static uint8_t code[64];
	ZeroMemory(code, sizeof(code));
	code[0] = 0xE8;
	code[1] = 0x10;
	uintptr_t pCode = reinterpret_cast<uintptr_t> (&code[0]);
	CHECK(CallTarget(pCode) == pCode + 5 + 0x10);
	SetCallTarget(pCode, pCode + 5 - 0x20);
	CHECK(CallTarget(pCode) == pCode + 5 - 0x20);
	code[0] = 0xE9;
	CHECK(CallTarget(pCode) == 0);
	static const uint8_t line[] = { 0x66, 0x83, 0xB9, 0xB2, 0x00, 0x00, 0x00, 0x00, 0x75 };
	CopyMemory(code, line, sizeof(line));
	code[DRAWNAME_LINE_RET_OFFSET] = 0xC2;
	code[DRAWNAME_LINE_RET_OFFSET + 1] = 0x14;
	CHECK(IsDrawNameLine(pCode, DRAWNAME_LINE_RET_OFFSET, 0x14));
	CHECK(!IsDrawNameLine(pCode, DRAWNAME_LINE2_RET_OFFSET, 0x0C) && !IsDrawNameLine(0, DRAWNAME_LINE_RET_OFFSET, 0x14));

	// every call to a function is found in a stretch of code, and nothing that only looks like one
	static uint8_t stretch[64];
	ZeroMemory(stretch, sizeof(stretch));
	uintptr_t pStretch = reinterpret_cast<uintptr_t> (&stretch[0]);
	const uintptr_t callee = pStretch + 0x1000;
	stretch[3] = 0xE8;
	SetCallTarget(pStretch + 3, callee);
	stretch[20] = 0xE8;
	SetCallTarget(pStretch + 20, callee);
	stretch[40] = 0xE8;
	SetCallTarget(pStretch + 40, callee + 1);
	stretch[50] = 0xE9;
	SetCallTarget(pStretch + 50, callee);
	uintptr_t sites[4] = {};
	CHECK(FindCallsIn(stretch, sizeof(stretch), callee, sites, 4) == 2 && sites[0] == pStretch + 3 && sites[1] == pStretch + 20);
	CHECK(FindCallsIn(stretch, sizeof(stretch), callee, sites, 1) == 2 && FindCallsIn(stretch, 4, callee, sites, 4) == 0);

	// the other calls are pointed at the plugin and back by the command, and the setting is kept
	Globals.DrawNameLineCalls[0] = 0;
	Globals.DrawNameLineCalls[1] = pStretch + 3;
	{
		uint8_t call[5];
		CallBytes(call, pStretch + 3, reinterpret_cast<uintptr_t> (&DrawNameLine));
		Globals.DrawNameLineSites[1] = Patches.Add(pStretch + 3, call, sizeof(call), true);
		CHECK(Globals.DrawNameLineSites[1] == 0);
	}
	Globals.DrawNameLineCallCount = 2;
	Globals.DrawNameLine2CallCount = 0;
	Shared.Hooked = 1;
	plugin.ParseCommand("/namehook othercalls on", true);
	CHECK(CallTarget(pStretch + 3) == 0 && Globals.OtherCallsTaken && OtherCalls == 1);
	plugin.ParseCommand("/namehook othercalls off", true);
	CHECK(Globals.OtherCallsTaken == false && OtherCalls == 0);
	int32_t back;
	memcpy(&back, &stretch[4], sizeof(back));
	CHECK(pStretch + 3 + 5 + static_cast<uintptr_t>(back) == callee); // as it was found
	// a call something else has changed since is left as it is, and the change is said to be undone
	plugin.ParseCommand("/namehook othercalls on", true);
	stretch[5] ^= 0xFF;
	plugin.messages.clear();
	plugin.ParseCommand("/namehook othercalls off", true);
	CHECK(plugin.messages.size() == 1 && plugin.messages[0] == MESSAGE::PATCH_ERROR && Patches.Sites[0].Abandoned);
	plugin.messages.clear();
	Patches.Drop(0);
	plugin.ParseCommand("/namehook save", true);
	OtherCalls = 1;
	plugin.ParseCommand("/namehook load", true);
	CHECK(OtherCalls == 0);
	plugin.ParseCommand("/namehook othercalls sometimes", true);
	CHECK(plugin.errors.size() == 1 && plugin.errors[0] == "othercalls");
	plugin.errors.clear();

	// the device's state is captured once a run of names unless told otherwise, and the choice is kept
	CHECK(plugin.KeepsStates());
	plugin.ParseCommand("/namehook keepstates off", true);
	CHECK(!plugin.KeepsStates());
	plugin.ParseCommand("/namehook save", true);
	KeepStates = 1;
	plugin.ParseCommand("/namehook load", true);
	CHECK(!plugin.KeepsStates());
	plugin.ParseCommand("/namehook keepstates on", true);
	CHECK(plugin.KeepsStates());
	plugin.ParseCommand("/namehook keepstates later", true);
	CHECK(plugin.errors.size() == 1 && plugin.errors[0] == "keepstates");
	plugin.errors.clear();
	plugin.ParseCommand("/namehook save", true);
	Globals.DrawNameLineCallCount = 0;
	Shared.Hooked = 0;
	OtherCalls = 1;

	// a line that is nobody's is the client's to draw, and is counted; the host is told each time the
	// client draws a line itself, and not when it does not
	plugin.Publish(nullptr, nullptr, true);
	lines = 0;
	plugin.clientDrew = 0;
	DrawNameLine(nullptr, nullptr, where, "Nobody", one, 0, 0);
	plugin.Publish(nullptr, nullptr, true);
	CHECK(lines == 1 && Globals.UnownedLast == 1 && plugin.clientDrew == 1);
	plugin.ParseCommand("/namehook show all", true);
	Shared.Claimed = 0;
	Fresh();
	CHECK(Drawn(buddy) && plugin.clientDrew == 3);
	Shared.Claimed = CATEGORY_ALL;
	Shared.ClaimFrame = Shared.Frame;
	Fresh();
	CHECK(!Drawn(buddy) && plugin.clientDrew == 3);
	Shared.Claimed = 0;

	// the game's own "names off" still wins
	namesOff = true;
	CHECK(!ShouldDrawNameplate(mob) && !ShouldDrawNameplate(buddy));

	// Damage popups: the patch hands each to the plugin, which lists it and says whether the client
	// draws it
	{
		CHECK(strcmp(Popups.Magic, "NAMEHOOKPOPUPS") == 0 && Popups.Version == 1);
		CHECK(Popups.Size == sizeof(HookPopups) && Popups.PopupSize == sizeof(HookPopup));
		// as winxi.popups reads them (tests/damage_check.lua checks the same)
		CHECK(sizeof(HookPopup) == 84 && offsetof(HookPopups, Draw) == 52 && offsetof(HookPopups, Popups) == 56);
		CHECK(sizeof(HookPopupDrawing) == 32 && offsetof(HookPopupDraw, Drawings) == 56 && offsetof(HookPopupDraw, Quads) == 56 + 32 * 64);
		// the patch: the skip written where it is not hooked goes on to the client's code after the patch;
		// a claimed popup jumps to the function's end, 0xAE from the patch's start
		CHECK(DRAWDAMAGE_PATCH_POPUP_LOCATION + 2 + DrawDamage_PopupSkip[1] == DRAWDAMAGE_PATCH_SIZE);
		CHECK(DrawDamage_Patch[0x53] == 0x0F && DrawDamage_Patch[0x54] == 0x84);
		int32_t jump;
		memcpy(&jump, &DrawDamage_Patch[0x55], sizeof(jump));
		CHECK(0x59 + jump == DRAWDAMAGE_END_OFFSET);
		uint32_t address;
		memcpy(&address, &DrawDamage_Patch[DRAWDAMAGE_PATCH_POPUP_ADDRESS_LOCATION], sizeof(address));
		CHECK(address == 0x12345678 && DrawDamage_Patch[DRAWDAMAGE_PATCH_POPUP_ADDRESS_LOCATION - 1] == 0xB8);

		uint32_t width = 1000, height = 500;
		Globals.pWindowWidth = &width;
		Globals.pWindowHeight = &height;
		static const float identity[16] = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 };

		// the client's object: what +FC points to points to the effect's generator, which has the
		// actors of who hit and who was hit
		static uint8_t object[0x200] = {};
		static uint32_t inner[1] = {};
		static uint32_t generator[0x44 / 4] = {};
		const uint32_t innerAt = static_cast<uint32_t>(reinterpret_cast<uintptr_t> (inner));
		memcpy(object + POPUP_OBJECT_EFFECT, &innerAt, 4);
		inner[0] = static_cast<uint32_t>(reinterpret_cast<uintptr_t> (generator));
		generator[POPUP_GENERATOR_TARGET / 4] = 0x0BADF00D;
		generator[POPUP_GENERATOR_SOURCE / 4] = 0x0BADBEEF;
		plugin.actors[0] = 0x0BADF00D;
		plugin.actors[1] = 0x0BADBEEF;
		strcpy(reinterpret_cast<char*> (object + POPUP_OBJECT_TEXT), "1234567890ABCDEFGHIJ"); // drawn to 16
		const float at[3] = { 0.5f, -0.5f, 3.0f }, size[2] = { 2.0f, 3.0f }, scale = 0.75f;

		plugin.Publish(nullptr, nullptr, true);
		const uint32_t names = Shared.Sequence;
		CHECK(OnDamagePopup(object, 0x80FFFFFF, at, size, &scale));
		CHECK(OnDamagePopup(object, 0x80FFFFFF, at, size, &scale)); // twice in a frame, listed once
		CHECK(plugin.WantsPublish(false));
		plugin.Publish(identity, identity, false);
		CHECK(Shared.Sequence == names); // the names are not made ready again for popups alone
		CHECK(Popups.Count == 1 && Popups.Frame == Shared.Frame);
		const HookPopup first = Popups.Popups[0];
		CHECK(first.Id != 0 && strcmp(first.Text, "1234567890ABCDEF") == 0);
		CHECK(first.Flags == (POPUP_DRAWN | POPUP_ON_SCREEN | POPUP_TARGET | POPUP_SOURCE) && first.EntityIndex == 0x123 && first.SourceIndex == 0x456);
		CHECK(first.Color == 0x80FFFFFF && first.Scale == 0.75f && first.Width == 2.0f && first.Height == 3.0f && first.Z == 3.0f);
		CHECK(first.ScreenX == 750.0f && first.ScreenY == 375.0f && first.Depth == 1.0f);
		CHECK(first.Object == static_cast<uint32_t>(reinterpret_cast<uintptr_t> (object)));
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Popups.Count == 1); // made ready, and not taken away as the frame ended

		// drawn again: the same popup; a frame without any, none
		const float fading = 0.5f;
		CHECK(OnDamagePopup(object, 0x40FFFFFF, at, size, &fading));
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Popups.Count == 1 && Popups.Popups[0].Id == first.Id && Popups.Popups[0].FirstFrame == first.FirstFrame
			&& Popups.Popups[0].Color == 0x40FFFFFF && (Popups.Popups[0].Flags & POPUP_ON_SCREEN) == 0);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Popups.Count == 0);

		// new text in the same object is a new popup, and so is the same after it has been gone a while
		object[POPUP_OBJECT_TEXT] = '9';
		OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
		plugin.Publish(nullptr, nullptr, true);
		const uint32_t second = Popups.Popups[0].Id;
		CHECK(second != first.Id);
		for (int i = 0; i < HOOK_DRAW_FRAMES + 1; i++) {
			plugin.Publish(nullptr, nullptr, true);
		}
		OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Popups.Popups[0].Id != second);

		// who: looked for once, as it first appears; an actor nobody is, none at all, or no generator
		const int looks = plugin.actorLooks;
		OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(plugin.actorLooks == looks);
		generator[POPUP_GENERATOR_SOURCE / 4] = 0x0D15EA5E;
		object[POPUP_OBJECT_TEXT] = '8';
		OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Popups.Popups[0].Flags == (POPUP_DRAWN | POPUP_TARGET) && Popups.Popups[0].EntityIndex == 0x123 && Popups.Popups[0].SourceIndex == HOOK_ENTITIES);
		generator[POPUP_GENERATOR_SOURCE / 4] = 0;
		object[POPUP_OBJECT_TEXT] = '4';
		const int noSource = plugin.actorLooks;
		OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(plugin.actorLooks == noSource + 1 && (Popups.Popups[0].Flags & POPUP_SOURCE) == 0); // no actor is never asked after
		inner[0] = 0;
		object[POPUP_OBJECT_TEXT] = '7';
		OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Popups.Popups[0].Flags == POPUP_DRAWN && Popups.Popups[0].EntityIndex == HOOK_ENTITIES && Popups.Popups[0].SourceIndex == HOOK_ENTITIES);

		// claimed: listed, not drawn by the client; the claim lapses as a name claim does
		Popups.Claimed = 1;
		Popups.ClaimFrame = Shared.Frame;
		CHECK(!OnDamagePopup(object, 0x80FFFFFF, at, size, &scale));
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Popups.Count == 1 && (Popups.Popups[0].Flags & POPUP_DRAWN) == 0);
		for (int i = 0; i < FRAMES_IN(HOOK_CLAIM_TIME) + 2; i++) {
			plugin.Publish(nullptr, nullptr, true);
		}
		CHECK(OnDamagePopup(object, 0x80FFFFFF, at, size, &scale));
		plugin.Publish(nullptr, nullptr, true);
		Popups.Claimed = 0;

		// a claimed popup is drawn as an addon has drawn it, where the client would have drawn it
		{
			// as Init leaves it, which is not run here
			PopupDraw.QuadsMax = HOOK_POPUP_QUADS_MAX;
			PopupDraw.DrawingsMax = HOOK_POPUPS_MAX;
			object[POPUP_OBJECT_TEXT] = '3';
			OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
			plugin.Publish(nullptr, nullptr, true);
			const uint32_t id = Popups.Popups[0].Id;
			const int begun = plugin.popupsBegun, drawn = plugin.popupsDrawn;

			// drawn by the client, nothing of the addon's is
			PopupDraw.Frame = Shared.Frame;
			PopupDraw.QuadCount = 3;
			PopupDraw.Count = 2;
			PopupDraw.Drawings[0] = { id + 1000, 0, { Shared.Frame, 0, 1, 1.0f, 0, 0 } };
			PopupDraw.Drawings[1] = { id, POPUP_DRAW_OVER, { Shared.Frame, 1, 2, 1.0f, 0, 0 } };
			CHECK(OnDamagePopup(object, 0x80FFFFFF, at, size, &scale));
			CHECK(plugin.popupsBegun == begun && plugin.popupsDrawn == drawn);
			plugin.Publish(nullptr, nullptr, true);

			// claimed: the host readied once a frame, the popup's own drawing at its point
			Popups.Claimed = 1;
			Popups.ClaimFrame = Shared.Frame;
			PopupDraw.Frame = Shared.Frame;
			PopupDraw.Drawings[0].Drawing.Frame = PopupDraw.Drawings[1].Drawing.Frame = Shared.Frame;
			CHECK(!OnDamagePopup(object, 0x80FFFFFF, at, size, &scale));
			CHECK(plugin.popupsBegun == begun + 1 && plugin.popupsFresh && plugin.popupsDrawn == drawn + 1);
			CHECK(plugin.popupSlot == 1 && plugin.popupQuads == &PopupDraw.Quads[1] && plugin.popupX == at[0]);
			static uint8_t other[0x200] = {};
			other[POPUP_OBJECT_TEXT] = '2';
			CHECK(!OnDamagePopup(other, 0x80FFFFFF, at, size, &scale));
			CHECK(plugin.popupsBegun == begun + 1 && plugin.popupsDrawn == drawn + 1); // no drawing of its own
			plugin.Publish(nullptr, nullptr, true);

			// a drawing past the quads, or one from before, is not drawn; a stale buffer, nothing is
			PopupDraw.Frame = Shared.Frame;
			PopupDraw.Drawings[1].Drawing.Frame = Shared.Frame;
			PopupDraw.Drawings[1].Drawing.First = 2;
			OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
			CHECK(plugin.popupsDrawn == drawn + 1);
			plugin.Publish(nullptr, nullptr, true);
			PopupDraw.Drawings[1].Drawing.First = 1;
			PopupDraw.Frame = Shared.Frame;
			OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
			CHECK(plugin.popupsDrawn == drawn + 1); // its own Frame is last frame's
			plugin.Publish(nullptr, nullptr, true);
			PopupDraw.Frame = Shared.Frame - HOOK_DRAW_FRAMES - 1;
			PopupDraw.Drawings[1].Drawing.Frame = PopupDraw.Frame;
			OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
			CHECK(!plugin.popupsFresh && plugin.popupsDrawn == drawn + 1);
			plugin.Publish(nullptr, nullptr, true);
			Popups.Claimed = 0;
			PopupDraw.Count = 0;
			PopupDraw.QuadCount = 0;
			object[POPUP_OBJECT_TEXT] = '7';
		}

		// more than the list holds: the rest drawn by the client, unlisted
		static uint8_t many[HOOK_POPUPS_MAX + 1][0x200] = {};
		for (auto& one : many) {
			one[POPUP_OBJECT_TEXT] = '5';
			CHECK(OnDamagePopup(one, 0x80FFFFFF, at, size, &scale));
		}
		plugin.Publish(nullptr, nullptr, true);
		CHECK(Popups.Count == HOOK_POPUPS_MAX);

		// the command, and its watch
		Popups.Hooked = 1;
		plugin.said.clear();
		OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
		plugin.Publish(nullptr, nullptr, true);
		plugin.ParseCommand("/namehook popups", true);
		CHECK(plugin.said.size() == 2 && plugin.said[0].find("1 damage popups last frame") == 0
			&& plugin.said[1].find("\"7234567890ABCDEF\" on nobody known from nobody known") != std::string::npos);
		plugin.said.clear();
		plugin.ParseCommand("/namehook popups watch on", true);
		CHECK(plugin.said.size() == 1 && PopupsWatched);
		object[POPUP_OBJECT_TEXT] = '6';
		inner[0] = static_cast<uint32_t>(reinterpret_cast<uintptr_t> (generator));
		generator[POPUP_GENERATOR_SOURCE / 4] = 0x0BADBEEF;
		OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
		OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(plugin.said.size() == 2 && plugin.said[1].find("\"6234567890ABCDEF\" on 0x123 from 0x456") != std::string::npos);
		OnDamagePopup(object, 0x80FFFFFF, at, size, &scale);
		plugin.Publish(nullptr, nullptr, true);
		CHECK(plugin.said.size() == 2); // said once
		plugin.ParseCommand("/nh popups watch off", true);
		CHECK(!PopupsWatched);
		plugin.ParseCommand("/nh popups watch maybe", true);
		CHECK(plugin.errors.size() == 1 && plugin.errors[0] == "popups");
		plugin.errors.clear();
		Popups.Hooked = 0;
		plugin.said.clear();
		plugin.ParseCommand("/namehook popups", true);
		CHECK(plugin.said.size() == 1 && plugin.said[0].find("not recognised") != std::string::npos);
		Globals.pWindowWidth = nullptr;
		Globals.pWindowHeight = nullptr;
	}

	{
		// unload gives every site back; the stars' jump is changed in place while it is as left
		static uint8_t client[64];
		memset(client, 0x75, sizeof(client));
		const uintptr_t pClient = reinterpret_cast<uintptr_t> (&client[0]);
		static const uint8_t patch[] = { 0x90, 0x90, 0x90 };
		const uint8_t jnz[1] = { 0x75 };
		CHECK(Patches.Add(pClient, patch, sizeof(patch)) == 0);
		Globals.StarsSite = Patches.Add(pClient + 8, jnz, sizeof(jnz));
		CHECK(Globals.StarsSite == 1 && Patches.Commit());
		Globals.Patched = true;
		plugin.messages.clear();
		plugin.ParseCommand("/namehook hidestars", true);
		CHECK(client[8] == 0xEB && client[0] == 0x90);
		plugin.ParseCommand("/namehook showstars", true);
		CHECK(client[8] == 0x75 && plugin.messages.empty());
		CHECK(plugin.Deinit() == 0 && client[0] == 0x75 && Patches.Count == 0 && !Globals.Patched && !Stranded);

		// the stars' jump written over by something else is left, and strands nothing
		CHECK(Patches.Add(pClient, patch, sizeof(patch)) == 0 && Patches.Add(pClient + 8, jnz, sizeof(jnz)) == 1 && Patches.Commit());
		Patches.Sites[1].Harmless = true;
		Globals.Patched = true;
		Globals.StarsSite = 1;
		client[8] = 0xCC;
		CHECK(plugin.Deinit() == 0 && !Stranded && client[0] == 0x75 && client[8] == 0xCC && Patches.Count == 0);
		client[8] = 0x75;

		// a site something else wrote over since: left, the plugin stranded, and never loaded again
		CHECK(Patches.Add(pClient, patch, sizeof(patch)) == 0 && Patches.Add(pClient + 8, jnz, sizeof(jnz)) == 1 && Patches.Commit());
		Globals.Patched = true;
		Globals.StarsSite = 1;
		client[1] = 0xE9;
		plugin.ParseCommand("/namehook hidestars", true);
		CHECK(client[8] == 0xEB);
		client[8] = 0xCC;
		plugin.ParseCommand("/namehook showstars", true);
		CHECK(client[8] == 0xCC && plugin.messages.size() == 1 && plugin.messages[0] == MESSAGE::PATCH_ERROR);
		CHECK(plugin.Deinit() == -26 && Stranded && Globals.Patched && client[1] == 0xE9 && client[8] == 0xCC);
		CHECK(plugin.Init() == -24 && Globals.Patched);
		CHECK(plugin.Deinit() == 0 && Stranded && Globals.Patched && client[1] == 0xE9); // a refused load's unload
		Stranded = false;
		Patches.Drop(0);
		ZeroMemory(&Globals, sizeof(Globals));
		AsmSettings.HideStars = 0;
	}

	printf(failures == 0 ? "all checks passed\n" : "%d checks FAILED\n", failures);
	return failures == 0 ? 0 : 1;
}
