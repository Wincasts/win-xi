# winbuff

Shows the statuses you are under (your buffs and debuffs) in a bar, with FFXIV-style icons and the time
each one has left. It takes the place of the game's own row of status icons, which it turns off.

## Why use it

- You see how long each of your buffs and debuffs has left, under its icon.
- You choose the icon size, how many icons fit in a row, and where the bar sits.
- You can see which buffs you cast yourself, and which of your debuffs Erase, a -na spell or a
  waltz can remove.

It needs only the `winxi` library (`addons/libs/winxi`). The optional `uihook` plugin makes it behave
even more like the game's own icons (see [With the uihook plugin](#with-the-uihook-plugin)).

## Renamed from buff

Up to 1.1 this addon was called buff.

- Unload buff, load `winbuff` in its place, and remove the old `addons\buff` folder.
- Change `load buff` to `load winbuff` in any startup script.
- Never run both. They change the same parts of the game's icon drawing.
- Each character's settings are brought over from `config/addons/buff/` the first time it logs in.

Before that it was called buffs. Settings kept under `config/addons/buffs/` are not brought over.
Copy them to `config/addons/winbuff/` before you first load winbuff, without overwriting any settings
already there.

## Commands

- `/winbuff` opens or closes the settings. **Visible**, in the Window section, shows or hides the
  bar. The bar only appears while you have a status.
- `/winbuff help` lists the commands.
- `/buff` still works the same as `/winbuff`.

Unload the `statustimers` addon first. Both addons turn the game's own icons off, and the second one
to try says it could not.

## Using the bar

- Rest the mouse on an icon to see the status's name, number and description.
- Right-click an icon to remove that status, where the game allows it.
- In the game's buff selector (the game's menu for removing a status), any click on an icon removes
  it.

## Where the bar goes

### Anchor To Default Location

**Anchor To Default Location** is on by default. It puts the bar where the game's own status icons
are, and keeps it fixed there. This README calls that "anchored". An anchored bar is locked,
see-through and has no border.

- With the `uihook` plugin (or the older `buffhook`), the game tells winbuff where its icons are.
- Without a plugin, the bar goes where the game's icons normally sit: about `148, 50` in the game's
  own menu coordinates. This spot was measured from a screenshot, not read from the game. Ashita's
  `scaling` helper gives the game's menu resolution. winbuff then scales across and down separately,
  to fit your screen size. If the helper is missing, or gives sizes that do not make sense, it uses a
  scale of 1:1. The menu resolution is read when winbuff loads, so reload winbuff after you change it.

**Anchor Adjustment** moves the bar a little from that spot, in screen pixels (default `0, 0`).

- Use its X and Y sliders (Ctrl+click one to type a number), or drag the bar with the left mouse
  button.
- The bar stays anchored as you drag it. With the plugin, it stays under the game's menus.
- In the game's buff selector, a click removes a status instead of dragging.
- **Lock Window** stops the dragging.

Notes on anchoring:

- The old `anchorOffset` setting is no longer used, so its old `(6, 6)` default does not move the
  bar.
- Icon size, timers and rows still use the normal settings.
- Anchoring places the whole bar, not each icon.
- The theme's padding, backgrounds, borders and shadows do not move or decorate the anchored bar.

### A window you drag

Turn **Anchor To Default Location** off to use a window you can drag instead.

- Its **Position** (X and Y sliders, or drag the window) is saved separately. So moving the anchored
  bar does not change where you put the free window.
- **Lock Window** holds it in place.
- **Show Backdrop** (on by default) gives the window the theme's background, border and shadow. When
  it is off, the icons and times sit straight over the game. The anchored bar never has a backdrop.

### Grow From

**Grow From** says where the icons in a row sit as statuses come and go: **Left** (as the game does),
**Right** or **Middle**.

- When anchored, the bar is a full row of **Icons Per Row** wide, from where it is placed. Each row
  sits at its left, its right or its middle.
- The mouse finds the icons where they are drawn.
- The window you drag keeps its top left, top right or top middle in place.

### When the bar hides

- The anchored bar disappears at once while the game's interface is hidden, while changing zone, and
  during events (cutscenes).
- The addon's own hiding rules also apply, anchored or not. You can change them. By default they
  include the opened-out chat log and the map.
- Existing character settings were updated once to bring back hiding while the map is open. After
  that, your own changes to the hiding rules are kept.

## With the uihook plugin

Load the `uihook` plugin before winbuff: `/load uihook`, then `/addon load winbuff` (see
[plugins/uihook](../../plugins/uihook/README.md)). The plugin then draws the anchored bar where and
when the game draws its own status icons, in their place. So it behaves like the game's icons:

- The menus the game opens over them (the macro palettes, the main menu and others) are drawn over
  the bar. A menu that covers part of it covers just that part.
- The bar goes away whenever the game would not draw its icons.
- It is placed where the game puts its first icon, not at the measured spot. **Anchor Adjustment**
  still moves it from there.
- Resting the mouse on an icon still shows its tooltip, and a right-click still removes it, while none
  of the game's menus is open.

