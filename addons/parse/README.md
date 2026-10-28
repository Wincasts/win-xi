# parse (experimental)

A new packet-based combat parser for Ashita v4, with a winxi overlay. This is **not a port of
`references/parse`**: it has its own decoder, identity model, accounting and tests. It needs no
runtime files from that addon.

## Install

Copy `addons/parse` and `addons/libs/winxi` into Ashita's `addons` folder, merging folders. It needs
**winxi 6 or newer** (copy the updated shared library too). Load it with `/addon load parse`. Do not
also load the reference Parse addon: they share the `/parse` command and the addon name. No native
plugin is needed.

Ashita **4.3+** with packet-chunk support is recommended, so that resent packets can be dropped.
Older versions can record, but show a warning, because duplicate packets may inflate the totals.

## Commands

| Command | Effect |
|---|---|
| `/parse` | Show or hide the overlay; recording goes on |
| `/parse config` | General, Full View, Minimal, Accuracy and Diagnostics settings |
| `/parse test` | Turn a separate 18-person dummy-data preview on or off |
| `/parse test on` or `/parse test off` | Turn the preview on or off explicitly |
| `/parse test 6` | Preview a chosen number of people (1–18) |
| `/parse clear` | Clear what was recorded and arm a new encounter (also resumes recording) |
| `/parse start` or `/parse reset` | Same as clear |
| `/parse pause` | Switch recording and the encounter clock between paused and running |
| `/parse resume` | Continue the encounter, leaving out the time spent paused |
| `/parse report` | Print totals, DPS and observed hit rates to your own chat log |
| `/parse report detail` | Also print each actor's damage by category |
| `/parse status` | Same as report, with diagnostics |
| `/parse capture <name>` | Start a **new encounter** and a diagnostic capture |
| `/parse capture off` | Close the capture; live recording goes on |
| `/parse wsprofile <id> <base TP> <Store TP %> <attempts>` | Save a controlled-test TP profile for a physical WS (ID 1–191) |
| `/parse wsprofile off` | Remove TP profiles without clearing recorded combat |

Zoning or logging out pauses the encounter. Use `start` for a new encounter after zoning, or
`resume` to keep adding across zones on purpose. This version does not detect encounters on its own.

## Minimal overlay

`/parse minimal` switches to a second, quieter view and back. `/parse minimal on` and
`/parse minimal off` choose it explicitly. The original full view stays the default,
with its window size, position, columns and widths unchanged.

Minimal mode has **no background, border, shadow, title, table headers, grid or buttons**.
It uses 12px text at 75% opacity, no row spacing, and shows the top six actors by
recorded damage. The default columns are **actor / share / damage / DPS**. A faint summary
shows the total damage, encounter seconds and whether it is paused. Hidden actors are shown
by a `+N more` line. Shares are still relative to the whole encounter, not just the visible rows.

In `/parse config` → **Minimal**, change the text opacity (20–100%), row count
(1–18), font size (10–18px), name-column width (60–220 at 12px), and row spacing (0–6px).
Choose a font from **Windows Fonts**, or keep **Theme Font**. A missing font, or one that
cannot be loaded, falls back to the theme font. The dark edge round all minimal text, including
the summaries and status labels, is Winxi Theme's **Text Outline** (winxisettings, Game Windows),
shared by every addon. It fades with the text opacity. The font choice is saved per character
and does not affect the full view or the settings window.

Widths scale with the font size. You can turn on or off the encounter summary, damage share,
damage total, DPS, rank numbers, compact K/M numbers, the remaining actor count, and hiding
when empty. The **Minimal** tab also lets you show **Melee** and **Ranged** hit rates, **Magic
Damage**, **WS Count**, **WS Hit % (TP)**, **WS TP Unknown**, **Magic Land %**, and **Magic
Resists**. These use the same stats as Full View, but which ones show is saved separately.
WS Hit % (TP) still needs the experimental WS TP profile. A rate that is not available shows
`--`. Compact K/M formatting also applies to magic damage. Actors stay sorted by total damage.
Names always stay visible. Each numeric column can be hidden on its own. The TEST and PAUSED
markers stay visible even with the summary off.

