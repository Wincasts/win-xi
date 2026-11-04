# winplates

Replaces the game's names over players, NPCs and monsters with fully configurable ones. Choose which
names appear and how each kind is formatted, and add health bars, cast bars, status icons, monster
levels and check information beneath or above them. Requires the namehook plugin, which comes with
its download.

## Highlights

- Hide the names you do not need while keeping your target's name visible.
- See a monster's possible levels, whether it is aggressive, and a letter that tells monsters of the
  same name apart.
- Show health bars, cast bars and active statuses alongside each name.
- Improve readability with your choice of font, size, outline and colours.

Up to 1.86 this addon was called name, and up to 1.5 it was called nametoggle. See
[Coming from name or nametoggle](#coming-from-name-or-nametoggle).

## Install and load

winplates needs:

- the `namehook` plugin, **1.35 or newer**. A plugin is a `.dll` file that Ashita loads with `/load`.
  The smoother outline round text and the smooth edges of health bars need namehook 1.32 or newer.
- the WinXI library (`addons\libs\winxi`), **78 or newer**. WinXI is the shared library that draws
  the winxi addons. With an older WinXI, winplates says so and does not load.

With a namehook that is too old, the game keeps its own names and winplates keeps only its controls
for which names are shown. It warns you to update.

Load the plugin first, then the addon:

```
/load namehook
/addon load winplates
```

When you update, install the new `namehook.dll` as well as winplates and WinXI. Then reload namehook
and every addon that uses WinXI, or start the game again.

If the addon is unloaded, or the plugin does not recognise your game client, the game draws the
names as it always did.

### Coming from name or nametoggle

- **From name:** load `winplates` instead of `name`, and remove the old `addons\name` folder. Each
  character's settings are brought over from `name` the first time that character logs in. `/name`
  still opens the settings.
- **From nametoggle:** its settings are not brought over. Copy the folder `config\addons\nametoggle`
  to `config\addons\winplates` before you load the addon.

## Commands

| Command | What it does |
|---|---|
| `/winplates` (or `/name`) | Opens or closes the settings window |
| `/winplates help` | Lists the commands in the chat log |
| `/winplates report` | Writes a support report. See [Diagnostics](#diagnostics) |
| `/winplates diag` | Turns diagnostic recording on or off. See [Diagnostics](#diagnostics) |
| `/winplates diag log` | Writes a diagnostic log now |

Anything else after `/winplates` only shows a line of help. To choose which names appear, use the
**Visibility** tab. To get the game's own names back, unload winplates.

## The settings window

Settings are kept for each character. They only change names that are shown.

Each setting is a row: its name, a sentence under it that says what it does, and its control on the
right. There are no help marks or tooltips.

The tabs, in order, are **General**, **Names**, **Bars**, **Check Details**, **Statuses** and
**Visibility**. Each extra part of a name (health bars, cast bars, check details, statuses) has its
own section, with **Enabled** at the top. Health bars and cast bars share the **Bars** tab.

### Starting settings

A new character starts with the author's own settings. Settings a character already has are kept and
win over these.

- Font **trebucbi.ttf**, not bold. Largest and smallest name size **30** and **10**.
- The sub-target's name at **125%**.
- Check details at **90%**, with abbreviated difficulty, in the icon style.
- Icons at **90%**, with **4 px** after them. Text outline **1 px**.
- Health bars off, at **120 × 7 px**.
- Statuses at **100%**, lined up with the left of the name, moved **2 px right and 5 px up**. Fewer
  statuses are ticked: 2–8, 10–13, 19, 132–135, 156, 192, 194 and 217.
- Mastery stars are off.
- **Own Name** hidden. **Other Players** and **Other Pets** shown. **Always Show Target** off.
- The players' **Normal** (pale blue) and **Alliance** (amber) colour overrides on.
- The appearance and the hiding rules are part of these settings too.

The values below say "to begin with" for these starting settings. Where the addon's plain default is
different, it is given as well.

### General tab

- **Enable winplates** (on to begin with): winplates draws the names. Turn it off and winplates lets
  go of them at once:
  - the game draws its own names, at its own size, unless `/namehook fontsize` gave them a size;
  - **Visibility** still decides which names are shown;
  - winplates' health bars and status icons are not drawn;
  - all other winplates settings are greyed out until you turn it on again. Your saved values are
    kept.
- **Preset**: a ready-made look to start from. A preset sets the three formats, **Health Bars** and
  **Combat Only**, status icons, and **Check Details**. It does not change the font, sizes, colours,
  visibility or the statuses you ticked. The list says **Custom** when your settings match no preset.

| Preset | Players | Enemies | Bars | Status icons | Check details |
|---|---|---|---|---|---|
| Default | `[party: space=2][icons: space=4][name]` | `[aggro] [name] [letters]` | Off | On | On |
| Minimal | `[name]` | `[name]` | Off | Off | Off |
| Robust | `[party: space=2][icons: space=4][name]` | `[aggro: space=4]Lv [level]. [name] [letters] ([distance: decimals=1]y)` | Always | On | On |
| Immersive | `[party: space=2][icons: space=4][name]` | `[name]` | In combat | Off | Off |

NPCs are `[vendor: space=4][name]` in every preset except Minimal, where they are `[name]`.

**Diagnostics** is also in the General tab. It starts collapsed. See [Diagnostics](#diagnostics).

### Names tab

**Appearance** has three sub-sections. One largest/smallest size applies to every kind of name:
players, pets, enemies and NPCs.

| Setting | What it does |
|---|---|
| **Font** (Font) | A Windows font, chosen by its file in `C:\Windows\Fonts`. Default is the font everything else is written in |
| **Bold** (Font) | Makes names and check-detail text heavier: each letter is drawn twice, one pixel apart. Off to begin with. Icons and stars do not change. For a font's own bold look, choose its bold font file instead |
| **Smooth Font** (Font) | Off to begin with. Draws the letters at four times their size once, keeps them, and shrinks them smoothly. It keeps the normal spacing and Bold. Icons and letter badges do not change. It uses more memory, takes a moment to prepare the first time, and can soften very small text. While it is being prepared, or if it cannot be used, names are drawn the normal way |
| **Maximum Name Size** (Size) | How tall names are when near: 6 to 48 px, for every kind of name. 30 to begin with. It does not depend on the bar size |
| **Minimum Name Size** (Size) | How tall names are when far. Never more than the maximum. 10 to begin with |
| **Subtarget Size** (Size) | The size of the name under the sub-target cursor (`<st>`, `<stpc>`, `<stnpc>` and the like) while you choose: 50% to 200% of the other names. 125% to begin with (plain default 100%). The game's own size changes when you start and stop choosing are ignored, so the name changes size once each way. Above 100% the letters are slightly softer |
| **Letter Spacing** (Size) | Extra space between the letters of every name: 0 to 10 px at the name's largest, less when it is further away. 0 (the font's own spacing) to begin with. It applies to everything in the format line, typed text included. A `[name]`, `[level]` or `[distance]` token's `spacing=` sets its own. Icons, signs, letter badges, check details and cast text are not spaced |
| **Vertical Offset** (Size) | Moves every name down from where the game puts it: -200 to 200 px at the name's largest, less when further away. Below 0 moves it up. 0 to begin with. Mastery stars, health and cast bars, check details and the status row move with the name |
| **Text Outline** (Outlines) | The dark edge round the text: None, 1, 2 or 3 px. 1 px to begin with. None turns off the outline and the soft shadow under the text |
| **Text Outline Opacity** (Outlines) | How solid the edge round the text and the bars is: 0 to 100%. 100% to begin with. It covers names, levels, distances, check details and cast text |
| **Icon Outline** (Outlines) | The dark edge round icons: None, 1, 2 or 3 px. 1 px to begin with |
| **Icon Outline Opacity** (Outlines) | How solid the edge round icons is: 0 to 100%. 100% to begin with |

More about the outlines:

- With namehook 1.32 or newer, the outline round text is smoother, with a soft shadow below. Health
  bar edges are smooth, also when the lens plugin changes the picture. Names keep their size, place,
  colours and formats. Small names keep more contrast.
- The outline is a whole number of screen pixels, so a higher screen resolution does not make near
  names look too bold. A distant name keeps the outline's thickness, but the outline grows fainter.
- The icon outline settings apply to player, party-role, vendor, aggro and passive, sense and check
  icons. Text Outline at None does not turn off icon outlines. Either icon setting at zero turns off
  only the icon edges. Fills, layout, colours, mastery stars and letter badges are not changed.
- The aggro and passive signs have no shadow, but their outline follows the width you chose.

**Player Names**, **Enemy Names** and **NPC Names** each have:

- a format you edit directly: **Player Format**, **Enemy Format** or **NPC Format**. A format is a
  line of text with tokens in square brackets, such as `[name]`. See
  [Writing a name format](#writing-a-name-format);
- a **Reset** button in the row after it, which puts back that format's default;
- **Format Tokens**, a sub-section that starts collapsed. It lists every token that kind of name can
  have, with an example format and what it writes;
- **Colour Overrides**, a sub-section that starts collapsed. See
  [Colour overrides](#colour-overrides).

| Format | Used for | Default | Tokens it can have |
|---|---|---|---|
| **Player Format** | Your own name, other players, and pets and trusts that look like players | `[party: space=2][icons: space=4][name]` | `[name]`, `[icons]`, `[distance]`, `[party]` |
| **Enemy Format** | Every monster, also when targeted or checked | `[aggro] [name] [letters]` | `[name]`, `[level]`, `[aggro]`, `[checked]`, `[letters]`, `[distance]` |
| **NPC Format** | NPCs you cannot fight | `[vendor: space=4][name]` | `[name]`, `[icons]`, `[distance]`, `[vendor]` |

The three formats do not depend on each other. Formats you already have are kept. There are no Help
or Examples dropdowns: what they said is now under Format Tokens.

**Player Names** also has **Player Icon Source**. See [Player icon source](#player-icon-source).

**Distance Thresholds**, at the bottom of the Names tab, is described in
[Optional readability settings](#optional-readability-settings).

### Bars tab

The Bars tab has health bars and cast bars.

**Shared Bar Settings** comes first. Its rows are greyed out until health bars or cast bars are on.

| Setting | What it does |
|---|---|
| **Bar Width** / **Bar Height** | One size for health and cast bars of every kind of name: the bar's size under a name at its largest. The bar shrinks as the name goes further away, and grows with a sub-targeted name. Width 12–300 px, height 3–40 px, border included. 120 × 7 px to begin with (plain default 60 × 6 px). Saved per character |
| **Bar Outline** | How thick the dark edge round the bars is: None to 3 px, 1 px to begin with. It fades with the name. With None the bars keep their soft edge |
| **Fit To Name** | Off to begin with. Health and cast bars grow to the width of the name and its letter badges. Bar Width is the least they are. See [Cast bars and bar layout](#cast-bars-and-bar-layout) |
| **Preview** | For this session only, while the section is open. Each name that can have a health bar shows one, emptying and filling, also at full health and out of combat (**Entity Types** still apply). With cast bars on, a sample cast runs under the names. Never saved |

The bars are always the plain bar with a dark border, tinted in the name's colour. (Bar Texture was
removed in 1.80.)

**Health Bars**:

| Setting | What it does |
|---|---|
| **Enabled** | Off to begin with. A bar in the name's colour under damaged names of every kind (pets, trusts and NPCs too), when HP is known. A name at full health has no bar, unless a cast bar needs the health row above it. Bars follow which names are shown and how they fade. They leave room for check details and statuses |
| **Combat Only** | Off to begin with. A bar only for something alive and fighting (Engaged). Being targeted or claimed is not fighting. If the game's data is missing or wrong, there is no bar |
| **Entity Types** | A sub-section: which kinds of name have a health bar. Yourself, Party Members, Alliance Members, Other Players, My Pet, Other Pets, NPCs and Monsters. All ticked to begin with |

Health bars need the character's live HP, which the game must send.

**Cast Bars** and **Cast Text** are described in [Cast bars and bar layout](#cast-bars-and-bar-layout).

### Check Details tab

When you `/check` a monster, a line under its name shows what the check found. See
[What a check shows](#what-a-check-shows).

| Setting | What it does |
|---|---|
| **Enabled** | On to begin with. Turns the line on. The other rows are greyed out while it is off |
| **Size** | How big the check text and icons are: 50% to 125% of the name size. 90% to begin with. Applies to both styles |
| **Abbreviate Difficulty** | On to begin with. Short labels (TW, IEP, EP, DC, EM, T, VT, IT) next to the aggro and link details. A difficulty on its own is still written in full; Impossible to Gauge stays ???. Off writes the full names in both styles |
| **Display Style** | **Icons & Text** (to begin with) or **Text Only**: a sentence without icons, such as `TW, Sight Aggro, Link: Goblin (Sight)` |

### Statuses tab

The Statuses tab puts a row of status icons above or below a name. Only the statuses you tick are
shown. See [Statuses over a name](#statuses-over-a-name) for which icons are used and what is known.

**Display**:

| Setting | What it does |
|---|---|
| **Enabled** | The row of icons, for names that are shown |
| **Icons** | **Winxi Theme** (to begin with): as **Custom Icons** in `/wxi` has them. **Game Icons**: the game's own. **Custom Icons**: the custom set chosen in `/wxi` (FFXIV to begin with), and the game's icon where the set has none |
| **Size** | An icon's height, as a percentage of the name's height: 50% to 300%. 100% to begin with (plain default 125%). An icon is as wide as the set's icons are for that height (three quarters for FFXIV's). It shrinks with its name |
| **Position** | **Above** (to begin with): over the name, and over the mastery stars if it has them. **Below**: under the name, and under a checked monster's details while they are shown |
| **Alignment** | **Left** (to begin with; plain default Center): level with the name's left, where its icons begin. **Center**: the row's middle on the name's middle. **Right**: level with the name's right |
| **X Offset** | Moves the row right, in screen pixels, -200 to 200. Below 0 moves it left. 2 to begin with (plain default 0) |
| **Y Offset** | Moves the row down, -200 to 200. Below 0 moves it up. -5 to begin with (plain default 0) |
| **Only Yours On Enemies** | Off to begin with. A monster's row shows only the statuses you put on it |
| **Preview** | Puts sample statuses over every name that is shown, so you can see how the row looks. Over a character: Protect, Shell and Haste that you cast, and a Paralysis running out. Over a monster: your Dia and Slow, a Paralysis, and an Attack Boost that Dispel removes. With **Show Durations**, each has a sample time in its colour. Not kept: it is off again when the addon is loaded |

**Durations**:

| Setting | What it does |
|---|---|
| **Show Durations** | Off to begin with. Writes the time left under each icon: seconds, then minutes (`m`), then hours (`h`). Your own times are exact, read from the game. Everyone else's are estimates (see below). Where the time cannot be known, `-` is written |
| **Duration Size** | How tall the times are, compared with the icon: 30% to 100%. 50% to begin with |
| **Duration Font** | **Same as Names** (to begin with), **Default**, or one of your fonts |
| **Estimate Colour** | The colour of estimated times and of `-`. Yellow to begin with |
| **Your Colour** | The colour of times on statuses you cast. Green to begin with. It lets you see when someone else's status replaces yours |
| **Low Time Warning** | 0 to 60 seconds, 10 to begin with, 0 for none. An icon with less time left than this fades out and in |

An estimate starts when the status is seen to land, or to appear on a party member. It uses the
server's usual time for that status.

**Removable Marks**:

| Setting | What it does |
|---|---|
| **Removable Marks** | Off to begin with. Puts a small square in a dark border inside the corner of each status you can take off |
| **Curable Mark Colour** | Light blue. Used on a character's debuffs that Erase, a -na spell or a waltz removes |
| **Dispellable Mark Colour** | Amber. Used on a monster's buffs that Dispel removes |
| **Only What You Can Remove** | Off to begin with. Marks only what a spell you have learned, and can cast at your level now, takes off. Level sync counts |

**Entity Types**: which kinds of name have a row: Yourself, Party Members, Alliance Members, Other
Players, My Pet, Other Pets, NPCs and Monsters. All ticked to begin with. Preview keeps to them too.

**Selected Statuses**:

| Setting | What it does |
|---|---|
| **Search** | Shows only statuses whose name contains what you type, or whose number matches |
| **Selected Only** | Shows only the ticked statuses |
| The list | Every status the game has a name for, by name and number. It leaves out placeholder entries whose names are wholly in brackets, such as (None), (N/A) and (Imagery), and numbers the server has no status for. Hover over a status to see its icon. Ticked to begin with: what ails a character, and what can be told about an enemy |

This section also has help about where status information comes from, which you can expand.

### Visibility tab

**Names Shown** has three sub-sections, **Players**, **Pets** and **NPCs & Monsters**, then **Always
Show Target**. There are no diagnostic controls here.

| Setting | Whose names |
|---|---|
| **Own Name** | Your own |
| **Party Members** | The others in your party, trusts among them |
| **Alliance Members** | The other parties of your alliance |
| **Other Players** | Every other player. A player on the plugin's whitelist is shown anyway: `/namehook whitelist add <name>` |
| **My Pet** | Your own pet |
| **Other Pets** | Anyone else's pet, trust or adventuring fellow |
| **NPCs** | What cannot be fought |
| **Monsters** | What can be fought, charmed players among them |
| **Always Show Target** | Shows your target's name even when names of its kind are hidden. Your own name is the exception: with Own Name off it stays hidden while you target yourself |

Some names are never drawn, whatever these settings say:

- **Someone under Invisible.** This includes your target and whitelisted players. winplates learns
  who is invisible from the server's updates. So someone who is already invisible when winplates
  loads keeps their name until their next update. With **Enable winplates** off, the game draws its
  own names and decides this itself.
- **A name the game hides.** For example a Chigoe's name until it is engaged, or an NPC the server
  keeps hidden. The game gives such a name no text. Only your own name is filled in from your
  character when that happens.

**Crowd Decluttering**, at the bottom of this tab, is described in
[Optional readability settings](#optional-readability-settings).

## Writing a name format

Edit **Player Format**, **Enemy Format** or **NPC Format** in its section of the Names tab. A format
is a line of text. Tokens in square brackets are replaced. Everything else is written as you typed it.

| Token | What it writes |
|---|---|
| `[name]` | The name |
| `[distance]` | How far the character is from you, in yalms to a tenth, as the game measures it |
| `[level]` | The levels a monster can be (enemies only). See [Level, checked and aggro](#level-checked-and-aggro) |
| `[icons]` | The game's player icons, at this point in the line. Leave it out to hide them. Mastery stars are separate |
| `[party]` | A party or alliance member's sign (players only). See below |
| `[vendor]` | A coin for an NPC that sells (NPCs only). See below |
| `[aggro]` | A sign for whether a monster is aggressive and how strong it is (enemies only) |
| `[checked]` | A magnifying glass when a monster's exact level is known (enemies only) |
| `[letters]` | A letter badge that tells same-name monsters apart (enemies only). See [Mob letters](#mob-letters) |
| `[space]`, `[space: 8]` | A gap of 4 px, or of as many screen pixels as given (0–64; `size=` does the same) |

Examples:

| Format | Written |
|---|---|
| `[name]` | `Goblin` |
| `[name] [distance]` | `Goblin 12.3` |
| `[name] ([distance]y)` | `Goblin (12.3y)` |
| `[distance] - [name]` | `12.3 - Goblin` |
| `[name] Lv[level]` | `Goblin Lv8-10` |

The format decides what is shown. `[level]` and `[aggro]` show whenever they are in the format.
Leave them out to hide that information. There are no separate level or aggro switches. Typed labels
and punctuation stay exactly as typed. So if you remove `[level]`, remove `Lv ` and its dot too.
Check-detail icons are separate (Check Details → Display Style → Text Only).

Enemy Format is used for every monster, also when targeted or checked. Checking a monster still
updates its known level and its check line. Targeting works as usual.

More about some tokens:

- **`[space]`** is only written between two things that are written. There is none at either end of
  the line, or next to a token that writes nothing. So a member with no icons has no gap before the
  name. `[icons][space: 4][name]` is the same as `[icons: space=4][name]`: an icon token followed by
  `[space]` gives up its own spacing.
- **`[icons: size=90, gap=2, space=4]`** draws icons at 90% of the name's height, with 2 px between
  icons and 4 px after the group. No space is kept when there are no icons.
- **`[party]`** draws a sign of each party and alliance member's role: Alliance Leader, Party Leader,
  another party's leader (Alliance Party Leader), Alliance Member or Party Member. `[party: replace]`
  also leaves out the game's icons for a member who has the sign. Players outside your party and
  alliance keep the game's icons. There is no sign while you are alone.
- **`[vendor]`** draws a coin for every NPC that sells: gil shops, guild merchants and outpost
  vendors. For any other NPC it draws nothing, and leaves no space. The list of vendors is the chosen
  server's `vendors` set in WinXI's game data, by area and name.

### Colours

Every part is in the colour the game gives the name, unless you give it another. A colour is
`#RRGGBB`, `#RGB`, or one of `white`, `black`, `grey`, `red`, `green`, `blue`, `yellow`, `orange`,
`purple`, `pink`, `cyan`.

| Format | What is coloured |
|---|---|
| `[name] [distance:yellow]` | The distance |
| `[name:#FF8000] [distance]` | The name |
| `[name] [grey]([distance]y)[/]` | Everything from `[grey]` to `[/]`, or to the end of the line if there is no `[/]` |

### Token options

Put `key=value` options after a colon. Separate them with commas, semicolons or spaces. The older
`[name:yellow]` colour shortcut still works.

| Applies to | Option | Meaning |
|---|---|---|
| Every token | `color=yellow` or `color=#FF8000` | Gives this token its own colour |
| Every token | `space=0`–`64` | A gap after the token, in screen pixels, scaled with your screen resolution. Left out when the token writes nothing |
| Every token | `when=target+checked+nm+relevant` | Only when all the listed conditions hold. Use any of them. Left out, or `always`, means always |
| Every token | `within=1`–`100` | Only within this distance in yalms. When the distance is not known, it is hidden |
| `[icons]`, `[party]`, `[vendor]` | `size=25`–`300` | Icon height as a percentage of the name's height. Default: the profile's earlier icon size (90% in the starting settings) |
| `[aggro]` | `size=25`–`300` | The sign's height as a percentage of the name's height. Default 125 |
| `[checked]` | `size=25`–`300` | The magnifying glass's size as a percentage of the letters'. Default 70 |
| `[icons]` | `gap=0`–`24` | Screen pixels between icons. Default 2 |
| `[party]` | `replace` | For a member with a sign, leave out the game's icons wherever `[icons]` is |
| `[distance]` | `decimals=0`–`2` | Decimal places. Default 1 |
| `[name]`, `[level]`, `[distance]` | `spacing=0`–`10` | Screen pixels between this token's letters at the name's largest, shrinking with the name. Used instead of **Letter Spacing** |
| `[level]` | `exact` | Only the exact level, once the monster is checked. Nothing before then, and nothing for a monster that is impossible to gauge, where `[level]` would write the range. Text around it stays |
| `[level]` | `nocombat` | Nothing while the monster is in combat (engaged and alive, as for **Combat Only** health bars). The level comes back when it is not. Text around it stays |
| `[letters]` / `[letter]` | `type=single` / `type=double` | Repeat A–Z, or go on with AA, AB and so on after Z. Default single |

```text
[icons: space=4][name]
[name: space=8][icons: size=100, gap=3, space=0]
[icons: space=4][name] ([distance: decimals=2, color=yellow]y)
[aggro: space=4]Lv [level: color=yellow, space=6][name]
[name: spacing=2] ([distance: spacing=0]y)
[aggro] Lv [level: nocombat] [name]
```

- With no `space` given, icons, party signs and the vendor coin use the profile's earlier icon
  spacing (4 px in the starting settings). Other tokens use zero.
- A colour on `[icons]` replaces the linkshell pearl's tint. Otherwise the pearl keeps its own colour,
  and two-part icons stay layered.
- Numbers out of range are moved into range.
- An unknown or badly written option leaves the whole bracketed token as typed. The name still works.
- Square brackets round anything else are written as they are. So `[NM] [name]` writes
  `[NM] Goblin`.
- Only the letters, digits and signs of plain English can be written.

### Level, checked and aggro

**`[level]`** is not the level of that one monster, because the game does not tell it. It is the
levels that monster can be, such as `5-6`, or `8` where it can only be one level. They come from
WinXI's game data, one table for each area, made from the server's own data. See
[Monster data](#monster-data). For anything the tables do not have (a player, an NPC, a monster the
server makes as it goes), `[level]` writes nothing. What you typed round it is still written.

When you `/check` a monster, the game's answer has its level in it. From then on `[level]` writes that
one level for that monster instead of the range.

- It stays while the monster's body lies there after it dies, with its health bar grey.
- It is forgotten once the body is gone, or the spot is seen alive again.
- It is forgotten when the monster is no longer there to be seen, and when you leave the area,
  because the monster in that spot next time is a different one.
- It is forgotten five minutes after the check, so a long stay in one place does not keep more and
  more. Check again to get it back.
- Nothing is sent to the game for this. The addon only reads the answers to checks you make.
- A notorious monster, which is impossible to gauge, gives no level.

**`[checked]`** writes a magnifying glass for a monster whose level is known from a check, and nothing
for any other. So `[name] Lv[level][checked]` marks levels that are the monster's own, not a range. It
takes a colour like the other tokens. The magnifying glass comes from Ashita's own font. A font you
chose for the names does not have it, so it is drawn from Ashita's font next to your font's letters.

**`[aggro]`** draws a sign for whether a monster is aggressive and how strong it is. The sign is a
quarter taller than the name's letters, with the same dark edge. It comes from the monster tables, so
it is there whether or not you have checked the monster. For what the tables do not have, it draws
nothing. `[aggro][name]` puts it before the name. A colour given to it tints it.

There are twelve signs: six for a monster that is not aggressive, and six for one that is.

| Sign | For |
|---|---|
| First | Level 1 to 19 |
| Second | Level 20 to 37 |
| Third | Level 38 to 56 |
| Fourth | Level 57 to 74 |
| Fifth | Level 75 and above |
| Sixth | A notorious monster, whatever its level, and one your check found impossible to gauge |

The level used is the one your check found, if you checked the monster. Otherwise it is the highest
level the tables say it can be.

## Mob letters

Put `[letters]` in **Enemy Format** where you want a small letter badge. It tells apart monsters that
share a name. There is no separate switch for letters or for double letters. Remove the token to hide
them. `[letter]` still works as an old name for it. Player, pet and NPC names are not affected. All
monsters, targeted and checked ones too, use the same format.

```text
[aggro] Lv [level]. [name] [letters: color=yellow]
[letters: type=double, color=cyan, space=4][name]
```

### How the badge looks

- A filled square with slightly rounded, smooth corners, and the letter cut out of it in uppercase.
  The game scene shows through the letter.
- The letter is always **Arial Bold** (`arialbd.ttf`), whatever font or Bold setting the names use.
  If Windows' Arial file cannot be loaded, Ashita's own default font is used instead.
- The box is about 68% of the name's font height. Its corners are rounded by about 8% of its side.
- The same close-up picture is used at every distance, shrunk smoothly. So the letter keeps its shape
  as you come closer.
- The fill is the name's colour, or the token's own colour. A colour override that is on sets the
  name and letter colour together. By default the badge also follows a `[name]` that has its own
  colour, even when the letter comes before the name.
- The badge has the name's colour and opacity, not the separate opacity of status icons. It grows,
  shrinks and fades with the name, and stays where the token puts it.
- It has the same outline as the name, with the same thickness and colour. The outline goes round
  the outside and round the letter. The middle of the letter stays see-through where there is room.
- If the badge cannot be made, a plain uppercase letter in the same font is used, with no jump when
  the badge is ready.
- No updated plugin is needed.

### How letters are given out

The letters are the same for every player. The addon reads the game's own list of the area's names
from the game files when you enter the area. It groups the list by exact name and puts each group in
a fixed order (by the game's own number for each spot). Then it labels those spawn spots `a` to `z`, and starts again at `a`.

- The first spot is `a`, even for a name with only one spot.
- The list includes spots you have not met or cannot see now.
- So these do not change a monster's letter: entering from another side, meeting monsters in another
  order, checking, deaths, reloading the addon, and respawns in the same spot.
- No addons talk to each other, and nothing comes from a server. Two players with the same game files
  have the same letters, whatever server they are on and whatever version of the addon they have.

The list is where the game takes the name it writes over a monster, so no name is guessed. It is read
through Pivot's overlays (Pivot lets replacement game files be used without changing the originals).
Phoenix keeps its own lists in the launcher's `EraDATs` overlay. They differ from the game's own
files in 48 areas.

The list has every spot the game knows. That includes spots the server leaves empty, and the area's
people. So letters can have gaps (`a`, `b`, `e`) where a server does not use the spots between. A
name with many unused spots wraps past `z` sooner.

**Differences are reported, not fixed.** Sometimes one of the zone's own monsters stands in a spot the
list does not have, or has a different name from the list. Then the addon says so once in the chat
log for that zone visit. It shows the same warning under **Enemy Names** when its format has letters.
Either the server renamed the monster, or the files read are not the ones the game uses. Such a spot
has no letter. Letters are never given out by what one player has met: no player sees a whole zone,
so that would differ between players. Where the file cannot be read at all, there are no letters in
that area, and the settings say why.

**`[letters: type=double]`** goes on after `z`: the 27th spot is `aa`, then `ab`, up to `zz`, in one
wider badge. The first 26 do not change. `[letters]` or `[letters: type=single]` repeats A–Z. The type
is set for each token, so both kinds can be in one format. Only the double badges that are needed are
made. Players who compare letters need the same token type.

These letters label spawn spots. They are not a lasting identity across deaths or separate
instances. After 26 spots with the same name, letters repeat, unless the token uses `type=double`
(then after 702). Monsters that spawn in other ways, and names that do not match their spot, get no
letter: there is no fallback by the order you met them. Players whose game files differ can get
different letters.

## What a check shows

With **Check Details** on, a monster you check gets a second line under its name. It is at the
**Size** you set (90% to begin with), centred under the name. It fades in when you check, stays for
five seconds, and fades out. Check again to bring it back.

In the icon style, a magnifying glass starts the line. It grows with **Size** and fades with the line.
While Check Details is on, a `[checked]` in the name format is not shown again next to the name.

The line can show:

- **How hard the fight is.** Abbreviated to begin with: **TW** (Too Weak), **IEP** (Incredibly Easy
  Prey), **EP** (Easy Prey), **DC** (Decent Challenge), **EM** (Even Match), **T** (Tough), **VT**
  (Very Tough), **IT** (Incredibly Tough) and **???** (Impossible to Gauge). Turn off **Abbreviate
  Difficulty** to get the full names. Even when abbreviating, a difficulty shown with no aggro or link
  details is written in full (for example, Very Tough). Impossible to Gauge stays ???. This is the same
  in both styles.
- **For an aggressive monster, what it notices you by**: a sign for each of sight, true sight, sound,
  low health, magic, job abilities and scent. Whether it is aggressive at all is not shown here: put
  `[aggro]` in the name's format for that.
- **If it links**, the link sign and its family, then Sight, Hearing, or Sight/Hearing, for example
  `Goblin (Sight/Hearing)`. This is worked out from the monster's detection flags; the tables have no
  separate field for how it links. If neither flag is there, the way it links is not written.

With **Text Only**, the line has no icons and no magnifying glass. It is a sentence in parts,
separated by commas:

    TW, Sight Aggro, Link: Goblin (Sight)

- The first part is the difficulty.
- The second part is there for an aggressive monster: what it notices you by (`Sight`, `Sound`,
  `Blood`, `Magic`, `JA`, `Scent`, with a stroke between them if there are several, and `True Sight`
  and `True Sound` for one that sees or hears truly), then `Aggro`.
- The third part is there for one that links. It names the family it links with, and Sight/Hearing
  when that can be worked out from the flags.

The difficulty comes from the game's answer to your check. The rest comes from the monster tables, and
is what the server's own tables say about that kind of monster. For a monster the tables do not have,
there is only the difficulty. The signs for what it notices you by, and for linking, are mobdb's
icons.

## Statuses over a name

To begin with, the icons are drawn the way the winparty and winbuff addons draw them, by **Custom
Icons** in wxi (`/wxi`). With Custom Icons on, the chosen set's icons (FFXIV, to start) are used where
the set has an icon for the status, and the game's icon where it has none. With it off, the game's
icons are used. The set's icons are as narrow as the set makes them; the game's are square. The
**Icons** setting makes this choice for winplates alone.

A name has at most twelve icons, each status once. How much is known depends on whose name it is:

| Whose | What is shown |
|---|---|
| Your own | Everything you are under, as the game has it |
| The five others in your party | Everything they are under, as the game has it, while they are in your area |
| Everyone else | Enemies, other players, the other parties of an alliance, and NPCs: any status the server was seen to say took hold on them, by spell, ability, weapon skill, monster move or added effect. Each lasts the server's base time for what caused it (or 180 seconds where nothing says), until the server says it wore off or was dispelled. Not known: what landed out of sight or before you entered the area, and how gear, merits or a partial resist changed the time |

## Colour overrides

Open **Colour Overrides** under Player Names, Enemy Names or NPC Names. They are off to begin with.
Each state has a checkbox to turn it on and a colour picker. **Use Game Colours** turns off that
category's overrides. It keeps the colours you picked and does not change your formats.

A state that is on colours the name, the letter badges and the health bar fill together. It wins over
colours given to the `[name]` and `[letters]` tokens. Other coloured text and icons keep their own
colours. The game's opacity and fading stay as they are.

The states are the ones the game colours names by:

| Category | States |
|---|---|
| Players (also yourself, pets and trusts) | Normal, Party, Alliance, Looking For Party, Dead |
| Enemies | Unclaimed, Claimed: You / Party / Alliance, Claimed: Others, Call For Help, Dead |
| NPCs | Normal, Dead |

- Each state replaces only the game's colour for that state. A state that is off keeps the game's
  colour. It never borrows another override.
- **Party** and **Alliance** are the other members of your party and alliance. You, your pet and
  everyone else's pets are **Normal**.
- **Looking For Party** is a player whose icons show they are looking for a party (with or without the
  star). The game has no colour of its own for it. With it off, the name is coloured as Normal, Party
  or Alliance would colour it.
- **Dead** comes first, so a corpse or a dead player never keeps a live colour. An NPC counts as dead
  by its status, because the server always gives NPCs full HP.
- **Call For Help** comes next. It lasts while the server's updates say the call stands. It is
  forgotten on the next update without it, when the monster despawns, or when you change area.
- Who owns a monster is not guessed when it is not known.
- Being targeted or in combat no longer has a colour of its own.
- Opacity cannot be set here. A target's name and letters keep a steady opacity. Status icons have
  their own. Fading for corpses, distance and disappearing still happens.

## Cast bars and bar layout

**Cast Bars** (in the Bars tab):

| Setting | What it does |
|---|---|
| **Enabled** | Off to begin with. A bar under a name while its owner casts, filling as the cast goes on |
| **Show Weaponskills** | Off to begin with. Also shows readied monster TP moves and weaponskill names |
| **Text Only For Weaponskills** | On to begin with. Weaponskills and TP moves show only their name and timer, with no bar. Spells keep their bar |

**Cast Text** (the text under the bar):

| Setting | What it does |
|---|---|
| **Font** | **Same as Names** (to begin with), **Default**, or a `.ttf` file in `C:\Windows\Fonts`. It is drawn without Smooth Font's smoothing. Bold follows the names' setting |
| **Show Action Name**, **Show Timer** | Both on to begin with. The spell or move's name, and the time left or the time so far |
| **Text Colour** | **White** (to begin with), **Name Colour**, or **Custom**, which shows a **Custom Colour** picker |
| **Cast Name Size**, **Timer Size** | Each text row's size compared with the name's font: 25% to 200%. 75% to begin with, which keeps the old look. Bar size and name text do not change. The status row moves to fit. Larger text can look softer |

**Preview**, in Shared Bar Settings, shows every bar that is on. With cast bars on, a clearly labelled
moving sample cast runs under the names that are shown. It uses the real bar and text layout, and
switches between spell and TP styles with **Show Weaponskills**. With health bars on, a bar runs under
every name that can have one, emptying and filling. Real actions come first. The preview stops shortly
after you leave the section or window. It resets when winplates is turned off or the settings are
reloaded. It is never saved.

Cast bars only appear on names that are shown, for a character the addon can match to the cast.
**Entity Types** and **Combat Only** only affect health bars.

### Bar size and placement

**Bar Width** and **Bar Height** in Shared Bar Settings are one size for both kinds of bar, so the two
cannot drift apart.

With **Fit To Name** on, health and cast bars both widen to the shown name plus its shown letter
badges, in either order. The saved width is the least they can be. The width covers the name and
letters and the spaces between them. It does not include the action's name, icons round them, the
distance or check details. Both bar rows are centred under the name and letters, and grow together,
with or without a cast. Hidden tokens do not count. A format with neither a name nor letters keeps the
saved width. Text sizes and bar height do not depend on Fit To Name.

With **Fit To Name** off, a cast bar on its own starts exactly where a health bar would. If a health
bar can show, it is above the cast bar, with the same left edge, width and height. While a character
casts, its health bar stays visible even at full health, so taking damage does not move the cast bar.
When nothing is being cast, a health bar at full HP is hidden as usual.

### How a cast bar works

- The cast bar's fill takes the name's final colour, including a colour given to the `[name]` token,
  and its fading. This is the same for spells, weaponskills and the preview.
- It fills from left to right. The action's name and a timer are on two centred lines below it.
- These labels may be wider than a narrow bar, rather than shrink until they cannot be read.
- A status row below the name starts below these labels.
- Bars and labels grow, shrink and fade with the name.
- A character who is casting keeps full details while **Crowd Decluttering** is cutting names down.

The game's message that a cast has started does **not** say how long it will take. So:

- Timers marked **~** are estimates, from the usual spell and monster move times. Fast Cast, monster
  changes, scripts and network delay can make the real time different.
- The messages that a cast has finished or been interrupted always win.
- If the estimate runs out first, a full bar says **Waiting** until the result comes, or until a
  safety time limit.
- If the time is not known, the timer shows **+seconds so far** with an empty bar. No percentage is
  made up.
- A finished or instant weaponskill briefly shows a full bar, its name and **Used**. No ready time is
  made up.
- A finished spell clears at once.
- Tracked casts are cleared on death, despawn, zoning, a change of settings profile, turning off
  winplates or cast bars, and losing the plugin.
- A cast that was already running cannot be picked up if its start was missed.

The usual monster ready times are estimates, made from the Phoenix server's data. They are not values
read from the server while you play.

## Optional readability settings

These two are **off to begin with**. **Crowd Decluttering** is at the bottom of the Visibility tab.
**Distance Thresholds** is at the bottom of the Names tab. They do not move names, change the font
size or change your saved formats. Turn them off to get the normal look back.

### Crowd decluttering

| Setting | What it does |
|---|---|
| **Enabled** | In a crowd, ordinary names are cut down to the name, the monster letters and the aggro sign |
| **Crowd Threshold** | How many names on screen make a crowd: 4 to 200, 20 to begin with |
| **Hold Time** | How long a crowd must last before details are hidden, and how long it must be gone before they come back: 250 to 3000 ms, 750 to begin with |

- It counts the names that would be drawn inside the game window, also with the lens plugin.
- A crowd ends when there are three fewer names than the threshold, for the same Hold Time.
- It is an estimate of crowding. It does not check whether names are hidden behind things or overlap
  each other.

In a crowd, ordinary names keep their name, aggro sign and monster letters, with their own colours and
token conditions. Other text and punctuation, player and vendor icons, stars, check lines, health bars
and status rows are left out. A format you made with no name stays with no name.

These stay fully detailed, at once: your target and sub-target, yourself, your party and alliance,
your own pet, whitelisted and charmed players, and characters seen casting (with Cast Bars on). Names
are never moved, and main names are never hidden, because they overlap.

### Distance thresholds

**Distance Thresholds** colours the `[distance]` tokens you already have when something is far away.

| Setting | What it does |
|---|---|
| **Distance Colours** | Turns the colouring on |
| **Warning Distance** | **Warning Colour** from this distance. 20 yalms to begin with |
| **Danger Distance** | **Danger Colour** from this distance. 25 yalms to begin with |
| **Exit Margin** | 1 yalm to begin with. How far back inside a distance something must come before its colour goes, so the colour does not flicker. 0 is none. It must be less than Warning Distance, so the colour can always clear |
| **Warning Colour**, **Danger Colour** | The two colours. You can change them |

- The colour starts exactly at the distance. A warning only clears below the distance minus the
  margin.
- When the two distances are equal, Danger wins.
- Colours you gave a token or a block come first. Normal name fading still applies.
- Other text and pictures keep their colours.
- The full measured distance is compared, not the rounded number on screen.
- When the distance is not known, no old number or colour is shown.
- It starts over when the character, the settings or the zone changes, or when you turn it on or off.
- These are **distance colours, not a check that a spell or ability is in range**.
- Formats and presets are not changed.

## How names look in the world

Names are drawn inside the game's picture, at the name's depth. So a wall, the ground or a character
in front of a name hides it, or the part it covers, just as it hides the game's names.

Names appear and disappear as the game decides. The game shrinks a name to nothing over the last part
of its distance. winplates instead shrinks it from the largest size to the smallest and fades it out,
or keeps its size and fades it out over the last third.

**Your target's name does not pulse.** The game pulses a living target's name: its colour moves
toward white or dark, and it gets fainter for a moment. In winplates, the target's text, outline,
letters, status icons, layered icons, aggro and check icons and mastery stars all stay at full
opacity. The text keeps the colour the pulse starts from. A colour change that is not the pulse, such
as a monster's name turning red when it is claimed, is shown at once. Letter badges take the name's
colour unless their token has its own colour. Token colours and colour overrides that are on still
apply. Fading with distance still works. This resets when you untarget, on respawn, when the character
slot is reused, or after a gap in drawing.

**Dead monsters.** By default a dead monster's name turns grey at once, even when its `[name]` token
has its own colour. A **Dead** colour override that is on replaces this grey. If the game gives the
corpse a neutral grey, that grey is used instead. Later red or white claim colours cannot recolour it.
The corpse's opacity follows the game, even while targeted, so icons and text fade together. Once the
game says the monster is no longer shown (or it has been removed), what is left of its name fades out
in about **0.2 seconds**, target icons and letters included. The fade does not start just because HP
reaches zero while the corpse is still visible. It is not restarted by late updates, it ends on
respawn, and a character slot reused by a different character at once hides the old label. Missing
data alone does not start the fade.

## Player icon source

**Names → Player Names → Player Icon Source** chooses the pictures for player icons and mastery stars:

- **Game DATs** (to begin with): reads the game's own menu files (DATs), including where each icon is
  and the layered pieces. For XIPivot replacements to be seen, XIPivot's `redirect_fopens` must be
  on. If the files are missing, damaged or not supported, the bundled icons are used. Your saved
  choice does not change.
- **Bundled**: uses `assets/player-icons.png` and its included map of icons, whatever DATs are
  installed.
- **Custom**: loads `addons/winplates/assets/player-icons-custom.png`. Copy `player-icons.png` as a
  starting point. Keep its layout: where each icon sits, in proportion, including the layered pieces.
  A larger picture with the same layout works too. Custom PNGs use normal PNG transparency, not the
  DATs' doubled transparency. If the file cannot load, winplates uses Bundled. Other layouts are not
  supported yet.

The linkshell pearl keeps its linkshell's colour, and two-part icons stay layered. This choice does
not change party and alliance role icons, vendor icons, or monster aggro and sense icons. When a
fallback is used, the settings window says so and gives the reason when you hover over it. Reload
winplates after you change a picture that is already loaded, or after you change Pivot packs.

## Monster data

winplates knows some things about monsters that the game does not say: the levels each can be,
whether it is aggressive and what it notices you by, its family, and which monsters a notorious
monster spawns from. This comes from WinXI's game data, made from the live branch of the Phoenix
server. After a game update nothing needs to be made again: each area's spawn names are read from the
game's own files when you enter it.

## The addon and the plugin

The namehook plugin keeps the list of which names are shown. It can be changed there too: by the
plugin's own command (`/namehook hide players`) or by another addon. winplates and the plugin are kept
the same:

- winplates gives its settings to the plugin when it finds the plugin, when another character's
  settings are loaded, and whenever a setting changes.
- A change made in the plugin is taken into winplates' settings, and saved.

If winplates is unloaded, names stay as they were last set, until the plugin is unloaded.
`/namehook show all` shows them all again. If the plugin is not loaded, the settings window says so.
Your settings are given to the plugin when it is loaded.

## Diagnostics

**Diagnostics** is a section of the General tab. It starts collapsed.

| Control | What it does |
|---|---|
| **Enable Diagnostics** | Turns on detailed recording, for testers. Off to begin with. `/winplates diag` does the same |
| **Names In View** | How many names the game drew last frame, shown and hidden |
| **Support Report** (**Write Report**) | Writes a support report you can share. `/winplates report` does the same |
| **Diagnostic Log** (**Write Log**) | While diagnostics are on, writes a log, as `/winplates diag log` does |

### Support report

**Write Report** makes a summary you can share, with one click. You do not need to turn on
diagnostics. `/winplates report` also works with **Enable winplates** off.

- Reports are saved as
  `config\addons\winplates\logs\winplates-report-<date>-<time>-<sequence>.txt`.
- Nothing is uploaded.
- A report has: the addon, library and plugin versions; what the plugin can do; display and drawing
  counts; the sizes of the font and badge pictures made; which icon pictures are used and whether a
  fallback is in use; how many casts were seen; and how many drawing failures were recorded.
- It leaves out the names of characters, NPCs and monsters, chat, file paths, formats you typed, raw error text and
  history. Failures while reading game files are hidden too.
- Recent failure counts are only there when diagnostic recording was on. With it off, a report still
  shows the current state.

### Diagnostic recording

Detailed recording is off unless you turn it on. It is meant for testers.

```
/winplates diag          turns diagnostics on or off; kept with the character's settings
/winplates diag on|off
/winplates diag log      writes a log now, on or off (with diagnostics off it has no history)
```

While diagnostics are on, the Diagnostics section shows whether winplates is drawing the names
(**Custom Names**).

If winplates stops drawing the names for more than half a second, at any frame rate, the game draws
its own names again. The reason is said once in the chat log, and a log is written, once a session for
each reason:

| Reason | What it means |
|---|---|
| `unloaded`, `old`, `mismatch` | The namehook plugin is not loaded, or is not a version this addon can read. No log is written for `unloaded` |
| `features` | The plugin can be read, but it cannot draw icon outlines on their own. The game's names stay |
| `unhooked` | The plugin did not recognise how this game client draws names |
| `texture` | Ashita's font picture was not ready, or could not be read |
| `draw` | The plugin had no room to draw into |
| `error` | A script error in the frame. It is still shown as before, and kept once in the log with its details and a count |

With diagnostic recording off, no diagnostic history or errors are kept. The support report and the
normal warnings about versions and fallbacks still work.

Logs are small text files in `config\addons\winplates\logs`, named `winplates-<date>-<time>.txt`.
**A detailed log can contain character names, file paths on your computer, your formats and raw
errors.** Use **Write Report** for sharing. Look through a detailed log before you send it.

## Testing pre-releases

A test version is a **pre-release**. Its version ends in `-pre1`, `-pre2` and so on. `/addon list`
and the settings window show it, and GitHub marks it as a pre-release. A pre-release that goes through
a test round with nothing left to fix becomes a **release candidate**, `-rc1`. The namehook plugin in
the winplates zip keeps a plain version number, which `/namehook` reports.

When you test one, send:

- the **Write Report** file (`/winplates report`, written to `config\addons\winplates\logs`, with
  nothing private in it);
- a screenshot, if the problem is how something looks;
- the lines of Ashita's log around any error;
- which pre-release you used: the version in `/addon list`.

## Settings from older versions

Old settings are brought into the new ones once, when the addon loads:

- **Player icons:** the old icon visibility, size and spacing become `[icons]` options in Player
  Format.
- **Party Icons** (1.66 and before): Beside becomes `[party: space=2]` before `[icons]`. Replace
  becomes `[party: replace, space=…]` with the icons' spacing. Off becomes no token.
- **Vendor Icons** (1.66 and before): if it was on, it becomes `[vendor: space=N]` (N its old
  spacing) at the start of NPC Format.
- **Show Monster Distance** (1.9 and 1.10): becomes `[distance]` in the monster format.
- **Health bars:** the old separate settings became one set. Bars are on if any old category had them
  on. The size is taken from the first old category that had bars on, in the order Enemy, Player,
  NPC (Enemy if all were off). This is never done again after later edits.
- **Mob letters:** the old automatic and double-letter settings become `[letters]` tokens. Tokens you
  remove later are not added back.
- **Enemy formats** you already have are kept. **Reset** puts back `[aggro] [name] [letters]`.
