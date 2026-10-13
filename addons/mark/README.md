# mark

Pick a notorious monster from a dropdown, make it your mark, and see what the server's own data says of
it: how it comes to be there, its placeholders, where it and they spawn, and what it drops with the
chance of each drop at each level of Treasure Hunter. Needs only the `winxi` library
(`addons/libs/winxi`).

- `/mark` shows or hides the window
- `/mark config` opens or closes the settings
- `/mark compact` switches between the whole window and the mark's few lines
- `/mark set <name>` makes a monster the mark, by its name or a part of it (one of the zone you are in
  before any other)
- `/mark clear` leaves no mark

## The window

Two dropdowns, a zone's and a monster's; the first time, they open on the zone you are in. **Find**
takes a part of a name: the monsters dropdown then lists every monster with it, in any zone. Under them,
for the monster chosen:

- **How It Appears**: a lottery (the chance each time a placeholder is killed, and how long the lottery
  is closed after the monster dies), a timed respawn (the window), a trade to a ??? (what, and where
  the ??? is), with whatever else the data says: day or night only, weather, fog.
- **Placeholders**: each one's name, its ID (the last three figures of its id, as other tools show
  them), level, respawn time and where it is put down; and, in its zone, whether it is in range now.
- **Spawn Locations**: its spawn points, or the stretch of ground it can be put down on, as `/pos` has
  them (east-west, north-south); and how far and which way the nearest is from you.
- **Drops**: every roll made as it dies, with its chance with no Treasure Hunter and at each level up
  to **Highest Treasure Hunter** (4 unless changed). A roll made more than once is one row with a
  count (`Slime Oil x3`); a roll that gives one of several items is a row `One Of` with each item's own
  chance under it. What can be stolen and despoiled follows.

**Set As Mark** makes the monster the mark, and **Clear Mark** undoes it.

## The mark

The mark heads the window, with whether it is in range and which way. It is watched whether or not the
window is showing:

- as it comes into range the chat log says so, with how far and which way, and a sound plays (Announce
  Mark, Sound When Up);
- when it is seen dead the time is kept, and the window counts from it: when the lottery opens again,
  or when a timed monster's window opens and closes. The time is saved with the settings, and let go
  when the monster is seen up again.

**Compact Window** (or `/mark compact`) leaves only the mark's lines: the mark, the time kept, and each
placeholder with whether it is in range.

"In range" is what the game client has been told of, about fifty yalms: the addon reads the client's
memory and asks the server nothing.

## Settings

| Setting | |
|---|---|
| Visible, Position | The window. |
| Compact Window | Only the mark's lines. |
| Show Scripted Spawns | Lists as well the monsters the data knows only as brought by a script (a quest, a battlefield, an event): their drops are there, and nothing of how they are brought. Off, about a quarter of the monsters are listed. |
| Highest Treasure Hunter | The drops are worked out up to this level, 0 to 14. The server takes up to 4 from a job that is not a thief's and up to 8 from a thief; more comes only as a thief's blows raise it in the fight. |
| Announce Mark | The chat log lines. |
| Sound When Up | `open.wav` of `libs\winxi\sounds`. |

## Where the data comes from

`data/` is written by `tools/build_mark_data.py` from the Phoenix server's source
(`references/Phoenix`), and is to be written again when the server changes:

```sh
python tools/build_mark_data.py
```

Requires PyYAML and luajit. It reads each zone's `mobs.yaml` (with the modules' changes laid over it, as
mobdb's importer does), `regions.yaml` and `npcs.yaml`, runs the mob scripts against stand-ins for their
placeholder lists, spawn points and respawn windows, and reads the lottery's chance and wait, and the
trades to a ???, off the scripts' text.

What to know of it:

- **The chances are the server's sums, not observations.** A roll's rate puts it in one of seven
  brackets, and each level of Treasure Hunter has a rate for each bracket
  (`scripts/combat/basic/treasure_hunter.lua`; `tests/mark_data_check.lua` compares the addon's sums
  with that function at every level and rate). So a roll written in the data as an odd percentage
  drops at its bracket's rate: one written as 50% comes to 24% with no Treasure Hunter.
- **The server's settings are not in its source.** The addon takes the drop rate multiplier and the
  lottery's multipliers to be 1, and every module the server lists to be in force, the era module's
  old respawn timers among them.
- A few lotteries (12 of 377) are written in a way the tool does not read: the window says the chance
  is not given. A ??? whose script asks for something other than an item says so too.
- Where a monster is put down anywhere in a region, the window gives the middle of the region and how
  far it reaches, not its outline.
- The places are coordinates and not map squares: the addon has no map to turn one into the other.
