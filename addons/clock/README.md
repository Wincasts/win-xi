# clock — experimental 0.7

The game's clock, written out in full on one line in its place: the time, the map grid, the day,
the date and the moon to begin with, as `3:32  (H-9)  Windsday  900/12/30  Moon 42%`; what it shows,
in what order and with what between, is a line you write. The game's own day and weather
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
- **Icon Set**: pictures of your own for the day and weather icons (Game's Icons to begin with).
  See [Icons](#icons).
- **Icon Scale**: how large the set's icons are, 0.5x to 3x (1x to begin with): where the game draws
  its own, against the game's icon, grown about its middle; in the line, against the text's height.
  The game's own icons keep their size.

- **Icon Offset**: moves the set's icons up or down, -10 to 10 pixels (0 to begin with), where the
  game draws its own and in the line.

Under **Line**, the line itself, written as you like: each field is a word in braces, `{time}`, and
anything else is written as it is, so `{time} | {grid} | {day}` is `3:32 | (H-9) | Windsday`. **Add
Field** puts a field at the end, two spaces on; **Add Divider** puts ` | `, ` · `, ` - `, ` / ` or two
spaces there in place of the spaces at the end; **Default** goes back to
`{time}  {grid}  {day}  {date}  {moon}`. Under it, what the line shows now. Hover a field's button for
what it writes.

| Field | Writes |
| --- | --- |
| `{time}` | Vana'diel time, as the game writes it: `3:32` |
| `{grid}` | where you are on the zone's map, as the game writes it: `(H-9)`; none where there is no map |
| `{day}` | `Windsday` (the game's day icon stays to the left of the line) |
| `{date}` | Vana'diel's year, month and day: `900/12/30` |
| `{moon}` | `Moon 42%` |
| `{weather}` | the weather by name: `Rain`; none under a clear sky |
| `{weathericon}` | the Icon Set's picture for the weather, in the line in place of above the clock (the game's own is hidden); where the set has none, the game's stays above |
| `{level}` | `Lv75` |
| `{exp}` | experience and what the level takes, `12,345/30,000`; in limit mode, limit points to the next merit point, `LP 4,000/10,000` |
| `{tnl}` | `TNL 17,655`; in limit mode `TNM 6,000`; none with no level to go to |
| `{rate}` | experience gained in the last hour, `4,200 EXP/hr` (since counting began, if sooner, and over at least a minute); in limit mode `LP/hr` |

A field with nothing to write takes the divider before it away with it (the first in the line, the
one after it), so `{time} | {grid} | {day}` is `3:32 | Windsday` where there is no map. A word in
braces that is no field is written as it is. Experience is counted only while one of `{level}`,
`{exp}`, `{tnl}` and `{rate}` is in the line; with one there, **Begin Again** forgets what has been
counted for `{rate}`.

The line begins four pixels clear of the day icon as it is drawn (the set's at its Icon Scale and
Offset, or the game's), and never left of where the game writes its text.

The line is the theme's font and text colour, with winxi's dark edge round it and no background. The
Winxi Theme tab sets those. Settings are kept for each character.

## Icons

The game draws the day's icon to the left of the clock, and above it the weather's when there is
weather: elemental weather only, none for a clear sky, sunshine, clouds or fog, and two side by side
for double weather. An icon set puts pictures of your own in their place, as buff's status icon
sets do: where the set has a picture for today or the weather, it is drawn exactly where and as
large as the game's icon would be, and the game's is not drawn; where it has none, the game's own
icon, from its DATs, is drawn as ever.

A set is a folder of `addons\clock\icons`, holding any of `days\firesday.png` to `days\darksday.png`
and `weather\fire.png`, `ice`, `wind`, `earth`, `thunder`, `water`, `light` and `dark`
([icons/README.txt](icons/README.txt)). Weather is by element: rain and squalls are water, dust and
sand storms earth, auroras and stellar glare light, and so on. A folder added while the game runs is
in the list the next time it is opened.

A set can also have `weather\clear.png` (for no weather and sunshine), `clouds` and `fog`: skies the
game draws no icon for. These go where its weather icon would be, 68 of its units above the day
icon and as large; once the game has drawn a weather icon, exactly where it drew it.

**gems** comes with the addon: the game's marbled day circles, in their colours and at their size,
cut as gemstones, and weather icons after the game's own (a fireball, an ice crystal, a whirlwind, an earth
block, a bolt, a drop, a glow and a dark swirl), with a sun for a clear sky. Each is 32 pixels, twice
the game's 16. `tools/generate_clock_icons.py` makes them.

## Commands

- `/clock`: the settings.
- `/clock on`, `/clock off`: Replace Game's Clock.
- `/clock status`: whether the line is drawn in the game's clock's place, and whether the compass is
  hidden, or what is in the way.
- `/clock exp reset`: EXP Per Hour begins again from now.

## Experience

The level and experience are the game's, read from memory. Gains are counted from the server's
messages (packet 0x02D, messages 8 and 253 for experience and an experience chain, 371 and 372 for
limit points and a limit chain, the player's own), as Phoenix sends them from
`src/map/utils/charutils.cpp`: memory's experience cannot be compared across a level up and does
not move while limit points are earned. A merit point is 10,000 limit points. Experience from a
scroll, which the server reports in the item's own message, is not counted in the rate.

## How it works

uihook draws the line when the game draws its clock. Of the game's clock, only its text gives way:
the game still writes it, unseen, and uihook measures where, so the line goes exactly there at any
resolution or menu scale. The day icon to its left and the weather icon above it (two for double
weather) are the game's own, drawn after the text as ever, unless the icon set has a picture for one:
uihook then measures the game's icon unseen as it does the text, and the picture goes there. The map
grid is the game's own `(H-9)`.

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
