# expbar

A basic Ashita v4 experience bar in the shared WinXI theme. Shows your main job's
main/subjob and levels (for example `WAR75/NIN37`), current / required XP, progress
percentage, session XP gained, and optionally XP/hour. A character without a subjob
shows only the main job.

Choose **Window** or **Overlay** mode. Window mode keeps the usual themed window with
information above and below the bar. Overlay mode removes the window background,
border, shadow and padding. XP values and percentage are centred inside the larger
bar; job/level sits above its top-left corner, session XP below its bottom-left corner,
and XP/hour below its bottom-right corner.
Drag either layout to move it; lock it in settings to make it click-through.

## Install

Copy `addons/expbar` and `addons/libs/winxi` into your Ashita installation's `addons`
folder (merging the existing folders), then run:

```
/addon load expbar
```

No extra plugin is required. The optional `winxisettings` addon controls the shared theme.

## Commands

| Command | Action |
|---|---|
| `/expbar` or `/expbar config` | Open / close settings |
| `/expbar toggle` | Show / hide the bar |
| `/expbar pos <x> <y>` | Set the display's screen position in pixels |
| `/expbar mode window` | Use the themed window layout (default) |
| `/expbar mode overlay` | Use the larger, borderless bar with XP inside and labels outside |
| `/expbar show` / `/expbar hide` | Explicitly show / hide it |
| `/expbar rate` | Toggle the XP/hour line |
| `/expbar rate on` / `/expbar rate off` | Show / hide XP/hour |
| `/expbar reset` | Clear session gains and restart the rate with the next gain |

Settings include screen X/Y positioning with a reset-position button, a per-addon
bar texture selector (or **Follow shared theme**), overlay mode, bar width (180–1200 px), overlay height (40–160 px),
a bar colour picker with opacity, XP/hour visibility, window locking, and the usual
WinXI visibility rules. The overlay automatically grows beyond the requested dimensions
if necessary to fit the XP text and keep the outside labels from overlapping,
including with larger shared fonts.
The bar colour and texture apply in both layouts. Texture selection affects only
expbar; **Follow shared theme** uses the shared theme's texture instead. Position is
the top-left of the entire display, including the labels outside the overlay bar.
Position and display settings are saved per character; session gains are not saved
across addon reloads.

## Tracking

The bar reads current XP from game memory. Session gains come from the player's own
server XP and XP-chain battle messages, so leveling up does not break the total and
other players' gains are ignored. Death does not subtract from **XP gained**.
Limit points, capacity points, and XP awards that do not send these battle messages
are outside this basic addon's scope.

XP/hour is total session XP divided by elapsed time **since the first gain**, with a
minimum denominator of 60 seconds to keep the first kill from inflating the rate.
Idle time after the first gain counts, including time spent with the bar hidden.
This is a session average, not a rolling-hour rate. Reset when beginning a new party
or camp; changing character or main job also clears the session automatically.

## Checks

```
luajit tests/expbar_check.lua
luajit tests/harness.lua expbar addons/expbar/expbar.lua tests/expbar_ui_check.lua
```

These exercise tracking and UI wiring against stubs; live rendering and server behavior
still need an in-game check.
