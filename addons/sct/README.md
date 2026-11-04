# sct

Scrolling text on your screen when your statuses change, and when you receive items or key items.
When you gain a status, `+ [icon] Name` appears at the top of a box and moves down. It fades out just
before it reaches the bottom. When you lose a status, `- [icon] Name` does the same.

## Why use it

- You see at a glance each buff and enfeeble you gain or lose, with its icon.
- Items and key items you receive scroll past too, so you do not miss a drop.
- Buffs, enfeebles and lost statuses each have their own colour, which you can change.

## Commands

- `/sct` shows or hides the text.
- `/sct config` opens or closes the settings.
- `/sct test` sends a buff gained, an enfeeble gained and a buff lost down the box.
- `/sct testdrop` sends a sample item drop (two fire crystals).

## How the lines look

- A buff gained is blue, an enfeeble gained is purple, and anything lost is grey. You can change each
  colour.
- The icons come from winxi. If **Custom Icons** (in Winxi Theme) is on and the chosen set has an icon
  for the status, that icon is used. If not, the game's own icon is used (read from the game's files,
  including ones changed by Pivot, a tool that adds replacement game files).
- The game does not say which statuses are enfeebles. So sct uses a list in `enfeebles.lua` (the one
  from Windower, as simplelog has it).
- Statuses you already have when the addon loads, or when you enter an area, are not shown as gained.

## Settings

Type `/sct config` to open the settings.

### Window

- **Visible**: whether the text shows.
- **Lock Window**: when unlocked, you can drag the box. Its edge is drawn if Box Style is Text Only
  and Show Outline is on. When locked, clicks go through it to the game. It starts unlocked, so you can
  place it.
- **Position**: where the box's top left corner is.
- **Box Style**:
  - **Text Only** (the default): only the scrolling lines. No background, border or shadow.
  - **Full Background**: draws the theme's window behind the lines while any are moving.

  An older **Show Box** setting is brought over: on becomes Full Background, off becomes Text Only.
- **Show Outline** (Text Only only): draws the box's edge while it is unlocked, never while locked. If
  it is off, you can still drag the unlocked box, but you cannot see it.
- **Box Width**, **Box Height**: the box's size in pixels.
- **Scroll Speed**: how fast a line moves down the box, in pixels a second (90 to start).
- **Line Spacing**: the gap in pixels between one line and the next when they come together.
- **Align**: puts the lines at the box's left, centre or right.

### Received Items

- **Show Received Items** (on by default): shows new items added to your main **Inventory**, with
  their names and quantities.
  - New key items show too, with **Key Item:** before the name.
  - Items that only go into the treasure pool do not show.
  - Items you get outside combat count too.
- A received item shows as `+ [item picture] Name`. The picture is the item's picture from your
  inventory. It uses the same **Icon Size** as status icons, and scrolls and fades the same way. If
  there is no picture, the name still shows. Key items show as text only, because they have no
  inventory picture.
- Changes to your wardrobes, storage, sack, satchel and other bags outside Inventory never show.
  sct reads those bags only to ignore items you move from them into Inventory. Such a move is
  ignored, even when the two bags are updated at slightly different times.
- The items and key items you already have when the addon loads, or when you change zone, are not
  shown as new. The first two seconds after loading or changing zone stay quiet. If your bags take
  longer to load, that is not shown as new either.
- **Separate Popup** (off by default): when off, items scroll in the same box as statuses. When on,
  items and key items use a scrolling box of their own.
- **Lock Drops** and **Drop Position** (with Separate Popup on): unlock to drag the item box, or type
  its position. It starts unlocked, so you can place it. Lock it to let clicks through, and to hide it
  when it is empty. Both boxes follow `/sct` (shown or hidden), and they share box size, style,
  speed, spacing and font.
- **Drop Color**: the colour of the item text (gold by default).
- **Test Drop**: shows a sample drop in the chosen box, as `/sct testdrop` does. Changing Separate
  Popup changes only new drops. Lines already moving finish in the box they started in.

### Lines

- **Show Gained**, **Show Lost**: which changes scroll.
- **Buff Color**, **Enfeeble Color**, **Lost Color**: the colour of each kind of line.
- **Icon Size**: how tall the icon is.
- **Font**, **Font Size**: the font of the lines. Theme Font and 0 (Theme Size) use the font and size
  set in Winxi Theme.
- **Test Lines**: sends sample lines down the box, as `/sct test` does.
- The dark edge round the text is Winxi Theme's **Text Outline**. You set it in wxi, for every addon.

Lines that come at the same time wait until the line before has moved down by its own height plus the
Line Spacing. So lines never overlap.

An older **Scroll Time** setting (from before Scroll Speed existed) is brought over as the speed that
takes the same time.
