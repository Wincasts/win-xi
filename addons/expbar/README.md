# expbar

A basic Ashita v4 experience bar in the shared WinXI theme. It shows your main job's
main/subjob and levels (for example `WAR75/NIN37`), current / required XP, progress
percentage, session XP gained, and, if you want it, XP/hour. A character without a subjob
shows only the main job.

Choose **Window** or **Overlay** mode. Window mode keeps the usual themed window, with
information above and below the bar. Overlay mode removes the window background,
border, shadow and padding. The XP values and percentage are centred inside the larger
bar. The job and level sit above its top-left corner, session XP below its bottom-left corner,
and XP/hour below its bottom-right corner.
Drag either layout to move it. Lock it in the settings to make it click-through.

## Install

Copy `addons/expbar` and `addons/libs/winxi` into your Ashita installation's `addons`
folder (merging the existing folders), then run:

```
/addon load expbar
```

No extra plugin is needed. The optional `winxisettings` addon controls the shared theme.

## Commands

| Command | Action |
|---|---|
| `/expbar` or `/expbar config` | Open / close the settings |
| `/expbar toggle` | Show / hide the bar |
| `/expbar pos <x> <y>` | Set the display's position on screen, in pixels |
| `/expbar mode window` | Use the themed window layout (default) |
| `/expbar mode overlay` | Use the larger, borderless bar with XP inside and labels outside |
| `/expbar show` / `/expbar hide` | Show it / hide it, rather than toggling |
| `/expbar rate` | Toggle the XP/hour line |
| `/expbar rate on` / `/expbar rate off` | Show / hide XP/hour |
| `/expbar reset` | Clear session gains and restart the rate with the next gain |

The settings include: screen X/Y position with a reset-position button, a bar texture
selector for this addon alone (or **Follow shared theme**), overlay mode, bar width (180–1200 px),
overlay height (40–160 px), a bar colour picker with opacity, XP/hour visibility, window locking,
and the usual WinXI visibility rules. The overlay grows beyond the size you asked for when it has
to, to fit the XP text and keep the outside labels from overlapping, including with larger shared
fonts.
The bar colour and texture apply in both layouts. The texture choice affects only
expbar; **Follow shared theme** uses the shared theme's texture instead. Position is
the top-left of the whole display, including the labels outside the overlay bar.
Position and display settings are saved per character. Session gains are not saved
across addon reloads.

## Tracking

The bar reads your current XP from game memory. Session gains come from your own
server XP and XP-chain battle messages, so leveling up does not break the total, and
other players' gains are ignored. Death does not take anything off **XP gained**.
Limit points, capacity points, and XP awards that do not send these battle messages
are outside this basic addon's scope.

XP/hour is the total session XP divided by the time passed **since the first gain**. The
divisor is never less than 60 seconds, so the first kill does not inflate the rate.
Idle time after the first gain counts, including time spent with the bar hidden.
This is a session average, not a rolling-hour rate. Reset it when you start a new party
or camp. Changing character or main job also clears the session on its own.

## Checks

```
luajit tests/expbar_check.lua
luajit tests/harness.lua expbar addons/expbar/expbar.lua tests/expbar_ui_check.lua
```

These test tracking and UI wiring against stubs. Live rendering and server behavior
still need an in-game check.
