# inventory

The bags in a window: what is in them, and what can be done with it, by mouse or controller. It was the
`inv` tool of xitools and is now an addon of its own, needing only the `winxi` library (`addons/libs/winxi`).

- `/inventory` shows or hides the window
- `/inventory config` opens or closes the settings
- `/inventory focus` gives the open window the controller, or takes it away again

`/inv` is the same command, shorter: `/inv`, `/inv config` and `/inv focus` all work.

With the mouse, right-click an item for what can be done with it. With a controller (Controller
Navigation, in the settings): the d-pad moves the highlight, LB / RB change tab, A opens the item's menu,
B backs out of a menu or gives the controller back to the game, and X (square) opens the sort menu. The
window takes the controller as `/inv` opens it, and only `/inv` closes it.

While there is treasure, the treasure pool sits to the right of the window: a line for each item with
the best lot so far, the time left, and buttons to lot and pass, with Lot All and Pass All over them.
Hover over an item for who is winning it. It comes and goes with the inventory window; Detach From
Inventory, under Treasure Pool in the settings, makes it a window of its own that can be moved and is
there whenever there is treasure. Show When Empty fills an empty pool with sample treasure, to see how
it looks; its buttons do nothing. It is worked with the mouse only, where the `treas` addon can be
worked with a controller.

The addon was called `inv`; the first time it is loaded for a character it brings over the settings it
kept under that name. If there are none, it brings over what xitools kept for the tool: its settings,
the window's place, the order items were put in by hand, and xitools' theme and hiding rules.
