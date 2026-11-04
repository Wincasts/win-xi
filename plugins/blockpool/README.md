# blockpool 0.1

A plugin for players who run the game through Proton (a way to play Windows games on Linux). It
works around a memory leak in Proton (GE-Proton11-5, seen 2026-10-26/27) that can make the game run
out of memory after a few hours. Load it if you play under Proton.

## Why use it

- Without it, the game under Proton can run out of memory and crash after about 2 hours 45 minutes.
- It stops the leak: after a small loss at the start, no more memory is lost.
- You load it once. There is nothing to set.

## Using it

```text
/load blockpool
/blockpool            says the pool size, and how many state blocks it made and how many it reused
```

## The problem it fixes

Proton turns the game's graphics calls into calls Linux can run. Its part for this is called wined3d.
Ashita (the program that runs addons) asks the graphics system to save and restore its settings. It
does this once a frame, and once for every text or shape object it draws (for example the compact bar
of the points addon, or the counter of truefps). Each time, Proton leaks a little memory:

- about 12 MB a minute with eight text objects on screen;
- the game runs out of memory in about 2 h 45 min;
- Ashita's log may then end with an addon's `d3d_present` exception and LuaJIT's "not enough memory".

## How it works

The saved graphics settings are called state blocks. blockpool keeps state blocks in a pool and reuses
them instead of making new ones. The first use of each one in the pool still leaks once. After that,
no memory is lost.

## Limitation

A reused state block holds only the lights that existed when it was first made. So restoring it does
not restore a light the game starts using later. The game sets every light it uses each frame, so you
do not see any difference.
