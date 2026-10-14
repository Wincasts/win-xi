# mark

Pick a notorious monster from a dropdown, make it a mark, and see what the server's own data says of
it: how it comes to be there, its placeholders, where it and they spawn, and what it drops with the
chance of each drop at each level of Treasure Hunter. It times each mark's placeholders and its window,
lists every mark and every time of death kept, and shows where a monster can spawn on the zone's map.
Needs the `winxi` library (`addons/libs/winxi`). The bundled maps are exported from XICombinedMaps;
without them, `zoneinfo` installed beside Mark can supply lower-resolution fallback pictures.

- `/mark` shows or hides the window
- `/mark config` opens or closes the settings
- `/mark stats` opens the hunting statistics tab
- `/mark compact` switches between the whole window and the marks' few lines
- `/mark map` shows or hides the map
- `/mark pin` pins or unpins the map; pinning also opens it, even if the main window is closed
- `/mark set <name>` makes a monster a mark, by its name or a part of it (one of the zone you are in
  before any other)
- `/mark clear` leaves no marks, and `/mark clear <name>` takes away the one with that in its name
- `/mark tod` keeps a time of death for the mark: the one of the zone you are in, or the only one
  there is; failing that, the monster on show. Now, or `/mark tod 15` for fifteen minutes ago, or
  `/mark tod 14:35` for a time by the computer's clock; `/mark tod clear` forgets it
- `/mark ph 126` says the placeholder of that ID died just now, `/mark ph 126 2` two minutes ago, and
  `/mark ph 126 clear` stops timing it

## The window

A header with the addon's name and, at its far end, an `x` that closes the window (`/mark` brings it
back; the marks are watched meanwhile). Under it, three tabs: **Database**, **Marks** and **Stats**.
The old level/job/family/aggro/links/detection summary has been removed; the lookup focuses on hunting.

## Database

The upper section shows the selected NM and its full hunting information. It scrolls independently,
including horizontally for wide drop tables. Below a separator, a fixed footer contains the **zone**
and **monster** dropdowns and **Find** box, so the search controls stay accessible with long records.
The details return to the top when another NM or zone is selected.

The first time, the dropdowns open on the zone you are in. **Find** takes a part of a name: the
monsters dropdown then lists matching monsters in any zone. For the monster chosen:

- **How It Appears**: a lottery (the chance each time a placeholder is killed, and how long the lottery
  is closed after the monster dies), a timed respawn (the window), a trade to a ??? (what, and where
  the ??? is), with whatever else the data says: day or night only, weather, fog.
- **Placeholders**: each one's name, its ID (the last three figures of its id, as other tools show
  them), respawn time and spawn point (the middle of the ground it can be put down on, where that is
  a region); and under **Next Spawn** the time to its respawn where its death was seen or told, that
  it is up, or `Unknown`. **Map** on its
  row opens the map with that placeholder alone beside the monster, for all the ground it covers;
  **TOD** says it died just now.
- **Spawn Locations**: its spawn points, or the stretch of ground it can be put down on, each as a
  square of the map and as `/pos` has it (`H-7 (-341, -233)`: east-west, north-south); and how far and
  which way the nearest is from you. The placeholders' places are written the same way.
- **Drops**: every roll made as it dies, with its chance with no Treasure Hunter and at each level up
  to **Highest Treasure Hunter** (4 unless changed). A roll made more than once is one row with a
  count (`Slime Oil x3`); a roll that gives one of several items is a row `One Of` with each item's own
  chance under it. What can be stolen and despoiled follows.

**Set As Mark** makes the monster a mark, and **Clear Mark** undoes it. **Show Map** opens the map.
**Report TOD** keeps a time of death for the monster on show, now or as many minutes ago as the box
beside it says, and **Clear TOD** forgets it.

### 3D model preview

A live 3D preview is not implemented. The current Lua/UI and Ashita resource interfaces do not provide
a ready-to-use mob model viewer. Supporting one would require mapping NMs to client model assets,
loading their geometry/materials (and animation for an animated preview), and rendering to a texture
with a separate compatible renderer or native plugin. The existing nameplate hook only renders names;
it is not a mob-model renderer. No game entities are modified or spawned to fake a preview.

## Marks

A line for every monster made a mark (its name in gold), and after them one for every other monster a
time of death is kept for. Each has its zone and, under **Next Spawn**, that it is up and which way, or the time to its window
where its death is known (in green once it is open; the whole of it is in the tooltip), or `Unknown`. Its buttons: **Database**
turns to the first tab with that monster on show, **TOD** says it died just now, **Clear TOD** forgets
its time of death, and **Clear Mark** or **Set As Mark** takes it off the marks or puts it on them. A
monster that is no mark and has no time of death leaves the list. Under a mark of the zone you are in
are its placeholders, each with its own next spawn.

