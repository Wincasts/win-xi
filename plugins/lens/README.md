# lens — experimental 0.91

FFXI's world through a Panini or cylindrical projection, either of which keeps a wide view without
the stretching a flat projection gives at the edges of a wide screen. No projection matrix can do that, but the game draws
its world to a texture of its own (at its 3D resolution) and copies it onto the screen with one quad
before drawing the menus and HUD over it. lens draws a warped grid in that quad's place, so the world
is bent and the UI is not. That copy is also where the world's edges are smoothed or not, so lens
draws it with anti-aliasing (`/lens aa`), with the warp on or off. lens also sets the field of view
and proportions the world is drawn with (`/lens middle`, `/lens fov`, `/lens square`), which were
drawscale's (now [vis](../../addons/vis)) until its 2.0.

```text
/load lens
/lens                 what the warp is doing
/lens on|off          everything lens does; off is the game's own view (on to start)
/lens mode panini|cylindrical   (panini to start)
/lens strength <n>    0 (flat, as the game) to 100; 50 to start
/lens aa on|off       each pixel the average of four reads over the world (on to start)
/lens middle <n>      keep n degrees up the middle of the screen whatever the warp (0, none, to start)
/lens fov <n>         draw the world n degrees up instead, 20 to 140 (0, the game's own, to start)
/lens square on|off   the world at the window's true proportions (off to start)
/lens battle same|<n>|0   the camera's distance when you engage: same keeps it, n how far (0, the game's, to start)
```

`/lens off` puts the game's own view back: flat, without aa, at the game's field of view and
proportions. Your settings are kept, and `/lens on` puts them all back. For aa without the warp, use
`/lens strength 0`.

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
`/lens` says how much. Drawing the world taller gives that back:

- `/lens middle <n>` keeps `n` degrees up the middle of the screen, the game's own being 77: lens
  works out the field of view that gives it back for the mode, the strength and the screen's
  proportions, and works it out again whenever one of them changes. At strength 0 it is the
  field of view itself. Past what 140 can give, it draws at the field of view showing the most, and
  `/lens` says so.
- `/lens fov <n>` draws the world `n` degrees up, 20 to 140, whatever the warp; `0` is the game's
  own, about 77. Without the warp, a narrower one stretches the edges of a wide screen less and shows
  less of the world: about 60 at 21:9 sees as far across as the game does at 16:9.

Setting one clears the other. The game keeps the height of the view fixed and widens it to the
window, so at 21:9 it is over 120 degrees across; its own closer views stay closer by the same
proportion. Past about 110 the flat picture the warp starts from spends most of its pixels on the
edges, though the game's 3D resolution being above the screen's helps.

`/lens square on` draws the world at the window's true proportions. The client builds its projection
with a fixed constant that stretches the 3D view about 5.5% wider than the window, so people look
broad and round things oval; on fixes the constant, and the view shows a little more at the sides.
The menus and HUD do not change.

Settings to try at 3440x1440 (21:9), each keeping the game's 77 up the middle of the screen unless
it says otherwise:

| | `/lens mode` | `/lens strength` | `/lens middle` | the world drawn up | across the screen |
|---|---|---|---|---|---|
| Gentle | panini | 25 | 77 | 93 | 134 |
| Balanced | panini | 50 | 77 | 110 | 146 |
| Panoramic, cheap | cylindrical | 50 | 77 | 96 | 132 |
| Panoramic, strong | cylindrical | 75 | 77 | 115 | 142 |
| The game's view, less stretch (70 up the middle) | cylindrical | 25 | 0 | 77 (the game's) | 120 |

The game's own is 122 across. At 16:9 the flat view is 106 across and stretches less, so less
strength does.

### The camera in battle

When you engage, the game moves the camera out from you, from its usual 3 to 6 to 7.2 to 8.6.
`/lens battle same` keeps it where it is: in battle the camera uses the usual distance. `/lens battle
<n>` moves it to `n` instead (1 to 50; the game's is 8.6), and `/lens battle 0` is the game's own.

The two distances are pairs of constants the game's camera reads (found by the patterns of Hokuten's
xicamera addon, `src/camera.h`). Each battle constant has exactly one reader, the battle camera, so
lens points those two reads at values of its own, as it does C for the field of view; the usual
pair is read only, since it is read in dozens of other places across the client and changing it in
place would change them too. `same` follows the usual pair as it stands, so another addon that
changes it in place (xicamera) still gets its own distance in battle as out of it.

