# inventory

The bags in a window: what is in them, and what can be done with it, by mouse or controller. It was the
`inv` tool of xitools and is now an addon of its own, needing only the `winxi` library (`addons/libs/winxi`).

- `/inventory` opens or closes the settings (`/inventory config` does the same)
- `/inventory toggle` shows or hides the window
- `/inventory focus` gives the open window the controller, or takes it away again

`/inv` is the same command, shorter: `/inv`, `/inv toggle` and `/inv focus` all work.

Settings are organized into four tabs, each in collapsible sections: **General** (Window,
Controller and Visibility), **Inventory** (Grid, Tabs and Currencies), **Treasure** (Treasure Pool and Display), and
**Equipment** (Equipment Monitor, Display and Slots). The Treasure and Equipment tabs are laid out
alike: **Enable**, **Detach From Inventory**, the pin, and, detached, the position; then how it
looks. While one is not enabled the rest of its tab is hidden. Every setting's tooltip is in winxi's
themed tooltip.

**Lock**, in General → Window, prevents dragging the inventory window when enabled.
It is off by default; the **Position** fields remain usable while locked.

While the window is locked, items can be dragged with the mouse. Drop an item on another item of the
tab to swap their places (your own order, as the controller's Manual sort makes it; Auto sort puts
the usual order back). Drop it on another tab's name at the top to move it into that tab's bags: the
bag chosen along the foot of the window if it has room, or else the first that has room and can take
it (wardrobes take only gear; the house's bags cannot be moved to from afar). Unlocked, a drag moves
the window, as before.

Under **Inventory → Grid** in the settings, **Rows** and **Columns** set the inventory grid's visible size
(5–30 rows and 6–30 columns). While settings are open, empty placeholders preview the full selected grid; changes to
rows and columns update that preview immediately. With settings closed, the grid collapses to fit the
bag content (including empty bag slots when Show Empty Slots is enabled), up to the selected row
limit. Increasing or decreasing either dimension resizes the window to fit. Extra items scroll, with
the mouse wheel, only when they exceed the chosen row limit. A slim bar just outside the grid's right
edge shows how far down it is scrolled; it takes no room from the slots, so the spacing and the
window's width stay the same whether the grid scrolls or not. The bar can be dragged anywhere in the
strip between the grid's right edge and the window's border: a press on the bar takes hold of it, and
a press elsewhere in the strip brings it to the mouse first. A press there never moves the window. The window is as wide as the grid: the
tabs above it and the gil, counts and bag tabs below it line up with the slots' edges. Tabs and slot counts remain visible. Every slot, full or
empty, sits on a faint square of its own, under the item's icon; around them the grid has no separate
background, so the base Winxi window shows through. These controls replace Max Height. **Show Bag/Satchel/Wardrobe/House Tab** toggles each group on or off;
controller tab navigation skips hidden groups. Hiding a tab does not change its items or prevent
moving items to those bags. The controls apply to both unified and separate-bag views.

### Currencies

The gil's place at the foot of the window can show gil or any currency, and a second after it with a
comma between: `12,345 G, 4,500 IS`. Choose them under **Inventory → Currencies** as **Currency 1**
(gil by default) and **Currency 2** (none by default); either can be **None**. Each is shown with a
short name (G, CP, GP, IS, AP, Tokens and so on); the list names them in full.

A server does not say which currencies it has, and its answers carry every currency the game knows,
so **Currency List** picks which the two offer. **Retail** has every one. **Phoenix**, the default,
holds gil, the currencies of Phoenix's era, and any other the server says the player has some of. The
era is Phoenix's, Treasures of Aht Urhgan (its `modules/init.txt` loads
`era/sql/wotg`, which takes back Wings of the Goddess' changes): conquest points, Beastmen's and
Kindred's Seals, Ancient Beastcoins, guild points, Ballista and Fellow Points, Imperial Standing,
assault points, Nyzul Isle Tokens and Imperial Army ID Tags. Opening the list asks the server what the
player has, so later currencies the player does have some of come into it.

The server tells the player how many they have only when asked, so while the inventory window is
shown and a currency is chosen, the addon asks as the game's own Currencies menus do (0x10F for the
first menu, 0x115 for the second): as the window is shown, every minute while it stays, and a few
seconds after arriving in a new area. Only the menus a chosen currency is in are asked for; gil needs
no asking. Until the first answer the count is a dash.

In the unified view (**Unified Bags**, under Inventory → Tabs), a tab with more than one bag has a row of tabs of its
own along the foot of the window: **all**, for every bag together, then one for each bag the player
has (satchel, case and sack; the wardrobes by number; safe 1, safe 2, storage and locker). Choosing a
bag shows its items alone, with its own count in the row above; Auto sort then sorts that bag alone.
On **all** the row has one count, of every bag together (35/35, say); each bag's own is on its tab.
A tab with one bag, such as the inventory's, has no row. These tabs are worked with the mouse.

With the mouse, right-click an item for what can be done with it. With a controller (Controller
Navigation, in the settings): the d-pad moves the highlight, LB / RB change tab, A opens the item's menu,
B backs out of a menu or gives the controller back to the game, and X (square) opens the sort menu. The
window takes the controller as `/inv toggle` opens it, and only `/inv toggle` closes it.

