# mark

Pick a notorious monster from a dropdown, make it your mark, and see what the server's own data says of
it: how it comes to be there, its placeholders, where it and they spawn, and what it drops with the
chance of each drop at each level of Treasure Hunter. It times the mark's placeholders and its window,
and shows where it can spawn on the zone's map. Needs the `winxi` library (`addons/libs/winxi`), and
`zoneinfo` installed beside it for the maps' pictures.

- `/mark` shows or hides the window
- `/mark config` opens or closes the settings
- `/mark compact` switches between the whole window and the mark's few lines
- `/mark map` shows or hides the map
- `/mark set <name>` makes a monster the mark, by its name or a part of it (one of the zone you are in
  before any other)
- `/mark clear` leaves no mark
- `/mark tod` keeps a time of death for the mark (or, with no mark, the monster on show): now, or
  `/mark tod 15` for fifteen minutes ago, or `/mark tod 14:35` for a time by the computer's clock;
  `/mark tod clear` forgets it

## The window

Two dropdowns, a zone's and a monster's; the first time, they open on the zone you are in. **Find**
takes a part of a name: the monsters dropdown then lists every monster with it, in any zone. Under them,
for the monster chosen:

- **How It Appears**: a lottery (the chance each time a placeholder is killed, and how long the lottery
  is closed after the monster dies), a timed respawn (the window), a trade to a ??? (what, and where
  the ??? is), with whatever else the data says: day or night only, weather, fog.
- **Placeholders**: each one's name, its ID (the last three figures of its id, as other tools show
  them), level, respawn time and where it is put down; and, in its zone, whether it is in range now.
- **Spawn Locations**: its spawn points, or the stretch of ground it can be put down on, each as a
  square of the map and as `/pos` has it (`H-7 (-341, -233)`: east-west, north-south); and how far and
  which way the nearest is from you. The placeholders' places are written the same way.
- **Drops**: every roll made as it dies, with its chance with no Treasure Hunter and at each level up
  to **Highest Treasure Hunter** (4 unless changed). A roll made more than once is one row with a
  count (`Slime Oil x3`); a roll that gives one of several items is a row `One Of` with each item's own
  chance under it. What can be stolen and despoiled follows.

**Set As Mark** makes the monster the mark, and **Clear Mark** undoes it. **Show Map** opens the map.
**Report TOD** keeps a time of death for the monster on show, now or as many minutes ago as the box
beside it says, and **Clear TOD** forgets it.

## The mark

The mark heads the window, with whether it is in range and which way. It is watched whether or not the
window is showing:

- as it comes into range the chat log says so, with how far and which way, and a sound plays (Announce
  Mark, Sound When Up);
- when it is seen dead the time is kept, and the window counts from it: when the lottery opens again,
  or when a timed monster's window opens and closes. The time is saved with the settings, and let go
  when the monster is seen up again;
- each of its placeholders seen dead is timed from then by its respawn time: `Respawns in 3:20`, then
  `Due 0:40 ago` until it is seen up. These are kept only while the addon is loaded and you stay in
  the zone. The monster on show has its placeholders timed the same way, mark or not.

**Compact Window** (or `/mark compact`) leaves only the mark's lines: the mark, how its window stands,
and each placeholder with whether it is in range or when it respawns.

## Times of death

A death you did not see can be given by hand, for any monster: **Report TOD** in the window, or
`/mark tod` for the mark. Every time kept is listed at the head of the window with how the monster's
window stands, in green once it is open, and an `x` to forget it. They are saved with the settings.

## The map

**Show Map** (or `/mark map`) opens the zone's map in a window of its own, for the monster on show.
Where the monster can spawn is laid over it in red and where its placeholders can in blue: a region it
can be put down anywhere in is filled, a spawn point is a spot, and a route it walks is a yellow line.
Each is thin enough that the colour deepens where several lie over one another, so the more that can
spawn in a place the hotter it shows. In the zone, you are the white spot and whatever of them is in
range is green (grey if dead). The square and the point under the mouse are in the tooltip.

What to know of the maps:

- **The scale is the game's.** Where a place falls on a map, and so its square, is worked out from the
  scale and offsets in the client's own table of maps, read from its memory as zoneinfo and boussole
  read it. Until that can be read there are no squares and no map.
- **A zone of several maps** (most dungeons): which map a place is on is asked of the client, which can
  only say for the zone you are in. Outside the zone the places have no squares, and the map draws
  everything on whichever map is chosen with the buttons over it.
- **The pictures are zoneinfo's**, looked for in `addons\zoneinfo\assets\maps\all` (or in mark's own
  `assets\maps`, if they are put there). Without them the overlay is drawn on a blank square. 172 of
  the 230 zones with notorious monsters have a map; the rest are battlefields and the like.
- **Routes**: the server's zone data has none for any monster, and only two monsters' scripts walk
  them over one, so the yellow lines are rare.

"In range" is what the game client has been told of, about fifty yalms: the addon reads the client's
memory and asks the server nothing.

## Settings

| Setting | |
|---|---|
| Visible, Position | The window. |
| Compact Window | Only the mark's lines. |
| Show Map, Map Size | The map window, and how many pixels across it is drawn (the pictures are 512). |
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
placeholder lists, spawn points, routes and respawn windows, and reads the lottery's chance and wait,
and the trades to a ???, off the scripts' text. `data/maps.lua`, the list of each zone's maps, is taken
from `addons/zoneinfo/data/all_maps.lua`.

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
  far it reaches; the map has its outline, drawn to within three yalms (less for a narrow one).
