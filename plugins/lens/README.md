# lens — experimental 0.2

FFXI's world through a Panini projection, which keeps a wide view without the stretching a flat
projection gives at the edges of a wide screen. No projection matrix can do that, but the game draws
its world to a texture of its own (at its 3D resolution) and copies it onto the screen with one quad
before drawing the menus and HUD over it. lens draws a warped grid in that quad's place, so the world
is bent and the UI is not.

```text
/load lens
/lens                 what the warp is doing
/lens on|off          the warp (on to start)
/lens strength <n>    0 (flat, as the game) to 100 (the classic Panini); 50 to start
```

The settings are kept in `config/lens/lens.ini` under the Ashita folder.

The warp keeps the whole width the game draws: its left and right edges stay at the screen's, and
the screen's corners show the picture's corners. Everything between is squeezed toward the edges by
the strength, so the middle is enlarged and shows less up and down than the world is drawn with;
`/lens` says how much. Draw the world taller to give that back, with drawscale's `fov` above the
game's 77 (it goes to 140). At 3440x1440, keeping the game's 77 up the middle takes about 92 at
strength 25 and 110 at 50; past that the flat picture the warp starts from wastes its pixels at the
edges, though the game's 3D resolution being above the screen's helps.

Not yet: clicks on the world are still read through the flat projection, so near the edges they land
beside what is under the mouse, and addons drawing over the world (targetlines, name's nameplates)
are not bent with it.

### How it works

The game's copy is the one draw that is a strip of two screen-space triangles (FVF 0x144) onto the
back buffer, covering it, textured from a render target; lens builds a 128 by 64 grid over the same
rectangle, each vertex's texture coordinate found by running the Panini mapping backwards from the
screen to the flat picture (the game's projection, as set at the copy, gives the picture's fields of
view), draws it with the game's own state but smooth sampling, and blocks the quad. The grid is built
again only when the strength, the picture's fields of view or the rectangle change.

### Capture

`/lens capture [frames]` records every draw over the next frames (2 to start, at most 10) and writes
`config/lens/capture-<date>-<time>.txt`: for each draw its kind, primitive type and count, its FVF
and whether its vertices are 3D or already on the screen (XYZRHW), the render target and its size,
the viewport, depth test and write, blending, fog, the projection and view as it stands (each
distinct one numbered, a perspective with its fields of view), the texture, and the game's code that
made it: the nearest two return addresses into FFXiMain.dll up the stack, read as the stack lies
since the client does not keep frame pointers everywhere. A summary groups draws in a row that share
their target, space, projection, view, depth test, viewport and caller into runs, with the scenes
and frames between them. It is how the copy was found (2026-10-21): the sky and the world into a
target of the 3D resolution, one quad from it onto the back buffer, then the UI.

## Build

```sh
plugins/lens/build.sh
plugins/lens/tests/run.sh
```

The same clang-cl/lld-link, x86 Windows SDK and Ashita SDK toolchain as uihook (default
`.toolchain`; overrides: `TOOLCHAIN`, `ASHITA_SDK_PATH`, `MSVC_PATH`). Output: `plugins/lens/build/lens.dll`.
