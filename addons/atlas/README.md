# atlas

The map of the zone you are in, in a window of its own: the game's own picture, with you, your party
and alliance, and your target on it. It follows the floor you are on, and pans and zooms.

The game's `/map` is left to the game: this is `/atlas`.

## Commands

- `/atlas` shows or hides the map
- `/atlas config` opens or closes the settings
- `/atlas status` says which map is drawn, or why none is
- `/atlas browse` gives the map the controller, or gives it back; it opens the map if hidden. Put it in a
  game macro to open the map from the controller.
- `/atlas cycle` steps the map through three modes, one each time: **hidden**, **open** (shown, with
  the controller, as `/atlas browse`) and **passthrough** (shown, with the controller left to the
  game, fading to **Passthrough Opacity** while you move), then hidden again. A map shown by `/atlas` goes to open next. With
  Controller Navigation off, open is just shown. Put it in a game macro for one button that does all three.

## The map

- **Mouse wheel** zooms, 1x to 8x, round the place under the mouse; **−** and **+** zoom round the middle.
- **Drag** pans, and stops following you. **Follow** keeps you in the middle again; **Whole Map**
  shows all of it.
- In a zone of several maps, the floor buttons over the map show another; **Auto** goes back to
  the one you are on.
- Over the map, the tooltip gives the grid square, the place in the zone and who is under the mouse.
- The grid square you are in is under the map.

## With a controller

`/atlas browse` (or the open step of `/atlas cycle`) gives the map the controller, as the game's own
map takes it while open:

| Button | Does |
| --- | --- |
| Left stick | scrolls, faster the further it is pushed |
| D-pad | scrolls a tenth of the view, repeating while held |
| RB / LB | zooms in / out a step: 1x, 1.5x, 2x, 3x, 4x, 6x, 8x |
| Y | puts a waypoint under the cursor (moving the one there was); on the waypoint, takes it away |
| A | locks the map to you: back to your floor, following you, the cursor on you |
| X | the zone's next floor, then back to yours |
| B | gives the controller back, and hides the map again if browsing opened it |

The buttons go through winxi's controller handling: they are kept from the game while the map has
them, and **Controller Type** picks XInput or a DirectInput layout. The left stick is kept from the game
while the map has the controller, so you don't walk off, and as browsing begins the game is told it
is centred, so if you were running you stop. The right stick stays the game's, for the camera. To
walk with the map up, use passthrough (`/atlas cycle`). The stick is read from the kind of controller
**Controller Type** names: an XInput controller's as Ashita's buttons 18 and 19, a DirectInput one's
as its axes 0 and 4.

While the map has the controller a cursor sits in the middle of it, or on you while the map is
locked to you (near the map's edge, where the view cannot centre on you). Scrolling stops the lock
and moves the map under the cursor. The waypoint is drawn on its floor's map as a ring round a dot, and its grid square shows under the
map. There is one at a time, and it is forgotten as you change zone. For now it only marks the place.

The triggers are not the map's. With tcrossbar loaded they stay its while you browse: hold L2 or R2
and the crossbar comes up, and the buttons you press while holding it fire its macros rather than
working the map. (This needs the tcrossbar in `forks/addons`; another crossbar addon, or none, leaves
the triggers to the game.)

## Markers

- **You**: an arrow the way you face.
- **Party** and **Alliance**: a dot each. A member the game is showing is where it has them. One further
  off is drawn hollow where the server last said, for ten seconds.
- **Target**: a diamond.

## Settings

**Window**

- **Visible**: whether the map shows.
- **Lock Window**: keeps the window where it is. The map can still be panned and zoomed.
- **Map Size**: 256 to 1024 pixels (512 to start).
- **Passthrough Opacity**: in passthrough, the map fades to this while your character moves and
  comes back about half a second after you stop, 0% to 100% (30% to start). At 0% it is gone until
  you stop. The mouse over the map shows it whole. Open, or shown by `/atlas`, it never fades.

**Markers**

- **Show Player**, **Show Party**, **Show Alliance** and **Show Target**, each with its colour.
- **Show Names**: names beside the party, the alliance and the target.
- **Marker Size**: 4 to 24 pixels.

**Controller**

- **Controller Navigation** (on): whether `/atlas browse` can give the map the controller.
- **Controller Sounds** and **Controller Type**, as in winxi's other addons.

**Party**

- **Party Across Zone** (on): while one of your party is in the zone but out of sight, asks the server
  where your party is every three seconds. The request is 0x0D2 and the server answers each member
  with 0x0A0, the same exchange the game's own map makes while it is open.

**Visibility**

- **Hide While Map Open**, **Hide While Chat Open**, **Hide While Loading**, **Hide During Events** and
  **Hide With Game Interface**, as in winxi's other addons.

## How it knows where things are

- **Which maps a zone has**: `data/maps.lua`, written by `tools/build_atlas_maps.py` from zone's
  `data/all_maps.lua`. It covers 200 zones and 448 maps.
- **How a map lies over the zone**: the client's own table of maps, read from memory as zone,
  mark and boussole read it. Each entry is checked against the zone and floor it should be.
- **Which floor a place is on**: the client's floor function, which only works for the zone you are in.
- **The pictures**: the game's own files, read by `winxi.mapdat`. These are XICombinedMaps' 2048-pixel
  ones where pivot has them, and the game's 512-pixel ones where it does not.

## Drawing in place of the game's map (later)

`view.lua` draws a map into any square it is given and knows nothing of the window. Atlas's
window is one such square. The plan is to hand it the square where the game draws its own map:

1. When the game's map menu (`menu    map     `) is open, a uihook slot stops it from drawing
   (its logic still runs) and reports its window's position on screen, as chat's slot does for the log.
2. Atlas draws `view.Draw` into that square, so the game's map key, menu entry, controller and
   Escape still open and close it.
3. Reading the game map's own zoom, scroll and shown floor from memory would let atlas follow them.
   That needs research first.

## Files

| File | What it does |
| --- | --- |
| `atlas.lua` | the addon: window, settings, which map is shown |
| `maps.lua` | the zone's maps, the client's map table and floor, the pictures |
| `markers.lua` | who is where: memory, and the server's 0x0A0 |
| `view.lua` | a map drawn into a square: pan, zoom, markers |
| `pad.lua` | the controller while browsing: buttons, the stick |
| `moving.lua` | how much of the map shows while you move |
| `data/maps.lua` | generated: zone → its maps |

`tests/atlas_check.lua` runs it against the stand-in for Ashita.
