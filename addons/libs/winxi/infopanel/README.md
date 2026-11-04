# Shared info panel (Winxi 22)

This is the info panel that winchat shows next to its chat log. It shows the time, the zone, your EXP
and the weather, and the map grid if you want it. You do not load it on its own: it comes with winxi,
and winchat uses it.

## What it shows

- The time, the zone, EXP and the weather. It can also show the map grid (your square on the map).
- The weather and the map grid work even when the game's own clock is not shown.
- If the weather cannot be read for a moment, the panel keeps showing the last weather it read.
  Changing zone or changing character clears it.
- The panel knows each zone's weather chances, as the server rolls them.

Some words in the panel show a tooltip when you rest the mouse on them:

- the time, day, date and moon: the Vana'diel month as a calendar;
- the zone name: the timetable of the ships and airships. It shows the next four to leave, for the
  routes you have chosen.

By default the panel sits right against the chat log. It does not change the chat window's position or
size, and it does not move the game's menus.

## Your own icons

You can add your own icon sets. Put them in `icons/<set>/days` and `icons/<set>/weather`. Use the same
file names as the `gems` set that comes with it:

- the eight days;
- the eight elements;
- `clear`, `clouds` and `fog`, for the skies the game has no icon for.

See [winchat](../../../winchat/README.md#info-panel) for the controls, the fields you can show
and moving from older versions.
