# sct

Scrolling text for your own statuses. As you gain one, `+ [icon] Name` starts at the top of a box
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

## Settings

**Box**

- **Visible**: whether the text shows.
- **Locked**: unlocked, the box's edge is drawn and it can be dragged; locked, clicks go through it.
  It starts unlocked, to be placed.
- **Position**: where the box's top left corner is.
- **Show Box**: draws the theme's window behind the lines while any are moving.
- **Box Width**, **Box Height**: the box's size in pixels.
- **Scroll Speed**: how fast a line moves down the box, in pixels a second (90 to start).
- **Line Spacing**: the gap between one line and the next when they come together, in pixels.
- **Align**: lines to the box's left, centre or right.

**Lines**

- **Show Gained**, **Show Lost**: which changes scroll.
- **Buff Color**, **Enfeeble Color**, **Lost Color**: the colour of each kind of line.
- **Icon Size**: how tall the icon is.
- **Font**, **Font Size**: the lines' font; Theme Font and 0 (Theme Size) follow Winxi Theme.
- **Outline**: the dark edge round the text, 0 to 3 pixels.

Lines that come at once wait for the one before to move its height and the Line Spacing down, so
they never overlap. A Scroll Time set before Scroll Speed is brought over as the speed that took as long.