There can be as many marks as are wanted. Each is watched whether or not the window is showing:

- as it comes into range the chat log says so, with how far and which way, and a sound plays (Announce
  Mark, Sound When Up);
- when it is seen dead the time is kept, and the window counts from it: when the lottery opens again,
  or when a timed monster's window opens and closes. The time is saved with the settings, and let go
  when the monster is seen up again;
- each of its placeholders seen dead is timed from then by its respawn time: `Respawns in 3:20`, then
  `Due 0:40 ago` until it is seen up, and then `Up, 10 yalms W, for 1:20`, counting from when it was
  seen to come back. A death you did not see is given with **TOD** on its row or `/mark ph <ID>`. The
  chat log says when a timed placeholder falls due and when it has respawned (Announce
  Placeholders). Their death times are saved per character and zone, including deaths given with
  **TOD** or `/mark ph`: logging out, reloading the addon or leaving the zone does not forget them.
  On returning, the countdown includes the time spent away. The monster on show has its placeholders
  timed the same way, mark or not.

**Compact Window** (or `/mark compact`) leaves only the marks' lines, with no header and no tabs: each
mark, how its window stands, and each placeholder with whether it is in range or when it respawns.

## Hunting Stats

The **Stats** tab (or `/mark stats`) is a per-character hunting database, saved automatically with the
character's Mark settings under `hunting` (schema version 1). It needs no database server or extra
runtime library. Records are keyed by zone and NM name, so identical names in different zones do not
share totals. Counts survive logout and addon reload; saving happens on observations, not every frame.

Tracking covers every mark and the NM selected in Database, even with the main window closed:

- **Placeholder kills**, both total and per placeholder ID. Shared placeholders are credited once to
  each associated watched hunt, so adding different hunts' PH totals is not a unique physical-kill count.
- **Total observed NM kills** and the date/time of the most recent kill.
- **NM sightings**: entering view alive, not necessarily a newly spawned NM. Initial sightings and
  re-entering range count; several indices of the same NM seen together count as one sighting.
- **Time to pop**: from the first observed PH kill in an attempt to the next NM sighting. Shows the
  average, fastest, slowest, sample count, and average PH kills per completed pop sample. This is an
  observed hunting duration, not a measurement of the server's lottery chance or cooldown.
- **Observed NM return intervals**: from an observed NM kill to seeing that same entity index alive
  again, with average, fastest, slowest and sample count. Useful for timed NMs too.
- **Drops**: each item's total quantity seen, the number of observed kills that produced it, and the
  percentage of observed NM kills with that item. Known items with no observed drops remain visible
  as zero. Multiple copies of an item count toward quantity but only once toward kills with the item.
- **Kills with loot seen**, separately from all observed NM kills, to expose incomplete loot coverage.

Select an NM's row for its detailed record. Kills are counted from death messages or an alive-to-dead
transition that Mark witnessed; just discovering an old corpse does not count. Death messages, corpse
polling and duplicate loot notifications for the same death are deduplicated. A fresh loot packet from
an NM can itself confirm its kill if the corpse or death message was missed. Manual **TOD** reports
only maintain timers and never invent kill/statistical samples.

Loot comes from incoming `0x0D2` treasure packets, matched to the watched NM's source ID and zone—not
by guessing which death happened near a treasure-pool update. Old pool entries, containers, unrelated
monsters and placeholder loot are excluded. **Items found are not necessarily items won.** Observed
kills can belong to other hunters, and Mark cannot see every drop. Treasure Hunter is not inferred.
These percentages are observational, potentially biased, and are not controlled drop-rate estimates;
the server's theoretical Treasure Hunter table remains separate on Database.

Logout, loading/zoning, settings reloads and stopping tracking discard unfinished timing samples so
offline time does not inflate the averages. Completed totals remain saved. Events while offline are
not recorded, and no historical stats can be reconstructed from old saved TODs. Database storage is
aggregate-only, rather than an ever-growing event log.

## Times of death

A death you did not see can be given by hand, for any monster: **Report TOD** in the window, or
`/mark tod` for the mark. Every time kept is listed on the Marks tab with how the monster's window
stands. They are saved with the settings.

Placeholder death times are saved too. Mark cannot see deaths or respawns while you are logged out
or away: a restored countdown is based on the last death you saw or reported, not a new observation.
Seeing the placeholder alive clears its saved death time. As before, a timer more than 30 minutes
past its expected respawn is discarded when that placeholder is next watched. How long a placeholder
has been seen up is a session-only observation, not carried across logins.

## The map

