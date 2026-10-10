# puppet

For a puppetmaster: the next three spells the automaton will enfeeble with, and the weapon skill it will
use, in a small window. It needs only the `winxi` library (`addons/libs/winxi`).

    Next Enfeeble: Dia II, Poison, Silence
    Next Weaponskill: Slapstick

- `/puppet` shows or hides the window (it only appears while the automaton is fighting)
- `/puppet config` opens or closes the settings

Both are worked out the way the Phoenix server chooses. Each head has a set order of spells, every
maneuver up moves the spells of its element to the front, and a spell is passed over when the automaton
lacks the magic skill for it or the target already has its effect. The weapon skill is the one of the frame's with the most maneuvers of its element up, and between two with
as many, the one needing more skill.

The window is there while the automaton is fighting an enemy, and fades out when it is not. A line with
nothing to name is left out: there is no line of spells for a frame that casts none.

What it cannot know:

- **The automaton, until the server describes it.** The head, frame and skills arrive on a change
  of area or job and when a part is changed. Loaded part way through a visit to an area, the window
  stays away until one of those happens. Skill gained since is not counted until then either.
- **When the spell comes.** Healing and nuking can come first, and every kind of spell waits on its own
  timer.
- **Debuffs it did not see land**, and those from anything but a spell: see `winxi.debuffs`.
- **Immunity.** An enemy immune to a spell is passed over by the automaton and not by this.
- **A skillchain to close.** With an Inhibitor the automaton may hold its TP, or close a skillchain
  that is open with whichever weapon skill does so. The window shows the usual choice all the same.

`predict.lua` holds the choosing, apart from the game, and `tests/puppet_check.lua` works it through.
