# cooldowns

Displays your ability and spell recast times in a single window titled **Cooldowns**, in the shared
winxi style, and, for puppetmasters, the automaton's cooldowns as well. It is based on imrecast by
atom0s, Thorny, RZN and lin, and replaces both imrecast and recast.

## Highlights

- Every recast in one list, with the time remaining on each.
- Timers change colour as they near completion.
- Puppetmasters also see the automaton's spell, Bash, Shot and attachment cooldowns.

cooldowns replaces the older recast and imrecast addons. See
[Upgrading from imrecast or recast](#upgrading-from-imrecast-or-recast) below. Its authors, as the
addon lists them, are atom0s, Thorny, RZN, lin and win.

## Commands

- `/addon load cooldowns` loads it.
- `/addon reload cooldowns` reloads it.
- `/cooldowns` opens the display settings.
- `/cooldowns debug` helps when a pet timer is missing (see [If a pet timer is missing](#if-a-pet-timer-is-missing)).

The folder, the addon's name and the command are all **cooldowns**.

## Example

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

Your own recasts are at the top. The automaton's are below the line.

## Settings

The look of the window (background, border, font, padding) comes only from winxi's shared theme, set
in wxi. cooldowns has no look settings of its own. Old look settings of its own are thrown away.

All the settings below are saved for each character.

### Name colours

- **Ability name color** and **Spell name color**: the colours of ability names and spell names.
  Both are white by default. They change only the names, not the countdowns.

### Countdown colours

- **Warning below (seconds)** (default 20) and **Critical at or below (seconds)** (default 5): when a
  countdown changes colour.
  - Below the warning time, the countdown turns the **Warning countdown color** (yellow by default).
  - At or below the critical time, it turns the **Critical countdown color** (red by default).
    Critical wins over warning.
  - Above both, countdowns use the shared theme's text colour.
- You can set each colour's transparency too.
- These colours apply to your countdowns, the pet's countdowns and the sample preview. They do not
  change the name colours.
- Times are whole seconds and cannot be below zero. If critical is set higher than warning, it is
  lowered to match warning.
- Set both to zero to turn the colour change off.

### What to show

- **Show Player Cooldowns** (on by default): shows your own ability and spell recasts. Turn it off to
  list only the pet's cooldowns. The line between the two lists goes too, and your recasts are not
  read while they are hidden. The preview follows this setting too.
- **Show pet cooldowns** (on by default): shows the automaton's spell, Bash, Shot and attachment
  cooldowns that have been seen, below your recasts. A line drawn in the winxi style separates them.
  The line shows only when both lists are shown, with the window's padding above and below it. Spell
  choice, weaponskill choice and current TP stay in the Puppet addon.
- **Show sample data**: shows sample player and pet timers while the settings window is open. This is
  only for a preview and is not saved. The pet setting and the name colours apply to the preview too.
  The preview includes your main job's two-hour ability with a `1h 59m 17s` recast, so you can check
  long countdowns.

### Sorting

- **Sort by time remaining** (off by default): sorts each list by the time actually left. When it is
  on, choose **Ascending (shortest first)** or **Descending (longest first)**.
  - Your list and the pet's list stay separate. Spells and abilities in each list are sorted together.
  - Timers with the same time keep their usual order.
  - Sorting applies to the sample data too.
  - Turning sorting off goes back to the usual fixed order.

## How the list looks

- Names are on the left. All countdowns line up on the right, in both lists. There is no dash between
  them, and long countdowns get enough room not to overlap.
- Pet skill names use Puppet's maneuver colours: Provoke in Fire, Flash in Light, Stoneskin in Earth,
  and so on.
- Bash and Shot are coloured Earth or Wind only when your attachments link them to those maneuvers, as
  in Puppet. Otherwise their names use the theme's text colour.
- Maneuver colours come from Puppet. The ability name colour setting does not change them.
- Pet countdowns use the same time format and warning colours as yours.

Your recasts are checked up to ten times a second. A recast that starts or resets shows on the next
check, normally within about a tenth of a second.

## Automaton (pet) cooldowns

Pet tracking works when puppetmaster is your main job or your support job. It works on its own,
without the Puppet addon. cooldowns and Puppet share some files in the winxi library, so install or
update winxi together with cooldowns.

### Pet spells

The automaton has one shared **Magic** recast, and separate **Healing**, **Enfeebling**, **Elemental**
and **Status removal** recasts (as its head and frame allow).

- Each timer appears only after the automaton is seen starting a spell of that kind. It goes when it
  runs out.
- These are cooldowns for each kind of spell, not for each single spell.
- Mana Booster (with Ice maneuvers) and Damage Gauge shorten them, as in Puppet.
- The timers stay on screen even when there is nothing to heal or enfeeble.
- The general Magic and Enfeebling names use your **Spell name color**. Healing, Elemental and Status
  removal use Puppet's Light, Ice and Water colours.
- The sample preview includes pet spell timers.

### What is tracked

- Only cooldowns that have been seen and are still running are shown. There are no guessed "ready" or
  unknown timers.
- Shot is tracked from the automaton's ranged attack. The server always sends this as its monster
  skill 1949, never as a normal ranged attack. This works even with your own cooldowns turned off.
- If no pet cooldown has been seen yet, or all have run out, the pet-only window is hidden.
- What has been seen is cleared when your pet, character, job or zone changes.
- Your automaton's head, frame and attachments are remembered for each character. The server sends
  them when you change zone or change an attachment. So the first time, change zone or change an
  attachment to send them.
- A timer that was already running before cooldowns loaded is not known until the automaton uses that
  action again.
- Cooldown times, and how attachments and maneuvers shorten them, follow the Phoenix-era rules used by
  Puppet.

### If a pet timer is missing

Run `/cooldowns debug` after the pet acts. It prints:

- the pet it found, and its head and frame;
- the last time it saw Shot;
- the ten most recent pet actions it saw (their category and number).

This list is short, is not saved, and is cleared along with the pet's other tracking.

## Upgrading from imrecast or recast

Install `libs/winxi`, `cooldowns` and the updated `puppet` addon. Then, in game:

```text
/addon unload recast
/addon load cooldowns
```

In your startup script (usually `scripts/default.txt`), replace `/addon load imrecast` with
`/addon load cooldowns`.

- Do not load both. The old imrecast folder is no longer used. You can remove it once cooldowns works.
- The old `/imrecast` and `/recast` commands do not work in cooldowns.

The first time cooldowns loads for each character, it brings over your old settings from
`config/addons/recast/<character>/settings.lua` (or from `imrecast` if there is no recast file):

- window position and size;
- name colours;
- the pet setting;
- the saved automaton parts.

Your old files are left as they were. New changes are saved under `config/addons/cooldowns/`. Old
look settings of its own are not brought over. The default settings are brought over separately from
each character's settings.
