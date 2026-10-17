# Parse 0.5.0 — experimental

A new packet-based combat parser for Ashita v4, with a winxi overlay. This is **not a port of
`references/parse`**: it has its own decoder, identity model, accounting and tests. No runtime files
from that addon are required.

## Install

Copy `addons/parse` and `addons/libs/winxi` into Ashita's `addons` folder, merging folders. Needs
**winxi 6 or newer** (copy the updated shared library too). Load with `/addon load parse`. Do not also load the reference Parse addon:
they share the `/parse` command and addon name. No native plugin is needed.

Ashita **4.3+** with packet-chunk support is recommended for retransmission suppression. Older
versions can record, but display a warning because duplicate packets may inflate totals.

## Commands

| Command | Effect |
|---|---|
| `/parse` | Show/hide the overlay; does not stop recording |
| `/parse config` | Settings, shared theme, visibility rules and diagnostics |
| `/parse test` | Toggle an isolated 18-person dummy-data preview |
| `/parse test on` or `/parse test off` | Explicitly enable/disable the preview |
| `/parse test 6` | Preview a chosen number of people (1–18) |
| `/parse clear` | Clear observations and arm a new encounter (also resumes recording) |
| `/parse start` or `/parse reset` | Aliases for clear |
| `/parse pause` | Toggle recording and the encounter clock between paused and running |
| `/parse resume` | Continue the encounter, excluding time spent paused |
| `/parse report` | Print totals, DPS and observed hit rates to your own chat log |
| `/parse report detail` | Also print each actor's damage-category breakdown |
| `/parse status` | Same as report, including diagnostics |
| `/parse capture <name>` | Start a **new encounter** and a diagnostic capture |
| `/parse capture off` | Close the capture; live recording continues |
| `/parse wsprofile <id> <base TP> <Store TP %> <attempts>` | Save a controlled-test TP profile for a physical WS (ID 1–191) |
| `/parse wsprofile off` | Remove TP profiles without clearing recorded combat |

Zoning/logging out pauses the encounter. Use `start` for a new encounter after zoning, or `resume`
to accumulate across zones deliberately. There is no automatic encounter detection in this version.

## Preview and scrolling

Use `/parse test` to open the overlay with **18 dummy people**, varied damage, hit rates, spells,
weaponskills and skillchains. `/parse test 6` shows a smaller party. The header clearly marks the
view as **TEST / Dummy data**. The preview is deterministic, uses a sample 180-second encounter,
and is not saved between reloads.

Dummy observations live in a separate model: **live recording and any existing capture continue
unchanged** behind the preview. Turn it off to return to your live totals. Clear/reset/pause/resume and
starting a new capture are protected while previewing; turn the preview off first. Reports while
previewing are marked `[TEST]`. Pet grouping and skillchain settings work on the sample data too;
separating pets adds companion rows without reducing the number of people.

The main window is **resizable**: drag an edge or its bottom-right grip. Its size is kept in your
character's settings. The results table fills the available width and height, with a **vertical
scrollbar and a fixed header**; hover it and use the mouse wheel or drag its scrollbar.
Click the **cog icon at the top-right** of the Parse window to choose your columns.
The overlay has no New encounter or Pause buttons; use `/parse clear` and `/parse pause` instead. Check/uncheck **Actor,
Damage, Share, DPS, Melee, Ranged, Magic Damage, WS Count, WS Hit % (TP), WS TP Unknown,
Magic Land %, Magic Resists**, then use **Up/Down** to set their left-to-right order.
Changes apply immediately and are saved per character, including across reloads. Hidden columns
remain in the editor so they can be restored or moved. **Reset columns** restores the original
six-column visible layout, with the other optional columns hidden by default. The same editor is available
under **Columns** in `/parse config`.
If every column is hidden, the cog button stays available to restore them. Live and test views
use the same choices; these settings never alter recorded combat data or reports.

