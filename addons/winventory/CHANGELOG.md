# Changelog

## 1.2

- Renamed winventory: the addon is `winventory` (`addons\winventory`, `/addon load winventory`), its settings window winventory Settings and its command `/winventory`, with `/inventory` and `/inv` kept as other ways in. Each character's settings are brought over the first time it logs in, from `config\addons\inventory` where it has them, otherwise from `config\addons\inv` (winxi.shell's formerName, now a list). Remove the old `addons\inventory` folder.
- `/winventory help` lists the commands. `/winventory config` is gone: `/winventory` alone opens the settings, and any other word after it only says so. `toggle` and `focus` are as they were.
- The treasure pool's Lot and Pass buttons no longer have their labels made afresh each frame.

## 1.1

- The controller's highlight, on an item, an equipment slot or a treasure pool button, is winxi's selection box (winxi 73): the Selection Style and Selection Color set in winxisettings → Styles for every addon, Bevel in a pale gold to begin with (Outline is the old look, in the new colour; Glow, Glass, Satin and Brushed Metal too). Requires winxi 73.
- Controller Legend (General → Controller, on to begin with): while the window has the controller, a line or two under it (or under the attached equipment monitor) says which buttons do what, in a word each (Move, Tab, Menu, Sort, Next, Exit; Select and Back in the treasure pool; Gear in the equipment monitor; Swap and Done while sorting by hand), each button a small glyph drawn as it looks on the controller in use (PlayStation's cross, circle, square and triangle in their colours, an Xbox controller's coloured letters, pills for L1 / R1 or LB / RB, a cross for the d-pad), in the theme's font and size: winxi 72's legend, as every winxi window worked with a controller has. The verbose item box below the window goes under it. Requires winxi 72.
- Y (triangle) cycles the controller through the windows: the inventory, the treasure pool while there is treasure, and the equipment monitor while it is shown, the one that has it outlined. The treasure pool can be worked with the controller: the highlight starts on the first item's Lot, left and right go between Lot and Pass, up and down between the items, up from the first to Lot All and Pass All, and A presses the button. So can the equipment monitor: the d-pad over the slots, A for Remove and the gear in the inventory and wardrobes that goes there and that the main job can wear at its level (up to 15, highest level first). B goes back to the inventory. Cycle Treasure Pool and Cycle Equipment (General → Controller, on to begin with) leave either out. Requires winxi 69.
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