**Show Map** (or `/mark map`) opens the zone's map in a window of its own, for the monster on show.
Where the monster can spawn is laid over it in red and where its placeholders can in blue: a region it
can be put down anywhere in is filled, a spawn point is a spot, and a route it walks is a yellow line.
Each is thin enough that the colour deepens where several lie over one another, so the more that can
spawn in a place the hotter it shows. In the zone, you are the white spot and whatever of them is in
range is green (grey if dead). The square and the point under the mouse are in the tooltip. Opened
from a placeholder's **Map** button it shows that placeholder alone beside the monster, until **Show
All** over the map is pressed.

**Map controls:**

- **Mouse wheel** over the map zooms from 1x to 6x, keeping the point under the cursor in place.
  The **−** and **+** buttons zoom around the viewport's center.
- **Left-drag inside the map** pans the zoomed view. Panning is bounded so the map cannot be lost
  offscreen; at 1x the entire map fits and there is no need to pan.
- **Reset View** restores the complete map. Choosing another monster or map floor resets the view too.
- **Drag outside the canvas**, such as over the monster's name, to move the map window. Its position
  is saved separately from the main window.
- **Pin Map** keeps the map open when the main Mark window is closed, including with `/mark` or its
  header's `x`. The pin is saved per character. The map still follows the configured loading,
  cutscene and other automatic hiding rules.
- The map's own **x** closes it independently; `/mark map` reopens it. Pinning does not prevent
  explicitly closing the map, and it does not keep the map running after the addon is unloaded.

The map image, spawn regions, routes, live markers and coordinates under the mouse all use the same
pan/zoom transform, within a fixed-size clipped viewport. **Map Size** changes the viewport size, not
the zoom; pan and zoom are temporary view controls, not saved across logins.

What to know of the maps:

- **The scale is the game's.** Where a place falls on a map, and so its square, is worked out from the
  scale and offsets in the client's own table of maps, read from its memory as zoneinfo and boussole
  read it. Until that can be read there are no squares and no map.
- **A zone of several maps** (most dungeons): which map a place is on is asked of the client, which can
  only say for the zone you are in. Outside the zone the places have no squares, and the map draws
  everything on whichever map is chosen with the buttons over it.
- **The pictures retain their native resolution**, exported from `references/XICombinedMaps-2048`
  into Mark's `assets\maps`: 258 of the 403 selected images are 2048×2048; the other 145 are only
  512×512 in the source pack. No images are artificially upscaled. Mark prefers these over Zoneinfo's
  512×512 previews in `addons\zoneinfo\assets\maps\all`. Without either set the overlay is drawn on
  a blank square. 172 of the 230 zones with notorious monsters have a map; the rest are battlefields
  and the like. Higher-resolution pictures improve zoom clarity, but cannot stay pixel-sharp beyond
  their native detail (roughly 4x at the default 512-pixel viewport for a 2048-pixel image).
- **Routes**: the server's zone data has none for any monster, and only two monsters' scripts walk
  them over one, so the yellow lines are rare.

"In range" is what the game client has been told of, about fifty yalms: the addon reads the client's
memory and asks the server nothing.

## Settings

| Setting | |
|---|---|
| Visible, Position | The window. |
| Compact Window | Only the marks' lines. |
| Show Map, Map Size | The map window and its viewport size in pixels, independent of image resolution. |
| Pin Map | Keeps the map open when Mark's main window is closed. Saved per character. |
| Show Scripted Spawns | Lists as well the monsters the data knows only as brought by a script (a quest, a battlefield, an event): their drops are there, and nothing of how they are brought. Off, about a quarter of the monsters are listed. |
| Highest Treasure Hunter | The drops are worked out up to this level, 0 to 14. The server takes up to 4 from a job that is not a thief's and up to 8 from a thief; more comes only as a thief's blows raise it in the fight. |
| Announce Mark | The chat log lines for the mark. |
| Announce Placeholders | The chat log lines for a timed placeholder: due, and respawned. |
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

Rebuild the native-resolution map pictures after changing that catalog:

```sh
python3 tools/build_mark_maps.py
```

Requires Pillow and the local `references/XICombinedMaps-2048` pack. The exporter uses Zoneinfo's
`assets/maps/all/manifest.json` to match DATs to the existing catalog filenames, verifies every source
DAT's SHA-256, and saves the complete native image without resizing, cropping or changing alignment.
It writes a provenance and dimensions manifest to `addons/mark/assets/maps/manifest.json`. JPEGs use
quality 95 without chroma subsampling. The generated map set occupies about 510 MiB on disk; Mark
continues to hold only the current map texture, not the entire set. Zoneinfo's previews are unchanged.

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
