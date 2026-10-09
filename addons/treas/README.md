# treas

The treasure pool in a window, with buttons to cast lots and pass, on one item or all of them. It was
the `treas` tool of xitools and is now an addon of its own, needing only the `winxi` library
(`addons/libs/winxi`).

- `/treas` shows or hides the window (it only appears while there is treasure in the pool)
- `/treas config` opens or closes the settings
- `/treas focus` gives the window the controller, or takes it away again

With a controller (Controller Navigation, in the settings): the window is up whenever there is treasure,
so it does not take the controller until `/treas focus` gives it (put that in a macro). Then up and down
move the highlight, A lots or passes on the highlighted item, Y (triangle) lots or passes on everything,
and B gives the controller back to the game.

X (square) is the window cycle, and another way in: it moves the controller between whichever winxi
windows are open, the inventory (the `inv` addon) first, then the treasure pool, and round again. While
a winxi window is open the game does not get X, except in a menu of its own.

The first time it is loaded for a character it brings over what xitools kept for the tool: its settings,
the window's place, and xitools' theme and hiding rules.
