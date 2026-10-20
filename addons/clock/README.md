# clock — Winxi Info Panel (experimental 0.11)

`clock` is now a configurable info panel. Keep loading it as `clock`; `/clock` opens
**Info Panel Settings**. It uses the same native HUD slot, menu layering and visibility rules as
before, so the game's clock must remain enabled and `hidecompass` must be unloaded.

**Prefer the chat-owned panel?** [Chatbox](../chatbox/README.md#optional-info-panel) now has an
optional Info Panel that keeps rendering when action menus hide the native clock. Unload `clock`
before enabling it with `/chatbox panel on`. The legacy addon remains available, with its settings
untouched; shared panel code is now in `addons/libs/winxi/infopanel` (Winxi 21).

## Settings Tabs

`/clock` opens five focused tabs; every section within them can be collapsed:

| Tab | Controls |
| --- | --- |
| **General** | Replacement on/off, compass visibility, native-hook status, panel/legacy mode |
| **Layout** | Panel size, padding, chat attachment/custom position, offsets, separator styling |
| **Data** | Left/Middle/Right slot formats, field pickers, alignment, width weights, EXP-rate reset; legacy line editor when panel mode is off |
| **Text** | Font, size and colour |
| **Icons** | Icon artwork, scale, offsets and panel placement; native weather controls only in legacy mode |

Frame and shadow settings remain in the shared Winxi theme. Changing tabs does not reset settings.

## Info Panel

**Enable Info Panel** is on by default. Turn it off to return to the original single-line clock;
your saved legacy format is retained, not overwritten by the panel presets.

- **Attach Above Chat**: follow the upper of two stacked chatboxes (the primary for side-by-side
  boxes). Horizontal/Vertical Offset move the whole panel relative to that anchor. Without fresh
  chat geometry it uses the native clock area. Off, Position X/Y specify the panel's top-left.
- **Width**: fixed pixels, or 0 to match the attached chat's width (640 without chat geometry).
- **Height**: fixed pixels, or 0 for input-style sizing: the content height plus padding, at least
  the last measured native input height. Oversized content clips rather than resizing a fixed box.
- **Padding**: room around the slot content. Font, Font Size, Text Color and Icon Scale
  remain under Text/Icons. Frame background, border and drop shadow follow the shared Winxi theme.
  Shadow visibility, opacity, blur and offset use the theme's shadow settings; the shadow is captured
  with the panel so it follows the same native HUD layering.

### Left, Middle and Right Data Slots

Each slot has its own **Data Format**, **Add Data** picker, **Alignment** (Left, Center, Right),
and **Relative Width**. Widths are weights: `2 / 1 / 1` gives half the panel to Left and a quarter
each to Middle/Right. All three slots remain in place even when empty. Long data stays within
its own slot and cannot overlap another. Text and inline icons are vertically centred.

Use any field in the table below and any literal labels/spaces. For example:

| Slot | Example Format | Alignment |
| --- | --- | --- |
| Left | `{time} | {grid}` | Left |
| Middle | `{dayicon} {day} | {date}` | Center |
| Right | `{level} | {tnl} | {rate}` | Right |

Data fields for time, day, date, grid, zone name, moon, weather and experience can go in any slot.
Choose **Zone Name** in Add Data or type `{zone}` (for example, `{zone} | {grid}`). Experience
packet tracking is active whenever any panel slot uses an experience field. `/clock exp reset`
resets the rate. Empty fields still remove their preceding divider.

### Panel Separators

**Slot Separators** toggles the two boundaries. Choose **Fine**, **Beveled** or **Ornament** for
theme-coloured vertical artwork, with an adjustable top/bottom inset. A literal `|` inside a slot
format becomes the same styled divider, not a font glyph. No automatic wrapping is done.

### Panel Icons

Choose **Hidden**, **Native**, **Left**, **Middle** or **Right** independently for day/weather.
Slot placement supports Before/After Data and independent X/Y pixel offsets. For exact ordering,
insert `{dayicon}` or `{weathericon}` in a slot; the token overrides automatic placement.
Icons follow Icon Set and fall back to the bundled `gems` artwork if that set has no picture.
Native leaves the game's icon outside the panel; Hidden suppresses it. A manually inserted token
still draws even if automatic placement is Hidden or Native. The weather icon in the panel is one
symbol, as the legacy inline weather field was; native double-weather icons are kept in Native mode.
Weather Offset, Show All Weather and native replacement-icon positioning remain legacy-mode controls.

**Deployment:** install the whole updated `addons/clock` directory (including `panel.lua` and
`panel_settings.lua`), then `/addon reload clock`. No additional DLL rebuild is needed for panel
layout/settings; attaching above the upper chatbox still requires the previously updated uihook DLL.

## Legacy Single-Line Mode

The game's clock, written out in full on one line in its place: the time, the map grid, the day,
the date and the moon to begin with, as `3:32  (H-9)  Windsday  900/12/30  Moon 42%`; what it shows,
in what order and with what between, is a line you write. The game's own day and weather
icons stay where the game puts them, and the compass above the clock is hidden. Drawn through
**uihook 0.2** where the game draws its clock, so the game's menus and chat log are drawn over it as
they are over the game's own.

With [chatbox](../chatbox/README.md) 0.4 or newer and its matching uihook build, the clock group
follows the **top of the replacement chat log**. Uihook moves the native clock text and
icons together, and reports their translated rectangles to this addon, preserving the
usual spacing above chat as typing opens/closes. With chatbox off or no fresh replacement,
normal native placement returns. While attached, the information line is drawn in a **Winxi-themed
box directly above chat**, aligned to its left edge and matching its current width. With two
stacked chatboxes it sits above the **upper** one and matches that window's width; side-by-side
chatboxes keep the primary log as the anchor. This needs the matching updated uihook DLL. The box follows
chat resizing and typing, and uses the theme's background and border art. It is a thin, single-line
strip with 3-pixel padding, no exterior shadow and no full-window minimum height. Its height follows
the chat input's sizing rule: one line plus padding, at least the last measured native input height.
The complete line, including inline weather icons, is centred horizontally and vertically. Long
lines are left-aligned and clipped to the box rather than widening it. The day/weather icons keep their native
positions and replacement behavior. Without an active replacement chat frame the line retains its
transparent native-clock presentation. Expanded chat also suspends this compact-clock relocation;
the game's normal expanded-chat visibility applies. No clock settings or saved positions are changed.

## Install

1. Build `plugins/uihook/build.sh` and copy `plugins/uihook/build/uihook.dll` to Ashita's `plugins/`.
   Unload addons and the plugin before updating a DLL. Do not load buffhook/partyhook alongside uihook.
2. Copy `addons/clock` and the updated `addons/libs/winxi` (version **21** or newer, including the shared `infopanel` modules) to Ashita's addons.
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

`/clock` opens or closes the tabbed settings. Settings are kept for each character.
The legacy controls are grouped as follows.

**General — Visibility**

- **Replace Game's Clock**: the line in place of the game's text (on to begin with). Off, the game's
  own clock comes back.
- **Hide Compass**: the game's compass and radar are not drawn (on to begin with). The clock and its
  icons are drawn all the same.
- Under them, whether the line is being drawn, or what is in the way.

**Data — Legacy Line**

- **Line**: the line itself, written as you like. Each field is a word in braces, `{time}`, and
  anything else is written as it is, so `{time} | {grid} | {day}` is `3:32 | (H-9) | Windsday`.
- **Shows**: what the line shows now.
- **Add Field**: a list of the fields; the one chosen goes at the end, two spaces on. Hover one for
  what it writes.
- **Add Divider**: ` | `, ` · `, ` - `, ` / ` or two spaces at the end, in place of the spaces there.
  **Default** goes back to `{time}  {grid}  {day}  {date}  {moon}`.
- **EXP Per Hour**, while an experience field is in the line: **Begin Again** forgets what has been
  counted for `{rate}`, and how much has been, over how long.

| Field | Writes |
| --- | --- |
| `{time}` | Vana'diel time, as the game writes it: `3:32` |
| `{grid}` | where you are on the zone's map, as the game writes it: `(H-9)`; none where there is no map |
| `{zone}` | current zone name, such as `West Ronfaure`; none while zone memory is unavailable; `Zone <id>` if its name is unavailable |
| `{day}` | `Windsday` (the game's day icon stays to the left of the line) |
| `{date}` | Vana'diel's year, month and day: `900/12/30` |
| `{moon}` | `Moon 42%` |
| `{weather}` | the weather by name: `Rain`; none under a clear sky |
| `{dayicon}` | day's picture at this position in an info-panel slot |
| `{weathericon}` | the Icon Set's picture for the weather, in the line in place of above the clock (the game's own is hidden); where the set has none, the game's stays above |
| `{level}` | `Lv75` |
| `{exp}` | experience and what the level takes, `12,345/30,000`; in limit mode, limit points to the next merit point, `LP 4,000/10,000` |
| `{tnl}` | `TNL 17,655`; in limit mode `TNM 6,000`; none with no level to go to |
| `{rate}` | experience gained in the last hour, `4,200 EXP/hr` (since counting began, if sooner, and over at least a minute); in limit mode `LP/hr` |

A field with nothing to write takes the divider before it away with it (the first in the line, the
one after it), so `{time} | {grid} | {day}` is `3:32 | Windsday` where there is no map. A word in
braces that is no field is written as it is. Experience is counted only while one of `{level}`,
`{exp}`, `{tnl}` and `{rate}` is in the line.

**Text Tab**

- **Font**: one of `C:\Windows\Fonts`, or the theme's (to begin with).
- **Font Size**: in pixels, up to 48; 0 for the theme's size (to begin with). The line keeps its left
  edge and middle on the game's text, growing to the right and both ways from the middle.
- **Text Color**: the line's colour, and how solid it is (white to begin with).
- The dark edge round the letters is Winxi Theme's Text Outline, set in winxisettings for every addon,
  so the line reads over anything.

When not attached to chatbox, the line has no background. It begins four pixels clear of the day icon as it is drawn (the set's at
its Icon Scale and Offset, or the game's), and never left of where the game writes its text.

**Icons — Icon Appearance / Native Weather**

- **Icon Set**: pictures of your own for the day and weather icons (Game's Icons to begin with).
  See [Icons](#icons).
- **Icon Scale**: how large the set's icons are, 0.5x to 3x (1x to begin with): where the game draws
  its own, against the game's icon, grown about its middle; in the line, against the text's height.
  The game's own icons keep their size.
- **Icon Offset**: moves the set's icons up or down, -10 to 10 pixels (0 to begin with), where the
  game draws its own and in the line.
- **Weather Offset**: moves the weather icon above the clock up or down, -40 to 40 pixels (0 to begin
  with): the game's own icon too, which uihook draws that much higher or lower, in the game's units
  (its day icon sixteen across), and the set's with it.
- **Weather Scale**: how large the weather icon above the clock is, 0.5x to 3x (1x to begin with),
  about its middle: the game's own too, which uihook draws that large, and the set's on top of Icon
  Scale, in the line as well. A double weather's two grow about the first's middle, side by side.
- **Show All Weather**: draws every weather icon in a row from the weather icon's place, fire, ice,
  wind, earth, thunder, water, light and dark, then the clear sky: the set's where it has them, the
  game's own where not, to see them all and where they sit. The weather's own icon gives way to the
  row. Until it is turned off, or the game restarted: it is not saved.

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
- Field definitions live in `addons/libs/winxi/infopanel/fields.lua`, one entry each.
  `addons/clock/fields.lua` is a compatibility import; shared fields can be chosen in either addon's
  picker without automatically changing a character's saved formats.
- Turning the line off or unloading gives back only the clock's slot and the compass's, never the
  buff or party addons'. If the addon stops handing the line over, the game's text is back within
  eight frames.
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
luajit tests/clock_panel_check.lua
```

See [uihook](../../plugins/uihook/README.md) for the hook protocol and native discovery details.
MIT, as the rest of this repository.
