# party
Party, target and pet frames in winxi's themed windows, with bars and a layout after the Windower
addon [XivParty](https://github.com/Tylas11/XivParty)'s compact one.

- **Party**: your party and the other two alliance parties. A member is a line: the name, an HP bar
  and a smaller MP bar with their values, and TP as a value. Selected members have the game's animated cursor before
  their name (blue text for the target, green for a subtarget or party-cursor selection); a leader has a circle before theirs. Your own party's list grows upwards, and
  has its buffs running leftwards from the window. The game's own icons beside the window mark a party or
  alliance invite waiting for an answer (a green exclamation mark in a dark circle) and anything in the treasure pool (the chest).
  A name is written as far as the right end of its HP bar, and only cut short with "..." past that.
  **Alliance Scale** (Party tab) sizes the other two parties together, on top of the Scale in Style.
  **Name Font** and **Value Font** (Style tab) choose a Windows font for the names and for the HP, MP and TP
  values, apart from each other; Theme Font, the default, is the one set in Winxi Theme.
- **Target**: your target, sub-target and target of target, each a line of the same kind: the name,
  the HP bar, the distance and the HP percentage, with the enemy's debuffs if wanted: as letters under it, or as status icons beside it, placed and sized as your party's buffs are.
- **Pets**: your pet, and your party members' pets, listed under your party below a line.

## usage
`/pt` (or `/xif`) opens the settings. `/party` is left alone for the game's own party chat;
`/xiframes` is no longer used. Its Style tab sets how every frame is drawn (sizes,
where the values sit, the outline); Party, Target and Pets have what is each one's own.
**Behavior** contains mouse interaction, optional **Automatic Positioning**, hiding rules,
**Fade When Idle**, and which windows fade.
There is no Winxi Theme tab in Party; use **winxisettings** for shared colours, padding, shadows,
window borders, bar textures, bookends and custom status icons. Organize, at the foot of the window, fills the frames with sample data to drag into place.
`/pt perf` measures the next five seconds of play and says how long the addon took a frame, on
average and at worst, and how much memory it made a frame.

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
| `perf.lua` | `/pt perf`: how long a frame takes in play |

`tests/run.sh` loads the addon against a stand-in for Ashita, and compares what it draws, call for
call, with a kept copy.

## window borders
In **winxisettings → Styles → Window Border**, choose **Theme** (the existing border), **Brushed Silver**,
**Bronze**, **FFXI-inspired** (a cool silver/lavender bevel reminiscent of the base UI),
**Crystal** (icy blue facets), **Royal Gold** (warm gilding with tiny inlaid corner ornaments),
**Obsidian** (dark violet metal with platinum corner highlights), or **Royal Silver**
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
Labels stay outlined even when general text outlines are disabled. Buffs return when the party cursor
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
  of Alliance 3 and the top of Target**. Pet space is reserved for **at most two pets** (one when party members' pets are hidden);
  target letter-debuff rows are also reserved. More than two pets can exceed this reservation.
- Sub-target and target of target keep their manual positioning and existing links.

Frame scale and text sizes are unchanged. Manual positions and the main party's saved corner are
preserved, and disabling Automatic Positioning returns to the manual layout. Turn it off to drag
the managed frames to custom positions.

With this option off, positions remain absolute pixels. Use **Positioning** or **Organize** to place
frames manually. The original defaults include positions beyond a 1920-wide output. Oversized frames
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
- **Original** — the bundled classic textures (still the default).
- **Glass** — glossy reflections and beveled edges.
- **Detailed** — metal bevels and subtle segmented fill.
- **Crystal** — angular facets, diagonal reflections and diamond accents.
- **Satin** — a soft, smooth fill with understated thin edging.
- **Runic** — a luminous central fill with chevrons and stationary frame markings.
- **Classic FF** — a clean top-to-bottom gradient and crisp square bevel.
- **Radiant (Bright)** — a near-white tintable fill for brighter HP/MP, with a thin silver bevel.
- **Chrome** — polished metal: a hard bright band over a dark horizon, with bright side edges.
- **Flat** — one even colour in a thin square frame.
- **Segmented** — ten cells, marked on the frame so that they stay put as the bar empties.
- **Ember** — a glowing core fading to darker edges, with fine sparks.

The choice applies to HP and MP across party, target and pet frames.
Colours, range fading, bar sizes and the optional bookends still work as before.

Preview: [`assets/bars/preview.png`](assets/bars/preview.png).
The generated textures live in their named subfolders under `assets/bars`; regenerate them
with `python3 tools/generate_party_bars.py` (requires Pillow). The preview is illustrative,
not an in-game screenshot.

## matching bookends
Enable **winxisettings → Styles → Bar Bookends**, then select **Bookend Style**:
- **Bar Texture** uses the selected bar's existing cap (the default).
- **Match Border** follows the Window Border: each border has its own ornament. With the plain
  Theme border it uses the bar texture cap.
- Any border's name selects its ornament independently of the border: rods with studs (Brushed
  Silver, Bronze, Mythril), riveted plates set with a jewel (FFXI-inspired, Obsidian, Adaman), jewelled
  spines (Royal Gold, Royal Silver, Royal Platinum) and cut stones (Crystal, Jade, Amethyst).

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
