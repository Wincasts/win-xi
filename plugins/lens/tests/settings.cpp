// lens settings: lens.ini's lines for your own settings and the ultrawide preset, read and written, each set
// reading only its own lines, and an ini from before the preset leaving it as it starts.
#include <stdio.h>
#include "../src/settings.h"
static int failures = 0;
static void Check(bool ok, const char* text) { printf("%s %s\n", ok ? "ok" : "FAIL", text); if (!ok) ++failures; }
static void ReadAll(const std::string& text, const char* prefix, lens::Settings& s) {
    size_t at = 0;
    while (at < text.size()) {
        size_t end = text.find('\n', at);
        std::string line = text.substr(at, end == std::string::npos ? std::string::npos : end + 1 - at);
        lens::ReadSetting(line.c_str(), prefix, s);
        at = end == std::string::npos ? text.size() : end + 1;
    }
}
static bool Same(const lens::Settings& a, const lens::Settings& b) {
    return a.strength == b.strength && a.mode == b.mode && a.aa == b.aa && a.fov == b.fov && a.middle == b.middle && a.square == b.square
        && a.battle == b.battle && (a.battle != lens::Battle::Distance || a.battleDistance == b.battleDistance);
}

int main() {
    const lens::Settings u = lens::Ultrawide();
    Check(u.strength == 25 && u.mode == lens::Panini && u.aa && u.fov == 68 && u.middle == 0 && u.square && u.battle == lens::Battle::Distance && u.battleDistance == 15,
        "the preset to start: panini 25, aa, fov 68, square, battle 15");

    lens::Settings own;
    own.strength = 60; own.mode = lens::Cylindrical; own.aa = false; own.middle = 80; own.battle = lens::Battle::Same;
    const std::string ini = "on=1\nultrawide=1\n" + lens::WriteSettings(own, "") + lens::WriteSettings(u, "ultrawide.");
    lens::Settings a, b = lens::Ultrawide();
    b.strength = 0;   // read over, so it must come back from the ini
    ReadAll(ini, "", a);
    ReadAll(ini, "ultrawide.", b);
    Check(Same(a, own), "your own settings read back from their lines alone");
    Check(Same(b, u), "the preset read back from its lines alone");

    lens::Settings old = lens::Ultrawide();
    ReadAll("on=1\nstrength=25\nmode=0\naa=1\nfov=68\nmiddle=0\nsquare=1\nbattle=15\n", "ultrawide.", old);
    Check(Same(old, u), "an ini from before the preset leaves the preset as it starts");

    lens::Settings bad = lens::Ultrawide();
    ReadAll("ultrawide.strength=400\nultrawide.fov=5\nultrawide.battle=nonsense\n", "ultrawide.", bad);
    Check(bad.strength == 25 && bad.fov == 68 && bad.battle == lens::Battle::Game, "values out of range kept out; an unknown battle is the game's");

    printf(failures ? "%d FAILED\n" : "lens settings: all checks passed\n", failures);
    return failures;
}
