# Changelog

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
