# inventory

The bags in a window: what is in them, and what can be done with it, by mouse or controller. It was the
`inv` tool of xitools and is now an addon of its own, needing only the `winxi` library (`addons/libs/winxi`).

- `/inventory` opens or closes the settings (`/inventory config` does the same)
- `/inventory toggle` shows or hides the window
- `/inventory focus` gives the open window the controller, or takes it away again

`/inv` is the same command, shorter: `/inv`, `/inv toggle` and `/inv focus` all work.

**Lock Drag to Move**, at the top of settings, prevents dragging the inventory window when enabled.
It is off by default; the **Position** fields remain usable while locked.

Under **Bags** in the settings, **Rows** and **Columns** set the inventory grid's visible size
(1–30 each). While settings are open, empty placeholders preview the full selected grid; changes to
rows and columns update that preview immediately. With settings closed, the grid collapses to fit the
bag content (including empty bag slots when Show Empty Slots is enabled), up to the selected row
limit. Extra items scroll, leaving the tabs and slot counts visible. The grid has no separate
background, so the base Winxi window shows through. These controls replace Max Height. **Show Bag/Satchel/Wardrobe/House Tab** toggles each group on or off;
controller tab navigation skips hidden groups. Hiding a tab does not change its items or prevent
moving items to those bags. The controls apply to both unified and separate-bag views.

With the mouse, right-click an item for what can be done with it. With a controller (Controller
Navigation, in the settings): the d-pad moves the highlight, LB / RB change tab, A opens the item's menu,
B backs out of a menu or gives the controller back to the game, and X (square) opens the sort menu. The
window takes the controller as `/inv toggle` opens it, and only `/inv toggle` closes it.

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
