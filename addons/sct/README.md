# sct

Scrolling text for your own statuses, items you receive and key items you gain. As you gain one, `+ [icon] Name` starts at the top of a box
and moves down it, fading out just before it reaches the bottom; as you lose one, `- [icon] Name`
does the same.

- A buff gained is blue, an enfeeble gained purple, anything lost grey (each can be changed).
- The icons are winxi's choice: the set chosen under **Custom Icons** (Winxi Theme) where it is on
  and the set has an icon for the status, the game's own (from its DATs, pivoted ones included)
  otherwise.
- Which statuses count as enfeebles is a list kept in `enfeebles.lua` (Windower's, as simplelog
  has it): the game does not say.
- Statuses already on as the addon loads, or as you come into an area, are not shown as gained.

## Commands

- `/sct` shows or hides the text
- `/sct config` opens or closes the settings
- `/sct test` sends a buff gained, an enfeeble gained and a buff lost down the box
- `/sct testdrop` sends a sample item drop (two fire crystals)

## Settings

**Box**

- **Visible**: whether the text shows.
- **Lock Window**: unlocked, the box can be dragged (its edge drawn, with Text Only and Show Outline on); locked, clicks go through it.
  It starts unlocked, to be placed.
- **Position**: where the box's top left corner is.
- **Box Style**: **Text Only** (to start) is the scrolling lines and nothing else: no background,
  border or shadow. **Full Background** draws the theme's window behind the lines while any are
  moving. A Show Box setting from before is brought over: on as Full Background, off as Text Only.
- **Show Outline** (Text Only): draws the box's edge while it is unlocked (never while locked). Off, the box
  can still be dragged while unlocked, unseen.
- **Box Width**, **Box Height**: the box's size in pixels.
- **Scroll Speed**: how fast a line moves down the box, in pixels a second (90 to start).
- **Line Spacing**: the gap between one line and the next when they come together, in pixels.
- **Align**: lines to the box's left, centre or right.

**Received Items**

- **Show Received Items**: shows newly received items added to your main **Inventory** (on by default), with their names
  and quantities, plus new key items prefixed with **Key Item:**. Items merely entering the treasure
  pool do not trigger notifications. This also covers items acquired outside combat.
- Received items display `+ [item picture] Name`, using the game's inventory picture at the same
  **Icon Size** as buff/enfeeble icons, with the same scrolling and fade. If a picture is unavailable,
  the name still displays. Key items remain text-only; their IDs are not regular inventory-item IDs.
- Wardrobe, storage, sack, satchel and other non-Inventory bag updates never trigger notifications.
  Other bags are read only to filter out transfers into Inventory, not as notification sources.
  Moves from your other bags into Inventory are ignored, including when the two bag updates arrive
  on separate frames.
- Existing inventory and key items at addon startup or when zoning are treated as a baseline, not
  new acquisitions. The first two seconds after loading or zoning settle silently, and container
  synchronization is also treated as a baseline if it takes longer.
- **Separate Popup**: off by default, so drops scroll in the current SCT box alongside statuses.
  On, newly received items and key items use their own independent scrolling area instead.
- **Lock Window**, **Drop Position** (Separate Popup): unlock to drag the drop area, or enter its
  position. It starts unlocked for placement; lock it to let clicks through and make it disappear
  when empty. Both areas follow `/sct` visibility and share box size, style, speed, spacing and font.
- **Drop Color**: the item text's color (gold by default).
- **Test Drop**: previews a sample drop in the selected area. Changing Separate Popup affects new
  drops; lines already moving finish in their original area.

**Lines**

- **Show Gained**, **Show Lost**: which changes scroll.
- **Buff Color**, **Enfeeble Color**, **Lost Color**: the colour of each kind of line.
- **Icon Size**: how tall the icon is.
- **Font**, **Font Size**: the lines' font; Theme Font and 0 (Theme Size) follow Winxi Theme.
- The dark edge round the text is Winxi Theme's Text Outline, set in winxisettings for every addon.

Lines that come at once wait for the one before to move its height and the Line Spacing down, so
they never overlap. A Scroll Time set before Scroll Speed is brought over as the speed that took as long.
