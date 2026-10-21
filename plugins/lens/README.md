# lens — diagnostic 0.1

The start of a plugin to draw FFXI's world through a projection of its own (Panini or cylindrical),
which keeps a wide view without the stretching a flat projection gives at the edges of a wide screen.
No matrix can do that: the world has to be drawn to a texture of our own and laid onto the screen
through a warped grid before the game's UI is drawn over it. For that, the place where the 3D world
ends and the UI begins must be known, and so must whether anything of the world is drawn after it.

For now lens only records what the game draws, so that place can be found:

```text
/load lens
/lens capture [frames]
```

`/lens capture` records every draw over the next frames (2 to start, at most 10) and writes
`config/lens/capture-<date>-<time>.txt` under the Ashita folder. For each draw: its kind, primitive
type and count, its FVF and whether its vertices are 3D or already on the screen (XYZRHW), the render
target and its size, the viewport, depth test and write, blending, fog, the projection and view as
it stands (each distinct one numbered, a perspective with its fields of view), the texture, and the
game's code that made it: the nearest two return addresses into FFXiMain.dll up the stack, read as
the stack lies since the client does not keep frame pointers everywhere. A summary groups draws in a
row that share their target, space, projection, view, depth test, viewport and caller into runs,
with the scenes and frames between them.

Take one standing in the open with name plates and the HUD as you play, and one with a menu open.
Recording changes nothing in the game.

## Build

```sh
plugins/lens/build.sh
plugins/lens/tests/run.sh
```

The same clang-cl/lld-link, x86 Windows SDK and Ashita SDK toolchain as uihook (default
`.toolchain`; overrides: `TOOLCHAIN`, `ASHITA_SDK_PATH`, `MSVC_PATH`). Output: `plugins/lens/build/lens.dll`.
