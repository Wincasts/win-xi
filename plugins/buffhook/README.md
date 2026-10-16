# buffhook

An Ashita v4 plugin that draws the `buff` addon's bar where, and when, the game draws its own row of
status icons, in their place. The game's menus that open over its icons (the macro palettes, the
main menu, and the rest) are drawn over the bar as they would be over them, a menu that covers part
of the bar covers just that part, and when the game does not draw its icons (no statuses, the
interface hidden, a cutscene) the bar is not drawn either.

It is loaded with `/load buffhook`, before `/addon load buff`. It has no commands. Without the
`buff` addon it does nothing: the game draws its own icons.

## How

The game draws its status icons as one of its menus: the menu's list calls one function for each
icon it shows, and another for each icon's time (with the game's own timers switched on). The plugin
finds both in `FFXiMain.dll` by their first bytes (`src/game.h`) and has them jump to its own
(`src/detour.h`). While the addon has handed it a bar in the last two frames, the first draws the
whole bar for the first icon, where the game would have put that icon, and nothing for the others;
the second draws nothing. The game draws the menus that come after its status icons on top of
whatever was drawn there, so they cover the bar. When the addon has not handed it a bar, both run as
the game's own.

The bar is drawn with Direct3D 8 as the game draws its icons, at that moment in the frame: the
device's state is recorded before and put back after.

While it draws the bar, the plugin also puts the hand the game's buff selector points with out of
sight, by setting the list window's cursor offset (which only the status list sets, to -5, -5, as it
is made) far off the picture, and puts it back when the game draws its own icons again or the plugin
unloads. It says which status the game's cursor is on, for the addon to draw its own highlight.

If the functions are not found (another client version, or something else has changed them), the
plugin says so in the chat and the addon draws its bar over the game as it does without the plugin.

## For the addon

The plugin keeps one block in its own memory, `BuffShared` in `src/buffhook.h`. The addon finds it in
`buffhook.dll` by its first 16 bytes (`BUFFHOOK-SHARED` and a 0), and is `addons/buff/hook.lua`.

Written by the plugin:

| Field | |
|---|---|
| `Hooked` | 1 while the game's two functions are in the plugin's hands |
| `Frame` | counts the frames presented |
| `DrawnFrame` | the `Frame` the game last drew its status icons in |
| `OriginX`, `OriginY` | where it put the first of them then, in pixels of its picture |
| `Width`, `Height` | the size of that picture, which may differ from the window's |
| `Cursor`, `CursorStatus` | the item the game's cursor is on, and its status (`0xFFFF` for none) |

Written by the addon, each frame the bar is to take the icons' place, whether it holds anything or
not: `SubmitFrame` (the `Frame` it was written in), `Count`, up to 48 `Textures` (Direct3D textures'
addresses) and up to 1024 `Quads`. A quad is a rectangle of one of the textures: its corners in the
game's pixels from where the game puts its first icon, the same corners in the texture, and a colour
as `0xAARRGGBB`; a quad whose texture is `0xFFFFFFFF` is its colour alone. The plugin holds a reference to each texture while it draws from it.

## Building

`./build.sh` builds `build/buffhook.dll` on Linux with clang-cl and lld-link, as namehook's does:
it needs the Ashita v4 plugin SDK and the Microsoft C runtime and Windows SDK for x86, under
`.toolchain` (see the script). `tests/run.sh` builds and runs the checks under wine: the game's two
functions are found by their patterns, and a function taken over runs the plugin's, can still run
its own, and is as it was once given back.

## License

MIT, as the rest of this repository: see `LICENSE.md`.
