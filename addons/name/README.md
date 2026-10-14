# name

Called nametoggle up to 1.5. Its settings were kept under that name: to keep them, copy the folder
`config\addons\nametoggle` to `config\addons\name` before loading it.

Shows and hides the names over characters' heads, by what they are over. A settings window for the
`namehook` plugin, which does the showing and hiding: the plugin has to be loaded.

```
/load namehook
/addon load name
```

- `/name`: opens or closes the settings
This ImGui testing build exposes only the menu command. Text-control verbs,
including show/hide/toggle, custom, watch and GDI, are disabled. Use Filters to
choose which names appear; unload Name to restore the game's names.

## Settings

The preferred baseline is captured in `name_defaults.lua` from the live Win_4458
profile. It uses **corbeli.ttf**, **bold**, maximum/minimum font sizes **28/10**,
**75% check size**, **93% icon size**, **2 px icon spacing**, and **1 px outline**.
Difficulty abbreviations and check details are enabled, mastery stars and words
mode are off. Own Name, Other Players, and Other Pets are hidden; Always Show
Target is on. Appearance/hide preferences are captured too. GDI remains off.
Existing character settings take precedence over this baseline.

Kept for each character. Each is on for names that are shown.

The menus follow Twister's layout: named sections, aligned controls, and visible
`(?)` help marks with wrapped explanations.

Public tabs are **Nameplates → Filters → NM Tracking → Statuses**. Experimental and Appearance are hidden;
GDI is forced off so testers exercise the ImGui renderer.

- **Nameplates:** follows `guis/name.menu`: Name Appearance, Player Icons,
  Mob Nameplates, and Check. Options boxes measure the longest option row and share a width fitted
  to that row plus its help marker and padding. Every `(?)` sits in the same
  right-aligned column. Measurements exclude help and window width, preventing
  auto-size feedback; widths can shrink when content becomes shorter. Font sizes and icon padding use numeric
  inputs; outline thickness uses radio buttons 0–3. Font selection comes first.
  **Mob Nameplates** exposes Show Level / Range, Show Aggro Icons, experimental Mob Letters,
  and Mob Format.
  Target Format and Checked Format controls are hidden. Mob strings are saved per character;
  the baseline is `[aggro] Lv [level]. [name]`. Mob Format applies to ordinary,
  targeted, and checked mobs alike. Legacy target/checked overrides are ignored.
  The general player-name format remains fixed at `[name]`.
- **Filters:** Players, Pets, NPCs And Monsters, Target, and Status, using the
  same bordered sections, content-fitted widths, and aligned help column.

| Setting | Whose names |
|---|---|
| Own Name | Your own |
| Party Members | The others of your party, trusts among them |
| Alliance Members | The other parties of your alliance |
| Other Players | Every other player. A player on the plugin's whitelist is shown all the same: `/namehook whitelist add <name>` |
| My Pet | Your own pet |
| Other Pets | Anyone else's pet, trust or adventuring fellow |
| NPCs | What cannot be fought |
| Monsters | What can be fought, charmed players among them |
| Always Show Target | Your target's name is shown though names like it are hidden. Your own is not: with Own Name off it stays hidden while you have yourself targeted |

Names In View, under them, is how many names the game had to draw last frame, and how many of them
are hidden.

## Custom names

Rendering is always enabled while Name and its compatible plugin are loaded.
In the first tab, Names, configure how the names are drawn in winxi's
outlined text and not by the game: each in the colour the game gives it, with the game's icons before
it. Which names are shown is still set in the Filters tab; only how they look changes. It needs
namehook 1.10 or later.