Over the world: the game's own target and subtarget arrows (through uihook 0.93), targetlines,
hideparty's target cursor and anything placed by winxi's
`nameplates.Screen` (chatbubbles' bubbles drawn on the screen) move their points to where the warp
shows them, through `winxi.lens` and the block lens publishes (below). name's nameplates and
chatbubbles' world bubbles are drawn into the world by namehook (1.30), which draws each through the
counter of the warp's stretch where it stands, so it comes out of the warp at its own shape and walls
still hide it. Not yet: the game reads clicks on the world through the flat projection,
so near the edges a click lands beside what is under the mouse.

### Anti-aliasing

The game draws its world larger than the screen (its 3D resolution, 5160x2160 at 3440x1440 by
default: 1.5 times across and down) and shrinks it onto the screen in the copy. One smooth read a
pixel takes in only the 2 by 2 of the world's pixels nearest it, so where a screen pixel covers more
than that the rest is skipped: edges stair-step, and fences, leaves and grass shimmer as you move. The
warp makes it worse at the sides, where it squeezes more of the world into each pixel. Forcing MSAA in
DXVK (`d3d9.forceSwapchainMSAA`) does not reach the world at all, as it is not drawn to the screen.

With `/lens aa on`, each pixel is the average of four smooth reads spread over the patch of the
world it covers, worked out at every point of the grid from the warp itself: wider apart where the
edges are squeezed, closer in the enlarged middle, half a pixel apart without the warp. At strength
0 with aa on, lens still draws the copy, flat. `/lens` says what the copy is doing, the
world's size against the screen's, and how the game's own copy reads it.

It can only average what the game drew. A 3D resolution twice the screen's each way (6880x2880 at
3440x1440, in the launcher or the registry's 0003 and 0004) gives each pixel exactly four of the
world's pixels, which the four reads then take in exactly: true 4x supersampling, at about 1.8 times
the cost of drawing at 1.5. At 1.5 aa still smooths what is there.

It needs pixel shader 1.1 and four textures at once, which any card since about 2001 and DXVK have;
without them, or if the game's copy were coloured in a way lens does not know, it reads once a
pixel as before, and `/lens` says so.

### How it works

The game's copy is the one draw that is a strip of two screen-space triangles (FVF 0x144) onto the
back buffer, covering it, textured from a render target; lens builds a 128 by 64 grid over the same
rectangle, each vertex's texture coordinate found by running the projection backwards from the
screen to the flat picture (the game's projection, as set at the copy, gives the picture's fields of
view), draws it with the game's own state but smooth sampling, and blocks the quad. Each vertex
carries five coordinate sets (FVF 0x544): the point by itself, and four taps around it at a quarter
of the way across the patch the screen pixel covers in each direction, the warp's Jacobian there
times the pixel's square (`Taps` in `src/warp.h`). With aa, the world's texture is bound in stages
0 to 3 and a ps_1_1 shader averages them (`src/shaders.h`, written out as tokens and checked against
Wine's d3dx9 assembler by `tests/shaders.cpp`); the game's stages, filters and shader are put back after. The grid is built
again only when the strength, the picture's fields of view or the rectangle change, and kept on the
card between, so a frame draws it without sending it (2026-10-21: some 330 KB a frame before). The
game draws hundreds of other screen quads a frame for its UI; while the warp is live they are told
from the copy by their size alone, before anything is asked of the device.

### The projection

Every world projection is built from the game object's fields: the aspect as 1 / (a * k), a from the
window (+0x2F0) and k the constant square changes (+0x2E8, 0.791, or 0.75 for true proportions), and
the vertical field of view as 2 atan(C / f), C a constant of 192 and f a focal length at +0x2F4 the
game sets (242 in play, more for a closer view). Four places build one, each pass of the frame, each
loading C just before f. lens points those four loads at a value of its own, 242 tan(fov / 2), so the
usual view has the field of view asked for and the game's closer views are closer by as much, whatever
the game does with f; the loads are pointed once and only the value changes after. C is found where
the projection's build function loads it, and the four by their shape (C, then f from the game object
or the stack, then the arctangent) over the whole client, at load; a fixed view the game makes with a
constant in place of f is left alone (`src/projection.h`, found 2026-10-21 for drawscale 1.7). The
game object is reached through the global its accessor reads, and k is set at each Present once the
object exists, only when it holds one of the two constants.

If the four loads already point somewhere else, drawscale before 2.0 has its own fov set: lens leaves
them to it and `/lens` says so (`/drawscale fov 0`, or move to vis). Unloading lens points them
back at C and puts k back; lens's value stays allocated, for a frame still being built.

### For addons

lens publishes what it is doing in a block in lens.dll that begins with the 16 bytes `LENS-WARP` and
zeros: version 1, its size (48), Frame (a count of Presents), WarpedFrame (the Frame the game's copy
was last warped in; live while the two are within a frame or two), Mode (0 Panini, 1 cylindrical),
Strength (0 to 1) and the picture's half fields of view as tangents, TanH and TanV (`src/shared.h`;
exported as `LensWarp` for a plugin to find with GetProcAddress). `winxi.lens` finds it and copies the
mapping, ScreenOf being the reverse of the warp's own: where it shows a point of the flat picture.
`Counter` in `src/warp.h` undoes the warp's stretch around a point, for what is drawn into the picture
and should come out at its own shape. A plugin mapping many points works out `EdgeOf` once and passes
it to `SourceOf` and `ScreenOf`: the cylindrical edge takes sixty halvings to find.

### Finding the mouse

`/lens mouse` is for finding where the game keeps the cursor's place, so that the place it picks
things in the world by can be moved through the warp while its menus keep theirs. With the cursor
over the game, it looks for the cursor's place in the window in writable memory, as a pair in four
forms (32-bit and 16-bit integers, floats, and floats as a fraction of the window). Each later
`/lens mouse`, with the cursor somewhere else, keeps only the places that moved with it. Once 32 or
fewer are left, `config/lens/mouse-<time>.txt` lists them with the client's code that reads them,
directly or through a global pointing at the object they are in, and the bytes around it.
`/lens mouse reset` starts again.

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
