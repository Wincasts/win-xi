// The settings lens draws with, and lens.ini's lines for them. Two sets are kept: your own and the ultrawide
// preset (/lens ultrawide on|off), its lines the same with "ultrawide." before them. Pure: text and numbers,
// so the check can run it.
#pragma once
#include <stdio.h>
#include <string.h>
#include <string>
#include "warp.h"
#include "camera.h"

namespace lens {

struct Settings {
    int strength = 50;          // the Panini distance, or for cylindrical how far from flat, in hundredths
    Mode mode = Panini;
    bool aa = true;             // four taps a pixel
    int fov = 0;                // the vertical field of view in degrees; 0 for the game's own
    int middle = 0;             // degrees to keep up the middle through the warp; 0 for none. One of the two at most
    bool square = false;        // the world at the window's true proportions
    Battle battle = Battle::Game;
    double battleDistance = 0;  // for Battle::Distance
};

// The ultrawide preset to start: panini at 25, aa, fov 68, square and battle 15 (the settings in play on 2026-10-24)
inline Settings Ultrawide() {
    Settings s;
    s.strength = 25; s.fov = 68; s.square = true; s.battle = Battle::Distance; s.battleDistance = 15;
    return s;
}

// battle as the ini and the status have it: game, same or the distance
inline std::string BattleWord(Battle battle, double distance) {
    if (battle == Battle::Same) return "same";
    if (battle == Battle::Game) return "game";
    char text[32];
    snprintf(text, sizeof(text), "%g", distance);
    return text;
}

// One line of lens.ini into s, when it is one of s's after prefix; lines for anything else are left alone.
inline void ReadSetting(const char* line, const char* prefix, Settings& s) {
    size_t n = strlen(prefix);
    if (strncmp(line, prefix, n) != 0) return;
    line += n;
    int v = 0;
    if (sscanf_s(line, "strength=%d", &v) == 1 && v >= 0 && v <= 100) s.strength = v;
    if (sscanf_s(line, "mode=%d", &v) == 1 && (v == 0 || v == 1)) s.mode = static_cast<Mode>(v);
    if (sscanf_s(line, "aa=%d", &v) == 1) s.aa = v != 0;
    if (sscanf_s(line, "fov=%d", &v) == 1 && (v == 0 || (v >= FovMin && v <= FovMax))) s.fov = v;
    if (sscanf_s(line, "middle=%d", &v) == 1 && (v == 0 || (v >= FovMin && v <= FovMax))) s.middle = v;
    if (sscanf_s(line, "square=%d", &v) == 1) s.square = v != 0;
    char word[16] = {};
    double d = 0;
    if (sscanf_s(line, "battle=%15s", word, 16u) == 1) {
        if (_stricmp(word, "same") == 0) s.battle = Battle::Same;
        else if (sscanf_s(word, "%lf", &d) == 1 && d >= BattleLeast && d <= BattleMost) { s.battle = Battle::Distance; s.battleDistance = d; }
        else s.battle = Battle::Game;
    }
}

// s as lens.ini's lines, each after prefix
inline std::string WriteSettings(const Settings& s, const char* prefix) {
    char text[256];
    snprintf(text, sizeof(text), "%sstrength=%d\n%smode=%d\n%saa=%d\n%sfov=%d\n%smiddle=%d\n%ssquare=%d\n%sbattle=%s\n",
        prefix, s.strength, prefix, static_cast<int>(s.mode), prefix, s.aa ? 1 : 0, prefix, s.fov, prefix, s.middle,
        prefix, s.square ? 1 : 0, prefix, BattleWord(s.battle, s.battleDistance).c_str());
    return text;
}

} // namespace lens
