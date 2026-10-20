# drawscale

Draw distance for the world and for entities, with the fog kept where you want it and the zone
drawn to match: objects that do not pop in, that keep their detail, and distant terrain the zone
would otherwise hide. Every value is saved per character and applied at load, and a zone can have
values of its own, applied as you arrive. It replaces the stock `drawdistance` addon: unload that
one and take its lines out of your startup script.

It needs nothing else.

## Settings

- `/drawscale` says the current values.
- `/drawscale world <n>` is terrain, objects and far clip at `n` times stock. `1` is stock.
- `/drawscale entity <n>` is players, NPCs and mobs at `n` times stock. The server only sends
  entities within about 50 yalms, so more than that changes little.
- `/drawscale fog <n>` is the fog at `n` times stock, whatever world is. `1` keeps the stock fog in
  front of however much terrain world draws.
- `/drawscale objects <n>` is how far buildings, trees and props are drawn, `n` times stock. `0`,
  the default, follows world. Without this, a world of 2 only pushes objects out about 1.4 times,
  because the client compares squared distances, and they pop in well inside the visible range.
- `/drawscale detail <n>` is how much further objects keep their detailed mesh. Objects swap between
  three meshes at two fixed distances; this moves both switch points out by `n`. `0`, the default,
  follows world.
- `/drawscale vis on|off` (default on) draws distant terrain the zone's visibility lists would hide
  from your area. Zones carry precomputed lists of what is visible from where, and terrain off the
  list is never drawn however far the draw distance goes, popping in as you cross into the next area.
  On costs some frames in big zones. `/drawscale vis` alone toggles it.
- `/drawscale square on|off` (default off) draws the world at the window's true proportions. The
  client builds its projection with a fixed constant that stretches the 3D view about 5.5% wider
  than the window, so people look broad and round things oval; on fixes the constant, and the view
  shows a little more at the sides. The menus and HUD do not change.

## Per zone

The values above are the general ones. A zone can have its own, so a town can draw everything
while a big field keeps its frames:

- `/drawscale zone` says which zone you are in and whether it has values of its own.
- `/drawscale zone on` gives the zone you are in its own values, starting as a copy of the general
  ones. From then on the settings above set this zone's, whenever you are in it, until
  `/drawscale zone off` drops them and the general values apply again.
- `/drawscale zone list` lists every zone with values of its own.
- `/drawscale general <setting> <value>` sets a general value from inside a zone that has its own,
  for example `/drawscale general world 2`.

The zone is read from the game at load and from the zone-in packet after, so the values change as
the new zone loads; a line in the chat says so when the zone has its own. `/drawscale` always says
which zone you are in and whose values are in force.

## How it works

The client multiplies its far clip, fog, zone-object ranges and entity cull distance by two floats,
world and entity; every distance asks one small function for the scale. drawscale sets the two
floats and sends particular calls to that function through stubs of its own: the fog's two calls
(its start and end) multiply their answer by fog / world, and the zone-object range's call multiplies
by objects² / world. The mesh-detail comparisons go through four more stubs that scale the squared
distance by 1 / detail². The visibility-list read is replaced by a read of nothing, and the
projection constant is swapped in the game object once it exists.

The client DLL is packed on disk, so everything is found in the running game, by byte patterns. The
scale function is found by the bytes drawdistance looks for; its entry by the calls to it (92 bytes
before those bytes, as of 2026-10-20); the fog's calls by their shape, in the function just before,
pushing the world selector and multiplying by the answer, twice; the object range's call by where it
stores the answer. If a client update moves any of them, the setting concerned says so at load and
the others keep working.

For the record, and for the next time the client changes:

- `/drawscale callers` lists every call to the scale function: a number, the address, which
  multiplier it selects, what it pushes, and the first thing done with the answer; the fog's two and
  the zone-object range are marked, and the detail and vis sites are counted. The full report, with
  the module scanned and the bytes around each call decoded, is written to
  `config/addons/drawscale/callers.txt`.
- `/drawscale patch <n> <mult>` sends caller `n` through a stub by hand, `/drawscale unpatch [n]`
  puts it (or all of them) back, and `/drawscale scan` finds everything afresh.

Unloading restores every patched byte and puts both multipliers back to 1. The stubs stay allocated,
since the render thread may be inside one at that moment.