If the bar is dragged somewhere else and **Hide Game Default Icons** is on, the plugin keeps the
game's own row and its pointing hand out of sight, instead of changing the game's code.

Without the plugin, or if the plugin did not recognise your game version, the anchored bar is a window
drawn over everything, at the measured spot. The settings say why. A bar you drag is always a window.

### The buff selector

The game's buff selector puts a cursor (a pointing hand) on the status icons, so you can remove one.
The game points the hand at where its own icons would be. Once winbuff's icons have their own size,
that is not where they are.

- With the plugin, the game's hand is hidden. winbuff draws it again at the left of the status the
  game's cursor is on, pointing at it, as the game's menus do. It is the game's own moving hand, read
  from its files, whether the bar is anchored or dragged.
- **Cursor Size** is how tall the hand is, compared with an icon (60% to start).
- If the hand cannot be read, the status gets winxi's highlight instead (the controller highlight: a
  line and a fainter glow outside it).
- The selector is still the game's: its keys and the controller move the cursor.
- The controller's confirm button removes the status the cursor is on. The press still reaches the
  game. If the game has not asked the server to remove the status a quarter of a second later,
  winbuff asks.
- A click on an icon removes that one too.
- Without the plugin there is no hand, but a click still removes a status.

Controller settings, in the **Controller** section:

- **Controller Navigation** is on to start.
- An XInput controller's A button is always heard.
- **Controller Type** (Automatic to start) follows the game's own controller setting (XInput or
  DirectInput), as the Phoenix launcher sets it. With Automatic, a DirectInput controller is taken to
  be a PlayStation one. You can also pick your DirectInput controller's make yourself.

## Settings

The settings window has five sections: **Window**, **Icons**, **Durations**, **Removable Marks** and
**Controller**.

### Window

- **Visible**: shows or hides the bar.
- **Anchor To Default Location**, **Anchor Adjustment** or **Position**, **Lock Window** and **Show
  Backdrop**: see [Where the bar goes](#where-the-bar-goes).
- **Hide Game Default Icons**: stops the game drawing its own row of icons. The row comes back when
  you turn this off or unload the addon. When the bar is anchored with the plugin, it takes the row's
  place whatever this says.

### Icons

- **Icon Size**: an icon's height in pixels. The icons are made 64 pixels tall, so 64 and 32 are the
  sharpest.
- **Cursor Size**: see [The buff selector](#the-buff-selector).
- **Icons Per Row**: how many icons before a new row starts.
- **Grow From**: see [Grow From](#grow-from).
- **Custom Icons** is in the Winxi Theme settings, not here. It follows winxi's choice of icon set
  (FFXIV to start, or any folder of icons added to `libs/winxi/statusicons`), or **None** for the
  game's own icons. With a set chosen, a status that the set has no icon for still uses the game's
  icon. The old **FFXIV Icons** setting of this addon is no longer used.

### Durations

- **Show Durations**: shows the time under each icon: seconds, then minutes (`m`), then hours (`h`).
- **Your Colour**: the colour of the time under a status you cast on yourself (green to start).
  - If someone else casts the same status over yours, its time goes back to the usual colour. So you
    can see that yours was replaced.
  - Only a cast that winbuff saw land counts. A status already on you when the addon started is not
    shown as yours.
  - It is kept when you change area.
- **Low Time Warning**: below this many seconds left, the icon fades out and in. 10 to start, 0 for no
  warning.
- **Font**: the font for the times and the status tooltips, from `C:\Windows\Fonts`. **Theme Font**
  (the default) uses the Winxi Theme font, anchored or not.
- **Font Size**: text size in pixels. `0` (**Theme Size**, the default) uses the theme's size. This does
  not change the icon size. The spacing of the times adjusts on its own.

### Removable Marks

- **Removable Marks** (off to start): a small square in a dark border, inside the corner of each of
  your debuffs that Erase, a -na spell or a waltz removes. It is drawn in **Curable Mark Colour**
  (light blue).
- **Only What You Can Remove**: marks only what a spell you have learned can take off, at your level
  now. Level sync is included.
- Your buffs are never marked: Dispel is for removing a monster's buffs.

## The icons

The icons come from winxi and are shared with the winparty addon.

- `libs/winxi/statusicons/ffxiv/<status number>.png` is the icon for an FFXI status. It is FFXIV's
  icon, 48 by 64 pixels, in the middle of a 64 by 64 square.
- A status with no file there uses the game's own icon.
- You can put any 64 by 64 PNG of that shape in its place, or make a set of your own beside it (see
  Custom icons in the [winxi README](../libs/winxi/README.md#custom-icons)).

A bard's songs, a corsair's rolls and a puppetmaster's maneuvers each share one FFXIV icon, in the
colours FFXI gives them. Statuses with exactly the same name in both games use that icon. The rest
were chosen by what the status does, and many could be improved.

## Credits

Based on ideas from the `statustimers` addon by heals, which showed how to read the times and how to
turn the game's own icons off.
