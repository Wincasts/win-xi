# blockpool 0.1

Works around a memory leak in Proton's wined3d (GE-Proton11-5, seen 2026-10-26/27). Load it if you
play under Proton. Ashita makes and deletes a d3d8 state block once a frame and once for every font
or primitive object it draws (points' compact bar, truefps' counter), and each delete there leaves a
little memory behind: about 12 MB a minute with eight font objects on screen. The game runs out of
memory in about 2 h 45 min, and Ashita's log may end with an addon's `d3d_present` exception and
LuaJIT's "not enough memory".

## How it works

blockpool keeps the state blocks in a pool and reuses them instead of making new ones. The first use
of each one in the pool still leaks once; after that nothing is lost.

```text
/load blockpool
/blockpool            pool size and how many creates were answered from it
```

A pooled block holds only the lights that existed when its slot was first created; an apply of it
does not restore a light the game first touches later. The game sets every light it uses each frame,
so nothing is seen of that.
