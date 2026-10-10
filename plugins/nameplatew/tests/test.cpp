// Checks which names are drawn in each mode, and the whitelist commands and file, without the game:
// the plugin's own source is compiled into this program, the client's patches are never applied, and
// the party is a made-up one. Built and run under wine by tests/run.sh.

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
	std::vector<MESSAGE> messages;
	wchar_t configPath[MAX_PATH];

	void Debug(const char* text) override {
		said.push_back(text);
	}
	void ShowMessage(MESSAGE message, int) override {
		messages.push_back(message);
	}
	bool GetConfigPath(wchar_t path[UNICODE_MAX_PATH]) override {
		StringCchCopyW(path, UNICODE_MAX_PATH, configPath);
		return true;
	}
	bool IsPartyMember(uint32_t serverId, bool alliance) override {
		return serverId == 0x1000 || serverId == 0x2000 || (alliance && serverId == 0x3000);
	}
};

static XiModel models[8];
static Entity entities[8];

static const XiModel* Make(int slot, uint32_t index, uint32_t id, const char* name, bool attackable = false) {
	ZeroMemory(&entities[slot], sizeof(Entity));
	entities[slot].EntityIndex = index;
	entities[slot].EntityId = id;
	StringCbCopyA(entities[slot].Name, sizeof(entities[slot].Name), name);
	entities[slot].Flags0 = attackable ? (1u << 13) : 0;
	models[slot].pEntity = &entities[slot];
	return &models[slot];
}

