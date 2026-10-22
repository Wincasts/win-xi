# Changelog

## 0.6

- Window titles: the game writes a menu's title ("Commands") in serif letters, one element each; they
  are read back and set on the panel's top edge as a winxi title, in the theme's Title Style, font and
  colour, the border broken behind it where the style breaks. Every mirrored menu that has one gets
  it, the item lists too.
- A smaller settings window: Mirror and Mouse first; the groups of menus collapsed to start, each with
  an All checkbox and its menus three to a row rather than one a line.
- Menu Name and Top Bar in the Picture Label Menus: the box at the top left with the open menu's name
  ("Items", `titlewin`) and the bar across the top with its help line ("Select an item.", `helpwind`)
  and its title ("Help"), in the theme's font. The game writes them a cell a letter from its text font,
  a grid read by its cells (winxi 39); words spelled in any mirrored window's contents are read and
  drawn so, not only in the Picture Label Menus.
- Needs winxi 39 (uihook 1.0).

## 0.5.1

- With 32 or more menus on, nothing was replaced: the mirror took 32 requests, and the hidden bit of the
  32nd came out as no bits at all, so every menu was the game's and none drawn here. Every menu (40)
  can now be on. Needs uihook 1.0 and winxi 37.

## 0.5

- The Picture Label Menus' words in the theme's font. The game spells those labels one letter at a time,
  each letter an element cut from its menu font; winxi 36 reads the letters back into words (a table of
  where each letter sits in the font, taken from the game's own sheet with uihook 0.99's
  `/uihook mirror labels`), leaving out the faint shadow the game draws under each. Anything that is not
  a letter of that font (the button bars, a title in another font) is still the game's art.
- Needs winxi 36 (uihook 0.98 or newer).

## 0.4

- [Experimental] Picture Label Menus, off to start: the Main Menu, Command Menu, Magic and Ability
  Categories, Status Menu, Config Menu, Mog House Menu and Options, Item Sort, Macro Menu, Mission Menu,
  Friend List Menu, Communication Menu, Unity Menu and Bazaar Menu, whose words are pictures. Each is a
  winxi panel with the game's own label art (uihook 0.98's Element quads), the cursor's row lit from
  the element the game tints, and the hand. Outline draws elements in purple.
- Needs uihook 0.98 and winxi 35.

## 0.3.1

- Dragging works with Keep Mouse From Game Menus: the mouse's place is read from Windows (the cursor in
  the game window's client area, scaled to imgui's display), not imgui's MousePos, which is fed by the
  moves kept from the game and stopped where the first kept move was. The settings window keeps its
  presses by its own place as last drawn, not imgui's WantCaptureMouse, which went stale the same way
  and handed every press on a menu back as imgui's.

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
