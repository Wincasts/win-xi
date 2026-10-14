# buffs

The statuses you are under, in a window, with FFXIV's icons and the time each has left. It stands in
for the game's own row of status icons, which it switches off. It needs only the `winxi` library
(`addons/libs/winxi`).

- `/buffs` shows or hides the window (it only appears while there is a status to show)
- `/buffs config` opens or closes the settings

Hover over an icon for the status's name, number and description; right click one to remove it, where
the game allows that.

Unload `statustimers` first: both switch the game's own icons off, and the second to try says it could
not.

## Settings

- **FFXIV Icons**: the icons of the `icons` folder, for every status that has one there. Off, every
  status has the game's own icon.
- **Icon Size**: an icon's height in pixels. The icons are 64 tall as made, so 64 and 32 are sharpest.
- **Icons Per Row**: how many before a new row starts.
- **Show Time Left**: the time under each icon: seconds, then minutes (`m`), then hours (`h`).
- **Hide Game's Icons**: stops the game drawing its own row. They come back when this is switched off
  or the addon unloads.

## The icons

`icons/<status number>.png` is the icon for an FFXI status: FFXIV's, 48 by 64 in the middle of a square
of 64. A status with no file there has the game's own icon. Any 64 by 64 PNG of that shape can be put
in its place.

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