Drag the text to move the overlay while it is unlocked. **Lock Window** lets mouse input
pass to the game. Unlock it in the settings to move it again. Minimal mode keeps its own
position and saves its settings per character. It follows the same visibility rules as the
full window and never changes recording. Diagnostics and column editing stay in the settings
or the full view.

To preview without fighting:

```text
/parse test 6
/parse minimal on
```

Return to live data with `/parse test off`. Return to the full layout with
`/parse minimal off`. The preview is labeled TEST in either view.

## Settings tabs

- **General:** display mode, pet grouping, skillchains, test preview, fading and visibility rules.
- **Full View:** the window's row-height preset, and which columns the full table shows and in what order.
- **Minimal:** the compact overlay's layout, text, shown statistics and click-through lock.
- **Accuracy:** what the magic and WS accuracy numbers mean, instructions for the experimental TP profile, and the saved profiles.
- **Diagnostics:** status report, last error and unknown message counters.

There is no Winxi Theme tab in Parse's menu. The full view still follows the Winxi theme you
have set. Hiding its editor does not overwrite your theme settings. Minimal mode keeps its own
transparent look.

## Preview and scrolling

Use `/parse test` to open the overlay with **18 dummy people**, with varied damage, hit rates,
spells, weaponskills and skillchains. `/parse test 6` shows a smaller party. The header clearly
marks the view as **TEST / Dummy data**. The preview is the same every time, uses a sample
180-second encounter, and is not saved between reloads.

The dummy data lives in a separate model: **live recording and any existing capture go on
unchanged** behind the preview. Turn it off to return to your live totals. Clear, reset, pause,
resume and starting a new capture are blocked while previewing; turn the preview off first.
Reports made while previewing are marked `[TEST]`. Pet grouping and skillchain settings work on
the sample data too. Separating pets adds companion rows without reducing the number of people.

The main window is **resizable**: drag an edge or its bottom-right grip. Its size is kept in your
character's settings. The results table fills the available width and height, with a **vertical
scrollbar and a fixed header**. Hover over it and use the mouse wheel, or drag its scrollbar.
Click the **cog icon at the top-right** of the Parse window to choose your columns.
The overlay has no New encounter or Pause buttons; use `/parse clear` and `/parse pause` instead.
Tick or untick **Actor, Damage, Share, DPS, Melee, Ranged, Magic Damage, WS Count, WS Hit % (TP),
WS TP Unknown, Magic Land %, Magic Resists**, then use **Up/Down** to set their left-to-right
order. Changes apply at once and are saved per character, including across reloads. Hidden
columns stay in the editor, so you can bring them back or move them. **Reset columns** puts back
the original six-column layout, with the other optional columns hidden. The same editor is under
**Full View → Columns** in `/parse config`. If every column is hidden, the cog button stays
there to bring them back. Live and test views use the same choices. These settings never change
recorded combat data or reports.

**Every column is resizable**: drag the vertical separators in the table header (including the
right edge of the last column). Widths are kept across addon reloads and game restarts through
Ashita's native ImGui table settings in `config/imgui.ini`. They are shared layout settings, not
part of a combat capture or the per-character Parse settings. The starting column widths apply
only when there is no saved layout. Turning the test preview on or off, or starting a new
encounter, does not reset them. Each distinct order of visible columns has its own saved widths,
so a width cannot end up on a different statistic after editing. A new layout starts with the
default widths. Going back to a layout you used before brings back its widths. A horizontal
scrollbar keeps the columns reachable if they are wider than the window.

In `/parse config` → **Full View**, **Visible Rows (preset)** (1–18, default 12) gives a quick
height change. You can then resize freely. Neither resizing nor the preset drops lower-ranked
participants: you can scroll to every row, including separate pets. There is also a test-preview
button in the settings.

## What the numbers mean

- **Magic Damage (optional column):** recognized spell plus magic-burst damage. Turn it on with
  **cog → Magic Damage**. It is part of the total damage, not extra damage added to the total.
  It leaves out ordinary WS, skillchain, additional-effect and pet-ability categories. It is not
  a complete list of every magical damage source in FFXI.

