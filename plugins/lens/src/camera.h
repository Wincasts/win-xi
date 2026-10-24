// The camera's distance from the player in battle (battle). Engaged, the game moves the camera out from its
// usual distance, 3 to 6, to its battle distance, 7.2 to 8.6, each a pair of float constants. Pure: byte spans
// and numbers, so the check can run it.
//
// Found by xicamera's patterns (Hokuten's addon, 0.7.10) and checked in the running game on 2026-10-24: each
// matches once, and each battle constant has exactly one reader, the battle camera's two loads below, so lens
// points those two loads at floats of its own as it does C for the field of view, and the constants stay as
// they are. The usual pair is read only: they are shared constants (3 is read in 36 places across the client,
// 6 in 12), so changing them in place, as xicamera does, changes whatever else reads them.
#pragma once
#include "projection.h"

namespace lens {

// push ecx; push edx; fadd [esp+0x24]; fld [battle min]; fadd st, st(1)
static const char BattleMinPattern[] = "5152D8442424D905????????D8C1";
static const size_t BattleMinAt = 0x06;   // the fld's opcode, its operand 2 bytes in
// fadd st, st(1); fmul st, st(2); fstp [esp+0x50]; fadd [battle max]; fmul st, st(1)
static const char BattleMaxPattern[] = "D8C1D8CAD95C2450D805????????D8C9";
static const size_t BattleMaxAt = 0x08;
// where the usual pair is read: fmul [min] at +0x08, fsub [max] at +0x04
static const char NormalMinPattern[] = "D8C9D9C0D8C1D9C2D80D????????D9C3DCC0D8EB";
static const size_t NormalMinAt = 0x0A;
static const char NormalMaxPattern[] = "D9442410D825????????51D80D";
static const size_t NormalMaxAt = 0x06;

// What /lens battle asks for: the game's own, the usual distance kept in battle, or a distance of the player's.
enum class Battle { Game, Same, Distance };
static const double BattleLeast = 1, BattleMost = 50;

// The battle pair to draw with, min and max, for what is asked: the usual pair for Same; for Distance, max at
// the distance and min below it by the game's own battle span (1.4), as xicamera does; the game's for Game.
inline void BattleRange(Battle what, double distance, double normalMin, double normalMax, double battleMin, double battleMax, double& min, double& max) {
    if (what == Battle::Same) { min = normalMin; max = normalMax; return; }
    if (what == Battle::Distance) { max = distance; min = distance - (battleMax - battleMin); if (min < 0) min = 0; return; }
    min = battleMin; max = battleMax;
}

} // namespace lens
