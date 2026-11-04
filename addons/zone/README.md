# Zone

Displays location banners as you travel. Entering a zone shows its name, region and weather along
with the Vana'diel day and time, and entering a named area within it, such as a square, bridge, shop
or guild, shows a smaller banner. Weather changes are announced, an optional location line can
remain on screen, and the named areas of each map can be edited.

## Highlights

- Always know which zone, and which part of it, you are in without opening the map.
- Notice dungeon entrances, town gates and weather changes as they happen.
- Newly found places are marked as discoveries, with a count for each zone.
- Eleven banner styles to suit your interface.

Zone used to be called zoneinfo. See [Coming from zoneinfo](#coming-from-zoneinfo).

## Install

Download the zone package from [DOWNLOADS.md](../../DOWNLOADS.md). Extract the zip into your Ashita
folder (the one that holds `addons`, `plugins` and `config`). Then, in game:

    /addon load zone

Use `/addon reload zone` if it is already loaded.

Zone needs nothing else. `addons/zone/winxi` is its own copy of the parts of winxi it uses. (Winxi is
the shared library behind the winxi addons.) If you use other winxi addons, the look they share, set
with wxi and `/winxi`, is zone's look too.

### Coming from zoneinfo

1. Unload `zoneinfo` before you install zone. Do not run both addons together.
2. While both are unloaded, copy your character settings and boundary changes from
   `config/addons/zoneinfo/` to `config/addons/zone/`.
3. Copy any background images of your own into `addons/zone/assets/backgrounds/`.

The saved boundary file format has not changed.

## Getting started

- `/zone` opens the settings.
- `/zone test` shows the banner for the zone you are in now.
- `/zone test titlecard` shows it once in that style. The styles you can name are `classic`,
  `titlecard`, `pennant`, `kanji`, `reveal`, `window`, `element`, `kind`, `seal`, `atlas` and
  `toast`. This does not change your setting.
- **Preview While Configuring** (Appearance → Preview) keeps a banner on screen while you change
  things.
- `/zone debug on` opens the map browser and boundary editor. See
  [Browse and edit any map](#browse-and-edit-any-map).

**Sub-zone popups are on to begin with. The debug window starts off.**

## Commands

| Command | What it does |
| --- | --- |
| `/zone` | Opens or closes the settings window |
| `/zone test [style]` | Shows the zone, region and weather now; once in a style, if you name one |
| `/zone reload` or `rl` | Reloads this character's display settings and shows the current zone again |
| `/zone subzones [on\|off]` | Turns **Show Sub-zone Popups** on or off, saved. `poc`, its old name, still works |
| `/zone debug [on\|off]` | Opens or closes the debug window: the map browser and editor |
| `/zone approach [field\|town\|dungeon] <0..100>` | Sets the approach distance in yalms for that kind of zone (open country if you name none), saved |
| `/zone sample` or `status` | Prints your position and the map details now |
| `/zone livemap auto` | Removes this zone's saved choice of map |
| `/zone livemap <map-key>` | Uses that map picture in the current zone, saved for that zone |
| `/zone transform <scale> <offset_x> <offset_y>` | For this session only: sets how the current map picture lines up with your position |
| `/zone transform reset` | Clears that and reads the game's own values again |
| `/zone help` | Shows how to type the commands (any word zone does not know does the same) |

## The settings window

The settings window has three tabs: **Appearance**, **Behaviour** and **Visibility**.

- **Appearance** is how the banner looks: the previews, its style for zone entry and for sub-zones,
  sizes, fonts, position, colours and backdrop.
- **Behaviour** is what the banner says and when: each popup's lines, how long it stays, detection,
  entrances and the location line.
- **Visibility** is when it is hidden.

Each setting is a row: its name, a sentence that says what it does, and its control on the right. All
winxi addons lay out their settings this way. There is no Winxi Theme tab: the theme, window and style
settings that zone follows are set in **wxi**.

### Behaviour tab

The Behaviour tab has these sections, in order:

| Section | What is in it |
| --- | --- |
| **Announcements** | Every on and off switch in one place: **Show Banner**, **Show Sub-zone Popups**, **Show Weather Popups**, **Chat Announcements** |
| **Zone Entry Popup** | The lines the zone banner shows |
| **Sub-zone Popup** | The lines the sub-zone banner shows, **Celebrate New Areas**, **Re-announce After** and **Forget Discovered Areas** (which asks first) |
| **Timing** | **Hold**, **Fade In** and **Fade Out**. With Classic Text in use, also **Use Per-Line Timing**, with a sub-section for each line (greyed out until it is on) |
| **Detection** | The three approach distances |
| **Entrances** | Dungeon and town entrances. Each distance is greyed out while its switch is off |
| **Location Line** | The line that always says where you are |

**Show Sub-zone Popups** is on to begin with. `/zone subzones` turns it off and on.

A zone banner never has a sub-zone line. A sub-zone banner shows the place's name as its title, with
no separate label for what kind of place it is. With **Show Zone Name** on, the zone's name is under
it.

**Show Day And Time**, under Zone Entry Popup and under Sub-zone Popup, adds the Vana'diel day and time
when the popup came up, such as `Firesday 14:20`. In Classic Text it is a line of its own. In the
other styles it is the last line. It starts on for zone entry and off for sub-zones. Weather popups
follow the sub-zone setting.

**Re-announce After** (10 seconds to start, 0 to 60) stops a place from being announced again when
you come back to it soon.

- It counts the time you were away, from when you left the place. Only if you were away that long is
  the place announced again.
- Example: step out of the Lion Springs Tavern after a moment, and Lion Square is not named again.
  Stay inside a while, and it is.
- It is the same for every kind of place. So walking along the edge of two streets, or stepping in
  and out of an entrance, does not repeat either name.
- Only the popup and its chat line are held back. The location line always names where you are.
- Changing zone starts afresh. 0 announces every return.

### Detection

A place is announced when you come near its outline. How near depends on the kind of zone. The kinds
are the same as for the Kind Frames style (see [Banner styles](#banner-styles)).

| Setting | To start | For |
| --- | --- | --- |
| **Field Approach Distance** | 50 yalms | Open country, where places are wide and far apart |
| **Town Approach Distance** | 10 yalms | A city, where squares and streets are a few yalms from each other |
| **Dungeon Approach Distance** | 15 yalms | A dungeon or a beastmen stronghold |

Each can be 0 to 100 yalms. 0 announces a place only when you are inside it. Shops and guilds are
always announced only when you are inside, whatever these are set to. These distances, and the map
chosen for each zone, are saved per character. `/zone approach` and `/zone livemap` change the same
settings.

### Dungeon and town entrances

**Announce Dungeon Entrances** (on to start) names a dungeon's entrance as you come to it, as a
sub-zone: `Quicksand Caves Entrance 7`.

- The number is the one the zone's map writes next to the entrance.
- If the map gives the place a name, that is added too: `Outer Horutoto Ruins Entrance 6 (Lilac
  Tower)`.
- **Dungeon Entrance Distance** (20 yalms to start, 5 to 50) is how near you must be. It is shorter
  than open country's distance, so you are told about the entrance and not the hills round it.
- An entrance is only announced when you are within 15 yalms of its height. So a path above or below
  it does not count.
- Inside a place, the entrance is named. When you step away, the place is named again.

There are 184 dungeon entrances from open country and cities, in 55 zones.

- They come from the Phoenix server's zone lines (the points where you change zone into a dungeon).
  Lines into the same dungeon within 30 yalms of each other count as one entrance.
- 123 have their map's number. For the others, either the map has no number there (King Ranperre's
  Tomb, Ghelsba Outpost, Davoi and most of the original dungeons have a label and an arrow instead),
  or the map picture is too rough to read one (Cape Teriggan, Eastern Altepa Desert and most [S] maps).
- Passages from one dungeon to another are not included.
- Entrances are drawn in blue in the map browser. You cannot edit them there.

**Announce Town Entrances** (on to start) names a town as you come up to its gates from the field or
from a dungeon: `Southern San d'Oria Entrance`, or `Norg Entrance` in Sea Serpent Grotto.

- **Town Entrance Distance** (40 yalms to start, 5 to 100) is longer than a dungeon's, so you are told
  about the town before you reach the gate.
- There are 38, from the same zone lines, into the cities and Nashmau. A town's lines within 60 yalms
  of each other count as one.
- Jeuno's three ways in from Batallia Downs, Rolanberry Fields and Sauromugue Champaign are left out,
  because Artisan Bridge, Market Bridge and Harbor Bridge already name them. Qufim Island's is kept.
- Towns have no map number.

### Weather popup

**Show Weather Popups** (on to start) shows a popup when the weather changes while you are in a zone.
The title is `Weather: Rain`, with the zone under it when **Show Zone Name** is on.

- It uses the sub-zone popup's fonts, sizes and per-line timing.
- It writes a line in the chat log if **Chat Announcements** is on.
- The weather is checked once a second.
- If the weather changes while another banner is up, that banner's weather line is updated. The
  weather popup comes after that banner has gone.
- A change in the first ten seconds after zoning only corrects the banner, because the game can still
  hold the last zone's weather then.
- **Preview Weather Once** shows the popup with the current weather.

### Location line

**Show Location Line** (off to start) keeps a small outlined line on screen. It shows the zone you are
in, and the sub-zone after it when you are in one: `West Ronfaure - Knightwell`.

- Drag it into place, or type its **Position** (its top-left corner on the screen).
- **Lock Position** then fixes it there, and lets clicks pass through it to the game.
- **Text Size** is 10 to 40 pixels.
- It follows the banner's hiding rules.
- It names the sub-zone the same way the popups do, and it works with **Show Sub-zone Popups** off.

**Line Style** is either:

- **Plain**: just the words; or
- **Breadcrumb**: a dark tag with a picture for the kind of zone (hills, towers or an arch), then
  region › zone › sub-zone. The sub-zone is in gold, and slides in when it changes. Under them, in
  smaller text: the weather's crystal (two for double weather) and name, the moon (such as `Waxing
  Gibbous 62%`, worked out as in the winchat info panel's calendar) and the Vana'diel day and time,
  checked once a second.

### Per-line timing

Turn on **Use Per-Line Timing** (Behaviour → Timing; offered only while Classic Text is in use) to set
**Start Delay**, **Hold**, **Fade In** and **Fade Out** for each line on its own. The lines are the
zone banner's region, title and weather lines, and the sub-zone banner's title, zone and weather
lines. With it off, the shared timing settings are used.

- Fade-in is part of the hold time.
- Start delay counts from when the popup appears.
- A popup lasts until its last line that is on has finished. Hidden lines do not make it last longer.
- Lines that have finished, or have not started yet, keep their space, so other text does not jump.
- Timing is read when a popup starts. Changes apply to the next popup.

### Discovery

**Celebrate New Areas** (Behaviour → Sub-zone Popup, on to start) is drawn instead of the sub-zone
style the first time this character comes to a place.

- A ring bursts behind NEW AREA DISCOVERED and the place's name.
- Under them are the zone, a dot for each of its places (the ones found are lit, and the new one
  pulses), and the count (`4 / 7`; with more than twenty places, only the count).
- The places found are saved with the character's settings, by map and place, whether this setting is
  on or off.
- Entrances are not counted, and a preview finds nothing.
- **Forget Discovered Areas** makes every place new again.

### Visibility tab

The Visibility tab is the same as in other winxi addons:

- **Fade In And Out**: off, a banner appears and disappears at once instead of fading.
- Rules for hiding the banner: while the map or the chat log is open, while loading, during events,
  and while the game's interface is hidden.

## Appearance

The **Appearance** tab has a section for each part. It shows only the sections for the styles in use:

- **Preview**: the preview buttons. It comes first.
- **Banner Style**: the style and opacity.
- **Pennant** and **Kanji Watermark**: only when that style is chosen.
- **Classic Text**: the **Text Renderer** (how the text is drawn) and the display style.
- **Text**: the sizes and fonts for the styles in use, and the colours.
- **Position**.
- **Backdrop**.
- **Flag And Background Image**: Classic Text only. It starts collapsed.

### Banner styles

**Appearance → Banner Style** chooses how the zone banner (**Zone Entry Style**) and the sub-zone
banner (**Sub-zone Style**) look. Weather popups use the sub-zone style.

| Style | What it looks like |
| --- | --- |
| **Classic Text** | Plain outlined text. See [Classic Text](#classic-text) |
| **Title Card** | The region in spaced capital letters, two lines growing out from a diamond, and the name settling from wide letter spacing to normal. The Vana'diel day, time and weather are under it |
| **Pennant** | A banner drops from the top of the screen in the nation's colours (taken from its flag; slate and silver for other regions). The flag is at its head and the name runs down it in capitals, as large as fits. The region, name, day and weather are written beside it, at the banner position. **Pennant Width**, **Pennant Length** and **Largest Letter Size** set its size |
| **Kanji Watermark** | The zone's name from the Japanese game, huge and faint, beside the English name, or across behind it with **Vertical Text** off. See below |
| **Letter Reveal** | The name appears a letter at a time, each dropping in out of a blur (faint copies on each side close in on it). Then the region between two short lines, and the day and weather under it |
| **Classic Window** | The banner in the game's own blue menu window with its silver edge. It opens from a line, and the menu's pointer nods at the name |
| **Elemental Weather** | The name over a glowing band in the colour of the weather's element. When the weather has no element (clear, sunshine, clouds, fog), or is not shown, the band takes the day's colour. One crystal for single weather and two for double, beside the weather in capitals, and the day in its element's colour. A weather popup shows its crystal under the title |
| **Kind Frames** | A look for each kind of zone. A city's name is on a framed plaque. Open country's is over a horizon line. A dungeon's is carved in stone in capitals, lit as if by a torch, and flickers in. The stone keeps its own colour, whatever the text colour |
| **Nation Seal** | The nation's flag as a round wax seal that stamps down beside the name, a little too far and then back, in the nation's colours (the Pennant's). The region is above the name in the seal's gold, and the day and weather under it. A region without a flag has a crystal on a slate seal |
| **Atlas Cartouche** | The name written on a parchment ribbon that unrolls from its middle, with notched ends. Beside it is a round window onto the zone's own map. For a sub-zone it shows the area round the place, with its outline in gold. For a zone it shows the area round you, with you as a blue dot. Without a map picture, there is only the ribbon. The day and weather are under the ribbon |
| **Edge Toast** | A notched tag slides in from the left edge of the screen (the right, if the banner is aligned right) at the banner's height. It shows a pin, ENTERING and the zone in small capitals, and the name. Under it, fading after two seconds, are LEAVING and the place you just left: the shop you stepped out of, or the zone you came from. A weather popup says WEATHER. Its name is two thirds of **Style Title Size** |

More about the styles:

- The kinds of zone in **Kind Frames** are the same as the vis addon uses. A zone of unknown kind
  counts as open country.
- The map in **Atlas Cartouche** is the map you are on, from the game's files (through pivot, which
  lets replacement game files be used), the same as in the map browser.
- **Kanji Watermark**: the line above the name has the region's Japanese name too. The font is the
  **Japanese Font** you choose. If you choose none, it is the first one found of IPA Mincho (which
  comes with Wine's Japanese fonts), Yu Mincho and MS Mincho. With none of them, there is no
  watermark. The addon cannot turn a character on its side, so when the name is written top to bottom,
  the long vowel mark ー is drawn as a vertical stroke, and small kana move to the top right of their
  square, as in Japanese vertical writing. Names with Latin letters, digits, brackets or a hyphen (the
  [S] zones, Abyssea, Mine Shaft #2716) are written across.
- All styles except Classic Text are drawn the normal way Ashita addons draw (ImGui), under every winxi
  window, whichever **Text Renderer** is chosen.
- **Style Title Size** and **Style Detail Size** set the text size for all of them, in the zone or
  sub-zone title and detail fonts (the theme's font when those are Default).
- They follow the banner's position, alignment, hold, fades and opacity, and **Show Region**, **Show
  Weather**, **Show Zone Name** and **Show Day And Time**. They do not use per-line timing.
- Each style's entrance plays over the first second or two.
- `/zone test` with a style name shows the zone once in that style without changing the setting. See
  [Getting started](#getting-started).

### Classic Text

**Classic Text** offers:

- **Display Style**:
  - **Floating Text** (to start): a large outlined title, a smaller region above it, and context or
    weather below if you want them. It has no background and does not catch clicks.
  - **Themed Panel**: the same text on winxi's background, with its border, padding and shadow if
    the theme has one. The shared theme settings, or this addon's own, work as normal.
- Separate fonts and pixel sizes for the zone and sub-zone title and detail lines (**Zone Title
  Font**, **Zone Detail Font**, **Sub-zone Title Font**, **Sub-zone Detail Font**, and their sizes).
  Choose Default or an installed `.ttf` file from `C:\Windows\Fonts`. Fonts are loaded once and kept.
  If a font cannot be loaded, Default is used.
- **Line Spacing**, and the theme's or your own title and detail colours, are shared.
- The outline is the Winxi Theme's **Text Outline**. No separate GDI engine is needed.
- **Text Alignment**: left, center or right. With **Centered On Screen** on, X is counted from the
  middle of the screen and Y from the top. Otherwise X and Y are screen pixels. The alignment also
  sets which point of the banner sits at that position.

### Backdrop

**Appearance → Backdrop** puts a soft dark shadow behind the banner, so it stands out from a bright
scene.

| Setting | To start | What it does |
| --- | --- | --- |
| **Show Backdrop** | On | Turns the shadow on |
| **Backdrop Opacity** | 0.5 | How dark it is in the middle |
| **Backdrop Softness** | 32 px | How far it fades out round the words |

The backdrop is behind every style, and behind Classic Text's Floating Text. Themed Panel has its
panel instead, and GDI text has none. A style tells the backdrop where its words are as it draws them,
so the backdrop follows from the style's second frame.

### Region flags

**Use Region Flags** (Appearance → Flag And Background Image, on to start) shows a nation's flag
behind every banner in that nation's own regions:

| Flag | Regions |
| --- | --- |
| San d'Oria | Kingdom of San d'Oria, Ronfaure, Ronfaure Front |
| Bastok | Republic of Bastok, Gustaberg, Gustaberg Front |
| Windurst | Federation of Windurst, Sarutabaruta, Sarutabaruta Front |
| Jeuno | Grand Duchy of Jeuno |
| Aht Urhgan | West Aht Urhgan, Western Aradjiah |

- Other regions show no flag.
- A flag keeps its shape. It is as large as **Image Size** allows, in the middle of it. It uses
  **Image Offset** and **Image Opacity**.
- Where there is a flag, it is used instead of your background image. Elsewhere your image is shown as
  usual.
- The flags are solid squares. If the text is hard to read over one, lower the opacity or move the
  offset.

### Background image of your own

1. Put a PNG, JPG/JPEG or BMP file in `addons/zone/assets/backgrounds/`.
2. Open **Appearance → Flag And Background Image** and turn on **Show Background Image**.
3. Type the file's name in **Image Filename**, such as `banner.png`. Full paths and subfolders are not
   accepted.
4. Set **Image Size**, **Image Offset** and **Image Opacity**, and check it with the banner preview.

Only the flags above come with the addon. See also
[the backgrounds folder's README](assets/backgrounds/README.md).

- The image stretches to the size you set. Transparent PNGs work well.
- Its left-right position follows the banner's alignment. Its offset is from the banner position.
- The image's size does not change where the text goes.
- The image fades with the banner. It works with floating text, panel text and the experimental GDI
  fonts. With a themed panel, it is drawn over the panel's fill and behind the text.
- The image is loaded when first needed, then kept. Changing the file name loads it again.
  **Reload Background Image** loads an edited file with the same name.
- If the image is missing or cannot be read, only the text is shown. The addon tries again at most
  every five seconds while the banner is visible, and shows an error in Appearance.
- Image settings are saved with the other per-character display settings.

### Experimental GDI fonts

GDI is Windows' own way of drawing text. To try it:

1. Open `/zone`.
2. Choose **Appearance → Classic Text → Text Renderer → GDI Fonts**. It is marked [Experimental] once
   chosen.
3. Use **Preview Zone Once** or **Preview Sub-zone Once**.

The normal renderer, **ImGui (Default)**, stays the default. Choose it to switch back.

- The settings and the editor are still drawn the normal way.
- Sub-zone detection, hiding rules, position and alignment, sizes, colours, outlines and per-line
  timing all still work.
- GDI draws **floating text only** for now. The Themed Panel option is ignored.
- Appearance has separate GDI font lists for the zone and sub-zone titles and details (**Zone Title
  Family** and so on), plus **Bold Titles** and **Bold Details**. The lists show the names of your
  installed Windows fonts, sorted and without repeats, instead of `.ttf` file names. Vertical
  `@Family` fonts are left out.
- If the list of fonts cannot be read, your saved choices are kept and an error is shown.
- If a chosen font is missing when drawing, Arial is used.

The addon includes its own `gdifonts/` Lua files, `gdifonttexture.dll` and their MIT license.
Thorny's MIT license is in `gdifonts/LICENSE`.

**Warning: this uses experimental code outside the game's script engine.** The DLL needs Windows and
Ashita's Direct3D 8 game client. If that code crashes, the addon cannot recover from it, and it cannot
be shown that losing the graphics device is handled. `gdi-diagnostic.txt` records how far start-up and
texture building got, to help find the cause of a crash.

### Defaults, preview and saving

Defaults:

- the banner is centred, at Y=110;
- zone and sub-zone title and detail sizes are 32 and 16;
- the banner holds for 5 seconds, fades in over 0.2 seconds and fades out over 1 second. The fade-in
  is part of the hold, so the whole banner lasts the hold plus the fade-out.

Timing changes apply to the next banner. Position, text style and opacity change at once. When a zone
banner takes priority over others, it lasts its own set time, not a fixed six seconds.

Previews:

- **Preview While Configuring** keeps the last banner on screen while you change how it looks. A
  sample is used before any banner has been shown.
- **Preview Zone Once** runs the zone banner with your timing and chat settings.
- **Preview Sub-zone Once** previews the current sub-zone, or an example name.
- A preview never turns on sub-zone detection or changes the map choice.

Saving:

- Display settings are saved per character under `config/addons/zone/`, apart from boundary changes.
- They are saved when you finish changing a control, close the settings, or unload the addon.
- Approach distances and each zone's chosen map are saved with them.
- The debug switch, hand-set map alignment and editor browsing last for the session only.
- The map editor window follows the chosen winxi theme. The map's coloured outlines keep their own
  colours.

## How places are found

Zone compares your position on the map with the outline of each named place.

- It checks your position every 0.25 seconds while the debug window or detection is on.
- A change must last one second before it counts.
- You stay "in" a place until you are three map pixels past its approach distance, so standing on the
  edge does not flip back and forth.
- Being inside a place wins over being near another one. Otherwise, where approach areas overlap,
  the current place is kept, or the nearest place in range is chosen.
- Beyond the approach distances, the land has no name.

When you leave a place for good (for one second), it is cleared. No made-up name is announced. Coming
back can announce it again.

Some changes are noted quietly, without a popup: loading the addon, turning detection on, changing
zone or floor, editing the outlines of the map you are on, and finding your position again after
losing it.

- Entering a zone does not show a sub-zone name.
- With **Show Sub-zone Popups** on, later moves into named places use a separate sub-zone popup.
- The zone banner keeps priority over waiting sub-zone banners.
- If your position or the map choice is missing, the old place is cleared.
- The ordinary zone, region and weather banners always work on their own.

### City buildings

A building is an **exact** place. It is announced when you step inside its outline, not as you come
near.

- It is noted about a third of a second after you cross the outline (places in open country wait a
  full second).
- Inside a shop that stands in a named square, you are in the shop. Step out, and you are in the
  square again.
- The outlines come from the map pictures. The names are the maps' own labels.

What this cannot know:

- The map shows a building's outer shape, not where its door is or how thick its walls are. The
  outline is the outer wall, so the name appears as you pass through the wall, wherever the door is.
- A building whose inside is a separate zone or an upper floor is announced when you walk over its
  shape.
- Buildings a map labels but does not draw were left out (Mhaura's guild salesrooms and Governor's
  House), or drawn small where the label's line ends (the shops along Lower Jeuno's bridge).
- Cities of the past (the [S] cities) have none.

In the editor, **Exact Boundary (No Approach)** switches any place between the two kinds.

## Browse and edit any map

`/zone debug on` opens the debug window: the map browser and editor. `/zone debug off` closes it.

You **do not need to travel to a zone to edit its maps**. A place's outline is a shape made of corner
points, which the editor calls vertices.

1. Choose a **Zone** from the list, then a **Map / floor / variant**. Choosing either turns off
   **Follow player zone/map**. Turn Follow back on to go back to the map you are on.
2. Tick **Edit vertices**, then choose the **Area** to edit.
3. Drag the numbered **yellow handles** with the left mouse button. The place's outline and the rounded
   approach outline move as you drag. Let go to apply.
4. Click a handle to select a corner. **Insert vertex after selected** adds a corner in the middle of
   the next side. **Remove selected vertex** removes it. An outline can have 3 to 64 corners, and can
   bend inward.
5. Edit **Area name** and **Announce this area**, then click **Apply name / detection**. Places that
   are off, or still have an unchecked draft name, stay silent until you turn them on yourself. Only
   turn on real names, as the game writes them.
6. **Minimum Height** and **Maximum Height** limit the place to a band of height, for a place above or
   below another. Tick a side, type its height or press **My Height** to use the height you are
   standing at, then press **Apply Height Limits**. A side that is not ticked has no limit. Heights are
   the Z value shown in the live position. The place you are in has one yalm of slack, so a jump does
   not take you out of it.
7. Use **New area name → Add Area** for more places. A four-corner shape appears in the middle of the
   map you are viewing. Drag it into place and add corners as needed. Turn a place off if you no
   longer want it announced.
8. **Undo** reverses the last change to the selected place, including corner, name and on/off changes
   (up to 50 changes). **Restore Default** puts back that place's built-in shape, name and on/off
   setting. Places you added have no built-in shape: they go back to their first shape this session,
   or to the saved shape that was loaded.
9. **Save Boundaries** saves all changed places on all maps, not only the map you are looking at. The
   window shows unsaved changes and save errors.

Good to know:

- Browsing does not change which map is used for detection, does not pause detection, and does not
  put your marker on another map.
- Dragging an outline on the map you are actually on pauses announcements until you let go. Then it
  notes where you are without announcing.
- Editing another map does not reset which place you are in.
- Changing the map you are viewing, closing or collapsing the window, or turning off edit mode
  cancels a drag that is not finished.
- Moves that make sides cross or fold onto each other are refused.
- Corners cannot be dragged off the map.

### Map pictures and XICombinedMaps

The browser draws each map from the game's own files. With the XICombinedMaps-2048 map pack installed
through pivot (which lets replacement game files be used), the pictures are the pack's. Without it, they are the game's own. 22 of the 494
maps are extra pictures of a map that only the pack has. Without the pack, they are blank.

### Zoom for exact placement

Use the **Map zoom** slider to enlarge the map from **1x to 6x**. Scrollbars and the mouse wheel move
you round the enlarged map. **Center selected vertex** brings the selected handle into view. **Reset
view** goes back to 1x and clears the scrolling. Zoom lasts for the session only and never changes
saved positions.

- The map, outlines, approach outlines and your marker grow together. Handles keep the same size on
  screen.
- Zoom lets you move a corner by less than one map pixel.
- Changing the zoom cancels a drag that is not finished, so a corner is not moved by accident.
- Zoom makes the map picture bigger. It does not add detail to it.

### Place outline and approach outline

The yellow handles edit the **place's outline**. The approach area is added outside it: the distance
for the zone's kind, **50 yalms** in open country to start.

| Colour | What it marks |
| --- | --- |
| Yellow | Handles (corners) |
| Gray | The place's outline |
| Orange and green | The approach area |
| Purple | Places that are off (drafts) |
| Blue | Entrances |
| Cyan | You, **only on the map you are on** |

```text
/zone approach 45
/zone approach 0
```

The first makes open country's approach area wider. The second makes the outline you drag the exact
edge there. `/zone approach town 8` and `/zone approach dungeon 12` set the others. The distances are
saved per character, and are sliders in the settings.

The distance is a straight line across the ground. It is not walking distance or line of sight. Walls,
cliffs and height-based parts of a place are not taken into account.

When you browse, the alignment of the map picture is read for the **map you are viewing**, not copied
from your zone. If it is not available, you can still edit the outline, but the window says the
approach outline cannot be lined up.

## Saved boundaries

Your changes are saved inside the addon folder, at:

```text
data/boundary_overrides.txt
```

- The file records each map, the place, its name, whether it is announced, its shape, and any height
  limits or change of kind.
- Each map is identified by its zone and its picture, so different versions of a map do not share
  each other's edits.
- The file saved before is kept as `.bak`.
- If you have an old file from the first three-zone test version (v1), it is read in automatically for
  those zones' first test maps. The next time you save, it is changed to the new format (v2), and the
  old file is kept as the backup. Nothing is saved automatically on upgrade.
- Edits that are not saved are lost when you reload or unload. Saved names, shapes and height limits
  are kept.
- The debug switch, browsing and hand-set map alignment last for the session only.
- Share the `.txt` file to have your boundaries added to the built-in set later.
- Saved edits are still experimental.
- If a map picture changes, it counts as a different map. Saved maps that do not match, or are not
  known, are refused. Shapes are never put on the wrong picture without warning.

## Choosing and lining up the map

469 maps have a matching zone and floor. The other 25 are marked **editor only**, unless you line them
up by hand. A match alone does not prove that the map works with the game or lines up. Before it names
a place, zone checks the game's zone, floor and map position. If the floor you are on cannot be found,
it turns sub-zone detection off rather than guess.

Where one floor has more than one map picture, each can be edited on its own.

- The addon picks one automatically: the one from the first test version, or the one with more
  checked names placed on it. It cannot prove which replacement picture matches your game.
- In the zone you are in, use **Use this map for live detection** to try another picture.
  **Automatic live floor** removes your choice. The choice is saved for that zone.
- Just choosing a map in the browser list never changes the map used for detection.

Before you trust a new map's detection:

1. Check the cyan marker at several landmarks far apart.
2. Run `/zone sample` at each one. It records your world position, the map picture's key, its
   alignment, the floor and the map pixels.
3. Fix draft corners and names that are not checked yet, then save.
4. Turn on sub-zone popups (**Show Sub-zone Popups**, once called POC detection). Start outside the
   **wider** approach outline, wait a moment, and walk towards the place. The first checks, or
   turning it on while inside a place, note where you are without announcing.

## Coverage and what is guessed

Every one of the **494 maps across 204 zones** in the XICombinedMaps-2048 pack has its own editable
place data. Different versions and floors are saved apart.

**419 named places** on 82 maps have their shapes, among them 162 buildings in 24 cities and towns
(see [City buildings](#city-buildings)). 409 are announced. The 9 that are off are city moats and
rivers that you cannot walk into. The other maps each have an **unnamed, editor-only draft**. These
never announce made-up sub-zone names. Rename or move them, or add named places, as you check the map.

These shapes are judged from the map pictures. They were **not walked or traced in game**. The map
picture writes Port Bastok's river as "Dalba River"; the name used is the game's, Dalha River.

The pack has no maps for 90 other zones, so those cannot be shown from it. This is not a claim that
every FFXI map or named place is covered.
