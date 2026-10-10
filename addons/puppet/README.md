# puppet

For a puppetmaster: the next three spells the automaton will enfeeble with, and the weapon skill it will
use, in a small window. It needs only the `winxi` library (`addons/libs/winxi`).

    Next Enfeeble: Dia II, Poison, Silence
    Next Weaponskill: Slapstick

- `/puppet` shows or hides the window
- `/puppet config` opens or closes the settings

Both are worked out the way the Phoenix server chooses. Each head has a set order of spells, every
maneuver up moves the spells of its element to the front, and a spell is passed over when the automaton
lacks the magic skill for it or the target already has its effect. The weapon skill is the one of the frame's with the most maneuvers of its element up, and between two with
as many, the one needing more skill.

With Always Show off, the window is there while the automaton is fighting an enemy, and fades out when
it is not. What it is
fighting is told to its master alone, in the packet that keeps the two in step. A line with
nothing to name is left out: there is no line of spells for a frame that casts none.

Under those two lines is the **priority list**: everything the automaton might do next, in the order it
tries them, with how each stands.

    > Enfeeble     Bio            Next
      Heal         you at 30%     -
      Weaponskill  Slapstick (TP 640)  -

Every three seconds or so the automaton tries a shield bash, then its spells in the head's order (which
Light and Ice maneuvers change), then a weapon skill, then a shot, and does the first it can. A row says
`Ready`, the seconds left of the timer it is waiting on, or `-` when there is nothing for it to do as
things stand (nobody to heal, no TP). The row marked `>` is the one that comes next. The timers are
Phoenix's for this era, with Mana Booster, Damage Gauge, Drum Magazine and Barrier Module counted where
fitted. A timer is known only once the automaton has been seen to act, so a row may say Ready when the
addon was loaded part way through a fight and it is not.

Between the two lines and the list are the **burden bars**: a small bar for each element, in its
colour, with the burden written over it. Fire, ice, wind and earth are the top row, thunder, water, light
and dark the one under it. A bar is full at 100. The figure is white while one more maneuver of that
element cannot overload, yellow when it might, and red when the chance is one in four or more.

The burden is reckoned as the server reckons it: 35 of each element when the automaton is activated,
one off each every three seconds (two with a Heatsink), and what each maneuver adds, which Cooldown
halves. What a maneuver adds goes by the automaton's stats, which the game is not told, so it is taken
for 20, the most it can be, until it has been seen. It is seen in the chance of overloading the server
gives with every maneuver: that is the burden less 25, so whenever there is any chance at all the figure
is the server's own, and with none the burden is known to be 25 or less.

In the settings: **Show Burden** switches the bars off. **Show Priority List** switches that list off. **Always Show** keeps the window there whether the automaton is fighting or not; outside
a fight it shows what the automaton would open with on an enemy with nothing on it. It starts on. **Show Dummy Data** fills every part of the window with made-up data, automaton or no, for seeing how
it looks: a row of the priority list in each state, and bars with a figure in each colour. It is not kept,
and is off again when the addon is next loaded. **Show Debug Information** is for finding out what is wrong: under the
window's own lines, what the addon knows (the automaton as described, whether a pet is out and what it is
fighting, how many of the pet's packets have come, the maneuvers up).

What it cannot know:

- **The automaton, until the server has once described it.** The head, frame and skills arrive on a
  change of area or job and when a part is changed, and are kept in the settings from then on, so only
  the first time the addon is ever loaded for a character does the window stay away until one of those
  happens. A part changed, or skill gained, while the addon was not loaded is not known of until then
  either.
- **The burden of an automaton that was out before the addon was loaded.** Each bar says `?` until a
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

`predict.lua` holds the choosing, apart from the game, `tracker.lua` when the automaton last did each
kind of thing, `burden.lua` the burden, `bars.lua` the drawing of its bars (the images are XivParty's, in
`assets/bars` with its licence), and `tests/puppet_check.lua` works them through.
