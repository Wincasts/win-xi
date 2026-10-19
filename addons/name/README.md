# name

Called nametoggle up to 1.5. Its settings were kept under that name: to keep them, copy the folder
`config\addons\nametoggle` to `config\addons\name` before loading it.

Shows and hides the names over characters' heads, by what they are over. A settings window for the
`namehook` plugin, which does the showing and hiding: the plugin has to be loaded.

```
/load namehook
/addon load name
```

- `/name`: opens or closes the settings. It is the only command, but for `/name diag` (see
  [Diagnostics](#diagnostics)): anything else after it only brings up this help. Use Visibility to choose which names appear; unload Name to restore the game's names.

## Settings

The preferred baseline is in `name_defaults.lua`, taken from the author's own settings.
It uses **trebucbi.ttf**, not bold, maximum/minimum font sizes **32/9**,
**90% check size**, **90% icon size**, **4 px icon spacing**, **1 px outline**, a hunted
monster's name at **120%**, and statuses level with the name's left.
Difficulty abbreviations and check details are enabled, mastery stars and words
mode are off. Own Name, Other Players, and Other Pets are hidden; Always Show
Target is on. Appearance/hide preferences are captured too.
Existing character settings take precedence over this baseline.

Kept for each character. Each is on for names that are shown.

The menus follow Trigger's layout: named sections, aligned controls, and visible
`(?)` help marks with wrapped explanations.

The tabs are **General → Names → Health Bars → Statuses → Visibility**, and **NM Tracking** after `/name dev`.

- **General:** **Preset**, a premade look to start from, and the switches for what Name draws.
  A preset sets the three formats, the check line, Health Bars and Combat Only, Status Icons and
  Check Details; font, sizes, colours, visibility and the chosen statuses are left as they are. The
  list says **Custom** when the settings are none of them.

  | Preset | Players | Enemies | Bars | Status icons | Check details |
  |---|---|---|---|---|---|
  | Default | `[icons: space=4][name]` | `[aggro] [name] [letters]` | Off | On | On |
  | Minimal | `[name]` | `[name]` | Off | Off | Off |
  | Robust | `[icons: space=4][name]` | `[aggro: space=4]Lv [level]. [name] [letters] ([distance: decimals=1]y)` | Always | On | On |
  | Immersive | `[icons: space=4][name]` | `[name]` | In combat | Off | Off |

  NPCs are `[name]` in each. **Custom Nameplates**, on to begin with, is Name drawing the names; off,
  Name lets them go at once and the game draws its own as namehook sizes them (`/namehook fontsize`),
  unstretched, Visibility still saying which are shown. Name's health bars and status icons are not
  drawn while it is off. **Health Bars** and **Status Icons** are the same switches as in their own tabs.

- **General Name Appearance:** common Font, Bold, Maximum/Minimum Name Size,
  Subtarget Size and Outline. One maximum/minimum pair applies to every entity type,
  including players, pets, enemies and NPCs.
- **Player Names:** a directly editable **Player Format**, including inline player
  icons through `[icons]` instead of a separate checkbox. The format applies to your
  own name, other players and player-style pets/trusts.
  Default: `[icons: space=4][name]`. Omit `[icons]` to hide icons or move it anywhere
  in the string. Existing icon visibility, size and spacing are migrated once.
- **Enemy Names:** a directly editable **Enemy Format** and expandable Check Details (Enabled, Size, Abbreviate Difficulty and
  Display Style: Icons & Text / Text Only). Existing enemy strings are preserved;
  Reset Format restores `[aggro] [name] [letters]` for ordinary, targeted and
  checked enemies alike.
- **NPC Names:** a directly editable **NPC Format** for non-combat NPCs, independent
  of player/enemy formats. Default: `[name]`.
- Each category has **Reset Format**. Hover the format editor's **(?)** for its
  token list, token options, a complete example format and sample output; there is
  no separate Tokens & Examples dropdown. Player/NPC strings support `[name]`,
  `[distance]`, `[icons]`, literal text and colours; enemies additionally support
  `[level]`, `[aggro]`, `[checked]`, `[letters]`.
- **Health Bars**, a tab of its own, has one shared **Enabled** toggle,
  **Combat Only**, and **Health Bar Width/Height** for every entity, including pets,
  trusts and NPCs. Dimensions and Combat Only stay visible but disabled while bars
  are off. Bars require valid live HP/server-ID data; full-health entities have none.
  Combat Only requires that particular entity to be alive and Engaged (status 1).
  Targeting/claiming alone is not combat; missing status data hides the bar.
  **Entity Types** under it says which kinds of name have a bar: Yourself, Party
  Members, Alliance Members, Other Players, My Pet, Other Pets, NPCs and Monsters,
  all ticked to begin with.
- Existing General name sizes remain authoritative. Health-bar consolidation
  migrates once: enabled if any old category enabled bars; dimensions come from the
  first enabled category in **Enemy → Player → NPC** order (Enemy if all were off).
  Old per-type bar tables remain archived but no longer drive rendering. Shared
  settings are never re-migrated during later edits. Diagnostics remains collapsed.
- Each format section has expandable **Colour Overrides**, disabled by default.
  An enabled state applies its RGB jointly to the name, spawn letters and matching
  HP fill, taking precedence over explicit name/letter token colours. Other coloured
  text and icons keep their own explicit colours; client opacity and fades remain intact.
- **Visibility:** Players, Pets, NPCs & Monsters, and Target. No diagnostic controls.
- **Statuses:** Display, Entity Types (the same eight kinds of name as for health
  bars, all ticked to begin with) and Selected Statuses, with expandable help about
  status sources.
- **NM Tracking:** Tracked Monster and conditional Placeholder Options. The tab is
  shown only after `/name dev`, until the addon is reloaded; `/name dev` again hides it.

Controls retain common widths and aligned `(?)` markers. Measurements exclude help
and window width to prevent auto-size feedback. Format token references and examples
live in the editor's tooltip; longer status/NM caveats remain in expandable help.
Existing character settings are preserved.

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

Names In View, under Names → Diagnostics, counts names shown and hidden last frame.
Diagnostics is collapsed by default and includes an Enable Diagnostics checkbox.

## Custom names

Rendering is always enabled while Name and its compatible plugin are loaded.
In the first tab, Names, configure how the names are drawn in winxi's
outlined text and not by the game: each in the colour the game gives it, with icons wherever
`[icons]` appears in its format. Which names are shown is still set in the Visibility tab; only how they look changes. It needs
namehook 1.10 or later.

| Setting | What it does |
|---|---|
| Health Bars → Enabled (shared) | Off by default. Shows a bar matching the name's colour for damaged names of every type when HP is available. Full-health names have no bar. Bars follow visibility/fading and leave room for check details and statuses |
| Health Bar Width / Height (px, Health Bars, shared) | One pair for all types, the bar's size under a name at its largest; it shrinks with the name as it goes further away, and grows with a hunted or sub-targeted one. Defaults to **60 × 6 px**, including border. Width: 12–300; height: 3–40. Saved per character |
| Bold | Makes names and check-detail text heavier. Each letter is drawn twice, a pixel apart. On in the preferred defaults; icons and stars are unchanged |
| Combat Only (Health Bars) | Off by default. Requires each entity's own Engaged status (1) and HP above zero. Missing/invalid data hides the bar; applies to players, enemies, pets/trusts and NPCs |
| Maximum Name Size (px, General) | Shared nearby text height, 6–48 pixels, for every entity type; independent of bar dimensions |
| Minimum Name Size (px, General) | Shared distant text height for every type, never more than the maximum |
| Subtarget Size (%) | The size of the name under the sub-target cursor (`<st>`, `<stpc>`, `<stnpc>` and the like) while you choose, 50% to 200% of the others'; 100% to begin with. The game's own changes to that name's size as the choice begins and ends are ignored, at any setting, so it changes size once each way. Above 100% its letters are the largest size's drawn larger, so they are slightly softer |
| Outline (px) | The dark edge round each name, 0 to 4 pixels; rounded down to whole render-target pixels to keep nearby names thinner. As letters shrink, it becomes thinner and slightly less opaque so distant names stay readable. Nearby names retain the original outline. At 0 the names are written plain |
| Font (experimental) | A font of Windows' own, chosen by its file in `C:\Windows\Fonts`; Default is the font everything else is written in |
| Player Format | How player-style names are written; NPCs and enemies have their own formats. See [How a name is written](#how-a-name-is-written) |
| NPC Format | How non-combat NPC names are written, independently of players and enemies |
| Enemy Format | How an enemy's name is written |
| `[icons]` | The game's player icons at this position in the string. Omit to hide them; mastery stars are independent |
| `[icons: size=90, gap=2, space=4]` | Icons at 90% of name height, with 2 px between icons and 4 px after the group. No spacing is reserved when there are no icons |
| Check Details → Enabled | Under the name of a monster you have checked: how hard a fight it is, what it does, and what it links with. See [What a check shows](#what-a-check-shows) |
| Check Details → Size (%) | Scale check-detail text and icons from 50% to 125% of the name size; 75% in the preferred defaults. Applies to either layout |
| Abbreviate Difficulty | On by default: TW, IEP, EP, DC, EM, T, VT and IT alongside aggro/link information. Difficulty alone uses full words; Impossible to Gauge stays ???. Off restores full difficulty names in either layout |
| Display Style → Text Only | A sentence without icons, such as `TW, Sight Aggro, Link: Goblin (Sight)`. Available while Check Details is enabled |
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

Each entity is listed once by namehook, even where the client draws its name more than once in a
frame (a player who is fishing): the addon lays out every listed name it is given and no other.

The shared drawing buffer checks capacity per quad instead of reserving 256 slots
for every name, allowing short names to use the last available slots safely.
Font-size rungs are also cached until maximum height changes, with the size setting or the window;
the letters kept for the old heights are let go then, so dragging a window's edge does not leave a
set behind for every height it passed through. Empty format parts avoid run-cache work and check-detail layout uses no temporary
width table.

Nothing asked every frame (the frame itself, a format's lookup, the letter badges' lookup) makes a
function inside itself, which LuaJIT cannot compile: what does is kept apart and called only when
something has changed. Statuses read the player's and the party's status icons only in a frame in
which a name needs them.

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
player-name icons use the same softened outline, including the base and small
badges of composite status icons. Composite badges retain the exported font-shape
size/offset: the seeking-party variant's star badge is half-size at the upper left,
not a full-size star over the icon. Plain seeking-party status has no added badge.
These status badges are independent of the three job-mastery stars, which remain unoutlined. Outline Thickness 0 disables all of these
outlines. This per-quad effect requires the
updated plugin as well as `libs/winxi`.

### How a name is written

Edit **Player Format**, **Enemy Format**, or **NPC Format** directly in the matching
section of Names. Player/NPC formats support `[name]`, `[distance]`, `[icons]` and colours;
Enemy Format also supports `[level]`, `[aggro]`, `[checked]` and `[letters]`.
Enemy Format applies to every mob nameplate,
including targeted and checked mobs. Checking a mob still updates
its known level and check-detail line; targeting still applies the usual targeting behaviour.

Formats are authoritative: `[level]` and `[aggro]` display whenever present, and
omitting them hides that information. There are no separate level/aggro toggles.
Literal labels and punctuation remain exactly as typed, so remove `Lv ` and its dot
as well if you do not want that label. Check-detail icons are separate (Check Details
→ Display Style → Text Only).

### Experimental: tracked notorious monster

This feature is experimental and has a tab of its own, **NM Tracking**, shown after `/name dev`. **Tracked NM** there lists
the notorious monsters of the area you are in
(and None). The one chosen, and each of its placeholders, has `assets/special/hunt.png` drawn in place
of its `[aggro]` icon, so it needs `[aggro]` in Enemy Format. The choice is kept by name when you leave the
area and does nothing elsewhere.

**Target Size (%)** (100–200%, shown while a monster is tracked) enlarges the tracked monster's
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

The **Statuses** tab puts a row of status icons above or below a name, for the statuses ticked there and no
others. To begin with the icons are drawn as the party and buff addons draw them, by Custom Icons in winxisettings
(`/wxi`): on, the chosen set's (FFXIV, `libs\winxi\statusicons\ffxiv`, to start) where it has an
icon for the status and the game's where it has not; off, the game's. `libs/winxi` has to be deployed
with its `statusicons` folder. The set's icons are as narrow as the set has them, the game's square.
**Icons** takes this choice over for name alone.

| Setting | What it does |
|---|---|
| Show Statuses | The row of icons, for names that are shown |
| Icons | Winxi Theme, to begin with: as Custom Icons in `/wxi` has them. Game Icons: the game's own, whatever the theme has. Custom Icons: the custom set's, the one chosen in `/wxi` (FFXIV to begin with), and the game's where it has none, whatever the theme has |
| Size (%) | An icon's height, as a percentage of the height of the names: 50% to 300%, 125% to begin with. An icon is as wide as the set's icons are for that height (three quarters for FFXIV's), and shrinks with its name |
| Position | Above, to begin with: over the name, and over the mastery stars where it has them. Below: under the name, and under the line a checked monster's details are written on while they are shown |
| Alignment | Center, to begin with: the row's middle on the name's. Left: level with the name's left, where its icons begin. Right: level with its right |
| X Offset (px) | 0 to begin with. Moves the row right from where Position and Alignment put it, in screen pixels, -200 to 200; below 0, left |
| Y Offset (px) | 0 to begin with. Moves the row down, -200 to 200; below 0, up |
| Entity Types | Which kinds of name have a row: Yourself, Party Members, Alliance Members, Other Players, My Pet, Other Pets, NPCs and Monsters. All ticked to begin with; Preview keeps to them too |
| Preview | Puts the first four ticked statuses over every name that is shown, whatever it is really under, to see how the row looks. Not kept: off again when the addon is loaded |
| Search | Narrows the list under it by part of a status's name, or its number |
| Selected Only | Lists only the ticked statuses |
| The list | Every status the game has a name for, by name with its number. Hovering one shows its icon. Ticked to begin with: what ails a character, and what can be told of an enemy |

A name has at most twelve icons, each status once. How much is known depends on whose name it is:

| Whose | What is shown |
|---|---|
| Your own | Everything you are under, as the game has it |
| The five others of your party | Everything they are under, as the game has it, while they are in your area |
| Everyone else | Enemies, other players, the other parties of an alliance and NPCs: any status the server was seen to say took hold on them, by spell, ability, weapon skill, monster's move or additional effect. `winxi.debuffs` keeps count, each lasting the server's base duration for what put it there (or 180 seconds where nothing says), until the server says it wore off or was dispelled. Not known: what landed out of sight or before you entered the area, and how gear, merits or a partial resist changed a duration |

The plugin draws names from eight pictures and the names' own use seven, so the icons are all drawn
from one, put together the first time it is wanted, 32 statuses a frame: the set's sheet
(`statusicons\ffxiv\sheet.png`, which `tools/build_status_icons.py` makes with the icons) or, for
another set, its icons one by one, and the game's icons in the places the set leaves. With Custom
Icons off it is a sheet of the game's icons alone.

### State colour overrides

Open **Colour Overrides** under Player Names, Enemy Names or NPC Names. Each state
has an enable checkbox and RGB picker. **Use Game Colours** disables that category's
overrides without discarding its chosen picker colours or changing format strings.

| Category | States |
|---|---|
| Players (also self, party/alliance, pets/trusts) | Normal, In Combat, Targeted, Dead |
| Enemies | Unclaimed, Claimed: You / Party / Alliance, Claimed: Others, Targeted, Dead |
| NPCs | Normal, Targeted |

Priority is **Dead → Targeted → combat/claim state → Normal**. A disabled live state
falls back to an enabled underlying state, then to the usual game/format colour.
Death never falls back to a live/target override: with Dead disabled, the normal
corpse colour remains. Claims use validated entity IDs and active party/alliance
server IDs; unknown ownership data is not guessed. State is evaluated every frame.
Opacity is not configurable here: a target's name and letters keep a steady opacity, status
icons stay independent, and corpse/distance/disappearance fades still apply.

### Experimental mob letters

Add `[letters]` to Enemy Format wherever a compact rounded letter badge belongs.
There is no separate enable or double-letter checkbox. `[letter]` remains a legacy alias.

```text
[aggro] Lv [level]. [name] [letters: color=yellow]
[letters: type=double, color=cyan, space=4][name]
```

The badge is a filled square with subtly rounded, antialiased corners and an **uppercase,
transparent letter cutout**. Indicators always use **Arial Bold** (`arialbd.ttf`), independently
of the nameplate font or Bold setting, matching the clean sans-serif
style in `references/letter_example.png`. The box is about 68% of the nameplate font height, with a subtle corner radius of about 8% of its side.
All distances use the same close-up badge artwork, scaled down smoothly rather than switching
to separately rasterized smaller letters. This keeps the letter shape consistent as you approach.
The game scene shows through the letter. The fill uses the nameplate colour, or the explicit
token colour, unless an enabled state override sets their joint colour. Default inheritance also follows an explicitly coloured `[name]`, even when the
letter appears before it in the format. Letters share the name text's colour and opacity rather than
the independent status-icon opacity. The entire badge scales and fades with the nameplate and
retains its saved token position. The badge uses the same
outline effect as the nameplate, including its thickness and colour. This outlines both the
outside edge and the letter cutout; the cutout's centre remains transparent where the outline
leaves room. Size/indicator-atlas changes rebuild the cached badge atlas; unchanged frames reuse
it. If texture preparation fails, an uppercase letter in the same fixed indicator font is used
and preparation is retried once per second. The plain fallback shares the badge's name-font
lowercase baseline, avoiding a vertical jump as the badge atlas becomes ready.
If Windows' Arial file cannot be loaded, the regular
ImGui default font is the recovery fallback. No updated plugin DLL is required.

Remove the token to hide letters. Player, pet and NPC nameplates are unaffected. All mobs, including targeted and checked mobs, use the same format.

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
zone visit and shows the same warning under Enemy Names when its format includes letters: the server has renamed it, or
the files read are not the ones the game uses. Such a slot has no letter. Letters are never renumbered
from what a client has met: no client sees a whole zone, so that would differ between players. Where
the file cannot be read at all there are no letters in that area, and the settings say why.

**`[letters: type=double]`** continues after `z`: the twenty-seventh slot is `aa`,
then `ab`, up to `zz`, in one wider badge. The first 26 stay unchanged.
`[letters]` or `[letters: type=single]` repeats A–Z. Type is per token, so both
variants can appear in one format. Only needed double badges are made; users
comparing letters need the same token type. Old automatic/double-letter settings
migrate into explicit tokens once, without re-adding tokens removed afterward.

These are labels for spawn slots, not unique identities across deaths or separate instances. After 26
same-name slots, letters repeat unless the token uses `type=double` (then after 702). Dynamic spawns and names that do not match their
slot are left unlabelled: there is no encounter-order fallback. Clients whose game files differ can
rank differently.

### Format tokens

Each format is a line of text. In it `[name]` stands for the name, `[distance]` for how
far the character is from you, in yalms to a tenth, as the game measures it, and `[level]` for the
levels a monster can be. `[icons]` draws player icons at that point in the string.
Everything else is written as you type it.

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

#### Token options

Use `key=value` options after a colon, separated by commas, semicolons or spaces.
The older `[name:yellow]` colour shorthand remains supported.

| Applies to | Option | Meaning |
|---|---|---|
| Every token | `color=yellow` or `color=#FF8000` | Override this token's colour |
| Every token | `space=0`–`64` | Screen-pixel gap after the token, scaled with render resolution. Omitted when the token produces nothing |
| Every token | `when=target+checked+nm+relevant` | Any subset, combined with AND; omitted / `always` means unconditional |
| Every token | `within=1`–`100` | Only within this distance in yalms; unavailable distance hides the block |
| `[mob]` | `display=raw` / `names` / `both` | Raw by default; `names` gives readable names, `both` adds the IDs |
| `[icons]` | `size=25`–`300` | Icon height as a percentage of name height; defaults to the profile's previous icon size (90% in preferred defaults) |
| `[icons]` | `gap=0`–`24` | Screen pixels between icons; default 2 |
| `[distance]` | `decimals=0`–`2` | Decimal places; default 1 |
| `[letters]` / `[letter]` | `type=single` / `type=double` | Repeat A–Z, or continue AA, AB, etc. after Z; default single |

```text
[icons: space=4][name]
[name: space=8][icons: size=100, gap=3, space=0]
[icons: space=4][name] ([distance: decimals=2, color=yellow]y)
[aggro: space=4]Lv [level: color=yellow, space=6][name]
```

With no explicit `space`, icons use the profile's previous icon spacing (4 px in
preferred defaults); other tokens use zero. Colours on icons override pearl tint;
otherwise the linkshell pearl retains its own colour and two-part icons remain overlaid.
Out-of-range numeric options are clamped; unknown or malformed options leave the
whole bracketed token literal, rather than breaking the nameplate.

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

The Show Monster Distance setting of 1.9 and 1.10 is made into `[distance]` in Mob Format when the
addon is loaded.

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
Check Details → Size (%), and fades with the details. When Show Check Details is enabled, an
explicit `[checked]` in the name format no longer repeats it beside the name.

- Difficulty is abbreviated by default: **TW** (Too Weak), **IEP** (Incredibly
  Easy Prey), **EP** (Easy Prey), **DC** (Decent Challenge), **EM** (Even Match),
  **T** (Tough), **VT** (Very Tough), **IT** (Incredibly Tough), and **???**
  (Impossible to Gauge). Turn off **Abbreviate Difficulty** under Names → Enemy Names → Check Details
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

Name visibility follows the game. The game shrinks a name to nothing over the last of its
distance; here it shrinks from the maximum size to the minimum and fades out, or keeps its
size and fades out over the last third.

The game pulses a living target's name, its colour going toward white or toward dark and its
opacity dipping. Here the target's name does not pulse: its text, outline, spawn letters, status
icons, composite overlays, aggro/check icons and mastery stars all hold the peak opacity, and the
text keeps the colour the pulse starts from. A change of colour that is no pulse, such as a
monster's name turning red as it is claimed, is taken at once. Spawn letters inherit the name's
colour unless their token has an explicit colour; explicit token colours and enabled state
overrides still apply. Distance fading remains active. The hold resets on untargeting, respawn,
entity reuse or a gap in drawing.

By default a dead monster's name turns grey immediately, including when its live `[name]`
token has an explicit colour. An enabled Dead state colour overrides that default grey. A neutral corpse grey supplied by the client replaces the fallback grey;
subsequent stale red/white claim samples cannot recolour it. Corpse opacity still follows the
client directly, even while targeted, so icons and text fade away together. Once the client's
render flags say the mob is no longer shown (or its entity has been removed), any remaining
nameplate fades out in about **0.2 seconds**, including target icons and letters. The fade does
not start just because HP reaches zero while the corpse is still visible. Late name calls do
not restart it, respawning releases it, and an index reused by a different entity immediately
suppresses the stale label. Missing render-flag data alone does not trigger a disappearance.

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

## Diagnostics

Off unless turned on, for testers:

```
/name diag          turns diagnostics on or off; kept with the character's settings
/name diag on|off
/name diag log      writes a log now, on or off (with diagnostics off it has no history)
```

While they are on, Names → Diagnostics shows whether Name is drawing the names (**Custom Names**).
When Name stops claiming the names for more than 30 frames, about half a second, the game draws
its own names again. The reason is said once in the chat log and a log is written, once a session for each reason.
The reasons:

| Reason | What it means |
|---|---|
| `unloaded`, `old`, `mismatch` | The namehook plugin is not loaded, or is not the version this addon reads. No log is written for `unloaded` |
| `unhooked` | The plugin did not recognise this client's name drawing |
| `texture` | imgui's font texture was not ready, or could not be read |
| `draw` | The plugin had no drawing buffer |
| `error` | A Lua error in the frame. It is still raised as before, and kept once in the log with its traceback and a count |

With diagnostics off, nothing is kept or said, and the frame is drawn exactly as without them.

**Write Log** in the Status section, while diagnostics are on, writes a log as `/name diag log` does. Logs are small text files in
`config\addons\name\logs`, named `name-<date>-<time>.txt`. Each holds:

- The plugin's state: whether it is hooked, the frame and the last claim, what is claimed and
  hidden, and the names of the last frame and who drew them.
- The font atlas texture: whether imgui has it ready, what imgui says of it, and the texture the plugin read for it as it last drew the names; and the display size.
- Pauses since loading, short and seen.
- Lua errors.
- The last 300 events: zone-ins, settings given to or taken from the plugin, stops and resumes, and
  fonts or letter badges that would not load, and each time imgui makes the font texture again.
- The settings.

Testers can send the file with a report.
