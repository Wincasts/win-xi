# Changelog

## 0.2

- Menu Scale: the mirrored menus drawn from 0.75x to 2x, each about the corner of the screen it is
  nearest, its text larger rather than stretched. The mouse is not yet mapped to the scaled menus.
- The cursor's row is found from the game's cursor, the game's row highlight used only where it is the
  shape of a row (in the item lists it covers the whole window, which lit the whole panel); the hand is
  drawn at its art's shape, a row tall, where the game drew its cursor.

## 0.1

- The first: the item lists (Inventory, Mog Safe, Shop) and the item description box mirrored through
  uihook 0.96's menu mirror (winxi.nativemirror). The game's windows keep working and are left undrawn;
  each is drawn again as a winxi panel with its text in the theme's font where the game printed it, its
  icons from the game's textures, the cursor's row lit, the game's hand and the scrollbar. Mirror Mode
  Outline leaves the game's drawing and outlines what is measured instead.