**Every column is resizable**: drag the vertical separators in the table header (including the
right edge of the last column). Widths are retained across addon reloads and game restarts through
Ashita's native ImGui table settings in `config/imgui.ini`. They are shared layout settings, not
part of a combat capture or the per-character Parse settings. Initial column widths apply only
when there is no saved layout; toggling the test preview or starting a new encounter does not
reset them. Each distinct visible-column order has its own saved width layout, so a width cannot
accidentally attach to a different statistic after editing. A new layout starts with default widths;
returning to a previously used layout restores its widths. A horizontal scrollbar keeps columns
accessible if they exceed the window width.

In `/parse config`, **Visible Rows (preset)** (1–18, default 12) provides a quick height adjustment;
you can then resize freely. Neither resizing nor the preset discards lower-ranked participants:
all rows remain reachable by scrolling, including separate pets. There is also a test-preview
button in settings.

## What the numbers mean

- **Magic Damage (optional column):** recognized spell plus magic-burst damage. Enable it with
  **cog → Magic Damage**. This is a subset of total damage, not extra damage added to the total.
  It excludes ordinary WS, skillchain, additional-effect and pet-ability categories; this is not
  an exhaustive classification of every magical damage source in FFXI.

- **Damage:** recognized server-reported outgoing damage against monsters, from you, your current
  party/alliance, trusts, pets and fellows. Outside players are not included.
- **Sources:** melee, ranged, WS, spell, magic burst, ability, pet ability, skillchain, additional
  effect, counter, spikes and retaliation. Coverage is deliberately explicit rather than assuming
  every numeric result is damage. Healing, statuses, interrupted/start actions and unknown results
  must not inflate damage.
- **Share:** your share of the selected, recorded damage. Not a claim to cover all actual damage.
- **DPS:** selected damage divided by the **same active encounter duration for every actor**. The
  clock starts at the first recognized event, includes subsequent idle time, and excludes pauses.
  A newly armed encounter has no elapsed time until an event. At zero elapsed time DPS is `--`.
- **Melee:** `(auto-attack hits + accepted TP-inferred WS hits) / (auto-attack hits/misses +
  accepted TP-inferred WS hits/misses)`. Crits count as hits. This is now a **mixed observed/estimated
  rate** if WS TP profiles are enabled. Missing or rejected WS samples never contribute guessed
  misses. A WS damage event is not also counted as an extra melee hit. Disable profiles and clear
  the parser for an auto-attack-only test; disabling profiles alone preserves earlier estimates.
- **Ranged:** recognized ranged hits divided by hits plus misses; no WS inference is added.
  Neither rate is the game's underlying Accuracy stat. Shadows/parries/anticipation are separate
  exclusions. `0%` means eligible trials with no hits; `--` means no eligible trials.
- **WS Count:** one recognized WS action packet, regardless of AoE target count or inferred strikes.
  Includes recognized entire-WS misses; aborted/unrecognized actions are not guessed as attempts.
- **WS Hit % (TP):** estimated landed strikes divided by the configured attempted strikes, for
  accepted local TP observations only. It is **not** the percentage of WS casts dealing damage.
- **WS TP Unknown:** local recognized WS outcomes rejected by the TP tracker, including missing
  profiles, missing/stale TP, ambiguous returns and contamination. Other players are not TP-tracked.
- **Magic Land %:** recognized spell successes divided by successes plus explicitly reported
  resists, including supported enfeebling outcomes. Damage spells and magic bursts count as landed
  even if partially resisted. Explicit normal, complete and Immunobreak resist messages count as
  resists. No-effect messages are excluded; healing and unsupported utility outcomes are not trials.
  This measures **observed spell land rate**, not the Magic Accuracy stat or unresisted damage rate.
- **Magic Resists:** count of those explicitly reported resist outcomes, not damage-tier estimates.
- **Grouping:** combine pets with owners and include/exclude skillchain damage in settings.
  Skillchains belong to the exact closing actor; no abbreviated synthetic actors are created.
  These settings change only the view, not the stored observations.
- **Identity:** full names are labels, not database keys. Keys shown in the overlay are
  `zone-epoch:server-ID`. Monsters with identical names remain distinct targets in accounting.
  An owner plus a pet with the same name cannot collide. Reuse of the *same server ID within one
  zone epoch* is not detected as a new spawn; start a new encounter when this distinction matters.

