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

Needs uihook 1.38 or newer and the `winxi` library.
