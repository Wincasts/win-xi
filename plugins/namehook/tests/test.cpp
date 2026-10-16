// Checks which names are shown in each category, what is listed for addons, and the commands and
// files, without the game: the plugin's own source is compiled into this program, the client's patches
// are never applied, and the party is a made-up one. Built and run under wine by tests/run.sh.

// the whitelist's load and save are private; the header is read first, with them opened up
#define private public
#include "../src/Nameplate.h"
#undef private

#include "../src/Nameplate.cpp"
#include "../src/NameBounds.h"

#include <string>
#include <vector>

static int failures = 0;

#define CHECK(what) do { if (!(what)) { failures++; printf("FAILED line %d: %s\n", __LINE__, #what); } } while (0)

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

int main() {
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
		CHECK(first.Left == -52 && first.Right == 52 && first.Top == -20 && first.Bottom == 30);
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
	for (const wchar_t* folder : { L"namehook", L"nameplatehook", L"nameplatew" }) {
		for (const wchar_t* file : { L"defaults.ini", L"whitelist.txt" }) {
			wchar_t left[MAX_PATH];
			StringCchPrintfW(left, MAX_PATH, L"%s\\%s\\%s", plugin.configPath, folder, file);
			DeleteFileW(left);
		}
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
	plugin.Settings.Flush();

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
	for (int i = 0; i < HOOK_CLAIM_FRAMES - 1; i++) {
		plugin.Publish(nullptr, nullptr, true);
	}
	CHECK(!Drawn(buddy));
	plugin.Publish(nullptr, nullptr, true);
	CHECK(Drawn(buddy));
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
	// nor what was drawn too long ago: the addon has stopped
	plugin.Publish(nullptr, nullptr, true);
	Shared.ClaimFrame = Shared.Frame;
	CHECK(!Drawn(buddy) && plugin.custom == 3);
	plugin.Publish(nullptr, nullptr, true);
	Shared.ClaimFrame = Shared.Frame;
	CHECK(!Drawn(buddy) && plugin.custom == 3);
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

		// the lower alone for longer than LIFT_FRAMES is the name's own place: drawn where it is
		for (int frame = 0; frame <= LIFT_FRAMES; frame++) {
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
	CHECK(plugin.said.size() == 4 && plugin.said[0] == "Shown: self, party, alliance, mypet, pets, monsters" && plugin.said[1] == "Hidden: players, npcs");

	// before its own settings are first saved, it starts from nameplatew's: its mode, and its whitelist
	wchar_t path[MAX_PATH];
	StringCchPrintfW(path, MAX_PATH, L"%s\\namehook\\defaults.ini", plugin.configPath);
	DeleteFileW(path);
	StringCchPrintfW(path, MAX_PATH, L"%s\\namehook\\whitelist.txt", plugin.configPath);
	DeleteFileW(path);
	StringCchPrintfW(path, MAX_PATH, L"%s\\nameplatew", plugin.configPath);
	CreateDirectoryW(path, NULL);
	StringCchPrintfW(path, MAX_PATH, L"%s\\nameplatew\\defaults.ini", plugin.configPath);
	WritePrivateProfileStringW(L"Settings", L"NameMode", L"8", path);
	WritePrivateProfileStringW(L"Settings", L"FontSizeInPx", L"17", path);
	StringCchPrintfW(path, MAX_PATH, L"%s\\nameplatew\\whitelist.txt", plugin.configPath);
	FILE* file = _wfopen(path, L"w");
	fprintf(file, "Oldfriend\n");
	fclose(file);
	plugin.ParseCommand("/namehook load", true);
	CHECK(Shared.Hidden == (CATEGORY_SELF | CATEGORY_ALLIANCE | CATEGORY_PLAYER) && Shared.Options == 0 && AsmSettings.FontSize == 17);
	CHECK(Whitelist.Count == 1 && strcmp(Whitelist.Names[0], "Oldfriend") == 0);
	CHECK(HiddenFromNameMode(7, true) == CATEGORY_PLAYER && HiddenFromNameMode(1, false) == CATEGORY_ALL && HiddenFromNameMode(0, false) == 0);
	CHECK(HiddenFromNameMode(3, false) == (CATEGORY_SELF | CATEGORY_PARTY | CATEGORY_ALLIANCE | CATEGORY_PLAYER));
	CHECK(HiddenFromNameMode(5, false) == (CATEGORY_MY_PET | CATEGORY_PET | CATEGORY_NPC | CATEGORY_MONSTER));

	// under the name it had before, nameplatehook, its settings are found too, and come before nameplatew's
	plugin.ParseCommand("/namehook wl clear", true);
	StringCchPrintfW(path, MAX_PATH, L"%s\\namehook\\defaults.ini", plugin.configPath);
	DeleteFileW(path);
	StringCchPrintfW(path, MAX_PATH, L"%s\\namehook\\whitelist.txt", plugin.configPath);
	DeleteFileW(path);
	StringCchPrintfW(path, MAX_PATH, L"%s\\nameplatehook", plugin.configPath);
	CreateDirectoryW(path, NULL);
	StringCchPrintfW(path, MAX_PATH, L"%s\\nameplatehook\\defaults.ini", plugin.configPath);
	WritePrivateProfileStringW(L"Settings", L"Hidden", L"130", path);
	WritePrivateProfileStringW(L"Settings", L"AlwaysTarget", L"1", path);
	WritePrivateProfileStringW(L"Settings", L"FontSizeInPx", L"19", path);
	StringCchPrintfW(path, MAX_PATH, L"%s\\nameplatehook\\whitelist.txt", plugin.configPath);
	file = _wfopen(path, L"w");
	fprintf(file, "Newerfriend\n");
	fclose(file);
	plugin.ParseCommand("/namehook load", true);
	CHECK(Shared.Hidden == (CATEGORY_PARTY | CATEGORY_MONSTER) && Shared.Options == OPTION_ALWAYS_TARGET && AsmSettings.FontSize == 19);
	CHECK(Whitelist.Count == 1 && strcmp(Whitelist.Names[0], "Newerfriend") == 0);
	plugin.ParseCommand("/namehook target off", true);
	plugin.ParseCommand("/namehook hide self alliance players", true);
	plugin.ParseCommand("/namehook show party monsters", true);
	plugin.ParseCommand("/namehook save", true);
	StringCchPrintfW(path, MAX_PATH, L"%s\\nameplatew\\whitelist.txt", plugin.configPath);

	// that load saved them as its own, which are read from then on
	WritePrivateProfileStringW(L"Settings", L"NameMode", L"1", path);
	StringCchPrintfW(path, MAX_PATH, L"%s\\nameplatew\\defaults.ini", plugin.configPath);
	WritePrivateProfileStringW(L"Settings", L"NameMode", L"1", path);
	plugin.ParseCommand("/namehook load", true);
	CHECK(Shared.Hidden == (CATEGORY_SELF | CATEGORY_ALLIANCE | CATEGORY_PLAYER));
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
	Globals.DrawNameLineCallCount = 2;
	Globals.DrawNameLine2CallCount = 0;
	Shared.Hooked = 1;
	plugin.ParseCommand("/namehook othercalls on", true);
	CHECK(CallTarget(pStretch + 3) == 0 && Globals.OtherCallsTaken && OtherCalls == 1);
	plugin.ParseCommand("/namehook othercalls off", true);
	CHECK(Globals.OtherCallsTaken == false && OtherCalls == 0);
	int32_t back;
	memcpy(&back, &stretch[4], sizeof(back));
	CHECK(pStretch + 3 + 5 + static_cast<uintptr_t>(back) == reinterpret_cast<uintptr_t> (Globals.DrawNameLineOrig));
	plugin.ParseCommand("/namehook save", true);
	OtherCalls = 1;
	plugin.ParseCommand("/namehook load", true);
	CHECK(OtherCalls == 0);
	plugin.ParseCommand("/namehook othercalls sometimes", true);
	CHECK(plugin.errors.size() == 1 && plugin.errors[0] == "othercalls");
	plugin.errors.clear();
	Globals.DrawNameLineCallCount = 0;
	Shared.Hooked = 0;
	OtherCalls = 1;

	// a line that is nobody's is the client's to draw, and is counted
	plugin.Publish(nullptr, nullptr, true);
	lines = 0;
	DrawNameLine(nullptr, nullptr, where, "Nobody", one, 0, 0);
	plugin.Publish(nullptr, nullptr, true);
	CHECK(lines == 1 && Globals.UnownedLast == 1);

	// the game's own "names off" still wins
	namesOff = true;
	CHECK(!ShouldDrawNameplate(mob) && !ShouldDrawNameplate(buddy));

	printf(failures == 0 ? "all checks passed\n" : "%d checks FAILED\n", failures);
	return failures == 0 ? 0 : 1;
}
