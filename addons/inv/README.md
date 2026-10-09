# inv

The bags in a window: what is in them, and what can be done with it, by mouse or controller. It was the
`inv` tool of xitools and is now an addon of its own, needing only the `winxi` library (`addons/libs/winxi`).

- `/inv` shows or hides the window
- `/inv config` opens or closes the settings

With the mouse, right-click an item for what can be done with it. With a controller (Controller
Navigation, in the settings): the d-pad moves the highlight, LB / RB change tab, A opens the item's menu,
B backs out or closes the window, and Y (triangle) opens the sort menu.

X (square) is the window cycle. The game's X steps through its own windows: the chat windows, then the
status icons. One more press from the status icons opens the inventory and gives it the controller; the
next passes it to the treasure pool (the `treas` addon, where there is treasure); the next goes back to
the game.

The first time it is loaded for a character it brings over what xitools kept for the tool: its settings,
the window's place, the order items were put in by hand, and xitools' theme and hiding rules.
