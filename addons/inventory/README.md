# inventory

The bags in a window: what is in them, and what can be done with it, by mouse or controller. It was the
`inv` tool of xitools and is now an addon of its own, needing only the `winxi` library (`addons/libs/winxi`).

- `/inventory` opens or closes the settings (`/inventory config` does the same)
- `/inventory toggle` shows or hides the window
- `/inventory focus` gives the open window the controller, or takes it away again

`/inv` is the same command, shorter: `/inv`, `/inv toggle` and `/inv focus` all work.

Settings are organized into four tabs: **General** (movement lock, Window, Controller and
Visibility), **Bags** (grid size and bag display), **Treasure** (treasure pool controls), and
**Equipment** (the live equipment monitor).

**Lock Drag to Move**, at the top of General, prevents dragging the inventory window when enabled.
It is off by default; the **Position** fields remain usable while locked.

Under **Bags** in the settings, **Rows** and **Columns** set the inventory grid's visible size
(5–30 rows and 6–30 columns). While settings are open, empty placeholders preview the full selected grid; changes to
rows and columns update that preview immediately. With settings closed, the grid collapses to fit the
bag content (including empty bag slots when Show Empty Slots is enabled), up to the selected row
limit. Increasing or decreasing either dimension resizes the window to fit. Extra items scroll only
when they exceed the chosen row limit; otherwise no scrollbar is shown. A scrollbar fits inside the
same window width by slightly tightening horizontal slot spacing; icon size and column count stay
unchanged, and normal spacing returns when scrolling is no longer needed. Tabs and slot counts remain visible. The grid has no separate
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

## Equipment monitor

Enable **Show Equipment** in `/inv` → **Equipment** for a live, independent equipment window,
similar to EquipMon. It is disabled by default and does not require the reference addon or its assets.
The monitor stays visible when the inventory window is toggled off, but follows General's shared
Visibility rules (including hiding while logged out).

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

**Quality Borders** adds an inset item border: normal grey, Rare blue, Exclusive green, and
Rare/Exclusive gold, based on the item's resource flags (not an inferred HQ status from its name).
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

The Equipment tab provides its own **Position**, **Lock Drag to Move**, **Scale**, **Spacing**,
**Opacity**, **Window Background**, and **Slot Backgrounds** controls. Drag the unlocked window to
move it. Settings are kept per character with the rest of Inventory's settings. Styling and count
text use Winxi's theme rather than EquipMon's numbered texture themes and separate font objects;
item icons share Inventory's icon atlas.

### Combat update performance

The visible equipment monitor reads all 16 equipped indices and their current container items on
**every rendered frame**, before Inventory's bag scans or sorting. It does not wait for the bag
packet debounce, and rereads item IDs/counts even when an equipped index has not changed. A gear or
ammo change is reflected on the next draw after the client updates its memory; swaps that occur
entirely between rendered frames cannot each be displayed.

Equipment gets first access to the atlas's 48-new-icons-per-frame upload budget, enough for a full
16-slot replacement before bag icons consume the remainder. Cached icons are reused immediately;
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
