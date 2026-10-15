# buff

The statuses you are under, in a window, with FFXIV's icons and the time each has left. It stands in
for the game's own row of status icons, which it switches off. It needs only the `winxi` library
(`addons/libs/winxi`).

- `/buff` shows or hides the window (it only appears while there is a status to show)
- `/buff config` opens or closes the settings

Hover over an icon for the status's name, number and description; right click one to remove it, where
the game allows that.

Unload `statustimers` first: both switch the game's own icons off, and the second to try says it could
not.

## Renamed from buffs

The folder and entry point are now `addons/buff/buff.lua`. Unload the old addon before loading
this one; never run both, as they patch the same native icon routines. Update any startup script
from `load buffs` to `load buff`. The old `/buffs` command is no longer handled.

Settings now live under `config/addons/buff/`. To preserve existing character settings, copy the
contents of `config/addons/buffs/` there **before first loading buff**, without overwriting any
existing buff settings. No live installation or settings files are changed by the repository rename.

## Automatic default-HUD placement

**Anchor To Default Location** is enabled by default. It draws a locked, transparent, borderless
bar below the help strip, at the screenshot-calibrated default buff location: approximately
`148, 50` in native menu coordinates. Ashita's existing `scaling` helper supplies the menu
resolution; the current display size determines the menu-to-screen scale independently on each
axis. If the helper is unavailable or its dimensions are invalid, placement falls back to 1:1.

**Anchor Adjustment** is an optional screen-pixel nudge (default: `0, 0`). Old absolute
`anchorOffset` settings are no longer used, so the previous `(6, 6)` default does not shift this
anchor. Icon size, timers and wrapping still use the normal settings; this change only positions
the bar, not its individual icons. Theme padding, backgrounds, borders and shadows do not move
or decorate the anchored bar.

Disable anchoring to return to the draggable window. Its saved **Position** is kept separately,
so adjusting the anchor does not overwrite your free-window placement.

Anchored buffs disappear immediately while the native interface is hidden, zoning, and during
events. The configurable addon hiding rules still apply in both positioning modes (including
expanded chat and maps by default). Existing character settings are updated once to restore map
hiding, after which manual changes to the hiding rules are respected.
Those rules are separate from native UI layering. **Hide Anchored Buffs With Menus** is enabled
by default: it immediately hides the anchored bar for any native menu or submenu, including macro
palettes (`mcr1pall`/`mcr2pall`), with no remaining tooltip or cancellation targets. This covers
profile, job levels, skills, currencies, unity, playtime, equipment/automaton equipment, magic,
items, synthesis, abilities, party, trade, search, linkshell, region info, Mog House, missions,
quests, key items, View House, bazaar, macros, config, help desk, current time, and communication.
The buff selector and ordinary inline chat input are exempt. This menu rule does not apply in
draggable mode; shared expanded-chat/map rules still apply in both modes. Disable it to leave
anchored buffs visible during menus too; native overlap clipping is still not implemented.

**Current limitations:** the default origin was measured from
`screenshots/Screenshot_20261014_111534.png` at 1:1 menu scale, not read from the live native buff
bar. UI scaling is automatic, but custom native layouts and other scales still need in-game
validation. Menu resolution is cached by Ashita's scaling helper at load time; reload buff after
changing that configuration. This does not use the experimental `menurect` addon. **Native menu
overlap clipping is not implemented yet**: ImGui draws after the game UI, so overlapping buffs can still
appear above native menus. Correct layering must preserve uncovered parts of the bar and suppress
both rendering and interaction in covered regions, using verified native menu rectangles or a
native-layer rendering hook. This version does not claim native draw-order inheritance. Controller
selection/cancellation is not added by anchoring.

## Settings

- **Custom Icons** (Winxi Theme): follows Winxi's choice of icon set (FFXIV to start, or any folder
  of icons added to `libs/winxi/statusicons`), or None for the game's own icons. With a set chosen,
  statuses it has no icon for still use the game's icon.
  The old addon-specific **FFXIV Icons** setting is no longer used.
- **Icon Size**: an icon's height in pixels. The icons are 64 tall as made, so 64 and 32 are sharpest.
- **Icons Per Row**: how many before a new row starts.
- **Show Time Left**: the time under each icon: seconds, then minutes (`m`), then hours (`h`).
- **Font**: the font for countdowns and status tooltips, selected from `C:\Windows\Fonts`.
  **Theme Font** (default) inherits the Winxi theme font in both anchored and draggable modes.
- **Font Size**: text size in pixels; `0` (**Theme Size**, default) inherits the current theme size.
  This does not resize the icons. Timer spacing and cached measurements update automatically.
- **Hide Game's Icons**: stops the game drawing its own row. They come back when this is switched off
  or the addon unloads.

## Optimization check

```
luajit tests/harness.lua buff addons/buff/buff.lua tests/buff_check.lua
luajit tests/harness.lua buff addons/buff/buff.lua tests/buff_performance_check.lua
```

The performance check counts work over 120 warmed-up frames with 32 statuses. Compared with the
previous live `buffs` implementation using the same fixture:

| Work over 120 frames | Before | After |
| --- | ---: | ---: |
| Timer metadata lookups, timers enabled | 2,880 | 0 |
| Text measurements, timers enabled | 2,040 | 0 |
| Menu checks, anchored bar visible | 240 | 120 |
| Timer-array fetches, timers disabled | 120 | 0 |
| Game-clock reads, timers disabled | 360 | 0 |
| Timer-array fetches, empty bar | 120 | 0 |
| Status-array fetches, visibility off and fading disabled | 120 | 0 |

Static timer flags and text widths are cached; font face/size changes invalidate text measurements.
Status entries are reused, not rebuilt. Timer arrays are read only if requested and at least one
status is present; the game clock is read only for finite timers. Tooltip cancellation reuses the
resource lookup already needed for the tooltip. Native patch scanning remains outside the frame
loop, and shared icon textures already use the library's cache.

These are synthetic call-count checks, **not an FPS claim or an in-game CPU/GPU benchmark**.
Rendering still emits one image per icon and updates countdowns every visible frame. Fade-out
frames still read statuses when fading is enabled. To print only the main measurement scenes
without enforcing optimized budgets (for comparison against an older implementation), append
`measure` to the performance-check command.

## The icons

The icons are winxi's, shared with the party addon: `libs/winxi/statusicons/ffxiv/<status number>.png` is the icon
for an FFXI status: FFXIV's, 48 by 64 in the middle of a square
of 64. A status with no file there has the game's own icon. Any 64 by 64 PNG of that shape can be put
in its place, or a set of your own made beside it (see Custom icons in the winxi README).

They are made by `tools/build_status_icons.py` from `tools/status_icons.csv`, which says which FFXIV
icon stands for each FFXI status. To change one, put another FFXIV status name or icon number on its
line (`references/ffxiv-status-icons/index.html` is there to pick from) and run the tool again;
`--sheet sheet.png` draws every status beside its icon to look the choices over. A line's `tint` is a
colour the icon is turned to: a bard's songs, a corsair's rolls and a puppetmaster's maneuvers each share
one FFXIV icon, in the colours FFXI gives them. Statuses of the same
name exactly are matched as they are; the rest are a first choice by what the status does, and many
could be bettered.

After the `statustimers` addon by heals, which showed how the times are read and how the game's own
icons are switched off.