- **Damage:** recognized server-reported outgoing damage against monsters, from you, your current
  party or alliance, trusts, pets and fellows. Outside players are not included.
- **Sources:** melee, ranged, WS, spell, magic burst, ability, pet ability, skillchain, additional
  effect, counter, spikes and retaliation. Each is listed on purpose, rather than assuming that
  every numeric result is damage. Healing, statuses, interrupted or started actions and unknown
  results must not inflate damage.
- **Share:** your share of the chosen, recorded damage. It does not claim to cover all actual damage.
- **DPS:** chosen damage divided by the **same active encounter time for every actor**. The
  clock starts at the first recognized event, includes idle time after it, and leaves out
  pauses. A newly armed encounter has no elapsed time until an event. At zero elapsed time, DPS
  is `--`.
- **Melee:** `(auto-attack hits + accepted TP-inferred WS hits) / (auto-attack hits/misses +
  accepted TP-inferred WS hits/misses)`. Crits count as hits. With WS TP profiles on, this is a
  **mixed observed and estimated rate**. Missing or rejected WS samples never add guessed misses.
  A WS damage event is not also counted as an extra melee hit. For an auto-attack-only test,
  turn off the profiles and clear the parser. Turning off the profiles alone keeps the earlier
  estimates.
- **Ranged:** recognized ranged hits divided by hits plus misses. No WS inference is added.
  Neither rate is the game's own Accuracy stat. Shadows, parries and anticipation are left out
  separately. `0%` means there were eligible trials but no hits. `--` means no eligible trials.
- **WS Count:** one recognized WS action packet, whatever the number of AoE targets or inferred
  strikes. It includes recognized misses of the whole WS. Aborted or unrecognized actions are not
  guessed as attempts.
- **WS Hit % (TP):** estimated landed strikes divided by the set number of attempted strikes, for
  accepted local TP observations only. It is **not** the percentage of WS casts that dealt damage.
- **WS TP Unknown:** local recognized WS outcomes the TP tracker rejected, including missing
  profiles, missing or stale TP, ambiguous returns and contamination. Other players are not
  TP-tracked.
- **Magic Land %:** recognized spell successes divided by successes plus explicitly reported
  resists, including the supported enfeebling outcomes. Damage spells and magic bursts count as
  landed even if partly resisted. Explicit normal, complete and Immunobreak resist messages count
  as resists. No-effect messages are left out. Healing and unsupported utility outcomes are not
  trials. This measures the **observed spell land rate**, not the Magic Accuracy stat or the
  unresisted damage rate.
- **Magic Resists:** the count of those explicitly reported resist outcomes, not damage-tier
  estimates.
- **Grouping:** combine pets with their owners, and include or leave out skillchain damage, in
  the settings. Skillchains belong to the exact closing actor. No abbreviated made-up actors are
  created. These settings change only the view, not the stored observations.
- **Identity:** full names are labels, not database keys. The keys shown in the overlay are
  `zone-epoch:server-ID`. Monsters with the same name stay distinct targets in the accounting.
  An owner plus a pet with the same name cannot collide. Reuse of the *same server ID within one
  zone epoch* is not detected as a new spawn. Start a new encounter when this difference matters.

The pure core keeps categories, ability-ID buckets and per-target buckets. In this first UI,
category breakdowns are available through `report detail`. Per-ability names and target filtering
are not yet shown. AoE counts each affected target or result, so event counts are **not cast
counts**.

## Experimental TP-based WS inference

This feature is **opt-in and limited to your own character**. It is not an alliance-wide hit
counter. Turn on the optional **WS Count**, **WS Hit % (TP)** and **WS TP Unknown** columns with
the cog. The test preview includes dummy WS-strike and magic-land statistics without touching
live records.

Set up each supported physical WS with:

```text
/parse wsprofile <WS ID> <first-hit TP after Store TP> <total Store TP percent> <known attempted hits>
```

