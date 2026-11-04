# vis

Extends how far the game draws terrain, buildings and characters, with independent control over the
fog. Objects no longer pop in or lose detail as you approach, and distant terrain the game would
normally hide can be drawn.

## Highlights

- See further than the game normally allows, without objects popping in nearby.
- Keep the standard fog or move it further out.
- Separate settings for cities, outdoor areas and dungeons, or for a single zone, applied
  automatically as you arrive.

Every value is saved for each character and applied when the addon loads.

## Before you start

- vis replaces the standard `drawdistance` addon. Unload `drawdistance` and remove its lines from your
  startup script.
- vis needs nothing else. Its download carries its own copy of the parts of winxi it uses (including
  the server data it reads, and what kind of area each zone is).

### Renamed from drawscale

vis was called drawscale until 2.1, and its `terrain` setting was called `vis`.

- The first time vis loads for a character, it copies their drawscale settings and says so. A saved
  `vis` setting is read as `terrain`.
- In your startup script, replace `/addon load drawscale` with `/addon load vis`.
- Do not load both. They change the same parts of the game.

## Commands

"Stock" below means the game's normal value. `1` is stock, `2` is twice as far, and so on.

| Command | What it does |
|---|---|
| `/vis` | Says the current values. |
| `/vis world <n>` | Sets terrain, objects and the far edge of the view to `n` times stock. `1` is stock. |
| `/vis entity <n>` | Sets players, NPCs and monsters to `n` times stock. The server only sends characters within about 50 yalms, so going further changes little. |
| `/vis fog <n>` | Sets the fog to `n` times stock, whatever `world` is. `1` keeps the normal fog, in front of however much terrain `world` draws. |
| `/vis objects <n>` | Sets how far buildings, trees and props are drawn, at `n` times stock. `0` (the default) follows `world`. |
| `/vis detail <n>` | Sets how much further objects keep their detailed shape. `0` (the default) follows `world`. |
| `/vis terrain on` / `off` | Draws distant terrain that the game would hide from where you are (off by default). `/vis terrain` alone switches it on or off. |

More about some of these:

- **objects**: without this setting, a `world` of 2 only pushes objects out about 1.4 times. This is
  because of how the game measures distance. Objects would then pop in well inside the range you can
  see.
- **detail**: each object has three versions, from detailed to simple. The game switches between them
  at two fixed distances. `detail` moves both of these distances out by `n`.
- **terrain**: each zone has built-in lists of what can be seen from where. Terrain that is not on the
  list is never drawn, however far the draw distance goes. It then pops in as you cross into the next
  part of the zone. `terrain on` draws it anyway.
  - It costs frame rate in big zones.
  - With the fog at stock, most of what it adds is hidden by the fog anyway.
  - It was on by default until 2.2. If you had it on before 2.2, it is turned off once, and vis says
    so when it loads.

### Field of view moved to lens

The field of view and the world's true proportions were the `fov` and `square` settings until 2.0.
They are now part of the lens plugin: `/lens fov`, `/lens middle` and `/lens square`, with or without
lens's warp. If a character had saved `fov` or `square` values, vis says them once when it loads, as
the lens commands that set them. A zone's or a preset's own `fov` and `square` are gone.

## Settings for each kind of zone, and for each zone

The values above are the general ones. You can set two more layers on top of them:

1. **A preset for each kind of zone.** Every zone on the server is a city, outdoors or a dungeon.
   (Dungeons include instanced areas, Dynamis and battlefields.) The kind comes from the server's zone
   data.
2. **A zone's own values.** These apply only to one zone.

Each layer holds only what you set in it. For each value, the most specific layer that has it wins:
the zone's own value first, then the preset, then the general value.

### Preset commands

| Command | What it does |
|---|---|
| `/vis dungeon world 2` | Sets `world` for every dungeon. `/vis city terrain off`, `/vis outdoors fog 1.5` and the rest work the same way. |
| `/vis dungeon` | Shows the dungeon preset. |
| `/vis dungeon world clear` | Takes one value out of the preset. |
| `/vis dungeon clear` | Empties the preset. |

At first, cities and dungeons have `world` x2 in their presets. The outdoors preset is empty, so the
outdoors use the general values.

### Zone commands

| Command | What it does |
|---|---|
| `/vis zone world 3` | Sets `world` for the zone you are in, and only that zone. |
| `/vis zone world clear` | Takes that value out. |
| `/vis zone clear` | Takes out all of this zone's values. |
| `/vis zone list` | Lists every zone that has values of its own. |

### Example

In a dungeon, with the presets as they start, `world` is 2 (from the dungeon preset) and everything
else is the general value. If that dungeon has its own `world` of 3, it uses 3.

The values change as each new zone loads. A line in the chat says what the zone gets from its own
values and from its kind's preset. `/vis` says which zone you are in, its kind, the values in use and
where each one comes from. A zone the server has no data for has no known kind. It uses the general
values, plus its own if it has any.

## How it works

The game multiplies all of its draw distances by two numbers: one for the world and one for
characters. vis sets those two numbers. It also changes the few places where the game reads the fog,
the object range, the object detail and the zone's visibility lists, so that each follows its own
setting.

Unloading vis puts back everything it changed, and sets both numbers back to 1.

## After a game update

vis finds the parts of the game it changes while the game runs. If a game update moves one of them,
the setting that uses it says so when vis loads, and the other settings keep working.

## If something goes wrong

If an error happens in vis, it says so once in the chat and keeps going. This is on purpose: when an
addon has an error, Ashita unloads it without letting it put the game back.

A game left changed that way (drawscale 1.6 could do this, 2026-10-21) shows up as the fog, range and
detail places "not found" when vis loads. Restarting the game fixes it.
