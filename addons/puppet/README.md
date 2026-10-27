# puppet

For a puppetmaster: the burden of each element, the selected magic with its cooldown, and the selected
weapon skill with current TP. It needs the `winxi` library (`addons/libs/winxi`). Observed spell,
Bash, Shot and attachment cooldowns are also displayed by [cooldowns](../../forks/addons/cooldowns/README.md).

    35  35  35  35  33  35  35  35
    Magic         Dia II     12s
    WS            Slapstick  650 TP

- `/puppet` shows or hides the window
- `/puppet config` opens or closes the settings

The spells and the weapon skill are worked out the way the Phoenix server chooses. Each head has a set
order of spells, every maneuver up moves the spells of its element to the front, and a spell is passed
over when the automaton lacks the magic skill for it or the target already has its effect; the Magic row
names what it would cast first. The weapon skill is the one of the frame's with the most maneuvers of its
element up, and between two with as many, the one needing more skill; the WS row names it. A name that
answers to a maneuver is written in the maneuver's colour: each spell, the weapon skill, Heal (Light
raises the HP it heals at), Nuke (Ice brings it forward), Erase (Water has it reach the party), Bash
and Shot where an attachment ties them to Earth or Wind, and every attachment's action.

With Always Show off, the window is there while the automaton is fighting an enemy, and fades out when
it is not. What it is
fighting is told to its master alone, in the packet that keeps the two in step. A line with
nothing to name is left out: there is no line of spells for a frame that casts none.

**Magic** names the head's first eligible spell as if cooldowns were ready, alongside its remaining
cooldown (`Unknown` until the required timers have been observed). It accounts for the shared magic
timer and the spell kind's timer. With nothing to cast it names nothing. Heal is eligible while you
are at 30% HP or under (40, 50 or 75 with Light maneuvers; 50, 75, 80 or 90 with a Damage Gauge), or
the automaton is at 50% or under. **WS** names the maneuver-selected weapon skill as if TP were full,
alongside current TP, not a time-to-TP estimate. There is no Predicted heading; internal prediction
tracking remains available in debug history.

**cooldowns** shows observed running pet cooldowns below player recasts with a winxi-styled separator: the shared Magic
and spell-type timers (Healing, Enfeebling, Elemental, Status removal), Bash (on a Valoredge frame),
Shot (on a Sharpshot frame), and fitted attachment actions:

| Attachment | Row | Maneuver | Recast | Also needs |
|---|---|---|---|---|
| Strobe, Strobe II | Provoke | Fire | 30 s | |
| Flashbulb | Flash | Light | 45 s | |
| Shock Absorber I to III | Stoneskin | Earth | 180 s | |
| Reactive Shield | Blaze Spikes | Fire | 60 s | |
| Replicator | Blink | Wind | 60 s | the automaton at 50% HP or less (75% with a Damage Gauge) |
| Eraser | Eraser | Light | 30 s | an ailment on the automaton or you |
| Economizer | Economizer | Dark | 180 s | MP at or under 40, 50 or 60% by Dark maneuvers |
| Mana Converter | Mana Conv. | Dark | 180 s | MP at or under 40, 60 or 70% by Dark maneuvers |
| Barrage Turbine | Barrage | Wind | 180 s | |
| Heat Capacitor I, II | Heat Cap. | Fire | 90 s | |
| Disruptor | Disruptor | Dark | 60 s | a buff on the enemy to take off |
| Regulator | Regulator | Dark | 60 s | a buff on the enemy to take off |

Every three seconds or so the automaton tries Bash, spells in the head's order, a weapon skill, a
shot, then attachments. Internal predictions exclude unobservable conditions (an enemy casting for
Bash, ailments for Erase/Eraser, buffs for Disruptor/Regulator). Zero MP and Silence block magic
predictions; Amnesia blocks WS and attachment predictions. Having MP does not guarantee enough for a
particular spell. Running timers in cooldowns remain visible even when their action is not eligible.
The timers are Phoenix's for this era, with Mana Booster, Damage Gauge, Drum Magazine and Barrier
Module counted where fitted.

Above it all is the **burden**: one line of eight figures centred in the window, the burden of each
element in the element's colour, in the maneuvers' order (fire, ice, wind, earth, thunder, water, light,
dark). Resting the mouse
on a figure names its element and gives the chance of one more maneuver of it overloading.

