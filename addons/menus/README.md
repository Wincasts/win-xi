# menus

Draws the game's menus in the winxi look. The game's own menus stay open and do everything they
do: the controller moves their cursor, Confirm and Cancel are theirs, and what they list is what the
game lists. The `uihook` plugin leaves them undrawn and says what they would have drawn, and menus
draws them again in the theme, each piece where the game put it: the window as a winxi panel, its
text in the theme's font (an item's name in the colour the game gives it), its icons from the game's
own textures, the row the cursor is on lit in the Highlight Color, the game's hand where the game put
it, and the scrollbar.

Needs `uihook` 0.96 or newer (its menu mirror) and winxi 33.

- `/menus` opens or closes the settings

This is the first step. It mirrors the item lists and the item description box; the game's other
menus are drawn by the game as ever. Everything is placed where the game placed it, so the game's
hit-tests still line up with what is seen; the mouse is not yet looked at.

## Settings

Every section collapses with its [-]/[+].

**Menus**: which of the game's windows are mirrored: Inventory, Item Info, Mog Safe, Shop. Off, the
game draws its own.

**Mirror**
- Mirror Mode: Replace leaves the game's menus undrawn and draws them again. Outline leaves them as
  the game draws them, and outlines over them what uihook measured: the window (yellow), each piece of
  text (green), each icon (blue), the cursor (red), the row highlight (pink) and the scrollbar
  (white). For checking what is measured before replacing.
- Menu Scale (0.75x to 2x): how large the menus are drawn in Replace, each grown from the corner of the
  screen it is nearest (the item lists from the top left, the item box from the bottom left), so it
  stays on the screen. Its text is drawn larger, not stretched. The controller works as ever; the mouse
  still clicks where the game's own menu is, so at any scale but 1 it does not line up yet.
- Status: what uihook says of the mirror, and any menu given back to the game, and why.

## When the game's own comes back

Whatever goes wrong, the menu is never left unseen: a window whose place could not be measured is the
game's to draw for two seconds, an error in drawing gives every menu back to the game for ten (said
once in the chat log), and uihook draws a window itself again four frames after menus last asked,
so unloading menus or uihook gives the game's menus back.
