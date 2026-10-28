# vis

Draw distance for the world and for entities. The fog stays where you want it, and the zone is drawn
to match: objects do not pop in, they keep their detail, and distant terrain the zone would otherwise
hide is drawn. Every value is saved per character and applied at load. Cities, the outdoors and
dungeons can each have a preset, and a zone can have values of its own, applied as you arrive. It
replaces the stock `drawdistance` addon: unload that one and take its lines out of your startup
script.

It needs nothing else. Its release carries its own copy of the parts of winxi it uses (among them
the server data it reads, and the kind of each zone).

vis was called drawscale until 2.1, and its `terrain` setting was called `vis`. The first time vis
loads for a character, it copies their drawscale settings, says so, and reads a saved `vis` as
`terrain`. Take `/addon load drawscale` out of your startup script and put `/addon load vis` in its
place. Don't load both: they patch the same places in the game.

## Settings

- `/vis` says the current values.
- `/vis world <n>` sets terrain, objects and far clip to `n` times stock. `1` is stock.
- `/vis entity <n>` sets players, NPCs and mobs to `n` times stock. The server only sends
  entities within about 50 yalms, so more than that changes little.
- `/vis fog <n>` sets the fog to `n` times stock, whatever world is. `1` keeps the stock fog in
  front of however much terrain world draws.
- `/vis objects <n>` sets how far buildings, trees and props are drawn: `n` times stock. `0`,
  the default, follows world. Without this, a world of 2 only pushes objects out about 1.4 times,
  because the client compares squared distances, and they pop in well inside the visible range.
- `/vis detail <n>` sets how much further objects keep their detailed mesh. Objects swap between
  three meshes at two fixed distances; this moves both switch points out by `n`. `0`, the default,
  follows world.
- `/vis terrain on|off` (default off) draws distant terrain that the zone's visibility lists would
  hide from your area. Zones carry precomputed lists of what is visible from where. Terrain that is
  not on the list is never drawn, however far the draw distance goes, and it pops in as you cross
  into the next area. On costs frames in big zones, and with the fog at stock most of what it adds
  is fogged out anyway. It was the default until 2.2; a terrain on saved before then is turned off
  once, and vis says so at load. `/vis terrain` alone toggles it.

The field of view and the world's true proportions were `fov` and `square` until 2.0. They belong
to the [lens](../../plugins/lens) plugin now: `/lens fov`, `/lens middle` and `/lens square`, with
lens's warp or without it. A character's saved fov and square are said once at load, as the lens
commands that set them. A zone's or preset's own fov and square are gone.

## Per kind of zone, and per zone

The values above are the general ones. Two more layers sit over them. Each holds only what you set
in it, and every value in force comes from the most particular layer that has it:

- A preset for each kind of zone. Every zone the server has is a city, outdoors or a dungeon
  (its dungeons, instanced areas, Dynamis and battlefields). The kind comes from `zones.lua`, built
  from the server's zone data (winxi's `zonekinds` set) with `tools/build_zone_kinds.py`.
  `/vis dungeon world 2` sets the world for every dungeon; `/vis city terrain off`,
  `/vis outdoors fog 1.5` and the rest work the same way. `/vis dungeon` alone shows the preset,
  `/vis dungeon world clear` takes one value out of it, and `/vis dungeon clear` empties it. To
  begin with, cities and dungeons have world x2 in their presets, and the outdoors preset is empty,
  so the outdoors draw with the general values.
- A zone's own values. `/vis zone world 3` sets the world for the zone you stand in alone.
  `/vis zone world clear` takes it out, `/vis zone clear` takes out all of them, and
  `/vis zone list` lists every zone with values of its own.

So in a dungeon, with the presets as they start, world is 2 from the dungeon preset and everything
else is the general value. A dungeon given its own world of 3 draws with that. The zone is read from
the game at load, and from the zone-in packet after that, so the values change as the new zone
loads. A line in the chat says what the zone gets from its own values and from its kind's preset.
`/vis` says which zone you are in, its kind, the values in force and where each override comes
from. A zone the server has no data for is of no known kind. It draws with the general values, plus
its own if it has any.

## How it works

The client multiplies its far clip, fog, zone-object ranges and entity cull distance by two floats,
world and entity. Every distance asks one small function for the scale. vis sets the two floats,
and sends particular calls to that function through stubs of its own: the fog's two calls (its
start and end) multiply their answer by fog / world, and the zone-object range's call multiplies by
objects² / world. The mesh-detail comparisons go through four more stubs that scale the squared
distance by 1 / detail². The visibility-list read is replaced by a read of nothing.

The client DLL is packed on disk, so everything is found in the running game, by byte patterns. The
scale function is found by the bytes drawdistance looks for. Its entry is found by the calls to it
(92 bytes before those bytes, as of 2026-10-20). The fog's calls are found by their shape, in the
function just before: pushing the world selector and multiplying by the answer, twice. The object
range's call is found by where it stores the answer. If a client update moves any of them, the
setting concerned says so at load, and the others keep working.

For the record, and for the next time the client changes:

- `/vis callers` lists every call to the scale function: a number, the address, which
  multiplier it selects, what it pushes, and the first thing done with the answer. The fog's two and
  the zone-object range are marked, and the detail and vis sites are counted. The full report, with
  the module scanned and the bytes around each call decoded, is written to
  `config/addons/vis/callers.txt`.
- `/vis patch <n> <mult>` sends caller `n` through a stub by hand, `/vis unpatch [n]`
  puts it (or all of them) back, and `/vis scan` finds everything afresh.

An error in any of vis's events is said once in the chat, and vis keeps going. This is because
Ashita unloads an addon whose event errors without letting it put the game back. A game left patched
that way (drawscale 1.6 could do this, 2026-10-21) shows as the fog, range and detail sites not
found at load. A restart of the game clears it.

Unloading restores every patched byte and puts both multipliers back to 1. The stubs stay allocated,
since the render thread may be inside one at that moment.
