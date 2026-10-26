# buff

The statuses you are under, in a window, with FFXIV's icons and the time each has left. It stands in
for the game's own row of status icons, which it switches off. It needs only the `winxi` library
(`addons/libs/winxi`).

- `/buff` shows or hides the window (it only appears while there is a status to show)
- `/buff config` opens or closes the settings

Hover over an icon for the status's name, number and description; right click one to remove it, where
the game allows that. In the game's buff selector, any click on an icon removes it.

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

**Anchor To Default Location** is enabled by default. It puts a locked, transparent, borderless
bar where the game's own status icons are. With the `buffhook` plugin the game says where that is;
without it, the bar goes at the screenshot-calibrated default buff location: approximately
`148, 50` in native menu coordinates. Ashita's existing `scaling` helper supplies the menu
resolution; the current display size determines the menu-to-screen scale independently on each
axis. If the helper is unavailable or its dimensions are invalid, placement falls back to 1:1.

**Anchor Adjustment** is an optional screen-pixel nudge (default: `0, 0`), set with its X and Y
sliders (Ctrl+click one to type a number) or by dragging the bar with the left button. The bar
stays anchored as it is dragged, under the game's menus with the plugin; in the game's buff
selector a click removes a status instead. **Lock Position** stops the dragging. Old absolute
`anchorOffset` settings are no longer used, so the previous `(6, 6)` default does not shift this
anchor. Icon size, timers and wrapping still use the normal settings; this change only positions
the bar, not its individual icons. Theme padding, backgrounds, borders and shadows do not move
or decorate the anchored bar.

**Grow From** says where a row's icons sit as statuses come and go: **Left**, as the game has them,
**Right** or **Middle**. Anchored, the bar spans a full row of Icons Per Row from where it is placed,
and each row sits at its left, its right or in its middle; the mouse finds the icons where they are
drawn. The dragged window keeps its top left, top right or top middle where it is.

**Show Backdrop** (on by default) gives the dragged window the theme's backdrop, border and shadow.
Off, its icons and times sit straight over the game. The anchored bar never has one.

Disable anchoring to return to the draggable window. Its saved **Position** (X and Y sliders, or
drag the window; Lock Position holds it) is kept separately, so adjusting the anchor does not
overwrite your free-window placement.

Anchored buffs disappear immediately while the native interface is hidden, zoning, and during
events. The configurable addon hiding rules still apply in both positioning modes (including
expanded chat and maps by default). Existing character settings are updated once to restore map
hiding, after which manual changes to the hiding rules are respected.

## Under the game's menus: the uihook plugin

With the `uihook` plugin loaded (`/load uihook`, before `/addon load buff`), the anchored bar is drawn by the plugin where, and when, the
game draws its own row of status icons, in their place (see [plugins/uihook](../../plugins/uihook)). It then behaves as the game's icons do: the menus the
game opens over them (the macro palettes, the main menu and the rest) are drawn over the bar, a menu
that covers part of it covers just that part, and it goes when the game would not draw its icons.
It is placed where the game puts its first icon, not where it was measured to be: **Anchor
Adjustment** still nudges it from there. Hovering an icon still shows its tooltip, and a right click
removes it, while no menu of the game's is open.

**The buff selector.** The game's selector (its cursor on the status icons, to remove one) points
its hand at where the game's own icons would be, which is not where the bar's are once they are a
size of their own. With the plugin, the game's hand is put out of sight and buff draws it again at the
left of the status the game's cursor is on, pointing at it as the game's menus do: the game's own
animated hand from its menu DAT, anchored or dragged. **Cursor Size** is how tall the hand is, as a
share of an icon's height (60% to begin with). Where the hand cannot be
read, the status has winxi's highlight round it instead (the controller's: a line and a fainter glow
outside it). The selector is still the game's: its keys and the controller move the cursor.
The controller's confirm removes the status the cursor is on: the press still reaches the game, and
if the game has not asked the server to remove the status a quarter of a second later, buff asks
(**Controller**: **Controller Navigation** on to begin with; an XInput controller's A is always
heard, and **Controller Type** picks the DirectInput make, PlayStation's cross with XInput chosen).
A click on an icon removes that one too.
Dragged elsewhere, with **Hide Game's Icons** on, the plugin keeps the game's row and its hand away
in place of changing the game's code. Without the plugin there is no hand, but a click still
removes.

Without the plugin, or with one that did not recognise the client, the anchored bar is a window
drawn over everything, at the place measured below, and the settings say why. Draggable mode is
always a window.

**Placement without the plugin:** the default origin was measured from
`screenshots/Screenshot_20261014_111534.png` at 1:1 menu scale, not read from the live native buff
bar. Menu resolution is cached by Ashita's scaling helper at load time; reload buff after changing
that configuration.

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
  or the addon unloads. Anchored with the plugin, the bar takes the row's place whatever this says.

## Optimization check

```
luajit tests/harness.lua buff addons/buff/buff.lua tests/buff_check.lua
luajit tests/harness.lua buff addons/buff/buff.lua tests/buff_performance_check.lua
luajit tests/harness.lua buff addons/buff/buff.lua tests/buff_hook_performance_check.lua
```

The performance check counts work over 120 warmed-up frames with 32 statuses. Compared with the
previous live `buffs` implementation using the same fixture:

| Work over 120 frames | Before | After |
| --- | ---: | ---: |
| Timer metadata lookups, timers enabled | 2,880 | 0 |
| Text measurements, timers enabled | 2,040 | 0 |
| Menu checks, anchored bar visible (the selector, once a frame) | 240 | 120 |
| Timer-array fetches, timers disabled | 120 | 0 |
| Game-clock reads, timers disabled | 360 | 0 |
| Timer-array fetches, empty bar | 120 | 0 |
| Status-array fetches, visibility off and fading disabled | 120 | 0 |

Static timer flags and text widths are cached; font face/size changes invalidate text measurements.
Status entries are reused, not rebuilt. Timer arrays are read only if requested and at least one
status is present; the game clock is read only for finite timers. Tooltip cancellation reuses the
resource lookup already needed for the tooltip. Native patch scanning remains outside the frame
loop, and shared icon textures already use the library's cache.

The hook check counts the anchored bar handed to the buffhook plugin, over 120 frames with 32
statuses, each with a time:

| Work over 120 frames, handed to the plugin | First version | Then | Now |
| --- | ---: | ---: | ---: |
| Bars written (the times going down once a second) | 120 | 120 | 4 |
| Quads written, times steady | 47,040 | 47,040 | 0 |
| Letter fields read from imgui (each a call into it) | 475,200 | 475,200 | 480 |
| Letter lookups | 720 | 720 | 120 |
| Textures the bar is drawn from, winxi's icon sheet ready | 33 | 33 | 2 |
| Lua memory made, per frame | 0.53 KiB | 0.09 KiB | about 0.1 KiB |

The bar changes as a time does, about once a second. Everything it is made from (the statuses, their
icons and times, the layout, the colours, the cursor, the font) is noted each frame and compared with
the last bar written: unchanged, the same bar is handed over again and nothing is written, and the
plugin draws from the vertices it made of it last. The letters are copied out of imgui once each, and
one is looked at each frame to see that imgui has not moved them in its texture. Icons come from
winxi's sheet of every icon once they are on it (filled a few a frame), so the bar is drawn in a run
or two, not one for each icon. Ashita is asked once a frame whether the plugin is still loaded, as its
block goes with it, and the game's menu once a frame for the selector.

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
