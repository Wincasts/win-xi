# Changelog

## 0.7

- Looks at uihook, the theme's fonts and its own settings twice a second, not every frame: each frame it made its
  commands again to compare them. A setting changed in the window is given at once.

## 0.6

- Menu Weight and Title Weight (As The Font, Regular, Bold; the menu font Bold to begin with, as a regular one's
  strokes are a pixel wide at a menu's size), and the winxi theme's Text Outline and its colour, given to uihook 1.54
  with each font chosen.

## 0.5

- Fonts: Menu Font and Title Font, each Follow Winxi Theme (the theme's Font and Title Font, changing with them),
  Skin's Own, or any font of C:\\Windows\\Fonts, drawn by uihook 1.52 into the skin's fonts as it loads
  (`/uihook skin font`).

## 0.4

- Screen (was Sides): Menu Scale, 0.75 to 2, every framed window of the game's drawn that much larger, each from
  its quarter's corner of the screen, the bar from its ends and the menus over the chat log from its top left
  (uihook 1.47's `/uihook native size`). Bring Sides In with it.

## 0.3

- uihook unloaded and loaded again is given the skin, the menus' offset and the sides again: it had none of them
  until the game was started again.

## 0.2

- Sides: Bring Sides In, the bar across the top shorter at each end by as many pixels, staying centred, and every
  window on either half of the screen moved in with it at its size (uihook 1.40's `/uihook native inset`). The
  chat log and the menus stacked on it stay put.

## 0.1

- Skin: a folder of `config\uihook\skins` chosen in the settings, loaded with `/uihook skin` each time the game
  starts; None for the game's own; Reload.
- Menus Over The Chat Log: Move Right and Move Down for every window the game stacks there (uihook 1.38's
  `/uihook native group`), together; Reset. Their drawing alone: the mouse clicks where the game put them.
