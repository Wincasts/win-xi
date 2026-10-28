# name

Up to 1.5 this addon was called nametoggle. Its settings were kept under that name. To keep them, copy
the folder `config\addons\nametoggle` to `config\addons\name` before you load the addon.

Shows and hides the names over characters' heads, by what kind of character they are over. It is a
settings window for the `namehook` plugin, which does the showing and hiding. The plugin has to be
loaded.

```
/load namehook
/addon load name
```

- `/name`: opens or closes the settings. It is the only command, apart from `/name diag` (see
  [Diagnostics](#diagnostics)). Anything else after it only brings up this help. Use Visibility to choose which names appear. Unload Name to get the game's names back.

## Settings

The format token reference under each kind of name's Format Tokens can be edited in
[`tooltips/name.md`](../../tooltips/name.md) (`name.format.*`); see the
[editing and build instructions](../../tooltips/README.md). Every other sentence is written
in the settings code itself.

The preferred baseline is in `name_defaults.lua`. It is taken from the author's own settings.
It uses **trebucbi.ttf**, not bold, maximum/minimum font sizes **30/10**, the sub-target's
name at **125%**, **90% check size**, **90% icon size**, **4 px icon spacing**, **1 px outline**,
a hunted monster's name at **120%**, and health bars (off) **120 × 7 px**. Statuses are
**100%**, level with the name's left and moved **2 px right and 5 up**, with fewer ticked:
2–8, 10–13, 19, 132–135, 156, 192, 194 and 217. Difficulty abbreviations and check details
are on. Mastery stars and words mode are off. Own Name is hidden, Other Players and
Other Pets are shown. Always Show Target is off. Players' **Normal** (pale blue) and
**Alliance** (amber) Colour Overrides are on. Appearance and hide preferences are captured too.
Settings a character already has win over this baseline.

Settings are kept for each character. Each one is on for names that are shown.

The settings are winxi's described rows: named sections, each setting a name with a
sentence under it saying what it does, and its control at the right. No help marks or tooltips.

The tabs are **General → Names → Bars → Check Details → Statuses → Visibility**, and
**NM Tracking** after `/name dev`. Each part a name can have (health bars, cast bars, check details,
statuses) is turned on and off in its own section, with **Enabled** at the top. Health and cast bars
share the **Bars** tab.

- **General:** **Enable Name** first, then **Preset**, a premade look to start from.
  A preset sets the three formats, the check line, Health Bars and Combat Only, Status Icons and
  Check Details. Font, sizes, colours, visibility and the chosen statuses are left as they are. The
  list says **Custom** when the settings match none of them.

  | Preset | Players | Enemies | Bars | Status icons | Check details |
  |---|---|---|---|---|---|
  | Default | `[party: space=2][icons: space=4][name]` | `[aggro] [name] [letters]` | Off | On | On |
  | Minimal | `[name]` | `[name]` | Off | Off | Off |
  | Robust | `[party: space=2][icons: space=4][name]` | `[aggro: space=4]Lv [level]. [name] [letters] ([distance: decimals=1]y)` | Always | On | On |
  | Immersive | `[party: space=2][icons: space=4][name]` | `[name]` | In combat | Off | Off |

  NPCs are `[vendor: space=4][name]` in each preset but Minimal, where they are `[name]`. **Enable Name**
  is at the top of General and on to begin with. It means Name draws the names. Turn it off and
  Name lets them go at once. The game then draws its own names, at the size namehook gives them
  (`/namehook fontsize`), unstretched. Visibility still says which are shown. Name's health bars and
  status icons are not drawn while it is off. All other Name settings are greyed out across the tabs
  until you turn it on again. Saved values are kept.

- **Rendering readability:** namehook **1.32** adds a smoother eight-direction text
  halo with a soft downward shadow, and antialiased HP-bar edges that stay smooth
  under Lens counter-transformation. Nearby font size, name placement, colours and
  format strings do not change. Small names keep more outline contrast. Install
  the updated `namehook.dll` as well as Name and WinXI. Older plugins still draw
  bars, but with their old hard edges. Outline 0 still turns off the halo and shadow.
  Letter badges also use a 4×4 area-sampled box/cutout mask and a transparent
  texture guard, so filtering can smooth their straight sides as well as their rounded
  corners. The guard does not count in the visible size, text advance or baseline.
  Single and double badge spacing, tint and nameplate centring do not change. This
  badge pass is built once per cached atlas, not every frame, and needs no
  plugin update beyond the halo changes above. Name text still uses its existing
  glyph atlas by default. **Smooth Font**, beside **Bold**, is optional. It builds a cached
  atlas by area-averaging a 4× glyph raster down to native drawing pixels at each
  existing distance-size rung. Transparent guards allow edge filtering without
  changing the normal font's bearings, advances or baseline. Bold stays independent.
  Icons and badges keep their existing rendering. Text uses the existing font texture
  slot, with its own white tile for HP bars. Source-font icons and missing glyphs
  keep the original texture in the sign slot, so no extra texture slot is needed.
  It is off by default, so you can compare. Smooth mode uses more atlas memory and can soften
  very small text. Builds wait one stable frame for the source upload. They are cached
  until the font, size, source texture or glyph UVs change. While a build is being prepared, or after
  a build fails, direct glyph rendering is used instead. Failures are reported once and
  retried at most once a second while the source is unchanged. Switching Smooth Font off
  releases Name's generated texture and high-resolution glyph-cache handles.
  Switching it back on builds a fresh atlas. ImGui owns the shared source atlas
  and may keep that allocation until it reclaims or rebuilds it. No further plugin
  update is needed for filtered text.
  **Text Outline Opacity (%)** (0–100, default 100%) softens the outline round text alone (names,
  levels, distances, check details and cast text), as Icon Outline Opacity does for icons.
  **Icon outlines** have their own **Icon Outline (px)** (0–3) and
  **Icon Outline Opacity (%)** (0–100) controls. The defaults are 1 px and 100%. They apply
  the same way to player, party-role, vendor, aggro/passive, sense and check icons.
  Text Outline 0 no longer turns off icon outlines. Either icon control at zero
  turns off only icon edges. Fills, layout, colours, mastery stars and letter
  badges are not affected. Width follows the existing resolution and distance scaling;
  small names may use a thinner edge. Aggro/passive and tracked-monster glyphs
  still have no shadow, but now follow the width you chose instead of a fixed cap.
  Name 1.64 needs **namehook 1.35** and **WinXI 47**. A capability check stops
  older ABI-compatible plugins from silently ignoring the independent width. Plugins that do not
  support it keep the stock names and visibility controls, with a warning to update.
  `./deploy.sh push name` includes changed WinXI and the built DLL before Name;
  reload every addon that uses WinXI, plus namehook. Deployment still asks for confirmation
  and makes backups. Nothing is compiled or written live while developing.
- **General Name Appearance:** the shared Font, Bold, Maximum/Minimum Name Size,
  Subtarget Size, Letter Spacing, Text Outline, Text Outline Opacity, Icon Outline and Icon Outline Opacity. One maximum/minimum pair applies to every entity type,
  including players, pets, enemies and NPCs.
- **Player Names:** a **Player Format** you edit directly. Player
  icons go inline through `[icons]` instead of a separate checkbox. The format applies to your
  own name, other players and player-style pets and trusts.
  Default: `[party: space=2][icons: space=4][name]`. Leave out `[icons]` to hide icons, or move it anywhere
  in the string. The old icon visibility, size and spacing are brought over once.
  `[party]` draws a sign of each party and alliance member's place: Alliance Leader, Party Leader,
  another party's leader (Alliance Party Leader), Alliance Member or Party Member, from
  `assets/special/`. `[party: replace]` also leaves out the game's icons for a member who has the
  sign. Players outside your party and alliance keep the game's icons. There is no sign while you
  are alone. Who leads is read from the party's memory. The Party Icons setting of 1.66 and before
  is brought into the formats once: Beside as `[party: space=2]` before `[icons]`, Replace as
  `[party: replace, space=…]` with the icons' spacing, Off as no token.
- **Enemy Names:** an **Enemy Format** you edit directly. Enemy strings you already have are kept.
  Reset puts back `[aggro] [name] [letters]` for ordinary, targeted and
  checked enemies alike.
- **NPC Names:** an **NPC Format** you edit directly, for non-combat NPCs. It does not depend on
  the player or enemy formats. Default: `[vendor: space=4][name]`.
  `[vendor]` draws a coin (`assets/special/vendor.png`) where it is, for every NPC that sells: gil
  shops, guild merchants and outpost vendors. For any other NPC it draws nothing, with no space. The list is
  the chosen server's `vendors` set (winxi's data), by area and name, made from its NPC scripts by
  `tools/build_name_vendors.py`. The Vendor Icons setting of 1.66 and before becomes
  `[vendor: space=N]` (N its old spacing) before the NPC format once, if it was on.
- Each format has its **Reset** as the row after the editor. **Format Tokens**, a sub-section
  that starts collapsed, lists every token that kind of name can have, an example format and its
  result. The token options are under [Token options](#token-options). Player and NPC
  formats have `[name]`, `[icons]` and `[distance]`; players have `[party]` too, and NPCs `[vendor]`.
  Enemy formats have `[name]`,
  `[level]`, `[aggro]`, `[checked]`, `[letters]` and `[distance]`. There are no Help /
  Examples dropdowns: what they said is under Format Tokens.
- **Bars**, one tab for health and cast bars. **Shared Bar Settings** comes first: **Bar Width/Height**
  for HP and cast rows alike, **Fit to Name** (both kinds as wide as the name) and **Preview** (every
  bar that is on is shown under the names while the section is open). Then **Health Bars**: **Enabled**,
  **Combat Only**, for every type including pets, trusts and NPCs, with
  **Health Bar Entity Types** after. HP bars need valid live HP and server-ID data. An entity at full
  health has no bar, unless an active cast needs the HP row above it. Combat Only needs that
  particular entity to be alive and Engaged (status 1); targeting or claiming alone is not combat. Then
  **Cast Bars** (**Enabled**, Show Weaponskills, Text Only for Weaponskills) and **Cast
  Text** (with its own Font). The shared settings wait until either kind is on. See
  [Cast bars and shared bar layout](#cast-bars-and-shared-bar-layout).
- **Check Details**, a tab of its own: **Enabled**, Size, Abbreviate Difficulty and Display Style
  (Icons & Text / Text Only), greyed out while it is off. See [What a check shows](#what-a-check-shows).
  **Entity Types** under it says which kinds of name have a bar: Yourself, Party
  Members, Alliance Members, Other Players, My Pet, Other Pets, NPCs and Monsters,
  all ticked to begin with.
- The name sizes in General stay the ones that count. Health bars were brought into one set of settings
  once: on if any old category had bars on, with the size taken from the
  first old category that had them on, in **Enemy → Player → NPC** order (Enemy if all were off).
  The old per-type bar tables are then let go of. Shared
  settings are never brought over again during later edits. Diagnostics stays collapsed.
- Each format section has **Colour Overrides** that you can expand. They are off by default.
  A state that is on applies its RGB to the name, spawn letters and matching
  HP fill together, and wins over explicit name and letter token colours. Other coloured
  text and icons keep their own explicit colours. The client's opacity and fades stay as they are.
- **Visibility:** Players, Pets, NPCs & Monsters, and Target. No diagnostic controls.
- **Statuses:** Display, Entity Types (the same eight kinds of name as for health
  bars, all ticked to begin with) and Selected Statuses, with help about
  status sources that you can expand.
- **NM Tracking:** Tracked Monster and, when they apply, Placeholder Options. The tab is
  shown only after `/name dev`, until the addon is reloaded; `/name dev` again hides it.

Format token references and examples are under each kind of name's Format Tokens.
Settings a character already has are kept.

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
| Always Show Target | Your target's name is shown even when names like it are hidden. Your own is not: with Own Name off it stays hidden while you have yourself targeted |

A name over someone under Invisible is never drawn, whatever the settings above say. This includes the
target and whitelisted players. Who is invisible is read from the server's updates (another player's
0x0D, your own 0x37), so someone who is already invisible when Name is loaded keeps their name until their
next update. With Enable Name off the game draws its own names, and this is left to it.

Names In View, under General → Diagnostics, counts the names shown and hidden last frame.
Diagnostics is collapsed by default and has an Enable Diagnostics checkbox.

## Custom names

Enable Name in General chooses between Name's own drawing and the game's own names.
The Names tab sets up WinXI text, in the game's colours, with icons wherever
`[icons]` appears in its format. Visibility still decides which names are shown.
Name's own drawing needs namehook 1.35 or newer and WinXI 47 or newer.
Turning Name off, losing the plugin, reloading settings or changing profile releases the
generated atlases and file textures Name owns. Cleaning up twice does no harm. Unloading the addon also
invalidates the last submission and gives up the claim before releasing textures,
including textures the plugin has not yet consumed. ImGui still owns its shared font atlas.
The draw buffer and cached DLL writers are invalidated before the GPU owners are freed,
so a texture released before the plugin's first scene cannot leave a stale pointer.
Removing `[letters]` releases the cached badge texture. Rebuilds
release replaced badge atlases promptly rather than waiting for Lua GC.

| Setting | What it does |
|---|---|
| Bars → Health Bars → Enabled | Off by default. Shows a bar in the name's colour under damaged names of every type when HP is available. Full-health names have no bar. Bars follow visibility and fading, and leave room for check details and statuses |
| Bar Width / Height (px, Bars → Shared Bar Settings) | One pair for the HP and cast rows of all types: the bar's size under a name at its largest. It shrinks with the name as the name goes further away, and grows with a hunted or sub-targeted one. Defaults to **60 × 6 px**, including the border. Width: 12–300; height: 3–40. Saved per character |
| Bold | Makes names and check-detail text heavier. Each letter is drawn twice, a pixel apart. On in the preferred defaults; icons and stars do not change |
| Smooth Font (beside Bold) | Off by default. Uses a cached, area-filtered text atlas made from 4× rasterised glyphs, with transparent edge guards. The native layout metrics and Bold's one-pixel stroke are kept; icons and badges do not change. It uses more atlas memory and has a one-time build cost. Direct rendering is used while it is being prepared or is unavailable |
| Bar Texture (Bars → Health Bars, Cast Bars) | What the bars are drawn in, each kind its own: **Plain** (the dark-bordered bar, to begin with) or one of WinXI's Bar Textures, party's HP art, tinted the name's colour. Drawn from a sheet Name makes of the sets in use and its own signs, at full, half and quarter size, so small bars stay clean. The fill's end is softened with namehook 1.37. Art that will not load leaves the bar Plain |
| Preview (Bars → Shared Bar Settings) | For this session only: every bar that is on is shown while the section is open. Each name that can have a health bar shows one, emptying and filling again, at full health and out of combat too (Entity Types still apply). With cast bars on, a sample cast runs under the names. Never saved |
| Combat Only (Health Bars) | Off by default. Needs each entity's own Engaged status (1) and HP above zero. Missing or invalid data hides the bar. Applies to players, enemies, pets, trusts and NPCs |
| Maximum Name Size (px, General) | The shared text height when near, 6–48 pixels, for every entity type. It does not depend on the bar size |
| Minimum Name Size (px, General) | The shared text height when far, for every type, never more than the maximum |
| Subtarget Size (%) | The size of the name under the sub-target cursor (`<st>`, `<stpc>`, `<stnpc>` and the like) while you choose, 50% to 200% of the others'; 100% to begin with. The game's own changes to that name's size as the choice begins and ends are ignored, at any setting, so it changes size once each way. Above 100% its letters are the largest size's drawn larger, so they are slightly softer |
| Letter Spacing (px) | Extra space between the letters of every name, 0 to 10 px at the name's largest, shrinking with it as it goes further off; 0, the font's own spacing, to begin with. Applies to everything written in the format line, typed text included. A `[name]`, `[level]` or `[distance]` token's `spacing=` sets its own. Icons, signs, letter badges, check details and cast text are not spaced |
| Outline (px) | The dark edge round each name, 0 to 4 pixels, rounded down to whole render-target pixels to keep nearby names thinner. As letters shrink it becomes thinner and slightly less opaque, so distant names stay readable. Nearby names keep the original outline. At 0 the names are written plain |
| Font (experimental) | A font of Windows' own, chosen by its file in `C:\Windows\Fonts`. Default is the font everything else is written in |
| Player Format | How player-style names are written. NPCs and enemies have their own formats. See [How a name is written](#how-a-name-is-written) |
| NPC Format | How non-combat NPC names are written, apart from players and enemies |
| Enemy Format | How an enemy's name is written |
| `[icons]` | The game's player icons at this position in the string. Leave it out to hide them. Mastery stars are separate |
| `[icons: size=90, gap=2, space=4]` | Icons at 90% of name height, with 2 px between icons and 4 px after the group. No spacing is reserved when there are no icons |
| `[space]`, `[space: 8]` | A gap of its own, 4 px or as many screen pixels as given (0–64, `size=` the same), only between two things that are written: none at either end of the line, nor beside a token that writes nothing. `[icons][space: 4][name]` is `[icons: space=4][name]`: an icon token followed by a `[space]` gives up its own spacing |
| Check Details → Enabled | Under the name of a monster you have checked: how hard a fight it is, what it does, and what it links with. See [What a check shows](#what-a-check-shows) |
| Check Details → Size (%) | Scales check-detail text and icons from 50% to 125% of the name size; 75% in the preferred defaults. Applies to either layout |
| Abbreviate Difficulty | On by default: TW, IEP, EP, DC, EM, T, VT and IT next to the aggro and link information. A difficulty on its own uses full words; Impossible to Gauge stays ???. Off puts back the full difficulty names in either layout |
| Display Style → Text Only | A sentence without icons, such as `TW, Sight Aggro, Link: Goblin (Sight)`. Available while Check Details is on |
| Show Mastery Stars | The three stars over the name of a player with a job mastered |

### Cast bars and shared bar layout

In **Bars → Cast Bars**, turn on cast bars (off by default). When they are on,
**Show Weaponskills** also turns on readied monster TP moves and weaponskill names;
that option starts off too. With it, **Text Only for Weaponskills** (on by default)
shows weaponskills and TP moves as their name and timer alone, with no bar. Spells
keep theirs.

**Bars → Cast Text** holds the text under the bar: **Font** (Same as Names to begin
with, Default, or a .ttf of `C:\Windows\Fonts`; drawn without Smooth Font's filtering, with Bold
following the names'), **Show Action Name** and **Show Timer** (both on), **Text Colour** (White by default, Name Colour, or Custom
with a colour picker), and **Cast Name Size (%)** and **Timer Size (%)**, which
scale the two text rows on their own, relative to the nameplate font (25–200%,
default **75%**, which keeps the old look). The bar size and nameplate text do not
change. The status anchor follows the resized captions. Upscaled text can look softer.

**Preview**, in Shared Bar Settings, shows every bar that is on. With cast bars on, a
clearly labelled animated sample cast runs under visible names, using the real bar and caption
layout, and switching between spell and TP styles with Show Weaponskills. With health bars on, a bar
runs under every name that can have one, emptying and filling. Real actions come first.
Samples send no packets and make no observed actor records. The preview stops shortly after you leave the
section or window, and resets when Name is turned off or the profile is reloaded. The switch is never saved.

Cast bars apply to visible names with a matching live
entity identity. The Entity Types and Combat Only controls still filter
HP bars only.

**Shared Bar Settings**, at the top of the Bars tab, holds one **Bar Width / Bar Height** pair for
both kinds of bar. They reuse the saved `healthBarWidth` / `healthBarHeight` values, so
there is no separate cast-bar size to drift out of line. **Fit to Name**
(off by default) widens health and cast bars alike to fit the visible **entity name plus visible letter
badges**, in either token order. The saved width stays as a minimum. It measures the
span of the name and letters, including the spaces between them, not the action caption, the
icons around them, or the distance and check details. Both bar rows are centred under that span and grow
together, with or without a cast.
Hidden tokens do not count. A format with neither name nor letters keeps the saved
width. The text-scale controls and bar height do not depend on auto-width.

With Fit to Name off, a cast bar on its own starts at
exactly the existing HP-bar origin. If an HP row that can show is on, HP is above the
cast, with the same left edge, width and height. While casting, the HP row stays
visible even at full health, so taking damage does not move the cast row. Away from
casts, the hide-at-full-HP behaviour is as before.

The cast-bar fill takes the **resolved entity-name colour**, including an explicit
name-token colour and fading, for spells, weaponskills and previews alike. It fills
forward, with the **action name** and a **timer** on two centred
lines below it. Labels may extend past a narrow bar rather than shrink to unreadable
text. Below-name status rows start below these labels. Bars and labels take the
nameplate's scaling and fading, use the existing font atlas, and need no new texture slot.
Active casters stay fully detailed in crowd mode.

Start packets do **not** include the effective cast duration. Timers marked **~** use
estimated base spell and monster-preparation timings; Fast Cast, mob modifiers, scripts
and network timing can change reality. Finish and interrupt packets come first.
When the estimate runs out first, a full bar says **Waiting** until the result or a
bounded safety timeout. Unknown timings show **+elapsed seconds** with an empty bar,
not an invented percentage. Completed and instant weaponskills briefly show a full bar,
the observed name and **Used**, never a made-up ready phase. Completed spells
clear at once. Death, despawn, zone and profile changes, turning off Name or cast bars, and
plugin loss clear tracked actions. Actors are keyed by server ID, checked against
live entity identity, and limited to 256 records. A cast already running cannot be
picked up if its start packet was missed.

Base mob ready times are made from Phoenix SQL (estimates, not runtime overrides):

```sh
python3 tools/build_name_cast_times.py --server references/Phoenix
```

### Optional readability policies

Both additions are **off by default**: Crowd Decluttering at the bottom of the Visibility tab,
Distance Thresholds at the bottom of Names. They do not move plate anchors,
change the font size or touch saved formats. Turning them off puts back the normal look.

**Crowd Decluttering** counts wanted, positive-scale, nontransparent anchors that project
inside the output window (including Lens projection). The default entry threshold is **20 names**,
with **750 ms** of steady crowding before it simplifies. To exit, there must be three fewer names,
held for the same time. This is an estimate of crowding. It does not detect occlusion or
overlaps between individual rectangles.

Ordinary plates keep their name, aggro cue and monster letters, including explicit colours
and token conditions. Secondary text and punctuation, player and vendor icons, stars, check lines,
HP bars and status rows are left out. A format made name-less on purpose stays name-less.
Your target and subtarget, yourself, party and alliance, your own pet, whitelisted and charmed players,
tracked NM and placeholders, and observed active casters (with Cast Bars on) stay
fully detailed, at once. Plates are not moved or core names hidden because of
overlaps. Font warming does not change.

**Distance Thresholds** colour the `[distance]` tokens you already have: warning at **20 y**, danger
at **25 y**, with colours you can edit and a default **1 y** exit margin. Entry happens at the
threshold; a warning clears only below its threshold minus the margin. The margin must be
less than Warning Distance, so clearing stays reachable. Danger wins when the thresholds are equal.
Explicit token and block colours come first, and ordinary nameplate fading still applies.
Other text and artwork keep their colours. Comparisons use the full measured distance, not the
rounded display text. Invalid or unavailable distances show no stale digits or highlights.
State resets on identity, settings/enable and zone changes. These are **distance thresholds,
not guaranteed spell/ability range checks**. Formats and presets are not rewritten.

### Rendering optimizations

Text layout is cached by string and font-size set, including glyph advances and
positions. The Bold switch also invalidates cached advances when its value changes.
Simulated bold adds a shifted copy of each visible text glyph, with the spacing adjusted to
match. It uses more quads when on, but does not thicken the outline or
change the shared ImGui font. If you prefer a font's designed bold face to simulated bold, choose
a bold font file directly instead. Each set keeps at most 512 runs. A font or atlas replacement makes new
sets, so stale texture coordinates are not reused. Distance text still updates to
a tenth, but unchanged text does not need decoding and measuring every frame.

Each entity is listed once by namehook, even where the client draws its name more than once in a
frame (a player who is fishing). The addon lays out every listed name it is given and no other.

The shared drawing buffer checks its capacity per quad instead of reserving 256 slots
for every name, so short names can safely use the last slots left.
Font-size rungs are also cached until the maximum height changes, with the size setting or the window.
The letters kept for the old heights are let go then, so dragging a window's edge does not leave a
set behind for every height it passed through. Empty format parts skip the run-cache work, and check-detail layout uses no temporary
width table.

Nothing asked every frame (the frame itself, a format's lookup, the letter badges' lookup) makes a
function inside itself, which LuaJIT cannot compile. What does is kept apart and called only when
something has changed. Statuses read the player's and the party's status icons only in a frame in
which a name needs them.

Letter badges keep their A–Z definitions on the close-up font set. Warm frames only
probe the font for atlas movement. They do not reread all 26 glyphs or serialize the
badge cache key. Replacing the font set invalidates these immutable definitions,
while the stable-frame delay and bounded texture retries stay in place.

Run the Linux synthetic CPU/allocation check with:

```sh
luajit tests/harness.lua name addons/name/name.lua tests/name_performance_check.lua
```

It tests 0, 32, 128 and the plugin maximum of 256 names with letters off and on, checks that warm frames do no
badge texture readback or upload, and reports time and allocations per frame. These
are mocked addon-side measurements, not in-client GPU timings. Set
`NAME_BENCH_FRAMES` to change the timing sample count (default 500).

The updated plugin caches complete name bounds and skips vertex expansion and draw
submission for names fully outside the viewport. A name with an off-screen anchor
is still drawn if any of its text, icons, stars, outline or details can be visible.
This does not change the ordering or depth passes of visible names.

Inline aggro and magnifying-glass icons, and the check line's sense and link icons,
use about 25% less outline opacity than text. Their fill does not change.
Player-name icons use the same softened outline, including the base and small
badges of composite status icons. Composite badges keep the exported font-shape
size and offset: the seeking-party variant's star badge is half-size at the upper left,
not a full-size star over the icon. Plain seeking-party status has no added badge.
These status badges are separate from the three job-mastery stars, which still have no outline. Outline Thickness 0 turns off all of these
outlines. This per-quad effect needs the
updated plugin as well as `libs/winxi`.

### How a name is written

Edit **Player Format**, **Enemy Format**, or **NPC Format** directly in the matching
section of Names. Player and NPC formats take `[name]`, `[distance]`, `[icons]` and colours, Player
Format `[party]` and NPC Format `[vendor]`. Enemy Format also takes `[level]`, `[aggro]`,
`[checked]` and `[letters]`.
Enemy Format applies to every mob nameplate,
including targeted and checked mobs. Checking a mob still updates
its known level and check-detail line. Targeting still works as usual.

The format is what counts: `[level]` and `[aggro]` show whenever they are present, and
leaving them out hides that information. There are no separate level or aggro switches.
Typed labels and punctuation stay exactly as typed, so remove `Lv ` and its dot
as well if you do not want that label. Check-detail icons are separate (Check Details
→ Display Style → Text Only).

### Experimental: tracked notorious monster

This feature is experimental. It has a tab of its own, **NM Tracking**, shown after `/name dev`. **Tracked NM** there lists
the notorious monsters of the area you are in
(and None). The one you choose, and each of its placeholders, has `assets/special/hunt.png` (one of `assets/special.png`'s signs, with the vendor coin and the party icons) drawn in place
of its `[aggro]` icon, so it needs `[aggro]` in Enemy Format. The choice is kept by name when you leave the
area, and does nothing elsewhere.

**Target Size (%)** (100–200%, shown while a monster is tracked) makes the tracked monster's
whole nameplate larger at every distance. Its placeholders stay the usual size. Above 100% the letters are
the largest size's drawn larger, so they are slightly softer.

When the tracked monster has placeholders, **Label Placeholders** appears (on by default): each
placeholder's `[name]` is written as `Placeholder`. The rest of its nameplate, its level and letter
included, does not change. Placeholders are the members of the monster's lottery slot in the server's
zone data (or, for the few that still have one, its script's `phList`), from winxi's game data
(`winxi.mobs.Placeholders`; see [Monster data](#monster-data)). A monster that appears some other
way than through a placeholder (timed, forced or scripted spawns) has none listed.

### Statuses over a name

The **Statuses** tab puts a row of status icons above or below a name, for the statuses ticked there and no
others. To begin with the icons are drawn as the party and buff addons draw them, by Custom Icons in winxisettings
(`/wxi`). With it on, the chosen set's icons (FFXIV, `libs\winxi\statusicons\ffxiv`, to start) are used where the set has an
icon for the status, and the game's where it has not. With it off, the game's icons are used. `libs/winxi` has to be deployed
with its `statusicons` folder. The set's icons are as narrow as the set has them; the game's are square.
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
| Preview | Puts the first four ticked statuses over every name that is shown, whatever it is really under, so you can see how the row looks. Not kept: off again when the addon is loaded |
| Search | Narrows the list under it by part of a status's name, or its number |
| Selected Only | Lists only the ticked statuses |
| The list | Every status the game has a name for, by name with its number. It leaves out the game's stand-ins, (None), (N/A), (Imagery) and the like, whose names are wholly in brackets, and the numbers the server has no status for. Hover over one to see its icon. Ticked to begin with: what ails a character, and what can be told of an enemy |

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

### Monster data

What name knows of monsters that the game does not say (the levels each can be, whether it is
aggressive and what it notices you by, its family, and which monsters a notorious monster is drawn
from) is winxi's, in `addons/libs/winxi/data`, read through `winxi.mobs`. Until 1.50 it was in this
addon's `data` and `placeholders` folders. It is made from the live branch of the Phoenix server on
GitHub, never from a local copy:

```sh
python3 tools/build_winxi_data.py
```

That fetches the branch's newest commit into `.cache/phoenix-live`, makes every set again and writes
`data/manifest.lua`, which says the commit it was made from. Deploy `libs/winxi` afterwards. It needs
PyYAML and luajit. After a client update nothing needs to be made again: each area's spawn names are read
from the game's own files as you enter it.

### State colour overrides

Open **Colour Overrides** under Player Names, Enemy Names or NPC Names. Each state
has a checkbox to turn it on and an RGB picker. **Use Game Colours** turns off that category's
overrides without losing the picker colours you chose or changing the format strings.

The states are the ones the game colours names by:

| Category | States |
|---|---|
| Players (also yourself, pets and trusts) | Normal, Party, Alliance, Looking For Party, Dead |
| Enemies | Unclaimed, Claimed: You / Party / Alliance, Claimed: Others, Call For Help, Dead |
| NPCs | Normal, Dead |

Each state replaces only the game's colour for that state. One left off keeps the game's
colour, and never falls back to another override. Party and Alliance are the other members of
your party and alliance; you, your pet and everyone else's are Normal. **Looking For Party** is a player whose
icons show they are seeking a party (with or without the star). The game has no colour of its
own for it, so with it off the name is coloured as Normal, Party or Alliance would colour it. **Dead** comes first,
so a corpse or a dead player never keeps a live colour. An NPC is dead by its status, since
the server always gives NPCs full HP. **Call For Help** comes next. It is read from the
entity update (0x0E), whose flags have 0x20 while the call stands, and is forgotten on the
next update without it, a despawn, or a change of area. Claims use validated entity IDs and
active party and alliance server IDs; unknown ownership data is not guessed. Being targeted or in
combat no longer has a colour of its own. Opacity cannot be set here: a target's name
and letters keep a steady opacity, status icons stay independent, and
corpse, distance and disappearance fades still apply.

### Experimental mob letters

Add `[letters]` to Enemy Format wherever a compact rounded letter badge belongs.
There is no separate switch for it or for double letters. `[letter]` still works as an old alias.

```text
[aggro] Lv [level]. [name] [letters: color=yellow]
[letters: type=double, color=cyan, space=4][name]
```

The badge is a filled square with slightly rounded, antialiased corners and an **uppercase,
transparent letter cutout**. The letters always use **Arial Bold** (`arialbd.ttf`), whatever
the nameplate font or Bold setting, to match the clean sans-serif
style in `references/letter_example.png`. The box is about 68% of the nameplate font height, with a corner radius of about 8% of its side.
All distances use the same close-up badge artwork, scaled down smoothly rather than switching
to smaller letters rasterized separately. This keeps the letter's shape the same as you approach.
The game scene shows through the letter. The fill uses the nameplate colour, or the explicit
token colour, unless a state override that is on sets their joint colour. By default it also follows an explicitly coloured `[name]`, even when the
letter comes before it in the format. Letters share the name text's colour and opacity, not
the separate status-icon opacity. The whole badge scales and fades with the nameplate and
keeps its saved token position. The badge uses the same
outline effect as the nameplate, including its thickness and colour. This outlines both the
outside edge and the letter cutout; the cutout's centre stays transparent where the outline
leaves room. Size and indicator-atlas changes rebuild the cached badge atlas; unchanged frames reuse
it. If the texture cannot be prepared, an uppercase letter in the same fixed font is used instead,
and preparation is retried once a second. This plain fallback shares the badge's name-font
lowercase baseline, so there is no vertical jump as the badge atlas becomes ready.
If Windows' Arial file cannot be loaded, the regular
ImGui default font is the fallback. No updated plugin DLL is needed.

Remove the token to hide letters. Player, pet and NPC nameplates are not affected. All mobs, including targeted and checked mobs, use the same format.

**Consistency across users:** the addon reads the game's own list of the area's names from the client's
files as you enter the area (winxi's `zone_names.lua`; the letters are winxi's `mob_letters.lua`, which party
uses too). It groups the list by exact name, sorts each group by stable
entity index, and labels those spawn slots `a` through `z`, then wraps to `a`. The first slot is `a`,
even for a name with only one known slot. It includes slots you have not met or cannot
see right now. So entering from a different side, a different draw or encounter order, checking, deaths, addon
reloads and respawns in the same slot do not renumber mobs. No addon communication is needed,
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
zone visit, and shows the same warning under Enemy Names when its format includes letters: the server has renamed it, or
the files read are not the ones the game uses. Such a slot has no letter. Letters are never renumbered
from what a client has met: no client sees a whole zone, so that would differ between players. Where
the file cannot be read at all there are no letters in that area, and the settings say why.

**`[letters: type=double]`** carries on after `z`: the twenty-seventh slot is `aa`,
then `ab`, up to `zz`, in one wider badge. The first 26 do not change.
`[letters]` or `[letters: type=single]` repeats A–Z. Type is per token, so both
kinds can appear in one format. Only the double badges that are needed are made. Players
comparing letters need the same token type. Old automatic and double-letter settings
are made into explicit tokens once, and tokens removed afterwards are not added back.

These are labels for spawn slots, not unique identities across deaths or separate instances. After 26
same-name slots, letters repeat unless the token uses `type=double` (then after 702). Dynamic spawns and names that do not match their
slot get no label: there is no encounter-order fallback. Clients whose game files differ can
rank differently.

### Format tokens

Each format is a line of text. In it `[name]` stands for the name, `[distance]` for how
far the character is from you, in yalms to a tenth, as the game measures it, and `[level]` for the
levels a monster can be. `[icons]` draws player icons at that point in the string, `[party]` a party
or alliance member's sign and `[vendor]` the coin of an NPC that sells. `[space]` is a gap of 4 px,
`[space: N]` one of N: only between two things written, so a member with no icons has none before the name.
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
The older `[name:yellow]` colour shorthand still works.

| Applies to | Option | Meaning |
|---|---|---|
| Every token | `color=yellow` or `color=#FF8000` | Gives this token its own colour |
| Every token | `space=0`–`64` | A gap after the token, in screen pixels, scaled with the render resolution. Left out when the token writes nothing |
| Every token | `when=target+checked+nm+relevant` | Any subset, all of which must hold; left out or `always` means always |
| Every token | `within=1`–`100` | Only within this distance in yalms; when the distance is not available the block is hidden |
| `[icons]`, `[party]`, `[vendor]` | `size=25`–`300` | Icon height as a percentage of name height; defaults to the profile's previous icon size (90% in the preferred defaults) |
| `[aggro]` | `size=25`–`300` | The sign's height as a percentage of name height; default 125 |
| `[checked]` | `size=25`–`300` | The magnifying glass's size as a percentage of the letters'; default 70 |
| `[icons]` | `gap=0`–`24` | Screen pixels between icons; default 2 |
| `[party]` | `replace` | For a member with a sign, leave out the game's icons wherever `[icons]` is |
| `[distance]` | `decimals=0`–`2` | Decimal places; default 1 |
| `[name]`, `[level]`, `[distance]` | `spacing=0`–`10` | Screen pixels between this token's letters at the name's largest, shrinking with the name, in place of **Letter Spacing** |
| `[level]` | `exact` | Only the exact level, once the monster is checked: nothing before then, nor for one impossible to gauge, where `[level]` writes the database's range. Text around it stays |
| `[level]` | `nocombat` | Nothing while the monster is in combat (engaged and alive, as **Combat Only** health bars have it); its level again once it is not. Text around it stays |
| `[letters]` / `[letter]` | `type=single` / `type=double` | Repeat A–Z, or carry on with AA, AB and so on after Z; default single |

```text
[icons: space=4][name]
[name: space=8][icons: size=100, gap=3, space=0]
[icons: space=4][name] ([distance: decimals=2, color=yellow]y)
[aggro: space=4]Lv [level: color=yellow, space=6][name]
[name: spacing=2] ([distance: spacing=0]y)
[aggro] Lv [level: nocombat] [name]
```

With no `space` given, icons, party signs and the vendor coin use the profile's previous icon spacing (4 px in
the preferred defaults); other tokens use zero. A colour on icons overrides the pearl's tint;
otherwise the linkshell pearl keeps its own colour, and two-part icons stay overlaid.
Numbers out of range are brought within it. An unknown or badly formed option leaves the
whole bracketed token as typed, rather than breaking the nameplate.

Square brackets round anything else are written as they are, so a format such as `[NM] [name]` writes
`[NM] Goblin`. Only the letters, figures and signs of plain English can be written.

`[level]` is not the level of the one monster, which the game does not tell. It is the levels that
monster can be, as `5-6`, or as `8` where it can only be the one. They are from winxi's game data
(`winxi.mobs`), one table for each area, made from the server's own; see [Monster data](#monster-data). For what the tables do not have (a player, an NPC, a monster the server makes as it goes)
`[level]` writes nothing, and what was typed round it is still written.

When you `/check` a monster, the game's answer has its level in it. From then on `[level]` writes
that one level for that monster in place of the range. It stays while the monster's body lies there
after it dies, its health bar grey. It is forgotten once the body is gone (or the place is seen alive
again), when it is no longer there to be seen, and when you leave the area, since the monster that next
has its place is another. It is also forgotten five minutes after the check, so that a long stay in one place does
not leave more and more kept: check again for it. Nothing is sent to the game for this: the addon only reads the answers to checks you make
yourself. A notorious monster, whose strength is impossible to gauge, gives no level.

`[checked]` writes a magnifying glass for a monster whose level is known that way, and nothing for any
other, so `[name] Lv[level][checked]` marks the levels that are a monster's own and not a range. It
takes a colour as the others do. The magnifying glass is one of the icons Ashita's own font has. A font
chosen for the names does not have it, so it is then drawn from Ashita's beside that font's letters.

The Show Monster Distance setting of 1.9 and 1.10 is made into `[distance]` in Mob Format when the
addon is loaded.

`[aggro]` draws a sign for whether a monster is aggressive and how strong it is, a quarter as high
again as the name's letters and with the dark edge they have.
It is from the `data` folder's tables, so it is there whether or not the monster has been checked.
For what the tables do not have it draws nothing. `[aggro][name]` puts it before the name. A colour
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
`Mob13_Icon.png` in that order. They are gathered into the one sheet the addon draws from,
`assets/aggro.png`, by `assets/make_aggro_sheet.py`: run it after changing any of them.

### What a check shows

With Show Check Details on, a monster you check has a second line under its name,
at the Check Size you set (75% in the preferred defaults), with its
middle under the name's. It fades in as you check, stays for five seconds, and fades out. Checking
the monster again brings it back. The magnifying glass leads this line in icon mode, scales with
Check Details → Size (%), and fades with the details. When Show Check Details is on, an
explicit `[checked]` in the name format no longer repeats it beside the name.

- Difficulty is abbreviated by default: **TW** (Too Weak), **IEP** (Incredibly
  Easy Prey), **EP** (Easy Prey), **DC** (Decent Challenge), **EM** (Even Match),
  **T** (Tough), **VT** (Very Tough), **IT** (Incredibly Tough), and **???**
  (Impossible to Gauge). Turn off **Abbreviate Difficulty** in the Check Details tab to get the full names back. In abbreviated mode, a difficulty shown
  without any aggro or link information is still spelled out (for example, Very Tough).
  Impossible to Gauge stays ???. This applies to both the icon and the words layouts.
- For an aggressive monster, a sign for each thing it notices you by: sight, true sight, sound, low
  health, magic, job abilities, scent. Whether it is aggressive at all is not shown here: put
  `[aggro]` in the name's format for that.
- If it links, the link sign and family, followed by Sight, Hearing, or
  Sight/Hearing when those detection flags are present. For example:
  `Goblin (Sight/Hearing)`. These methods are worked out from the detection flags;
  the copied tables have no separate linking-method fields. If neither
  flag is present, the method is left unsaid.

With Text Only on, the line has no icons, and no magnifying glass.
Its sentence has parts separated with commas:

    TW, Sight Aggro, Link: Goblin (Sight)

The second part is there for an aggressive monster: what it notices you by (`Sight`, `Sound`, `Blood`,
`Magic`, `JA`, `Scent`, with a stroke between them if there are several, and `True Sight` and `True
Sound` for one that sees or hears truly) and then `Aggro`. The third is there for one that links, and
names the family it links with and the Sight/Hearing method worked out from the flags, when available.

The first part is from the game's answer to your check. The rest is from the tables in the `data` folder,
and is what the server's own tables say of that kind of monster. For one the tables do not have, the
first part is all there is. The signs for what it notices you by, and for linking, are mobdb's icons,
gathered into `assets/senses.png`.

The names are not drawn on the screen by this addon, as its windows are. An addon draws on the finished
picture, where nothing of the world can hide what it draws, and a name drawn there would show through
walls. So each name is set out here (`custom.lua`) as rectangles, one for each letter and icon, and
left with the plugin. The plugin draws them in the game's own picture at the moment the game would have
drawn the name, as deep in the picture as the name is. A wall, the ground or a character in front of
a name hides it, or the part of it that it covers, as it hides the game's.

The letters are those of imgui's font. Where the game's picture is larger than its window (a
background resolution above the window's) they are made larger to match, so that they are as sharp as
the rest of the picture. Every frame, Name reads the plugin's world render-target size and ImGui's
live output size. The horizontal and vertical ratios are applied separately, so fonts, icons and
spacing do not stretch when the background aspect ratio differs, or the client's menu resolution
is different from the output resolution. The updated `namehook.dll` also applies the horizontal
ratio to outline offsets and off-screen bounds; update the plugin together with the addon and library. Font sizes are measured in output pixels, not menu pixels. They are kept at three sizes only: the largest a name can be, three quarters
of it and half of it. A name at its largest is drawn letter for letter. A smaller one is drawn from
the next size up, scaled down to fit, so that names shrink smoothly with distance and imgui is not
asked for letters of a new size at every step. What is set out in one frame is drawn in the next.

Resolution regression check:

```sh
luajit tests/harness.lua name addons/name/name.lua tests/name_resolution_check.lua
plugins/namehook/tests/run.sh
```

The Lua check covers every combination of 11 window, menu and background sizes (4:3, 16:9,
16:10, ultrawide, portrait and square, through 8K), plus unknown dimensions, output fallback,
resize transitions and legacy callers. It checks square geometry, centring, independent spacing
and outline proportions. The native tests check aspect-aware bounds and cache invalidation. These
are CPU and geometry tests, not an in-game GPU certification: check live resizing, depth occlusion,
font-atlas changes and device resets in the client before you treat a setup as verified.

Name visibility follows the game. The game shrinks a name to nothing over the last of its
distance. Here it shrinks from the maximum size to the minimum and fades out, or keeps its
size and fades out over the last third.

The game pulses a living target's name: its colour goes toward white or toward dark, and its
opacity dips. Here the target's name does not pulse. Its text, outline, spawn letters, status
icons, composite overlays, aggro and check icons and mastery stars all hold the peak opacity, and the
text keeps the colour the pulse starts from. A change of colour that is no pulse, such as a
monster's name turning red as it is claimed, is taken at once. Spawn letters take the name's
colour unless their token has an explicit colour; explicit token colours and state
overrides that are on still apply. Distance fading still works. The hold resets on untargeting, respawn,
entity reuse or a gap in drawing.

By default a dead monster's name turns grey at once, even when its live `[name]`
token has an explicit colour. A Dead state colour that is on overrides that default grey. A neutral corpse grey supplied by the client replaces the fallback grey, and
stale red or white claim samples that come after it cannot recolour it. Corpse opacity still follows the
client directly, even while targeted, so icons and text fade away together. Once the client's
render flags say the mob is no longer shown (or its entity has been removed), any nameplate that is left
fades out in about **0.2 seconds**, including target icons and letters. The fade does
not start just because HP reaches zero while the corpse is still visible. Late name calls do
not restart it, respawning releases it, and an index reused by a different entity at once
suppresses the stale label. Missing render-flag data alone does not start a disappearance.

**Names → Player Names → Player Icon Source** chooses the artwork for player icons and mastery stars:

- **Game DATs** (default): reads the client's menu DAT, including its icon UV mapping and composite
  overlays, through the Pivot-aware file reader. XIPivot's `redirect_fopens` must be on for its
  replacements to be seen. The menu resource's file-table path is honoured, with `ROM/119/51.DAT` as the fallback.
  Supported artwork is a DXT3 `ustatshd` atlas with `fontshp` shapes; non-stock atlas sizes and
  rearranged rectangles are supported. Alpha is doubled to match the game. A missing, malformed or
  unsupported DAT falls back to the bundled icons without changing the saved choice.
- **Bundled**: uses `assets/player-icons.png` and the included mapping, whatever DATs are installed.
- **Custom**: loads `addons/name/assets/player-icons-custom.png`. Copy `player-icons.png` as a template:
  keep its proportional atlas layout, including the composite pieces. Higher-resolution versions of
  the same layout work too. Custom PNGs use normal PNG alpha, not DAT's doubled alpha. If the file
  cannot load, Name falls back to Bundled. Different custom layouts and mappings are not yet supported.

The linkshell pearl keeps its linkshell's colour, and two-part icons keep their overlay. The
choice does not change party and alliance role icons, vendor icons, or monster aggro and sense icons.
The UI reports a fallback and gives its reason on hover. Successful DAT reads and uploads are cached,
not repeated every frame; failures retry at most every ten seconds. Switching sources releases the
owned DAT texture and retries on returning to Game DATs. PNG failures retry once a second through the
shared image loader. Reload Name after changing an image that is already loaded, or after changing Pivot packs.
No signatures, game font-memory scans, borrowed textures or Python are needed at runtime.

The atlas and mapping were exported from the installed client's high-resolution `ustatshd` and
`fontshp` resources in `ROM/119/51.DAT`, with icon alpha doubled to match the game's rendering.
To make them again from a local install (Python with Pillow):

```sh
python tools/export_name_icons.py '/path/to/FINAL FANTASY XI/ROM/119/51.DAT'
```

This export stays as the independent fallback and the Custom PNG template. Game DATs mode reads the active
artwork directly without making these files again. Source decoding is in `playerdat.lua`; the choice,
fallback and per-source mapping changes are in `icons.lua`.

With the addon unloaded, or the plugin not recognising the client, the game draws
the names as before.

## The addon and the plugin

What is shown is the plugin's to keep, and can be changed there as well: by its own command
(`/namehook hide players`) or by another addon. The settings here and the plugin are kept the
same. They are given to the plugin when it is found, when another character's are loaded, and as they
change. A change made in the plugin is taken into them, and saved.

If this addon is unloaded, names stay as they were last set, until the plugin is unloaded.
`/namehook show all` shows them all again. If the plugin is not loaded, the settings window says
so, and what is set is given to the plugin when it is.

## Diagnostics

**Write Report** in General → Diagnostics makes a support summary you can share, with one
click, without turning on diagnostic recording. `/name report` also works with Enable Name
off. Files are `config\\addons\\name\\logs\\name-report-<date>-<time>-<sequence>.txt`.
Nothing is uploaded. Reports include the addon, library and capability-build versions, capability
flags, display and draw counts, generated font and badge atlas sizes, the active artwork source
and fallback state, observed cast counts, and recorded rendering failure counts. They leave out character and entity
names, chat, paths, formats you typed, raw errors and history. Reader failures are redacted.
Recent failure counts are there only when diagnostic recording was on; a report
still captures the current state when it was off.

Detailed diagnostic recording is off unless you turn it on, for testers:

```
/name diag          turns diagnostics on or off; kept with the character's settings
/name diag on|off
/name diag log      writes a log now, on or off (with diagnostics off it has no history)
```

While they are on, General → Diagnostics shows whether Name is drawing the names (**Custom Names**).
When Name stops claiming the names for more than half a second, at any frame rate, the game draws
its own names again. The reason is said once in the chat log and a log is written, once a session for each reason.
The reasons:

| Reason | What it means |
|---|---|
| `unloaded`, `old`, `mismatch` | The namehook plugin is not loaded, or is not the version this addon reads. No log is written for `unloaded` |
| `features` | The ABI can be read, but independent icon outlines are not supported; the stock names stay |
| `unhooked` | The plugin did not recognise this client's name drawing |
| `texture` | imgui's font texture was not ready, or could not be read |
| `draw` | The plugin had no drawing buffer |
| `error` | A Lua error in the frame. It is still raised as before, and kept once in the log with its traceback and a count |

With diagnostic recording off, no diagnostic history or errors are kept. The on-demand
support report and the normal compatibility and fallback warnings still work.

**Write Log** in General → Diagnostics, while diagnostics are on, writes a log as `/name diag log` does. Logs are small text files in
`config\addons\name\logs`, named `name-<date>-<time>.txt`. Each holds:

- The plugin's state: whether it is hooked, the frame and the last claim, what is claimed and
  hidden, and the names of the last frame and who drew them.
- The font atlas texture: whether imgui has it ready, what imgui says of it, and the texture the plugin read for it as it last drew the names; and the display size.
- Pauses since loading, short and seen.
- Lua errors.
- The last 300 events: zone-ins, settings given to or taken from the plugin, stops and resumes, and
  fonts or letter badges that would not load, and each time imgui makes the font texture again.
- The settings.

Detailed logs can contain character names, local paths, format strings and raw errors.
Prefer **Write Report** for sharing. Look through a detailed log before you send it.

## Pre-releases and release candidates

A testing round's package is a **pre-release**: the version carries `-pre1`, `-pre2`... (in `addon.version`, so
`/addon list` and the settings window say it; in the zip's and the tag's name; marked pre-release on GitHub), and
its notes say what it is. A pre-release that comes through a round with nothing left to fix becomes a
**release candidate**, `-rc1`, built from the same code. A candidate that runs a round untouched is the release,
its version without a suffix. The changelog section is the release's throughout: the stage is not a version
of its own. Packages are made from the commit with `tools/package_release.py <name> --stage pre1` (or `rc1`),
after `tests/run.sh`, and the command it prints makes the GitHub release, marked pre-release.

The namehook plugin in name's zip is built from the same commit (`plugins/namehook-SOURCE.txt` says which),
but its own version stays a number (1.51): Ashita gives a plugin a number for a version, so the stage is
the package's, and `/namehook` reports the plain number. A pre-release of name is a pre-release of the
namehook it carries.

What a round of name and namehook covers before a release candidate is cut:

- **Loading**: `/load namehook` then `/addon load name`, and the other way round; unload and load each
  again while the other stays, both ways. The names come back each time, and Diagnostics says
  **Custom Names** is on, never `old` or `mismatch`.
- **Names**: players, NPCs, monsters and pets, each kind's format and colours, distance thresholds,
  crowd decluttering, the check details, statuses over a name, cast bars, NM tracking; a zone change
  and a long session (an hour or more) without names dropping to the game's own.
- **The settings window**: every tab, each row doing what its sentence says, saving and reloading
  the character's settings, and the Reset rows.
- **With the others**: lens on (the names aligned under the warp), the damage addon (damage popups
  through namehook), a second names addon if any (claim slots), and the perf addon's figures for name.
- **What to send**: **Write Report** (`/name report`, written to `config\addons\name\logs`, nothing
  private in it), a screenshot where the look is the matter, and the lines of Ashita's log around any
  error. Say which pre-release: the version in `/addon list`.

A finding fixed within the round makes the next pre-release (`-pre2`). A round with nothing to fix
makes `-rc1` from the same commit, and that candidate's untouched round makes the release.
