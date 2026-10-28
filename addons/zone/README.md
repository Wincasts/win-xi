# Zone

An Ashita v4 addon for FFXI that tells you where you are. When you enter a zone, a
banner shows its name, region, weather and the Vana'diel day and time. When you walk
into a named part of it (a square, a bridge, a shop, a guild), a smaller banner shows.
A change of weather shows one too. An always-on location line can say where you are,
and every map has an editor for the areas it announces.

The banner comes in eleven styles: **Classic Text**, **Title Card**, **Pennant**,
**Kanji Watermark** (the Japanese client's name, huge and faint), **Letter Reveal**,
**Classic Window** (the game's own blue window), **Elemental Weather**, **Kind
Frames** (a look for cities, open country and dungeons), **Nation Seal**, **Atlas
Cartouche** (a ribbon and a round inset of the map) and **Edge Toast** (a tag from
the side of the screen). A soft **Backdrop** sits behind it, so you can read it over a
bright scene. The first time you come to an area, **Discovery** celebrates it.

## Install

Extract the release zip into your Ashita folder (the one holding `addons`, `plugins`
and `config`). Then, in game:

    /addon load zone

Zone needs nothing else. `addons/zone/winxi` is its own copy of the parts of winxi it
uses. Winxi is the library behind the winxi addons. If you use other winxi addons, the
look they share (set with winxisettings and `/winxi`) is zone's look too.

## Using it

- `/zone` opens the settings. **Appearance** is how the banner looks (the previews,
  its style for zone entry and for sub-zones, sizes, fonts, position, colours,
  backdrop). **Behaviour** is what it says and when (each popup's lines, how long
  it stays, detection, entrances, the location line). **Visibility** is when it
  is hidden. Every setting is a row: its name, a sentence saying what it does,
  and its control at the right. Every winxi addon lays them out this way.
- `/zone test` shows the zone now. `/zone test titlecard` (or `pennant`, `kanji`,
  `reveal`, `window`, `element`, `kind`, `classic`) shows it once in that style.
- **Preview While Configuring** (Appearance → Preview) keeps a banner up while you
  change things.

The rest of this file is the detail: how the areas were made, every setting, the
map editor and the commands.

### Coming from zoneinfo

Zone used to be called zoneinfo. Unload `zoneinfo` before you install zone. While
both are unloaded, copy your character settings and boundary overrides from
`config/addons/zoneinfo/` to `config/addons/zone/`. Copy any background images of
your own into `addons/zone/assets/backgrounds/`. The saved boundary file format has
not changed. Do not run both addons together.

## Coverage and what is guessed

All **494 unique zone-map rasters across 204 zones** in the supplied
`XICombinedMaps-2048` pack have their own editable area data. Duplicate copies of
the same raster are stored once. Different raster variants and floors have
separate save identities.

The browser draws each map from the game's own files, read by `winxi.mapdat`
the way pivot turns towards its overlays. With XICombinedMaps-2048 installed as
an overlay, the pictures are its pictures. Without it, they are the game's own. 22
of the 494 are other pictures of a map that only the pack has. Without it, they are
blank.

The dataset contains **835 polygons**:

- **419 named features** on 82 maps. Every one was placed by eye on its map's
  artwork, traced from it, placed from the server's own positions, or is a
  player's own edit:
  - 162 are **buildings** in 24 cities and towns (and Count Caffaule's
    Manor, the player's own): shops, guilds, auction houses, consulates, manors
    and rooms. See "City buildings" below.
  - 28 are the player's saved edits, kept exactly. Among them is Southern San
    d'Oria, laid out street by street (2026-10-24).
  - 27 in 11 other cities were redrawn after Southern San d'Oria. Each street,
    square, bridge and gate covers the whole of the walkable place it names,
    end to end, not just a mark beside its label. Gingerberry Grove (Windurst
    Waters south) is new. See `research/boundary_authoring_style.md`.
  - 128 were drawn on the feature the map names: the square, bridge, pond or
    stretch of river its label or leader line points at.
  - 55 on past-era and Abyssea maps take the present-day map's shape. The two
    maps' artwork was compared and found to be the same layout.
  - 11 are copied between two rasters that are the same picture (Windurst
    Waters North, Aht Urhgan Whitegate), so the one the client uses has them.
  - 7 are unchanged: the four original POC shapes, Lake Mechieume, and two
    (Colkhab's Hive, Hurkan's Roost) whose first placement already sat on
    the feature.
  - 1, **Tenshodo H.Q.** under Lower Jeuno, is placed from the Phoenix
    server's positions of its doors, merchants and coffer. The map draws only
    the streets above it. It is a building announced only below street level
    (a minimum height of 1; the street is at about 0 and the H.Q. at 4).
  - 409 are announced. The 9 that are off are city moats and rivers that you
    cannot walk into.
- **416 unnamed editor-only drafts**, one for each raster without reviewed
  names. These do not announce invented sub-zone names. Rename or move them,
  or add named areas, as you review the map.

Ten of the named features were not in the label review and were added from the
maps: eight outposts (named for their region, as the player named Ronfaure
Outpost), Giddeus's second spring and the Metalworks' second cannonry.

These shapes are judged from the map artwork, **not walked or terrain-traced in
game**. See [`research/boundary_authoring_style.md`](https://github.com/Wincasts/win-xi/blob/main/addons/zone/research/boundary_authoring_style.md)
for how the player's edits were read and applied. The map art writes Port
Bastok's river as "Dalba River"; the name used is the game's, Dalha River.

The pack does not include maps for 90 other resource-registry zones. Those
cannot be shown from this pack. This is not a claim of complete FFXI map or
named-sub-region coverage.

**Sub-zone popups are on by default; debugging starts OFF.** Use `/zone` to
change the sub-zone popup settings. The POC command is kept for compatibility.

## City buildings

A building is an **exact** area. It is announced when you step inside its
outline, not as you approach. It is taken about a third of a second after you
cross (open-country features wait a full second). Inside a shop that stands in
a named square, you are in the shop. Step out, and you are in the square again.

The outlines come from the map artwork. Most buildings are painted a darker
colour than the street, and `tools/trace_zoneinfo_buildings.py` follows that
paint out to the building's wall line. Where the artwork only outlines a
building, its polygon was drawn by hand on the outline. Names are the maps'
own labels. The source is `research/building_seeds.json`. To add a building,
put it there (a box round it, or a polygon) and run:

```sh
python3 tools/trace_zoneinfo_buildings.py references/XICombinedMaps-2048 --preview /tmp/buildings
python3 tools/build_zoneinfo_maps.py references/XICombinedMaps-2048 --defaults-only
```

`--preview` writes each map with its buildings drawn on it, so you can check by eye.

What this cannot know: the map shows a building's footprint, not where its
door is or how thick its walls are. The outline is the outer wall, so the name
appears as you pass through it, wherever the door is. A building whose inside
is a separate zone or an upper floor is announced when you walk over its
footprint. Buildings a map labels but does not draw were left out (Mhaura's
guild salesrooms and Governor's House), or drawn small where the label's line
ends (the shops along Lower Jeuno's bridge). Past-era cities have none. In the
editor, **Exact Boundary (No Approach)** switches any area between the two kinds.

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

Use `/addon reload zone` if it is already loaded. This update includes about 41 MB
of new preview assets. Deploy the whole addon, not just the Lua entrypoint.

## Display settings (winxi)

```text
/zone
/zone test
/zone reload
```

The look is inspired by `references/Zonename`, but it uses the shared **winxi**
ImGui renderer and theme instead of a separate GDI font engine or font DLL.
`/zone test` shows the current zone at once. `config` / `settings` opens or closes
the settings window. `reload` / `rl` reloads character settings and shows the
current zone again.

The settings window has three tabs: **Appearance**, **Behaviour** and
**Visibility**. **Appearance** begins with **Preview** (the preview buttons).
**Behaviour** is, in order: **Announcements** (Show Banner, Show Sub-zone Popups,
Show Weather Popups, Chat Announcements: every on and off in one place), **Zone
Entry Popup** and **Sub-zone Popup** (the lines each shows, Re-announce After, and
Forget Discovered Areas, which asks first), **Timing** (Hold, Fade In and Fade
Out, and with Classic Text in use, Use Per-Line Timing with a sub-section for each
line, greyed until it is on), **Detection** (the three approach distances),
**Entrances** (dungeon and town, each distance greyed while its switch is off)
and **Location Line**. **Visibility** is winxi's: Fade In And Out (off, and a
banner pops instead of fading) and the rules for hiding (while the map or the
chat log is open, while loading, during events, with the game interface hidden).
**Appearance** holds how the banner looks: its style and opacity, text, position
and backdrop.
There is no Winxi Theme tab. The theme, window and style settings zone follows
are set in **winxisettings**. Zone-entry popups never include a sub-zone line.
Sub-zone popups show the area's name as the title, without a separate category
label, and the zone's name under it with **Show Zone Name**.
**Show Sub-zone Popups** is on by default. `/zone subzones` turns it off and on.

**Show Day And Time**, under Zone Entry Popup and under Sub-zone Popup, adds the
Vana'diel day and time the popup came up at, such as `Firesday 14:20`. It is a line
of its own in Classic Text, and the last line in the other styles. It starts on for
zone entry and off for sub-zones. Weather popups follow the sub-zone's setting.

How near a feature is announced, from 0 to 100 yalms from its outline, depends
on the kind of zone it is in (the kinds of Kind Frames, below). **Field Approach
Distance** is for open country (50 to start), where features are wide and far
apart. **Town Approach Distance** (10) is for a city, where squares and streets
lie a few yalms from each other. **Dungeon Approach Distance** (15) is for a
dungeon or a beastmen stronghold. Shops and guilds are exact, whatever these are
set to. They are under Sub-zone Popup, and saved per character, as is the map
chosen for live detection in each zone. `/zone approach` and `/zone livemap`
change the same settings.

**Re-announce After** (10 seconds to start, 0 to 60) stops an area you come back
to from being announced again, unless you were away from it that long. Step out
of the Lion Springs Tavern after a moment and Lion Square is not named again.
Stay inside a while and it is. It counts time away, from when you left the area.
It is the same for every kind of area, so walking along the edge of two streets,
or stepping in and out of an entrance, does not repeat either. Only the popup
and its chat line are held back. The location line always names where you are.
Zoning starts afresh, and 0 announces every return.

### Dungeon and town entrances

**Announce Dungeon Entrances** (on to start) names a dungeon's entrance as you
come to it, as a sub-zone: `Quicksand Caves Entrance 7`. The number is the one
the zone's map writes beside it. If the map gives the place a name, that is added
too: `Outer Horutoto Ruins Entrance 6 (Lilac Tower)`. **Entrance Distance** (20
yalms to start, 5 to 50) is how near you must be. It is closer in than open
country's features, so you are told of the entrance and not the hills round it.
An entrance is only announced within 15 yalms of its height, so a path above or
below it is not taken for it. Inside a feature, the entrance is named, and
stepping away names the feature again.

There are 184 entrances into dungeons from open country and cities in 55 zones.
They come from the Phoenix server's zone lines (where each way into a dungeon
is). Lines into the same dungeon within 30 yalms of each other count as one
entrance. 123 have their map's number. For the others, the map marks no number
there (King Ranperre's Tomb, Ghelsba Outpost, Davoi and most of the original
dungeons have a label and an arrow, not a number), or the map's picture is too
coarse to read one (Cape Teriggan, Eastern Altepa Desert and most [S] maps).
Dungeon-to-dungeon passages are not included. The entrances are drawn in blue in
the map browser and cannot be edited there. `tools/build_zone_entrances.py` makes
them, with the numbers from `research/dungeon_entrances.json`.

**Announce Town Entrances** (on to start) names a town as you come up to its
gates from the field or from a dungeon: `Southern San d'Oria Entrance`, or
`Norg Entrance` in Sea Serpent Grotto. **Town Entrance Distance** (40 yalms to
start, 5 to 100) is wider than a dungeon's, so you are told of the town before
you reach the gate. There are 38, from the same zone lines, into the cities and
Nashmau. A town's lines within 60 yalms of each other count as one. Jeuno's
three ways in from Batallia Downs, Rolanberry Fields and Sauromugue Champaign are
left out, since Artisan Bridge, Market Bridge and Harbor Bridge already name
them. Qufim Island's is kept. Towns carry no map number.

### Weather popup

**Show Weather Popups** (on by default) shows a popup when the weather changes
while you are in a zone: `Weather: Rain` as the title, with the zone under it
when **Show Zone Name** is on. It uses the sub-zone popup's fonts, sizes and
per-line timing. It writes a line to the chat log if **Chat Announcements** is
on. The weather is read once a second. If the weather changes while another
banner is up, that banner's weather line is updated, and the popup follows once
the banner has gone. A change in the ten seconds after zoning only corrects the
banner, since the client can still hold the last zone's weather then. **Preview
Weather Once** shows the popup with the current weather.

### Location line

**Show Location Line** (off by default) keeps a small outlined line on screen
with the zone you are in, and the sub-zone after it when you are in one:
`West Ronfaure - Knightwell`. Drag it into place, or type its **Position**.
**Lock Position** then fixes it there and lets clicks pass through it. **Text
Size** is 10 to 40 pixels. It follows the banner's hiding rules. Naming the
sub-zone uses the same detection as the popups, and works with **Show Sub-zone
Popups** off.

**Line Style** is **Plain**, the words alone, or **Breadcrumb**: a dark chip with
a picture of the kind of zone (hills, towers or an arch), then region › zone ›
sub-zone, with the sub-zone in gold and sliding in as it changes. Under them,
smaller, are the weather's crystal (two for double weather) and name, the moon
(`Waxing Gibbous 62%`, as the info panel's calendar works it out) and the
Vana'diel day and time, read once a second.

Turn on **Use Per-Line Timing** for separate start delay, hold, fade-in and
fade-out controls for the zone region, title and weather lines, and for the
sub-zone title, zone-context and weather lines. Otherwise the shared timing
controls apply. Fade-in is part of the hold time. Start delay is measured from
when the popup is created. Each popup lasts until its last enabled line has
expired. Hidden lines do not make it last longer. Expired and delayed lines keep
their space in the layout, so other text does not jump. Timing is taken when a
popup starts; changes apply to the next popup.

**Appearance** has a section for each part, and shows only those for the styles
in use: **Banner Style**, **Pennant** and **Kanji Watermark** (when chosen),
**Classic Text** (renderer and display style), **Text** (the sizes and fonts
for the styles in use, and the colours), **Position**, **Backdrop** and **Flag
And Background Image** (Classic Text only; it starts collapsed). **Use
Per-Line Timing**, under Behaviour → Timing, is offered only while Classic Text
is in use.
Classic Text offers:

- **Floating Text** (default): a large outlined title, a smaller region above
  it, and optional context or weather below. It has no background and does not
  catch clicks.
- **Themed Panel**: the same text with winxi's background, border, padding and
  optional shadow. The shared theme or addon-specific theme controls work as
  normal.
- Separate font choices and pixel sizes for the zone-entry and sub-zone title
  and detail lines. Choose Default or an installed `.ttf` file from
  `C:\\Windows\\Fonts`. Font choices are cached, and Default is used when a font
  cannot be loaded. Line spacing and the theme or title/detail colors are
  shared. The outline is Winxi Theme's Text Outline. No separate GDI engine is
  needed.
- Left, center or right alignment. With **Centered On Screen** on, X is an
  offset from the screen's center and Y is measured from the top. Otherwise X
  and Y are screen pixels. The alignment also anchors the whole banner at that
  point.

### Banner styles

**Appearance → Banner Style** chooses how the zone-entry popup (**Zone Entry
Style**) and the sub-zone popup (**Sub-zone Style**) look. Weather popups take
the sub-zone style. **Classic Text** is the banner described above. The others
are drawn with ImGui under every winxi window, whichever Text Renderer is chosen:

- **Title Card**: the region in spaced capitals, two rules growing out from a
  diamond, and the name settling from wide letter spacing to its own, with the
  Vana'diel day, time and weather under it.
- **Pennant**: a banner drops from the top of the screen in the nation's
  colours (from its flag; slate and silver for other regions), with the flag at
  its head and the name in capitals down it, as large as fits. The region, name,
  day and weather are written beside it, at the banner position. **Pennant
  Width**, **Pennant Length** and **Largest Letter Size** set its size.
- **Kanji Watermark**: the zone's name from the Japanese client, huge and faint,
  beside the English name or (with **Vertical Text** off) across behind it.
  The line above the name has the region's Japanese name too. The names are in
  `data/zone_names_ja.lua`, made by `tools/build_zone_ja.py` from Boussole's
  zone table, which is read out of the client's own strings. The font is the
  **Japanese Font** you choose, or else the first found of IPA Mincho (which
  comes with Wine's Japanese fonts), Yu Mincho and MS Mincho. With none of them,
  there is no watermark. ImGui cannot turn a glyph, so when written top to
  bottom the long vowel mark ー is drawn as its vertical stroke, and small kana
  move to the top right of their square, as Japanese vertical type has them.
  Names with Latin letters, digits, brackets or a hyphen (the [S] zones,
  Abyssea, Mine Shaft #2716) are written across.
- **Letter Reveal**: the name a letter at a time, each dropping in out of a
  blur (faint copies on either side closing on it, since ImGui has no blur),
  then the region between two short rules, and the day and weather under it.
- **Classic Window**: the banner in the game's own blue menu window with its
  silver edge, opening from a line, with the menu's pointer nodding at the name.
- **Elemental Weather**: the name over a glowing band in the colour of the
  weather's element. When the weather has no element (clear, sunshine, clouds,
  fog), or is not shown, the band takes the day's colour. One crystal is shown
  for single weather and two for double, beside the weather in capitals, and
  the day in its element's colour. A weather popup shows its crystal under the
  title.
- **Kind Frames**: a look for each kind of zone. A city's name is on a framed
  plaque. Open country's is over a horizon line. A dungeon's is carved in stone
  in capitals, lit as if by a torch, and flickers in. The kinds are vis's
  (winxi's `zonekinds` set, which vis reads too, made by `tools/build_zone_kinds.py`
  from the Phoenix server's zone data). A zone of no known kind counts as open
  country. The stone's colour is its own, whatever the text colour.
- **Nation Seal**: the nation's flag as a round wax seal that stamps down beside
  the name, overshooting a little, in the nation's colours (the Pennant's). The
  region is above the name in the seal's gold, and the day and weather are
  under it. A region without a flag has a crystal on a slate seal.
- **Atlas Cartouche**: the name inked on a parchment ribbon that unrolls from its
  middle, with notched tails. Beside it is a round inset of the zone's own map:
  for a sub-zone, the part round the area with its outline in gold; for a zone,
  the part round you, with you as a blue dot. The picture is the map you are on,
  from the game's files through pivot, as the browser has it. Without one, there
  is the ribbon alone. The day and weather go under the ribbon.
- **Edge Toast**: a notched tag slides in from the left edge of the screen (the
  right, with the banner aligned right) at the banner's height. It shows a pin,
  ENTERING and the zone in small capitals, and the name. Under it, fading after
  two seconds, are LEAVING and the place you just left: the shop you stepped out
  of, or the zone you came from. A weather popup says WEATHER. Its name is two
  thirds of Style Title Size.

**Discovery** (Behaviour → Sub-zone Popup → **Celebrate New Areas**, on to start)
is drawn in place of the sub-zone style the first time this character comes to an
area. A ring bursts behind NEW AREA DISCOVERED and the name. Under them are the
zone, a pip for each of its areas (those found are lit and the new one pulses),
and the count (`4 / 7`; with more than twenty areas, the count alone). The areas
found are saved with the character's settings, by map and area, whether or not
it is on. Entrances are not counted, and a preview finds nothing. **Forget
Discovered Areas** makes every area new again.

**Appearance → Backdrop** puts a soft dark shadow behind the banner, so it stands
out from a bright scene (**Show Backdrop**, on to start). **Backdrop Opacity**
(0.5 to start) is how dark it is in the middle. **Backdrop Softness** (32 px) is
how far it fades out round the words. It is behind every style and Classic
Text's Floating Text. Themed Panel has its panel instead, and GDI text has none.
A style says where its words lay as it draws them, so the backdrop follows from
its second frame.

**Style Title Size** and **Style Detail Size** set the size of them all, in the
zone or sub-zone title and detail fonts (the theme's font when those are
Default). They follow the banner's position, alignment, hold, fades and opacity,
and **Show Region**, **Show Weather**, **Show Zone Name** and **Show Day And
Time**. Per-line timing is not used. Each entrance plays over the first second or
two. `/zone test titlecard`, `pennant`, `kanji`, `reveal`, `window`, `element`,
`kind` or `classic` shows the zone once in that style without changing the
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
proportions. It is as large as **Image Size** allows, in the middle of it, and
uses **Image Offset** and **Image Opacity**. Where there is a flag, it takes the
place of the background image below. Elsewhere that image is shown as before.
The flags are opaque squares, so lower the opacity or move the offset if the
text is hard to read over one. The PNGs were made from the `.webp` files in
`assets/flags/`, which the client cannot load.

### Optional background image

Place a PNG, JPG/JPEG or BMP in `addons/zone/assets/backgrounds/` (or the
same folder in the deployed addon). Open **Appearance → Flag And Background Image**,
turn on **Show Background Image** and enter its filename, such as `banner.png`.
Full paths and subfolders are not accepted. Only the flags above come with the addon.

Set **Image Size**, **Image Offset** and **Image Opacity**, and use the banner
preview. The image stretches to the size you set; transparent PNGs work well.
Its horizontal anchor follows the banner's alignment, and its offset is relative
to the banner position. The image's size does not change the text layout. The
image fades with the banner, and works with ImGui floating/panel text and the
experimental GDI renderer. With a themed panel, it is drawn above the panel's
fill and behind the text.

The image is loaded when first needed and then cached. Changing the filename
reloads it. **Reload Background Image** reloads an edited file with the same
name. A missing or unreadable image falls back to text only, retries at most
every five seconds while visible, and reports an error in Appearance. Image
settings save with the other per-character display settings. Native texture
loading, transparency, layering and device-reset behavior still need checking in
game.

Defaults are centered, Y=110, zone and sub-zone title/detail sizes 32/16, a
5-second hold, 0.2-second fade-in and 1-second fade-out. The fade-in happens
within the hold. The full lifetime is hold plus fade-out. Timing changes apply
to the next banner. Position, text style and opacity can be changed live.
Zone-entry priority uses that banner's set lifetime, not a fixed six-second
display.

Turn on **Preview While Configuring** to keep the last banner visible while you
change its appearance (a sample is used before any banner has been shown).
**Preview Zone Once** runs the zone display with your timing and chat settings.
**Preview Sub-zone Once** previews the current sub-zone, or an example name.
Preview never turns on area detection or changes the map selection.

Display settings are saved by Ashita's per-character `settings` library under
`config/addons/zone/`, separately from polygon overrides. Display changes are
saved when you finish changing a control, close the settings, or unload the
addon. Approach distances and each zone's live map are saved with them. The
debug toggle, manual transforms and editor browsing last for the session only.
The map editor window also follows the chosen winxi theme. Map overlays keep
their diagnostic colors.

The shared `addons/libs/winxi/` modules must be installed alongside the addon.
Visual placement, font scaling and fading still need confirming in Ashita.
Offline tests only exercise a mocked renderer.

## Experimental GDI banner renderer

Open `/zone`, choose **Appearance → Classic Text → Text Renderer → GDI Fonts**
(marked [Experimental] once chosen), then use **Preview Zone Once** or **Preview
Sub-zone Once**. ImGui stays the default. Choose **ImGui (Default)** to switch
back.

This uses Thorny's `gdifonts` full-string textures and Direct3D sprite rendering,
as Zonename did. The banner's text does **not** load or bake ImGui fonts. The
settings and editor UI still use ImGui. Zone and sub-zone detection, visibility
rules, position and alignment, sizes, colors, outlines and per-line timing all
still work. GDI currently draws **floating text only**; the Themed Panel option
is ignored.

Appearance has separate GDI family dropdowns for the zone and sub-zone titles
and details, plus **Bold Titles** and **Bold Details**. The dropdowns list
installed Windows family names, sorted with duplicates removed, rather than
`.ttf` filenames. Vertical `@Family` variants are left out. The list is cached
and does not depend on the texture DLL. If the list cannot be read, your saved
choices are kept and an error is shown. A family that is missing for drawing
falls back to Arial. Each enabled line is drawn as a full-string texture, cached
until its text, font, size, colors or outline change. Fade opacity is applied by
the sprite, without rebuilding textures.

The addon includes its own `gdifonts/` Lua files, `gdifonttexture.dll` and MIT
license. It uses a private manager and explicit drawing instead of sharing
`name`'s GDI module or an automatic render tick. The texture-pointer lifetime fix
from `name` is kept. Deploy the **whole zone addon**, not just the Lua
entrypoint, and reload it before testing.

**Experimental native code:** the DLL needs Windows and Ashita's Direct3D 8
client. Lua error handling cannot recover from a native access violation, or
prove that device loss is handled. Offline tests use a mocked renderer. Native
font quality, placement and use at the same time as `name` still need checking
in game. `gdi-diagnostic.txt` records initialization and texture-build
checkpoints, to help look into a native failure. Cached frames do not log.

Thorny's MIT license is in [`gdifonts/LICENSE`](gdifonts/LICENSE). The reference
implementation is `references/Zonename`. Zone's private library turns off
automatic drawing, uses a unique event ID, reports manager and sprite creation
failures, and ends sprite drawing before passing on a Lua drawing error.

## Browse and edit any map

You **do not need to travel to a zone to edit its maps**.

1. Choose a **Zone** from the dropdown, then choose a **Map / floor / variant**.
   Choosing either turns off **Follow player zone/map**. Turn Follow back on to
   return to your live map.
2. Tick **Edit vertices**, then choose the **Area** to edit.
3. Drag the numbered **yellow handles** with the left mouse button. The feature
   polygon and the rounded approach outline update as you move. Release to apply.
4. Click a handle to select a vertex. **Insert vertex after selected** adds a
   midpoint on the next edge. **Remove selected vertex** removes it.
   A polygon can have 3–64 vertices, and may be concave.
5. Edit **Area name** and **Announce this area**, then click **Apply name /
   detection**. Disabled or unlocalized drafts stay silent until you turn them
   on yourself. Only turn on meaningful, localized names.
   **Minimum Height** and **Maximum Height** limit the area to a band of
   height, for a place above or below another. Tick a side, type its height
   or press **My Height** to take the Z you are standing at, then **Apply Height
   Limits**. An unticked side is open. Heights are the Z shown as the live
   position. The area you are in keeps one yalm of slack, so a jump does not
   leave it.
6. Use **New area name → Add Area** for more features. A four-vertex polygon
   appears in the center of the viewed map. Drag it into place and add vertices
   as needed. Turn an area off if you no longer want it announced.
7. **Undo** reverses the last change to the selected area, including vertex,
   name and enable changes (up to 50 changes). **Restore Default** puts back
   that area's built-in shape, name and enable setting. Custom areas have no
   built-in shape: their reset point is their first shape in the session, or
   the saved shape that was loaded.
8. **Save Boundaries** saves all changed areas across all maps, not just the
   map you are looking at. The window shows unsaved changes and save errors.

Browsing does not change the live map selection, pause live detection, or put
the player marker on another map. Dragging a boundary on the actual live map
pauses announcements until you release, and then seeds membership silently.
Editing another map does not reset live membership. Changing the viewed map,
closing or collapsing the window, or turning off edit mode cancels an unfinished
drag. Moves that cross or collapse edges are rejected. Vertices are kept within
the 512-reference map bounds.

### Zoom for precise vertex placement

Use the **Map zoom** slider to enlarge the canvas from **1x to 6x**. Scrollbars
and the mouse wheel move you around the enlarged map. **Center selected
vertex** brings the current handle into view. **Reset view** returns to 1x and
clears the scrolling. Zoom lasts for the session only and never changes saved
coordinates.

The map, polygons, approach outlines and player marker scale together. Vertex
handles keep a fixed size on screen. Dragging converts screen movement back to
512-reference coordinates, including the scrolling, so zoom lets you make finer
fractional pixel changes. Changing the zoom cancels an unfinished drag rather
than moving its vertex by accident. Zoom enlarges the map's picture; it does not
add new raster detail.

### Feature boundary versus approach boundary

The yellow handles edit the **feature polygon**. The approach buffer is added
outside it: the distance for the zone's kind, **50 yalms** in open country to
start. Gray outlines mark the feature. Orange and green outlines show the
approach envelope. Purple marks disabled drafts. Cyan marks the player, **only
on the live map**.

```text
/zone approach 45
/zone approach 0
```

The first widens open country's buffer. The second makes the draggable polygon
the exact detection boundary there. `/zone approach town 8` and `/zone approach
dungeon 12` set the others. The distances are saved per character and are
sliders in the settings. The distance is straight-line horizontal distance, not
walking distance or line of sight. Terrain barriers and height-specific sub-area
volumes are not modelled.

When browsing, the client transform is read for the **viewed map**, not copied
from your zone. If it is not available, you can still edit feature vertices,
but the UI says the approach outline cannot be calibrated.

## Persistence and existing edits

Overrides are saved inside the deployed addon at:

```text
data/boundary_overrides.txt
```

The new **v2 format** records the source raster's identity, the area ID, name,
enable flag and vertices. After the name come two optional fields: `h:<min>:<max>`
for an area with height limits (`~` for an open side), and `e:1` or `e:0` where
an area's kind (exact or with approach) is not its built-in one. A file with
neither is written as before. It is validated text, never executable Lua. Map
identity includes the zone, texture and raster hash, so variants do not inherit
each other's edits. The previous saved file is kept as `.bak`. Saving uses a
temporary file, and tries to restore the old file if installing the new one
fails.

Your existing **v1 three-zone POC file imports automatically** into those zones'
primary POC rasters. The next time you Save, it migrates to v2 and keeps the
original file as the backup. Nothing is saved automatically on upgrade.

Unsaved edits are lost on reload or unload. Saved names, shapes and height
limits are kept. The debug toggle, browsing state and manual transform settings
last for the session only. Share the `.txt` file to have your boundaries added
to the default dataset later. Saved edits are still experimental.

Regenerating the defaults does not overwrite this local override file. A changed
source raster has a new identity. Saved maps that do not match, or are unknown,
are rejected rather than silently applying shapes to the wrong artwork.

## Live map selection and alignment

469 rasters have a matching zone and floor index in the Boussole reference
metadata. The remaining 25 are marked **editor only** unless you calibrate them
by hand. A metadata match alone does not prove the map works with the client or
lines up. Every live transform read still checks the actual client zone ID,
floor ID, nonzero scale and sane offsets before it allows classification.

The three outdoor POC zones already tested keep their direct floor-zero path.
Other zones with only one floor use that floor. Other zones with more than one
reference client floor (even if the pack only includes one) use Boussole's
signature-based native floor selection, including its X/Z/Y call convention.
Missing signatures or pointers, or a returned floor that is not mapped, turn
classification off rather than guessing. This native path needs checking
against your client. Offline tests cannot check native addresses or calling
conventions. The debug browser itself does not call the native floor function.

Where one floor has more than one artwork variant, each can be edited on its
own. Automatic selection prefers the existing POC, or the variant with more
located reviewed names. It cannot prove which replacement artwork matches your
client. In the zone you are in, use **Use this map for live detection** to try
another raster. **Automatic live floor** removes the override. The choice is
saved for that zone. Just choosing a map in the dropdown never sets a live
override.

Before trusting any new map's detection:

1. Check the cyan marker at several landmarks far apart.
2. Run `/zone sample` at each checkpoint to record the world position, raster
   key, client transform, floor and map pixels.
3. Correct draft vertices and unlocalized names, then Save.
4. Turn on POC detection, start outside the **expanded** boundary, wait a
   moment and approach the area. The first samples, or turning it on while
   inside an area, seed silently.

Player position uses `Movement.LocalPosition`: X/Y horizontal, Z elevation.
The standard image conversion in 512-reference coordinates is:

```text
map_x = world_x * abs(scale) / 5 - offset_x
map_y = -world_y * abs(scale) / 5 - offset_y
```

Resizing the preview does not change this coordinate space. No arbitrary clamp is
applied to the position before testing polygons.

## Commands and detection behavior

| Command | Effect |
| --- | --- |
| `/zone` | Open or close the display settings and the Appearance tab |
| `/zone test [style]` | Show the zone, region and weather now, once in a style if one is named |
| `/zone reload` or `rl` | Reload character display settings and show the current zone |
| `/zone subzones [on\|off]` | Show Sub-zone Popups, saved (`poc`, its old name, still works) |
| `/zone debug [on\|off]` | Open or close the debug window: the all-map browser and editor |
| `/zone approach [field\|town\|dungeon] <0..100>` | Approach buffer in yalms for that kind of zone (open country without one), saved |
| `/zone sample` or `status` | Print a live coordinate and map report |
| `/zone livemap auto` | Remove this zone's saved live-map choice |
| `/zone livemap <map-key>` | Use a raster in the current zone, saved for that zone |
| `/zone transform <scale> <offset_x> <offset_y>` | Session-only transform for the current live raster |
| `/zone transform reset` | Clear that raster override and read the client metadata again |
| `/zone help` | Command syntax |

Polling is every 0.25 seconds while debug or detection is active. A transition
must stay stable for one second. Current membership has three map pixels of
exit hysteresis beyond the approach boundary. Being inside a feature wins over
a neighbouring approach buffer. Otherwise, in overlaps, the current membership
is kept, or the closest feature within range is chosen. Beyond the finite
buffers, terrain stays unlabelled.

A stable exit clears membership without announcing an invented name. Coming
back in can announce again. Load, enable, zone and floor changes, geometry edits
to the live map and position recovery all seed silently. Zone entry does not
show a sub-zone name. With **Show Sub-zone Popups** on, later stable transitions
into named areas use a separate sub-zone popup. Zone entry keeps priority over
queued area banners. A missing position or map selection clears stale area
state. The ordinary zone, region and weather banners stay available on their own.

## Files, generation and tests

The release zip leaves out `research/`, the `.webp` flags the PNGs were made from, and
the data no code loads (`data/king_ranperres_tomb_*.lua`, `data/map_subregions.lua`).
They are in the repository, for making the data again.

- `data/all_maps.lua`: generated all-raster identities and polygons.
- `research/boundary_refinements.json`: canonical player examples and visual drafts.
- `data/boundary_refinements.lua`: generated raster-specific refinement layer.
- `map_catalog.lua`: groups zones, floors and variants, and keeps the POC defaults.
- `data/poc_areas.lua`: the original seven POC shapes.
- `data/region_flags.lua`: which flag each nation's regions show.
- `data/zone_names_ja.lua`: each zone's Japanese name, made by
  `tools/build_zone_ja.py` from `references/boussole/data/zones.lua`.
- `banner_styles.lua`: every style but Classic Text.
- winxi's `zonekinds`, `entrances` and `regions` sets (the chosen server's data): each zone's kind
  for Kind Frames (vis reads it too), its entrances, and each region's zones, made by
  `tools/build_zone_kinds.py`, `build_zone_entrances.py` and `build_zone_regions.py`.
- `research/building_seeds.json`: where each city building is, for the tracer.
- `presentation.lua`, `banner_layout.lua`: winxi display settings, text layout
  and timed fades, separate from the geometry and editor persistence.
- `map_browser.lua`, `debug_view.lua`: browsing, maps and editing, on their own.
- `boundary_editor.lua`: validation, undo, names and flags, and v1/v2 persistence.
- `map_position.lua`, `area_tracking.lua`, `area_geometry.lua`: live mapping and
  membership logic.
- The exported map previews in `assets/maps/` are obsolete and no longer bundled.
  The browser reads map textures directly from the game's DAT files.
- `research/map_subregions.md`: where the reviewed names came from, and the
  limits of the research.
- `research/performance_audit.md`: optimization findings, offline measurements
  and what still needs checking against the native client.

Rebuild all draft defaults and previews (needs Pillow):

```sh
python3 tools/build_zoneinfo_maps.py references/XICombinedMaps-2048
# Or refresh defaults only, keeping already prepared previews:
python3 tools/build_zoneinfo_maps.py references/XICombinedMaps-2048 --defaults-only
```

The previews keep the supplied community artwork, labels and attribution. No
further ownership or licensing claim is made here.

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

The synthetic tests cover coverage accounting, geometry, editing, dropdowns,
map and floor isolation, persistence and migration, mocked floor selection,
fade timing, text visibility, settings reloads and winxi renderer cleanup.
They do **not** prove compatibility with the real client, map alignment,
physical terrain boundaries or how it looks.
