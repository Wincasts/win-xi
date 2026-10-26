# party
Party, target and pet frames in winxi's themed windows, with bars and a layout after the Windower
addon [XivParty](https://github.com/Tylas11/XivParty)'s compact one.

- **Party**: your party and the other two alliance parties. A member is a line: the name, an HP bar
  and a smaller MP bar with their values, and TP as a value. Selected members have the game's animated cursor before
  their name (blue text for the target, green for a subtarget or party-cursor selection); a leader has a circle before theirs (yellow for the party's leader; the alliance's leader has a white one above it), and the level sync designee a red one at the right end of their line, as high as the party leader's. Your own party's list grows upwards, and
  has its buffs running leftwards from the window. The game's own icons beside the window mark a party or
  alliance invite waiting for an answer (a green exclamation mark in a dark circle) and anything in the treasure pool (the chest).
  A name is written as far as the right end of its HP bar, and only cut short with "..." past that.
  **Alliance Scale** (Party tab) sizes the other two parties together, on top of the Scale in Style.
  **Name Font** and **Value Font** (Style tab) choose a Windows font for the names and for the HP, MP and TP
  values, apart from each other; Theme Font, the default, is the one set in Winxi Theme.
  **Advanced: Value Positioning** (Party tab, collapsed) moves the HP, MP and TP values of the party, the
  alliance and pets.
- **Target**: your target, sub-target and target of target, each a line of the same kind: the name,
  the HP bar, the distance and the HP percentage, with the enemy's debuffs if wanted: as letters under it, or as status icons beside it, placed and sized as your party's buffs are.
  **Advanced: Value Positioning** (Target tab, collapsed) moves the HP percentage and the distance, each on
  its own; the party's offsets no longer move them.
  **Game Name Colors** (Target tab → Names, off to begin with) writes the name in the colour the game gives
  it over the head: an enemy yellow while unclaimed, red claimed by your party or alliance, purple by anyone
  else and orange once help is called for; a player white, or blue in your party or alliance; an NPC green;
  anything dead grey. With namehook loaded and the name on screen, the colour is read from the game itself,
  exactly, held steady while the game pulses the target's name; otherwise it is worked out, the NPC green,
  the player white and the party blue measured from the game, the enemy colours close to it.
  **Monster Letters** (Target tab → Names, on to begin with) puts a monster's spawn letter after its name, in
  a small box in the name's colour: the letter name writes over it (A, B, C… among the monsters of one name in
  the area, by their places in the game's own list, so every player sees the same; past Z, A again). None for
  players or NPCs, or where the area's list cannot be read or differs from what the game shows.
  **Lock-On Brackets** (Target tab → Lock-On, on to begin with) stand a [ and a ] outside the left and right
  of the main target's window while you are locked on to it, enclosing its frame without touching it, as the game frames its own, in the **Bracket
  Color** (white to begin with) with the theme's Text Outline.
- **Pets**: your pet, and your party members' pets, listed under your party below a line.

## usage
`/pt` (or `/xif`) opens the settings. `/party` is left alone for the game's own party chat;
`/xiframes` is no longer used. Its Style tab sets how every frame is drawn (sizes,
fonts, bars, statuses); Party, Target and Pets have what is each one's own. The dark edge round names
and values is Winxi Theme's Text Outline, set in winxisettings for every addon.
**Behavior** has **Positioning** (optional **Automatic Positioning**), uihook while it is loaded, then
**Mouse Interaction**. **Visibility**, the last tab, has the hiding rules (**Hide Windows**), **Fade When Idle** and which windows fade (**Fading**).
There is no Winxi Theme tab in Party; use **winxisettings** for shared colours, padding, shadows,
window borders, bar textures, bookends and custom status icons. Organize, at the foot of the window, fills the frames with sample data to drag into place.
`/pt perf` measures five seconds of render and packet-handler CPU time: average, median, p95,
p99 and worst latency. Memory is a **GC-sensitive net-growth estimate**, excluding negative deltas,
not an exact allocation count. `/pt perf counters` also counts addon-local entity reads, text
measurements, image submissions, texture-load attempts and status reorderings; shared Winxi internals are not all counted.
These measurements do not include GPU execution. Percentile samples are capped at the first 16,384
calls per category; averages and maxima cover the full interval.

## customization

- **Style → Appearance → Scale** is a visible control. The **Sort By Role** toggle is hidden;
  existing saved sorting behavior is preserved. Native party selection temporarily suspends role sorting.
- **Style → Status Display** provides a 1–32 icon limit, one or two rows, left/right/most-space growth,
  screen-edge fitting and overflow badges. Screen fitting conservatively reserves the widest icon in
  mixed sets. When needed, the last available slot becomes a `+N` badge; with no external space the
  badge uses the frame's lower-left corner. Two rows increase row height.
- **Style → Status Display → Show Statuses**, on by default, draws the buff and debuff icons beside the
  party and alliance. Off, every status setting (Status Display, Status Filtering, Advanced: Status IDs)
  is greyed and kept; a target's debuffs follow the Target tab.
- **Style → Status Filtering** has Debuffs First and two effect pickers, Priority Effects and Hidden
  Effects: search by name or ID, tick effects, and reorder priorities with Up and Down. Priority order
  follows the list, hidden effects win, and other effects keep their original order. The same lists
  can be typed as comma-separated numeric IDs under **Advanced: Status IDs** (collapsed by default),
  which is also where IDs without a name in the game's resources can be entered. With Debuffs First,
  every debuff comes before every buff, nearest the frame in the Status Growth direction, and Priority
  Effects order each kind among itself. The debuffs are those Erase or a waltz removes in Phoenix's
  `data/status_effects.yaml`, and the harmful ones that cannot be cancelled (sleep, charm, doom, helix,
  enemy songs, dazes, the Geo downs and the like).
- **Style → Warnings** has a low-HP `!` threshold (zero disables it) Flash TP When Ready and TP Ready Color (blue to begin with); TP is ready at 1000.
  **Advanced: Range Indicators** has near range (centimeters), far range (meters) and both dimming
  levels. Far range is treated as at least near range. These are approximate distance indicators,
  not action-specific range guarantees.
- **Style → Appearance → Bar Shadows**: Off, Simple (one layer), or Full (two layers). This is
  independent of Winxi window shadows.
- **Behavior → Mouse Interaction → Show Tooltips**, beside Clickthrough, is off by default. On, hovering
  the windows shows Winxi tooltips: full names, jobs and pet owners on the members, and each buff and
  debuff (icons and a target's letters) with its estimated time left. Off, there are none.
- **Clickthrough** lets clicks through to the game, but the windows are still hovered: with Show Tooltips
  on, their tooltips show either way. Another window drawn over them, wanting the mouse, keeps them from showing.
- **Shift+drag** moves a window when **Clickthrough** is off: hold Shift as you click it, and the drag goes
  on until the mouse is let go. Without Shift the windows stay put, so a click on them does not move them.
  With Clickthrough on they cannot be dragged except while organizing. A window placed by Automatic
  Positioning or by uihook, or linked to another, is not moved this way (Organize unlinks it).
  Tooltips follow **winxisettings → Tooltips**, including visibility, delay and appearance.
  Enemy duration tooltips explicitly describe estimates, not exact server timers.
  No click-to-target behavior is introduced.
- **Style → Names → Short Zone Names**, on by default: a member in another zone has the game's own short
  form of its name where their bars would be (`zones.names_abbr`), or the whole name where
  the game has none. Off, the whole name, cut short where it does not fit.
- **Pets → Layout → Pet Names**: `Pet`, `Owner: Pet` (default), or `Pet (Owner)`.
- The settings window has no section-reset buttons.

Layout reservation is cached until relevant values change. Hidden frames and frames with both groups
disabled or fully faded skip layout and pet polling. A visible target with its party hidden retains
the configured minimum pet reservation without polling live pets. Status filtering is cached per input
list, with value comparisons detecting in-place updates; caches release discarded lists. Hover details
read mouse coordinates once per enabled frame. Automatic windows reuse their positioning vector.
Theme-font changes invalidate cached text measurements. Debuff tracking clears on disable,
settings/character switches and zone-in/out, including while frames are disabled; re-enabling begins
with only newly observed effects, never a reconstructed complete enemy status list.

### Live validation

After reloading Party in Ashita, run `/pt perf` with settings closed for solo, full party, full alliance,
pet-heavy and target-debuff scenarios; repeat with `/pt perf counters` when investigating work counts.
Compare Full/Simple/Off bar shadows under the same conditions. Validate six-pet positioning, theme-font
switches, status overflow near both screen edges, two-row icons, tooltips, and
zone/disable/re-enable tracking. Offline checks cannot validate actual GPU performance, DPI or mouse
behavior in the game.

## once called xiframes
The addon was xiframes until it was renamed party. The first time each character logs in with it,
what xiframes kept for them (`config\addons\xiframes`) is taken up as party's settings, so nothing
needs copying by hand; xiframes' folder is left as it was. Unload xiframes and load party in its
place (and change `xiframes` to `party` in any script that loads it).

## the code
| file | what it does |
|---|---|
| `party.lua` | puts the rest together: what goes in which window each frame, which packets go where |
| `roster.lua`, `pets.lua`, `target.lua` | read the game, and hand back lists of lines |
| `frames.lua` | draws a list of lines: the bars, names and values |
| `notices.lua` | invitations and treasure waiting, and their icons |
| `debuffs.lua` | the row of letters or icons for what is on an enemy, which `winxi.debuffs` keeps count of |
| `windows.lua` | the windows the lists are drawn in: themed, arranged, fading, held by a corner |
| `options.lua` | the settings, each an entry in a list: defaults and the settings tabs come from it |
| `config.lua` | the settings window |
| `draw.lua`, `colors.lua`, `game.lua`, `packets.lua` | drawing on a draw list, the colours that mean something, small things asked of the game, and the packets read |
| `perf.lua` | `/pt perf`: render/packet CPU statistics and optional operation counters |
| `geometry.lua` | cached automatic-layout reservations |
| `statuses.lua`, `details.lua` | status filtering, screen capacity and hover details |

`tests/run.sh` loads the addon against a stand-in for Ashita, and compares what it draws, call for
call, with a kept copy.

### Offline QA

From the repository root, run Party's checks independently with:

```sh
for check in tests/party*_check.lua; do
    luajit tests/harness.lua party addons/party/party.lua "$check" || exit 1
done
```

`party_lifecycle_check.lua` covers null buff pointers, inactive-slot reads, cache reuse,
immediate pet-setting changes, zone resets, invitations while disabled, and entity-index reuse
during target fade-out. `party_performance_check.lua` isolates geometry and letter-debuff
allocation budgets from the harness's allocating stubs, with JIT disabled for reproducibility.
`party_customization_check.lua` covers settings validation, status sorting and fitting, shadows,
font invalidation, warning/overflow rendering, cached reservations, six pets, hidden-frame work
and the effect picker.
`party_tracking_check.lua` covers debuff lifecycle, tooltip semantics and profiling statistics.
`party_optimization_check.lua` verifies disabled/faded early exits, target-only reservations,
once-per-frame mouse sampling, and status-cache invalidation.
The lifecycle check also verifies that empty status IDs 0 and 255 never enter the player's buff list.
The existing resolution, cursor, rearrangement, border and dropdown checks cover presentation
and input paths. The full runner also compares the plain and bare draw snapshots.

The initial optimization pass preserved both scenes byte-for-byte relative to its pre-pass code.
The customization pass intentionally updates pet-owner labels and screen-constrained status overflow;
the snapshots also include previously unrecorded cursor/title and shared-library changes.
The follow-up pass removes empty status 255 and fixes the Organize snapshot to open settings with
`/pt`, asserting that settings and Organize are active. Measurement mode closes settings with `/pt`
and asserts that both are off. The refreshed Organize scenes now genuinely include sample rows.
Isolated allocation measurements before → after:

| Operation | Bytes per call/row (JIT disabled) |
|---|---:|
| Full-list geometry reservation | 160 → 0 |
| Letter-debuff row | 1,072 → 0 |

The new cached-reservation and unchanged-status-filtering checks also measure **0 bytes per call**
with JIT disabled after warm-up. These isolated budgets exclude rendering-library allocations.
Native renewal/rectangle/anchoring paths also have zero-allocation budgets; idle-disabled hooks make
no repeated DLL calls. Manual layout avoids unused display queries, and target polling skips discarded
ToT entity lookups or all target reads when every target window is disabled. Native capture/replay
optimization details and the CPU-only benchmark are in the [partyhook README](../../plugins/partyhook/README.md#optimization-checks).

Empty alliance slots skip stats, jobs and buffs. Pet options invalidate the pet snapshot
immediately rather than waiting for its polling interval. Invitations and automaton state
continue receiving lifecycle packets while their frames are disabled; zoning clears cached
rosters, automaton exact values and lingering target identities. These are offline checks,
not an in-game FPS benchmark. Verify zoning, character switches, native selection, fading
and actual rendering in Ashita before treating live QA as complete.

## window borders
In **winxisettings → Styles → Window Border**, choose **Theme** (the existing border), **Brushed Silver**,
**Bronze**, **FFXI-inspired** (a cool silver/lavender bevel reminiscent of the base UI),
**Crystal** (icy blue facets), **Royal Gold** (warm gilding with tiny inlaid corner ornaments),
**Obsidian** (dark violet metal with platinum corner highlights), **Plain Obsidian** (the same without
the corner highlights; Match Border gives it Obsidian's bookends), or **Royal Silver**
(the Royal Gold ornamentation in cool silver), or **Royal Platinum**
(a lighter, near-white silver version with softer bevel shadows), **Mythril** (cool blue steel with
corner studs), **Adaman** (dark crimson metal with riveted corner plates), **Jade** (green stone
facets), or **Amethyst** (violet crystal facets).
The border is part of winxi's theme, so it is drawn on every window of every addon that follows
the same theme, this addon's party, target and pet windows among them.
The thin **3px** edging replaces the native window border rather than overlaying it.
Corners keep their size as windows resize, and borders follow window fading.
Theme remains the default; missing textures leave the theme border visible.
**Border Opacity** (beside it) fades the border of every game window, plain or art: 100 is solid, 0 is none.
Settings windows keep a solid border.

Preview: [`libs/winxi/assets/borders/preview.png`](../libs/winxi/assets/borders/preview.png). The blue background in the
FFXI-inspired preview, and the tinted backgrounds of the other concepts, are illustrative:
selecting a border keeps your current theme background.
For that look, use a dark navy background in Winxi Theme. Keep theme padding at least **3px**
to leave room for these borders. Regenerate the assets with
`python3 tools/generate_party_borders.py` (requires Pillow); no extracted game art is used.

## Experimental Native HUD Replacement

Use [uihook](../../plugins/uihook/README.md) for new native-rendering installations; it combines
buff and party/target support. Load `/load uihook` instead of `/load partyhook`, and never load both.
The updated addon still supports legacy partyhook for rollback. The behavior and testing notes below
apply to both plugins.

The opt-in `partyhook` plugin captures existing Party windows and replays them at the native HUD's
rendering stage, rather than as a final overlay. Native logic keeps running; only GPU submissions
inside the selected native window's render call are blocked. Normal rendering remains the default.
User testing confirms party/rearranging, chat hiding, target/native arrows, menu overlap, subtarget
range colours, rapid switching/despawns/doors, cutscenes, interface hide/show and independent toggles.
**Zoning remains untested**, as do font/device-reset recovery and broader client compatibility.

Build/install/update and live checklist: [plugins/partyhook](../../plugins/partyhook/README.md).
**This addon requires partyhook 0.3 (shared ABI 3); update both addon and DLL, not just the addon.**
Unload Party and partyhook before replacing the DLL; keep hideparty unloaded.

- `/pt native on|off`: party/alliance lists, including embedded pet rows.
- `/pt native target on|off`: independent target replacement. Captures main, sub-target and target-of-target
  windows together at the native target-box stage; normal Target settings still select which are shown.
- `/pt native status`: concise mode/readiness status; cumulative debug counters are hidden.
- **Behavior → uihook**, between Positioning and Mouse Interaction, shown only while uihook (or partyhook) is loaded, its title followed in green by the plugin found
  and its version, e.g. `[uihook 1.60 found]`. **Use uihook** turns the
  hooking on or off as a whole; while it is on, **Party** and **Target** choose which windows the plugin
  draws in the game's place, and **Follow Default UI Behavior** sits with them; each one's explanation is in the tooltip of the (?) after it. Pets are rows of the
  Party windows and go with Party. The choices are kept while the plugin is not loaded. `/pt native on` turns Use uihook on too; `/pt native status` says how the hooking is doing.

While a fish is on the line, target mode lets the game's own target window draw, since the game draws the
fish's stamina gauge with it (in the middle of the screen, not where the window sits), and Party's target
windows step aside so a target is not shown twice. This lasts from the bite (packet 0x115)
until the fight ends (the client's fishing packet ending or releasing the catch, a change of area, or the
fight's time limit passing).

Target mode preserves the **game's own overhead main/subtarget arrows**, including placement, animation
and range tints, by allowing their two verified native draw calls through HUD suppression. No Lua
replacement cursor is drawn. All custom target windows share the native target window's lifecycle;
no entity (for example some doors) may mean an arrow without a custom information bar.

Manual/automatic positions and styling remain the defaults. Outer window drop shadows are captured
with native-rendered party/alliance and target windows, using Winxi's shadow settings. Only the exterior
shadow is drawn in native mode so it cannot darken the existing window background. Bar/text shadows
remain unchanged. This fix requires updated Party and `winxi/shadow.lua`, not a new uihook DLL.

**Use Default UI Positioning is hidden and forcibly disabled for this testing build**, including old
saved opt-ins. Its alliance-location controls are hidden too. Manual positions, corners and links are
preserved; ordinary Automatic Positioning remains available. With Automatic Positioning off, arrange
alliances independently in Organize. Alliance 3 is linked below Alliance 2 by default, not the main
party; use **Unlink** to move all three lists separately.

- **Follow Default UI Behavior** remains a separate opt-in for native-rendered groups: follow the native
  window lifecycle rather than custom chat/map hide rules, keep native member order, allow solo-party
  drawing, and disable addon idle/presence fading. Loading, interface-hide and cutscene guards remain.
  Styles, sizes, pet/buff choices and non-native groups keep their normal settings. This is not a
  pixel-identical recreation of stock frames or all their animations.

Default behavior remains off by default and **has not yet been live-tested**. Organize uses ordinary
windows and temporarily restores stock HUD frames; it edits saved manual positions. Native anchoring
cannot be reactivated through saved settings while parked.
With default behavior off, visibility-rule hiding renews empty replacements so stock frames stay suppressed.
Disabling one mode leaves the other untouched. Do not run hideparty alongside either mode.
The plugin is built/installed separately, not automatically included in the existing release package.

## Native Selection Cursor

Selected members use the animated, right-pointing cursor from the installed client's
`ROM/119/51.DAT` (`anc_s` sprites and the `anc` texture). The shared `winxi.cursor` loader
reads the DAT through the same pivot-aware file reader used for maps, uploads it once, and
animates its six frames at 15 FPS. The cursor retains the DAT's artwork/colours and scales
with name text. It overlays the frame to the left of the name without indenting the name or
changing its truncation; overlapping other elements is allowed. No replacement cursor PNG is bundled.
Reload Party after changing the DAT or its overlay. If the DAT/sprites/texture cannot load,
Party falls back to `>>` for the target and `>` for subtarget/party-cursor selection, retrying
periodically. `/pt cursor` retries immediately and reports whether loading failed at DAT read,
DAT parsing, or texture upload (or confirms a successful load). This only draws an indicator;
it does not move or modify the game's cursor.

## Party-Order Rearrangement

While the native party cursor is active, party buff icons are replaced with outlined job/subjob
labels beside each member. Detection uses the same pointer and active flag as `hideparty` uses to
restore the default party frames—not the chat/menu name. This covers party-order rearrangement
and party-member selection with `<stpt>`/`<stal>`. The labels appear in all three party lists,
including Alliance 2 and Alliance 3. Labels use `[WAR15/RDM7]`; unknown halves use `---`, so
an entirely unknown member shows `[---/---]`. Members in another zone also get a label.
Labels stay outlined even with Winxi Theme's Text Outline at 0. Buffs return when the party cursor
closes. Role sorting is suspended and idle fading is paused while the party cursor is active.
This is separate from the addon's Organize mode and does not modify target or pet frames.

## Resolution And Scaling

Party draws in ImGui output/display pixels, not the game's background-render or native-menu
coordinate space. Frame dimensions use the saved style scale; changing aspect ratio does not
stretch the bars. Background supersampling and native menu resolution are not inputs to Party's
layout. Actual presentation and Windows DPI behavior still need in-game validation.

Enable **Behavior → Positioning → Automatic Positioning** for the edge-relative layout
(off by default):

- Main party: bottom-right, **15px from the right and bottom**, growing upward and leftward.
- Target: **5px above the main party**, following its actual height.
- Alliance 2: **15px from the right**, at a stable vertical position reserved for the full layout.
- Alliance 3: **5px below Alliance 2**, retaining their existing vertical link.
- With both alliance parties and the main party fully expanded, reserve **35px between the bottom
  of Alliance 3 and the top of Target**. Pet space reserves at least **Pets → Reserved Pet Rows**
  (default two, one when party pets are hidden), expanding for the actual pet count, up to six.
  Select six for a stable full-party reservation without movement as pets appear.
  Target letter-debuff rows are also reserved.
- Sub-target and target of target keep their manual positioning and existing links.

Frame scale and text sizes are unchanged. Manual positions and the main party's saved corner are
preserved, and disabling Automatic Positioning returns to the manual layout. Turn it off to drag
the managed frames to custom positions.

With this option off, positions remain absolute pixels. Use **Organize**, or Shift+drag with
Clickthrough off, to place frames manually. The original defaults include positions beyond a 1920-wide output. Oversized frames
cannot fit completely on small screens, and buff icons extending outside a window may still reach
the screen edge; this is basic adaptation, not a full responsive layout system.

The offline resolution check covers 640×480 through 3840×2160 and ultrawide outputs up to
5120×1440, at saved scales of 50–200%, checking geometry and output clipping, plus automatic
edge margins, the Target and alliance links, the full-layout 35px gap, clamping and invalid-display
handling. It does not emulate
the native game's renderer or prove every layout fits on every screen.

## window backgrounds
In **winxisettings → Styles → Window Background**, choose **Plain** (the flat Background
Color, the default), **Gradient** (lighter at the top, darker at the bottom), **FFXI-inspired** (that
gradient with a fine dark line on every other row, after the look of the game's own windows),
**Grain** (soft stone), **Marble** (faint veins), **Weave** (linen) or **Brushed Metal**.
Each is drawn in your Background Color, its opacity included, and fades with the window. Like the
border, it is part of winxi's theme and drawn on every game window; settings windows stay plain.

Preview: [`libs/winxi/assets/backgrounds/preview.png`](../libs/winxi/assets/backgrounds/preview.png).
Regenerate the tiles with `python3 tools/generate_winxi_backgrounds.py` (Pillow and numpy); no game
art is used.

## bar textures
In **winxisettings → Styles → Bar Texture**, choose:
- **Original** — the bundled classic textures.
- **Glass** — glossy reflections and beveled edges.
- **Detailed** — metal bevels and subtle segmented fill.
- **Crystal** — angular facets, diagonal reflections and diamond accents.
- **Satin** — a soft, smooth fill with understated thin edging.
- **Runic** — a luminous central fill with chevrons and stationary frame markings.
- **Classic FF** — a clean top-to-bottom gradient and crisp square bevel.
- **Radiant (Bright)** — a near-white tintable fill for brighter HP/MP, with a thin silver bevel.
- **Chrome** — polished metal: a hard bright band over a dark horizon, with bright side edges. The default.
- **Flat** — one even colour in a thin square frame.
- **Segmented** — ten cells, marked on the frame so that they stay put as the bar empties.
- **Ember** — a glowing core fading to darker edges, with fine sparks.
- **Kingdom** — a single square bright rail over a plain dark field, inspired by classic Final Fantasy console menus.
- **Magitek** — industrial ribs, alternating metal highlights and mechanical rail markings; a nod to Final Fantasy's machinery.
- **Aether** — luminous crystal facets and diamond rail accents, inspired by the series' crystal motifs.
- **Elven** — soft satin light, curved filigree rails and flowing leaf-like reflections; high-fantasy metalwork.
- **Gothic** — dark iron edging with pointed tracery and a luminous interior; dark-fantasy ornament.

The smooth sets are shaded from top to foot only, with no pattern along the bar. The fill image is
stretched to the HP left, so a pattern squeezes as the bar empties; these look the same at any HP.
- **Enamel** — a bright upper half over a deeper lower one, softly parted, as the game's own bars are.
- **Enamel (Lit Rim)** — the same, with a thin light along the top.
- **Enamel (Gradient)** — each half a gradient of its own.
- **Glass Tube** — round like a tube: dark edges, a highlight a quarter of the way down, light along the foot.
- **Glass Tube (Deep)** — darker edges and a sharper highlight.
- **Glass Enamel** — the enamel's two halves with the tube's highlight.

These are original procedural designs, not extracted or reproduced game assets.

The choice applies to HP and MP across party, target and pet frames.
Colours, range fading, bar sizes and the optional bookends still work as before.

**Bar Frame** draws a frame of its own in place of the texture's: **Capsule Outline** is a thin
rim in the cyan of the Rounded bookends, **Capsule Outline (Silver)** in Rounded Silver's, along the
bar above and below. It is not tinted by the HP/MP colour. With those bookends the bar and its caps
are one capsule being filled; with others, or none, its ends are closed square. **Bar Texture** keeps
the texture's own frame. **Bar Frame Opacity (%)** makes either frame see-through: 100 is solid, 0 hides it.

**Fill End Glow (%)** puts a soft white light at the end of each fill, where it stops, as on the
game's own gauges: 0 is none, 100 the brightest. It dims with the bar's range fading.
**Custom Bar Backdrop** colours the empty part of the bars with **Bar Backdrop Color** in place
of the bar's own colour darkened; its alpha lets the dark trough show through.

Preview: [`assets/bars/preview.png`](assets/bars/preview.png).
The generated textures live in their named subfolders under `assets/bars`; regenerate them
with `python3 tools/generate_party_bars.py` (requires Pillow), or only the sets named after it
(`python3 tools/generate_party_bars.py enamel tube`). It copies each set's HP art, and the glow,
into `libs/winxi/assets/bars` for `winxi.bars`. The preview is illustrative,
not an in-game screenshot.

## matching bookends
Enable **winxisettings → Styles → Bar Bookends**, then select **Bookend Style**:
- **Bar Texture** uses the selected bar's existing cap (the default).
- **Match Border** follows the Window Border: each border has its own ornament. With the plain
  Theme border it uses the bar texture cap.
- Any border's name selects its ornament independently of the border: rods with studs (Brushed
  Silver, Bronze, Mythril), riveted plates set with a jewel (FFXI-inspired, Obsidian, Adaman), jewelled
  spines (Royal Gold, Royal Silver, Royal Platinum) and cut stones (Crystal, Jade, Amethyst).
- Five additional independent ornaments: **Kingdom** (gold crown and blue jewel), **Magitek**
  (steel coupling and cyan core), **Aether** (violet floating shards), **Elven** (gilt green leaf),
  and **Gothic** (dark lance and ruby). Pair with their namesake bars or mix freely.
- **Rounded** and **Rounded Silver**: round ends after the game's own gauges, in cyan or silver.
  Unlike the others they sit beyond the bar's ends, the frame's height and about half as wide,
  so the bar carries on into them.

The slim ornaments are not tinted by HP/MP, so silver stays silver and gold stays gold.
**Bookend Opacity** (under Bookend Style) makes them see-through: 100 is solid, 0 hides them.
They retain range-independent frame visibility and window fading, and work with all bar textures.
Missing ornaments fall back to the bar's existing cap.
For the silver combination, choose **Royal Silver** border, **Radiant (Bright)** bars,
and **Match Border** bookends.

Preview: [`assets/bookends/preview.png`](assets/bookends/preview.png), including enlarged ornament
detail. Regenerate with `python3 tools/generate_party_bookends.py` after generating the bar
textures (Pillow required). The preview is illustrative, not an in-game screenshot.

The Original bar images are XivParty's, cut down to the bars themselves, in `assets/bars` with its licence.
The generated sets do not use those images as source material.
Needs `libs/winxi`.
