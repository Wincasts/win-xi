// Checks which names are shown in each category, what is listed for addons, and the commands and
// files, without the game: the plugin's own source is compiled into this program, the client's patches
// are never applied, and the party is a made-up one. Built and run under wine by tests/run.sh.

// the whitelist's load and save are private; the header is read first, with them opened up
#define private public
#include "../src/Nameplate.h"
#undef private

#include "../src/Nameplate.cpp"

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
	void GetFrameFacts(FrameFacts& facts) override {
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
	static_assert(offsetof(HookShared, Override) == 80 && offsetof(HookShared, Names) == 80 + HOOK_ENTITIES);
	CHECK(memcmp(Shared.Magic, "NAMEPLATEHOOK\0\0\0", 16) == 0 && Shared.Version == 1);
	CHECK(Shared.Size == sizeof(HookShared) && Shared.NameSize == sizeof(HookName));

	TestPlugin plugin;
	wchar_t temp[MAX_PATH];
	GetTempPathW(MAX_PATH, temp);
	StringCchPrintfW(plugin.configPath, MAX_PATH, L"%snameplatehook-test-%lu", temp, GetCurrentProcessId());
	CreateDirectoryW(plugin.configPath, NULL);

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
		StringCbPrintfA(command, sizeof(command), "/nameplatehook hide %s", CategoryWords[i].Word);
		CHECK(plugin.ParseCommand(command, true));
		CHECK(Shared.Hidden == CategoryWords[i].Category);
		for (const XiModel* model : everyone) {
			CHECK(Drawn(model) == (CategoryOf(model) != CategoryWords[i].Category));
		}
		StringCbPrintfA(command, sizeof(command), "/nph show %s", CategoryWords[i].Word);
		plugin.ParseCommand(command, true);
		CHECK(Shared.Hidden == 0);
	}

	// several at once, toggled, and all
	plugin.ParseCommand("/nameplatehook hide players alliance  mobs", true);
	CHECK(Shared.Hidden == (CATEGORY_PLAYER | CATEGORY_ALLIANCE | CATEGORY_MONSTER));
	CHECK(!Drawn(stranger) && !Drawn(ally) && !Drawn(mob) && !Drawn(charmed) && Drawn(buddy) && Drawn(trust) && Drawn(self));
	plugin.ParseCommand("/nameplatehook toggle players party", true);
	CHECK(Shared.Hidden == (CATEGORY_PARTY | CATEGORY_ALLIANCE | CATEGORY_MONSTER));
	plugin.ParseCommand("/nameplatehook hide all", true);
	CHECK(Shared.Hidden == CATEGORY_ALL && !Drawn(self) && !Drawn(npc));
	plugin.ParseCommand("/nameplatehook show all", true);
	CHECK(Shared.Hidden == 0);

	// a command that is wrong says so and changes nothing
	plugin.ParseCommand("/nameplatehook hide", true);
	plugin.ParseCommand("/nameplatehook hide party goblins", true);
	plugin.ParseCommand("/nameplatehook target maybe", true);
	CHECK(Shared.Hidden == 0 && Shared.Options == 0 && plugin.errors.size() == 3);
	CHECK(plugin.errors[0] == "hide" && plugin.errors[2] == "target");
	plugin.errors.clear();

	// where the client's calls were not taken, the name is decided on before it is drawn; where they
	// were, it is let through to be listed
	plugin.ParseCommand("/nameplatehook hide players", true);
	CHECK(!ShouldDrawNameplate(stranger) && ShouldDrawNameplate(buddy));
	Shared.Hooked = 1;
	CHECK(ShouldDrawNameplate(stranger) && !Drawn(stranger));
	Shared.Hooked = 0;

	// the whitelist, typed in any case, shows a player whose category is hidden
	plugin.ParseCommand("/nameplatehook whitelist add fRIEND someoneelse", true);
	CHECK(Whitelist.Count == 2 && strcmp(Whitelist.Names[0], "Friend") == 0 && strcmp(Whitelist.Names[1], "Someoneelse") == 0);
	CHECK(Drawn(friendly) && !Drawn(stranger));

	// a name that only begins like a listed one is not that name
	const XiModel* friendlier = Make(11, 0x406, 0x7000, "Friendlier");
	CHECK(!Drawn(friendlier));
	Make(11, 0x406, 0x7000, "Frien");
	CHECK(!Drawn(friendlier));

	// the whitelist is of players: it does not show the player's own name, or a monster of that name
	plugin.ParseCommand("/nameplatehook wl add me goblin", true);
	plugin.ParseCommand("/nameplatehook hide self monsters", true);
	CHECK(!Drawn(self) && !Drawn(mob));
	plugin.ParseCommand("/nameplatehook wl remove me goblin", true);
	plugin.ParseCommand("/nameplatehook show self monsters", true);

	// a second add changes nothing; the list is said back
	plugin.said.clear();
	plugin.ParseCommand("/nameplatehook whitelist add Friend", true);
	CHECK(Whitelist.Count == 2 && plugin.said.size() == 1 && plugin.said[0] == "Friend is already on the whitelist.");
	plugin.said.clear();
	plugin.ParseCommand("/nameplatehook whitelist list", true);
	CHECK(plugin.said.size() == 2 && plugin.said[0] == "Whitelist (2):" && plugin.said[1] == "Friend, Someoneelse");

	// it is saved as it changes, and read back by a load
	Whitelist.Count = 0;
	CHECK(plugin.LoadWhitelist() == 0);
	CHECK(Whitelist.Count == 2 && strcmp(Whitelist.Names[1], "Someoneelse") == 0);
	plugin.ParseCommand("/nameplatehook whitelist remove friend nobody", true);
	CHECK(Whitelist.Count == 1 && !Drawn(friendly));
	plugin.ParseCommand("/nameplatehook whitelist frobnicate", true);
	plugin.ParseCommand("/nameplatehook whitelist add Anamethatisfartoolongtobeaname", true);
	CHECK(plugin.errors.size() == 2 && plugin.errors[0] == "whitelist" && Whitelist.Count == 1);
	plugin.errors.clear();
	plugin.ParseCommand("/nameplatehook whitelist clear", true);
	CHECK(Whitelist.Count == 0);

	// the target's name is shown whatever its category, when that is asked for
	plugin.target = 0x403;
	plugin.Publish(nullptr, nullptr, true);
	CHECK(!Drawn(stranger));
	plugin.ParseCommand("/nameplatehook target on", true);
	CHECK(Shared.Options == OPTION_ALWAYS_TARGET && Drawn(stranger) && !Drawn(friendly));
	plugin.ParseCommand("/nameplatehook target off", true);
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
	plugin.ParseCommand("/nameplatehook whitelist add friend", true);
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

	// the names stay as the scene ends a second time, and go with the frame
	const uint32_t frame = Shared.Frame;
	const uint32_t sequence = Shared.Sequence;
	plugin.Publish(view, projection, false);
	CHECK(Shared.Count == 4 && Shared.Frame == frame && Shared.Sequence == sequence + 1);
	plugin.Publish(view, projection, true);
	CHECK(Shared.Count == 4 && Shared.Frame == frame + 1);
	plugin.Publish(view, projection, true);
	CHECK(Shared.Count == 0 && Shared.Frame == frame + 2);
	plugin.ParseCommand("/nameplatehook whitelist clear", true);

	// what is behind the camera has no place on screen
	const float behind[3] = { 0.0f, 0.0f, -4.0f };
	DrawNameLine(mob, nullptr, behind, "Goblin", one, 0, 0);
	plugin.Publish(view, projection, true);
	CHECK(Shared.Count == 1 && (Shared.Names[0].Flags & NAME_ON_SCREEN) == 0);

	// with the stars hidden, none are noted
	plugin.ParseCommand("/nameplatehook hidestars", true);
	Drawn(buddy, "Buddy", "\xD2");
	plugin.ParseCommand("/nameplatehook showstars", true);
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
	DrawNameLine(mob, nullptr, where, nullptr, one, 0, 0);
	lines = 0;
	for (int i = 0; i < HOOK_NAMES_MAX + 5; i++) {
		DrawNameLine(mob, nullptr, where, "Goblin", one, 0, 0);
		DrawNameLine(stranger, nullptr, where, "Stranger", one, 0, 0);
	}
	plugin.Publish(nullptr, nullptr, true);
	CHECK(Shared.Count == HOOK_NAMES_MAX && lines == HOOK_NAMES_MAX + 5);
	CHECK(strlen(Shared.Names[0].Text) == HOOK_TEXT_SIZE - 1 && Shared.Names[1].Text[0] == '\0');
	plugin.Publish(nullptr, nullptr, true);

	// what is hidden goes to the ini with the rest and comes back
	plugin.ParseCommand("/nameplatehook hide players npcs", true);
	plugin.ParseCommand("/nameplatehook target on", true);
	plugin.ParseCommand("/nameplatehook fontsize 30", true);
	plugin.ParseCommand("/nameplatehook save", true);
	plugin.ParseCommand("/nameplatehook show all", true);
	plugin.ParseCommand("/nameplatehook target off", true);
	plugin.ParseCommand("/nameplatehook fontsize 12", true);
	plugin.ParseCommand("/nameplatehook load", true);
	CHECK(Shared.Hidden == (CATEGORY_PLAYER | CATEGORY_NPC) && Shared.Options == OPTION_ALWAYS_TARGET && AsmSettings.FontSize == 30);

	// what is shown and hidden is said back
	plugin.said.clear();
	plugin.ParseCommand("/nameplatehook status", true);
	CHECK(plugin.said.size() == 4 && plugin.said[0] == "Shown: self, party, alliance, mypet, pets, monsters" && plugin.said[1] == "Hidden: players, npcs");

	// before its own settings are first saved, it starts from nameplatew's: its mode, and its whitelist
	wchar_t path[MAX_PATH];
	StringCchPrintfW(path, MAX_PATH, L"%s\\nameplatehook\\defaults.ini", plugin.configPath);
	DeleteFileW(path);
	StringCchPrintfW(path, MAX_PATH, L"%s\\nameplatehook\\whitelist.txt", plugin.configPath);
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
	plugin.ParseCommand("/nameplatehook load", true);
	CHECK(Shared.Hidden == (CATEGORY_SELF | CATEGORY_ALLIANCE | CATEGORY_PLAYER) && Shared.Options == 0 && AsmSettings.FontSize == 17);
	CHECK(Whitelist.Count == 1 && strcmp(Whitelist.Names[0], "Oldfriend") == 0);
	CHECK(HiddenFromNameMode(7, true) == CATEGORY_PLAYER && HiddenFromNameMode(1, false) == CATEGORY_ALL && HiddenFromNameMode(0, false) == 0);
	CHECK(HiddenFromNameMode(3, false) == (CATEGORY_SELF | CATEGORY_PARTY | CATEGORY_ALLIANCE | CATEGORY_PLAYER));
	CHECK(HiddenFromNameMode(5, false) == (CATEGORY_MY_PET | CATEGORY_PET | CATEGORY_NPC | CATEGORY_MONSTER));

	// that load saved them as its own, which are read from then on
	WritePrivateProfileStringW(L"Settings", L"NameMode", L"1", path);
	StringCchPrintfW(path, MAX_PATH, L"%s\\nameplatew\\defaults.ini", plugin.configPath);
	WritePrivateProfileStringW(L"Settings", L"NameMode", L"1", path);
	plugin.ParseCommand("/nameplatehook load", true);
	CHECK(Shared.Hidden == (CATEGORY_SELF | CATEGORY_ALLIANCE | CATEGORY_PLAYER));
	plugin.ParseCommand("/nameplatehook show all", true);

	// other plugins' commands are not this one's
	CHECK(plugin.messages.empty() && plugin.errors.empty());
	CHECK(!plugin.ParseCommand("/nameplatew hide all", true) && !plugin.ParseCommand("/nphx hide all", true) && Shared.Hidden == 0);
	plugin.ParseCommand("/nameplatehook mode all", true);
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

	// the game's own "names off" still wins
	namesOff = true;
	CHECK(!ShouldDrawNameplate(mob) && !ShouldDrawNameplate(buddy));

	printf(failures == 0 ? "all checks passed\n" : "%d checks FAILED\n", failures);
	return failures == 0 ? 0 : 1;
}