The burden is reckoned as the server reckons it: 35 of each element when the automaton is activated,
one off each every three seconds (two with a Heatsink), and what each maneuver adds, which Cooldown
halves. What a maneuver adds goes by the automaton's stats, which the game is not told, so it is taken
for 20, the most it can be, until it has been seen. It is seen in the chance of overloading the server
gives with every maneuver: that is the burden less 25, so whenever there is any chance at all the figure
is derived from that report (subject to gear modifiers), and with none the burden is known to be 25
or less. Decay uses integer three-second ticks with one shared phase: a maneuver does not restart it.
The exact server tick phase is not transmitted, so values between observations are estimates; the
hover text distinguishes estimated burden. Heatsink changes affect future ticks, not elapsed decay.
Cooldown halves integer burden, rounding down. Learned costs are cleared with runtime resets.

## Combined or split windows

Open `/puppet config` and enable **Split Windows** to use two independently movable windows:

1. The **burden window** has no title and contains only the eight figures and their hover details.
   Its eight slots reserve three digits each, including the full last slot, so ordinary value changes
   (including `?`) do not change its width. Larger values can widen the slots. Font or theme changes
   resize the split window equally left and right around its saved top-centre point. Dragging updates
   that centre; numeric **Burden Position** edits still use top-left coordinates.
2. **Cooldowns** contains Magic, WS, and any enabled debug information. Running Bash, Shot and
   attachment cooldowns live in the cooldowns addon instead.

Drag either window to position it, or edit **Burden Position** and **Cooldown Position** in settings.
Positions are saved per character. On first use, the burden window starts at the combined window's
position and cooldowns start 60 pixels below it. Turning split mode off returns to the combined layout;
each layout retains its own positions. Combined mode remains the default for existing installations.

**Show Burden** and **Show Cooldown Tracker** independently hide their corresponding split windows.
With debug enabled, the cooldown window stays available for diagnostics even if its action list is
switched off. `/puppet` toggles both windows together. **Always Show**, transparency, fading, and the
shared game-UI hiding rules apply to both. Dummy data is separated into the same two windows.

## Attachment bonus window

Enable **Attachment Bonuses** in `/puppet config` for a separate, independently movable window.
It works with either combined or split mode; its position is saved per character and can also be
edited under **Attachment Position**. It starts disabled so existing layouts are unchanged.

Each equipped attachment shows its current contribution at the active maneuver count, shown in
brackets after its name. Values refresh at 10 Hz and when attachment packets arrive. Zero-maneuver
bonuses and penalties are included. Optic Fiber enhances only the modifiers the server marks eligible,
rounding each contribution down separately (including negative values). Overdrive treats an element
with at least one maneuver as three, but does not create maneuvers for inactive elements.

These are **attachment contributions, not final pet stats**: equipment, other buffs, stat caps and
conditional proc state are not inferred. Repair Kit regen shows its max-HP formula because pet max HP
is not available here. Mana Tank refresh uses the era's flat values. Ability effects such as Stoneskin
and Blink describe what activation grants, not a claim that the buff is currently active. Attachments
without a passive modifier are explicitly marked as action/conditional effects; unfamiliar modifier
units remain labelled as server units rather than guessed percentages.

The window follows `/puppet`, Always Show, transparency, fade and game-UI hiding settings, and hides
when there is no automaton out. Dummy Data previews it with sample attachments. Equipped parts use
the same server packet and per-character cache as the existing trackers; zone or change an attachment
if the addon has not yet received a parts description.