The pure core retains categories, ability-ID buckets and per-target buckets. In this first UI,
category breakdowns are available through `report detail`; per-ability names and target filtering
are not yet exposed. AoE counts each affected target/result, so event counts are **not cast counts**.

## Experimental TP-based WS inference

This feature is **opt-in and limited to your own character**, not an alliance-wide hit counter.
Enable the optional **WS Count**, **WS Hit % (TP)** and **WS TP Unknown** columns using the cog.
The test preview includes dummy WS-strike and magic-land statistics without touching live records.

Configure each supported physical WS with:

```text
/parse wsprofile <WS ID> <first-hit TP after Store TP> <total Store TP percent> <known attempted hits>
```

For example, **if** a controlled setup really has a 120-TP first-hit return, zero Store TP and four
attempts, `/parse wsprofile 80 120 0 4` describes it. These are hypothetical values, not defaults for
WS 80. Calibrate the first-hit return with a known single-hit WS under the same weapon/delay and
WS gear, with no extra attacks. Include all Store TP sources in the percentage. Do not guess this
profile from average damage. Profile settings are saved per character and listed/removable in
`/parse config` → **Accuracy / experimental WS TP**.

For one full-TP strike and N−1 additional attempts, the solver considers **both** first-hit land
and first-hit miss cases, matching integer TP return to:

```text
(first hit landed ? calibrated first-hit TP : 0)
  + floor(additional landed hits × 10 × (1 + Store TP / 100))
```

Only a unique landed-hit count is accepted. In the example, 140 TP indicates three landed strikes
and one missed attempt. That interpretation is **conditional on the profile's assumptions**:

- The configured attempt count must be exact. There must be **no DA/TA/QA or other extra attacks**,
  no Save TP, Conserve TP, retained TP, WS-specific bonus TP or hidden TP source. We cannot read
  every modifier from client memory, so these conditions cannot all be independently verified.
- Only a known single melee weapon is supported. Dual wield, H2H, ranged WS IDs and unknown weapon
  context are excluded. A grip with weapon skill 0 is allowed. WAR/THF/BLU/RNG/DRG/DNC main or sub
  are conservatively excluded because they can supply multi-attacks or Conserve TP, even at levels
  where the relevant trait may not yet apply.
- A matching WS start within five seconds is required. Equipment must stay unchanged from start
  through TP observation. Gear-swapping back immediately can therefore reject a sample.
- Recognized TP/multi-attack-altering buffs, including Sekkanoki, Meikyo Shisui, Regain, relevant
  rolls, aftermath and charge/flourish effects, are excluded. Hidden or unsupported effects are
  still the user's responsibility when calibrating a controlled test.
- A fresh `0x0DF` TP update must arrive strictly after the WS and within two seconds. It must then
  remain unchanged for 0.4 seconds while no other action involving you, HP change, equipment change
  or observed death invalidates it. Missing/stale/ambiguous/off-profile TP becomes **unknown**.
- AoE/multi-result WS and zero/absorbed-damage successes are excluded. Death messages received just
  before the result or during settling reject killing blows so unexecuted strikes are not called
  misses. This correlation is still a heuristic: delayed/missing packets can hide contamination.
- Pause, clear, zoning, profile/settings changes and capture boundaries cancel pending inference.
  A paused parser does not accumulate inferred strikes. Clear resets accumulated estimates too.

**This does not implement a damage-baseline guesser.** Magic resist tracking is currently based
on explicit server messages; no partial-resist tier is inferred from low damage. Before using
estimated WS hit rates for comparisons, capture controlled samples and compare known TP returns.

## Accuracy and limitations

This first version has automated synthetic packet and UI tests, **not live accuracy certification**.
Compare a short live capture against known combat outcomes before using it for gear testing.

- Damage comes from `0x028`; TP inference also reads `0x0DF` and death messages in `0x029`.
  Periodic DoT ticks, healing totals, defensive rates,
  buff-state test indexing, threat, automatic fights and kill/overkill reconciliation are not
  implemented. Displayed damage is the reported result, not reconstructed monster HP removed.
- Additional HP/MP drain effects are not automatically added to hit damage: they may be part of
  that hit. Direct recognized HP-drain spells/abilities are included.
