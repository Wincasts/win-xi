# parse (experimental)

A combat parser: it counts the damage you, your party and your alliance deal, and shows it in a window.
It reads the server's combat messages as they arrive, and shows totals, damage per second (DPS) and hit
rates for each person. It is new: it is not a copy of the older Parse addon, and does not need any of
that addon's files.

## Why use it

- You see who is dealing how much damage, and each person's share and DPS, while you fight.
- You can see observed hit rates for melee, ranged attacks and spells.
- A small, see-through "minimal" view can sit over the game without getting in the way.

This first version has been tested only against made-up data, not in live play. See
[Accuracy and limits](#accuracy-and-limits).

## Install

1. Copy `addons/parse` and `addons/libs/winxi` into Ashita's `addons` folder, merging the folders.
   parse needs **winxi 25 or newer**, so copy the updated winxi library too.
2. Load it with `/addon load parse`.

- Do not also load the older Parse addon. Both use the `/parse` command and the same addon name.
- No plugin is needed.
- Ashita **4.3 or newer** is recommended. It lets parse drop messages the server sent twice. Older
  versions can still record, but show a warning, because repeated messages may make the totals too
  high.

## Commands

| Command | What it does |
|---|---|
| `/parse` | Shows or hides the window. Recording goes on. |
| `/parse config` | Opens the settings: General, Full View, Minimal, Accuracy and Diagnostics. |
| `/parse minimal` | Switches between the full view and the minimal view. |
| `/parse minimal on` or `/parse minimal off` | Chooses the minimal view, or the full view. |
| `/parse test` | Turns a preview with 18 made-up people on or off. |
| `/parse test on` or `/parse test off` | Turns the preview on or off. |
| `/parse test 6` | Previews a chosen number of people (1–18). |
| `/parse clear` | Clears what was recorded and gets ready for a new fight. Also starts recording again. |
| `/parse start` or `/parse reset` | The same as clear. |
| `/parse pause` | Pauses recording and the fight clock, or starts them again. |
| `/parse resume` | Carries on the fight, leaving out the time spent paused. |
| `/parse report` | Prints totals, DPS and observed hit rates in your own chat log. |
| `/parse report detail` | Also prints each person's damage by kind. |
| `/parse status` | The same as report, with technical details. |
| `/parse capture <name>` | Starts a **new fight** and a diagnostic capture (see [Diagnostic capture](#diagnostic-capture)). |
| `/parse capture off` | Closes the capture. Live recording goes on. |
| `/parse wsprofile <id> <base TP> <Store TP %> <attempts>` | Saves a TP profile for a physical weaponskill (ID 1–191), for a controlled test. See [Weaponskill hits from TP](#weaponskill-hits-from-tp-experimental). |
| `/parse wsprofile off` | Removes the TP profiles, without clearing recorded combat. |

### Fights

In this addon a "fight" (encounter) is the stretch of combat being counted.

- parse does not start and stop fights on its own in this version. Use `/parse clear` to start one.
- Changing zone or logging out pauses the fight.
- After changing zone, use `/parse start` for a new fight, or `/parse resume` to keep adding across
  zones on purpose.

## The full view

The full view is the default window.

- You can resize it: drag an edge or its bottom-right corner. Its size is saved for your character.
- The results table fills the window. It has a fixed header row and a scroll bar. Use the mouse wheel
  over it, or drag the scroll bar.
- The window has no "New encounter" or "Pause" buttons. Use `/parse clear` and `/parse pause`.

### Choosing columns

Click the **cog icon at the top right** of the Parse window to choose your columns.

- Tick or untick **Actor, Damage, Share, DPS, Melee, Ranged, Magic Damage, WS Count, WS Hit % (TP),
  WS TP Unknown, Magic Land %, Magic Resists**.
- Use **Up/Down** to set their order from left to right.
- Changes show at once, and are saved for your character, including across reloads.
- Hidden columns stay in the list, so you can bring them back or move them.
- **Reset columns** goes back to the original six columns, with the other columns hidden.
- The same list is under **Full View → Columns** in `/parse config`.
- If every column is hidden, the cog button stays, so you can bring them back.
- The live view and the test preview use the same choices.
- These settings never change the recorded combat or the reports.

### Column widths

**Every column can be resized**: drag the lines between the column headings (including the right
edge of the last column).

- Widths are kept across addon reloads and game restarts, in Ashita's `config/imgui.ini`. They are
  shared window settings, not part of a capture or of your character's Parse settings.
- The starting widths apply only when no layout has been saved yet.
- Turning the preview on or off, or starting a new fight, does not reset them.
- Each order of visible columns keeps its own widths, so a width cannot end up on a different column
  after you change the order. A new order starts with the default widths. Going back to an order you
  used before brings back its widths.
- If the columns are wider than the window, a scroll bar across the bottom lets you reach them.

### Height

In `/parse config` → **Full View**, **Visible Rows (preset)** (1–18, default 12) changes the height
quickly. You can then resize freely. Neither resizing nor the preset leaves out lower-ranked people:
you can scroll to every row, including separate pets. There is also a test-preview button in the
settings.

## The minimal view

`/parse minimal` switches to a second, quieter view and back. `/parse minimal on` and
`/parse minimal off` choose one. The full view stays the default, and its size, position, columns and
widths do not change.

The minimal view has **no background, border, shadow, title, column headings, grid or buttons**.

- It uses 12-pixel text at 75% opacity, with no space between rows.
- It shows the top six people by damage recorded.
- The default columns are **actor / share / damage / DPS** ("actor" means a person or pet).
- A faint summary line shows the total damage, the fight's length in seconds, and whether it is
  paused.
- A `+N more` line counts the people not shown. Shares are still of the whole fight, not just the rows
  shown.

### Minimal settings

In `/parse config` → **Minimal** you can change:

- the text opacity (20–100%), the number of rows (1–18), the font size (10–18 pixels), the name
  column's width (60–220 at 12 pixels) and the space between rows (0–6 pixels);
- the font: choose one from **Windows Fonts**, or keep **Theme Font**. If a font is missing or cannot
  be loaded, the theme font is used. The font choice is saved for your character. It does not change
  the full view or the settings window;
- what shows: the fight summary, damage share, damage total, DPS, rank numbers, short K/M numbers, the
  count of people not shown, and hiding when empty;
- extra columns: **Melee** and **Ranged** hit rates, **Magic Damage**, **WS Count**, **WS Hit % (TP)**,
  **WS TP Unknown**, **Magic Land %** and **Magic Resists**. These are the same numbers as in the full
  view, but which ones show is saved separately.

More about the minimal view:

- The dark edge round all the text is Winxi Theme's **Text Outline** (set in wxi, Game Windows), shared
  by every addon. It fades with the text opacity.
- Widths grow and shrink with the font size.
- WS Hit % (TP) still needs the experimental weaponskill TP profile.
- A rate that cannot be worked out shows `--`.
- Short K/M numbers apply to magic damage too.
- People stay sorted by total damage. Names always show. Each number column can be hidden on its own.
- The TEST and PAUSED labels stay even with the summary off.

### Moving it

- While it is unlocked, drag the text to move it.
- **Lock Window** lets the mouse click through to the game. Unlock it in the settings to move it again.
- The minimal view keeps its own position and saves its settings for each character.
- It follows the same hiding rules as the full window, and never changes the recording.
- Diagnostics and column editing stay in the settings or the full view.

## Preview (test data)

Use `/parse test` to open the window with **18 made-up people**, with varied damage, hit rates, spells,
weaponskills and skillchains. `/parse test 6` shows a smaller party.

- The header clearly says **TEST / Dummy data**. The preview is labelled TEST in either view.
- The preview is the same every time. It uses a sample fight of 180 seconds, and is not saved between
  reloads.
- **Live recording, and any capture, go on unchanged** behind the preview. Turn the preview off to see
  your live totals again.
- Clear, reset, pause, resume and starting a new capture do not work while the preview is on. Turn the
  preview off first.
- Reports made during the preview are marked `[TEST]`.
- The pet and skillchain settings work on the sample data too. Showing pets separately adds pet rows
  without reducing the number of people.

To preview the minimal view without fighting:

```text
/parse test 6
/parse minimal on
```

Go back to live data with `/parse test off`, and back to the full view with `/parse minimal off`.

## Settings tabs

- **General**: display mode, pet grouping, skillchains, test preview, fading and hiding rules.
- **Full View**: the window's row-height preset, and which columns the full table shows, and in what
  order.
- **Minimal**: the minimal view's layout, text, which numbers show, and the click-through lock.
- **Accuracy**: what the magic and weaponskill accuracy numbers mean, how to use the experimental TP
  profile, and the saved profiles.
- **Diagnostics**: a status report, the last error, and counts of messages parse did not recognise.

There is no Winxi Theme tab in Parse's settings. The full view still follows the Winxi theme you have
set, and your theme settings are not changed. The minimal view keeps its own see-through look.

## What the numbers mean

"Recognised" below means parse knows what that kind of server message is. parse only counts what it
recognises.

| Number | What it is |
|---|---|
| **Damage** | Recognised damage dealt to monsters by you, your current party or alliance, trusts, pets and fellows. Players outside your party and alliance are not counted. |
| **Share** | Each person's share of the damage recorded. It does not claim to cover all the damage actually dealt. |
| **DPS** | Damage divided by the **same fight time for everyone**. The clock starts at the first recognised event, includes idle time after it, and leaves out pauses. A new fight has no time until the first event. With no time yet, DPS is `--`. |
| **Melee** | Hit rate of auto-attacks, plus accepted weaponskill hits worked out from TP (see below). |
| **Ranged** | Recognised ranged hits divided by hits plus misses. |
| **Magic Damage** | (optional column) Recognised spell damage plus magic burst damage. |
| **WS Count** | The number of recognised weaponskills used. |
| **WS Hit % (TP)** | Estimated weaponskill hits that landed, out of the attempts set in the profile. |
| **WS TP Unknown** | Your weaponskills that the TP tracker could not use. |
| **Magic Land %** | Spells that landed, out of spells that landed plus spells reported as resisted. |
| **Magic Resists** | The count of resists the server reported. |

More detail on each:

- **Damage sources** counted: melee, ranged, weaponskill, spell, magic burst, ability, pet ability,
  skillchain, additional effect, counter, spikes and retaliation. Each one is listed on purpose, rather
  than counting every number as damage. Healing, statuses, interrupted or started actions and unknown
  results must not add to damage.
- **Magic Damage**: turn it on with **cog → Magic Damage**. It is part of total damage, not extra
  damage added on top. It leaves out normal weaponskill, skillchain, additional effect and pet ability
  damage. It is not a full list of every kind of magic damage in FFXI.
- **Melee**: `(auto-attack hits + accepted TP-inferred WS hits) / (auto-attack hits and misses +
  accepted TP-inferred WS hits and misses)`. Critical hits count as hits.
  - With weaponskill TP profiles on, this is a **mix of seen and estimated hits**.
  - A missing or rejected weaponskill never adds guessed misses.
  - A weaponskill's damage is not also counted as an extra melee hit.
  - For an auto-attack-only test, turn off the profiles and clear the parser. Turning off the
    profiles alone keeps the earlier estimates.
- **Ranged**: no weaponskill estimates are added.
- Melee and Ranged are not the game's own Accuracy stat. Shadows, parries and anticipation are left
  out of both. `0%` means there were attacks but no hits. `--` means there were no attacks to count.
- **WS Count**: one weaponskill counts once, however many targets it hits (area of effect) or however
  many strikes are worked out. It includes recognised misses of the whole weaponskill. Cancelled or
  unrecognised actions are not guessed as attempts.
- **WS Hit % (TP)**: only for your own weaponskills with an accepted TP reading. It is **not** the
  percentage of weaponskills that did damage.
- **WS TP Unknown**: includes missing profiles, missing or out-of-date TP, unclear TP returns, and
  readings spoiled by other events. Other players' TP is not tracked.
- **Magic Land %**: spells that landed divided by landed plus resisted, including the enfeebling
  results parse supports.
  - Damage spells and magic bursts count as landed even if partly resisted.
  - Normal, complete and Immunobreak resist messages count as resists.
  - "No effect" messages are left out.
  - Healing and unsupported support spells are not counted.
  - This is the **seen land rate of spells**, not the Magic Accuracy stat and not the rate of
    unresisted damage.
- **Magic Resists**: the count of resists the server reported, not estimates from low damage.

### Grouping and names

- **Grouping**: in the settings you can combine pets with their owners, and include or leave out
  skillchain damage. A skillchain belongs to the person who closed it. No made-up short names are
  created. These settings change only the view, not what was recorded.
- **Names**: names are only labels. Behind them, parse tells people and monsters apart by the zone
  visit and the server's ID for them, shown as `zone-epoch:server-ID`. ("Zone epoch" means one visit to
  a zone.)
  - Monsters with the same name are still counted as separate targets.
  - An owner and a pet with the same name are not mixed up.
  - If the server reuses the *same ID within one zone visit*, parse does not see it as a new monster.
    Start a new fight when this matters.

In this first version, damage by kind is shown only with `/parse report detail`. Names of each ability,
and filtering by target, are not shown yet. An area-of-effect action counts each target it hits, so
event counts are **not counts of casts**.

## Weaponskill hits from TP (experimental)

This feature is **off unless you set it up, and only for your own character**. It is not a hit counter
for the whole alliance. Turn on the optional **WS Count**, **WS Hit % (TP)** and **WS TP Unknown**
columns with the cog. The test preview includes made-up weaponskill and spell-land numbers, without
touching your live records.

The idea: after a weaponskill, the TP you get back depends on how many of its hits landed. If you tell
parse exactly how much TP each hit gives back, it can work out how many hits landed.

Set up each physical weaponskill with:

```text
/parse wsprofile <WS ID> <first-hit TP after Store TP> <total Store TP percent> <known attempted hits>
```

For example, **if** a controlled setup really gives 120 TP back for the first hit, has no Store TP and
four hits, `/parse wsprofile 80 120 0 4` describes it. These are made-up values, not defaults for
weaponskill 80.

- Measure the first-hit TP with a known single-hit weaponskill, using the same weapon, delay and
  weaponskill gear, with no extra attacks.
- Include every source of Store TP in the percentage.
- Do not guess this profile from average damage.
- Profiles are saved for each character. You can see and remove them in `/parse config` →
  **Accuracy / experimental WS TP**.

For one full-TP strike and N−1 more attempts, parse checks **both** the case where the first hit lands
and the case where it misses. It matches the whole-number TP you get back to:

```text
(first hit landed ? calibrated first-hit TP : 0)
  + floor(additional landed hits × 10 × (1 + Store TP / 100))
```

A reading is accepted only when exactly one number of landed hits fits. In the example, 140 TP means
three hits landed and one missed. That reading **depends on the profile being right**:

- The attempt count must be exact. There must be **no Double, Triple or Quadruple Attack or other extra
  attacks**, and no Save TP, Conserve TP, kept TP, weaponskill bonus TP or hidden TP source. parse
  cannot read every one of these from the game, so it cannot check them all itself.
- Only one known melee weapon is supported. Dual wield, hand-to-hand, ranged weaponskills and unknown
  weapons are left out. A grip (weapon skill 0) is allowed. WAR, THF, BLU, RNG, DRG and DNC, as main or
  support job, are left out to be safe, because they can give extra attacks or Conserve TP, even at
  levels where the trait may not apply yet.
- The weaponskill must have started within the last five seconds. Your gear must not change from the
  start until the TP reading. So swapping gear back at once can make a sample be rejected.
- Known buffs that change TP or extra attacks are left out. These include Sekkanoki, Meikyo Shisui,
  Regain, the rolls that matter, aftermath, and charge or flourish effects. Hidden or unsupported
  effects are still up to you to avoid when you set up a controlled test.
- A new TP update must arrive after the weaponskill, within two seconds. It must then stay the same
  for 0.4 seconds, with no other action involving you, HP change, gear change or death that would
  spoil it. Missing, old, unclear or off-profile TP is counted as **unknown**.
- Area-of-effect and multi-target weaponskills, and hits that did zero or absorbed damage, are left
  out. If a death message comes just before the result, or while waiting, the killing blow is
  rejected, so strikes that never happened are not called misses. This matching is still a best guess:
  late or missing messages can hide problems.
- Pausing, clearing, changing zone, changing a profile or setting, and starting or closing a capture
  all cancel a reading in progress. A paused parser does not add estimated hits. Clear also resets the
  estimates.

**This does not guess damage.** Spell resists are counted only from the server's resist messages.
Partial resists are not guessed from low damage. Before you compare estimated weaponskill hit rates,
record controlled samples and compare known TP returns.

## Accuracy and limits

This first version has been tested only against made-up data. It is **not proven accurate in live
play**. Compare a short live capture against combat results you know before you use it to test gear.

- Damage comes from the server's action messages. The TP feature also reads TP updates and death
  messages.
- Not done yet: damage over time ticks, healing totals, defence rates, buff-based test sorting, enmity,
  automatic fight detection, and matching kills and overkill. The damage shown is what the server
  reported, not the monster HP actually removed.
- Extra HP or MP drain effects are not added to a hit's damage, because they may already be part of
  that hit. Recognised HP-drain spells and abilities are included.
- Only what the server sends to your game can be measured. Events that were missing, out of range, or
  about characters that could not be identified cannot be rebuilt.
- parse is careful about what it counts. Unknown messages show as `category:part:message` counts in
  the Diagnostics tab. Many are harmless support effects. Some may point to damage parse does not
  support yet.
- Your party and who owns which pet are checked at each action. Members who have left, and pets whose
  owner cannot be found at that moment, are not credited later. If a pet changes owner during a fight,
  it is not split. Start a new fight for tests with charm or changes of owner.
- Messages the server sent twice are dropped by comparing each one with the batch of messages just
  before it. This does not catch every repeat.
- Totals are kept only in memory, for the current fight you started. Reloading loses them. Captures
  are for diagnostics, not a way to save or load results in game.

## Diagnostic capture

If you are asked to send a capture, make one like this:

- `/parse capture test_01` creates `addons/parse/captures/test_01.txt`. Names may use only letters,
  numbers, underscores and hyphens. Existing files are never overwritten.
- Starting a capture resets the current fight.
- `/parse capture off` (or unloading the addon) closes it. Closing the capture does not pause live
  recording.
- Messages received while paused are left out.

Captures contain **character names and the raw combat data from the server**. Keep them private. Use
them for short diagnostic sessions, not for benchmarks.
