# cooldowns

Displays player ability and spell recasts in a winxi-styled frame titled **Cooldowns**, using the shared theme.

Load with `/addon load cooldowns`, reload with `/addon reload cooldowns`, and open display settings
with `/cooldowns`. The folder, registered addon name and command all use **cooldowns**.

Window styling is handled exclusively by winxi's shared theme;
cooldowns has no local theme, background, border, font or padding controls. Old local style
overrides are discarded.

- **Ability name color** and **Spell name color**: independent RGBA colors for player ability and
  spell names, saved per character. Both default to white. Only names use these colors: countdowns
  use their normal theme color until reaching the configurable urgency thresholds below.
- **Warning below (seconds)** and **Critical at or below (seconds)**: whole-second countdown
  thresholds, defaulting to 20 and 5 respectively. Critical takes priority and is inclusive; warning
  is exclusive. **Warning countdown color** and **Critical countdown color** independently configure
  their RGBA colors (including alpha), defaulting to yellow and red. Both apply to player and pet
  countdowns and the sample preview, without changing skill-name colors. Colors and thresholds are
  saved per character; seconds cannot be negative, and critical is clamped to warning if necessary.
  Above the thresholds, countdowns retain the shared theme's text color.
  Set both thresholds to zero to disable urgency coloring on running cooldowns.
- **Show pet cooldowns** (on by default): show observed automaton spell, Bash, Shot, and fitted
  attachment cooldowns below player recasts, separated by a horizontal line styled by winxi.
  The separator appears only when both player and pet cooldowns are visible, with the window's
  shared padding above and below it. Spell choice and weaponskill choice/current TP remain in Puppet.
- **Show sample data**: preview player and pet timers while the settings window is open. This is
  temporary and is not saved. The pet toggle and name colors also apply to the preview. Your current
  main job's two-hour ability is included with a `1h 59m 17s` recast to test long countdowns.
- **Sort by time remaining** (off by default): sort each section by the actual remaining time.
  Choose **Ascending (shortest first)** or **Descending (longest first)** when enabled. Player and pet
  sections remain separate; spells and abilities within each section are sorted together. Equal
  durations keep their original order. Sorting also applies to sample data. Both preferences are
  saved per character; turning sorting off restores the normal fixed order.

Pet skill names use Puppet's maneuver colors: Provoke in Fire, Flash in Light, Stoneskin in Earth,
and so on. Bash and Shot are colored Earth/Wind only when the fitted attachments link them to those
maneuvers, matching Puppet's rules; otherwise their names use the theme's text color. Pet countdowns
retain the same urgency colors as player countdowns. Maneuver colors are shared with Puppet, not
changed by the player ability-name color setting.

Names are left-aligned and all countdowns are right-aligned to the same content edge, across both
player and pet groups. No dash separates them; long countdowns reserve enough room to avoid overlap.

Example layout:

```text
Overdrive       1h 59m 17s
Maneuver              30s
Cure IV               12s

-------------------------

Magic                 18s
Healing                7s
Enfeebling            26s
Bash               2m 22s
Shot                   7s
Provoke               24s
Flash                  4s
```

Pet spells use a shared **Magic** recast and separate **Healing**, **Enfeebling**, **Elemental**,
and **Status removal** recasts (as supported by the head and frame). Each timer appears only after
its spell start is observed and disappears on expiry; they are independent cooldowns, not individual
spell-resource recasts. Mana Booster/Ice and Damage Gauge reductions match Puppet. These timers
remain visible even when there is currently nothing to heal or enfeeble. Generic Magic and Enfeebling
names use the configured spell-name color; Healing, Elemental and Status removal use Puppet's
Light, Ice and Water colors. The sample preview includes pet spell timers.

Pet tracking works independently of Puppet. Both use the shared definitions in
`addons/libs/winxi/automaton/`, with independent runtime state in their respective addons. Install
or update the winxi library along with cooldowns.

Only observed, running cooldowns are shown, not guessed-ready or unknown timers. Observations are
cleared when the pet, character, job, or zone changes. Head, frame and attachments are cached per
character from the server's extended-job packet; on first use, zone or change an attachment to get
that description. A timer already running before cooldowns loads is not known until its action is
observed again. Cooldown durations and attachment/maneuver reductions follow the Phoenix-era rules
used by Puppet. Pet timers use the same recast formatting and urgency colors as player timers.

## Performance

Player recasts are scanned at most ten times per second. Cached snapshots count down every frame,
so display, thresholds, sorting and expiry remain smooth; newly started or reset recasts appear on
the next scan (normally within about 100 ms). Name lookups, including unknown abilities/spells, are
cached. The fallback ability-resource map is built once when needed, rather than scanned per frame.
Job/subjob, character, zone and settings changes invalidate these caches. Returning from a hidden
UI refreshes the snapshot immediately.

Disabling pet cooldowns skips pet row calculations, but packet observation continues so re-enabling
the display can show already-observed running timers. Countdown text is reused between measurement
and drawing, and retained while a cached row's displayed second is unchanged. Empty/single-row
sections skip sorting.

Run the synthetic profile with:

```sh
luajit tests/harness.lua cooldowns tests/cooldowns_stand_in.lua tests/cooldowns_performance_check.lua
```

The profile reports native-call counts and harness CPU/allocation measurements; it does not measure
actual Ashita memory access or in-game rendering performance.

## Upgrading from imrecast / recast

Deploy `libs/winxi`, `cooldowns`, and the updated `puppet` addon. In game:

```text
/addon unload recast
/addon load cooldowns
```

Replace `/addon load imrecast` with `/addon load cooldowns` in your startup script (typically
`scripts/default.txt`). Do not load both versions: the old imrecast folder is no longer used and can
be removed once the new addon works. The old `/imrecast` and `/recast` commands are not aliases.

On first load for each character, cooldowns imports window position/size, name colors, pet toggle,
and cached automaton parts from `config/addons/recast/<character>/settings.lua` (or `imrecast` as a
fallback). Originals are left intact; subsequent changes are saved under `config/addons/cooldowns/`.
Old local theme overrides are not imported. Defaults are migrated independently from character settings.
