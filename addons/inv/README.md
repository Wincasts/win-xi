# inv

The bags in a window: what is in them, and what can be done with it, by mouse or controller. It was the
`inv` tool of xitools and is now an addon of its own, needing only the `winxi` library (`addons/libs/winxi`).

- `/inv` shows or hides the window
- `/inv config` opens or closes the settings
- `/inv focus` gives the open window the controller, or takes it away again
- `/winxi inv` is the one for a macro: it opens the window; if it is open already without the controller,
  gives it the controller; if it has the controller, closes it. `/winxi` alone moves the controller to the
  next open winxi window, as X does.

With the mouse, right-click an item for what can be done with it. With a controller (Controller
Navigation, in the settings): the d-pad moves the highlight, LB / RB change tab, A opens the item's menu,
B backs out of a menu or gives the controller back to the game, and Y (triangle) opens the sort menu.
The window takes the controller as `/inv` opens it, and only `/inv` closes it.

X (square) is the window cycle: it moves the controller between whichever winxi windows are open, the
inventory first, then the treasure pool (the `treas` addon, where there is treasure), and round again.
Nothing is opened or closed by it. While a winxi window is open the game does not get X, except in a
menu of its own; with none open X is the game's as ever.

The first time it is loaded for a character it brings over what xitools kept for the tool: its settings,
the window's place, the order items were put in by hand, and xitools' theme and hiding rules.
