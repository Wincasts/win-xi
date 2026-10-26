# Changelog

## 0.1.1

- Requires winxi 55: winxi.popups lets go of namehook's popup block when namehook has been unloaded and loaded again since it was found, at another address or as another build, and never writes to the old one.

## 0.1

- The game's damage popups, read from namehook 1.38 through winxi.popups, are claimed and drawn in the
  theme's font with its text outline, centred on the game's point, in the game's colour (its alpha, with
  0x80 for full, doubled), 26 pixels tall at the game's full size for the popup. One for each hit: the
  darker copy the game makes of each is left out, and a miss (the game's ":") says "Miss!".
  `/damage on|off`. tests/damage_check: the blocks' layout, one drawing for each hit, its letters, place,
  size and colour, the claim renewed with the names' frame, given up when off and on unload.
