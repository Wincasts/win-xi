# drawscale

World and entity draw distance with the fog kept where you want it. The client multiplies its far
clip, its fog, its zone-object ranges and its entity cull distance by two floats, world and entity,
which the stock `drawdistance` addon sets; raising the world one pushes the fog out with the
terrain, so weather thins. drawscale sets the same two floats and adds a third, fog, by sending the
fog's two distance calls (its start and its end) through a stub of its own, so the fog sits at `fog`
times stock whatever `world` is. A fog of 1 with a world of 2 is stock fog in front of twice the
terrain. The three are saved per character and applied at load. It replaces `drawdistance`: unload
that one and take its lines out of your startup script.

It needs nothing else.

- `/drawscale` says the current values.
- `/drawscale world <n>` is terrain, objects and far clip at `n` times stock. `1` is stock.
- `/drawscale entity <n>` is players, NPCs and mobs at `n` times stock. The server only sends
  entities within about 50 yalms, so more than that changes little.
- `/drawscale fog <n>` is the fog at `n` times stock, whatever world is. `1` keeps the stock fog.

For the record, and for the next time the client changes:

- `/drawscale callers` lists every call to the client's scale function: a number, the address,
  which multiplier it selects, what it pushes, and the first thing done with the answer; the fog's
  two and the zone-object range are marked. The full report, with the module scanned and the bytes
  around each call decoded, is written to `config/addons/drawscale/callers.txt`.
- `/drawscale patch <n> <mult>` sends caller `n` through a stub by hand, `/drawscale unpatch [n]`
  puts it (or all of them) back, and `/drawscale scan` finds everything afresh.

## How it finds the fog

The client DLL is packed on disk, so everything is found in the running game. The scale function is
found by the bytes drawdistance looks for; its entry by the calls to it (92 bytes before those bytes,
as of 2026-10-20); and the fog's calls by their shape: in the function just before, pushing the world
selector, and multiplying a distance by the answer, twice. If a client update moves them, the fog
setting says so and world and entity still work; `/drawscale callers` is the first thing to read then.

Unloading restores every call and puts both multipliers back to 1.
