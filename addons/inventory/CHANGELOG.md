# Changelog

## 1.1

- Y (triangle) cycles the controller through the windows: the inventory, the treasure pool while there is treasure, and the equipment monitor while it is shown, the one that has it outlined. The treasure pool can be worked with the controller: the d-pad over the items, A for Lot, Pass, Lot All and Pass All. So can the equipment monitor: the d-pad over the slots, A for Remove and the gear in the inventory and wardrobes that goes there and that the main job can wear at its level (up to 15, highest level first). B goes back to the inventory. Cycle Treasure Pool and Cycle Equipment (General → Controller, on to begin with) leave either out. Requires winxi 69.
- Controller Type is Automatic to begin with (winxi 68): the kind of controller the game reads, as the Phoenix launcher sets it, a DirectInput controller taken for a PlayStation one. A Controller Type saved as XInput becomes Automatic once (XInput still where the game reads XInput). Requires winxi 68.
- General → Window has a Growth Anchor setting: while locked, the inventory keeps the chosen corner fixed as tabs or grid settings change its size. Top Left (the default), Top Right, Bottom Left and Bottom Right are available.

- An item's highlight and the controller's marks are clipped on the screen (winxi.clip, so winxi 50 is needed): with the window at the screen's edge their clip reached off it, where Direct3D 8 can stretch what is in a clip over the whole screen.

- The tab names start with a capital letter: Bag, Satchel, Ward and House, and the bags' own tabs under the grid (All, Case, Safe 1).

- The item, treasure and equipment tooltips are drawn by winxi.tooltip, as the settings' are, so winxisettings' Tooltips tab applies to them. Lock, the inventory window's and the monitor's, is winxi's own control (widgets.Lock) and holds the window through winxi.window.

## 1.0 — first release

- Your bags in a window, one at a time or all together, by mouse or controller (experimental).
- Drag to sort, and an order of your own that is kept.
- Two currencies where the gil is shown, from Phoenix's or every currency.
- The treasure pool beside the window or on its own, and an equipment monitor.
