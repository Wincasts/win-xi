# Changelog

## 0.7.1

- The line begins four pixels clear of the day icon as drawn, the set's scaled and moved or the
  game's, and never left of the game's text.
- `{exp}` is the numbers alone, `12,345/30,000`.

## 0.7.0

- The line is a string you write: `{field}` for each field and anything else as it is, the dividers;
  Add Field, Add Divider and Default build it. A field with nothing to write takes its divider away.
  0.3 to 0.6's ticked, ordered list is brought over as a line.
- Experience is counted while an experience field (`{level}`, `{exp}`, `{tnl}`, `{rate}`) is in the
  line: no switch of its own. `{rate}` is always the last hour's: Rate Over is gone.
- Icon Offset: the set's icons moved up or down, -10 to 10 pixels.
- gems: the days closer to the game's own circles, in their sampled colours, marbled, at their size.

## 0.6.0

- Weather Icon: a field for the Icon Set's weather picture in the line, put in order like the rest;
  the game's own above is hidden while it is there, and stays where the set has no picture.
- Icon Scale (0.5x to 3x) for the set's icons, at the game's places and in the line.
- Experience, a module turned on under Experience: Level, EXP (or limit points to the next merit),
  EXP To Level and EXP Per Hour fields, counted from the server's gain messages, the rate over the
  last Rate Over minutes; Begin Again and `/clock exp reset`.

## 0.5.0

- The **gems** icon set: round cut gemstones for the days, and weather icons after the game's, with
  a sun for a clear sky (`tools/generate_clock_icons.py`).
- Skies the game draws no icon for (no weather, sunshine, clouds, fog) can have a set's picture,
  `clear`, `clouds` or `fog`, where the game's weather icon would be.

## 0.4.0

- Icon Set: pictures of your own for the day and weather icons, a folder of `icons` each, drawn where
  and as large as the game's. Where a set has no picture, the game's own icon (from its DATs) is drawn.
- Needs uihook 0.2 with HUD ABI 4.

## 0.3.0

- The line's fields are chosen and put in order under Line in the settings: Time, Map Grid, Day,
  Date, Moon and Weather (by name, hidden to begin with), each ticked and moved with Up and Down.
- Fields are one entry each in `fields.lua` (from `display.lua`); a new one reaches every character's
  settings at the end of their line.

## 0.2.0

- One line in place of the game's clock text: time, map grid (the game's own), day, date and moon.
- The game's day and weather icons kept where it draws them; only its text gives way (uihook's
  text call). The line sits exactly where the game writes its text.
- No background; winxi's outlined text in the theme's font and colour.
- Settings (`/clock`): Replace Game's Clock, Text Scale (0.5x to 3x) and Hide Compass (on to begin with).
- `/clock pos` is gone: the line is always on the game's clock. 0.1's settings are brought over.
- Needs uihook 0.2 with HUD ABI 3.

## 0.1.0

- Initial basic clock-only replacement through uihook 0.2 / HUD ABI 2 and winxi 5.
- Vana'diel time, weekday/date, moon illumination and optional native weather ID/name.
- Drawn on the game's own clock by default (`/clock pos native`), or a saved screen position; no compass replacement UI.
- Offline discovery, ABI, scope, bridge and presentation tests. Live rendering validation pending.
