# clock — experimental 0.3

The game's clock, written out in full on one line in its place: the time, the map grid, the day,
the date and the moon to begin with, as `3:32  (H-9)  Windsday  900/12/30  Moon 42%`, and what is
shown, and in what order, is yours to choose. The game's own day and weather
icons stay where the game puts them, and the compass above the clock is hidden. Drawn through
**uihook 0.2** where the game draws its clock, so the game's menus and chat log are drawn over it as
they are over the game's own.

## Install

1. Build `plugins/uihook/build.sh` and copy `plugins/uihook/build/uihook.dll` to Ashita's `plugins/`.
   Unload addons and the plugin before updating a DLL. Do not load buffhook/partyhook alongside uihook.
2. Copy `addons/clock` and the updated `addons/libs/winxi` (version **5** or newer) to Ashita's addons.
   The clock also uses Ashita's supplied `common`, `imgui`, `settings`, and `ffxi.time` libraries.
3. In game:

   ```text
   /addon unload hidecompass
   /load uihook
   /addon load clock
   ```

**Unload hidecompass first.** It hides the object the game draws both its compass and its clock from,
so the game never gets as far as its clock and there is nothing to draw in place of. This addon's own
Hide Compass does the compass's part. Keep the clock on in the game's config too.

## Settings

`/clock` opens or closes the settings. Under **Clock**:

- **Replace Game's Clock**: the one line in place of the game's text (on to begin with). Off, the
  game's own clock comes back.
- **Text Scale**: how large the line is, from 0.5x to 3x the theme's font size (1x to begin with).
  The line keeps its left edge and middle on the game's text, growing to the right and both ways
  from the middle; the dark edge round the letters thickens from 1.75x.
- **Hide Compass**: the game's compass and radar are not drawn (on to begin with). The clock and its
  icons are drawn all the same.

Under **Line**, each field the line can show, ticked if shown, in the order they are written from left
to right; **Up** and **Down** move one along. Hover a field for what it writes.

| Field | Writes | To begin with |
| --- | --- | --- |
| Time | Vana'diel time, as the game writes it: `3:32` | shown |
| Map Grid | where you are on the zone's map, as the game writes it: `(H-9)`; none where there is no map | shown |
| Day | `Windsday` (the game's day icon stays to the left of the line) | shown |
| Date | Vana'diel's year, month and day: `900/12/30` | shown |
| Moon | `Moon 42%` | shown |
| Weather | the weather by name: `Rain`; none under a clear sky (the game's icon is above the clock either way) | hidden |

Fields are two spaces apart, as the game spaces its time and grid. A field with nothing to say is
left out, gap and all. With none ticked, the game's text is hidden and nothing written in its place.

The line is the theme's font and text colour, with winxi's dark edge round it and no background. The
Winxi Theme tab sets those. Settings are kept for each character.

## Commands

- `/clock`: the settings.
- `/clock on`, `/clock off`: Replace Game's Clock.
- `/clock status`: whether the line is drawn in the game's clock's place, and whether the compass is
  hidden, or what is in the way.

## How it works

uihook draws the line when the game draws its clock. Of the game's clock, only its text gives way:
the game still writes it, unseen, and uihook measures where, so the line goes exactly there at any
resolution or menu scale. The day icon to its left and the weather icon above it (two for double
weather) are the game's own, drawn after the text as ever. The map grid is the game's own `(H-9)`.

- Nothing is drawn until uihook has seen where the game writes its clock, and then only while the
  game goes on drawing it: with the clock off in the game's config, in a cutscene, or with the
  interface hidden, there is no line either. There is no floating clock of its own.
- One timestamp supplies every field, read four times a second; a change in the settings shows at once.
- The fields are `addons/clock/fields.lua`, one entry each. A field added there (the EXP tracker to
  come) is added to every character's line at the end, as it begins, shown or not.
- Turning the line off or unloading gives back only the clock's slot and the compass's, never the
  buff or party addons'. If the addon stops handing the line over, the game's text is back within
  two frames.
- If uihook cannot find the game's text call it replaces the whole clock, icons and all, as 0.1 did.
  `/uihook hud` says which.

**Not live-validated yet.** Check the clock and radar toggles in the game's config, weather and double
weather, cutscenes, zoning, hiding the interface, resolution and font changes, and reloading the
addon and the plugin.

## Checks

```sh
plugins/uihook/tests/run.sh
luajit tests/nativehud_check.lua
luajit tests/harness.lua clock tests/clock_stand_in.lua tests/clock_check.lua
```

See [uihook](../../plugins/uihook/README.md) for the hook protocol and native discovery details.
MIT, as the rest of this repository.
