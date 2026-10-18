# mapoverlay

The ground you can walk in the zone you are in, laid over the game, flat white-grey with a darker
rim and the game's own grid over it; everything off the ground is left clear. A marker shows where
you are and which way you face. **Style** can show the map's own artwork instead, cut to the ground.

## Commands

- `/mapoverlay` (or `/mov`) shows or hides the overlay
- `/mapoverlay config` opens or closes the settings
- `/mapoverlay status` says which map is drawn, or why none is

Bind it to a key with Ashita's `/bind`, for example `/bind F10 /mov`.

## Where it works

Only maps whose ground has been traced have an overlay; anywhere else nothing is drawn. Traced so
far (0.1):

| Zone | Maps | How |
| --- | --- | --- |
| Lower, Middle and Upper Delkfutt's Tower | every floor (16) | traced from the floor's colour, a few patches cut by hand |
| Qufim Island | 1 | the island inside its ink lines; the east shore and the canyon to Jeuno drawn by hand |
| Port Jeuno | 1 | streets traced; docks and Air Travel Agencies as rectangles by hand |
| Upper Jeuno | 1 | streets and shops traced |
| Ru'Lude Gardens | 1 | the Quadrangle traced; the palace and its roads by hand |
| Lower Jeuno | 1 | the main street drawn by hand as a band; the shops off it are not in |

The tower floors are the most faithful. The Jeuno maps draw streets as thin lines in nearly the
parchment's colour, so their shapes are rougher and partly hand-drawn.

In a zone of several floors, the floor is the client's own for where you stand, read as zone reads
it. A floor with no traced map draws nothing.

## Settings

**Overlay**

- **Visible**: whether the overlay shows.
- **Centered**: in the middle of the screen (on to start). Off, it stays where it is put:
  **Locked** off lets it be dragged, its edge drawn; on, clicks go through it. **Position** is its
  top left corner.
- **Size**: how wide and tall the overlay is, 150 to 1600 pixels.
- **Map Opacity**: how solid the ground is, 0.05 to 1 (0.85 to start).
- **Style**: **Flat** (to start) paints the ground in **Fill Color** (light grey) with its rim, a
  map unit and a half wide, in **Edge Color** (mid grey). **Map Art** is the map's own picture, only
  where the ground is. A colour change is painted again within a fifth of a second.

**Grid**

- **Show Grid** (on): the game's map squares, A to O across and 1 to 15 down, the same squares the
  clock names, drawn over the part of the map shown and across the whole overlay.
- **Grid Color** (black) and **Grid Opacity** (0.6): its lines, and how strongly they and the labels
  show.
- **Grid Labels** (on): each square's letter along the top and number down the left, in outlined
  text.

**View**

- **Fit To Walkable Area** (on): shows the part of the map with ground on it, as large as the
  overlay. Off, the whole map.
- **Zoom**: 1x to 4x. Past 1x, nearer, with you in the middle.

**Player**

- **Show Player**, **Player Color**, **Player Size**: the marker, 6 to 64 pixels.

The overlay follows Winxi Theme's hiding rules (cutscenes, menus) like the other winxi addons.

## How the ground is traced

`tools/trace_walkable_maps.py` reads each map's picture from XICombinedMaps-2048 and writes
`data/walkable.lua`: for each map, a mask two pixels to a map unit, as runs along each row. The
addon finds the ground's rim, softens the edge, and paints the two into a texture (`flat.lua`); with
Map Art it hands the mask to `winxi.mapdat`, which multiplies the picture's own alpha by it as it
reads the picture from the game's files. A mask traced from the pack's picture fits the
game's own picture too, as where a map lies is the client's table, not the picture.

What to trace and how is in `research/walkable.json`, by map key (as zone's `data/all_maps.lua`
names them). Each map can take:

- `colors`: the colour of the ground (a point on it, or `{"rgb": [r, g, b]}`). Every enclosed patch
  that colour is filled out to the ink round it. Squares of light parchment boxed in by the map's grid
  are left out unless they touch the ground across a grid line.
- `seeds` and `light`: for streets drawn in lines (the cities), each seed fills what is at least
  `light` bright, after the grid's lines are taken out, stopping at ink. A seed that runs out onto
  the parchment is left out, and the tool says so.
- `within`: a polygon, or `{"circle": [x, y, r]}`, the ground is kept inside.
- `walls`: lines drawn on the map first, to close an exit a fill would run out of.
- `drop`, `cut`, `add`, `paths`: ground taken away or given by hand.

```sh
python3 tools/trace_walkable_maps.py references/XICombinedMaps-2048 --preview /tmp/walkable
python3 tools/trace_walkable_maps.py references/XICombinedMaps-2048 --only 246_m_246_00_9a675ef2fc63 --preview /tmp/walkable
```

`--preview` writes each map as the overlay shows it; `--only` traces one map and writes nothing else.

What this cannot know: the ground is what the map paints, not what the game lets you walk on. Small
ledges, stairs drawn in another colour and the cities' side streets can be missing or extra.

Needs `addons/libs/winxi` 20 or newer.

Checks: `luajit tests/harness.lua mapoverlay addons/mapoverlay/mapoverlay.lua tests/mapoverlay_check.lua`,
`luajit tests/winxi_mapdat_check.lua` and `(cd tools && python3 -m unittest test_trace_walkable_maps)`.
