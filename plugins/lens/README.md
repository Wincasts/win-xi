# lens — experimental 0.4

FFXI's world through a Panini or cylindrical projection, either of which keeps a wide view without
the stretching a flat projection gives at the edges of a wide screen. No projection matrix can do that, but the game draws
its world to a texture of its own (at its 3D resolution) and copies it onto the screen with one quad
before drawing the menus and HUD over it. lens draws a warped grid in that quad's place, so the world
is bent and the UI is not.

```text
/load lens
/lens                 what the warp is doing
/lens on|off          the warp (on to start)
/lens mode panini|cylindrical   (panini to start)
/lens strength <n>    0 (flat, as the game) to 100; 50 to start
```

- **Panini** keeps lines running toward the middle of the view straight (a road or corridor ahead,
  the edges of what you face) and squeezes the edges somewhat. The strength is its distance: 100 is
  the classic Panini.
- **Cylindrical** gives every degree across the same width on the screen, the look of a panoramic
  photograph: the sides look the most natural, and long lines across the side of the view bow
  a little. The strength blends from the flat picture to it. Fully cylindrical can't keep the whole
  width with the corners inside the picture, so it gives up a few degrees at the sides; and its middle
  keeps shrinking as the field of view grows, so stay below 100.

Both keep verticals and the horizon straight.

The settings are kept in `config/lens/lens.ini` under the Ashita folder.

The warp keeps the whole width the game draws: its left and right edges stay at the screen's, and
the screen's corners show the picture's corners. Everything between is squeezed toward the edges by
the strength, so the middle is enlarged and shows less up and down than the world is drawn with;
`/lens` says how much. Draw the world taller to give that back, with drawscale's `fov` above the
game's 77 (it goes to 140). Past about 110 the flat picture the warp starts from spends most of its
pixels on the edges, though the game's 3D resolution being above the screen's helps.

Settings to try at 3440x1440 (21:9, drawscale square off), each keeping about the game's 77 up the
middle of the screen unless it says otherwise:

| | `/lens mode` | `/lens strength` | `/drawscale fov` | across the screen |
|---|---|---|---|---|
| Gentle | panini | 25 | 93 | 134 |
| Balanced | panini | 50 | 110 | 146 |
| Panoramic, cheap | cylindrical | 50 | 96 | 132 |
| Panoramic, strong | cylindrical | 75 | 115 | 142 |
| The game's view, less stretch (70 up the middle) | cylindrical | 25 | 0 (the game's 77) | 120 |

The game's own is 122 across. At 16:9 the flat view is 106 across and stretches less, so less
strength does.

Over the world: targetlines, hideparty's target cursor and anything placed by winxi's
`nameplates.Screen` (chatbubbles' bubbles drawn on the screen) move their points to where the warp
shows them, through `winxi.lens` and the block lens publishes (below). name's nameplates and
chatbubbles' world bubbles are drawn into the world by namehook (1.30), which draws each through the
counter of the warp's stretch where it stands, so it comes out of the warp at its own shape and walls
still hide it. Not yet: the game reads clicks on the world through the flat projection,
so near the edges a click lands beside what is under the mouse.

### How it works

The game's copy is the one draw that is a strip of two screen-space triangles (FVF 0x144) onto the
back buffer, covering it, textured from a render target; lens builds a 128 by 64 grid over the same
rectangle, each vertex's texture coordinate found by running the projection backwards from the
screen to the flat picture (the game's projection, as set at the copy, gives the picture's fields of
view), draws it with the game's own state but smooth sampling, and blocks the quad. The grid is built
again only when the strength, the picture's fields of view or the rectangle change.

### For addons

lens publishes what it is doing in a block in lens.dll that begins with the 16 bytes `LENS-WARP` and
zeros: version 1, its size (48), Frame (a count of Presents), WarpedFrame (the Frame the game's copy
was last warped in; live while the two are within a frame or two), Mode (0 Panini, 1 cylindrical),
Strength (0 to 1) and the picture's half fields of view as tangents, TanH and TanV (`src/shared.h`;
exported as `LensWarp` for a plugin to find with GetProcAddress). `winxi.lens` finds it and copies the
mapping, ScreenOf being the reverse of the warp's own: where it shows a point of the flat picture.
`Counter` in `src/warp.h` undoes the warp's stretch around a point, for what is drawn into the picture
and should come out at its own shape.

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
