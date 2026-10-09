# inv

The bags in a window: what is in them, and what can be done with it, by mouse or controller. It was the
`inv` tool of xitools and is now an addon of its own, needing only the `winxi` library (`addons/libs/winxi`).

- `/inv` shows or hides the window
- `/inv config` opens or closes the settings
- `/inv focus` gives the open window the controller, or takes it away again

With the mouse, right-click an item for what can be done with it. With a controller (Controller
Navigation, in the settings): the d-pad moves the highlight, LB / RB change tab, A opens the item's menu,
B backs out of a menu or gives the controller back to the game, and Y (triangle) opens the sort menu.
The window takes the controller as `/inv` opens it, and only `/inv` closes it.

X (square) is the window cycle, through whichever winxi windows are open. The game's X steps through its
own windows: the chat windows, then the status icons. One more press from the status icons gives the
inventory the controller; the next passes it to the treasure pool (the `treas` addon, where there is
treasure); the next goes back to the game. Nothing is opened or closed by it.

The first time it is loaded for a character it brings over what xitools kept for the tool: its settings,
the window's place, the order items were put in by hand, and xitools' theme and hiding rules.
