// lens camera: the battle camera's two loads and the usual pair's constants found in the client's own bytes
// (read from the running game on 2026-10-24, FFXiMain.dll at 0x02FC0000), each once, and the battle pair for
// the game's own, same and a distance of the player's.
#include <stdio.h>
#include "../src/camera.h"
static int failures = 0;
static void Check(bool ok, const char* text) { printf("%s %s\n", ok ? "ok" : "FAIL", text); if (!ok) ++failures; }
static bool Near(double a, double b) { return fabs(a - b) < 1e-6; }
static std::vector<uint8_t> Bytes(const char* hex) {
    std::vector<uint8_t> out;
    for (size_t i = 0; hex[i] && hex[i + 1]; i += 2) out.push_back(static_cast<uint8_t>(lens::HexDigit(hex[i]) * 16 + lens::HexDigit(hex[i + 1])));
    return out;
}

int main() {
    // the battle camera at 0x02FE03DD: its fld [battle min] at +0x0E and fadd [battle max] at +0x1A
    const auto battle = Bytes("4C8D9424AC0000005152D8442424D905A8A32E03D8C1D8CAD95C2450D805A4A32E03D8C9D99C24DC000000DDD8D94424");
    const lens::Pattern min(lens::BattleMinPattern), max(lens::BattleMaxPattern);
    const ptrdiff_t a = lens::Find(battle.data(), battle.size(), min), b = lens::Find(battle.data(), battle.size(), max);
    Check(a == 8 && battle[a + lens::BattleMinAt] == 0xD9 && lens::U32(&battle[a + lens::BattleMinAt + 2]) == 0x032EA3A8, "the battle min's load found, reading 0x032EA3A8");
    Check(b == 20 && battle[b + lens::BattleMaxAt] == 0xD8 && lens::U32(&battle[b + lens::BattleMaxAt + 2]) == 0x032EA3A4, "the battle max's load found, reading 0x032EA3A4");
    Check(lens::Find(battle.data() + a + 1, battle.size() - a - 1, min) == -1 && lens::Find(battle.data() + b + 1, battle.size() - b - 1, max) == -1, "each once");

    const auto normalMin = Bytes("D8C9D9C0D8C1D9C2D80D389D2E03D9C3DCC0D8EBD8442404");
    const auto normalMax = Bytes("D9442410D825E8A32E0351D80DC4A32E");
    const lens::Pattern nmin(lens::NormalMinPattern), nmax(lens::NormalMaxPattern);
    const ptrdiff_t c = lens::Find(normalMin.data(), normalMin.size(), nmin), d = lens::Find(normalMax.data(), normalMax.size(), nmax);
    Check(c == 0 && lens::U32(&normalMin[c + lens::NormalMinAt]) == 0x032E9D38, "the usual min's constant, 0x032E9D38");
    Check(d == 0 && lens::U32(&normalMax[d + lens::NormalMaxAt]) == 0x032EA3E8, "the usual max's constant, 0x032EA3E8");

    // the game's 3 to 6, and 7.2 to 8.6 in battle
    double lo = 0, hi = 0;
    lens::BattleRange(lens::Battle::Game, 0, 3, 6, 7.2, 8.6, lo, hi);
    Check(Near(lo, 7.2) && Near(hi, 8.6), "the game's own: its battle pair");
    lens::BattleRange(lens::Battle::Same, 0, 3, 6, 7.2, 8.6, lo, hi);
    Check(Near(lo, 3) && Near(hi, 6), "same: the usual pair in battle");
    lens::BattleRange(lens::Battle::Same, 0, 2, 5, 7.2, 8.6, lo, hi);
    Check(Near(lo, 2) && Near(hi, 5), "same follows the usual pair as it is");
    lens::BattleRange(lens::Battle::Distance, 12, 3, 6, 7.2, 8.6, lo, hi);
    Check(Near(lo, 10.6) && Near(hi, 12), "a distance: max there, min the game's battle span below");
    lens::BattleRange(lens::Battle::Distance, 1, 3, 6, 7.2, 8.6, lo, hi);
    Check(Near(lo, 0) && Near(hi, 1), "a short distance keeps min at 0");
    printf(failures ? "%d FAILED\n" : "lens camera: all checks passed\n", failures);
    return failures;
}