| Setting | What it does |
|---|---|
| Bold | Makes names and check-detail text heavier. The normal renderer uses simulated bold; experimental GDI uses the family's native bold style. On in the preferred defaults; icons and stars are unchanged |
| Maximum Font Size | The height of a nearby name, 6 to 48 pixels. Names automatically shrink with distance |
| Minimum Font Size | The height of a name at the distance it is no longer drawn at; never more than the maximum |
| Outline Thickness | The dark edge round each name, 0 to 4 pixels; rounded down to whole render-target pixels to keep nearby names thinner. As letters shrink, it becomes thinner and slightly less opaque so distant names stay readable. Nearby names retain the original outline. At 0 the names are written plain |
| Font (experimental) | A font of Windows' own, chosen by its file in `C:\Windows\Fonts`; Default is the font everything else is written in |
| Name Format | How every name but a monster's is written: see [How a name is written](#how-a-name-is-written) |
| Monster Format | How a monster's name is written |
| Targeted Monster Format | How the name of the monster you have targeted is written. Left empty, it is written as other monsters' are |
| Checked Monster Format | How the name of a monster you have checked is written, until it dies or you leave the area. Left empty, checking a monster changes nothing of how its name is set out. For a monster that is both checked and targeted, this one is used |
| Show Icons | The game's icons before a name |
| Icon Size | An icon's side, as a percentage of the height of the names |
| Icon Spacing | The space between a name's icons and the name itself, 0 to 24 pixels |
| Show Check Details | Under the name of a monster you have checked: how hard a fight it is, what it does, and what it links with. See [What a check shows](#what-a-check-shows) |
| Check Size | Scale check-detail text and icons from 50% to 125% of the name size; 75% in the preferred defaults. Applies to either layout |
| Abbreviate Difficulty | On by default: TW, IEP, EP, DC, EM, T, VT and IT alongside aggro/link information. Difficulty alone uses full words; Impossible to Gauge stays ???. Off restores full difficulty names in either layout |
| Check Details In Words | A leading magnifying glass followed by a sentence without aggro/link signs, such as `TW, Sight Aggro, Link: Goblin (Sight)`. There while Show Check Details is on |
| Show Mastery Stars | The three stars over the name of a player with a job mastered |

### Rendering optimizations

Text layout is cached by string and font-size set, including glyph advances and
positions. The Bold switch also invalidates cached advances when its value changes.
Simulated bold adds a shifted copy per visible text glyph, with spacing adjusted to
match. It uses more quads when enabled, but does not increase outline thickness or
modify the shared ImGui font. Select a bold font file directly instead if you prefer
its designed bold face over simulated bold. Each set keeps at most 512 runs; a font/atlas replacement creates new
sets, so stale texture coordinates are not reused. Distance text still updates to
a tenth, but unchanged text does not need decoding and measuring every frame.

If the client lists an entity more than once through different drawing call sites,
only its last wanted entry is laid out each frame. This preserves the final text
selection while avoiding unused quads and repeated size/colour stabilization.
The plugin still draws the resulting geometry at each original call site.

The shared drawing buffer checks capacity per quad instead of reserving 256 slots
for every name, allowing short names to use the last available slots safely.
Font-size rungs are also cached until maximum height changes;
empty format parts avoid run-cache work and check-detail layout uses no temporary
width table.

Letter badges keep their A–Z definitions on the close-up font set. Warm frames only
probe the font for atlas movement; they do not reread all 26 glyphs or serialize the
badge cache key. Font-set replacement invalidates these immutable definitions,
while the stable-frame delay and bounded texture retries remain in place.

Run the Linux synthetic CPU/allocation check with:

```sh
luajit tests/harness.lua name addons/name/name.lua tests/name_performance_check.lua
```

It tests 0, 32, 128 and the plugin maximum of 256 names with letters off/on, checks that warm frames perform no
badge texture readback/upload, and reports time and allocations per frame. These
are mocked addon-side measurements, not in-client GPU timings. Set
`NAME_BENCH_FRAMES` to change the timing sample count (default 500).

The updated plugin caches complete name bounds and skips vertex expansion and draw
submission for names fully outside the viewport. A name with an off-screen anchor
is still drawn if any of its text, icons, stars, outline or details can be visible.
This does not change the ordering or depth passes of visible names.

Inline aggro and magnifying-glass icons, and the check line's sense/link icons,
use approximately 25% less outline opacity than text. Their fill stays unchanged;
player-name icons use the same softened outline, including both halves of two-part
icons. Mastery stars remain unoutlined. Outline Thickness 0 disables all of these
outlines. This per-quad effect requires the
updated plugin as well as `libs/winxi`.

### Retained experimental GDI implementation

GDI code and standalone tests remain for reversible development, but the current
public build hides its tab, disables its commands and forces ImGui in the frame
callback. It is not a selectable testing backend. Native crashes with some font
families remain unresolved; passing stub tests does not establish native safety.
The implementation notes below describe the retained backend, not public controls.

GDI rasterizes plain ASCII glyphs into one cached atlas at the current size rungs.
Each capture surrounds its character with visible sentinels, then crops them away
in Lua, avoiding the reference DLL's unsafe standalone-punctuation cropping path.
The plugin still handles world-depth occlusion, outlines, colours and fading;
distance changes do not rasterize new text. Unchanged frames reuse the prepared
request without allocating another height list, building a key string, or calling
the backend again; failed requests are cached too. Check Size only changes layout
and does not regenerate the atlas. Changing Bold rebuilds the atlas with
the family's native regular/bold style; it does not add simulated strokes to GDI glyphs. The magnifying glass still uses
Ashita's ImGui font in a separate texture slot. This first version deliberately
keeps the plugin's existing outline style rather than baking GDI outlines.

The first frame after enabling GDI or changing the family, bold style, font size,
or render-resolution scale may pause while the atlas is generated.
Unavailable fonts or Lua-level generation errors produce one warning and fall back to
ImGui; change the settings or toggle GDI off and on to retry. Native access violations
cannot be safely caught by that fallback. While building an atlas, the experimental
backend writes `gdi-diagnostic.txt` in the addon folder, recording the last native
operation attempted; cached frames do no diagnostic file I/O. Check spacing,
centering, crowded areas, shrinking, check details and alt-tab in-game before
keeping this backend enabled. GDI rendering itself is not covered by the stub tests.

The vendored GdiFonts library and DLL are from
`references/crispy-chainsaw/gdifonts` (Thorny's MIT-licensed library); atlas/image
helpers are adapted from that reference's `ui` directory. The DLL's upstream
source is https://github.com/ThornyFFXI/gdifonttexture.

### How a name is written

Edit **Mob Format** in Nameplates → Mob Nameplates. It applies to every mob nameplate,
including targeted and checked mobs. The target and checked controls are hidden, and legacy
saved `targetFormat` and `checkedFormat` strings are ignored. Checking a mob still updates
its known level and check-detail line; targeting still applies the usual targeting behaviour.

**Show Level / Range** suppresses `[level]` in the mob format, including the standard
`Lv ` prefix and following dot. **Show Aggro Icons** suppresses inline `[aggro]` icons.
Both default to on, and neither rewrites the saved strings. Other custom literal labels or
punctuation remain as typed. These toggles do not change player icons or detection/link icons
in the check-detail line (use Check → Text Only for those).

### Experimental: tracked notorious monster

This feature is experimental and has a tab of its own, **NM Tracking**. **Tracked NM** there lists
the notorious monsters of the area you are in
(and None). The one chosen, and each of its placeholders, has `assets/special/hunt.png` drawn in place
of its `[aggro]` icon, so it needs `[aggro]` in Mob Format and Show Aggro Icons on. The choice is kept by name when you leave the
area and does nothing elsewhere.

**Hunt Target Scale** (100–200%, shown while a monster is tracked) enlarges the tracked monster's
whole nameplate at every distance; its placeholders stay the usual size. Above 100% the letters are
the largest size's drawn larger, so they are slightly softer.

When the tracked monster has placeholders, **Label Placeholders** appears (on by default): each
placeholder's `[name]` is written as `Placeholder`. The rest of its nameplate, its level and letter
included, is unchanged. Placeholders are the spawn slots the server's scripts list in the
monster's `phList`, bundled per area in `placeholders/<zone>.lua` and regenerated with:

```sh
python tools/build_name_placeholders.py
```

Requires PyYAML and luajit; defaults to `references/Phoenix`. A monster that appears by some other
means than a placeholder (timed, forced, or scripted spawns) has none listed.

### Statuses over a name

The **Statuses** tab puts a row of status icons above a name, for the statuses ticked there and no
others. The icons are winxi's FFXIV-style ones (`libs\winxi\statusicons`), so `libs/winxi` has to be
deployed with its `statusicons` folder; a status with no icon there is not listed and not drawn.

| Setting | What it does |
|---|---|
| Show Statuses | The row of icons, for names that are shown |
| Scale | An icon's height, as a percentage of the height of the names: 50% to 300%, 125% to begin with. An icon is three quarters as wide as it is tall, and shrinks with its name |
| Preview | Puts the first four ticked statuses over every name that is shown, whatever it is really under, to see how the row looks. Not kept: off again when the addon is loaded |
| Search | Narrows the list under it by part of a status's name, or its number |
| Chosen Only | Lists only the ticked statuses |
| The list | Every status that has an icon, by name with its number. Hovering one shows its icon. Ticked to begin with: what ails a character, and what can be told of an enemy |

A name has at most twelve icons, each status once, and the row sits above the mastery stars when a
name has them. How much is known depends on whose name it is:

| Whose | What is shown |
|---|---|
| Your own | Everything you are under, as the game has it |
| The five others of your party | Everything they are under, as the game has it, while they are in your area |
| Everyone else | Enemies, other players, the other parties of an alliance and NPCs: any status the server was seen to say took hold on them, by spell, ability, weapon skill, monster's move or additional effect. `winxi.debuffs` keeps count, each lasting the server's base duration for what put it there (or 180 seconds where nothing says), until the server says it wore off or was dispelled. Not known: what landed out of sight or before you entered the area, and how gear, merits or a partial resist changed a duration |

The plugin draws names from eight pictures and the names' own use seven, so the icons are all drawn
from one, `statusicons\sheet.png`, which `tools/build_status_icons.py` makes with the icons.

### Experimental mob letters

Enable **Mob Letters** in Nameplates → Mob Nameplates (off by default). It adds a compact rounded letter
badge after the mob nameplate, or uses an explicit `[letter]` token wherever you put it:

```text
[aggro] Lv [level]. [name] [letter:yellow]
[letter:cyan] - [name]
```

The badge is a filled square with subtly rounded, antialiased corners and an **uppercase,
transparent letter cutout**. Indicators always use **Arial Bold** (`arialbd.ttf`), independently
of the nameplate font, Bold setting or experimental GDI backend, matching the clean sans-serif
style in `references/letter_example.png`. The box is about 78% of the nameplate font height, with a subtle corner radius of about 8% of its side.
All distances use the same close-up badge artwork, scaled down smoothly rather than switching
to separately rasterized smaller letters. This keeps the letter shape consistent as you approach.
The game scene shows through the letter. The fill uses the nameplate colour, or the explicit
token colour; the entire badge scales and fades with the nameplate. The badge uses the same
outline effect as the nameplate, including its thickness and colour. This outlines both the
outside edge and the letter cutout; the cutout's centre remains transparent where the outline
leaves room. Size/indicator-atlas changes rebuild the cached badge atlas; unchanged frames reuse
it. If texture preparation fails, an uppercase letter in the same fixed indicator font is used
and preparation is retried once per second. If Windows' Arial file cannot be loaded, the regular
ImGui default font is the recovery fallback. No updated plugin DLL is required.

Turning the toggle off hides the token without changing the saved string. Player, pet and NPC
nameplates are unaffected. All mobs, including targeted and checked mobs, use the same format.

**Consistency across users:** the addon reads the game's own list of the area's names from the client's
files as the area is entered (`zone_names.lua`), groups it by exact name, sorts each group by stable
entity index, and labels those spawn slots `a` through `z`, then wraps to `a`. The first slot is `a`,
including for a name with only one known slot. It includes slots you have not encountered or cannot
currently see. Entering from a different side, different draw/encounter order, checking, deaths, addon
reloads and respawns in the same slot therefore do not renumber mobs. No addon communication is needed,
and nothing is bundled or exported from a server: two clients with the same game files have the same
letters whatever server they are on and whatever version of the addon they have.

Each area has one such file, numbered `6720 + zone` among the game's (`86491 + zone - 256` for areas
past 255): 32-byte records, a 28-byte name and the 4-byte server id. It is where the game takes the name
it writes over a monster, so no name is guessed. Ashita is asked for the file's path
(`GetResourceManager():GetFilePath`), and it is opened with `fopen_s` so that pivot turns the read
towards its overlays: Phoenix keeps its own lists in the launcher's `EraDATs` overlay, and they differ
from the game's own files in 48 areas.

The list is of every slot the game knows, including slots the server leaves empty and the area's
people. So letters can have gaps (`a`, `b`, `e`) where a server does not use the slots between, and
a name with many unused slots wraps past `z` sooner.

**Differences are reported, not repaired.** When one of the zone's own monsters stands in a slot the
list lacks, or under a different name than the list's, the addon says so once in the chat log for that
zone visit and shows the same warning under Mob Letters in the settings: the server has renamed it, or
the files read are not the ones the game uses. Such a slot has no letter. Letters are never renumbered
from what a client has met: no client sees a whole zone, so that would differ between players. Where
the file cannot be read at all there are no letters in that area, and the settings say why.

**Double Letters** (shown under Mob Letters while it is on, off by default) goes on past `z` in place
of starting again: the twenty-seventh slot of a name is `aa`, then `ab`, and so on to `zz`, drawn as one
wider badge with both letters cut out of it. The first 26 are unchanged. Only as many double badges
are made as the area's most numerous name needs. Two players comparing letters need the same choice.

These are labels for spawn slots, not unique identities across deaths or separate instances. After 26
same-name slots, letters repeat and are not unique unless Double Letters is on (then after 702). Dynamic spawns and names that do not match their
slot are left unlabelled: there is no encounter-order fallback. Clients whose game files differ can
rank differently.

### Format tokens

Each format is a line of text. In it `[name]` stands for the name, `[distance]` for how
far the character is from you, in yalms to a tenth, as the game measures it, and `[level]` for the
levels a monster can be. Everything else is written as you type it.

| Format | Written |
|---|---|
| `[name]` | `Goblin` |
| `[name] [distance]` | `Goblin 12.3` |
| `[name] ([distance]y)` | `Goblin (12.3y)` |
| `[distance] - [name]` | `12.3 - Goblin` |
| `[name] Lv[level]` | `Goblin Lv8-10` |

A thing is in the colour the game gives the name unless you give it another. A colour is `#RRGGBB`,
`#RGB`, or one of `white`, `black`, `grey`, `red`, `green`, `blue`, `yellow`, `orange`, `purple`,
`pink`, `cyan`.

| Format | What is coloured |
|---|---|
| `[name] [distance:yellow]` | The distance |
| `[name:#FF8000] [distance]` | The name |
| `[name] [grey]([distance]y)[/]` | Everything from `[grey]` to `[/]`, or to the end of the line if there is no `[/]` |

Square brackets round anything else are written as they are, so a format such as `[NM] [name]` writes
`[NM] Goblin`. Only the letters, figures and signs of plain English can be written.

`[level]` is not the level of the one monster, which the game does not tell: it is the levels that
monster can be, as `5-6`, or as `8` where it can only be the one. They are from the tables in this
addon's `data` folder, one for each area, which are mobdb's, made from the server's own, and copied
here so that mobdb need not be installed. To bring them up to date, copy mobdb's `data` folder over
this one. They are made by mobdb's `import_phoenix.py`, which since this addon's 1.17 also writes
each monster's family: tables made before that have none, and no family is then written. For what the tables do not have (a player, an NPC, a monster the server makes as it goes)
`[level]` writes nothing, and what was typed round it is still written.

When you `/check` a monster, the game's answer has its level in it, and from then on `[level]` writes
that one level for that monster in place of the range. It is forgotten when the monster dies, when it
is no longer there to be seen, and when you leave the area, since the monster that next has its place
is another. It is also forgotten five minutes after the check, so that a long stay in one place does
not leave more and more kept: check again for it. Nothing is sent to the game for this: the addon only reads the answers to checks you make
yourself. A notorious monster, whose strength is impossible to gauge, gives no level.

`[checked]` writes a magnifying glass for a monster whose level is known that way, and nothing for any
other, so `[name] Lv[level][checked]` marks the levels that are a monster's own and not a range. It
takes a colour as the others do. The magnifying glass is one of the icons Ashita's own font has; a font
chosen for the names does not have it, and it is then drawn from Ashita's beside that font's letters.

To write a distance after the name of the monster you have targeted and no other, leave Monster Format
as `[name]` and set Targeted Monster Format to `[name] [distance]`. The Show Monster Distance and
Distance For Target Only settings of 1.9 and 1.10 are made into these lines when the addon is loaded.

`[aggro]` draws a sign for whether a monster is aggressive and how strong it is, a quarter as high
again as the name's letters and with the dark edge they have.
It is from the `data` folder's tables, so it is there whether or not the monster has been checked;
for what the tables do not have it draws nothing. `[aggro][name]` puts it before the name. A colour
given to it tints it.

There are twelve signs, six for a monster that is not aggressive and six for one that is:

| Sign | Whose |
|---|---|
| First | Level 1 to 19 |
| Second | Level 20 to 37 |
| Third | Level 38 to 56 |
| Fourth | Level 57 to 74 |
| Fifth | Level 75 and above |
| Sixth | A notorious monster, whatever its level, and one your check found impossible to gauge |

The level is the one your check found, if you have checked the monster, and otherwise the highest
the tables say it can be. The signs are the twelve pictures in `assets/aggro`, `Mob2_Icon.png` to
`Mob13_Icon.png` in that order, which are gathered into the one sheet the addon draws from,
`assets/aggro.png`, by `assets/make_aggro_sheet.py`: run it after changing any of them.

### What a check shows

With Show Check Details on, a monster you check has a second line under its name,
at the configured Check Size (75% in the preferred defaults), with its
middle under the name's. It fades in as you check, is there for five seconds, and fades out; checking
the monster again brings it back. The magnifying glass leads this line in icon mode, scales with
Check Scale, and fades with the details. When Show Check Details is enabled, an
explicit `[checked]` in the name format no longer repeats it beside the name.

- Difficulty is abbreviated by default: **TW** (Too Weak), **IEP** (Incredibly
  Easy Prey), **EP** (Easy Prey), **DC** (Decent Challenge), **EM** (Even Match),
  **T** (Tough), **VT** (Very Tough), **IT** (Incredibly Tough), and **???**
  (Impossible to Gauge). Turn off **Abbreviate Difficulty** under Names → Check
  Details to restore the full names. In abbreviated mode, a difficulty shown
  without any aggro/link information is still spelled out (for example, Very Tough).
  Impossible to Gauge remains ???. This applies to both icon and words layouts.
- For an aggressive monster, a sign for each thing it notices you by: sight, true sight, sound, low
  health, magic, job abilities, scent. Whether it is aggressive at all is not shown here: put
  `[aggro]` in the name's format for that.
- If it links, the link sign and family, followed by Sight, Hearing, or
  Sight/Hearing when those detection flags are present. For example:
  `Goblin (Sight/Hearing)`. These methods are inferred from detection flags;
  the copied tables do not contain separate linking-method fields. If neither
  flag is present, the method remains unspecified.

With Text Only on, the line contains no icons, including no magnifying glass.
Its sentence has parts separated with commas:

    TW, Sight Aggro, Link: Goblin (Sight)

The second part is there for an aggressive monster: what it notices you by (`Sight`, `Sound`, `Blood`,
`Magic`, `JA`, `Scent`, with a stroke between them if there are several, and `True Sight` and `True
Sound` for one that sees or hears truly) and then `Aggro`. The third is there for one that links, and
names the family it links with and the inferred Sight/Hearing method, when available.

The first is from the game's answer to your check. The rest is from the tables in the `data` folder,
and is what the server's own tables say of that kind of monster; for one the tables do not have, the
first is all there is. The signs for what it notices you by, and for linking, are mobdb's icons,
gathered into `assets/senses.png`.

The names are not drawn on the screen by this addon, as its windows are. An addon draws on the finished
picture, where nothing of the world can hide what it draws, and a name drawn there shows through
walls. So each name is set out here (`custom.lua`) as rectangles, one for each letter and icon, and
left with the plugin, which draws them in the game's own picture at the moment the game would have
drawn the name, as deep in the picture as the name is. A wall, the ground or a character in front of
a name hides it, or the part of it that it covers, as it hides the game's.

The letters are those of imgui's font, and where the game's picture is larger than its window (a
background resolution above the window's) they are made larger to match, so that they are as sharp as
the rest of the picture. Every frame, Name reads the plugin's world render-target size and ImGui's
live output size. Horizontal and vertical ratios are applied independently, so fonts, icons and
spacing do not stretch when the background aspect ratio differs or the client's menu resolution
is different from the output resolution. The updated `namehook.dll` also applies the horizontal
ratio to outline offsets and off-screen bounds; update the plugin together with the addon/library. Font sizes are measured in output pixels, not menu pixels. They are kept at three sizes only: the largest a name can be, three quarters
of it and half of it. A name at its largest is drawn letter for letter; a smaller one is drawn from
the next size up, scaled down to fit, so that names shrink smoothly with distance and imgui is not
asked for letters of a new size at every step. What is set out in one frame is drawn in the next.

Resolution regression check:

```sh
luajit tests/harness.lua name addons/name/name.lua tests/name_resolution_check.lua
plugins/namehook/tests/run.sh
```

The Lua check covers the Cartesian product of 11 window, menu and background sizes (4:3, 16:9,
16:10, ultrawide, portrait and square, through 8K), plus unknown dimensions, output fallback,
resize transitions and legacy callers. It verifies square geometry, centring, independent spacing
and outline proportions. Native tests verify aspect-aware bounds and cache invalidation. These
are CPU/geometry tests, not an in-game GPU certification: check live resizing, depth occlusion,
font-atlas changes and device resets in the client before treating a configuration as verified.

A name is drawn exactly when the game would have drawn it, and fades with its character as the game's
does. The game shrinks a name to nothing over the last of its distance; here it shrinks from the
maximum size to the minimum and fades out, or keeps its size and fades out over the last third.

Player icons and mastery stars use the bundled `assets/player-icons.png`, loaded through the same
owned Direct3D file-texture cache as the mob icon sheets. `assets/player-icons.lua` contains the fixed
character-to-pixel mapping; `icons.lua` no longer scans or reads the game's font memory. The linkshell
pearl retains its linkshell's colour, and two-part icons retain their overlay. Failed sheet loads retry
once per second; successful textures remain cached for the addon lifetime.

The atlas and mapping were exported from the installed client's high-resolution `ustatshd` and
`fontshp` resources in `ROM/119/51.DAT`, with icon alpha doubled to match the game's rendering.
To regenerate from a local install (Python with Pillow):

```sh
python tools/export_name_icons.py '/path/to/FINAL FANTASY XI/ROM/119/51.DAT'
```

The addon needs only the bundled PNG and mapping at runtime. Custom game icon/font DAT replacements
are not automatically reflected; replace/regenerate the bundled atlas if desired.

With the addon unloaded, or the plugin not recognising the client, the game draws
the names as before.

## The addon and the plugin

What is shown is the plugin's to keep, and can be changed there as well: by its own command
(`/namehook hide players`) or by another addon. The settings here and the plugin are kept the
same. They are given to the plugin when it is found, when another character's are loaded, and as they
change; and a change made in the plugin is taken into them, and saved.

If this addon is unloaded, names stay as they were last set, until the plugin is unloaded.
`/namehook show all` shows them all again. If the plugin is not loaded, the settings window says
so, and what is set is given to the plugin when it is.
