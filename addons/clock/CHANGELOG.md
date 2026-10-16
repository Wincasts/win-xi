# Changelog

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