int main() {
	static_assert(offsetof(Entity, Name) == 0x7C);
	static_assert(offsetof(Entity, Flags0) == 0x120);

	TestPlugin plugin;
	wchar_t temp[MAX_PATH];
	GetTempPathW(MAX_PATH, temp);
	StringCchPrintfW(plugin.configPath, MAX_PATH, L"%snameplatew-test-%lu", temp, GetCurrentProcessId());
	CreateDirectoryW(plugin.configPath, NULL);

	static bool namesOff = false;
	static uint16_t selfIndex = 100;
	Globals.pNamesOff = &namesOff;
	Globals.pPlayerEntityIndex = &selfIndex;
	Instance = &plugin;

	const XiModel* self = Make(0, 100, 0x1000, "Me");
	const XiModel* buddy = Make(1, 101, 0x2000, "Buddy");
	const XiModel* ally = Make(2, 102, 0x3000, "Ally");
	const XiModel* stranger = Make(3, 103, 0x4000, "Stranger");
	const XiModel* friendly = Make(4, 104, 0x5000, "Friend");
	const XiModel* mob = Make(5, 300, 0x01001234, "Goblin");
	const XiModel* charmed = Make(6, 105, 0x6000, "Charmed", true);

	plugin.Settings.Init();
	plugin.Settings.Flush();

	// with nothing on the whitelist the old modes do what they did
	CHECK(plugin.ParseCommand("/nameplatew mode hidepc", true));
	CHECK(ShouldDrawNameplate(mob) && ShouldDrawNameplate(charmed));
	CHECK(!ShouldDrawNameplate(self) && !ShouldDrawNameplate(buddy) && !ShouldDrawNameplate(friendly));

	plugin.ParseCommand("/nameplatew mode all", true);
	CHECK(ShouldDrawNameplate(stranger) && ShouldDrawNameplate(mob) && ShouldDrawNameplate(self));

	// the party mode: party, self, NPCs and charmed players, and no one else
	plugin.ParseCommand("/nameplatew mode hidepcparty", true);
	CHECK(AsmSettings.NameMode == NAME_MODE::HIDE_PCPARTY);
	CHECK(ShouldDrawNameplate(self) && ShouldDrawNameplate(buddy) && ShouldDrawNameplate(mob) && ShouldDrawNameplate(charmed));
	CHECK(!ShouldDrawNameplate(ally) && !ShouldDrawNameplate(stranger) && !ShouldDrawNameplate(friendly));

	plugin.ParseCommand("/nameplatew alliance on", true);
	CHECK(ShouldDrawNameplate(ally) && !ShouldDrawNameplate(stranger));
	plugin.ParseCommand("/nameplatew alliance off", true);
	CHECK(!ShouldDrawNameplate(ally));

	plugin.ParseCommand("/nameplatew mode hidepcpartyself", true);
	CHECK(AsmSettings.NameMode == NAME_MODE::HIDE_PCPARTYSELF);
	CHECK(!ShouldDrawNameplate(self) && ShouldDrawNameplate(buddy) && ShouldDrawNameplate(mob) && !ShouldDrawNameplate(stranger));

	// the whitelist, typed in any case, shows a player in every mode that hides players
	CHECK(plugin.messages.empty());
	plugin.ParseCommand("/nameplatew whitelist add fRIEND someoneelse", true);
	CHECK(Whitelist.Count == 2 && strcmp(Whitelist.Names[0], "Friend") == 0 && strcmp(Whitelist.Names[1], "Someoneelse") == 0);
	CHECK(ShouldDrawNameplate(friendly) && !ShouldDrawNameplate(stranger));
	plugin.ParseCommand("/nameplatew mode hidepc", true);
	CHECK(ShouldDrawNameplate(friendly) && !ShouldDrawNameplate(stranger) && !ShouldDrawNameplate(buddy));
	plugin.ParseCommand("/nameplatew mode hidepcself", true);
	CHECK(ShouldDrawNameplate(friendly) && !ShouldDrawNameplate(self));
	plugin.ParseCommand("/nameplatew mode hidenpc", true);
	CHECK(ShouldDrawNameplate(stranger) && !ShouldDrawNameplate(mob));
	plugin.ParseCommand("/nameplatew mode hidepcparty", true);

	// a name that only begins like a listed one is not that name
	const XiModel* friendlier = Make(7, 106, 0x7000, "Friendlier");
	CHECK(!ShouldDrawNameplate(friendlier));
	Make(7, 106, 0x7000, "Frien");
	CHECK(!ShouldDrawNameplate(friendlier));

	// the player's own name stays hidden in a self mode, listed or not
	plugin.ParseCommand("/nameplatew wl add me", true);
	plugin.ParseCommand("/nameplatew mode hidepcpartyself", true);
	CHECK(!ShouldDrawNameplate(self));
	plugin.ParseCommand("/nameplatew mode hidepcparty", true);
	plugin.ParseCommand("/nameplatew wl remove me", true);

	// a second add changes nothing; the list is said back
	plugin.said.clear();
	plugin.ParseCommand("/nameplatew whitelist add Friend", true);
	CHECK(Whitelist.Count == 2 && plugin.said.size() == 1 && plugin.said[0] == "Friend is already on the whitelist.");
	plugin.said.clear();
	plugin.ParseCommand("/nameplatew whitelist list", true);
	CHECK(plugin.said.size() == 2 && plugin.said[0] == "Whitelist (2):" && plugin.said[1] == "Friend, Someoneelse");
	plugin.said.clear();
	plugin.ParseCommand("/nameplatew whitelist", true);
	CHECK(plugin.said.size() == 2);

	// it is saved as it changes, and read back by a load
	Whitelist.Count = 0;
	CHECK(plugin.LoadWhitelist() == 0);
	CHECK(Whitelist.Count == 2 && strcmp(Whitelist.Names[1], "Someoneelse") == 0);

	plugin.ParseCommand("/nameplatew whitelist remove friend nobody", true);
	CHECK(Whitelist.Count == 1 && strcmp(Whitelist.Names[0], "Someoneelse") == 0);
	CHECK(!ShouldDrawNameplate(friendly));
	Whitelist.Count = 0;
	plugin.LoadWhitelist();
	CHECK(Whitelist.Count == 1);

	// the settings, alliance among them, go to the ini and come back; the whitelist with them
	plugin.ParseCommand("/nameplatew alliance on", true);
	plugin.ParseCommand("/nameplatew save", true);
	plugin.ParseCommand("/nameplatew alliance off", true);
	plugin.ParseCommand("/nameplatew mode all", true);
	Whitelist.Count = 0;
	plugin.ParseCommand("/nameplatew load", true);
	CHECK(AsmSettings.NameMode == NAME_MODE::HIDE_PCPARTY && AsmSettings.IncludeAlliance == 1 && Whitelist.Count == 1);

	plugin.ParseCommand("/nameplatew whitelist clear", true);
	CHECK(Whitelist.Count == 0);
	Whitelist.Count = 5;
	plugin.LoadWhitelist();
	CHECK(Whitelist.Count == 0);

	// commands that are wrong say so and change nothing
	CHECK(plugin.messages.empty());
	plugin.ParseCommand("/nameplatew whitelist add", true);
	plugin.ParseCommand("/nameplatew whitelist add Anamethatisfartoolongtobeaname", true);
	plugin.ParseCommand("/nameplatew whitelist frobnicate", true);
	plugin.ParseCommand("/nameplatew alliance maybe", true);
	plugin.ParseCommand("/nameplatew mode hidepcpart", true);
	CHECK(plugin.messages.size() == 5 && Whitelist.Count == 0);
	CHECK(plugin.messages[0] == MESSAGE::WHITELIST_COMMAND_ERROR && plugin.messages[3] == MESSAGE::ALLIANCE_COMMAND_ERROR && plugin.messages[4] == MESSAGE::MODE_COMMAND_ERROR);
	CHECK(AsmSettings.NameMode == NAME_MODE::HIDE_PCPARTY);

	// the old plugin's command is not this one's
	CHECK(!plugin.ParseCommand("/nameplate mode all", true));

	// the game's own "names off" still wins
	namesOff = true;
	CHECK(!ShouldDrawNameplate(mob) && !ShouldDrawNameplate(buddy));

	printf(failures == 0 ? "all checks passed\n" : "%d checks FAILED\n", failures);
	return failures == 0 ? 0 : 1;
}
