# blockpool 0.1

Reuses the d3d8 state blocks that are made and deleted every frame, around a leak in Proton's
wined3d (GE-Proton11-5, seen 2026-10-26/27). Ashita's core creates a state block of type
`D3DSBT_ALL` once a frame and once for every font or primitive object it draws (points' compact bar,
truefps' counter), applies it after drawing and deletes it. Each such create copies the game's lights
into the new block, and the delete leaves one copy of light 2 behind, 272 bytes a time: about 12 MB a
minute with eight font objects on screen, and the 32-bit process out of address space in about
2 h 45 min (the crash of 2026-10-27 00:04, Ashita's log ending in `Addon 'trigger' threw an exception
in event 'd3d_present' (E24C4A04)`, LuaJIT's "not enough memory").

A fresh `D3DSBT_ALL` block is a snapshot of the whole device state at the create; so is
`CaptureStateBlock` on an existing one, which copies no lights. So `CreateStateBlock(ALL)` is
answered with a block from a pool, captured just now, and `DeleteStateBlock` of a pooled block puts
it back. The first use of each pool slot is a real create (one copy leaked, once); after that nothing
is. Vertex-state blocks are pooled the same way; pixel-state blocks pass through. `Reset` deletes the
idle pool and forgets the rest.

```text
/load blockpool
/blockpool            pool size and how many creates were answered from it
```

A pooled block holds only the lights that existed when its slot was first created; an apply of it
does not restore a light the game first touches later. The game sets every light it uses each frame,
so nothing is seen of that.

Load it before `d3dcount` if both are wanted; they patch the same device slots, and the later one
has to be unloaded first. Found with [d3dcount](../d3dcount) and `tools/leakwatch.py`.
