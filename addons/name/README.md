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

Public tabs are **Nameplates → Filters**. Experimental and Appearance are hidden;
GDI is forced off so testers exercise the ImGui renderer.

- **Nameplates:** follows `guis/name.menu`: Name Appearance, Player Icons, and
  Check. Options boxes measure the longest option row and share a width fitted
  to that row plus its help marker and padding. Every `(?)` sits in the same
  right-aligned column. Measurements exclude help and window width, preventing
  auto-size feedback; widths can shrink when content becomes shorter. Font sizes and icon padding use numeric
  inputs; outline thickness uses radio buttons 0–3. Font selection comes first.
  Format controls are hidden; drawing uses the saved `name_defaults.lua` formats:
  `[name]` for general names and `[aggro] Lv [level]. [name]` for monsters,
  targeted monsters and checked monsters.
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

Each of the four formats is a line of text. In it `[name]` stands for the name, `[distance]` for how
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
the rest of the picture. They are kept at three sizes only: the largest a name can be, three quarters
of it and half of it. A name at its largest is drawn letter for letter; a smaller one is drawn from
the next size up, scaled down to fit, so that names shrink smoothly with distance and imgui is not
asked for letters of a new size at every step. What is set out in one frame is drawn in the next.

A name is drawn exactly when the game would have drawn it, and fades with its character as the game's
does. The game shrinks a name to nothing over the last of its distance; here it shrinks from the
maximum size to the minimum and fades out, or keeps its size and fades out over the last third.

The icons are drawn from the game's own picture of them, found in its memory (`icons.lua`); the
linkshell pearl is given its linkshell's colour.

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
