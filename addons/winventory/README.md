# winventory

Displays all of your bags in a single window, with full mouse and controller support. It also
includes the treasure pool and an equipment monitor.

## Highlights

- Browse every bag through tabs, and move items between bags by dragging them.
- Lot or pass on treasure and change your equipment from the same window.
- Full controller support, with an on-screen guide to each button.

It needs only the `winxi` library (`addons/libs/winxi`). It started as the `inv` tool of xitools, then
became the `inventory` addon, and is now winventory.

## Install

The download is listed in [DOWNLOADS.md](../../DOWNLOADS.md). Extract it into your Ashita folder (the
one that holds `addons`, `plugins` and `config`). Then, in game, type:

    /addon load winventory

### Coming from inventory, inv or xitools

- Each character's settings are brought over the first time it logs in with winventory. They come from
  `config/addons/inventory/` if it has them, otherwise from `config/addons/inv/`.
- Remove the old `addons/inventory` folder.
- The addon was once called `inv`. The first time it is loaded for a character, it brings over the
  settings kept under that name. If there are none, it brings over what xitools kept for its tool:
  the settings, the window's place, the order you put items in by hand, and xitools' theme and hiding
  rules.

## Commands

- `/winventory` opens or closes the settings.
- `/winventory toggle` shows or hides the window. Put it in a macro to open the window with a
  controller.
- `/winventory focus` gives the open window the controller, or gives it back to the game.
- `/winventory help` lists the commands in the chat log.

`/inventory` and `/inv` still work the same as `/winventory`, and so do `/inv toggle` and
`/inv focus`. Anything else after the command only says how to open the settings.

## Using the window

### With the mouse

- Right-click an item to see what you can do with it.
- Rest the mouse on an item to see its details.

### Moving items