For example, **if** a controlled setup really has a 120-TP first-hit return, zero Store TP and four
attempts, `/parse wsprofile 80 120 0 4` describes it. These are made-up values, not defaults for
WS 80. Calibrate the first-hit return with a known single-hit WS under the same weapon, delay and
WS gear, with no extra attacks. Include all Store TP sources in the percentage. Do not guess this
profile from average damage. Profile settings are saved per character, and are listed and can be
removed in `/parse config` → **Accuracy / experimental WS TP**.

For one full-TP strike and N−1 additional attempts, the solver considers **both** the case where
the first hit lands and the case where it misses, matching the whole-number TP return to:

```text
(first hit landed ? calibrated first-hit TP : 0)
  + floor(additional landed hits × 10 × (1 + Store TP / 100))
```

Only a landed-hit count with one possible answer is accepted. In the example, 140 TP means three
landed strikes and one missed attempt. That reading **depends on the profile's assumptions**:

- The set attempt count must be exact. There must be **no DA/TA/QA or other extra attacks**,
  no Save TP, Conserve TP, retained TP, WS-specific bonus TP or hidden TP source. The addon cannot
  read every modifier from client memory, so it cannot check all of these on its own.
- Only a known single melee weapon is supported. Dual wield, H2H, ranged WS IDs and unknown weapon
  context are left out. A grip with weapon skill 0 is allowed. WAR/THF/BLU/RNG/DRG/DNC main or sub
  are left out to be safe, because they can give multi-attacks or Conserve TP, even at levels
  where the trait may not yet apply.
- A matching WS start within five seconds is needed. Equipment must stay unchanged from the start
  through to the TP observation. Swapping gear back at once can therefore reject a sample.
- Recognized buffs that change TP or multi-attack, including Sekkanoki, Meikyo Shisui, Regain,
  relevant rolls, aftermath and charge or flourish effects, are left out. Hidden or unsupported
  effects are still your responsibility when you calibrate a controlled test.
- A fresh `0x0DF` TP update must arrive strictly after the WS and within two seconds. It must then
  stay unchanged for 0.4 seconds while no other action involving you, HP change, equipment change
  or observed death invalidates it. Missing, stale, ambiguous or off-profile TP becomes **unknown**.
- AoE and multi-result WS, and successes with zero or absorbed damage, are left out. Death messages
  received just before the result, or while settling, reject killing blows, so strikes that never
  happened are not called misses. This matching is still a heuristic: delayed or missing packets
  can hide contamination.
- Pause, clear, zoning, profile or settings changes and capture boundaries cancel pending
  inference. A paused parser does not add inferred strikes. Clear resets the accumulated estimates
  too.

**This does not guess a damage baseline.** Magic resist tracking is currently based on explicit
server messages. No partial-resist tier is inferred from low damage. Before you use estimated WS
hit rates for comparisons, capture controlled samples and compare known TP returns.

## Accuracy and limitations

This first version has automated synthetic packet and UI tests, **not live accuracy certification**.
Compare a short live capture against known combat outcomes before you use it for gear testing.

- Damage comes from `0x028`. TP inference also reads `0x0DF` and death messages in `0x029`.
  Periodic DoT ticks, healing totals, defensive rates, buff-state test indexing, threat,
  automatic fights and kill/overkill reconciliation are not implemented. The damage shown is the
  reported result, not a reconstruction of the monster HP removed.
- Additional HP/MP drain effects are not added to hit damage on their own: they may be part of
  that hit. Direct recognized HP-drain spells and abilities are included.
- Only information sent to this client can be measured. Missing or out-of-range events and
  unresolved entities cannot be reconstructed.
- Classification is cautious. Unknowns appear as `category:part:message` counters in the config
  diagnostics. Many are harmless utility outcomes. Some may point to unsupported damage.
- The current roster and ownership are sampled for each action packet. Members who have left, and
  pets that cannot be resolved at the time, are not attributed after the fact. A change of owner
  for the same pet ID within an encounter is not split. Start a new encounter for tests involving
  charm or owner changes.
- Chunk deduplication compares complete action packets against the network chunk just before,
  keeping multiplicity within a chunk. It is not an unlimited history of resent packets.
- Totals live in memory for the current manual encounter. Reloading loses them. Capture and replay
  are for diagnostics, not an in-game import/export feature.

