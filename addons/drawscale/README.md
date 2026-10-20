# drawscale

A diagnostic for separating the fog from the draw distance. The client multiplies its far clip, its
fog, its zone-object ranges and its entity cull distance by two floats, world and entity, which the
`drawdistance` and `drawcull` addons set; every one of those distances goes through one small
function. drawscale finds that function, scans the client's code for every call to it, and says what
each caller hands it and does with the answer. Then one caller can be sent through a stub that scales
its answer on its own, so that, say, the fog stays at stock while the world multiplier stays at 2.

It needs nothing else. It changes nothing until told to, and unloading puts every call back.

- `/drawscale` prints the callers again: a number, the address, which multiplier it selects (`world`,
  `entity`, or where it reads the selector from), what it pushes, and the first thing done with the
  answer. The caller that stores to the zone-object range is marked; it is the one drawcull patches.
- `/drawscale scan` finds them afresh.
- `/drawscale patch <n> <mult>` sends caller `n` through a stub so that its distance is `mult` times
  stock whatever the world multiplier is. `1` is stock. Up to eight callers at once.
- `/drawscale unpatch [n]` puts caller `n`, or all of them, back.

The full report, with the bytes before and after each call and what they decode to, is written to
`config/addons/drawscale/callers.txt` whenever the callers are listed.

## Finding the fog

1. Set the draw distance as usual (`/drawdistance setw 2`) and stand somewhere with weather fog.
2. `/addon load drawscale`. Read the list; the world callers are the candidates.
3. `/drawscale patch <n> 1` for one world caller at a time, looking at the fog after each. The one
   that pulls the fog back in is the fog's. `/drawscale unpatch <n>` before trying the next.
4. The fog start and end may be two callers; patch both.

A patched caller is a change to the running client's code: if a patch makes the picture wrong,
`/drawscale unpatch` puts it back, and if the game crashes, the caller was not one to touch. The
report file survives either.
