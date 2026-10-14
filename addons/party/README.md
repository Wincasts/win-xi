# party
Party, target and pet frames in winxi's themed windows, with bars and a layout after the Windower
addon [XivParty](https://github.com/Tylas11/XivParty)'s compact one.

- **Party**: your party and the other two alliance parties. A member is a line: the name, an HP bar
  and a smaller MP bar with their values, and TP as a value. The member targeted has `>>` before
  their name, in blue; a leader has a circle before theirs. Your own party's list grows upwards, and
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
`/xif` (or `/xiframes`) opens the settings: `/party` is the game's own party chat, so the addon keeps
the commands it had as xiframes. Its Style tab sets how every frame is drawn (sizes,
where the values sit, the outline); Party, Target and Pets have what is each one's own. The Winxi
Theme tab, last and coloured apart, is winxi's shared theme: the colours, padding and shadow, and its
Styles section, with the Window Border, Bar Texture, Bar Bookends, Bookend Style and Custom
Icons (the status icons) that were once this addon's own. What was set of those here is carried into the theme. Organize, at the foot of the window, fills the frames with sample data to drag into place.

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

`tests/run.sh` loads the addon against a stand-in for Ashita, and compares what it draws, call for
call, with a kept copy.

## window borders
In `/xif` → **Winxi Theme → Styles → Window Border**, choose **Theme** (the existing border), **Brushed Silver**,
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

## window backgrounds
In `/xif` → **Winxi Theme → Styles → Window Background**, choose **Plain** (the flat Background
Color, the default), **Gradient** (lighter at the top, darker at the bottom), **FFXI-inspired** (that
gradient with a fine dark line on every other row, after the look of the game's own windows),
**Grain** (soft stone), **Marble** (faint veins), **Weave** (linen) or **Brushed Metal**.
Each is drawn in your Background Color, its opacity included, and fades with the window. Like the
border, it is part of winxi's theme and drawn on every game window; settings windows stay plain.

Preview: [`libs/winxi/assets/backgrounds/preview.png`](../libs/winxi/assets/backgrounds/preview.png).
Regenerate the tiles with `python3 tools/generate_winxi_backgrounds.py` (Pillow and numpy); no game
art is used.

## bar textures
In `/xif` → **Winxi Theme → Styles → Bar Texture**, choose:
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
Enable **Winxi Theme → Styles → Bar Bookends**, then select **Bookend Style**:
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