## Diagnostic capture and offline replay

`/parse capture test_01` creates `addons/parse/captures/test_01.txt`. Names may only use
letters, numbers, underscores and hyphens. Existing files are never overwritten. This resets the
current encounter, so replay starts from the same state. Each action packet that was decoded and
accepted carries its monotonic timestamp and resolved identity metadata. Injected packets,
suppressed duplicates and packets received while paused are left out. Pause, resume and reset
markers keep the timeline. Turning the capture off, or unloading, freezes the offline timeline
without pausing live accounting. Version 2 also records WS inference decisions, TP and calibration
evidence and the reasons for exclusions (`W` records), so replay keeps the mixed melee and WS
accuracy without reading current memory. Replay checks the TP arithmetic, but does not rerun the
live eligibility guards from raw TP, gear and buff packets.

Captures contain **character names and raw combat packets**. Treat them as private. The folder
is git-ignored. Captures are written out per record (use them for short diagnostic sessions, not
benchmarks). The last 128 normalized combat events are also kept in a bounded diagnostic ring in
the session.

Copy the file to a machine with LuaJIT and this repository. From the repository root:

```sh
luajit tools/parse_replay.lua /path/to/test_01.txt
luajit tools/parse_replay.lua /path/to/test_01.txt --separate-pets --no-skillchains
```

Replay uses the captured identities rather than live memory. It prints totals, rates, categories
and unknown outcomes. The format is versioned, non-executable text; it is never `loadfile`d. Replay
accepts both v1 and v2. A malformed capture causes a nonzero exit with the line number.

## Development and validation

```sh
luajit tests/parse_check.lua
luajit tests/parse_accuracy_check.lua
luajit tests/harness.lua parse tests/parse_stand_in.lua tests/parse_ui_check.lua
luajit tools/parse_replay.lua tests/fixtures/parse_capture.txt
luajit tools/parse_replay.lua tests/fixtures/parse_accuracy_capture.txt
```

The tests use synthetic packed packets and fixed v1/v2 synthetic captures, not captures claimed to
come from retail. They check unsigned IDs, conditional fields, truncation, same-name actors, pets,
AoE, counters and spikes, skillchains, exclusions, zero rates, timing, replay and chunk multiplicity.
The UI checks run the real addon against the project's Ashita stand-in.

For live validation: start a capture, make several known hits and misses and a WS or skillchain,
pause and resume, then stop the capture. Compare `report detail` with the replay and the known
actions. Repeat with a trust and a pet, a multi-target spell, zoning and a crowded fight. Look at
the unknown counters before making accuracy claims.

### Files

- `parse_packet.lua`: bounded unsigned wire decoder, starting at bit 40.
- `parse_identity.lua`: verified server-ID lookup, roster and companion attribution, zone-scoped keys.
- `parse_classify.lua`: explicit outcomes, and actor/target reversal for reactive damage.
- `parse_core.lua`: pure aggregates, rates, reversible grouping and pause-aware encounter timing.
- `parse_session.lua`: pipeline, diagnostics, capture lifecycle and replay entry point.
- `parse_capture.lua`: versioned text serialization; no executable Lua in captures.
- `parse_dedupe.lua`: adjacent-chunk retransmission comparison.
- `parse_preview.lua`: deterministic dummy observations, kept apart from the live session.
- `parse_columns.lua`: column definitions, visibility and order normalization, and cell formatting.
- `parse_controls.lua`: font-independent cog button drawing.
- `parse_minimal.lua`: compact transparent overlay with its own position and click-through lock.
- `parse_ws.lua`: pure calibrated TP solver and cautious observation and settling state machine.
- `parse_ws_live.lua`: local equipment, buff and job context guards, and party TP packet fields.
- `parse.lua`: Ashita lifecycle, commands and winxi presentation.

Wire-format reference: [XiPackets server 0x0028](https://github.com/atom0s/XiPackets/tree/main/world/server/0x0028).
Protocol identifiers and layout were also checked against the local Phoenix server reference. No
reference addon or server implementation was copied. New code is under the repository's MIT license.