While there is treasure, the treasure pool sits to the right of the window: a line for each item with
the best lot so far, the time left, and buttons to lot and pass, with Lot All and Pass All over them.
Hover over an item for who is winning it. It comes and goes with the inventory window; Detach From
Inventory, under Treasure Pool in the settings, makes it a window of its own that can be moved, with
its own **Position** and **Lock**. Show When Empty fills an empty pool with sample treasure, to see how
it looks; its buttons do nothing. It is worked with the mouse only, where the `treas` addon can be
worked with a controller.

## Equipment monitor

Turn on **Enable** in `/inv` → **Equipment** for a live equipment window, similar to EquipMon. It
is disabled by default and does not require the reference addon or its assets; while it is off, the
rest of its settings are hidden.

By default the monitor is attached to the inventory, as the treasure pool is: it sits under the
inventory window, its left edge in line with the window's, and comes and goes (and fades) with it
unless pinned (see Pinning below).
The controller's verbose item box, when placed below the window, goes under the monitor instead.
Turn on **Detach From Inventory** to make it a window of its own, with its own **Position** and
**Lock**.

### Pinning

`/inv toggle` shows and hides the inventory window, the treasure pool and the equipment monitor
together, attached or detached. Each has a pin that keeps it on screen when they are toggled off:
**Pin Inventory** (General → Window), **Pin Treasure Pool** (Treasure) and **Pin Equipment**
(Equipment). A pinned inventory window toggled off stays, but gives the controller back to the game.
With the inventory hidden, pinned windows that are attached to it move up into its place: the
equipment monitor to the inventory's top-left corner, and the treasure pool beside the monitor, or
to that corner itself when the monitor is not there. Once the inventory is shown again they go back
under and beside it. Pinned windows still follow General's shared Visibility rules (including
hiding while logged out).

All 16 slots use the game's equipment-screen arrangement:

| | | | |
|---|---|---|---|
| Main | Sub | Range | Ammo |
| Head | Neck | Left Ear | Right Ear |
| Body | Hands | Left Ring | Right Ring |
| Back | Waist | Legs | Feet |

Equipped items are resolved from their actual containers, including wardrobes, and update live.
Hover a slot for its name and equipped item. Stackable ammunition shows its current count; red
crosses mark encumbered slots, even when empty. Both overlays can be switched off independently.

**Quality Borders** draws a white inset border around high-quality gear, as the game does; other
gear has no border. The game's item data has no HQ flag (an item's HQ is a separate item named with
+1, +2 or +3), so an item counts as high quality when its name ends that way.
**Wardrobe Markers** marks gear kept in a wardrobe as the game's equipment menu does: the
wardrobe's number, white with a dark edge, in the top-right corner, over a wash of the wardrobe's
colour along the top and right edges. Wardrobes 1–3 use the game's blue, yellow and green; 4–8 use
red, purple, teal, orange and pink. Main-inventory items have no mark. Both controls are under **Equipment → Slots**, enabled
by default, and independent of Slot Backgrounds and each other. Hovering an equipped item shows
its storage location even when wardrobe markers are disabled.

**Slot Backgrounds** draws each slot as the game's equipment menu does: a flat lavender-grey tile
sunk into the window, its top and left edges in shadow and its right and bottom edges lit, meeting
on the diagonal inside a thin dark rim, with the slot's name in pale lettering at its centre. Empty
slots retain their labels; occupied slots draw their icons on top. The backdrop and lettering scale
with the icons, remain inside the square grid, and turn off together with Slot Backgrounds.

The Equipment tab provides its own **Scale**, **Spacing**, **Opacity**, **Window Background**, and
**Slot Backgrounds** controls, and, detached, **Position** and **Lock**. Drag the
unlocked, detached window to move it; attached, it moves with the inventory window. Settings are kept per character with the rest of Inventory's settings. Styling and count
text use Winxi's theme rather than EquipMon's numbered texture themes and separate font objects;
item icons share Inventory's icon atlas.

### Combat update performance

The visible equipment monitor reads all 16 equipped indices and their current container items on
**every rendered frame**, before Inventory's bag scans or sorting. It does not wait for the bag
packet debounce, and rereads item IDs/counts even when an equipped index has not changed. A gear or
ammo change is reflected on the next draw after the client updates its memory; swaps that occur
entirely between rendered frames cannot each be displayed.

Detached, equipment gets first access to the atlas's 48-new-icons-per-frame upload budget, enough
for a full 16-slot replacement before bag icons consume the remainder. Attached, it is drawn after
the inventory window, whose position it needs that frame, so the bag icons come first; it still reads
the equipped items every frame. Cached icons are reused immediately;
pending atlas uploads are requested again on subsequent frames, and missing icons never fall back
to displaying the previous item's icon.
All equipment icons are drawn together in one atlas batch, with decorations afterward. Stable
resource metadata, label/badge measurements and opacity-dependent colors are cached, while live
equipment is never throttled. Font/scale/opacity changes invalidate the relevant presentation caches.
Hidden or disabled equipment windows do not poll equipment memory.

`tests/inventory_equipment_performance_check.lua` exercises consecutive full-set swaps, item/count
changes at unchanged indices, icon-budget contention, batching and cache invalidation. Its printed
CPU/allocation sample includes mocked ImGui/Ashita overhead and is **not an in-game GPU/frame-time
measurement**.

The addon was called `inv`; the first time it is loaded for a character it brings over the settings it
kept under that name. If there are none, it brings over what xitools kept for the tool: its settings,
the window's place, the order items were put in by hand, and xitools' theme and hiding rules.
