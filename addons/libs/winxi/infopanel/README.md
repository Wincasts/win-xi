# Shared info panel (Winxi 22)

The info panel winchat draws against its chat log: the time, the zone, EXP and the weather, and
optionally the map grid. Weather and the map grid are read even when the game's own clock is not drawn.
The last weather read is kept while it cannot be read for a moment; zoning and changing character clear
it.

Some words in the panel have a tooltip:

- over the time, day, date and moon, the Vana'diel month as a calendar;
- over the zone name, the ships' and airships' timetable: the next four to leave, of the lines chosen.

The panel also knows the zone's weather odds as the server rolls them.

The panel sits flush against the chat log by default. It does not change the chat window's position or
size, and the game's menus are not moved.

Custom icon sets live in `icons/<set>/days` and `icons/<set>/weather`, using the filenames in the
bundled `gems` set: the eight days, the eight elements, and `clear`, `clouds` and `fog` for the skies the game
draws no icon for.

See [winchat](../../../winchat/README.md#optional-info-panel) for controls, data fields and migration.
