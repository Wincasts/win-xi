# puppet

For a puppetmaster: the enfeebling spell the automaton will cast next, and the ones after it, in a small
window. It needs only the `winxi` library (`addons/libs/winxi`).

- `/puppet` shows or hides the window (it only appears while an automaton is out)
- `/puppet config` opens or closes the settings

The answer is worked out the way the Phoenix server chooses: each head has a set order of spells, every
maneuver up moves the spells of its element to the front, and a spell is passed over when the automaton
lacks the magic skill for it or the target already has its effect. The target is the enemy the automaton
is fighting, or else the one targeted, so the window can be read before the automaton is deployed.

What it cannot know:

- **The automaton, until the server describes it.** The head, frame and magic skill arrive on a change
  of area or job and when a part is changed. Loaded part way through a visit to an area, the window
  says so until one of those happens. Skill gained since is not counted until then either.
- **When the spell comes.** Healing and nuking can come first, and every kind of spell waits on its own
  timer.
- **Debuffs it did not see land**, and those from anything but a spell: see `winxi.debuffs`.
- **Immunity.** An enemy immune to a spell is passed over by the automaton and not by this.

`predict.lua` holds the choosing, apart from the game, and `tests/puppet_check.lua` works it through.
