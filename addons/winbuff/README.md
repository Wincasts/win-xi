# winbuff

The statuses you are under, in a window, with FFXIV's icons and the time each has left. It stands in
for the game's own row of status icons, which it switches off. It needs only the `winxi` library
(`addons/libs/winxi`).

- `/winbuff` opens or closes the settings. **Visible**, under Window, shows or hides the bar (it only
  appears while there is a status to show).
- `/winbuff help` lists the commands.

`/buff` still works as `/winbuff`.

Hover over an icon for the status's name, number and description. Right click one to remove it, where
the game allows that. In the game's buff selector, any click on an icon removes it.

Unload `statustimers` first. Both switch the game's own icons off, and the second to try says it
could not.

## Renamed from buff

Up to 1.1 this addon was called buff. Unload buff, load `winbuff` in its place and remove the old
`addons\buff` folder; change `load buff` to `load winbuff` in any startup script. Never run both: they patch
the same native icon routines. Each character's settings are brought over from `config/addons/buff/` the
first time it logs in.

Before that it was called buffs. Settings kept under `config/addons/buffs/` are not brought over: copy them
to `config/addons/winbuff/` before you first load winbuff, without overwriting any settings already there.

## Automatic default-HUD placement

**Anchor To Default Location** is on by default. It puts a locked, transparent, borderless bar where
the game's own status icons are. With the `buffhook` plugin, the game says where that is. Without it,
the bar goes at the default buff location measured from a screenshot: about `148, 50` in native menu
coordinates. Ashita's `scaling` helper gives the menu resolution, and the current display size sets
the menu-to-screen scale on each axis separately. If the helper is not available, or its dimensions
are not valid, the placement falls back to 1:1.

**Anchor Adjustment** is an optional nudge in screen pixels (default: `0, 0`). Set it with its X and
Y sliders (Ctrl+click one to type a number), or drag the bar with the left button. The bar stays
anchored as you drag it, under the game's menus with the plugin. In the game's buff selector, a click
removes a status instead. **Lock Position** stops the dragging. Old absolute `anchorOffset` settings
are no longer used, so the old `(6, 6)` default does not shift this anchor. Icon size, timers and
wrapping still use the normal settings. This only positions the bar, not its individual icons. Theme
padding, backgrounds, borders and shadows do not move or decorate the anchored bar.

**Grow From** says where a row's icons sit as statuses come and go: **Left**, as the game has them,
**Right** or **Middle**. Anchored, the bar spans a full row of Icons Per Row from where it is placed,
and each row sits at its left, its right or in its middle. The mouse finds the icons where they are
drawn. The dragged window keeps its top left, top right or top middle where it is.

**Show Backdrop** (on by default) gives the dragged window the theme's backdrop, border and shadow.
Off, its icons and times sit straight over the game. The anchored bar never has one.

Turn anchoring off to go back to the draggable window. Its saved **Position** (X and Y sliders, or
drag the window; Lock Position holds it) is kept separately, so adjusting the anchor does not
overwrite where you put the free window.

Anchored buffs disappear at once while the native interface is hidden, while zoning, and during
events. The addon's own hiding rules, which you can change, still apply in both positioning modes
(including expanded chat and maps by default). Existing character settings are updated once to bring
back map hiding. After that, your changes to the hiding rules are kept.

## Under the game's menus: the uihook plugin

With the `uihook` plugin loaded (`/load uihook`, before `/addon load winbuff`), the plugin draws the
anchored bar where, and when, the game draws its own row of status icons, in their place (see
[plugins/uihook](../../plugins/uihook)). It then behaves as the game's icons do: the menus the game
opens over them (the macro palettes, the main menu and the rest) are drawn over the bar, a menu that
covers part of it covers just that part, and it goes when the game would not draw its icons. It is
placed where the game puts its first icon, not where it was measured to be. **Anchor Adjustment**
still nudges it from there. Hovering over an icon still shows its tooltip, and a right click removes
it, while no menu of the game's is open.