Items can be dragged with the mouse while the window is locked (**Lock**, see
[Window settings](#window-settings)). When it is unlocked, dragging moves the window instead.

- Drop an item on another item in the same tab to swap their places. This makes your own order, as the
  controller's Manual sort does. Auto sort puts the usual order back.
- Drop an item on another tab's name at the top to move it into that tab's bags. It goes into the bag
  chosen along the bottom of the window if that has room. If not, it goes into the first bag that has
  room and can take it. Wardrobes take only gear. You cannot move items into your Mog House bags from
  elsewhere.

### With a controller

Turn on **Controller Navigation** in the settings (General → Controller). Then:

| Button | What it does |
|---|---|
| D-pad | Moves the highlight. |
| LB / RB | Change tab. |
| A | Opens the item's menu. |
| B | Backs out of a menu, or gives the controller back to the game. |
| X (square) | Opens the sort menu. |
| Y (triangle) | Moves the controller on to the next window. |

The window takes the controller when `/winventory toggle` opens it. Only `/winventory toggle` closes it.

**Y** moves the controller from window to window: the inventory, then the treasure pool (only while
there is treasure), then the equipment monitor (only while it is shown), then back to the inventory.
The window that has the controller has a thin outline. To leave a window out of this cycle, turn off
**Cycle Treasure Pool** or **Cycle Equipment** (General → Controller).

- **In the treasure pool**: the highlight starts on the first item's **Lot**. Left and right move
  between Lot and Pass. Up and down move between items. Up from the first item reaches **Lot All** and
  **Pass All**. A presses the button the highlight is on.
- **In the equipment monitor**: the d-pad moves over the slots. A opens what you can put on in that
  slot: **Remove** for what you are wearing, then the gear in your inventory and wardrobes that fits
  the slot and that your main job can wear at its level, highest level first (up to 15).
- **B** in either one goes back to the inventory.

While the window has the controller, a legend under it shows which buttons do what at that moment:
in the inventory, the treasure pool, the equipment monitor, a menu, or while sorting by hand. Each
button looks as it does on your controller: the cross, circle, square and triangle in their colours on
a PlayStation controller, coloured letters on an Xbox one, L1 / R1 or LB / RB as small rounded labels,
and a cross shape for the d-pad. Turn off **Controller Legend** (General → Controller) to hide it. The
detailed item box, placed below the window, goes under the legend.

## Treasure pool

While there is treasure, the treasure pool shows to the right of the window.

- Each item has a line with the best lot so far, the time left, and buttons to lot and pass. **Lot
  All** and **Pass All** are above them.
- Rest the mouse on an item, or highlight it with the controller, to see all its details, as for an
  item in your bags, and who is winning it.
- It shows and hides with the inventory window.
- **Detach From Inventory** (Treasure → Treasure Pool) makes it a window of its own that you can move,
  with its own **Position** and **Lock**.
- **Show When Empty** fills an empty pool with sample treasure, so you can see how it looks. Its
  buttons do nothing.
- With a controller, **Y** takes you to it (see [With a controller](#with-a-controller)).

## Equipment monitor

Turn on **Enable** in `/winventory` → **Equipment** to get a window that shows the gear you are
wearing, like the EquipMon addon. It is off by default. It does not need EquipMon or its files. While
it is off, the rest of its settings are hidden.

### Where it goes

- The monitor is a window of its own, with the theme's shadow, as every winxi window has.
- The first time it shows, it goes under the inventory window, lined up with its left edge. After
  that, it stays where you put it: drag it, or set its **Position**. **Lock** holds it in place.
- It shows, hides and fades with the inventory, unless it is pinned (see [Pinning](#pinning)).
- Before 1.2 it could be attached under the inventory. A monitor that was attached is put there once,
  and is free after that.

### The slots

All 16 slots are laid out as on the game's equipment screen:

| | | | |
|---|---|---|---|
| Main | Sub | Range | Ammo |
| Head | Neck | Left Ear | Right Ear |
| Body | Hands | Left Ring | Right Ring |
| Back | Waist | Legs | Feet |

- Worn items are found in the bag they are really in, wardrobes included, and update as you change
  gear.
- A gear or ammo change shows as soon as the game has updated. Very fast swaps that happen between two
  screen updates cannot all be shown.
- Rest the mouse on a slot to see its name and the item in it. Hovering over a worn item shows which
  bag it is in, even when Wardrobe Markers is off.
- Stackable ammunition shows how many are left.
- Red crosses mark slots you cannot use (encumbered), even when empty.
- You can turn each of these off on its own: **Show Ammo Count** and **Show Encumbrance**.

### How the slots look

These are under **Equipment → Slots**.

- **Quality Borders** (on by default) draws a white border inside the edge of high-quality (HQ) gear,
  as the game does. Other gear has no border. The game's item data does not say which items are HQ (an
  HQ item is a separate item, named with +1, +2 or +3). So an item counts as HQ when its name ends that
  way.
- **Wardrobe Markers** (on by default) marks gear kept in a wardrobe, as the game's equipment menu
  does. The wardrobe's number is in the top-right corner, white with a dark edge, over a strip of the
  wardrobe's colour along the top and right edges. Wardrobes 1–3 use the game's blue, yellow and
  green. Wardrobes 4–8 use red, purple, teal, orange and pink. Items in your main inventory have no
  mark.
- Quality Borders and Wardrobe Markers work separately from each other and from Slot Backgrounds.
- **Slot Backgrounds** draws each slot as the game's equipment menu does. Each slot is a flat
  lavender-grey square, set into the window: its top and left edges are shaded and its right and
  bottom edges are lit, inside a thin dark rim. The slot's name is in pale letters in the middle.
  Empty slots keep their names. Full slots show the item's icon on top. The background and names grow
  and shrink with the icons, and turn off together with Slot Backgrounds.

### Other equipment settings

The Equipment tab has its own **Scale**, **Spacing**, **Opacity**, **Window Background** and **Slot
Backgrounds** settings, and **Position** and **Lock**. Drag the unlocked window to move it. The
settings are saved for each character with the rest of winventory's settings. The look and the count
text use the Winxi theme, not EquipMon's themes and fonts.

## Pinning

`/winventory toggle` shows and hides the inventory window, the treasure pool and the equipment monitor
together. Each has a pin that keeps it on screen when the others are hidden:

- **Pin Inventory** (General → Window). A pinned inventory window stays when you toggle it off, but
  gives the controller back to the game.
- **Pin Treasure Pool** (Treasure). With the inventory hidden, a pinned treasure pool that is attached
  to it moves into the inventory's top-left corner. It goes back beside the inventory when the
  inventory shows again.
- **Pin Equipment** (Equipment). The equipment monitor stays where you put it.

Pinned windows still follow General's shared Visibility rules, including hiding while you are logged
out.

## Settings

The settings are in five tabs, each with sections that fold open and shut:

| Tab | Sections |
|---|---|
| **General** | Window, Controller |
| **Inventory** | Grid, Tabs, Currencies |
| **Treasure** | Treasure Pool, Display |
| **Equipment** | Equipment Monitor, Display, Slots |
| **Tooltips** | Tooltip Window, Display |

Then comes **Visibility**. Every setting's tooltip uses winxi's themed tooltip.

The Treasure and Tooltips tabs are laid out the same way: first the setting that turns it on, then
**Detach From Inventory**, then (when detached) its position and lock, then how it looks. While one is
not turned on, the rest of its tab is hidden.

### Window settings

These are in **General → Window**.

- **Scale** sets the size of the inventory window: its icons, the space between them, and its text.
  The other windows have their own Scale:
  - the treasure pool's (Treasure → Display) and the Tooltip Window's (**Tooltip Scale**, Tooltips → Display) apply only
    while they are detached. While attached, they use the inventory's, so all three match;
  - the equipment monitor's (Equipment → Display) sets its slots, their spacing and its text.
- **Lock** stops you dragging the inventory window. It is off by default. The **Position** fields
  still work while it is locked. While it is locked, you can drag items (see
  [Moving items](#moving-items)).
- **Growth Anchor** chooses which corner stays in place when the locked window changes size (for
  example, when you switch tabs):
  - **Top Left** (the default) grows right and down;
  - **Top Right** grows left and down;
  - **Bottom Left** grows right and up;
  - **Bottom Right** grows left and up.

  Changing the anchor does not move the window. Unlocking goes back to growing from the top left, so
  you can move it freely.

### Grid and tabs

These are in **Inventory → Grid** and **Inventory → Tabs**.

**Rows** and **Columns** set how much of the grid you see: 5–30 rows and 6–30 columns.

- While the settings are open, empty boxes show the full grid you chose. Changes to rows and columns
  show at once.
- With the settings closed, the grid shrinks to fit what is in the bag, up to the row limit you chose.
  This includes empty bag slots when **Show Empty Slots** is on.
- Making the grid bigger or smaller resizes the window to fit.
- These settings replace the old Max Height setting.

Scrolling:

- When there are more items than the row limit, you can scroll with the mouse wheel.
- A thin bar just outside the grid's right edge shows how far down you are. It takes no room from the
  slots, so the window's width stays the same whether the grid scrolls or not.
- You can drag the bar anywhere in the strip between the grid and the window's border. Press on the
  bar to take hold of it. Press elsewhere in the strip to bring the bar to the mouse first. A press
  there never moves the window.

How it looks:

- The window is as wide as the grid. The tabs above, and the gil, counts and bag tabs below, line up
  with the edges of the slots. Tabs and slot counts always show.
- Every slot, full or empty, sits on its own faint square, under the item's icon. The grid has no
  background of its own, so the Winxi window background shows through.

**Show Bag Tab**, **Show Satchel Tab**, **Show Wardrobe Tab** and **Show House Tab** turn each group of
bags on or off. Controller tab changes skip hidden groups. Hiding a tab does not change its items, and
you can still move items into those bags. These settings work in both the combined and the
separate-bag views.

**Unified Bags** combines bags into one tab. In that view, a tab with more than one bag has its own
row of tabs along the bottom of the window:

- **all**, for every bag together;
- then one for each bag you have: satchel, case and sack; the wardrobes by number; safe 1, safe 2,
  storage and locker.

Choosing a bag shows only its items, with its own count in the row above. Auto sort then sorts only
that bag. On **all**, the row has one count for every bag together (35/35, for example), and each
bag's own count is on its tab. A tab with only one bag, such as the inventory's, has no row. These
tabs work with the mouse only.

### Currencies

These are in **Inventory → Currencies**.

The bottom of the window, where gil is shown, can show gil or any currency. It can show a second one
after it, with a short line between them, and another line before the bag count:
`12,345 G | 4,500 IS | 08/30`.

- **Currency 1** is gil by default. **Currency 2** is none by default. Either can be **None**.
- Each is shown with a short name (G, CP, GP, IS, AP, Tokens and so on). The list shows the full names.

**Currency List** picks which currencies the two lists offer. The server does not say which currencies
it has, and its answers include every currency the game knows. So:

- **Retail** offers every currency.
- **Phoenix** (the default) offers gil, the currencies of Phoenix's era, and any other currency the
  server says you have some of. Phoenix's era is Treasures of Aht Urhgan. Its currencies are conquest
  points, Beastmen's and Kindred's Seals, Ancient Beastcoins, guild points, Ballista and Fellow Points,
  Imperial Standing, assault points, Nyzul Isle Tokens and Imperial Army ID Tags.
- Opening the list asks the server what you have. So later currencies that you have some of are added
  to it.

The server tells you how much of a currency you have only when asked. So while the inventory window
shows a chosen currency, winventory asks, as the game's own Currencies menus do:

- when the window opens;
- every minute while it stays open;
- a few seconds after you arrive in a new area.

It asks only for the menus that the chosen currencies are in. Gil needs no asking. Until the first
answer, the count shows a dash.

### Tooltip window

These are in the **Tooltips** tab.

With **Tooltip Window** on (off by default), winventory shows its details in a window of its own,
with the item's icon at the left. It shows details for whatever is under the mouse or the controller's
highlight:

- an item: its name, slot and races, stats and description, level and jobs;
- a treasure pool line: the same, and who is winning it;
- an equipment slot: the gear in it.

This takes the place of the tooltip beside the mouse and the box beside the controller highlight. It
keeps the grid clear while you use a controller. **Controller Item Info** is then greyed out, because
the window always shows everything.

Where the window goes:

- By default it is attached to the right of the inventory, its top level with the inventory's top.
  While there is treasure, it sits under the treasure pool, so it moves down as the pool fills and back
  up as it empties. Clicks go through it there.
- With the inventory hidden and the pool pinned, it goes to the right of the pool.
- Turn on **Detach From Inventory** to place it yourself: drag it, or set
  **Tooltip Position X** and **Tooltip Position Y**.
  **Lock Tooltip Window** holds it in place and lets clicks through it.
- **Grow From** is the corner that stays in place as the window changes size. For example, put it at
  the bottom right of the screen and choose Bottom Right, and it grows up and to the left.
- While the settings are open, it shows a sample, so you can see where it is with nothing selected.
- The window stays for a moment as the mouse moves from one item to the next, so it does not flicker.
