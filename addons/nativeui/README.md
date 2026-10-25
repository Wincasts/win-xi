# nativeui

Settings for the game's own interface as uihook changes it: which skin its menus are drawn with, and where the
menus it stacks over the chat log go. It keeps them for each character and gives them to uihook each time the
game starts.

- `/nativeui`: opens or closes the settings

## Skin

A folder of `config\uihook\skins\`, as `tools/uihook_skin.py` makes them (`--style winxi` for the winxi theme's
look), loaded with `/uihook skin`. None draws the game's own. Reload reads the skin's pictures again after they
are changed.

## Menus Over The Chat Log

The game stacks a family of windows in the bottom left with their bottom on the chat log's top: the command
menu, a shop's buy and sell, yes-or-no questions, an item's description, and some fifty more. Move Right and
Move Down draw them all that many pixels from where the game puts them, together, kept on the screen
(`/uihook native group`). Only their drawing moves: the controller works them as ever, but the mouse clicks
where the game put them.

[Experimental] Drawn As (The Game to begin with), needing uihook 1.59:

- **Winxi Frames**: their frames, the game's corners, edges and striped background, drawn by uihook as a panel in
  the theme's Background Color, its border in Border Color at Border Opacity, the corners rounded as a winxi
  window's. Their words, pictures, buttons and hand are the game's, drawn over it (`/uihook native frames`).
- **Winxi**: each drawn again whole in the winxi look from uihook's mirror of them (`groupmirror.lua`,
  `groupdraw.lua`): a winxi frame with the window's title on its edge, its words in the theme's font (the command
  menu's pictured words read back from the game's letters), its icons and buttons the game's art, the row the cursor
  is on lit in the Highlight Color, the game's hand, the scrollbar. The game's own stays open unseen underneath, so
  the controller works it as ever and the mouse clicks it where it is drawn (with Move Right, Move Down or Menu
  Scale, while Mouse Follows Menus is on). One whose text cannot all be placed is left to the game for a couple of
  seconds and taken again once it measures whole; the settings say which.

Both follow the theme as it changes.

## Fonts

Menu Font (the menus' words: commands, lists, buttons) and Title Font (the windows' titles, the jobs' and races'
names): Follow Winxi Theme draws them in the theme's Font and Title Font, and changes with it; Skin's Own keeps the
skin's pictures as they were made; any other is that font of `C:\Windows\Fonts`. uihook draws each glyph in the font
where the game's goes, at every size of the skin, as the skin loads (`/uihook skin font`); the skin needs a
`fonts.txt`, as `tools/uihook_skin.py --style winxi` makes. A font chosen is drawn in winxi's look: smoothed, with
the theme's Text Outline about its letters and no game shadow. Menu Weight and Title Weight draw it Regular or Bold
(the menu font Bold to begin with: at a menu's size a regular font's strokes are a pixel wide), or as the font is.

## Screen

Menu Scale (0.75 to 2) draws every framed window of the game's that much larger, each from its corner of
the screen so they keep their places to each other: the bar across the top from its ends, the menus over the chat
log from the log's top left. The chat log and the target's arrow stay as they are. `/uihook native size`.

Bring Sides In makes the bar across the top that many pixels shorter at each end, staying centred, and moves
every window on either half of the screen in as far: the title box, the network box, the main menu and the rest
keep their size and their places next to each other and to the bar. A window over the middle of the screen
(a centred question) stays put, as do the chat log and the menus stacked on it. `/uihook native inset`; only
the drawing moves, as above.

[Experimental] Mouse Follows Menus (off to begin with) gives the game's mouse each window where it is drawn,
moved or larger: pointing and clicking go to the same place on the game's own window, and where the game puts a
window drawn elsewhere, with nothing drawn there, the game is given no mouse (`/uihook native mouse`). The wheel
is the game's, where its own cursor is.

Needs uihook 1.58 or newer for Mouse Follows Menus, 1.54 for the rest, and the `winxi` library.
