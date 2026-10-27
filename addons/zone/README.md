# Zone

An Ashita v4 addon for FFXI that announces where you are. Entering a zone shows a
banner with its name, region, weather and the Vana'diel day and time; walking into a
named part of it (a square, a bridge, a shop, a guild) shows a smaller one, and so does
a change of weather. An always-on location line can say where you are, and every map
has an editor for the areas it announces.

The banner comes in eleven styles: **Classic Text**, **Title Card**, **Pennant**,
**Kanji Watermark** (the Japanese client's name, huge and faint), **Letter Reveal**,
**Classic Window** (the game's own blue window), **Elemental Weather**, **Kind
Frames** (a look for cities, open country and dungeons), **Nation Seal**, **Atlas
Cartouche** (a ribbon and a round inset of the map) and **Edge Toast** (a tag from
the side of the screen), with a soft **Backdrop** behind it so it reads over a
bright scene. The first time you come to an area, **Discovery** celebrates it.

## Install

Extract the release zip into your Ashita folder (the one holding `addons`, `plugins`
and `config`), then in game:

    /addon load zone

Zone needs nothing else. `addons/zone/winxi` is its own copy of the parts of winxi it
uses, the library behind the winxi addons; if you use other winxi addons, the look
they share (set with winxisettings and `/winxi`) is zone's too.

## Using it

- `/zone` opens the settings. **Appearance** is how the banner looks (the previews,
  its style for zone entry and for sub-zones, sizes, fonts, position, colours,
  backdrop); **Behaviour** is what it says and when (each popup's lines, detection,
  entrances, the location line); **Visibility** is how long it stays and when it
  is hidden.
- `/zone test` shows the zone now; `/zone test titlecard` (or `pennant`, `kanji`,
  `reveal`, `window`, `element`, `kind`, `classic`) shows it once in that style.
- **Preview While Configuring** (Appearance → Preview) keeps a banner up while you
  change things.

The rest of this file is the detail: how the areas were made, every setting, the
map editor and the commands.

### Coming from zoneinfo

Zone was called zoneinfo. Unload `zoneinfo` before installing zone, and while both
are unloaded copy your character settings and boundary overrides from
`config/addons/zoneinfo/` to `config/addons/zone/`, and any background images of your
own into `addons/zone/assets/backgrounds/`. The saved boundary file format is
unchanged; do not run both addons together.

## Coverage and what is guessed

All **494 unique zone-map rasters across 204 zones** in the supplied
`XICombinedMaps-2048` pack have independently editable area data.
Duplicate copies of the same raster are represented once; different raster
variants and floors have separate save identities.

The browser draws each map from the game's own files, read by `winxi.mapdat`
the way pivot turns towards its overlays: with XICombinedMaps-2048 installed as
an overlay they are its pictures, and without it the game's own. 22 of the 494
are other pictures of a map that only the pack has; without it they are blank.

The dataset contains **835 polygons**:

- **419 named features** on 82 maps. Every one has been placed by eye on its
  map's artwork, traced from it, placed from the server's own positions, or is
  a player's own edit:
  - 162 are **buildings** in 24 cities and towns (and Count Caffaule's
    Manor, the player's own): shops, guilds, auction
    houses, consulates, manors and rooms. See "City buildings" below.
  - 28 are the player's saved edits, kept exactly, among them Southern San
    d'Oria laid out street by street (2026-10-24).
  - 27 in 11 other cities were redrawn after Southern San d'Oria: each street,
    square, bridge and gate covers the whole of the walkable place it names,
    end to end, not a mark beside its label. Gingerberry Grove (Windurst
    Waters south) is new. See `research/boundary_authoring_style.md`.
  - 128 were drawn on the feature the map names: the square, bridge, pond or
    stretch of river its label or leader line points at.
  - 55 on past-era and Abyssea maps take the present-day map's shape, where the
    two maps' artwork was compared and found to be the same layout.
  - 11 are copied between two rasters that are the same picture (Windurst
    Waters North, Aht Urhgan Whitegate), so the one the client uses has them.
  - 7 are unchanged: the four original POC shapes, Lake Mechieume, and two
    (Colkhab's Hive, Hurkan's Roost) whose first placement already sat on
    the feature.
  - 1, **Tenshodo H.Q.** under Lower Jeuno, is placed from the Phoenix
    server's positions of its doors, merchants and coffer: the map draws only
    the streets above it. It is a building announced only below street level
    (a minimum height of 1, the street being at about 0 and the H.Q. at 4).
  - 409 are announced. The 9 that are off are city moats and rivers that
    cannot be walked into.
- **416 unnamed editor-only drafts**, one for each raster without reviewed
  names. These do not announce invented sub-zone names. Rename/reposition them
  or add named areas as you review the map.

Ten of the named features were not in the label review and were added from the
maps: eight outposts (named for their region, as the player named Ronfaure
Outpost), Giddeus's second spring and the Metalworks' second cannonry.

These shapes are judged from the map artwork, **not walked or terrain-traced in
game**. See [`research/boundary_authoring_style.md`](https://github.com/Wincasts/win-xi/blob/main/addons/zone/research/boundary_authoring_style.md)
for how the player's edits were read and applied. The map art writes Port
Bastok's river as "Dalba River"; the name used is the game's, Dalha River.

The pack does not include maps for 90 other resource-registry zones. Those
cannot be displayed from this pack; this is not a claim of complete FFXI map or
named-sub-region coverage.

**Sub-zone popups are enabled by default; debugging starts OFF.** Use
`/zone` to adjust sub-zone popup settings. The POC command is retained
for compatibility.

## City buildings

A building is an **exact** area: it is announced when you step inside its
outline, not on approach, and is taken about a third of a second after you
cross (open-country features wait a full second). Inside a shop that stands in
a named square you are in the shop; step out and you are in the square again.

The outlines come from the map artwork. Most buildings are painted a darker
colour than the street, and `tools/trace_zoneinfo_buildings.py` follows that
paint out to the building's wall line. Where the artwork only outlines a
building, its polygon was drawn by hand on the outline. Names are the maps'
own labels. The source is `research/building_seeds.json`; add a building there
(a box round it, or a polygon) and run:

```sh
python3 tools/trace_zoneinfo_buildings.py references/XICombinedMaps-2048 --preview /tmp/buildings
python3 tools/build_zoneinfo_maps.py references/XICombinedMaps-2048 --defaults-only
```

`--preview` writes each map with its buildings drawn on it, to check by eye.

What this cannot know: the map shows a building's footprint, not where its
door is or how thick its walls are. The outline is the outer wall, so the name
appears as you pass through it, wherever the door is. A building whose inside
is a separate zone or an upper floor is announced when you walk over its
footprint. Buildings a map labels but does not draw were left out (Mhaura's
guild salesrooms and Governor's House) or drawn small where the label's line
ends (the shops along Lower Jeuno's bridge). Past-era cities have none. In the editor, **Exact Boundary (No
Approach)** switches any area between the two kinds.

## Deploy and open

From a terminal, if needed:

```sh
./deploy.sh push zone
```

In Ashita:

```text
/addon load zone
/zone debug on
```

Use `/addon reload zone` if already loaded. This update includes about 41 MB
of new preview assets; deploy the entire addon, not just the Lua entrypoint.

## Display settings (winxi)

```text
/zone
/zone test
/zone reload
```

The presentation is inspired by `references/Zonename`, but uses the shared
**winxi** ImGui renderer/theme instead of a separate GDI font engine or font DLL.
The `/zone test` command shows the current zone immediately;
`config` / `settings` opens or closes the settings window, and `reload` / `rl`
reloads character settings and shows the current zone again.

The settings window has three tabs: **Appearance**, **Behaviour** and
**Visibility**. **Appearance** begins with **Preview** (the preview buttons). **Behaviour** is, in order: **Announcements** (Show Banner, Show Sub-zone Popups, Show
Weather Popups, Chat Announcements: every on and off in one place), **Zone
Entry Popup** and **Sub-zone Popup** (the lines each shows, and Re-announce
After), **Detection** (the three approach distances), **Entrances** (dungeon and
town, each distance greyed while its switch is off) and **Location Line**.
**Visibility** has **Timing** and **Hide Banner** (winxi's game-UI hiding
rules). **Appearance** holds how the banner looks: its style and opacity, text,
position and backdrop.
There is no Winxi Theme tab: the theme, window and style settings zone follows
are set in **winxisettings**. Zone-entry popups never include a sub-zone line.
Sub-zone popups show the area's name as the title, without a separate category
label, and the zone's name under it with **Show Zone Name**.
**Show Sub-zone Popups** is on by default; `/zone subzones` turns it off and on.

**Show Day And Time**, under Zone Entry Popup and under Sub-zone Popup, adds the
Vana'diel day and time the popup came up at, such as `Firesday 14:20`: a line
of its own in Classic Text, the last line in the other styles. It starts on for
zone entry and off for sub-zones; weather popups follow the sub-zone's.

How near a feature is announced, from 0 to 100 yalms from its outline, depends
on the kind of zone it is in (the kinds of Kind Frames, below): **Field Approach
Distance** for open country (50 to start), where features are wide and far
apart; **Town Approach Distance** (10) in a city, where squares and streets lie
a few yalms from each other; **Dungeon Approach Distance** (15) in a dungeon or
a beastmen stronghold. Shops and guilds are exact whatever these are. They are
under Sub-zone Popup, saved per character as is the map chosen for live
detection in each zone; `/zone approach` and `/zone livemap` change the same
settings.

**Re-announce After** (10 seconds to start, 0 to 60) keeps an area you come
back to from being announced again unless you were away from it that long:
step out of the Lion Springs Tavern after a moment and Lion Square is not
named again; stay inside a while and it is. It counts time away, from when you
left the area. It is the same for every kind of area, so walking along the edge
of two streets or stepping in and out of an entrance does not repeat either.
Only the popup and its chat line are held back: the location line always names
where you are. Zoning starts afresh, and 0 announces every return.

### Dungeon and town entrances

**Announce Dungeon Entrances** (on to start) names a dungeon's entrance as you
come to it, as a sub-zone: `Quicksand Caves Entrance 7`. The number is the one
the zone's map writes beside it, and a name the map gives the place is added:
`Outer Horutoto Ruins Entrance 6 (Lilac Tower)`. **Entrance Distance** (20
yalms to start, 5 to 50) is how near: closer in than open country's features,
so it is the entrance you are told of and not the hills round it. An entrance is
only announced within 15 yalms of its height, so a path above or below it is
not taken for it; inside a feature, the entrance is named, and stepping away
names the feature again.

There are 184 entrances into dungeons from open country and cities in 55 zones,
from the Phoenix server's zone lines (where each way into a dungeon is). Lines
into the same dungeon within 30 yalms of each other are one entrance. 123 have
their map's number. The others' maps mark none there (King Ranperre's Tomb,
Ghelsba Outpost, Davoi and most of the original dungeons have a label and an
arrow, not a number), or the map's picture is too coarse to read one (Cape
Teriggan, Eastern Altepa Desert and most [S] maps). Dungeon-to-dungeon passages
are not included. The entrances are drawn in blue in the map browser and are
not edited there; `tools/build_zone_entrances.py` makes them, with the numbers
from `research/dungeon_entrances.json`.

**Announce Town Entrances** (on to start) names a town as you come up to its
gates from the field or from a dungeon: `Southern San d'Oria Entrance`,
`Norg Entrance` in Sea Serpent Grotto. **Town Entrance Distance** (40 yalms to
start, 5 to 100) is wider than a dungeon's, to be told of the town before you
reach the gate. There are 38, from the same zone lines, into the cities and
Nashmau; a town's lines within 60 yalms of each other are one. Jeuno's three
ways in from Batallia Downs, Rolanberry Fields and Sauromugue Champaign are left
out, since Artisan Bridge, Market Bridge and Harbor Bridge already name them;
Qufim Island's is kept. Towns carry no map number.

### Weather popup

**Show Weather Popups** (on by default) shows a popup when the weather changes
while you are in a zone: `Weather: Rain` as the title, with the zone under it
when **Show Zone Name** is on. It uses the sub-zone popup's fonts, sizes and
per-line timing, and writes a line to the chat log if **Chat Announcements** is
on. The weather is read once a second. A change while another banner is up
updates that banner's weather line and the popup follows once it has gone. A
change in the ten seconds after zoning only corrects the banner, since the
client can still hold the last zone's weather then. **Preview Weather Once**
shows the popup with the current weather.

### Location line

**Show Location Line** (off by default) keeps a small outlined line on screen
with the zone you are in, and the sub-zone after it when you are in one:
`West Ronfaure - Knightwell`. Drag it into place, or type its **Position**;
**Lock Position** then fixes it there and lets clicks pass through it. **Text
Size** is 10 to 40 pixels. It follows the banner's hiding rules. Naming the
sub-zone uses the same detection as the popups, and works with **Show Sub-zone
Popups** off.

**Line Style** is **Plain**, the words alone, or **Breadcrumb**: a dark chip with
a picture of the kind of zone (hills, towers or an arch), then region › zone ›
sub-zone, the sub-zone in gold and sliding in as it changes; under them, smaller,
the weather's crystal (two for double weather) and name, the moon (`Waxing
Gibbous 62%`, as the info panel's calendar works it out) and the Vana'diel day
and time, read once a second.

Enable **Use Per-Line Timing** for independent start delay, hold, fade-in and
fade-out controls for zone region/title/weather and sub-zone title/zone-context/
weather. Otherwise the shared timing controls apply. Fade-in is part of the
hold interval; start delay is measured from popup creation. Each popup lasts
until its last enabled line expires. Hidden lines do not extend its lifetime,
and expired/delayed lines keep their layout space so other text does not jump.
Timing is captured when a popup starts; changes apply to the next popup.

**Appearance** has a section for each part, and shows only those for the styles
in use: **Banner Style**, **Pennant** and **Kanji Watermark** (when chosen),
**Classic Text** (renderer and display style), **Text** (the sizes and fonts
for the styles in use, and the colours), **Position**, **Backdrop** and **Flag
And Background Image** (Classic Text only; it starts collapsed). **Use
Per-Line Timing**, under Timing, is offered only while Classic Text is in use.
Classic Text offers:

- **Floating Text** (default): large outlined title, smaller region above and
  optional context/weather below; no background and no interception of clicks.
- **Themed Panel**: the same text with winxi background, border, padding and
  optional shadow. Shared-theme or addon-specific theme controls work normally.
- Independent zone-entry and sub-zone title/detail font selectors and pixel
  sizes. Choose Default or an installed `.ttf` file from `C:\\Windows\\Fonts`.
  Font choices are cached, with Default used when a font cannot be loaded.
  Line spacing and theme or title/detail colors are shared; the outline is Winxi Theme's Text Outline.
  No separate GDI engine is required.
- Left/center/right alignment. With **Centered On Screen** enabled, X is an
  offset from screen center and Y is measured from the top; otherwise X/Y are
  absolute screen pixels. Alignment also anchors the whole banner at that point.

### Banner styles

**Appearance → Banner Style** chooses how the zone-entry popup (**Zone Entry
Style**) and the sub-zone popup (**Sub-zone Style**) look. Weather popups take
the sub-zone style. **Classic Text** is the banner described above; the others
are drawn with ImGui under every winxi window, whichever Text Renderer is chosen:

- **Title Card**: the region in spaced capitals, two rules growing out from a
  diamond, and the name settling from wide letter spacing to its own, with the
  Vana'diel day, time and weather under it.
- **Pennant**: a banner drops from the top of the screen in the nation's
  colours (from its flag; slate and silver for other regions), the flag at its
  head and the name in capitals down it, as large as fits. The region, name,
  day and weather are written beside it, at the banner position. **Pennant
  Width**, **Pennant Length** and **Largest Letter Size** size it.
- **Kanji Watermark**: the zone's name from the Japanese client, huge and faint,
  beside the English name or (with **Vertical Text** off) across behind it.
  The line above the name has the region's Japanese name too. The names are in
  `data/zone_names_ja.lua`, made by `tools/build_zone_ja.py` from Boussole's
  zone table, which is read out of the client's own strings. The font is the
  **Japanese Font** chosen, or the first of IPA Mincho (which comes with Wine's
  Japanese fonts), Yu Mincho and MS Mincho; with none of them there is no
  watermark. ImGui cannot turn a glyph, so written top to bottom the long vowel
  mark ー is drawn as its vertical stroke and small kana move to the top right of
  their square, as Japanese vertical type has them. Names with Latin letters,
  digits, brackets or a hyphen (the [S] zones, Abyssea, Mine Shaft #2716) are
  written across.
- **Letter Reveal**: the name a letter at a time, each dropping in out of a
  blur (faint copies either side closing on it, since ImGui has no blur), then
  the region between two short rules and the day and weather under it.
- **Classic Window**: the banner in the game's own blue menu window with its
  silver edge, opening from a line, the menu's pointer nodding at the name.
- **Elemental Weather**: the name over a glowing band in the colour of the
  weather's element, or of the day's when the weather has none (clear,
  sunshine, clouds, fog) or is not shown; one crystal for single weather and
  two for double beside the weather in capitals, and the day in its element's
  colour. A weather popup shows its crystal under the title.
- **Kind Frames**: a look for each kind of zone. A city's name on a framed
  plaque, open country's over a horizon line, a dungeon's carved in stone in
  capitals, lit as by a torch and flickering in. The kinds are vis's
  (winxi's `zonekinds` set, which vis reads too, made by `tools/build_zone_kinds.py`
  from the Phoenix server's zone data); a zone of no known kind is open country.
  The stone's colour is its own whatever the text colour.
- **Nation Seal**: the nation's flag as a round wax seal that stamps down beside
  the name, overshooting a little, in the nation's colours (the Pennant's); the
  region above the name in the seal's gold and the day and weather under it. A
  region without a flag has a crystal on a slate seal.
- **Atlas Cartouche**: the name inked on a parchment ribbon that unrolls from its
  middle, its tails notched, and beside it a round inset of the zone's own map:
  for a sub-zone the part round the area with its outline in gold, for a zone the
  part round you, and you a blue dot. The picture is the map you are on, from the
  game's files through pivot as the browser has it; without one there is the
  ribbon alone. The day and weather go under the ribbon.
- **Edge Toast**: a notched tag slides in from the left edge of the screen (the
  right, with the banner aligned right) at the banner's height: a pin, ENTERING
  and the zone in small capitals, and the name. Under it, fading after two
  seconds, LEAVING and the place just left: the shop you stepped out of, or the
  zone you came from. A weather popup says WEATHER. Its name is two thirds of
  Style Title Size.

**Discovery** (Behaviour → Sub-zone Popup → **Celebrate New Areas**, on to start)
is drawn in place of the sub-zone style the first time this character comes to an
area: a ring bursts behind NEW AREA DISCOVERED and the name, and under them the
zone, a pip for each of its areas with those found lit and the new one pulsing,
and the count (`4 / 7`; with more than twenty areas, the count alone). The areas
found are saved with the character's settings, by map and area, whether or not
it is on; entrances are not counted, and a preview finds nothing. **Forget
Discovered Areas** makes every area new again.

**Appearance → Backdrop** puts a soft dark shadow behind the banner so it stands
out from a bright scene (**Show Backdrop**, on to start): **Backdrop Opacity**
(0.5 to start) is how dark it is in the middle and **Backdrop Softness** (32 px)
how far it fades out round the words. It is behind every style and Classic
Text's Floating Text; Themed Panel has its panel instead, and GDI text has none.
A style says where its words lay as it draws them, so the backdrop follows from
its second frame.

**Style Title Size** and **Style Detail Size** size them all, in the zone or
sub-zone title and detail fonts (the theme's font when those are Default).
They follow the
banner's position, alignment, hold, fades and opacity, and **Show Region**,
**Show Weather**, **Show Zone Name** and **Show Day And Time**; per-line
timing is not used. Each
entrance plays over the first second or two. `/zone test titlecard`, `pennant`,
`kanji`, `reveal`, `window`, `element`, `kind` or `classic` shows the zone once in that style without changing the
setting.

### Region flags

**Use Region Flags** (Appearance → Background Image, on by default) shows a
nation's flag behind every banner in that nation's own regions:

| Flag | Regions |
| --- | --- |
| San d'Oria | Kingdom of San d'Oria, Ronfaure, Ronfaure Front |
| Bastok | Republic of Bastok, Gustaberg, Gustaberg Front |
| Windurst | Federation of Windurst, Sarutabaruta, Sarutabaruta Front |
| Jeuno | Grand Duchy of Jeuno |
| Aht Urhgan | West Aht Urhgan, Western Aradjiah |

Other regions show no flag. The table is `data/region_flags.lua`: a region ID
and the name of a PNG in `assets/backgrounds/flags/`. A flag keeps its
proportions, as large as **Image Size** allows and in the middle of it, and uses
**Image Offset** and **Image Opacity**. Where there is a flag it takes the place
of the background image below; elsewhere that image is shown as before. The
flags are opaque squares, so lower the opacity or move the offset if the text
is hard to read over one. The PNGs were made from the `.webp` files in
`assets/flags/`, which the client cannot load.

### Optional background image

Place a PNG, JPG/JPEG or BMP in `addons/zone/assets/backgrounds/` (or the
same folder in the deployed addon). Open **Appearance → Flag And Background Image**,
enable **Show Background Image** and enter its filename, such as `banner.png`.
Absolute paths and subdirectories are not accepted. Only the flags above are bundled.

Set **Image Size**, **Image Offset** and **Image Opacity** and use the banner
preview. The image stretches to the specified size; transparent PNGs work well.
Its horizontal anchor follows banner alignment, and its offset is relative to
the banner position. Image dimensions do not change text layout. The image fades
with the banner and works with ImGui floating/panel text and experimental GDI.
With a themed panel it is drawn above the panel fill and behind the text.

The image is loaded lazily and cached; replacing the filename refreshes it.
**Reload Background Image** refreshes an edited file with the same name. Missing
or unreadable images fall back to text-only, retry at most every five seconds
while visible, and report an error in Appearance. Image settings save with the
other per-character display settings. Native texture loading, transparency,
layering and device-reset behavior require in-game validation.

Defaults are centered, Y=110, zone and sub-zone title/detail sizes 32/16, a
5-second hold, 0.2-second fade-in and 1-second fade-out. Fade-in occurs within the hold; the
full lifetime is hold plus fade-out. Timing changes apply to the next banner;
position, text style and opacity can be adjusted live. Zone-entry priority uses
that banner's configured lifetime instead of a fixed six-second display.

Enable **Preview While Configuring** to keep the last banner visible while
adjusting its appearance (a sample is used before any banner has been shown).
**Preview Zone Once** runs the zone display with configured timing and chat
behavior. **Preview Sub-zone Once** previews the current sub-zone or an example
name. Preview never enables area detection or changes map selection.

Display settings are saved by Ashita's per-character `settings` library under
`config/addons/zone/`, separately from polygon overrides. Display changes
save on completed interaction/config close/unload. Approach distances and each
zone's live map are saved with them. The debug toggle, manual transforms and
editor browsing remain session-only. The map editor window also
follows the selected winxi theme; map overlays keep their diagnostic colors.

Shared `addons/libs/winxi/` modules must be installed alongside the addon.
Visual placement, font scaling and fading still need confirmation in Ashita;
offline tests only exercise mocked renderer behavior.

## Experimental GDI banner renderer

Open `/zone`, select **Appearance → Classic Text → Text Renderer → GDI Fonts**
(marked [Experimental] once chosen), then use **Preview Zone Once** or **Preview Sub-zone Once**.
ImGui remains the default; select **ImGui (Default)** to switch back.

This uses Thorny's `gdifonts` full-string textures and Direct3D sprite rendering,
as Zonename did. The banner's text does **not** load or bake ImGui fonts. The
settings/editor UI still uses ImGui. Zone/sub-zone detection, visibility rules,
position/alignment, sizes, colors, outlines and per-line timing are retained.
GDI currently renders **floating text only**; the Themed Panel option is ignored.

Appearance provides separate GDI family dropdowns for zone and sub-zone titles
and details, plus **Bold Titles** and **Bold Details**. Dropdowns list installed
Windows family names, sorted and deduplicated, rather than `.ttf` filenames.
Vertical `@Family` variants are excluded. Enumeration is cached and independent
of the texture DLL. If enumeration fails, saved selections are retained and an
error is shown; missing rendering families fall back to Arial. Each enabled line is rendered as a full-string
texture, cached until its text/font/size/colors/outline change. Fade opacity is
applied by the sprite without rebuilding textures.

The addon includes its own `gdifonts/` Lua files, `gdifonttexture.dll` and MIT
license. It uses a private manager and explicit rendering instead of sharing
`name`'s GDI module or an automatic render tick. The texture-pointer lifetime fix
from `name` is retained. Deploy the **whole zone addon**, not just the Lua
entrypoint, and reload it before testing.

**Experimental native code:** the DLL requires Windows/Ashita's Direct3D 8
client. Lua error handling cannot recover from a native access violation or
prove device-loss compatibility. Offline tests use a mocked renderer; native
font quality, placement and simultaneous use with `name` require in-game
validation. `gdi-diagnostic.txt` records initialization and texture-build
checkpoints to help investigate a native failure; cached frames do not log.

Thorny's MIT license is in [`gdifonts/LICENSE`](gdifonts/LICENSE). The reference
implementation is `references/Zonename`; zone's private library disables
automatic rendering, uses a unique event ID, reports manager/sprite creation
failures and ends sprite rendering before propagating a Lua drawing error.

## Browse and edit any map

You **do not need to travel to a zone to edit its maps**.

1. Choose a **Zone** from the dropdown, then choose a **Map / floor / variant**.
   Selecting either turns off **Follow player zone/map**. Re-enable Follow to
   return to the player's live map.
2. Check **Edit vertices**, then choose the **Area** to edit.
3. Drag numbered **yellow handles** with the left mouse button. The feature
   polygon and rounded approach outline update as you move. Release to apply.
4. Click a handle to select a vertex. **Insert vertex after selected** adds a
   midpoint on the following edge; **Remove selected vertex** removes it.
   Polygons support 3–64 vertices, including concave outlines.
5. Edit **Area name** and **Announce this area**, then click **Apply name /
   detection**. Disabled/unlocalized drafts remain non-announcing until you
   explicitly enable them. Only enable meaningful, localized names.
   **Minimum Height** and **Maximum Height** limit the area to a band of
   elevation, for a place above or below another. Tick a side, type its height
   or press **My Height** to take the Z you are standing at, then **Apply Height
   Limits**. An unticked side is open. Heights are the Z shown as the live
   position. The area you are in keeps one yalm of slack, so a jump does not
   leave it.
6. Use **New area name → Add Area** for additional features. A four-vertex
   polygon appears in the center of the viewed map; drag it into place and add
   vertices as needed. Disable an area if you no longer want it announced.
7. **Undo** reverses the last operation for the selected area, including vertex,
   name and enable changes (up to 50 operations). **Restore Default** restores
   that area's built-in shape/name/enable setting. Custom areas have no built-in
   geography: their reset baseline is their initial session shape or loaded
   saved shape.
8. **Save Boundaries** saves all modified areas across all maps—not just the
   currently viewed map. The window shows unsaved changes and save errors.

Browsing does not change live map selection, pause live detection, or place
the player marker on another map. Dragging a boundary on the actual live map
pauses announcements until release and then seeds membership silently.
Editing another map does not reset live membership. Changing the viewed map,
closing/collapsing the window or disabling edit mode cancels an unfinished drag.
Invalid moves that cross/collapse edges are rejected; vertices are clamped to
512-reference map bounds.

### Zoom for precise vertex placement

Use the **Map zoom** slider to enlarge the canvas from **1x to 6x**. Scrollbars
and the mouse wheel let you navigate the enlarged map. **Center selected
vertex** brings the current handle into view; **Reset view** returns to 1x and
clears scrolling. Zoom is session-only and never changes saved coordinates.

The map, polygons, approach outlines and player marker scale together. Vertex
handles keep a fixed screen size. Dragging converts screen movement back to
512-reference coordinates, including scrolling, so zoom allows finer fractional
pixel adjustments. Changing zoom cancels an unfinished drag rather than moving
its vertex accidentally. Zoom enlarges the map's picture; it does not add
new raster detail.

### Feature boundary versus approach boundary

The yellow handles edit the **feature polygon**. The approach buffer is added
outside it: the zone's kind's distance, **50 yalms** in open country to start. Gray outlines mark the feature; orange/green
outlines show the approach envelope; purple marks disabled drafts. Cyan marks
the player **only on the live map**.

```text
/zone approach 45
/zone approach 0
```

The first widens open country's buffer; the second makes the draggable polygon
the exact detection boundary there. `/zone approach town 8` and `/zone approach
dungeon 12` set the others. The distances are saved per character and are
sliders in the settings. It is straight-line horizontal proximity, not walking-path length or
line of sight. Terrain barriers and elevation-specific sub-area volumes are
not modelled.

When browsing, the client transform is read for the **viewed map**, not copied
from the player's zone. If unavailable, you can still edit feature vertices,
but the UI says the approach outline cannot be calibrated.

## Persistence and existing edits

Overrides are saved inside the deployed addon at:

```text
data/boundary_overrides.txt
```

The new **v2 format** records source-raster identity, area ID, name, enable flag
and vertices. After the name come two optional fields: `h:<min>:<max>` for an
area with height limits (`~` for an open side), and `e:1` or `e:0` where an
area's kind (exact or with approach) is not its built-in one. A file with
neither is written as before. It is validated text, never executable Lua. Map identity includes
zone, texture and raster hash, so variants do not inherit each other's edits.
The previous saved file is retained as `.bak`. Saving uses a temporary file and
attempts to restore the old file if installation fails.

Your existing **v1 three-zone POC file imports automatically** into those zones'
primary POC rasters. The next explicit Save migrates to v2 and keeps the original
file as the backup. No automatic save occurs on upgrade.

Unsaved edits are discarded on reload/unload. Saved names, shapes and height
limits persist; the debug toggle, browsing state and manual transform settings
are session-only. Share the `.txt` file to incorporate your authored
boundaries into the default dataset later. Saved edits remain experimental.

Regenerating defaults does not overwrite this local override file. A changed
source raster has a new identity; mismatched/unknown saved maps are rejected
rather than silently applying geometry to the wrong artwork.

## Live map selection and alignment

469 rasters have a matching zone/floor index in the Boussole reference metadata.
The remaining 25 are marked **editor only** unless manually calibrated.
Metadata matches alone do not establish client compatibility or alignment.
Every live transform read still checks the actual client zone ID, floor ID,
nonzero scale and sane offsets before allowing classification.

The already-tested three outdoor POC zones retain their direct floor-zero path.
Other genuinely single-floor zones use their single floor. Other zones with
more than one reference client floor—even if the pack only includes one—use
Boussole's signature-based native floor selection, including its X/Z/Y call
convention. Missing signatures/pointers or an unmapped returned floor disable
classification rather than guessing. This native path needs validation against
your client; offline tests cannot validate native addresses/calling conventions.
The debug browser itself does not call the native floor function.

Multiple artwork variants for one floor are separately editable. Automatic
selection prefers the existing POC or the variant with more located reviewed
names. It cannot prove which replacement artwork matches your client. In the
current player zone, use **Use this map for live detection** to explicitly test
an alternate raster. **Automatic live floor** removes the override. The choice is saved for that zone.
Merely choosing a map in the dropdown never sets a live override.

Before trusting any new map's detection:

1. Check the cyan marker at several separated landmarks.
2. Run `/zone sample` at each checkpoint to record world position, raster
   key, client transform, floor and map pixels.
3. Correct draft vertices and unlocalized names, then Save.
4. Enable POC detection, start outside the **expanded** boundary, wait briefly
   and approach the area. Initial samples/enabling inside an area seed silently.

Player position uses `Movement.LocalPosition`: X/Y horizontal, Z elevation.
Standard image conversion in 512-reference coordinates is:

```text
map_x = world_x * abs(scale) / 5 - offset_x
map_y = -world_y * abs(scale) / 5 - offset_y
```

Preview resize does not alter this coordinate space. No arbitrary clamp is
applied to position before testing polygons.

## Commands and detection behavior

| Command | Effect |
| --- | --- |
| `/zone` | Open/close display settings and Appearance tab |
| `/zone test [style]` | Show zone/region/weather now, once in a style if one is named |
| `/zone reload` or `rl` | Reload character display settings and show current zone |
| `/zone subzones [on\|off]` | Show Sub-zone Popups, saved (`poc`, its old name, still works) |
| `/zone debug [on\|off]` | Open/close the debug window: the all-map browser/editor |
| `/zone approach [field\|town\|dungeon] <0..100>` | Approach buffer in yalms for that kind of zone (open country without one), saved |
| `/zone sample` or `status` | Print live coordinate/map report |
| `/zone livemap auto` | Remove this zone's saved live-map choice |
| `/zone livemap <map-key>` | Use a raster in the current zone, saved for that zone |
| `/zone transform <scale> <offset_x> <offset_y>` | Session-only transform for the current live raster |
| `/zone transform reset` | Clear that raster override and retry client metadata |
| `/zone help` | Command syntax |

Polling is every 0.25 seconds while debug or detection is active. A transition
must remain stable for one second. Current membership has three map pixels of
exit hysteresis beyond the approach boundary. Actual feature containment wins
over neighbouring approach buffers; otherwise current membership is retained
in overlaps, or the closest feature within range is chosen. Beyond finite
buffers, terrain remains unlabelled.

Stable exits clear membership without announcing an invented name. Reentry
can announce again. Load, enable, zone/floor changes, geometry edits to the live
map and position recovery seed silently. Zone entry does not show a sub-zone name;
with **Show Sub-zone Popups** enabled, later stable transitions into named areas
use a separate sub-zone popup. Zone entry retains priority over queued area
banners. Missing position/map selection clears stale area state. Ordinary
zone/region/weather banners remain available independently.

## Files, generation and tests

The release zip leaves out `research/`, the `.webp` flags the PNGs were made from and
the data no code loads (`data/king_ranperres_tomb_*.lua`, `data/map_subregions.lua`):
they are in the repository, for making the data again.

- `data/all_maps.lua`: generated all-raster identities and polygons.
- `research/boundary_refinements.json`: canonical player examples/visual drafts.
- `data/boundary_refinements.lua`: generated raster-specific refinement layer.
- `map_catalog.lua`: groups zones/floors/variants and preserves POC defaults.
- `data/poc_areas.lua`: original seven POC shapes.
- `data/region_flags.lua`: which flag each nation's regions show.
- `data/zone_names_ja.lua`: each zone's Japanese name, made by
  `tools/build_zone_ja.py` from `references/boussole/data/zones.lua`.
- `banner_styles.lua`: every style but Classic Text.
- winxi's `zonekinds`, `entrances` and `regions` sets (the chosen server's data): each zone's kind
  for Kind Frames (vis reads it too), its entrances, and each region's zones, made by
  `tools/build_zone_kinds.py`, `build_zone_entrances.py` and `build_zone_regions.py`.
- `research/building_seeds.json`: where each city building is, for the tracer.
- `presentation.lua`, `banner_layout.lua`: winxi display settings, text layout
  and timed fades, independent of geometry/editor persistence.
- `map_browser.lua`, `debug_view.lua`: independent browsing, maps and editing.
- `boundary_editor.lua`: validation, undo, names/flags and v1/v2 persistence.
- `map_position.lua`, `area_tracking.lua`, `area_geometry.lua`: live mapping and
  membership logic.
- Exported map previews in `assets/maps/` are obsolete and no longer bundled.
  The browser reads map textures directly from the game's DAT files.
- `research/map_subregions.md`: reviewed-name provenance and research limits.
- `research/performance_audit.md`: optimization findings, offline measurements
  and remaining native/client validation needs.

Rebuild all draft defaults/previews (requires Pillow):

```sh
python3 tools/build_zoneinfo_maps.py references/XICombinedMaps-2048
# Or refresh defaults only, keeping already prepared previews:
python3 tools/build_zoneinfo_maps.py references/XICombinedMaps-2048 --defaults-only
```

The previews retain supplied community artwork/labels and attribution. No
additional ownership or licensing claim is made here.

Focused offline checks, also included in `tests/run.sh`:

```sh
luajit tests/zone_math_check.lua
luajit tests/zone_banner_check.lua
luajit tests/zone_editor_check.lua
luajit tests/zone_catalog_check.lua
luajit tests/zone_geometry_regression_check.lua
luajit tests/harness.lua zone tests/zone_fixture.lua tests/zone_check.lua
luajit tests/harness.lua zone-presentation tests/zone_fixture.lua tests/zone_presentation_ui_check.lua
luajit tests/harness.lua zone-subzone tests/zone_fixture.lua tests/zone_subzone_check.lua
luajit tests/harness.lua zone-gdi tests/zone_fixture.lua tests/zone_gdi_check.lua
luajit tests/harness.lua zone-styles tests/zoneinfo_fixture.lua tests/zoneinfo_styles_check.lua
luajit tests/harness.lua zone-background tests/zone_background_fixture.lua tests/zone_background_check.lua
luajit tests/zone_gdi_families_check.lua
luajit tests/zone_height_check.lua
luajit tests/zone_exact_check.lua
luajit tests/harness.lua zone-features tests/zone_background_fixture.lua tests/zone_features_check.lua
luajit tests/harness.lua zone-editor tests/zone_fixture.lua tests/zone_editor_ui_check.lua
luajit tests/harness.lua zone-browser tests/zone_fixture.lua tests/zone_browser_ui_check.lua
luajit tests/harness.lua zone-zoom tests/zone_fixture.lua tests/zone_zoom_ui_check.lua
luajit tests/harness.lua zone-performance tests/zone_fixture.lua tests/zone_performance_ui_check.lua
luajit tools/benchmark_zone.lua
python3 -m unittest discover -s tools -p 'test_*.py'
```

Synthetic tests cover coverage accounting, geometry, editing, dropdowns,
map/floor isolation, persistence/migration, mocked floor-selection behavior,
fade timing, text visibility, settings reloads and winxi renderer cleanup.
They do **not** establish real-client native compatibility, map alignment,
physical terrain boundaries or visual appearance.
