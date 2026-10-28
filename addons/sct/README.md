# sct

Scrolling text for your own statuses, items you receive and key items you gain. When you gain one,
`+ [icon] Name` starts at the top of a box and moves down it. It fades out just before it reaches the
bottom. When you lose one, `- [icon] Name` does the same.

- A buff gained is blue, an enfeeble gained is purple, and anything lost is grey. Each colour can be
  changed.
- The icons are winxi's choice. Where **Custom Icons** (Winxi Theme) is on and the chosen set has an
  icon for the status, that icon is used. Otherwise the game's own icon is used (from its DATs,
  pivoted ones included).
- Which statuses count as enfeebles comes from a list kept in `enfeebles.lua` (Windower's, as
  simplelog has it). The game does not say.
- Statuses already on you when the addon loads, or when you come into an area, are not shown as
  gained.

## Commands

- `/sct` shows or hides the text
- `/sct config` opens or closes the settings
- `/sct test` sends a buff gained, an enfeeble gained and a buff lost down the box
- `/sct testdrop` sends a sample item drop (two fire crystals)

## Settings

**Box**

- **Visible**: whether the text shows.
- **Lock Window**: unlocked, you can drag the box (its edge is drawn, with Text Only and Show Outline
  on). Locked, clicks go through it. It starts unlocked, so you can place it.
- **Position**: where the box's top left corner is.
- **Box Style**: **Text Only** (to start) is the scrolling lines and nothing else: no background,
  border or shadow. **Full Background** draws the theme's window behind the lines while any are
  moving. A Show Box setting from before is brought over: on becomes Full Background, off becomes
  Text Only.
- **Show Outline** (Text Only): draws the box's edge while it is unlocked (never while locked). Off,
  you can still drag the box while unlocked, but you cannot see it.
- **Box Width**, **Box Height**: the box's size in pixels.
- **Scroll Speed**: how fast a line moves down the box, in pixels a second (90 to start).
- **Line Spacing**: the gap between one line and the next when they come together, in pixels.
- **Align**: lines to the box's left, centre or right.

**Received Items**

- **Show Received Items**: shows new items added to your main **Inventory** (on by default), with
  their names and quantities. New key items show too, with **Key Item:** before the name. Items that
  only enter the treasure pool do not show. Items you get outside combat count too.
- A received item shows as `+ [item picture] Name`. The picture is the game's inventory picture, at
  the same **Icon Size** as buff and enfeeble icons, and it scrolls and fades the same way. If there is
  no picture, the name still shows. Key items are text only: their IDs are not regular inventory-item
  IDs.
- Changes to your wardrobe, storage, sack, satchel and other bags outside Inventory never show. Those
  bags are read only to filter out moves into Inventory, never as a source of lines. A move from one
  of your other bags into Inventory is ignored, even when the two bag updates arrive on separate
  frames.
- The items and key items you already have when the addon loads, or when you zone, are taken as a
  baseline, not as new. The first two seconds after loading or zoning stay quiet. If the containers
  take longer to sync, that is treated as a baseline too.
- **Separate Popup**: off by default, so drops scroll in the SCT box along with statuses. On, new
  items and key items use a scrolling area of their own.
- **Lock Window**, **Drop Position** (Separate Popup): unlock to drag the drop area, or type its
  position. It starts unlocked so you can place it. Lock it to let clicks through and to make it
  disappear when empty. Both areas follow `/sct` visibility, and they share box size, style, speed,
  spacing and font.
- **Drop Color**: the colour of the item text (gold by default).
- **Test Drop**: shows a sample drop in the chosen area. Changing Separate Popup affects new drops
  only; lines already moving finish in the area they started in.

**Lines**

- **Show Gained**, **Show Lost**: which changes scroll.
- **Buff Color**, **Enfeeble Color**, **Lost Color**: the colour of each kind of line.
- **Icon Size**: how tall the icon is.
- **Font**, **Font Size**: the lines' font. Theme Font and 0 (Theme Size) follow Winxi Theme.
- The dark edge round the text is Winxi Theme's Text Outline. You set it in winxisettings, for every
  addon.

Lines that come at the same time wait for the one before to move down by its height plus the Line
Spacing, so they never overlap. A Scroll Time set before Scroll Speed existed is brought over as the
speed that takes as long.