**The buff selector.** The game's selector (its cursor on the status icons, to remove one) points
its hand at where the game's own icons would be. That is not where the bar's icons are once they have
a size of their own. With the plugin, the game's hand is put out of sight, and buff draws it again at
the left of the status the game's cursor is on, pointing at it as the game's menus do. It is the
game's own animated hand from its menu DAT, anchored or dragged. **Cursor Size** is how tall the hand
is, as a share of an icon's height (60% to begin with). Where the hand cannot be read, the status has
winxi's highlight round it instead (the controller's: a line and a fainter glow outside it). The
selector is still the game's: its keys and the controller move the cursor. The controller's confirm
removes the status the cursor is on. The press still reaches the game, and if the game has not asked
the server to remove the status a quarter of a second later, winbuff asks (**Controller**:
**Controller Navigation** is on to begin with; an XInput controller's A is always heard, and
**Controller Type**, Automatic to begin with, follows the game's own setting as the Phoenix launcher sets it or picks the DirectInput make, PlayStation's cross where XInput is in use). A click on
an icon removes that one too.
Dragged elsewhere, with **Hide Game's Icons** on, the plugin keeps the game's row and its hand away,
instead of changing the game's code. Without the plugin there is no hand, but a click still removes.

Without the plugin, or with one that did not recognise the client, the anchored bar is a window
drawn over everything, at the place measured below, and the settings say why. Draggable mode is
always a window.

**Placement without the plugin:** the default origin was measured from a screenshot at 1:1 menu
scale, not read from the live native buff
bar. The menu resolution is cached by Ashita's scaling helper when winbuff loads; reload winbuff after
changing that configuration.

## Settings

- **Custom Icons** (Winxi Theme): follows Winxi's choice of icon set (FFXIV to start, or any folder
  of icons added to `libs/winxi/statusicons`), or None for the game's own icons. With a set chosen, a
  status it has no icon for still uses the game's icon.
  The old addon-specific **FFXIV Icons** setting is no longer used.
- **Icon Size**: an icon's height in pixels. The icons are 64 tall as made, so 64 and 32 are sharpest.
- **Icons Per Row**: how many icons before a new row starts.
The settings window has Window, Icons, **Durations**, **Removable Marks** and Controller sections.

- **Show Durations** (Durations): the time under each icon: seconds, then minutes (`m`), then hours (`h`).
- **Your Colour**: the colour of the time under a status you cast on yourself, green to begin with.
  When someone else casts the same status over yours, its time goes back to the usual colour, so you can
  see yours was replaced. Only a cast seen to land counts: one already on you when the addon started is
  not shown as yours. It is kept through a change of area.
- **Low Time Warning**: below this many seconds left, the icon fades out and in; 10 to begin with, 0 for
  no warning.
- **Removable Marks**, off to begin with: a small square in a dark border inside the corner of each of
  your debuffs that Erase, a -na spell or a waltz removes, in **Curable Mark Colour** (light blue).
  **Only What You Can Remove** marks only what a spell you have learned, at your level now, takes off,
  level sync included. Your buffs are never marked: Dispel is for a monster's.
- **Font**: the font for countdowns and status tooltips, chosen from `C:\Windows\Fonts`.
  **Theme Font** (default) uses the Winxi theme font, in both anchored and draggable modes.
- **Font Size**: text size in pixels. `0` (**Theme Size**, default) uses the current theme size.
  This does not resize the icons. Timer spacing and cached measurements update on their own.
- **Hide Game's Icons**: stops the game drawing its own row. The row comes back when this is switched
  off or the addon unloads. Anchored with the plugin, the bar takes the row's place whatever this says.

## The icons

The icons are winxi's, shared with the winparty addon. `libs/winxi/statusicons/ffxiv/<status number>.png`
is the icon for an FFXI status: FFXIV's, 48 by 64 in the middle of a square of 64. A status with no
file there has the game's own icon. You can put any 64 by 64 PNG of that shape in its place, or make
a set of your own beside it (see Custom icons in the winxi README).

A bard's songs, a corsair's rolls and a puppetmaster's maneuvers each share one FFXIV icon, in the
colours FFXI gives them. Statuses with exactly the same name are matched as they are. The rest are a
first choice by what the status does, and many could be bettered.

After the `statustimers` addon by heals, which showed how the times are read and how the game's own
icons are switched off.
