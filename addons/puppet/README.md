# puppet

For a puppetmaster: the burden of each element, what the automaton will do next, and everything it might
do in the order it tries them, each with its timer, in a small window. It needs only the `winxi` library
(`addons/libs/winxi`).

    35  35  35  35  33  35  35  35
    Next Action:  Enfeeble Dia II
    Heal                                   -
    Enfeeble      Dia II, Poison, Silence  Next
    WS            Slapstick                -

    Bash                                   142s
    Provoke                                12s

- `/puppet` shows or hides the window
- `/puppet config` opens or closes the settings

The spells and the weapon skill are worked out the way the Phoenix server chooses. Each head has a set
order of spells, every maneuver up moves the spells of its element to the front, and a spell is passed
over when the automaton lacks the magic skill for it or the target already has its effect; the Enfeeble
row names the next three. The weapon skill is the one of the frame's with the most maneuvers of its
element up, and between two with as many, the one needing more skill; the WS row names it. A name that
answers to a maneuver is written in the maneuver's colour: each spell, the weapon skill, Heal (Light
raises the HP it heals at), Nuke (Ice brings it forward), Erase (Water has it reach the party), Bash
and Shot where an attachment ties them to Earth or Wind, and every attachment's action.

With Always Show off, the window is there while the automaton is fighting an enemy, and fades out when
it is not. What it is
fighting is told to its master alone, in the packet that keeps the two in step. A line with
nothing to name is left out: there is no line of spells for a frame that casts none.

The list is in three parts. **Next Action** is what the automaton will do next: whatever comes first
in its order with something to do and nothing to wait for, or, with nothing ready, the weapon skill it
will use once it has the TP. Under that is the **queue**: what the
maneuvers choose, in the order it tries them, each with its timer, named short: Heal, Enfeeble, Nuke,
Erase (a status removal) and WS (the weapon skill). After a gap come the **cooldowns**: what is not
chosen but runs on a timer of its own, each row there only while its timer runs, with the seconds left.
Those are Bash (a shield bash, on a Valoredge frame), Shot (a ranged attack, on a Sharpshot frame) and
the action of each attachment fitted that acts of its own accord when its maneuver is up:

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

Every three seconds or so the automaton tries a shield bash, then its spells in the head's order (which
Light and Ice maneuvers change), then a weapon skill, then a shot, then what its attachments do, and does
the first it can. A row of the queue says `Ready`, the seconds left of the timer it is waiting on, `-`
when there is nothing for it to do as things stand (nobody to heal, nothing to cast, no TP), or `Next` on
the one that comes next; a thing whose condition the game is not told of (an enemy casting for Bash, an
ailment for Erase and Eraser, a buff for Disruptor and Regulator) is never Next. The timers are Phoenix's for this era, with Mana Booster, Damage Gauge, Drum Magazine and Barrier
Module counted where fitted. A timer is known only once the automaton has been seen to act, so a row
may say Ready when the addon was loaded part way through a fight and it is not.

Above it all is the **burden**: one line of eight figures centred in the window, the burden of each
element in the element's colour, in the maneuvers' order (fire, ice, wind, earth, thunder, water, light,
dark). Resting the mouse
on a figure names its element and gives the chance of one more maneuver of it overloading.

The burden is reckoned as the server reckons it: 35 of each element when the automaton is activated,
one off each every three seconds (two with a Heatsink), and what each maneuver adds, which Cooldown
halves. What a maneuver adds goes by the automaton's stats, which the game is not told, so it is taken
for 20, the most it can be, until it has been seen. It is seen in the chance of overloading the server
gives with every maneuver: that is the burden less 25, so whenever there is any chance at all the figure
is the server's own, and with none the burden is known to be 25 or less.

In the settings: **Transparent** takes away the window's backdrop, border and shadow, and writes every
line as winxi's outlined text (the theme's Text Outline, a dark edge round the letters), so that it reads
straight over the game; the dimmed words are the theme's text colour at a little over half strength. It starts
off. **Show Burden** switches the figures off. **Show Priority List** switches that list off. **Always Show** keeps the window there whether the automaton is fighting or not; outside
a fight it shows what the automaton would open with on an enemy with nothing on it. It starts on. **Show Dummy Data** fills every part of the window with made-up data, automaton or no, for seeing how
it looks: a row of the priority list in each state and names in the maneuvers' colours, and a figure in each element's colour. It is not kept,
and is off again when the addon is next loaded. **Show Debug Information** is for finding out what is wrong: under the
window's own lines, what the addon knows (the automaton as described, whether a pet is out and what it is
fighting, how many of the pet's packets have come, the maneuvers up).

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
kind of thing, `burden.lua` the burden, and `tests/puppet_check.lua` works them through.
