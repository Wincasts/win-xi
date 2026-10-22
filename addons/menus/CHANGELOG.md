# Changelog

## 0.3

- More menus, in groups: Lists (Abilities And Spells, Emotes, Mounts, Currencies, Missions, Quests,
  Quest Pages, Friend List, Area List, Search Results, Help Desk), on to start; Status (Status, Level
  And EXP, Profile, Job Levels, Combat Skills, Crafting Skills, Gil) and Config (Chat Filters, Battle
  Message Filters, Chat Colors), off to start, to be looked at in Outline first.
- Keep Mouse From Game Menus: the game given no mouse over a mirrored menu or its own place under it,
  a kept press's release kept too; with it on, menus are dragged to where they are wanted (Lock Menu
  Positions, Reset Positions), each kept on the screen and saved as an offset from the game's place.
- Needs uihook 0.97 (mirror ABI 2: 32 windows asked for, 16 published a frame) and winxi 34.
- tests/menus_check.lua (through tests/menus_stand_in.lua): what is asked, the mouse kept and given,
  dragging, the lock, the screen's edge, the fallback and Outline.

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