- Only information delivered to this client can be measured. Missing/out-of-range events and
  unresolved entities cannot be reconstructed.
- Classification coverage is conservative. Unknowns appear as `category:part:message` counters in
  config diagnostics. Many are harmless utility outcomes; some may indicate unsupported damage.
- The current roster and ownership are sampled for each action packet. Departed members and pets
  that cannot be resolved at observation time are not retrospectively attributed. Ownership
  changes for the same pet ID within an encounter are not split; start a new encounter for tests
  involving charm/owner transitions.
- Chunk deduplication compares complete action packets against the immediately preceding network
  chunk, preserving multiplicity within a chunk. It is not an unlimited retransmission history.
- Aggregates live in memory for the current manual encounter. Reloading loses them. Capture/replay
  is diagnostic persistence, not an in-game import/export interface.

## Diagnostic capture and offline replay

`/parse capture test_01` creates `addons/parse/captures/test_01.txt`. Names are restricted to
letters/numbers/underscores/hyphens. Existing files are never overwritten. This resets the current
encounter so replay starts from the same state. Each successfully decoded, accepted action packet carries
its monotonic timestamp and resolved identity metadata. Injected packets, suppressed duplicates,
and packets received while paused are excluded. Pause/resume/reset markers preserve the timeline.
Capture-off/unload freezes the offline timeline without pausing live accounting. Version 2 also
records WS inference decisions, TP/calibration evidence and exclusion reasons (`W` records), so
replay preserves mixed melee/WS accuracy without consulting current memory. Replay validates the
TP arithmetic, but does not rerun the live eligibility guards from raw TP/gear/buff packets.

Captures contain **character names and raw combat packets**. Treat them as private. The directory
is git-ignored. Captures are flushed per record (use for short diagnostic sessions, not benchmarks).
The last 128 normalized combat events are also kept in a bounded diagnostic ring in the session.

Copy the file to a machine with LuaJIT and this repository. From the repository root:

```sh
luajit tools/parse_replay.lua /path/to/test_01.txt
luajit tools/parse_replay.lua /path/to/test_01.txt --separate-pets --no-skillchains
```

Replay uses the captured identities rather than live memory. It prints totals, rates, categories,
and unknown outcomes. The format is versioned, non-executable text; it is never `loadfile`d. Replay accepts both v1 and v2.
A malformed capture causes a nonzero exit with the line number.

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
AoE, counters/spikes, skillchains, exclusions, zero rates, timing, replay and chunk multiplicity.
The UI checks exercise the real addon against the project's Ashita stand-in.

For live validation: start a capture, make several known hits/misses and a WS/skillchain, pause and
resume, then stop capture. Compare `report detail` with replay and the known actions. Repeat with
a trust and a pet, a multi-target spell, zoning and a crowded fight. Inspect unknown counters
before making accuracy claims.

### Files

- `parse_packet.lua`: bounded unsigned wire decoder, starting at bit 40.
- `parse_identity.lua`: verified server-ID lookup, roster/companion attribution, zone-scoped keys.
- `parse_classify.lua`: explicit outcomes and actor/target reversal for reactive damage.
- `parse_core.lua`: pure aggregates, rates, reversible grouping and pause-aware encounter timing.
- `parse_session.lua`: pipeline, diagnostics, capture lifecycle and replay entry point.
- `parse_capture.lua`: versioned text serialization; no executable Lua in captures.
- `parse_dedupe.lua`: adjacent-chunk retransmission comparison.
- `parse_preview.lua`: deterministic dummy observations isolated from the live session.
- `parse_columns.lua`: column definitions, visibility/order normalization and cell formatting.
- `parse_controls.lua`: font-independent cog button drawing.
- `parse_ws.lua`: pure calibrated TP solver and conservative observation/settling state machine.
- `parse_ws_live.lua`: local equipment/buff/job context guards and party TP packet fields.
- `parse.lua`: Ashita lifecycle, commands and winxi presentation.

Wire-format reference: [XiPackets server 0x0028](https://github.com/atom0s/XiPackets/tree/main/world/server/0x0028).
Protocol identifiers/layout were also checked against the local Phoenix server reference. No
reference addon or server implementation was copied. New code is under the repository's MIT license.
