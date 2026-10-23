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

## Screen

Menu Scale (0.75 to 2) draws every framed window of the game's that much larger, each from its corner of
the screen so they keep their places to each other: the bar across the top from its ends, the menus over the chat
log from the log's top left. The chat log and the target's arrow stay as they are. `/uihook native size`.

Bring Sides In makes the bar across the top that many pixels shorter at each end, staying centred, and moves
every window on either half of the screen in as far: the title box, the network box, the main menu and the rest
keep their size and their places next to each other and to the bar. A window over the middle of the screen
(a centred question) stays put, as do the chat log and the menus stacked on it. `/uihook native inset`; only
the drawing moves, as above.

Needs uihook 1.47 or newer and the `winxi` library.
