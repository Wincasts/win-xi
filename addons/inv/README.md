# inv

The bags in a window: what is in them, and what can be done with it, by mouse or controller. It was the
`inv` tool of xitools and is now an addon of its own, needing only the `winxi` library (`addons/libs/winxi`).

- `/inv` shows or hides the window
- `/inv config` opens or closes the settings
- `/inv focus` gives the open window the controller, or takes it away again

With the mouse, right-click an item for what can be done with it. With a controller (Controller
Navigation, in the settings): the d-pad moves the highlight, LB / RB change tab, A opens the item's menu,
B backs out of a menu or gives the controller back to the game, and X (square) opens the sort menu. The
window takes the controller as `/inv` opens it, and only `/inv` closes it.

While there is treasure, the treasure pool sits under the window, as wide as it: a line for each item
with the best lot so far, the time left, and buttons to lot and pass, with Lot All and Pass All over
them. Hover over an item for who is winning it. It comes and goes with the inventory window; Detach
From Inventory, under Treasure Pool in the settings, makes it a window of its own that can be moved and
is there whenever there is treasure. It is worked with the mouse only, where the `treas` addon can be
worked with a controller.

The first time it is loaded for a character it brings over what xitools kept for the tool: its settings,
the window's place, the order items were put in by hand, and xitools' theme and hiding rules.