The attachments are the chosen server's data: winxi's `attachments` set, made by
`tools/build_winxi_data.py` (or `tools/build_puppet_attachments.py` alone) from the server as it
runs. It reads `sql/item_puppet.sql` and `item_basic.sql` for each attachment and its element (by
`item_basic`'s name, the one the server keys an attachment by), and `scripts/globals/automaton.lua`
for the modifiers, the Repair Kit and Mana Tank formulas and each frame's divisor. Then it applies
what the modules put in their place, such as the era's
`modules/era/lua/actions/abilities/pets/automaton/attachments.lua`. On Phoenix that means:

- the era's Strobe and Store TP values
- Defense on the Armor Plates
- gear haste on the Turbo Charger
- Mana Booster's cooldown reduction
- Drum Magazine's accuracy penalty
- Heatsink
- Repair Kit II, and Mana Tank I and II with flat refresh
- the abilities, such as Analyzer, Replicator and Shock Absorber

A Repair Kit's or Mana Tank's frame bonus is the server's divisor for the fitted frame. A Mana Tank
adds nothing on Valoredge or Sharpshot, which have no MP. An attachment the data does not have is
named as such, not guessed.

The game client does not need network access: the data is in `addons/libs/winxi/data/<server>/attachments`,
and `attachments.lua` calculates and formats the contributions.

## Other settings

**Transparent** takes away the window's backdrop, border and shadow, and writes every
line as winxi's outlined text (the theme's Text Outline, a dark edge round the letters), so that it reads
straight over the game; the dimmed words are the theme's text colour at a little over half strength. It starts
off. **Show Burden** switches the figures off. **Show Cooldown Tracker** switches the action list off. **Always Show** keeps the window there whether the automaton is fighting or not; outside
a fight it shows what the automaton would open with on an enemy with nothing on it. It starts on. **Show Dummy Data** fills every part of the window with made-up data, automaton or no, for seeing how
it looks: a row of the priority list in each state and names in the maneuvers' colours, and a figure in each element's colour. It is not kept,
and is off again when the addon is next loaded. **Show Debug Information** is for finding out what is wrong: under the
window's own lines, what the addon knows (the automaton as described, whether a pet is out and what it is
fighting, how many of the pet's packets have come, the maneuvers up, your HP and the automaton's HP and TP,
which the heal and the weapon skill go by). It also shows the latest five observed pet actions,
including action IDs, targets, and the preceding prediction with its confidence and age. Up to twenty
observations are kept in memory, never written to settings; pet, zone, and character resets clear them.
Maneuvers are captured with the prediction, rather than read retroactively when inspecting history.

State collection continues while a map or cutscene hides the window. Decision and burden presentation
updates run at 10 Hz, with relevant packets requesting an immediate refresh; rendering stays at the
game's frame rate. Turning off both priority and debug skips priority generation.

What it cannot know:

- **The automaton, until the server has once described it.** The head, frame and skills arrive on a
  change of area or job and when a part is changed, and are kept in the settings from then on, so only
  the first time the addon is ever loaded for a character does the window stay away until one of those
  happens. A part changed, or skill gained, while the addon was not loaded is not known of until then
  either.
- **The burden of an automaton that was out before the addon was loaded.** Each figure is `?` until a
  maneuver of its element is used. Gear that moves the point of overloading puts a figure taken from the
  server's chance out by as much.
- **When the spell comes.** Healing and nuking can come first, and every kind of spell waits on its own
  timer.
- **Debuffs it did not see land**, and those from anything but a spell: see `winxi.debuffs`.
- **Some of what decides the order.** Whether the enemy is casting, for a shield bash; a Stormwaker's
  nuke to finish an enemy nearly dead; which ailments a Soulsoother would remove; what the attachments
  do of their own accord, which comes last; and the three seconds between one try and the next.
- **Immunity.** An enemy immune to a spell is passed over by the automaton and not by this.
- **A skillchain to close.** With an Inhibitor the automaton may hold its TP, or close a skillchain
  that is open with whichever weapon skill does so. The window shows the usual choice all the same.
- **What an attachment waits for besides its maneuver**, where the game is not told: an ailment for an
  Eraser, a buff on the enemy for a Disruptor or Regulator. They are never called the next action.

`predict.lua` holds the choosing, apart from the game, `tracker.lua` when the automaton last did each
kind of thing, `tp.lua` how fast it gains TP, `burden.lua` the burden, and `tests/puppet_check.lua`
works them through. `tests/puppet_regression_check.lua` adds assertion-based lifecycle, uncertainty,
burden, TP, history, split-window layout/visibility/positions, and update-budget regressions. Run both with:

```sh
luajit tests/harness.lua puppet addons/puppet/puppet.lua tests/puppet_check.lua
luajit tests/harness.lua puppet addons/puppet/puppet.lua tests/puppet_regression_check.lua
luajit tests/harness.lua puppet addons/puppet/puppet.lua tests/puppet_attachments_check.lua
```
